import 'package:flutter/material.dart';

import 'ai_data_sharing_consent.dart';
import 'medical_records_api.dart';

/// Gate + API helper for App Store Guideline 5.1.2(i).
class ConsentedAiAssist {
  ConsentedAiAssist(this._api);

  final MedicalRecordsApi _api;

  /// Call before [assist] while [context] is still valid (no await before this).
  static Future<bool> ensureConsent(
    BuildContext context, {
    bool includesHealthRecords = false,
  }) {
    return AiDataSharingConsent.requestIfNeeded(
      context,
      includesHealthRecords: includesHealthRecords,
    );
  }

  Future<Map<String, dynamic>> assist({
    required String query,
    List<String>? recordIds,
    String? kind,
  }) {
    return _api.aiAssist(
      query: query,
      recordIds: recordIds,
      kind: kind,
    );
  }
}

void showAiConsentDeniedSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'AI is off until you allow data sharing. You can enable it in Settings → AI data sharing.',
      ),
      duration: Duration(seconds: 5),
    ),
  );
}
