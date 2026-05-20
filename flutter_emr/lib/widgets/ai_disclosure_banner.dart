import 'package:flutter/material.dart';

import '../services/ai_data_sharing_consent.dart';

/// Persistent notice on AI screens (supplements the consent dialog).
class AiDisclosureBanner extends StatelessWidget {
  const AiDisclosureBanner({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                compact
                    ? 'AI sends your typed health text to ${AiDataSharingConsent.operatorName} '
                        '(${AiDataSharingConsent.aiProcessor}). Not for emergencies. '
                        'You will be asked to allow before the first request.'
                    : 'AI features send the text you enter to ${AiDataSharingConsent.operatorName} '
                        'via our secure API, where ${AiDataSharingConsent.aiProcessor} generates a reply. '
                        'This is not a diagnosis or emergency service. We ask for your permission before '
                        'any data is sent. See our Privacy Policy for details.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
