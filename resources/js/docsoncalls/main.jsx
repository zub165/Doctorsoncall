import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { App } from './src/App.jsx';

const el = document.getElementById('docsoncalls-root');
if (el) {
  createRoot(el).render(
    <React.StrictMode>
      <BrowserRouter basename="/app">
        <App />
      </BrowserRouter>
    </React.StrictMode>,
  );
}

