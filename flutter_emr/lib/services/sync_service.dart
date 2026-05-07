import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../config/api_paths.dart';
import 'emergency_api_client.dart';
import 'offline_db.dart';

String _canon(String entity) => canonicalSyncEntity(entity);

/// Offline-first hybrid sync (device SQLite ↔ server DB).
///
/// Server must expose:
/// - `GET  /api/doctor-on-call/sync/<entity>/?since=<cursor>`
/// - `POST /api/doctor-on-call/sync/push/` { events: [...] }
class SyncService {
  SyncService({required this.client, required this.db});

  final EmergencyApiClient client;
  final OfflineDb db;

  static const _kCursorPrefix = 'sync_cursor:'; // sync_cursor:appointments

  Future<void> syncAll() async {
    await _pushOutbox();
    await _pullEntity(_canon('appointments'));
    await _pullEntity(_canon('medical-records'));
    await _pullEntity(_canon('medications'));
    await _pullEntity(_canon('lab-results'));
  }

  Future<void> _pushOutbox() async {
    final events = await db.pendingOutbox(limit: 50);
    if (events.isEmpty) return;

    final payload = {
      'events': events
          .map(
            (e) => {
              'id': 'outbox:${e.id}',
              'entity': e.entity,
              'operation': e.operation,
              'data': jsonDecode(e.payloadJson),
              'created_at': e.createdAt.toIso8601String(),
            },
          )
          .toList(),
    };

    try {
      final res = await client.raw.post<Map<String, dynamic>>(
        ApiPaths.docOnCallSyncPush,
        data: payload,
        options: Options(contentType: Headers.jsonContentType),
      );
      // Mark sent (backend returns accepted/errors; for now treat 200 as success).
      final body = res.data ?? const <String, dynamic>{};
      final hasErrors = body['errors'] is List && (body['errors'] as List).isNotEmpty;
      if (hasErrors) {
        for (final ev in events) {
          await (db.update(db.outboxEvents)
                ..where((t) => t.id.equals(ev.id)))
              .write(
            OutboxEventsCompanion(
              attemptCount: Value(ev.attemptCount + 1),
              lastError: Value('Some events rejected by server'),
            ),
          );
        }
        return;
      }

      final now = DateTime.now();
      for (final e in events) {
        await (db.update(db.outboxEvents)
              ..where((t) => t.id.equals(e.id)))
            .write(OutboxEventsCompanion(sentAt: Value(now)));
      }
    } on DioException catch (e) {
      // keep pending; record last error for visibility
      for (final ev in events) {
        await (db.update(db.outboxEvents)
              ..where((t) => t.id.equals(ev.id)))
            .write(
          OutboxEventsCompanion(
            attemptCount: Value(ev.attemptCount + 1),
            lastError: Value(e.message ?? 'push failed'),
          ),
        );
      }
    }
  }

  Future<void> _pullEntity(String entity) async {
    final canonical = _canon(entity);
    final cursorKey = '$_kCursorPrefix$canonical';
    final since = await db.getState(cursorKey);
    final path = '${ApiPaths.docOnCallSyncPull}$canonical/';
    try {
      final res = await client.raw.get<Map<String, dynamic>>(
        path,
        queryParameters: {
          if (since != null && since.isNotEmpty) 'since': since,
        },
      );
      final body = res.data ?? <String, dynamic>{};
      // Backend shape: { results: [], next_cursor: "...", server_time: "..." }
      final data = (body['data'] is Map)
          ? Map<String, dynamic>.from(body['data'] as Map)
          : body;
      final items = (data['results'] is List)
          ? List.from(data['results'] as List)
          : const [];
      final nextCursor = data['next_cursor']?.toString() ?? data['cursor']?.toString();

      if (items.isNotEmpty) {
        await _applyServerItems(canonical, items);
      }
      if (nextCursor != null && nextCursor.isNotEmpty) {
        await db.setState(cursorKey, nextCursor);
      }
    } on DioException {
      // ignore pull failures (offline)
    }
  }

  Future<void> _applyServerItems(String entity, List items) async {
    // Store raw JSON blobs; mapping to typed models can be layered later.
    final now = DateTime.now();
    for (final it in items) {
      if (it is! Map) continue;
      final m = Map<String, dynamic>.from(it);
      final id = (m['id'] ?? m['uuid'] ?? m['pk'])?.toString();
      if (id == null || id.isEmpty) continue;

      final isDeleted = (m['is_deleted'] == true) || (m['deleted'] == true);
      final jsonStr = jsonEncode(m);

      if (entity == 'appointments') {
        await db.into(db.localAppointments).insertOnConflictUpdate(
              LocalAppointmentsCompanion(
                id: Value(id),
                json: Value(jsonStr),
                updatedAt: Value(now),
                isDeleted: Value(isDeleted),
              ),
            );
      } else if (entity == 'medical-records') {
        await db.into(db.localMedicalRecords).insertOnConflictUpdate(
              LocalMedicalRecordsCompanion(
                id: Value(id),
                json: Value(jsonStr),
                updatedAt: Value(now),
                isDeleted: Value(isDeleted),
              ),
            );
      } else if (entity == 'medications') {
        await db.into(db.localMedications).insertOnConflictUpdate(
              LocalMedicationsCompanion(
                id: Value(id),
                json: Value(jsonStr),
                updatedAt: Value(now),
                isDeleted: Value(isDeleted),
              ),
            );
      } else if (entity == 'lab-results') {
        await db.into(db.localLabResults).insertOnConflictUpdate(
              LocalLabResultsCompanion(
                id: Value(id),
                json: Value(jsonStr),
                updatedAt: Value(now),
                isDeleted: Value(isDeleted),
              ),
            );
      }
    }
  }
}

