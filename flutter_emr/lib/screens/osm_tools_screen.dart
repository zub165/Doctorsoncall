import 'package:flutter/material.dart';

import '../services/emergency_api_client.dart';
import '../theme/app_theme.dart';

/// Quick entry: full triage + visit tools live in **Doctor visit** (single workflow).
class OsmToolsScreen extends StatelessWidget {
  const OsmToolsScreen({
    super.key,
    required this.apiClient,
    this.onNavigateToShellTab,
  });

  /// Kept for call-site compatibility (e.g. guest hospitals flow).
  // ignore: unused_field
  final EmergencyApiClient apiClient;

  /// When null (e.g. pushed from guest hospitals flow), only Close is offered.
  final ValueChanged<int>? onNavigateToShellTab;

  @override
  Widget build(BuildContext context) {
    final canShell = onNavigateToShellTab != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Triage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'One place for triage',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Vitals, BMI, skin photo, file import/export, WhatsApp or browser meet, '
                    'and linking a chart to an appointment are all in Doctor visit.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade800,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 18),
                  if (canShell) ...[
                    FilledButton.icon(
                      onPressed: () => onNavigateToShellTab!(7),
                      icon: const Icon(Icons.video_call_outlined),
                      label: const Text('Open Doctor visit'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => onNavigateToShellTab!(1),
                      icon: const Icon(Icons.local_hospital_outlined),
                      label: const Text('Hospitals & nearby'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Close'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
