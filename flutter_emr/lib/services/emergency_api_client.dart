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

  EmergencyApiClient({TokenRepository? tokenRepository})
      : tokenRepo = tokenRepository ?? TokenRepository() {
    _dio.options
      ..baseUrl = ApiConfig.apiBaseUrl
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers['Accept'] = ApiHeaders.acceptJson;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenRepo.readToken();
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
}
