import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the DRF API token used as `Authorization: Token <token>`.
///
/// **`login_portal`** stores [`patient`|`doctor`|`administrator`] for UI/session context.
class TokenRepository {
  static const _kToken = 'drf_api_token';
  static const _kPortal = 'login_portal';

  TokenRepository({FlutterSecureStorage? storage, Map<String, String>? memory})
      : _storage = memory == null ? (storage ?? const FlutterSecureStorage()) : storage,
        _memory = memory;

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memory;

  /// Keychain-free store for `flutter test` API smoke checks.
  factory TokenRepository.inMemory() =>
      TokenRepository(memory: <String, String>{});

  Future<String?> readToken() async {
    if (_memory != null) return _memory[_kToken];
    return _storage!.read(key: _kToken);
  }

  Future<void> saveToken(String token) async {
    if (_memory != null) {
      _memory[_kToken] = token;
      return;
    }
    await _storage!.write(key: _kToken, value: token);
  }

  Future<String?> readLoginPortal() async {
    if (_memory != null) return _memory[_kPortal];
    return _storage!.read(key: _kPortal);
  }

  Future<void> saveLoginPortal(String portal) async {
    if (_memory != null) {
      _memory[_kPortal] = portal;
      return;
    }
    await _storage!.write(key: _kPortal, value: portal);
  }

  Future<void> clear() async {
    if (_memory != null) {
      _memory.remove(_kToken);
      _memory.remove(_kPortal);
      return;
    }
    await _storage!.delete(key: _kToken);
    await _storage!.delete(key: _kPortal);
  }
}
