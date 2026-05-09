import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../config/api_paths.dart';
import '../models/login_portal.dart';
import 'emergency_api_client.dart';

/// Pulls token from Django login envelope: `{ "status": "success", "data": { "token": "..." } }`.
String? _tokenFromLoginResponse(Map<String, dynamic>? body) {
  if (body == null) return null;
  if (body['status']?.toString() == 'success' && body['data'] is Map) {
    final data = Map<String, dynamic>.from(body['data'] as Map);
    final t = data['token'];
    if (t is String && t.isNotEmpty) return t;
  }
  // Fallback shapes (bare or nested elsewhere)
  return _fallbackToken(body);
}

String? _fallbackToken(Map<String, dynamic>? data) {
  if (data == null) return null;
  final direct = data['token'] ?? data['auth_token'] ?? data['key'];
  if (direct is String && direct.isNotEmpty) return direct;
  final inner = data['data'];
  if (inner is Map<String, dynamic>) return _fallbackToken(inner);
  if (inner is Map) return _fallbackToken(Map<String, dynamic>.from(inner));
  return null;
}

String _formatAuthError(dynamic data) {
  if (data is Map && data['status']?.toString() == 'error') {
    final err = data['errors'];
    if (err is Map) return err.toString();
    return data['message']?.toString() ?? 'Authentication failed';
  }
  return 'Authentication failed';
}

class AuthApi {
  AuthApi(this._client);

  final EmergencyApiClient _client;

  /// **`POST /api/auth/login/`** — send **`email` + `password`** or **`username` + `password`**.
  /// Includes **`portal`** and **`role`** ([LoginPortal.apiValue]) for server-side lane checks.
  Future<void> login(
    String identifier,
    String password, {
    LoginPortal portal = LoginPortal.patient,
  }) async {
    final id = identifier.trim();
    final data = <String, dynamic>{
      'password': password,
      'portal': portal.apiValue,
      'role': portal.apiValue,
    };
    if (id.contains('@')) {
      data['email'] = id;
    } else {
      data['username'] = id;
    }
    final res = await _client.raw.post<Map<String, dynamic>>(
      ApiPaths.authLogin,
      data: data,
      options: Options(contentType: Headers.jsonContentType),
    );

    final body = res.data;
    final token = _tokenFromLoginResponse(body)?.trim();
    if (token != null && token.isNotEmpty) {
      await _client.tokenRepo.saveToken(token);
      await _client.tokenRepo.saveLoginPortal(portal.apiValue);
      // Ensure the very next request uses the new token even if secure storage read lags.
      _client.raw.options.headers['Authorization'] = ApiHeaders.authorizationToken(token);
      return;
    }

    final msg =
        body?['message']?.toString() ?? _formatAuthError(body ?? res.data);
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      message: msg,
    );
  }

  /// **`POST /api/auth/register/`** — **`username`** optional; omit or leave blank so the server
  /// derives from **`email`**. Prefer **no spaces** in `username` when set.
  /// This backend does **not** use `password1`/`password2`; match is enforced client-side before send.
  Future<void> register({
    String? username,
    required String email,
    required String password,
    LoginPortal registrationPortal = LoginPortal.patient,
  }) async {
    final payload = <String, dynamic>{
      'email': email,
      'password': password,
      'portal': registrationPortal.apiValue,
      'role': registrationPortal.apiValue,
    };
    final u = username?.trim();
    if (u != null && u.isNotEmpty) {
      if (u.contains(' ')) {
        throw ArgumentError('Username must not contain spaces');
      }
      payload['username'] = u;
    }

    final res = await _client.raw.post<Map<String, dynamic>>(
      ApiPaths.authRegister,
      data: payload,
      options: Options(contentType: Headers.jsonContentType),
    );

    final body = res.data;
    if (body != null && body['status']?.toString() == 'error') {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: _formatAuthError(body),
      );
    }

    final tokenFromBody = _fallbackToken(body)?.trim();
    if (tokenFromBody != null && tokenFromBody.isNotEmpty) {
      await _client.tokenRepo.saveToken(tokenFromBody);
      final portalToPersist = registrationPortal == LoginPortal.doctor
          ? LoginPortal.patient
          : registrationPortal;
      await _client.tokenRepo.saveLoginPortal(portalToPersist.apiValue);
      return;
    }

    await login(
      email,
      password,
      portal: registrationPortal == LoginPortal.doctor
          ? LoginPortal.patient
          : registrationPortal,
    );
  }

  /// Clears local token; best-effort **`POST /api/auth/logout/`** when a token exists.
  Future<void> logout() async {
    try {
      final token = await _client.tokenRepo.readToken();
      if (token != null && token.isNotEmpty) {
        await _client.raw.post<void>(
          ApiPaths.authLogout,
          options: Options(contentType: Headers.jsonContentType),
        );
      }
    } catch (_) {
      // still clear local session
    }
    await _client.tokenRepo.clear();
  }

  /// Optional: **`GET /api/auth/password-policy/`**
  Future<Map<String, dynamic>> fetchPasswordPolicy() async {
    final res = await _client.raw.get<Map<String, dynamic>>(ApiPaths.authPasswordPolicy);
    return res.data ?? <String, dynamic>{};
  }

  Future<void> requestPasswordReset(String email) async {
    final res = await _client.raw.post<Map<String, dynamic>>(
      ApiPaths.authPasswordResetRequest,
      data: {'email': email.trim()},
      options: Options(contentType: Headers.jsonContentType),
    );
    final body = res.data;
    if (body != null && body['status']?.toString() == 'error') {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: body['message']?.toString() ?? 'Reset request failed',
      );
    }
  }

  DioException decorateError(dynamic e) {
    if (e is DioException) return e;
    return DioException(
      requestOptions: RequestOptions(path: ''),
      message: e.toString(),
    );
  }
}
