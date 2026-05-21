import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'token_repository.dart';

/// HTTP client for the Django REST API mounted at `/api/`.
///
/// Auth: Django REST Framework token style:
/// `Authorization: Token <value>` (see `authtoken` or your token plugin).
/// Handle **`status: "error"`** and **429** throttling in callers when needed.
class EmergencyApiClient {
  final TokenRepository tokenRepo;
  final Dio _dio = Dio();

  static String _normalizeBaseUrl(String input) {
    var base = input.trim();
    if (base.isEmpty) return base;
    if (!base.endsWith('/')) base = '$base/';

    // If already mounted at `/api/`, keep it stable.
    if (base.endsWith('/api/')) return base;
    if (base.endsWith('/api')) return '$base/';

    // Common misconfig: user sets "https://api.docsoncalls.com" (host only).
    // Our paths are relative to `/api/`, so ensure it exists.
    return '${base}api/';
  }

  EmergencyApiClient({TokenRepository? tokenRepository, String? baseUrl})
      : tokenRepo = tokenRepository ?? TokenRepository() {
    final resolved = (baseUrl != null && baseUrl.trim().isNotEmpty)
        ? baseUrl.trim()
        : ApiConfig.emrApiBaseUrl;
    _dio.options
      ..baseUrl = _normalizeBaseUrl(resolved)
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers['Accept'] = ApiHeaders.acceptJson;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final raw = await tokenRepo.readToken();
          final token = raw?.trim();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = ApiHeaders.authorizationToken(token);
          }
          final method = options.method.toUpperCase();
          final data = options.data;
          final hasJsonBody = data != null &&
              data is! FormData &&
              data is! List<int> &&
              (method == 'POST' || method == 'PUT' || method == 'PATCH');
          if (hasJsonBody &&
              options.contentType == null &&
              options.headers['Content-Type'] == null) {
            options.headers['Content-Type'] = ApiHeaders.contentTypeJson;
          }
          handler.next(options);
        },
      ),
    );
  }

  Dio get raw => _dio;

  /// Resolved EMR base URL (always ends with `/api/`).
  String get emrApiBaseUrl => _dio.options.baseUrl;

  /// Convenience constructor for maps / ER wait-time backend.
  factory EmergencyApiClient.maps({TokenRepository? tokenRepository}) =>
      EmergencyApiClient(
        tokenRepository: tokenRepository,
        baseUrl: ApiConfig.mapsApiBaseUrl,
      );
}
