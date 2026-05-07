import axios from 'axios';

const DEFAULT_BASE = 'http://127.0.0.1:3015/api/';

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
  if (typeof v === 'string' && v.trim()) return v.trim();
  return DEFAULT_BASE;
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
  myAppointments: 'appointments/mine/',
  allAppointments: 'appointments/all/',
  storeAppointment: 'appointments/',
  feedbackSubmit: 'feedback/submit/',
  medicalRecords: 'medical-records/',
  medicalRecordsAiAssist: 'medical-records/ai-assist/',
};

