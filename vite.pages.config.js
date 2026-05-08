import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Dedicated Vite build for GitHub Pages (static hosting).
// Produces `dist/` and expects routing via hash to avoid 404s on deep links.
export default defineConfig({
  base: '/Doctorsoncall/',
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input: 'docsoncalls-pages/index.html',
    },
  },
  define: {
    'import.meta.env.VITE_ROUTER_MODE': JSON.stringify('hash'),
    'import.meta.env.VITE_ROUTER_BASENAME': JSON.stringify('/Doctorsoncall'),
    // GitHub Pages is HTTPS, so the API must be HTTPS too (avoid Mixed Content).
    'import.meta.env.VITE_API_BASE_URL': JSON.stringify('https://api.docsoncalls.com/api/'),
  },
});

