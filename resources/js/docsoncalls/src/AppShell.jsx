import React from 'react';
import { Link, Navigate, Route, Routes, useLocation, useNavigate, useParams } from 'react-router-dom';
import { api, ApiPaths, tokenStore, apiBaseUrl } from './api.js';
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
  'Patients ↔ providers',
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

  const [me, setMe] = React.useState({ loading: true, role: 'guest', is_staff: false });

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const { data } = await api.get(ApiPaths.docOnCallMe);
        const role =
          (data?.data?.role ?? data?.role ?? data?.data?.portal ?? data?.portal ?? 'guest')
            .toString()
            .toLowerCase()
            .trim();
        const user = data?.data?.user ?? data?.user ?? {};
        const isStaff = Boolean(user?.is_staff || user?.is_superuser);
        if (!alive) return;
        setMe({ loading: false, role, is_staff: isStaff });
      } catch {
        if (!alive) return;
        setMe({ loading: false, role: 'guest', is_staff: false });
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const role = (me.role || '').toLowerCase();
  const isAdmin = role === 'admin' || role === 'administrator' || role === 'staff' || me.is_staff;
  const isDoctor = role === 'doctor' || role === 'provider' || role === 'physician';
  const isPatient = !isAdmin && !isDoctor; // default

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
          {!isPatient ? <NavItem to={navTo(2)} active={isActive(2)} label="Triage" /> : null}
          <NavItem to={navTo(3)} active={isActive(3)} label="Courses" />
          <NavItem to={navTo(4)} active={isActive(4)} label="AI assistant" />
          {!isPatient ? <NavItem to={navTo(5)} active={isActive(5)} label="Doctor notes (SOAP)" /> : null}
          <div className="dc-nav-section">Care</div>
          <NavItem to={navTo(6)} active={isActive(6)} label="Appointments" />
          {!isPatient ? <NavItem to={navTo(7)} active={isActive(7)} label="Doctor visit" /> : null}
          <NavItem to={navTo(8)} active={isActive(8)} label="Book appointment" />
          <NavItem to={navTo(9)} active={isActive(9)} label="Discovery" />
          {isAdmin || isDoctor ? <NavItem to={navTo(10)} active={isActive(10)} label="Patients ↔ providers" /> : null}
          <NavItem to={navTo(11)} active={isActive(11)} label="Feedback" />
          <div className="dc-nav-section">Account</div>
          <NavItem to={navTo(12)} active={isActive(12)} label="Settings" />
          <NavItem to={navTo(13)} active={isActive(13)} label="Change password" />
          <NavItem to={navTo(14)} active={isActive(14)} label="Client hub" />
          {isPatient ? <NavItem to={navTo(15)} active={isActive(15)} label="Provider application" /> : null}
          {isAdmin ? <NavItem to={navTo(16)} active={isActive(16)} label="Admin hub" /> : null}
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
            {apiBaseUrl} · {me.loading ? 'role: …' : `role: ${role || 'guest'}`}
          </div>
        </div>

        <Routes>
          <Route path="/" element={<Navigate to="0" replace />} />
          <Route path=":tab" element={<TabRouter isAdmin={isAdmin} isDoctor={isDoctor} isPatient={isPatient} />} />
          <Route path="*" element={<Navigate to="0" replace />} />
        </Routes>
      </main>
    </div>
  );
}

function TabRouter({ isAdmin, isDoctor, isPatient }) {
  const tab = useTab();
  switch (tab) {
    case 0:
      return <Dashboard onNavigateToTab={(i) => {}} />;
    case 1:
      return <Hospitals />;
    case 2:
      return <OsmTriage />;
    case 3:
      return <Courses />;
    case 4:
      return <AiAssistant />;
    case 5:
      return <SoapNotes />;
    case 6:
      return <Appointments />;
    case 7:
      return <DoctorVisit />;
    case 8:
      return <BookAppointment />;
    case 9:
      return <Discovery />;
    case 10:
      return isAdmin || isDoctor ? <PatientsProviders /> : <Placeholder title={TITLES[tab]} tab={tab} />;
    case 11:
      return <Feedback />;
    case 12:
      return <Settings isAdmin={isAdmin} isDoctor={isDoctor} isPatient={isPatient} />;
    case 13:
      return <ChangePassword />;
    case 14:
      return <ClientHub />;
    case 15:
      return isPatient ? <ProviderApply /> : <Placeholder title={TITLES[tab]} tab={tab} />;
    case 16:
      return isAdmin ? <AdminHubLite /> : <Placeholder title={TITLES[tab]} tab={tab} />;
    case 17:
      return <MedicalRecords />;
    default:
      return <Placeholder title={TITLES[tab] || 'Screen'} tab={tab} />;
  }
}

