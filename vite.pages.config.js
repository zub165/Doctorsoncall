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
    // Default to the Django EMR API on your VPS. Override in workflow/env if needed.
    'import.meta.env.VITE_API_BASE_URL': JSON.stringify('http://208.109.215.53:8012/api/'),
  },
});

