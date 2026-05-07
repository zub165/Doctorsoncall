import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the DRF API token used as `Authorization: Token <token>`.
///
/// **`login_portal`** stores [`patient`|`doctor`|`administrator`] for UI/session context.
class TokenRepository {
  static const _kToken = 'drf_api_token';
  static const _kPortal = 'login_portal';

  TokenRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<void> saveToken(String token) =>
      _storage.write(key: _kToken, value: token);

  Future<String?> readLoginPortal() => _storage.read(key: _kPortal);

  Future<void> saveLoginPortal(String portal) =>
      _storage.write(key: _kPortal, value: portal);

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kPortal);
  }
}
