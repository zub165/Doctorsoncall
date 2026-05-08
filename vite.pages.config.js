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
      input: 'docsoncalls-pages/index.html',
    },
  },
  define: {
    'import.meta.env.VITE_ROUTER_MODE': JSON.stringify(envStr('VITE_ROUTER_MODE', 'hash')),
    'import.meta.env.VITE_ROUTER_BASENAME': JSON.stringify(envStr('VITE_ROUTER_BASENAME', '/')),
    // GitHub Pages is HTTPS, so the API must be HTTPS too (avoid Mixed Content).
    'import.meta.env.VITE_API_BASE_URL': JSON.stringify(envStr('VITE_API_BASE_URL', 'https://api.docsoncalls.com/api/')),
  },
});

