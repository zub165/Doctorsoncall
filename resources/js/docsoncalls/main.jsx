import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, HashRouter } from 'react-router-dom';
import { App } from './src/App.jsx';

const el = document.getElementById('docsoncalls-root');
if (el) {
  const routerMode = (import.meta.env?.VITE_ROUTER_MODE || '').toString().toLowerCase();
  const basename = (import.meta.env?.VITE_ROUTER_BASENAME || '/app').toString();
  const Router = routerMode === 'hash' ? HashRouter : BrowserRouter;

  createRoot(el).render(
    <React.StrictMode>
      <Router basename={routerMode === 'hash' ? undefined : basename}>
        <App />
      </Router>
    </React.StrictMode>,
  );
}

