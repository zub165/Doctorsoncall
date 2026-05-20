import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:dio/dio.dart';

import '../config/api_paths.dart';
import '../models/medical_record.dart';
import '../utils/api_envelope.dart';
import 'emergency_api_client.dart';
import 'offline_db.dart';

class MedicalRecordsApi {
  MedicalRecordsApi(this._c);

  final EmergencyApiClient _c;

  static List<Map<String, dynamic>> _unwrapRecordRows(dynamic data) {
    final rows = <Map<String, dynamic>>[];
    if (data is List) {
      for (final e in data) {
        if (e is Map) rows.add(Map<String, dynamic>.from(e));
      }
    } else if (data is Map<String, dynamic>) {
      final inner = ApiEnvelope.dataMap(data);
      final list = inner?['results'] ?? inner?['records'] ?? data['results'];
      if (list is List) {
        for (final e in list) {
          if (e is Map) rows.add(Map<String, dynamic>.from(e));
        }
      }
    } else if (data is Map) {
      final inner = ApiEnvelope.dataMap(Map<String, dynamic>.from(data));
      final list = inner?['results'] ?? inner?['records'];
      if (list is List) {
        for (final e in list) {
          if (e is Map) rows.add(Map<String, dynamic>.from(e));
        }
      }
    }
    return rows;
  }

  /// Parses Django `MedicalRecord` rows (`title`, `raw_payload`, `ai_summary`, …).
  static MedicalRecord fromServerRow(Map<String, dynamic> json) {
    final m = Map<String, dynamic>.from(json);
    final rp = m['raw_payload']?.toString() ?? '';
    if (rp.trim().startsWith('{')) {
      try {
        final inner = jsonDecode(rp);
        if (inner is Map) {
          final merged = Map<String, dynamic>.from(inner);
          merged['id'] ??= m['id'];
          if ((m['ai_summary'] ?? '').toString().isNotEmpty) {
            merged['ai_summary'] = m['ai_summary'];
            merged['ai_highlight'] ??= m['ai_summary'];
            merged['notes'] ??= m['ai_summary'];
          }
          if ((m['title'] ?? '').toString().isNotEmpty) {
            merged['title'] ??= m['title'];
            merged['hospitalName'] ??= m['title'];
          }
          merged['created_at'] ??= m['created_at'];
          return MedicalRecord.fromJson(merged);
        }
      } catch (_) {
        // fall through
      }
    }
    final merged = Map<String, dynamic>.from(m);
    final ai = (m['ai_summary'] ?? '').toString();
    if (ai.isNotEmpty) {
      merged['ai_highlight'] = ai;
      merged['notes'] = ai;
    }
    merged['hospitalName'] = (m['title'] ?? 'Medical record').toString();
    merged['created_at'] ??= m['created_at'];
    return MedicalRecord.fromJson(merged);
  }

