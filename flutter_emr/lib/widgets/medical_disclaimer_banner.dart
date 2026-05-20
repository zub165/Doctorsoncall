import 'package:flutter/material.dart';

/// Google Play Health policy: visible reminder to consult a healthcare professional.
class MedicalDisclaimerBanner extends StatelessWidget {
  const MedicalDisclaimerBanner({super.key, this.compact = false});

  final bool compact;

  static const String playStoreText =
      'This app does not provide medical advice, diagnosis, or treatment. '
      'Always consult a qualified healthcare professional for medical advice, '
      'diagnosis, or treatment. In an emergency, call your local emergency number.';

  static const String shortText =
      'Not medical advice. Consult a healthcare professional for diagnosis and treatment. '
      'Call emergency services in an emergency.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = compact ? shortText : playStoreText;

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.amber.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade200),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.medical_information_outlined,
              color: Colors.amber.shade900,
              size: compact ? 22 : 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.amber.shade900,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
