import axios from 'axios';

/** Default matches local `django_emr`: `python manage.py runserver 127.0.0.1:8012` */
const DEFAULT_BASE = 'http://127.0.0.1:8012/api/';

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

export const apiBaseUrl = (() => {
  const v = import.meta.env?.VITE_API_BASE_URL;
  let base = typeof v === 'string' && v.trim() ? v.trim() : DEFAULT_BASE;
  if (!base.endsWith('/')) base += '/';
  return base;
})();

export const api = axios.create({
  baseURL: apiBaseUrl,
  headers: {
    Accept: 'application/json',
    'Content-Type': 'application/json',
  },
});

api.interceptors.request.use((config) => {
  const token = tokenStore.read();
  if (token) {
    config.headers = config.headers ?? {};
    config.headers.Authorization = `Token ${token}`;
  }
  return config;
});

export const ApiPaths = {
  health: 'health/',
  authLogin: 'auth/login/',
  authRegister: 'auth/register/',
  authLogout: 'auth/logout/',
  changePassword: 'auth/change-password/',
  docOnCallMe: 'doctor-on-call/me/',
  hospitals: 'hospitals/',
  osmSystemStatus: 'osm/system-status/',
  osmSearchHospitals: 'osm/search-hospitals/',
  coursesV1: 'v1/courses/',
  countries: 'countries/',
  specialities: 'specialities/',
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
  medicalRecords: 'medical-records/',
  medicalRecordsAiAssist: 'medical-records/ai-assist/',
};