  Future<List<MedicalRecord>> listRecords() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.medicalRecords);
    return _unwrapRecordRows(r.data)
        .map(fromServerRow)
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  /// Server charts for one patient (`GET …/medical-records/?patient_id=`).
  Future<List<MedicalRecord>> listRecordsForPatient(int patientId) async {
    final r = await _c.raw.get<dynamic>(
      ApiPaths.medicalRecords,
      queryParameters: {'patient_id': patientId},
    );
    return _unwrapRecordRows(r.data)
        .map(fromServerRow)
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  /// Provider inbox shares; optional [patientId] filter on client.
  Future<List<Map<String, dynamic>>> listSharesInbox({int? patientId}) async {
    final r = await _c.raw.get<dynamic>(ApiPaths.sharesInbox);
    final rows = _unwrapRecordRows(r.data);
    if (patientId == null) return rows;
    return rows.where((s) {
      final p = s['patient'];
      if (p is Map) {
        final id = p['id'];
        if (id is int) return id == patientId;
        return int.tryParse(id.toString()) == patientId;
      }
      return int.tryParse('${s['patient_id'] ?? ''}') == patientId;
    }).toList();
  }

  static bool isServerNumericId(String id) => int.tryParse(id) != null;

  Future<MedicalRecord?> getRecord(String id) async {
    final r = await _c.raw.get<dynamic>(ApiPaths.medicalRecordDetail(id));
    final data = r.data;
    if (data == null) return null;
    if (data is Map<String, dynamic>) {
      return MedicalRecord.fromJson(data);
    }
    if (data is Map) {
      return MedicalRecord.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// AI assistant over records — `{ "query": "...", "record_ids": [] }`
  Future<Map<String, dynamic>> aiAssist({
    required String query,
    List<String>? recordIds,
    String? kind,
  }) async {
    final payload = <String, dynamic>{'query': query};
    if (recordIds != null && recordIds.isNotEmpty) {
      payload['record_ids'] = recordIds;
    }
    final k = kind?.trim();
    if (k != null && k.isNotEmpty) {
      payload['kind'] = k;
    }
    final res = await _c.raw.post<Map<String, dynamic>>(
      ApiPaths.medicalRecordsAiAssist,
      data: payload,
    );
    final body = res.data;
    if (body == null) return {};
    if (ApiEnvelope.isSuccess(body)) {
      final d = ApiEnvelope.dataMap(body);
      if (d != null) return d;
    }
    return Map<String, dynamic>.from(body);
  }

  /// Save on this device only — **no server upload** (HIPAA-friendly default).
  Future<void> saveOfflineLocalOnly({
    required OfflineDb db,
    required MedicalRecord record,
  }) async {
    final now = DateTime.now();
    final payload = Map<String, dynamic>.from(record.toJson())
      ..['local_only'] = true
      ..['hipaa_device_only'] = true;
    await db.into(db.localMedicalRecords).insertOnConflictUpdate(
          LocalMedicalRecordsCompanion(
            id: Value(record.id),
            json: Value(jsonEncode(payload)),
            updatedAt: Value(now),
            isDeleted: const Value(false),
          ),
        );
    await db.cancelOutboxForRecordId(record.id);
  }

  /// Save a medical record offline (SQLite) and enqueue an outbox sync event.
  ///
  /// This uses the **Doctor On Call JSON format** defined in `MedicalRecord.toJson()`.
  Future<void> saveOffline({
    required OfflineDb db,
    required MedicalRecord record,
    bool uploadToServer = true,
  }) async {
    final now = DateTime.now();
    final jsonStr = record.toJson();
    if (!uploadToServer) {
      await saveOfflineLocalOnly(db: db, record: record);
      return;
    }
    await db.into(db.localMedicalRecords).insertOnConflictUpdate(
          LocalMedicalRecordsCompanion(
            id: Value(record.id),
            json: Value(jsonEncode(jsonStr)),
            updatedAt: Value(now),
            isDeleted: Value(record.deleted),
          ),
        );

    await db.enqueueOutbox(
      entity: 'medical-records',
      operation: record.deleted ? 'delete' : 'upsert',
      payload: jsonStr,
    );
  }

  /// Server row id when [record] was uploaded or linked (may differ from local `local-…` id).
  static int? serverRecordPk(MedicalRecord? record) {
    if (record == null) return null;
    if (isServerNumericId(record.id)) return int.tryParse(record.id);
    final raw = record.raw['server_medical_record_id'] ??
        record.raw['linked_server_record_id'];
    return int.tryParse(raw?.toString() ?? '');
  }

  static bool hasServerCopy(MedicalRecord? record) => serverRecordPk(record) != null;

  static int? linkedAppointmentPk(MedicalRecord? record) {
    if (record == null) return null;
    return int.tryParse((record.raw['linked_appointment_id'] ?? '').toString());
  }

  /// Remove from this phone; optionally DELETE on server when a server copy exists.
  Future<void> purgeRecord({
    required OfflineDb db,
    required String recordId,
    bool deleteFromServer = false,
    int? serverRecordId,
  }) async {
    await db.cancelOutboxForRecordId(recordId);
    await (db.delete(db.localMedicalRecords)..where((t) => t.id.equals(recordId))).go();
    final serverPk =
        serverRecordId ?? (isServerNumericId(recordId) ? int.tryParse(recordId) : null);
    if (deleteFromServer && serverPk != null) {
      try {
        await _c.raw.delete<dynamic>(ApiPaths.medicalRecordDetail('$serverPk'));
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
    }
  }

  /// Wipe all local medical rows (visit end / patient reset on device).
  Future<void> purgeAllLocalRecords(OfflineDb db) async {
    final rows = await db.select(db.localMedicalRecords).get();
    for (final row in rows) {
      await db.cancelOutboxForRecordId(row.id);
    }
    await db.delete(db.localMedicalRecords).go();
  }

  // --- Documents (upload → process → report) ---

  Future<List<Map<String, dynamic>>> listDocuments() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.documents);
    final data = r.data;
    if (data is Map<String, dynamic>) {
      final inner = ApiEnvelope.dataMap(data);
      final list = inner?['results'] ?? data['results'] ?? inner?['documents'];
      if (list is List) {
        return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> uploadDocument({
    required String filePath,
    String? filename,
    int? patientId,
  }) async {
    final form = FormData.fromMap({
      if (patientId != null) 'patient_id': patientId,
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    final r = await _c.raw.post<dynamic>(
      ApiPaths.documents,
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<Map<String, dynamic>> processDocument(int id) async {
    final r = await _c.raw.post<dynamic>(ApiPaths.documentDetail(id));
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  // --- OCR (direct) ---

  Future<Map<String, dynamic>> ocrImage({
    required String filePath,
    String? filename,
    String lang = 'eng',
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
      if (lang.trim().isNotEmpty) 'lang': lang.trim(),
    });
    final r = await _c.raw.post<dynamic>(
      ApiPaths.ocrImage,
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<Map<String, dynamic>> ocrPdf({
    required String filePath,
    String? filename,
    String lang = 'eng',
    int dpi = 200,
  }) async {
    final safeDpi = dpi.clamp(72, 400);
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
      if (lang.trim().isNotEmpty) 'lang': lang.trim(),
      'dpi': safeDpi,
    });
    final r = await _c.raw.post<dynamic>(
      ApiPaths.ocrPdf,
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  // --- Consent share (patient → doctor) ---

  Future<List<Map<String, dynamic>>> myShares() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.sharesMine);
    final data = r.data;
    if (data is Map<String, dynamic>) {
      final inner = ApiEnvelope.dataMap(data);
      final list = inner?['results'] ?? data['results'];
      if (list is List) {
        return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> inboxShares() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.sharesInbox);
    final data = r.data;
    if (data is Map<String, dynamic>) {
      final inner = ApiEnvelope.dataMap(data);
      final list = inner?['results'] ?? data['results'];
      if (list is List) {
        return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    return const [];
  }

  /// Patient shares triage vitals + note → doctor inbox (+ server PatientVital).
  Future<Map<String, dynamic>> shareTriageWithDoctor({
    required int providerId,
    required Map<String, dynamic> vitals,
    String? patientNote,
    int? appointmentId,
    bool includePatientEmail = false,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.sharesTriage,
      data: {
        'provider_id': providerId,
        'vitals': vitals,
        if (patientNote != null && patientNote.trim().isNotEmpty)
          'patient_note': patientNote.trim(),
        if (appointmentId != null) 'appointment_id': appointmentId,
        'include_patient_email': includePatientEmail,
      },
    );
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<List<Map<String, dynamic>>> listVisitNotes({
    int? appointmentId,
    int? patientId,
  }) async {
    final r = await _c.raw.get<dynamic>(
      ApiPaths.visitNotes,
      queryParameters: {
        if (appointmentId != null) 'appointment_id': appointmentId,
        if (patientId != null) 'patient_id': patientId,
      },
    );
    return _unwrapRecordRows(r.data);
  }

  Future<Map<String, dynamic>> sendVisitNoteToPatient({
    required int patientId,
    required String subjective,
    required String objective,
    required String assessment,
    required String plan,
    int? appointmentId,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.visitNotes,
      data: {
        'patient_id': patientId,
        'subjective': subjective,
        'objective': objective,
        'assessment': assessment,
        'plan': plan,
        if (appointmentId != null) 'appointment_id': appointmentId,
      },
    );
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<Map<String, dynamic>> createShare({
    required int providerId,
    required String note,
    required bool includePatientEmail,
    String? aiSummary,
  }) async {
    final r = await _c.raw.post<dynamic>(
      ApiPaths.sharesCreate,
      data: {
        'provider_id': providerId,
        'patient_note': note,
        'include_patient_email': includePatientEmail,
        if (aiSummary != null && aiSummary.trim().isNotEmpty) 'ai_summary': aiSummary.trim(),
      },
    );
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<void> deleteShare(int id) async {
    await _c.raw.delete<dynamic>(ApiPaths.shareDetail(id));
  }

  Future<Map<String, dynamic>> emailShare(int id) async {
    final r = await _c.raw.post<dynamic>(ApiPaths.shareEmail(id));
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }
}
