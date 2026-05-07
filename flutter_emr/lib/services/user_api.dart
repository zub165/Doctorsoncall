import '../config/api_config.dart';
import '../config/api_paths.dart';
import 'emergency_api_client.dart';

class UserApi {
  UserApi(this._client);

  final EmergencyApiClient _client;

  /// Raw JSON from **`GET /api/user-data/`** (`Authorization: Token …` when logged in).
  ///
  /// May return **200** with `is_authenticated: false` for **guest** — not an error.
  /// Success envelope: `{ "status": "success", "data": { ... , "is_authenticated": bool } }`.
  Future<Map<String, dynamic>> fetchUserDataEnvelope() async {
    final path = ApiConfig.userMePath;
    final res = await _client.raw.get<Map<String, dynamic>>(path);
    return res.data ?? <String, dynamic>{};
  }

  /// Inner **`data`** object when present (else full body), for UI.
  static Map<String, dynamic> unwrapData(Map<String, dynamic> envelope) {
    final inner = envelope['data'];
    if (inner is Map<String, dynamic>) return inner;
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return envelope;
  }

  /// Doctor On Call role + profile summary from **`GET /api/doctor-on-call/me/`**.
  ///
  /// Expected shape (envelope or raw):
  /// `{ role: "doctor|patient|admin", user: {}, doctor: {}, patient: {} }`
  Future<Map<String, dynamic>> fetchDoctorOnCallMe() async {
    final res = await _client.raw.get<Map<String, dynamic>>(ApiPaths.docOnCallMe);
    final body = res.data ?? <String, dynamic>{};
    return unwrapData(body);
  }
}
