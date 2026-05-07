import React from 'react';
import { Link, Navigate, Route, Routes, useLocation, useNavigate, useParams } from 'react-router-dom';
import { api, ApiPaths, tokenStore } from './api.js';
import { Dashboard } from './screens/Dashboard.jsx';
import { Hospitals } from './screens/Hospitals.jsx';
import { Placeholder } from './screens/Placeholder.jsx';
import { Appointments } from './screens/Appointments.jsx';
import { BookAppointment } from './screens/BookAppointment.jsx';
import { Feedback } from './screens/Feedback.jsx';
import { MedicalRecords } from './screens/MedicalRecords.jsx';

const TITLES = [
  'Dashboard',
  'Hospitals',
  'Triage',
  'Courses',
  'AI assistant',
  'Doctor notes (SOAP)',
  'Appointments',
  'Doctor visit',
  'Book appointment',
  'Discovery',
  'Patients · Providers',
  'Feedback',
  'Settings',
  'Change password',
  'Client (home · profile · plan)',
  'Provider apply',
  'Admin (CRUD parity)',
  'Medical records & AI',
];

function NavItem({ to, active, label }) {
  return (
    <Link to={to} data-active={active ? 'true' : 'false'}>
      <span style={{ width: 18, textAlign: 'center', opacity: 0.9 }}>•</span>
      <span>{label}</span>
    </Link>
  );
}

function useTab() {
  const params = useParams();
  const t = Number(params.tab);
  if (Number.isFinite(t) && t >= 0 && t < TITLES.length) return t;
  return 0;
}

export function AppShell() {
  const nav = useNavigate();
  const loc = useLocation();
  const tab = useTab();

  const title = TITLES[tab] || 'Doctor On Call';

  async function signOut() {
    try {
      await api.post(ApiPaths.authLogout);
    } catch {
      // best-effort
    } finally {
      tokenStore.clear();
      nav('/login', { replace: true });
    }
  }

  const navTo = (i) => `/shell/${i}`;
  const isActive = (i) => loc.pathname === navTo(i) || loc.pathname.startsWith(`${navTo(i)}/`);

  return (
    <div className="dc-layout">
      <aside className="dc-sidebar">
        <div className="dc-brand">
          <div className="dc-brand-badge">+</div>
          <div>
            <div className="dc-brand-title">Doctor On Call</div>
            <div className="dc-brand-subtitle">On-call care · Hospital finder</div>
          </div>
        </div>

        <nav className="dc-nav" aria-label="Sidebar navigation">
          <div className="dc-nav-section">Overview</div>
          <NavItem to={navTo(0)} active={isActive(0)} label="Dashboard" />
          <div className="dc-nav-section">Explore</div>
          <NavItem to={navTo(1)} active={isActive(1)} label="Hospitals" />
          <NavItem to={navTo(3)} active={isActive(3)} label="Courses" />
          <NavItem to={navTo(4)} active={isActive(4)} label="AI assistant" />
          <div className="dc-nav-section">Care</div>
          <NavItem to={navTo(6)} active={isActive(6)} label="Appointments" />
          <NavItem to={navTo(8)} active={isActive(8)} label="Book appointment" />
          <NavItem to={navTo(9)} active={isActive(9)} label="Discovery" />
          <NavItem to={navTo(11)} active={isActive(11)} label="Feedback" />
          <div className="dc-nav-section">Account</div>
          <NavItem to={navTo(12)} active={isActive(12)} label="Settings" />
          <NavItem to={navTo(13)} active={isActive(13)} label="Change password" />
          <NavItem to={navTo(14)} active={isActive(14)} label="Client hub" />
          <NavItem to={navTo(15)} active={isActive(15)} label="Provider application" />
          <NavItem to={navTo(16)} active={isActive(16)} label="Admin hub" />
          <NavItem to={navTo(17)} active={isActive(17)} label="Medical records & AI" />
        </nav>

        <div style={{ marginTop: 14 }}>
          <button className="dc-btn dc-btn-danger" style={{ width: '100%' }} onClick={signOut}>
            Sign out
          </button>
        </div>
      </aside>

      <main className="dc-main">
        <div className="dc-topbar">
          <div style={{ fontWeight: 900, fontSize: 18 }}>{title}</div>
          <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>
            {import.meta.env?.VITE_API_BASE_URL ? 'API configured' : 'API default (local)'}
          </div>
        </div>

        <Routes>
          <Route path="/" element={<Navigate to="0" replace />} />
          <Route path=":tab" element={<TabRouter />} />
          <Route path="*" element={<Navigate to="0" replace />} />
        </Routes>
      </main>
    </div>
  );
}

function TabRouter() {
  const tab = useTab();
  switch (tab) {
    case 0:
      return <Dashboard onNavigateToTab={(i) => {}} />;
    case 1:
      return <Hospitals />;
    case 6:
      return <Appointments />;
    case 8:
      return <BookAppointment />;
    case 11:
      return <Feedback />;
    case 17:
      return <MedicalRecords />;
    default:
      return <Placeholder title={TITLES[tab] || 'Screen'} tab={tab} />;
  }
}

