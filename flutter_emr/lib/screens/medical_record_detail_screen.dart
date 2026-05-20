import 'package:flutter/material.dart';

import '../models/medical_record.dart';
import '../services/medical_records_api.dart';
import '../services/offline_db.dart';
import '../theme/app_theme.dart';

class MedicalRecordDetailScreen extends StatelessWidget {
  const MedicalRecordDetailScreen({
    super.key,
    required this.api,
    required this.recordId,
    this.preview,
    this.offlineDb,
    this.onDeleted,
  });

  final MedicalRecordsApi api;
  final String recordId;
  final MedicalRecord? preview;
  final OfflineDb? offlineDb;
  final VoidCallback? onDeleted;

  bool get _isDeviceOnly =>
      preview?.raw['local_only'] == true ||
      preview?.raw['hipaa_device_only'] == true ||
      !MedicalRecordsApi.isServerNumericId(recordId);

  Future<void> _delete(BuildContext context) async {
    final db = offlineDb;
    if (db == null) return;

    final deleteServer = MedicalRecordsApi.isServerNumericId(recordId)
        ? await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete record?'),
              content: const Text(
                'Remove from this phone. Also delete the server copy?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('This phone only'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Phone + server'),
                ),
              ],
            ),
          )
        : false;
    if (!context.mounted) return;
    if (MedicalRecordsApi.isServerNumericId(recordId) && deleteServer == null) {
      return;
    }

    try {
      await api.purgeRecord(
        db: db,
        recordId: recordId,
        deleteFromServer: deleteServer == true,
      );
      onDeleted?.call();
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record deleted')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical record'),
        actions: [
          if (offlineDb != null)
            IconButton(
              tooltip: 'Delete',
              onPressed: () => _delete(context),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: FutureBuilder<MedicalRecord?>(
        future: api.getRecord(recordId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              preview == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          final r = snap.data ?? preview;
          if (r == null) {
            return const Center(child: Text('Record not found'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_isDeviceOnly)
                Card(
                  color: Colors.teal.shade50,
                  child: const ListTile(
                    leading: Icon(Icons.phonelink_lock_outlined),
                    title: Text('Stored on this device only'),
                    subtitle: Text('Not uploaded to the server unless you chose otherwise.'),
                  ),
                ),
              Text(
                r.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (r.recordType != null) ...[
                const SizedBox(height: 8),
                Chip(
                  label: Text(r.recordType!),
                  avatar: const Icon(Icons.category_outlined, size: 18),
                ),
              ],
              if (r.summary != null && r.summary!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Summary',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(r.summary!),
              ],
              if (r.aiHighlight != null && r.aiHighlight!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.purple.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.purple.shade800),
                        const SizedBox(width: 10),
                        Expanded(child: Text('AI highlight: ${r.aiHighlight}')),
                      ],
                    ),
                  ),
                ),
              ],
              if (r.providerName != null)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Provider'),
                  subtitle: Text(r.providerName!),
                ),
              if (r.facilityName != null)
                ListTile(
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: const Text('Facility'),
                  subtitle: Text(r.facilityName!),
                ),
              if (r.recordedAt != null)
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Recorded'),
                  subtitle: Text(r.recordedAt!.toIso8601String()),
                ),
              if (offlineDb != null) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _delete(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade800,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete from this phone'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