function useApiCall(fn, deps) {
  const [state, setState] = React.useState({ loading: true, error: '', data: null });
  React.useEffect(() => {
    let alive = true;
    setState({ loading: true, error: '', data: null });
    fn()
      .then((data) => {
        if (!alive) return;
        setState({ loading: false, error: '', data });
      })
      .catch((e) => {
        if (!alive) return;
        const msg = e?.response?.data?.message || e?.message || 'Request failed';
        setState({ loading: false, error: msg.toString(), data: null });
      });
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return state;
}

function Card({ title, children, actions }) {
  return (
    <div className="dc-card">
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'center' }}>
        <div style={{ fontWeight: 900, fontSize: 18 }}>{title}</div>
        {actions}
      </div>
      <div style={{ marginTop: 10 }}>{children}</div>
    </div>
  );
}

function KeyValue({ k, v }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, padding: '10px 0', borderBottom: '1px solid var(--dc-border)' }}>
      <div style={{ fontWeight: 800 }}>{k}</div>
      <div style={{ color: 'var(--dc-muted)', textAlign: 'right' }}>{v}</div>
    </div>
  );
}

function OsmTriage() {
  const s = useApiCall(() => api.get(ApiPaths.osmSystemStatus).then((r) => r.data), []);
  return (
    <Card title="Triage (OSM tools)">
      {s.loading ? (
        <div style={{ color: 'var(--dc-muted)' }}>Loading…</div>
      ) : s.error ? (
        <div style={{ color: 'var(--dc-danger)', fontWeight: 800 }}>{s.error}</div>
      ) : (
        <pre style={{ margin: 0, padding: 12, borderRadius: 12, background: '#0b1220', color: '#e5e7eb', overflowX: 'auto', fontSize: 12 }}>
          {JSON.stringify(s.data, null, 2)}
        </pre>
      )}
    </Card>
  );
}

