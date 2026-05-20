import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/ai_data_sharing_consent_dialog.dart';

/// Tracks explicit user permission before sending health-related text to the
/// app's AI backend (Ollama on Docs On Call servers).
class AiDataSharingConsent {
  AiDataSharingConsent._();

  static const _storage = FlutterSecureStorage();
  static const _grantedKey = 'ai_data_sharing_consent_granted';
  static const _versionKey = 'ai_data_sharing_consent_version';

  /// Bump when disclosure text changes so users are re-prompted.
  static const int currentVersion = 1;

  static const privacyPolicyUrl = 'https://docsoncalls.com/privacy.html';

  static const String operatorName = 'Innovator Generation';
  static const String apiEndpoint =
      'https://api.docsoncalls.com/api/medical-records/ai-assist/';
  static const String aiProcessor =
      'Ollama (open-source large language model) on Docs On Call servers';

  static Future<bool> isGranted() async {
    final v = await _storage.read(key: _versionKey);
    if (v != currentVersion.toString()) return false;
    final g = await _storage.read(key: _grantedKey);
    return g == 'true';
  }

  static Future<void> revoke() async {
    await _storage.delete(key: _grantedKey);
    await _storage.delete(key: _versionKey);
  }

  static Future<void> _saveGranted() async {
    await _storage.write(key: _grantedKey, value: 'true');
    await _storage.write(key: _versionKey, value: currentVersion.toString());
  }

  /// Shows disclosure + permission dialog when needed. Returns false if denied.
  static Future<bool> requestIfNeeded(
    BuildContext context, {
    bool includesHealthRecords = false,
  }) async {
    if (await isGranted()) return true;
    if (!context.mounted) return false;

    final allowed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AiDataSharingConsentDialog(
        includesHealthRecords: includesHealthRecords,
        onViewPrivacy: () => launchUrl(
          Uri.parse(privacyPolicyUrl),
          mode: LaunchMode.externalApplication,
        ),
      ),
    );

    if (allowed == true) {
      await _saveGranted();
      return true;
    }
    return false;
  }
}

/// Thrown when the user declines AI data sharing.
class AiConsentDenied implements Exception {
  const AiConsentDenied();
}
