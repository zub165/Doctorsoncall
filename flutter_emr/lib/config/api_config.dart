/// API base URLs (must end with `api/`).
///
/// ## Hospitals tab — two APIs (do not mix)
///
/// | App area | Base URL | Auth |
/// |----------|----------|------|
/// | Hospitals / ER search / wait times | `https://api.mywaitime.com/api/` | None for read APIs |
/// | Login, appointments, billing, records | `https://api.docsoncalls.com/api/` | `Authorization: Token …` |
///
/// Production: never use `:3015`, `127.0.0.1`, or host-only URLs in release builds.
/// No `MYWAITIME_API_KEY` in the client. TomTom tiles/geocode go through `/api/tomtom/*` on EMR.
///
/// See **`docs/HOSPITALS_TAB_FRONTEND.md`** for full copy/paste spec.
///
/// ## 1 — Base URL (config)
/// - **`EMR_API_BASE_URL = https://api.docsoncalls.com/api/`** (GoDaddy production)
/// - **`MAPS_API_BASE_URL = https://api.mywaitime.com/api/`** (Hospitals live search first)
///
/// ### GoDaddy VPS (gunicorn :8012 behind nginx)
/// - **Phones / TestFlight / Play Store** must use **`https://api.docsoncalls.com/api/`** only.
/// - Nginx on **443** proxies to **`127.0.0.1:8012`**; port **8012 is not open** to the public internet.
/// - Do **not** set `http://YOUR_VPS_IP:8012/api/` on mobile — that causes **“Sign-in failed (network)”**.
///
/// Use **`https://host/api/`** when nginx terminates TLS on **443** (never put `:8012` in the app URL).
///
/// Server remains canonical: **`GET …/api/schema/`** or **`GET …/api/docs/`** (your deployment).
/// Full index also lives in repo **`FRONTEND_API_DOCUMENTATION.md`** §13.
///
/// ## Examples
/// - **Local EMR (iOS Simulator):** `--dart-define=EMR_API_BASE_URL=http://127.0.0.1:8012/api/`
///   Or run: `scripts/flutter_run_ios_simulator_local_api.sh` (EMR **8012**, maps **3015**).
/// - **Local maps (Mac):** `MAPS_API_BASE_URL=http://127.0.0.1:3015/api/` and set Django
///   `MYWAITIME_UPSTREAM_API_BASE=http://127.0.0.1:3015/api/` so `GET …/hospitals/search/` proxies correctly.
/// - **Production / TestFlight:** `./scripts/flutter_run_production_api.sh` sets EMR only;
///   maps default `https://api.mywaitime.com/api/` (override with `FLUTTER_MAPS_API_BASE_URL` if needed).
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