function Courses() {
  const s = useApiCall(() => api.get(ApiPaths.coursesV1).then((r) => r.data), []);
  const items = Array.isArray(s.data) ? s.data : s.data?.results || s.data?.data || [];
  return (
    <Card title="Courses">
      {s.loading ? (
        <div style={{ color: 'var(--dc-muted)' }}>Loading…</div>
      ) : s.error ? (
        <div style={{ color: 'var(--dc-danger)', fontWeight: 800 }}>{s.error}</div>
      ) : items.length === 0 ? (
        <div style={{ color: 'var(--dc-muted)' }}>No courses returned.</div>
      ) : (
        <div className="dc-row">
          {items.slice(0, 30).map((c, idx) => (
            <div key={c?.id || idx} style={{ padding: 12, border: '1px solid var(--dc-border)', borderRadius: 14 }}>
              <div style={{ fontWeight: 800 }}>{(c?.title || c?.name || 'Course').toString()}</div>
              <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>{(c?.description || '').toString()}</div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

function AiAssistant() {
  return <Placeholder title="AI assistant" tab={4} />;
}

function SoapNotes() {
  return <Placeholder title="Doctor notes (SOAP)" tab={5} />;
}

function DoctorVisit() {
  return <Placeholder title="Doctor visit" tab={7} />;
}

function Discovery() {
  const countries = useApiCall(() => api.get(ApiPaths.countries).then((r) => r.data), []);
  const specialities = useApiCall(() => api.get(ApiPaths.specialities).then((r) => r.data), []);
  const providers = useApiCall(() => api.get(ApiPaths.providers).then((r) => r.data), []);

  const list = (x) => (Array.isArray(x) ? x : x?.results || x?.data || []);

  return (
    <div className="dc-row">
      <Card title="Countries">{renderMiniList(countries, list(countries.data), (m) => m.country_name || m.name, (m) => m.country_code || m.code)}</Card>
      <Card title="Specialities">{renderMiniList(specialities, list(specialities.data), (m) => m.speciality_name || m.name, (m) => (m.country || m.country_id || '').toString())}</Card>
      <Card title="Providers">{renderMiniList(providers, list(providers.data), (m) => m.full_name || m.name, (m) => (m.status || '').toString())}</Card>
    </div>
  );
}

function renderMiniList(state, items, titleFn, subFn) {
  if (state.loading) return <div style={{ color: 'var(--dc-muted)' }}>Loading…</div>;
  if (state.error) return <div style={{ color: 'var(--dc-danger)', fontWeight: 800 }}>{state.error}</div>;
  if (!items || items.length === 0) return <div style={{ color: 'var(--dc-muted)' }}>Empty.</div>;
  return (
    <div className="dc-row">
      {items.slice(0, 8).map((m, idx) => (
        <div key={m?.id || idx} style={{ padding: 12, border: '1px solid var(--dc-border)', borderRadius: 14 }}>
          <div style={{ fontWeight: 800 }}>{(titleFn(m) || 'Item').toString()}</div>
          <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>{(subFn(m) || '').toString()}</div>
        </div>
      ))}
    </div>
  );
}

function PatientsProviders() {
  const s = useApiCall(() => api.get(ApiPaths.patientsProviders).then((r) => r.data), []);
  return (
    <Card title="Patients ↔ providers">
      {s.loading ? (
        <div style={{ color: 'var(--dc-muted)' }}>Loading…</div>
      ) : s.error ? (
        <div style={{ color: 'var(--dc-danger)', fontWeight: 800 }}>{s.error}</div>
      ) : (
        <pre style={{ margin: 0, padding: 12, borderRadius: 12, background: '#0b1220', color: '#e5e7eb', overflowX: 'auto', fontSize: 12 }}>
          {JSON.stringify(s.data, null, 2)}
        </pre>
      )}
    </Card>
  );
}

function Settings({ isAdmin }) {
  const health = useApiCall(() => api.get(ApiPaths.health).then((r) => r.status), []);
  const me = useApiCall(() => api.get(ApiPaths.docOnCallMe).then((r) => r.data), []);
  const repl = useApiCall(() => api.get(ApiPaths.replicateToken).then((r) => r.data), []);

  return (
    <div className="dc-row">
      <Card title="API connections">
        <KeyValue k="API base URL" v={apiBaseUrl} />
        <KeyValue k="Backend health" v={health.loading ? '…' : health.error ? 'Not reachable' : 'Connected'} />
        <KeyValue k="Role endpoint" v={me.loading ? '…' : me.error ? 'Failed' : `OK (role: ${(me.data?.data?.role ?? me.data?.role ?? 'unknown').toString()})`} />
        <KeyValue
          k="AI provider (Replicate)"
          v={
            repl.loading
              ? '…'
              : repl.error
                ? 'Not configured'
                : (repl.data?.configured === true || repl.data?.data?.configured === true)
                  ? 'Configured'
                  : 'Not configured'
          }
        />
        {isAdmin ? (
          <div style={{ marginTop: 12 }}>
            <Link className="dc-btn dc-btn-primary" to="/shell/16">
              Open Admin hub
            </Link>
          </div>
        ) : null}
      </Card>
    </div>
  );
}

function ChangePassword() {
  const [pw, setPw] = React.useState('');
  const [state, setState] = React.useState({ loading: false, error: '', ok: '' });

  async function submit(e) {
    e.preventDefault();
    setState({ loading: true, error: '', ok: '' });
    try {
      await api.post(ApiPaths.changePassword, { new_password: pw });
      setState({ loading: false, error: '', ok: 'Password updated.' });
      setPw('');
    } catch (err) {
      setState({ loading: false, error: err?.response?.data?.message || 'Failed', ok: '' });
    }
  }

  return (
    <Card title="Change password">
      <form className="dc-row" style={{ maxWidth: 520 }} onSubmit={submit}>
        <input className="dc-input" type="password" value={pw} onChange={(e) => setPw(e.target.value)} placeholder="New password" required />
        {state.error ? <div style={{ color: 'var(--dc-danger)', fontWeight: 800, fontSize: 13 }}>{state.error}</div> : null}
        {state.ok ? <div style={{ color: 'var(--dc-primary)', fontWeight: 900, fontSize: 13 }}>{state.ok}</div> : null}
        <button className="dc-btn dc-btn-primary" disabled={state.loading}>
          {state.loading ? 'Updating…' : 'Update'}
        </button>
      </form>
    </Card>
  );
}

function ClientHub() {
  return <Placeholder title="Client hub" tab={14} />;
}

function ProviderApply() {
  const [form, setForm] = React.useState({ full_name: '', email: '', phone_number: '', gender: 'male', speciality_id: '' });
  const [state, setState] = React.useState({ loading: false, error: '', ok: '' });

  async function submit(e) {
    e.preventDefault();
    setState({ loading: true, error: '', ok: '' });
    try {
      await api.post(ApiPaths.providerApply, { ...form, speciality_id: Number(form.speciality_id) });
      setState({ loading: false, error: '', ok: 'Submitted (pending approval).' });
    } catch (err) {
      setState({ loading: false, error: err?.response?.data?.message || 'Submit failed', ok: '' });
    }
  }

  return (
    <Card title="Provider apply">
      <form className="dc-row" style={{ maxWidth: 640 }} onSubmit={submit}>
        <input className="dc-input" value={form.full_name} onChange={(e) => setForm((s) => ({ ...s, full_name: e.target.value }))} placeholder="Full name" required />
        <input className="dc-input" value={form.email} onChange={(e) => setForm((s) => ({ ...s, email: e.target.value }))} placeholder="Email" required />
        <input className="dc-input" value={form.phone_number} onChange={(e) => setForm((s) => ({ ...s, phone_number: e.target.value }))} placeholder="Phone number" required />
        <input className="dc-input" value={form.speciality_id} onChange={(e) => setForm((s) => ({ ...s, speciality_id: e.target.value }))} placeholder="Speciality ID" required />
        {state.error ? <div style={{ color: 'var(--dc-danger)', fontWeight: 800, fontSize: 13 }}>{state.error}</div> : null}
        {state.ok ? <div style={{ color: 'var(--dc-primary)', fontWeight: 900, fontSize: 13 }}>{state.ok}</div> : null}
        <button className="dc-btn dc-btn-primary" disabled={state.loading}>
          {state.loading ? 'Submitting…' : 'Submit'}
        </button>
      </form>
    </Card>
  );
}

function AdminHubLite() {
  const s = useApiCall(() => api.get(ApiPaths.registrationsPending).then((r) => r.data), []);
  const [busy, setBusy] = React.useState(false);

  async function approve(kind, id) {
    setBusy(true);
    try {
      await api.post(ApiPaths.registrationsApprove, { kind, id });
      window.location.reload();
    } finally {
      setBusy(false);
    }
  }

  const data = s.data?.data || s.data || {};
  const providers = Array.isArray(data.providers) ? data.providers : [];
  const patients = Array.isArray(data.patients) ? data.patients : [];

  return (
    <div className="dc-row">
      <Card title="Pending provider registrations" actions={<button className="dc-btn" onClick={() => window.location.reload()} disabled={busy}>Refresh</button>}>
        {s.loading ? (
          <div style={{ color: 'var(--dc-muted)' }}>Loading…</div>
        ) : s.error ? (
          <div style={{ color: 'var(--dc-danger)', fontWeight: 800 }}>{s.error}</div>
        ) : providers.length === 0 ? (
          <div style={{ color: 'var(--dc-muted)' }}>No pending providers.</div>
        ) : (
          <div className="dc-row">
            {providers.slice(0, 50).map((p) => (
              <div key={p.id} style={{ padding: 12, border: '1px solid var(--dc-border)', borderRadius: 14, display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                <div>
                  <div style={{ fontWeight: 800 }}>{p.full_name || p.name}</div>
                  <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>{p.email}</div>
                </div>
                <button className="dc-btn dc-btn-primary" onClick={() => approve('provider', p.id)} disabled={busy}>
                  Approve
                </button>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Card title="Pending patient registrations">
        {s.loading ? (
          <div style={{ color: 'var(--dc-muted)' }}>Loading…</div>
        ) : s.error ? (
          <div style={{ color: 'var(--dc-danger)', fontWeight: 800 }}>{s.error}</div>
        ) : patients.length === 0 ? (
          <div style={{ color: 'var(--dc-muted)' }}>No pending patients.</div>
        ) : (
          <div className="dc-row">
            {patients.slice(0, 50).map((p) => (
              <div key={p.id} style={{ padding: 12, border: '1px solid var(--dc-border)', borderRadius: 14, display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                <div>
                  <div style={{ fontWeight: 800 }}>{p.name || p.full_name}</div>
                  <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>{p.email}</div>
                </div>
                <button className="dc-btn dc-btn-primary" onClick={() => approve('patient', p.id)} disabled={busy}>
                  Approve
                </button>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}

