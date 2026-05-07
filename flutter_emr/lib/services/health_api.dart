import '../config/api_paths.dart';
import 'emergency_api_client.dart';

/// `GET /api/health/`.
class HealthApi {
  HealthApi(this._client);

  final EmergencyApiClient _client;

  Future<Map<String, dynamic>> check() async {
    final res = await _client.raw.get<Map<String, dynamic>>(ApiPaths.health);
    return res.data ?? <String, dynamic>{};
  }
}
