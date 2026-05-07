import 'package:flutter/material.dart';

import '../models/medical_record.dart';
import '../services/medical_records_api.dart';
import '../theme/app_theme.dart';

class MedicalRecordDetailScreen extends StatelessWidget {
  const MedicalRecordDetailScreen({
    super.key,
    required this.api,
    required this.recordId,
    this.preview,
  });

  final MedicalRecordsApi api;
  final String recordId;
  final MedicalRecord? preview;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medical record')),
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
            ],
          );
        },
      ),
    );
  }
}
