import 'dart:convert';

import 'package:drift/drift.dart';

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
}
