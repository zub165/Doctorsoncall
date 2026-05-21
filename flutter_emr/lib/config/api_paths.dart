/// Paths under [ApiConfig.apiBaseUrl] (`…/api/`). Names mirror **`GET /api/schema/`** on the server.
class ApiPaths {
  ApiPaths._();

  // --- Discovery (OpenAPI / docs) ---
  /// `GET …/api/schema/` (DRF / spectacular, etc.)
  static const apiSchema = 'schema/';

  /// `GET …/api/docs/` when enabled
  static const apiDocs = 'docs/';

  // --- §3 — Core auth & session ---
  static const health = 'health/';
  static const authLogin = 'auth/login/';
  static const authRegister = 'auth/register/';
  static const adminCreateUser = 'admin/users/create/';
  static const authPasswordPolicy = 'auth/password-policy/';
  static const authLogout = 'auth/logout/';
  static const authDeleteAccount = 'auth/delete-account/';
  static const authPasswordResetRequest = 'auth/password-reset/request/';
  static const authPasswordResetConfirm = 'auth/password-reset/confirm/';
  static const changePassword = 'auth/change-password/';

  // --- Doctor On Call (role-based app layer) ---
  static const docOnCallHealth = 'doctor-on-call/health/';
  static const docOnCallMe = 'doctor-on-call/me/';
  static const docOnCallSyncPull = 'doctor-on-call/sync/';
  static const docOnCallSyncPush = 'doctor-on-call/sync/push/';

  /// Default `user-data/`; override with `--dart-define=API_USER_ME_PATH=…`.
  /// Use [ApiConfig.userMePath] at call sites that need the configured path.
  static const userData = 'user-data/';

  // --- §4 — Hospital / ER ---
  static const hospitals = 'hospitals/';

  /// Search / nearby — query params as your backend expects (e.g. lat, lon, radius).
  static String hospitalsSearch({
    required double lat,
    required double lon,
    int radiusM = 25000,
    int limit = 50,
    String type = 'all',
  }) =>
      'hospitals/search/?lat=$lat&lon=$lon&radius_m=$radiusM&limit=$limit&type=$type';

  /// Alias of search (MyWaitime / EMR proxy).
  static String hospitalsNearby({
    required double lat,
    required double lon,
    int radiusM = 25000,
    int limit = 50,
  }) =>
      'hospitals/nearby/?lat=$lat&lon=$lon&radius_m=$radiusM&limit=$limit';

  static String hospitalDetail(String uuid) => 'hospitals/$uuid/';

  /// `GET …/api/hospitals/<uuid>/smart-wait-time/`
  static String hospitalSmartWaitTime(
    String uuid, {
    double? userLat,
    double? userLon,
  }) {
    var path = 'hospitals/$uuid/smart-wait-time/';
    if (userLat != null && userLon != null) {
      path += '?user_lat=$userLat&user_lon=$userLon';
    }
    return path;
  }

  /// `POST …/api/hospitals/smart-wait-time/batch/` — max 30 UUIDs.
  static const hospitalsSmartWaitTimeBatch = 'hospitals/smart-wait-time/batch/';

  /// Legacy EMR catalog AI wait (integer hospital pk only).
  static String hospitalAiWaitTime(String uuid) =>
      'hospitals/$uuid/ai-wait-time/';

  static const feedbackSubmit = 'feedback/submit/';
  static const feedbackContext = 'feedback/context/';

  // --- OSM / courses (when wired) ---
  static String osmSearchHospitals({
    required double lat,
    required double lon,
  }) => 'osm/search-hospitals/?lat=$lat&lon=$lon';
  static const osmSystemStatus = 'osm/system-status/';

  // TomTom via nginx → Django (key on server)
  static const mapConfig = 'map-config/';
  static const tomtomStatus = 'tomtom/status/';
  static String tomtomTile(int z, int x, int y) =>
      'tomtom/tiles/$z/$x/$y.png';
  /// TomTom Nearby Search backup (EMR proxy; key on server).
  static String tomtomSearchHospitals({
    required double lat,
    required double lon,
    int radiusM = 25000,
    int limit = 40,
  }) =>
      'tomtom/search-hospitals/?lat=$lat&lon=$lon&radius_m=$radiusM&limit=$limit';
  static const coursesV1 = 'v1/courses/';

