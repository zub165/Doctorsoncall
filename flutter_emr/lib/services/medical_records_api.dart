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

  Future<List<MedicalRecord>> listRecords() async {
    final r = await _c.raw.get<dynamic>(ApiPaths.medicalRecords);
    final data = r.data;
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
    }
    return rows
        .map(MedicalRecord.fromJson)
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

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
  }) async {
    final payload = <String, dynamic>{'query': query};
    if (recordIds != null && recordIds.isNotEmpty) {
      payload['record_ids'] = recordIds;
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

  /// Save a medical record offline (SQLite) and enqueue an outbox sync event.
  ///
  /// This uses the **Doctor On Call JSON format** defined in `MedicalRecord.toJson()`.
  Future<void> saveOffline({
    required OfflineDb db,
    required MedicalRecord record,
  }) async {
    final now = DateTime.now();
    final jsonStr = record.toJson();
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
