import 'package:dio/dio.dart';

import '../config/api_paths.dart';
import 'emergency_api_client.dart';

/// `GET /api/health/`.
class HealthApi {
  HealthApi(this._client);

  final EmergencyApiClient _client;

  Future<Map<String, dynamic>> check() async {
    final res = await _client.raw.get<dynamic>(ApiPaths.health);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  /// True when `GET …/health/` returns HTTP 200 and a known healthy payload.
  static bool isHealthyResponse(int? statusCode, dynamic data) {
    if (statusCode != 200) return false;
    if (data is! Map) return true;
    final m = Map<String, dynamic>.from(data);
    final st = m['status']?.toString().toLowerCase();
    if (st == 'success' || st == 'healthy' || st == 'ok') return true;
    if (m['data'] is Map) return true;
    if (m['ok'] == true) return true;
    return false;
  }

  /// Ping with optional retry (simulator Wi‑Fi / DNS glitches on cold start).
  Future<bool> ping({int attempts = 3}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final res = await _client.raw.get<dynamic>(
          ApiPaths.health,
          options: Options(
            sendTimeout: const Duration(seconds: 25),
            receiveTimeout: const Duration(seconds: 25),
            validateStatus: (code) => code != null && code < 500,
          ),
        );
        if (isHealthyResponse(res.statusCode, res.data)) return true;
      } on DioException {
        /* try again */
      } catch (_) {
        /* try again */
      }
      if (i + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    return false;
  }
}