  // --- Full list + EMR extras (see FRONTEND_API_DOCUMENTATION.md §13) ---
  static const countriesList = 'countries/';
  static const specialitiesList = 'specialities/';
  static const specialitiesSeedAvatars = 'specialities/seed-avatars/';
  static const providersList = 'providers/';
  static const patientsList = 'patients/';
  static const patientsProvidersCross = 'patients-providers/';
  /// Admin: pending patient + provider registrations (staff token).
  static const registrationsPending = 'registrations/pending/';
  static const registrationsApprove = 'registrations/approve/';
  static const importsSubmit = 'imports/submit/';
  /// Doctor applies to become a provider (`POST`).
  static const providersApply = 'providers/apply/';
  static const storeAppointment = 'appointments/';
  static const myAppointments = 'appointments/mine/';
  static const allAppointments = 'appointments/all/';
  /// Llama via Ollama on the VPS (`OLLAMA_BASE_URL`, `OLLAMA_MODEL` on server).
  static const ollamaStatus = 'integrations/ollama-status/';
  static const plans = 'plans/';
  static const roles = 'roles/';

  /// Prefer stable **`/api/nutrition/v1/…`** contract vs legacy analyze paths.
  static const nutritionV1 = 'nutrition/v1/';
  static const nutrition = 'nutrition/';
  static const vitals = 'vitals/';
  static const invoices = 'invoices/';

  /// **`GET/POST /api/medical-records/`** — list / create (see live OpenAPI).
  static const medicalRecords = 'medical-records/';

  /// **`GET/PATCH/DELETE /api/medical-records/<uuid>/`**
  static String medicalRecordDetail(String id) => 'medical-records/$id/';

  /// **`POST /api/medical-records/ai-assist/`** — AI help over records (body: query, optional ids).
  static const medicalRecordsAiAssist = 'medical-records/ai-assist/';

  // --- Patient documents (upload → OCR/text extract → summary report) ---
  static const documents = 'documents/';
  static String documentDetail(int id) => 'documents/$id/';

  // --- Patient consent share (patient → provider) ---
  static const sharesMine = 'shares/mine/';
  static const sharesInbox = 'shares/inbox/';
  static const sharesCreate = 'shares/';
  static const sharesTriage = 'shares/triage/';
  static String shareDetail(int id) => 'shares/$id/';
  static String shareEmail(int id) => 'shares/$id/email/';

  /// Provider SOAP → patient; GET list / POST send.
  static const visitNotes = 'visit-notes/';

  // --- Patient self profile update ---
  static const patientMe = 'patient/me/';

  // --- Billing ---
  static const billingStatus = 'billing/status/';
  static const billingCheckout = 'billing/checkout/';
  static const billingVerifyStore = 'billing/verify-store/';
  static const billingAdminSummary = 'billing/admin/summary/';
  static const doctorStripeConnect = 'billing/doctor/stripe-connect/';
  static const doctorStripeConnectStatus = 'billing/doctor/stripe-connect/status/';
  static const doctorBillingSummary = 'billing/doctor/summary/';
  static const doctorTransactions = 'billing/doctor/transactions/';
  static const doctorCreateInvoice = 'billing/doctor/create-invoice/';
  static const doctorComplimentaryVisit = 'billing/doctor/complimentary-visit/';
  static const doctorRequestPayout = 'billing/doctor/request-payout/';
  static const patientBills = 'billing/patient/bills/';
  static const patientPayBill = 'billing/patient/pay-bill/';

  // --- OCR (direct endpoints) ---
  static const ocrImage = 'ocr/image/';
  static const ocrPdf = 'ocr/pdf/';

  /// Alias for [feedbackSubmit] (legacy call sites).
  static const feedback = feedbackSubmit;
}
