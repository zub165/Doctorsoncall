import 'package:flutter/material.dart';

import '../services/ai_data_sharing_consent.dart';

/// In-app disclosure required by App Store Guideline 5.1.2(i) before AI requests.
class AiDataSharingConsentDialog extends StatelessWidget {
  const AiDataSharingConsentDialog({
    super.key,
    required this.includesHealthRecords,
    required this.onViewPrivacy,
  });

  final bool includesHealthRecords;
  final VoidCallback onViewPrivacy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Allow AI to process your information?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Docs On Call uses an AI assistant. Before anything is sent, please '
              'review what is shared and who receives it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'What may be sent',
              bullets: [
                'Text you type or dictate (symptoms, questions, visit notes, SOAP drafts).',
                if (includesHealthRecords)
                  'Excerpts from medical records or documents you select for summarization.',
                'Context needed to answer (for example, patient vs provider role).',
              ],
            ),
            _Section(
              title: 'Who receives it',
              bullets: [
                AiDataSharingConsent.operatorName,
                'Our API at ${AiDataSharingConsent.apiEndpoint}',
                'Inference is run by ${AiDataSharingConsent.aiProcessor}. '
                    'We do not sell your data or send it to consumer AI chatbots '
                    '(such as ChatGPT) for advertising or model training.',
              ],
            ),
            _Section(
              title: 'How it is used',
              bullets: const [
                'General health information and documentation help only — not a diagnosis.',
                'Responses are generated automatically; always follow your clinician or emergency services for urgent care.',
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You can decline and still use non-AI features. You may revoke consent '
              'any time in Settings → AI data sharing.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton(
              onPressed: onViewPrivacy,
              child: const Text('Read full Privacy Policy'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Don't Allow"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Allow & Continue'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(b, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
