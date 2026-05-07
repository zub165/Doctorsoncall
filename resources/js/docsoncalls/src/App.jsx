import React from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { SessionGate } from './SessionGate.jsx';
import { AppShell } from './AppShell.jsx';
import { Login } from './screens/Login.jsx';
import { Register } from './screens/Register.jsx';

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/register" element={<Register />} />
      <Route path="/" element={<SessionGate />} />
      <Route path="/shell/*" element={<AppShell />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

