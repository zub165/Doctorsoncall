import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

function envStr(key, fallback) {
  const v = process.env[key];
  return typeof v === 'string' && v.trim() ? v.trim() : fallback;
}

// Dedicated Vite build for GitHub Pages (static hosting).
// Produces `dist/` and expects routing via hash to avoid 404s on deep links.
export default defineConfig({
  // When using a custom domain (docsoncalls.com), the site is served from `/`.
  // (Project Pages would use `/Doctorsoncall/`, but the custom domain is the target.)
  base: envStr('VITE_PAGES_BASE', '/'),
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input: {
        index: 'docsoncalls-pages/index.html',
        privacy: 'docsoncalls-pages/privacy.html',
      },
    },
  },
  define: {
    'import.meta.env.VITE_ROUTER_MODE': JSON.stringify(envStr('VITE_ROUTER_MODE', 'hash')),
    'import.meta.env.VITE_ROUTER_BASENAME': JSON.stringify(envStr('VITE_ROUTER_BASENAME', '/')),
    // GitHub Pages is HTTPS, so APIs must be HTTPS too (avoid Mixed Content).
    // EMR (Django 8012 behind TLS)
    'import.meta.env.VITE_EMR_API_BASE_URL': JSON.stringify(envStr('VITE_EMR_API_BASE_URL', envStr('VITE_API_BASE_URL', 'https://api.docsoncalls.com/api/'))),
    // Maps / ER time (nginx → 3015 legacy app)
    'import.meta.env.VITE_MAPS_API_BASE_URL': JSON.stringify(envStr('VITE_MAPS_API_BASE_URL', 'https://api.mywaitime.com/api/')),
  },
});

