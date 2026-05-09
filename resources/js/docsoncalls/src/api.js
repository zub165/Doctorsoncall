import axios from 'axios';

/** Default matches local `django_emr`: `python manage.py runserver 127.0.0.1:8012` */
const DEFAULT_EMR_BASE = 'http://127.0.0.1:8012/api/';

/** Default matches nginx → legacy maps/ER backend (3015). */
const DEFAULT_MAPS_BASE = 'https://api.mywaitime.com/api/';

export const tokenStore = {
  key: 'docsoncalls_token',
  read() {
    try {
      return localStorage.getItem(this.key) || '';
    } catch {
      return '';
    }
  },
  write(token) {
    try {
      localStorage.setItem(this.key, token);
    } catch {
      // ignore
    }
  },
  clear() {
    try {
      localStorage.removeItem(this.key);
    } catch {
      // ignore
    }
  },
};

function normBase(v, fallback) {
  let base = typeof v === 'string' && v.trim() ? v.trim() : fallback;
  if (!base.endsWith('/')) base += '/';
  return base;
}

export const emrApiBaseUrl = normBase(import.meta.env?.VITE_EMR_API_BASE_URL ?? import.meta.env?.VITE_API_BASE_URL, DEFAULT_EMR_BASE);
export const mapsApiBaseUrl = normBase(import.meta.env?.VITE_MAPS_API_BASE_URL, DEFAULT_MAPS_BASE);

// Back-compat alias (older call sites / builds used `VITE_API_BASE_URL`).
export const apiBaseUrl = emrApiBaseUrl;

function mkClient(baseURL) {
  const client = axios.create({
    baseURL,
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
  });

  client.interceptors.request.use((config) => {
    const token = tokenStore.read();
    if (token) {
      config.headers = config.headers ?? {};
      config.headers.Authorization = `Token ${token}`;
    }
    return config;
  });

  return client;
}

// EMR client (Django 8012) — auth, records, appointments, settings, etc.
export const api = mkClient(emrApiBaseUrl);
export const emrApi = api;

// Maps/ER client (nginx → 3015) — hospitals/map/wait-times only.
export const mapsApi = mkClient(mapsApiBaseUrl);

export const ApiPaths = {
  health: 'health/',
  authLogin: 'auth/login/',
  authRegister: 'auth/register/',
  authLogout: 'auth/logout/',
  changePassword: 'auth/change-password/',
  docOnCallMe: 'doctor-on-call/me/',
  hospitals: 'hospitals/',
  hospitalsSearch: 'hospitals/search/',
  // NOTE: prefer `mapsApi` direct calls for maps/ER time (do not mix with EMR).
  erWaitTimes: 'er-wait-times/',
  osmSystemStatus: 'osm/system-status/',
  osmSearchHospitals: 'osm/search-hospitals/',
  coursesV1: 'v1/courses/',
  countries: 'countries/',
  specialities: 'specialities/',
  plans: 'plans/',
  roles: 'roles/',
  providers: 'providers/',
  patients: 'patients/',
  patientsProviders: 'patients-providers/',
  providerApply: 'providers/apply/',
  registrationsPending: 'registrations/pending/',
  registrationsApprove: 'registrations/approve/',
  replicateToken: 'integrations/replicate-token/',
  myAppointments: 'appointments/mine/',
  allAppointments: 'appointments/all/',
  storeAppointment: 'appointments/',
  feedbackSubmit: 'feedback/submit/',
  vitals: 'vitals/',
  invoices: 'invoices/',
  medicalRecords: 'medical-records/',
  medicalRecordsAiAssist: 'medical-records/ai-assist/',
  importsSubmit: 'imports/submit/',
  settingsGeneral: 'settings/general/',
  settingsGeneralKey: (key) => `settings/general/${encodeURIComponent(String(key))}/`,
  documents: 'documents/',
  documentDetail: (id) => `documents/${encodeURIComponent(String(id))}/`,
  sharesMine: 'shares/mine/',
  sharesInbox: 'shares/inbox/',
  sharesCreate: 'shares/',
  shareDetail: (id) => `shares/${encodeURIComponent(String(id))}/`,
  shareEmail: (id) => `shares/${encodeURIComponent(String(id))}/email/`,
  patientMe: 'patient/me/',
  billingStatus: 'billing/status/',
  billingCheckout: 'billing/checkout/',
  ocrImage: 'ocr/image/',
  ocrPdf: 'ocr/pdf/',
};

