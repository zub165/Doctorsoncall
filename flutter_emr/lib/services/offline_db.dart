import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'offline_db.g.dart';

/// Canonical sync entity names (client side).
///
/// Canonical: `appointments`, `medical-records`, `medications`, `lab-results`.
String canonicalSyncEntity(String raw) {
  final dashed = raw.toLowerCase().trim().replaceAll('_', '-');
  switch (dashed) {
    case 'appointment':
    case 'appointments':
      return 'appointments';
    case 'medical-record':
    case 'medical-records':
    case 'medical_record':
    case 'medical_records':
    case 'medicalrecord':
    case 'medicalrecords':
      return 'medical-records';
    case 'medication':
    case 'medications':
      return 'medications';
    case 'lab-result':
    case 'lab-results':
    case 'lab_result':
    case 'lab_results':
    case 'labresult':
    case 'labresults':
      return 'lab-results';
    default:
      return dashed;
  }
}

class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

class OutboxEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get operation => text()(); // upsert, delete
  TextColumn get payloadJson => text()(); // JSON payload for server `data`
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get sentAt => dateTime().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

class LocalAppointments extends Table {
  TextColumn get id => text()(); // server id or client uuid
  TextColumn get json => text()(); // raw server-ish JSON
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalMedicalRecords extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalMedications extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalLabResults extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI assistant chat bubbles (single thread, chronological).
class AiAssistantMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  BoolColumn get isUser => boolean()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(
  tables: [
    SyncState,
    OutboxEvents,
    LocalAppointments,
    LocalMedicalRecords,
    LocalMedications,
    LocalLabResults,
    AiAssistantMessages,
  ],
)
class OfflineDb extends _$OfflineDb {
  OfflineDb() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(aiAssistantMessages);
          }
        },
      );

  Future<String?> getState(String keyName) async {
    final row =
        await (select(syncState)..where((t) => t.key.equals(keyName)))
            .getSingleOrNull();
    return row?.value;
  }

  Future<void> setState(String keyName, String value) async {
    await into(syncState).insertOnConflictUpdate(
      SyncStateCompanion(
        key: Value(keyName),
        value: Value(value),
      ),
    );
  }

  Future<void> enqueueOutbox({
    required String entity,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    await into(outboxEvents).insert(
      OutboxEventsCompanion.insert(
        entity: canonicalSyncEntity(entity),
        operation: operation,
        payloadJson: jsonEncode(payload),
      ),
    );
  }

  Future<List<OutboxEvent>> pendingOutbox({int limit = 50}) =>
      (select(outboxEvents)
            ..where((t) => t.sentAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(limit))
          .get();

  Future<void> appendAiAssistantMessage({
    required bool isUser,
    required String body,
  }) async {
    await into(aiAssistantMessages).insert(
      AiAssistantMessagesCompanion.insert(
        isUser: isUser,
        body: body,
      ),
    );
  }

  Future<List<AiAssistantMessage>> aiAssistantMessagesOrdered() =>
      (select(aiAssistantMessages)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  Future<void> clearAiAssistantMessages() async {
    await delete(aiAssistantMessages).go();
  }

  /// Drop pending outbox rows whose JSON payload references [recordId].
  Future<void> cancelOutboxForRecordId(String recordId) async {
    final pending = await pendingOutbox(limit: 200);
    for (final ev in pending) {
      try {
        final m = jsonDecode(ev.payloadJson);
        if (m is Map && (m['id']?.toString() == recordId)) {
          await (delete(outboxEvents)..where((t) => t.id.equals(ev.id))).go();
        }
      } catch (_) {
        // ignore malformed payload
      }
    }
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'doctor_on_call_offline');
}

