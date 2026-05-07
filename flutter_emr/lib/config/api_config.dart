/// Django API base: every request path is relative to [ApiConfig.apiBaseUrl] (must end with `api/`).
///
/// **Lab / LMS (optional):** a separate origin may host **`/lab/`** — use a second client or
/// `--dart-define=LAB_API_BASE_URL=https://host/lab/` when you wire lab features (not the same as `/api/`).
///
/// ## 1 — Base URL (config)
/// **`API_BASE_URL = https://YOUR_PUBLIC_HOST/api/`**
///
/// Use **`https://host/api/`** when nginx terminates TLS on **443** (no `:3015` in the URL).
/// Only append **`:3015`** if clients truly connect to that port on the public host.
///
/// Server remains canonical: **`GET …/api/schema/`** or **`GET …/api/docs/`** (your deployment).
/// Full index also lives in repo **`FRONTEND_API_DOCUMENTATION.md`** §13.
///
/// **Production (canonical):** `https://api.mywaitime.com/api/` (see `FRONTEND_API_DOCUMENTATION.md` §2.1
/// and repo `scripts/flutter_run_production_api.sh`.)
///
/// ## Examples
/// - **HTTPS (443):** `--dart-define=API_BASE_URL=https://api.mywaitime.com/api/`
/// - **HTTPS explicit port:** `--dart-define=API_BASE_URL=https://YOUR_DOMAIN:3015/api/`
/// - **VPS IP (HTTP, dev only):** `--dart-define=API_BASE_URL=http://208.109.215.53:3015/api/`
/// - **Local:** `http://127.0.0.1:3015/api/` or `http://127.0.0.1:3016/api/`
/// - **Android emulator → Mac:** `http://10.0.2.2:PORT/api/`
///
/// ## 2 — Headers (see [ApiHeaders])
/// - `Content-Type: application/json`
/// - `Accept: application/json`
/// - `Authorization: Token <paste-token-after-login>`
///
/// ## 6 — Example Flutter defines
/// ```bash
/// flutter run \
///   --dart-define=API_BASE_URL=https://YOUR_PUBLIC_HOST/api/ \
///   --dart-define=API_USER_ME_PATH=user-data/
/// ```
class ApiConfig {
  ApiConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3015/api/',
  );

  /// `GET` path under [apiBaseUrl] → **`GET /api/user-data/`** when default is kept.
  static const String userMePath = String.fromEnvironment(
    'API_USER_ME_PATH',
    defaultValue: 'user-data/',
  );
}

/// Standard header values for the Django REST JSON API (single source of truth: `GET …/api/schema/`).
abstract final class ApiHeaders {
  ApiHeaders._();

  static const String contentTypeJson = 'application/json';
  static const String acceptJson = 'application/json';

  /// Django REST Framework token style: `Authorization: Token <key>`.
  static String authorizationToken(String token) => 'Token $token';
}
