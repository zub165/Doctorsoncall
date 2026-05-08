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
  static const authPasswordPolicy = 'auth/password-policy/';
  static const authLogout = 'auth/logout/';
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
  static String hospitalsSearch({required double lat, required double lon}) =>
      'hospitals/search/?lat=$lat&lon=$lon';

  static String hospitalDetail(String uuid) => 'hospitals/$uuid/';

  /// Example AI wait feature: `GET …/api/hospitals/<uuid>/ai-wait-time/`
  static String hospitalAiWaitTime(String uuid) =>
      'hospitals/$uuid/ai-wait-time/';

  static const feedbackSubmit = 'feedback/submit/';

  // --- OSM / courses (when wired) ---
  static String osmSearchHospitals({
    required double lat,
    required double lon,
  }) => 'osm/search-hospitals/?lat=$lat&lon=$lon';
  static const osmSystemStatus = 'osm/system-status/';
  static const coursesV1 = 'v1/courses/';

  // --- Full list + EMR extras (see FRONTEND_API_DOCUMENTATION.md §13) ---
  static const countriesList = 'countries/';
  static const specialitiesList = 'specialities/';
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
  static const replicateToken = 'integrations/replicate-token/';
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
  static String shareDetail(int id) => 'shares/$id/';
  static String shareEmail(int id) => 'shares/$id/email/';

  /// Alias for [feedbackSubmit] (legacy call sites).
  static const feedback = feedbackSubmit;
}
