/// API base URLs (must end with `api/`).
///
/// This app intentionally uses **two** backends:
/// - **EMR (Django)**: auth, appointments, records, settings, sync
/// - **Maps / ER time (legacy)**: hospitals + map/wait-time endpoints
///
/// ## 1 — Base URL (config)
/// - **`EMR_API_BASE_URL = https://api.docsoncalls.com/api/`**
/// - **`MAPS_API_BASE_URL = https://api.mywaitime.com/api/`**
///
/// Use **`https://host/api/`** when nginx terminates TLS on **443** (no `:3015` in the URL).
/// Only append **`:3015`** if clients truly connect to that port on the public host.
///
/// Server remains canonical: **`GET …/api/schema/`** or **`GET …/api/docs/`** (your deployment).
/// Full index also lives in repo **`FRONTEND_API_DOCUMENTATION.md`** §13.
///
/// ## Examples
/// - **Local EMR (iOS Simulator):** `--dart-define=EMR_API_BASE_URL=http://127.0.0.1:8012/api/`
///   Or run: `scripts/flutter_run_ios_simulator_local_api.sh` (default port **8012**).
/// - **Maps stays public:** (no override needed) `https://api.mywaitime.com/api/`
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

  /// Main EMR backend (Django).
  static const String emrApiBaseUrl = String.fromEnvironment(
    'EMR_API_BASE_URL',
    defaultValue: 'https://api.docsoncalls.com/api/',
  );

  /// Maps / ER time backend (legacy).
  static const String mapsApiBaseUrl = String.fromEnvironment(
    'MAPS_API_BASE_URL',
    defaultValue: 'https://api.mywaitime.com/api/',
  );

  /// Back-compat alias for older call sites.
  static const String apiBaseUrl = emrApiBaseUrl;

  /// `GET` path under [apiBaseUrl] → **`GET /api/user-data/`** when default is kept.
  static const String userMePath = String.fromEnvironment(
    'API_USER_ME_PATH',
    defaultValue: 'user-data/',
  );

  /// In-browser group video (default Jitsi). Room name is appended as a single path segment.
  static const String videoMeetHost = String.fromEnvironment(
    'VIDEO_MEET_HOST',
    defaultValue: 'https://meet.jit.si/',
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
