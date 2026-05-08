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
  'Patients ↔ providers',
  'Feedback',
  'Settings',
  'Change password',
  'Client (home · profile · plan)',
  'Provider apply',
  'Admin (CRUD parity)',
  'Medical records & AI',
];

function NavItem({ to, active, label, onClick }) {
  return (
    <Link to={to} data-active={active ? 'true' : 'false'} onClick={onClick}>
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
  const [drawerOpen, setDrawerOpen] = React.useState(false);

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
      {drawerOpen ? <div className="dc-drawer-overlay" onClick={() => setDrawerOpen(false)} /> : null}

      <aside className="dc-sidebar" data-open={drawerOpen ? 'true' : 'false'}>
        <div className="dc-brand">
          <div className="dc-brand-badge">+</div>
          <div>
            <div className="dc-brand-title">Doctor On Call</div>
            <div className="dc-brand-subtitle">On-call care · Hospital finder</div>
          </div>
        </div>

        <nav className="dc-nav" aria-label="Sidebar navigation">
          <div className="dc-nav-section">Overview</div>
          <NavItem to={navTo(0)} active={isActive(0)} label="Dashboard" onClick={() => setDrawerOpen(false)} />
          <div className="dc-nav-section">Explore</div>
          <NavItem to={navTo(1)} active={isActive(1)} label="Hospitals" onClick={() => setDrawerOpen(false)} />
          {!isPatient ? <NavItem to={navTo(2)} active={isActive(2)} label="Triage" onClick={() => setDrawerOpen(false)} /> : null}
          <NavItem to={navTo(3)} active={isActive(3)} label="Courses" onClick={() => setDrawerOpen(false)} />
          <NavItem to={navTo(4)} active={isActive(4)} label="AI assistant" onClick={() => setDrawerOpen(false)} />
          {!isPatient ? <NavItem to={navTo(5)} active={isActive(5)} label="Doctor notes (SOAP)" onClick={() => setDrawerOpen(false)} /> : null}
          <div className="dc-nav-section">Care</div>
          <NavItem to={navTo(6)} active={isActive(6)} label="Appointments" onClick={() => setDrawerOpen(false)} />
          {!isPatient ? <NavItem to={navTo(7)} active={isActive(7)} label="Doctor visit" onClick={() => setDrawerOpen(false)} /> : null}
          <NavItem to={navTo(8)} active={isActive(8)} label="Book appointment" onClick={() => setDrawerOpen(false)} />
          <NavItem to={navTo(9)} active={isActive(9)} label="Discovery" onClick={() => setDrawerOpen(false)} />
          {isAdmin || isDoctor ? (
            <NavItem to={navTo(10)} active={isActive(10)} label="Patients ↔ providers" onClick={() => setDrawerOpen(false)} />
          ) : null}
          <NavItem to={navTo(11)} active={isActive(11)} label="Feedback" onClick={() => setDrawerOpen(false)} />
          <div className="dc-nav-section">Account</div>
          <NavItem to={navTo(12)} active={isActive(12)} label="Settings" onClick={() => setDrawerOpen(false)} />
          <NavItem to={navTo(13)} active={isActive(13)} label="Change password" onClick={() => setDrawerOpen(false)} />
          <NavItem to={navTo(14)} active={isActive(14)} label="Client hub" onClick={() => setDrawerOpen(false)} />
          {isPatient ? (
            <NavItem to={navTo(15)} active={isActive(15)} label="Provider application" onClick={() => setDrawerOpen(false)} />
          ) : null}
          {isAdmin ? <NavItem to={navTo(16)} active={isActive(16)} label="Admin hub" onClick={() => setDrawerOpen(false)} /> : null}
          <NavItem to={navTo(17)} active={isActive(17)} label="Medical records & AI" onClick={() => setDrawerOpen(false)} />
        </nav>

        <div className="dc-sidebar-footer">
          <button className="dc-btn dc-btn-danger" style={{ width: '100%' }} onClick={signOut}>
            Sign out
          </button>
        </div>
      </aside>

      <main className="dc-main">
        <div className="dc-topbar">
          <div className="dc-topbar-left">
            <button
              className="dc-icon-btn"
              aria-label="Open menu"
              onClick={() => setDrawerOpen(true)}
              title="Menu"
              type="button"
            >
              <span style={{ fontSize: 18, lineHeight: 1 }}>☰</span>
            </button>
            <div style={{ fontWeight: 900, fontSize: 18, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {title}
            </div>
          </div>
          {/* Intentionally hide API/role debug info from the main UI.
              Admins can view API connections inside Settings. */}
          <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>{me.loading ? '' : ''}</div>
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
      return <Appointments isAdmin={isAdmin} isDoctor={isDoctor} isPatient={isPatient} />;
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
  const [v, setV] = React.useState({
    height_cm: '',
    weight_kg: '',
    temperature_c: '',
    bmi: '',
    bp_sys: '',
    bp_dia: '',
    pulse_bpm: '',
    resp_min: '',
    spo2: '',
    glucose_mgdl: '',
    notes: '',
  });
  const [photo, setPhoto] = React.useState(null);

  React.useEffect(() => {
    const h = Number(v.height_cm);
    const w = Number(v.weight_kg);
    if (Number.isFinite(h) && Number.isFinite(w) && h > 0 && w > 0) {
      const m = h / 100;
      const bmi = w / (m * m);
      if (Number.isFinite(bmi)) {
        setV((s) => ({ ...s, bmi: bmi.toFixed(1) }));
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [v.height_cm, v.weight_kg]);

  function exportJson() {
    const payload = { ...v, photo_name: photo?.name || null, exported_at: new Date().toISOString() };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'triage.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  function exportText() {
    const lines = Object.entries(v)
      .map(([k, val]) => `${k.replaceAll('_', ' ')}: ${val}`)
      .join('\n');
    const blob = new Blob([lines], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'triage.txt';
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Triage</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
      </div>

      <div>
        <div style={{ fontWeight: 950, fontSize: 20 }}>Triage</div>
        <div style={{ color: 'var(--dc-muted)', fontWeight: 800, marginTop: 4 }}>
          Vitals, BMI, and skin photo for quick assessment.
        </div>
      </div>

      <div className="dc-card" style={{ padding: 16 }}>
        <div className="dc-grid-2">
          <input className="dc-input" placeholder="Height (cm)" value={v.height_cm} onChange={(e) => setV((s) => ({ ...s, height_cm: e.target.value }))} />
          <input className="dc-input" placeholder="Weight (kg)" value={v.weight_kg} onChange={(e) => setV((s) => ({ ...s, weight_kg: e.target.value }))} />
          <input className="dc-input" placeholder="Temperature (°C)" value={v.temperature_c} onChange={(e) => setV((s) => ({ ...s, temperature_c: e.target.value }))} />
          <input className="dc-input" placeholder="BMI" value={v.bmi} readOnly />
          <input className="dc-input" placeholder="BP Sys" value={v.bp_sys} onChange={(e) => setV((s) => ({ ...s, bp_sys: e.target.value }))} />
          <input className="dc-input" placeholder="BP Dia" value={v.bp_dia} onChange={(e) => setV((s) => ({ ...s, bp_dia: e.target.value }))} />
          <input className="dc-input" placeholder="Pulse (bpm)" value={v.pulse_bpm} onChange={(e) => setV((s) => ({ ...s, pulse_bpm: e.target.value }))} />
          <input className="dc-input" placeholder="Resp (/min)" value={v.resp_min} onChange={(e) => setV((s) => ({ ...s, resp_min: e.target.value }))} />
          <input className="dc-input" placeholder="SpO2 (%)" value={v.spo2} onChange={(e) => setV((s) => ({ ...s, spo2: e.target.value }))} />
          <input className="dc-input" placeholder="Glucose (mg/dL)" value={v.glucose_mgdl} onChange={(e) => setV((s) => ({ ...s, glucose_mgdl: e.target.value }))} />
        </div>
        <textarea className="dc-input" rows={4} placeholder="Notes" value={v.notes} onChange={(e) => setV((s) => ({ ...s, notes: e.target.value }))} style={{ marginTop: 12 }} />

        <div style={{ display: 'flex', gap: 12, marginTop: 12, flexWrap: 'wrap' }}>
          <label className="dc-btn" style={{ display: 'inline-flex', alignItems: 'center', gap: 10, fontWeight: 950 }}>
            📷 Camera
            <input
              type="file"
              accept="image/*"
              capture="environment"
              style={{ display: 'none' }}
              onChange={(e) => setPhoto(e.target.files?.[0] || null)}
            />
          </label>
          <label className="dc-btn" style={{ display: 'inline-flex', alignItems: 'center', gap: 10, fontWeight: 950 }}>
            🖼️ Gallery
            <input type="file" accept="image/*" style={{ display: 'none' }} onChange={(e) => setPhoto(e.target.files?.[0] || null)} />
          </label>
        </div>

        {photo ? <div style={{ marginTop: 10, color: 'var(--dc-muted)', fontWeight: 800, fontSize: 12 }}>Selected: {photo.name}</div> : null}

        <div style={{ display: 'flex', gap: 12, marginTop: 14, flexWrap: 'wrap' }}>
          <button className="dc-btn dc-btn-primary" type="button" onClick={exportJson} style={{ fontWeight: 950 }}>
            ⤓ Export JSON
          </button>
          <button className="dc-btn dc-btn-primary" type="button" onClick={exportText} style={{ fontWeight: 950 }}>
            ⤓ Export text
          </button>
        </div>

        <div style={{ marginTop: 10, color: 'var(--dc-muted)', fontWeight: 800, fontSize: 12 }}>
          Next step: save this triage into the patient medical record offline + sync.
        </div>
      </div>
    </div>
  );
}

function Courses() {
  const [tab, setTab] = React.useState('education'); // education | courses | maintenance
  const [q, setQ] = React.useState('');
  const s = useApiCall(() => api.get(ApiPaths.coursesV1).then((r) => r.data), []);
  const itemsAll = React.useMemo(() => {
    const x = s.data;
    const arr = Array.isArray(x) ? x : x?.results || x?.data || [];
    return Array.isArray(arr) ? arr : [];
  }, [s.data]);
  const items = React.useMemo(() => {
    const qq = q.trim().toLowerCase();
    if (!qq) return itemsAll;
    return itemsAll.filter((c) => JSON.stringify(c || {}).toLowerCase().includes(qq));
  }, [itemsAll, q]);

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Courses</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
        <div className="dc-tabs" role="tablist" aria-label="Courses tabs">
          <button className="dc-tab" type="button" data-active={tab === 'education' ? 'true' : 'false'} onClick={() => setTab('education')}>
            <span aria-hidden="true">📖</span>
            Education
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'courses' ? 'true' : 'false'} onClick={() => setTab('courses')}>
            <span aria-hidden="true">🎓</span>
            Courses
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'maintenance' ? 'true' : 'false'} onClick={() => setTab('maintenance')}>
            <span aria-hidden="true">✅</span>
            Maintenance
          </button>
        </div>
      </div>

      {tab === 'maintenance' ? (
        <AnnualMaintenance />
      ) : tab === 'education' ? (
        <div className="dc-row" style={{ gap: 14 }}>
          <div style={{ fontWeight: 950, fontSize: 18 }}>Patient education (MedlinePlus)</div>
          <div className="dc-card" style={{ padding: 16 }}>
            <div style={{ display: 'flex', gap: 12 }}>
              <input className="dc-input" placeholder="Search topic" value={q} onChange={(e) => setQ(e.target.value)} />
              <button className="dc-btn dc-btn-primary" type="button" style={{ fontWeight: 950 }}>
                Search
              </button>
            </div>
            <div style={{ textAlign: 'center', padding: 34, color: 'var(--dc-muted)', fontWeight: 800 }}>
              Search to see education resources
            </div>
          </div>
        </div>
      ) : (
        <div className="dc-row" style={{ gap: 14 }}>
          <div style={{ fontWeight: 950, fontSize: 18 }}>Preventive care courses</div>
          <div style={{ color: 'var(--dc-muted)', fontWeight: 800 }}>Common topics patients need for prevention and wellness.</div>
          <div className="dc-card" style={{ padding: 14 }}>
            <input className="dc-input" placeholder="Search…" value={q} onChange={(e) => setQ(e.target.value)} />
          </div>

          {s.loading ? (
            <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
              Loading…
            </div>
          ) : s.error ? (
            <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
              {s.error}
            </div>
          ) : items.length === 0 ? (
            <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
              No courses returned.
            </div>
          ) : (
            <div className="dc-row" style={{ gap: 12 }}>
              {items.slice(0, 30).map((c, idx) => {
                const title = (c?.title || c?.name || 'Course').toString();
                const desc = (c?.description || c?.summary || '').toString();
                const mins = c?.minutes || c?.duration_minutes || c?.duration || '';
                const level = (c?.level || c?.difficulty || 'Beginner').toString();
                const tags = Array.isArray(c?.tags) ? c.tags : [];
                const resources = Array.isArray(c?.resources) ? c.resources : [];
                return (
                  <div key={c?.id || idx} className="dc-card" style={{ padding: 16 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                      <div>
                        <div style={{ fontWeight: 950, fontSize: 16 }}>{title}</div>
                        <div style={{ color: 'var(--dc-muted)', fontWeight: 800, marginTop: 6 }}>{level}</div>
                        <div style={{ color: 'var(--dc-muted)', fontSize: 13, marginTop: 6 }}>{desc}</div>
                      </div>
                      {mins ? (
                        <div className="dc-chip" data-active="true" style={{ cursor: 'default' }}>
                          {mins} min
                        </div>
                      ) : null}
                    </div>

                    {tags.length ? (
                      <div className="dc-chip-row" style={{ marginTop: 12 }}>
                        {tags.slice(0, 6).map((t) => (
                          <span key={t} className="dc-chip" style={{ cursor: 'default' }}>
                            {t}
                          </span>
                        ))}
                      </div>
                    ) : null}

                    {resources.length ? (
                      <div style={{ marginTop: 12 }}>
                        <div style={{ fontWeight: 950, marginBottom: 8 }}>Resources</div>
                        <div className="dc-chip-row">
                          {resources.slice(0, 4).map((r, rIdx) => (
                            r?.url ? (
                              <a key={r?.url || r?.title} className="dc-chip" href={r.url} target="_blank" rel="noreferrer">
                                {(r?.title || 'Link').toString()}
                              </a>
                            ) : (
                              <span key={`${r?.title || 'link'}-${rIdx}`} className="dc-chip" style={{ cursor: 'default', opacity: 0.7 }}>
                                {(r?.title || 'Link').toString()}
                              </span>
                            )
                          ))}
                        </div>
                      </div>
                    ) : null}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function AnnualMaintenance() {
  const AGE = [
    { key: '0-2', label: '0–2' },
    { key: '3-6', label: '3–6' },
    { key: '7-12', label: '7–12' },
    { key: '13-18', label: '13–18' },
    { key: '19-39', label: '19–39' },
    { key: '40-64', label: '40–64' },
    { key: '65+', label: '65+' },
  ];
  const [age, setAge] = React.useState('19-39');
  const plan = React.useMemo(() => maintenancePlan(age), [age]);

  function card(title, icon, bullets, links) {
    return (
      <div className="dc-card" style={{ padding: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
          <div className="dc-avatar" style={{ background: 'rgba(211,47,47,0.10)', color: 'var(--dc-primary-dark)' }}>
            {icon}
          </div>
          <div style={{ fontWeight: 950, fontSize: 16 }}>{title}</div>
        </div>
        <div style={{ display: 'grid', gap: 8 }}>
          {bullets.map((b) => (
            <div key={b} style={{ fontWeight: 700, color: 'var(--dc-text)' }}>
              • {b}
            </div>
          ))}
        </div>
        {links?.length ? (
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginTop: 12 }}>
            {links.map((l) => (
              <a key={l.href} className="dc-btn" href={l.href} target="_blank" rel="noreferrer" style={{ fontWeight: 900 }}>
                ↗ {l.label}
              </a>
            ))}
          </div>
        ) : null}
      </div>
    );
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-card" style={{ padding: 16, background: '#fff' }}>
        <div style={{ fontWeight: 950, fontSize: 18 }}>Annual maintenance checklist</div>
        <div style={{ color: 'var(--dc-muted)', fontWeight: 800, marginTop: 6 }}>
          Age-wise preventive care, vaccines, and exercise/PT/OT guidance.
        </div>
        <div className="dc-chip-row" style={{ marginTop: 12 }}>
          {AGE.map((a) => (
            <button key={a.key} type="button" className="dc-chip" data-active={age === a.key ? 'true' : 'false'} onClick={() => setAge(a.key)}>
              {a.label}
            </button>
          ))}
        </div>
      </div>

      {card('Preventive care', '🛡️', plan.preventive, [
        { label: 'USPSTF', href: 'https://www.uspreventiveservicestaskforce.org/uspstf/recommendation-topics' },
      ])}
      {card('Vaccines', '💉', plan.vaccines, [
        { label: 'CDC schedules', href: 'https://www.cdc.gov/vaccines/schedules/' },
      ])}

      <div className="dc-card" style={{ padding: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
          <div className="dc-avatar" style={{ background: 'rgba(211,47,47,0.10)', color: 'var(--dc-primary-dark)' }}>
            🏃
          </div>
          <div style={{ fontWeight: 950, fontSize: 16 }}>Exercise (home)</div>
        </div>
        <div className="dc-row" style={{ gap: 10 }}>
          {plan.exercises.map((e) => (
            <div key={e.title} className="dc-card" style={{ padding: 12, background: '#f8fafc' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <div className="dc-avatar" style={{ width: 36, height: 36, fontSize: 16 }}>
                  {e.icon}
                </div>
                <div>
                  <div style={{ fontWeight: 950 }}>{e.title}</div>
                  <div style={{ color: 'var(--dc-muted)', fontWeight: 800, fontSize: 13, marginTop: 2 }}>{e.body}</div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {card('PT / OT (when to consider)', '🦵', plan.ptot, [
        { label: 'ChoosePT', href: 'https://www.choosept.com/' },
        { label: 'AOTA', href: 'https://www.aota.org/consumers' },
      ])}

      <div className="dc-card" style={{ padding: 14, background: 'rgba(245, 158, 11, 0.10)' }}>
        <div style={{ fontWeight: 900 }}>
          Note: This is general guidance, not medical advice. Always follow your clinician’s recommendations.
        </div>
      </div>
    </div>
  );
}

function maintenancePlan(age) {
  if (age === '0-2') {
    return {
      preventive: ['Well-child visits & development screening', 'Sleep safety & nutrition guidance', 'Dental: first visit by 1 year'],
      vaccines: ['Routine childhood schedule (DTaP, IPV, Hib, PCV, MMR, Varicella, Hep A/B, Flu)'],
      exercises: [
        { icon: '👶', title: 'Tummy time', body: 'Supervised tummy time daily (as advised).' },
        { icon: '🧸', title: 'Active play', body: 'Daily movement and play.' },
      ],
      ptot: ['PT/OT if delayed milestones or feeding/posture concerns (clinician referral).'],
    };
  }
  if (age === '3-6') {
    return {
      preventive: ['Annual checkup; vision/hearing screening', 'Dental every 6 months; brushing & fluoride'],
      vaccines: ['Routine schedule + annual flu; catch-up as needed'],
      exercises: [
        { icon: '🏃', title: 'Play-based activity', body: '60 minutes active play most days.' },
        { icon: '⚽', title: 'Coordination', body: 'Jumping, hopping, ball play.' },
      ],
      ptot: ['PT/OT if balance/coordination delays or fine-motor concerns.'],
    };
  }
  if (age === '7-12') {
    return {
      preventive: ['Annual wellness visit; nutrition & sleep habits', 'Vision/hearing screening; dental every 6 months'],
      vaccines: ['Annual flu; school-age schedule'],
      exercises: [
        { icon: '🏀', title: 'Daily activity', body: '60 minutes/day moderate–vigorous activity.' },
        { icon: '🧘', title: 'Flexibility', body: 'Gentle stretching after activity.' },
      ],
      ptot: ['PT for recurrent sports injuries; OT for handwriting/fine-motor issues if needed.'],
    };
  }
  if (age === '13-18') {
    return {
      preventive: ['Annual visit; mental health screening', 'Sleep/nutrition; sexual health counseling as appropriate'],
      vaccines: ['HPV, Tdap, meningococcal; annual flu; catch-up'],
      exercises: [
        { icon: '🏋️', title: 'Strength', body: '2–3 days/week strength training (safe form).' },
        { icon: '🏃', title: 'Cardio', body: '150+ min/week moderate activity (or equivalent).' },
      ],
      ptot: ['PT for sports injuries; OT for ergonomics/hand issues.'],
    };
  }
  if (age === '40-64') {
    return {
      preventive: ['Annual checkup: BP, diabetes risk, cholesterol (as advised)', 'Cancer screening per guidelines (colon; breast/cervix/prostate as appropriate)'],
      vaccines: ['Annual flu; COVID boosters as advised; shingles at 50+; Tdap every 10 years'],
      exercises: [
        { icon: '🚶', title: 'Walking', body: '30 min brisk walk most days.' },
        { icon: '🏋️', title: 'Strength', body: '2 days/week full-body strength.' },
        { icon: '🧘', title: 'Mobility', body: 'Daily mobility/stretching 5–10 minutes.' },
      ],
      ptot: ['PT for back/neck/knee pain; OT for ergonomics or hand arthritis.'],
    };
  }
  if (age === '65+') {
    return {
      preventive: ['Annual visit; fall risk + vision/hearing assessment', 'Medication review; bone health discussion'],
      vaccines: ['Annual flu; pneumococcal as advised; shingles; COVID boosters as advised'],
      exercises: [
        { icon: '⚖️', title: 'Balance', body: 'Balance exercises 3+ days/week (safe).'},
        { icon: '🚶', title: 'Walking', body: 'Regular walking as tolerated.' },
        { icon: '🏋️', title: 'Strength', body: '2 days/week strength (safe/supervised).'},
      ],
      ptot: ['PT for balance/gait; OT for home safety and daily activities.'],
    };
  }
  return {
    preventive: ['Annual checkup: BP, weight, mental health, lifestyle review', 'Screenings based on risk factors'],
    vaccines: ['Annual flu; COVID boosters as advised; Tdap every 10 years'],
    exercises: [
      { icon: '🚶', title: 'Walking', body: '150 minutes/week moderate activity.' },
      { icon: '🏋️', title: 'Strength', body: '2 days/week strength training.' },
    ],
    ptot: ['PT/OT if pain, mobility issues, or recovery after injury/surgery.'],
  };
}

function AiAssistant() {
  const [msg, setMsg] = React.useState('');
  const [busy, setBusy] = React.useState(false);
  const [history, setHistory] = React.useState([
    {
      role: 'assistant',
      text:
        "Hi! I'm your AI medical assistant.\n\nI can help with basic symptoms and next steps, but I'm not a doctor.\nIf you have severe symptoms (trouble breathing, chest pain, fainting, severe bleeding, stroke signs), call emergency services immediately.",
    },
  ]);

  const quick = [
    'Headache',
    'Chest pain',
    'Fever',
    'Nausea',
    'Breathing issues',
    'Dental pain',
    'Bleeding',
    'Injury',
    'Fatigue',
    'Medication help',
  ];

  async function send() {
    const t = msg.trim();
    if (!t || busy) return;
    setBusy(true);
    setHistory((h) => [...h, { role: 'user', text: t }]);
    setMsg('');
    try {
      const { data } = await api.post(ApiPaths.medicalRecordsAiAssist, { query: t });
      const reply =
        (data && (data.message || data.detail || data.answer || data.response)) ||
        (typeof data === 'string' ? data : '') ||
        JSON.stringify(data, null, 2);
      setHistory((h) => [...h, { role: 'assistant', text: reply.toString() }]);
    } catch (err) {
      const serverMsg =
        err?.response?.data?.message ||
        err?.response?.data?.detail ||
        (typeof err?.response?.data === 'string' ? err.response.data : '') ||
        err?.message ||
        'AI request failed.';
      setHistory((h) => [...h, { role: 'assistant', text: `Error: ${serverMsg}` }]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>AI assistant</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
      </div>

      <div className="dc-card" style={{ background: '#fff6f6' }}>
        <div style={{ color: 'var(--dc-primary-dark)', fontWeight: 900 }}>
          Not for emergencies. If severe symptoms, call local emergency services.
        </div>
      </div>

      <div className="dc-chip-row">
        {quick.map((t) => (
          <button key={t} type="button" className="dc-chip" onClick={() => setMsg(t)}>
            {t}
          </button>
        ))}
      </div>

      <div className="dc-card" style={{ padding: 16 }}>
        <div className="dc-row" style={{ gap: 10 }}>
          {history.slice(-6).map((m, idx) => (
            <div key={idx} style={{ padding: 12, borderRadius: 14, background: m.role === 'user' ? 'rgba(211,47,47,0.08)' : '#f3f4f6' }}>
              <div style={{ whiteSpace: 'pre-wrap', fontWeight: 800, color: m.role === 'user' ? 'var(--dc-primary-dark)' : 'var(--dc-text)' }}>
                {m.text}
              </div>
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 10, marginTop: 12 }}>
          <input
            className="dc-input"
            placeholder="Send a message"
            value={msg}
            onChange={(e) => setMsg(e.target.value)}
            onKeyDown={(e) => (e.key === 'Enter' ? send() : null)}
            disabled={busy}
          />
          <button className="dc-btn dc-btn-primary" type="button" onClick={send} disabled={busy} style={{ fontWeight: 950 }}>
            {busy ? '…' : '▶'}
          </button>
        </div>
      </div>
    </div>
  );
}

function SoapNotes() {
  const [raw, setRaw] = React.useState('');
  const [soap, setSoap] = React.useState({ s: '', o: '', a: '', p: '' });
  const [ai, setAi] = React.useState({ loading: false, error: '' });

  function unwrapAiAssist(data) {
    if (data && data.status === 'success' && data.data && typeof data.data === 'object') {
      return data.data;
    }
    return data;
  }

  function parseSoapFromText(answer) {
    if (!answer || typeof answer !== 'string') return null;
    try {
      const t = answer.trim();
      const start = t.indexOf('{');
      const end = t.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      const m = JSON.parse(t.slice(start, end + 1));
      if (!m || typeof m !== 'object') return null;
      return {
        s: String(m.subjective ?? ''),
        o: String(m.objective ?? ''),
        a: String(m.assessment ?? ''),
        p: String(m.plan ?? ''),
      };
    } catch {
      return null;
    }
  }

  async function aiAssist() {
    const text = raw.trim();
    if (!text) return;
    setAi({ loading: true, error: '' });
    try {
      const prompt = `Convert the following clinician dictation into a SOAP note.
Return STRICT JSON with keys: subjective, objective, assessment, plan.
No markdown, no extra keys.

DICTATION:\n${text}`;
      const { data } = await api.post(ApiPaths.medicalRecordsAiAssist, {
        query: prompt,
        kind: 'soap',
      });
      const inner = unwrapAiAssist(data);
      const sk = inner?.soap;
      if (sk && typeof sk === 'object') {
        setSoap({
          s: String(sk.subjective ?? ''),
          o: String(sk.objective ?? ''),
          a: String(sk.assessment ?? ''),
          p: String(sk.plan ?? ''),
        });
      } else {
        const answer = String(inner?.answer ?? inner?.summary ?? '').trim();
        const parsed = parseSoapFromText(answer);
        if (parsed) setSoap(parsed);
        else setSoap({ s: answer, o: '', a: '', p: '' });
      }
      setAi({ loading: false, error: '' });
    } catch (err) {
      const msg = err?.response?.data?.message || err?.response?.data?.detail || 'AI Assist failed';
      setAi({ loading: false, error: msg.toString() });
    }
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Doctor notes (SOAP)</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
      </div>

      <div>
        <div style={{ fontWeight: 950, fontSize: 20 }}>Doctor note (SOAP)</div>
        <div style={{ color: 'var(--dc-muted)', fontWeight: 800, marginTop: 4 }}>
          Dictate or paste notes, then use AI Assist to structure into SOAP.
        </div>
      </div>

      <div className="dc-card" style={{ padding: 16 }}>
        <textarea className="dc-input" rows={5} placeholder="Dictation / free text" value={raw} onChange={(e) => setRaw(e.target.value)} />
        <div style={{ display: 'flex', gap: 12, marginTop: 12, flexWrap: 'wrap' }}>
          <button className="dc-btn dc-btn-primary" type="button" onClick={aiAssist} disabled={ai.loading} style={{ flex: 1, minWidth: 220, fontWeight: 950 }}>
            ✨ AI Assist SOAP
          </button>
          <button className="dc-btn" type="button" onClick={() => navigator.clipboard?.writeText(JSON.stringify({ raw, soap }, null, 2))} style={{ minWidth: 120, fontWeight: 950 }}>
            📋 Copy
          </button>
        </div>
        {ai.error ? <div style={{ marginTop: 10, color: 'var(--dc-danger)', fontWeight: 900 }}>{ai.error}</div> : null}
      </div>

      <div className="dc-row" style={{ gap: 12 }}>
        <textarea className="dc-input" rows={3} placeholder="Subjective (S)" value={soap.s} onChange={(e) => setSoap((s) => ({ ...s, s: e.target.value }))} />
        <textarea className="dc-input" rows={3} placeholder="Objective (O)" value={soap.o} onChange={(e) => setSoap((s) => ({ ...s, o: e.target.value }))} />
        <textarea className="dc-input" rows={3} placeholder="Assessment (A)" value={soap.a} onChange={(e) => setSoap((s) => ({ ...s, a: e.target.value }))} />
        <textarea className="dc-input" rows={3} placeholder="Plan (P)" value={soap.p} onChange={(e) => setSoap((s) => ({ ...s, p: e.target.value }))} />
      </div>
    </div>
  );
}

function DoctorVisit() {
  const [latest, setLatest] = React.useState({ loading: true, error: '', record: null });
  const [wa, setWa] = React.useState({ loading: true, number: '' });
  const tools = [
    { label: 'Video', icon: '🎥' },
    { label: 'Audio', icon: '🎧' },
    { label: 'Upload', icon: '📎' },
    { label: 'Import', icon: '⬇️' },
    { label: 'Export PDF', icon: '🧾' },
    { label: 'Export text', icon: '📝' },
  ];

  async function refreshLatest() {
    setLatest({ loading: true, error: '', record: null });
    try {
      const { data } = await api.get(ApiPaths.medicalRecords);
      const items = Array.isArray(data) ? data : data?.results || data?.data || [];
      const first = Array.isArray(items) ? items[0] : null;
      setLatest({ loading: false, error: '', record: first || null });
    } catch (err) {
      const msg = err?.response?.data?.message || err?.response?.data?.detail || err?.message || 'Failed to load';
      setLatest({ loading: false, error: msg.toString(), record: null });
    }
  }

  React.useEffect(() => {
    refreshLatest();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const { data } = await api.get(ApiPaths.settingsGeneralKey('whatsapp_support_number'));
        const n = (data?.data?.value ?? data?.value ?? '').toString().trim();
        if (!alive) return;
        setWa({ loading: false, number: n });
      } catch {
        if (!alive) return;
        setWa({ loading: false, number: '' });
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const waHref = React.useMemo(() => {
    const n = (wa.number || '').replace(/\s+/g, '');
    if (!n) return '';
    const num = n.replace(/^\+/, '');
    const msg = encodeURIComponent('Hello Doctor On Call support. I need assistance.');
    return `https://wa.me/${num}?text=${msg}`;
  }, [wa.number]);

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Doctor visit</h2>
          <button className="dc-btn" type="button" onClick={refreshLatest} style={{ fontWeight: 950 }}>
            ↻
          </button>
        </div>
      </div>

      <div className="dc-card" style={{ padding: 16 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
          <div>
            <div style={{ fontWeight: 950 }}>Latest local medical record</div>
            <div style={{ color: 'var(--dc-muted)', fontWeight: 800, fontSize: 13, marginTop: 4 }}>
              {latest.loading
                ? 'Loading…'
                : latest.error
                  ? latest.error
                  : latest.record
                    ? `${(latest.record?.title || latest.record?.type || 'Record').toString()} · ${(latest.record?.created_at || latest.record?.date || '').toString()}`
                    : 'No local record found yet. Create one from Medical records.'}
            </div>
          </div>
          <button className="dc-btn" type="button" onClick={refreshLatest} style={{ fontWeight: 950 }}>
            Refresh
          </button>
        </div>
      </div>

      <div className="dc-card" style={{ padding: 16 }}>
        <div style={{ fontWeight: 950, marginBottom: 12 }}>Visit tools</div>
        <div className="dc-grid-2">
          {tools.map((t) => (
            <button key={t.label} className="dc-btn dc-btn-primary" type="button" style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}>
              {t.icon} {t.label}
            </button>
          ))}
        </div>
      </div>

      {wa.loading ? null : waHref ? (
        <a
          className="dc-btn dc-btn-primary"
          href={waHref}
          target="_blank"
          rel="noreferrer"
          style={{ padding: 14, borderRadius: 16, fontWeight: 950, textAlign: 'center' }}
        >
          WhatsApp Support
        </a>
      ) : null}
    </div>
  );
}

function Discovery() {
  const [tab, setTab] = React.useState('countries'); // countries | specialities | providers
  const [q, setQ] = React.useState('');
  const countries = useApiCall(() => api.get(ApiPaths.countries).then((r) => r.data), []);
  const specialities = useApiCall(() => api.get(ApiPaths.specialities).then((r) => r.data), []);
  const providers = useApiCall(() => api.get(ApiPaths.providers).then((r) => r.data), []);

  const list = (x) => (Array.isArray(x) ? x : x?.results || x?.data || []);

  const items = React.useMemo(() => {
    const qq = q.trim().toLowerCase();
    const src =
      tab === 'countries'
        ? list(countries.data)
        : tab === 'specialities'
          ? list(specialities.data)
          : list(providers.data);
    if (!qq) return src;
    return src.filter((m) => JSON.stringify(m || {}).toLowerCase().includes(qq));
  }, [tab, q, countries.data, specialities.data, providers.data]);

  const loading =
    tab === 'countries' ? countries.loading : tab === 'specialities' ? specialities.loading : providers.loading;
  const error =
    tab === 'countries' ? countries.error : tab === 'specialities' ? specialities.error : providers.error;

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Countries · Specialities · Providers</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
        <div className="dc-tabs" role="tablist" aria-label="Discovery tabs">
          <button className="dc-tab" type="button" data-active={tab === 'countries' ? 'true' : 'false'} onClick={() => setTab('countries')}>
            <span aria-hidden="true">🌐</span>
            Countries
          </button>
          <button
            className="dc-tab"
            type="button"
            data-active={tab === 'specialities' ? 'true' : 'false'}
            onClick={() => setTab('specialities')}
          >
            <span aria-hidden="true">➕</span>
            Specialities
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'providers' ? 'true' : 'false'} onClick={() => setTab('providers')}>
            <span aria-hidden="true">👥</span>
            Providers
          </button>
        </div>
      </div>

      <div className="dc-card" style={{ padding: 14 }}>
        <input className="dc-input" placeholder="Search…" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>

      {loading ? (
        <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
          Loading…
        </div>
      ) : error ? (
        <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
          {error}
        </div>
      ) : (
        <div className="dc-list">
          {items.slice(0, 60).map((m, idx) => {
            const isCountries = tab === 'countries';
            const isSpecs = tab === 'specialities';
            const isProviders = tab === 'providers';

            const title = isCountries
              ? (m?.country_name || m?.name || 'Country')
              : isSpecs
                ? (m?.speciality_name || m?.name || 'Speciality')
                : (m?.full_name || m?.name || 'Provider');
            const sub = isCountries
              ? (m?.country_code || m?.code || '').toString()
              : isSpecs
                ? ((m?.country || m?.country_id || '')?.toString() || '')
                : `${(m?.email || '').toString()}${m?.status ? ` · ${m.status}` : ''}`;

            return (
              <div className="dc-list-row" key={m?.id || `${tab}-${idx}`}>
                <div className="dc-list-left">
                  <div className="dc-avatar">{isCountries ? '🌐' : isSpecs ? '➕' : (title || 'P').toString().slice(0, 1).toUpperCase()}</div>
                  <div className="dc-list-text">
                    <div className="dc-list-title">{title?.toString()}</div>
                    <div className="dc-list-sub">{sub}</div>
                  </div>
                </div>
                <div className="dc-chevron">›</div>
              </div>
            );
          })}
        </div>
      )}
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
  const [tab, setTab] = React.useState('patients'); // patients | physicians | schedule
  const patients = useApiCall(() => api.get(ApiPaths.patients).then((r) => r.data), []);
  const providers = useApiCall(() => api.get(ApiPaths.providers).then((r) => r.data), []);
  const appts = useApiCall(() => api.get(ApiPaths.allAppointments).then((r) => r.data), []);

  const list = (x) => (Array.isArray(x) ? x : x?.results || x?.data || []);
  const items =
    tab === 'patients' ? list(patients.data) : tab === 'physicians' ? list(providers.data) : list(appts.data);
  const loading = tab === 'patients' ? patients.loading : tab === 'physicians' ? providers.loading : appts.loading;
  const error = tab === 'patients' ? patients.error : tab === 'physicians' ? providers.error : appts.error;

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Patients · Providers</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
        <div className="dc-tabs" role="tablist" aria-label="Patients/providers tabs">
          <button className="dc-tab" type="button" data-active={tab === 'patients' ? 'true' : 'false'} onClick={() => setTab('patients')}>
            <span aria-hidden="true">👤</span>
            Patients
          </button>
          <button
            className="dc-tab"
            type="button"
            data-active={tab === 'physicians' ? 'true' : 'false'}
            onClick={() => setTab('physicians')}
          >
            <span aria-hidden="true">🩺</span>
            Physicians
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'schedule' ? 'true' : 'false'} onClick={() => setTab('schedule')}>
            <span aria-hidden="true">📅</span>
            Schedule
          </button>
        </div>
      </div>

      {loading ? (
        <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
          Loading…
        </div>
      ) : error ? (
        <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
          {error}
        </div>
      ) : items.length === 0 ? (
        <div className="dc-card" style={{ color: 'var(--dc-muted)', textAlign: 'center', padding: 40 }}>
          No appointments yet
        </div>
      ) : (
        <div className="dc-list">
          {items.slice(0, 80).map((m, idx) => {
            if (tab === 'patients') {
              const title = (m?.full_name || m?.name || m?.username || 'Patient').toString();
              const sub = (m?.email || '').toString();
              return (
                <div className="dc-list-row" key={m?.id || `p-${idx}`}>
                  <div className="dc-list-left">
                    <div className="dc-avatar">👤</div>
                    <div className="dc-list-text">
                      <div className="dc-list-title">{title}</div>
                      <div className="dc-list-sub">{sub}</div>
                    </div>
                  </div>
                  <div className="dc-chevron">›</div>
                </div>
              );
            }
            if (tab === 'physicians') {
              const title = (m?.full_name || m?.name || 'Provider').toString();
              const sub = `${(m?.email || '').toString()}${m?.status ? ` · ${m.status}` : ''}`;
              return (
                <div className="dc-list-row" key={m?.id || `d-${idx}`}>
                  <div className="dc-list-left">
                    <div className="dc-avatar">{title.slice(0, 1).toUpperCase()}</div>
                    <div className="dc-list-text">
                      <div className="dc-list-title">{title}</div>
                      <div className="dc-list-sub">{sub}</div>
                    </div>
                  </div>
                  <div className="dc-chevron">›</div>
                </div>
              );
            }

            const title = (m?.title || m?.reason || 'Appointment').toString();
            const sub = (m?.date || m?.scheduled_at || m?.created_at || '').toString();
            return (
              <div className="dc-list-row" key={m?.id || `a-${idx}`}>
                <div className="dc-list-left">
                  <div className="dc-avatar">📅</div>
                  <div className="dc-list-text">
                    <div className="dc-list-title">{title}</div>
                    <div className="dc-list-sub">{sub}</div>
                  </div>
                </div>
                <div className="dc-chevron">›</div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function Settings({ isAdmin }) {
  const health = useApiCall(() => api.get(ApiPaths.health).then((r) => r.status), []);
  const me = useApiCall(() => api.get(ApiPaths.docOnCallMe).then((r) => r.data), []);
  const repl = useApiCall(() => api.get(ApiPaths.replicateToken).then((r) => r.data), []);
  const [wa, setWa] = React.useState({ loading: false, value: '', saved: '', error: '' });

  React.useEffect(() => {
    let alive = true;
    if (!isAdmin) return () => {};
    (async () => {
      try {
        const { data } = await api.get(ApiPaths.settingsGeneralKey('whatsapp_support_number'));
        const v = (data?.data?.value ?? data?.value ?? '').toString();
        if (!alive) return;
        setWa((s) => ({ ...s, value: v, saved: v, error: '' }));
      } catch {
        if (!alive) return;
        setWa((s) => ({ ...s, error: '' }));
      }
    })();
    return () => {
      alive = false;
    };
  }, [isAdmin]);

  async function saveWhatsapp() {
    const v = (wa.value || '').trim();
    setWa((s) => ({ ...s, loading: true, error: '' }));
    try {
      const { data } = await api.post(ApiPaths.settingsGeneral, { key: 'whatsapp_support_number', value: v });
      const saved = (data?.data?.value ?? data?.value ?? v).toString();
      setWa((s) => ({ ...s, loading: false, saved, value: saved, error: '' }));
    } catch (err) {
      const msg = err?.response?.data?.message || err?.response?.data?.detail || 'Failed to save';
      setWa((s) => ({ ...s, loading: false, error: msg.toString() }));
    }
  }

  const roleLabel = me.loading
    ? '…'
    : me.error
      ? 'Failed'
      : `OK (role: ${(me.data?.data?.role ?? me.data?.role ?? 'unknown').toString()})`;

  const replLabel = repl.loading
    ? '…'
    : repl.error
      ? 'Not configured'
      : (repl.data?.configured === true || repl.data?.data?.configured === true)
        ? 'Configured'
        : 'Not configured';

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Settings</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
      </div>

      {isAdmin ? <div style={{ fontWeight: 950, fontSize: 20 }}>API connections</div> : null}

      {isAdmin ? (
        <div className="dc-list">
          <div className="dc-list-row">
            <div className="dc-list-left">
              <div className="dc-avatar">🔗</div>
              <div className="dc-list-text">
                <div className="dc-list-title">API base URL</div>
                <div className="dc-list-sub">{apiBaseUrl}</div>
              </div>
            </div>
          </div>

          <div className="dc-list-row">
            <div className="dc-list-left">
              <div className="dc-avatar">✅</div>
              <div className="dc-list-text">
                <div className="dc-list-title">Backend health</div>
                <div className="dc-list-sub">
                  {health.loading ? 'Checking…' : health.error ? 'Not reachable' : 'Connected'}
                </div>
              </div>
            </div>
          </div>

          <div className="dc-list-row">
            <div className="dc-list-left">
              <div className="dc-avatar">👤</div>
              <div className="dc-list-text">
                <div className="dc-list-title">Role endpoint</div>
                <div className="dc-list-sub">{roleLabel}</div>
              </div>
            </div>
          </div>

          <div className="dc-list-row">
            <div className="dc-list-left">
              <div className="dc-avatar">🤖</div>
              <div className="dc-list-text">
                <div className="dc-list-title">AI provider (Replicate)</div>
                <div className="dc-list-sub">{replLabel}</div>
              </div>
            </div>
          </div>
        </div>
      ) : (
        <div className="dc-card" style={{ color: 'var(--dc-muted)', fontWeight: 800 }}>
          Admin-only settings are hidden on this account.
        </div>
      )}

      {isAdmin ? (
        <div className="dc-row" style={{ gap: 10 }}>
          <div style={{ fontWeight: 950, fontSize: 20 }}>Administration</div>
          <Link className="dc-list-row" to="/shell/16">
            <div className="dc-list-left">
              <div className="dc-avatar">🛡️</div>
              <div className="dc-list-text">
                <div className="dc-list-title">Admin hub</div>
                <div className="dc-list-sub">Pending approvals, providers, patients, appointments</div>
              </div>
            </div>
            <div className="dc-chevron">›</div>
          </Link>
          <div style={{ color: 'var(--dc-muted)', fontSize: 12, fontWeight: 800 }}>
            Pull down to refresh status.
          </div>
        </div>
      ) : null}

      {isAdmin ? (
        <div className="dc-row" style={{ gap: 10 }}>
          <div style={{ fontWeight: 950, fontSize: 20 }}>Support</div>
          <div className="dc-card" style={{ padding: 16 }}>
            <div style={{ fontWeight: 950, marginBottom: 8 }}>WhatsApp support number</div>
            <div style={{ color: 'var(--dc-muted)', fontWeight: 800, fontSize: 13, marginBottom: 10 }}>
              Use E.164 format, e.g. +14155552671 (no spaces).
            </div>
            <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
              <input
                className="dc-input"
                value={wa.value}
                onChange={(e) => setWa((s) => ({ ...s, value: e.target.value }))}
                placeholder="+14155552671"
                style={{ flex: 1, minWidth: 240 }}
              />
              <button className="dc-btn dc-btn-primary" type="button" onClick={saveWhatsapp} disabled={wa.loading} style={{ fontWeight: 950 }}>
                {wa.loading ? 'Saving…' : 'Save'}
              </button>
            </div>
            {wa.error ? <div style={{ marginTop: 10, color: 'var(--dc-danger)', fontWeight: 900 }}>{wa.error}</div> : null}
            {wa.saved ? (
              <div style={{ marginTop: 10, color: 'var(--dc-muted)', fontWeight: 800, fontSize: 12 }}>
                Saved: {wa.saved}
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  );
}

function ChangePassword() {
  const [form, setForm] = React.useState({ current: '', next: '', confirm: '', show: false });
  const [state, setState] = React.useState({ loading: false, error: '', ok: '' });

  async function submit(e) {
    e.preventDefault();
    setState({ loading: true, error: '', ok: '' });
    if (form.next !== form.confirm) {
      setState({ loading: false, error: 'Confirm password does not match.', ok: '' });
      return;
    }
    try {
      // Backend currently only accepts `new_password`. UI shows current/confirm for parity with Flutter.
      await api.post(ApiPaths.changePassword, { new_password: form.next });
      setState({ loading: false, error: '', ok: 'Password updated.' });
      setForm({ current: '', next: '', confirm: '', show: false });
    } catch (err) {
      const server =
        err?.response?.data?.message ||
        err?.response?.data?.detail ||
        (err?.response?.data?.errors ? JSON.stringify(err.response.data.errors) : '') ||
        '';
      setState({ loading: false, error: server || 'Failed', ok: '' });
    }
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Change password</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
      </div>

      <div className="dc-card" style={{ padding: 0, overflow: 'hidden' }}>
        <div className="dc-hero" style={{ borderRadius: 0, padding: 18 }}>
          <div style={{ fontWeight: 950, fontSize: 20 }}>Change Password</div>
          <div style={{ opacity: 0.9, fontWeight: 800, fontSize: 13, marginTop: 6 }}>
            Update your password to keep your account secure
          </div>
        </div>

        <form className="dc-row" style={{ padding: 16 }} onSubmit={submit}>
          <label className="dc-row" style={{ gap: 6 }}>
            <div style={{ fontSize: 13, fontWeight: 900 }}>Current Password</div>
            <input
              className="dc-input"
              type={form.show ? 'text' : 'password'}
              value={form.current}
              onChange={(e) => setForm((s) => ({ ...s, current: e.target.value }))}
              placeholder="Current Password"
            />
          </label>

          <label className="dc-row" style={{ gap: 6 }}>
            <div style={{ fontSize: 13, fontWeight: 900 }}>New Password</div>
            <input
              className="dc-input"
              type={form.show ? 'text' : 'password'}
              value={form.next}
              onChange={(e) => setForm((s) => ({ ...s, next: e.target.value }))}
              placeholder="New Password"
              required
            />
            <div style={{ color: 'var(--dc-muted)', fontSize: 12, fontWeight: 800 }}>Minimum 8 characters</div>
          </label>

          <label className="dc-row" style={{ gap: 6 }}>
            <div style={{ fontSize: 13, fontWeight: 900 }}>Confirm Password</div>
            <input
              className="dc-input"
              type={form.show ? 'text' : 'password'}
              value={form.confirm}
              onChange={(e) => setForm((s) => ({ ...s, confirm: e.target.value }))}
              placeholder="Confirm New Password"
              required
            />
          </label>

          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, fontWeight: 900 }}>
            <input type="checkbox" checked={form.show} onChange={(e) => setForm((s) => ({ ...s, show: e.target.checked }))} />
            Show passwords
          </label>

          <div
            className="dc-card"
            style={{
              background: '#f7efe2',
              borderColor: 'rgba(245, 158, 11, 0.25)',
              padding: 14,
            }}
          >
            <div style={{ fontWeight: 950, marginBottom: 8 }}>Password Requirements</div>
            <div style={{ color: 'rgba(17,24,39,0.8)', fontWeight: 700, fontSize: 13, display: 'grid', gap: 6 }}>
              <div>- At least 8 characters</div>
              <div>- Contains a number</div>
              <div>- Contains uppercase & lowercase</div>
            </div>
          </div>

          {state.error ? <div style={{ color: 'var(--dc-danger)', fontWeight: 900, fontSize: 13 }}>{state.error}</div> : null}
          {state.ok ? <div style={{ color: 'var(--dc-primary)', fontWeight: 950, fontSize: 13 }}>{state.ok}</div> : null}

          <button className="dc-btn dc-btn-primary" disabled={state.loading} style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}>
            {state.loading ? 'Updating…' : 'Update Password'}
          </button>
        </form>
      </div>
    </div>
  );
}

function ClientHub() {
  const [tab, setTab] = React.useState('home'); // home | profile | plan
  const me = useApiCall(() => api.get(ApiPaths.docOnCallMe).then((r) => r.data), []);
  const appts = useApiCall(() => api.get(ApiPaths.myAppointments).then((r) => r.data), []);
  const invoices = useApiCall(() => api.get(ApiPaths.invoices).then((r) => r.data), []);
  const vitals = useApiCall(() => api.get(ApiPaths.vitals).then((r) => r.data), []);
  const user = me.data?.data?.user || me.data?.user || {};
  const fullName = (user?.full_name || user?.username || 'User').toString();
  const email = (user?.email || '').toString();

  const list = (x) => (Array.isArray(x) ? x : x?.results || x?.data || x?.appointments || x?.invoices || x?.items || []);
  const apptCount = list(appts.data).length;
  const invCount = list(invoices.data).length;
  const vitalsNote =
    (typeof vitals.data?.note === 'string' && vitals.data.note) || (typeof vitals.data?.data?.note === 'string' && vitals.data.data.note) || '';

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Client (home · profile · plan)</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
        <div className="dc-tabs" role="tablist" aria-label="Client hub tabs">
          <button className="dc-tab" type="button" data-active={tab === 'home' ? 'true' : 'false'} onClick={() => setTab('home')}>
            <span aria-hidden="true">🏠</span>
            Home
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'profile' ? 'true' : 'false'} onClick={() => setTab('profile')}>
            <span aria-hidden="true">👤</span>
            Profile
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'plan' ? 'true' : 'false'} onClick={() => setTab('plan')}>
            <span aria-hidden="true">💳</span>
            Plan
          </button>
        </div>
      </div>

      {me.loading ? (
        <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
          Loading…
        </div>
      ) : me.error ? (
        <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
          {me.error}
        </div>
      ) : tab === 'profile' ? (
        <div className="dc-row" style={{ gap: 14 }}>
          <div className="dc-card" style={{ padding: 18, textAlign: 'center' }}>
            <div className="dc-avatar" style={{ width: 92, height: 92, margin: '0 auto', fontSize: 34 }}>
              👤
            </div>
            <div style={{ fontWeight: 950, fontSize: 22, marginTop: 10 }}>{fullName}</div>
            <div style={{ color: 'var(--dc-muted)', fontWeight: 800, marginTop: 4 }}>{email}</div>
          </div>

          <div className="dc-list">
            <div className="dc-list-row">
              <div className="dc-list-left">
                <div className="dc-avatar">🪪</div>
                <div className="dc-list-text">
                  <div className="dc-list-sub">Full Name</div>
                  <div className="dc-list-title">{fullName}</div>
                </div>
              </div>
            </div>
            <div className="dc-list-row">
              <div className="dc-list-left">
                <div className="dc-avatar">✉️</div>
                <div className="dc-list-text">
                  <div className="dc-list-sub">Email</div>
                  <div className="dc-list-title">{email || '—'}</div>
                </div>
              </div>
            </div>
            <div className="dc-list-row">
              <div className="dc-list-left">
                <div className="dc-avatar">📞</div>
                <div className="dc-list-text">
                  <div className="dc-list-sub">Phone</div>
                  <div className="dc-list-title">—</div>
                </div>
              </div>
            </div>
            <div className="dc-list-row">
              <div className="dc-list-left">
                <div className="dc-avatar">📍</div>
                <div className="dc-list-text">
                  <div className="dc-list-sub">Address</div>
                  <div className="dc-list-title">—</div>
                </div>
              </div>
            </div>
            <div className="dc-list-row">
              <div className="dc-list-left">
                <div className="dc-avatar">📅</div>
                <div className="dc-list-text">
                  <div className="dc-list-sub">Date of Birth</div>
                  <div className="dc-list-title">—</div>
                </div>
              </div>
            </div>
          </div>

          <button className="dc-btn dc-btn-primary" type="button" style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}>
            ✎ Edit Profile
          </button>
        </div>
      ) : tab === 'plan' ? (
        <div className="dc-row" style={{ gap: 14 }}>
          <div className="dc-hero" style={{ padding: 18 }}>
            <div style={{ opacity: 0.9, fontWeight: 900 }}>Current Plan</div>
            <div style={{ fontWeight: 950, fontSize: 32, marginTop: 6 }}>Premium</div>
            <div style={{ opacity: 0.9, fontWeight: 900, marginTop: 2 }}>$49/month</div>
            <div style={{ marginTop: 10, display: 'grid', gap: 6, fontWeight: 900, opacity: 0.95 }}>
              <div>✓ Up to 15 Appointments/month</div>
              <div>✓ AI Assistant Access</div>
            </div>
            <div className="dc-chip" style={{ marginTop: 12, cursor: 'default', display: 'inline-flex' }} data-active="true">
              Active until Dec 31, 2026
            </div>
          </div>

          <div style={{ fontWeight: 950, fontSize: 18 }}>Available Plans</div>
          <div className="dc-row" style={{ gap: 12 }}>
            <div className="dc-card" style={{ padding: 18 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 }}>
                <div style={{ fontWeight: 950, fontSize: 18 }}>Basic</div>
                <div style={{ color: 'var(--dc-muted)', fontWeight: 900 }}>Free</div>
              </div>
              <div style={{ fontWeight: 950, fontSize: 26, color: 'var(--dc-primary)', marginTop: 6 }}>$5/month</div>
              <div style={{ marginTop: 10, display: 'grid', gap: 6, fontWeight: 900, color: 'rgba(17,24,39,0.8)' }}>
                <div>✓ 1 Visit/month</div>
                <div>✓ Basic Support</div>
              </div>
            </div>

            <div className="dc-card" style={{ padding: 18 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 }}>
                <div style={{ fontWeight: 950, fontSize: 18 }}>Pro</div>
                <div className="dc-chip" data-active="true" style={{ cursor: 'default' }}>
                  Popular
                </div>
              </div>
              <div style={{ fontWeight: 950, fontSize: 26, color: 'var(--dc-primary)', marginTop: 6 }}>$30/month</div>
              <div style={{ marginTop: 10, display: 'grid', gap: 6, fontWeight: 900, color: 'rgba(17,24,39,0.8)' }}>
                <div>✓ 3 Visits/month</div>
                <div>✓ Priority Support</div>
              </div>
            </div>

            <div className="dc-card" style={{ padding: 18 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 12 }}>
                <div style={{ fontWeight: 950, fontSize: 18 }}>Enterprise</div>
                <div className="dc-chip" data-active="true" style={{ cursor: 'default' }}>
                  Best Value
                </div>
              </div>
              <div style={{ fontWeight: 950, fontSize: 26, color: 'var(--dc-primary)', marginTop: 6 }}>$75/month</div>
              <div style={{ marginTop: 10, display: 'grid', gap: 6, fontWeight: 900, color: 'rgba(17,24,39,0.8)' }}>
                <div>✓ 7 Visits/month</div>
                <div>✓ 24/7 Support</div>
                <div>✓ AI Features</div>
              </div>
            </div>
          </div>
        </div>
      ) : (
        <div className="dc-row" style={{ gap: 14 }}>
          <div className="dc-hero" style={{ padding: 18 }}>
            <div style={{ opacity: 0.9, fontWeight: 900 }}>Welcome</div>
            <div style={{ fontWeight: 950, fontSize: 26, marginTop: 8 }}>{fullName}</div>
            <div style={{ opacity: 0.9, fontWeight: 900, marginTop: 6 }}>Manage your plan, profile, and visits.</div>
          </div>

          <div className="dc-card" style={{ padding: 16 }}>
            <div style={{ fontWeight: 950, marginBottom: 8 }}>Health overview</div>
            <div style={{ color: 'var(--dc-muted)', fontWeight: 850, fontSize: 13 }}>
              Appointments: {apptCount} · Invoices: {invCount}
              {vitalsNote ? ` · ${vitalsNote}` : ''}
            </div>
          </div>

          <div className="dc-grid-2">
            <Link className="dc-action" to="/shell/6">
              🗓️ Appointments
            </Link>
            <Link className="dc-action" to="/shell/8">
              ＋ Book appointment
            </Link>
            <Link className="dc-action" to="/shell/17">
              🧠 Medical records
            </Link>
            <Link className="dc-action" to="/shell/11">
              🧾 Billing & invoices
            </Link>
            <Link className="dc-action" to="/shell/13">
              🔒 Change password
            </Link>
          </div>
        </div>
      )}
    </div>
  );
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
  const [tab, setTab] = React.useState('approvals'); // approvals | roles | plans | specialities | countries | providers | patients | appointments
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

  const roles = useApiCall(
    () => (tab === 'roles' ? api.get(ApiPaths.roles).then((r) => r.data) : Promise.resolve(null)),
    [tab],
  );
  const plans = useApiCall(
    () => (tab === 'plans' ? api.get(ApiPaths.plans).then((r) => r.data) : Promise.resolve(null)),
    [tab],
  );
  const countries = useApiCall(
    () => (tab === 'countries' ? api.get(ApiPaths.countries).then((r) => r.data) : Promise.resolve(null)),
    [tab],
  );
  const specialities = useApiCall(
    () => (tab === 'specialities' ? api.get(ApiPaths.specialities).then((r) => r.data) : Promise.resolve(null)),
    [tab],
  );
  const allAppts = useApiCall(
    () => (tab === 'appointments' ? api.get(ApiPaths.allAppointments).then((r) => r.data) : Promise.resolve(null)),
    [tab],
  );

  function unwrapList(payload) {
    const root = payload?.data ?? payload ?? {};
    if (Array.isArray(root)) return root;
    if (Array.isArray(root?.results)) return root.results;
    const d = root?.data ?? root;
    if (Array.isArray(d)) return d;
    if (Array.isArray(d?.results)) return d.results;
    if (Array.isArray(d?.appointments)) return d.appointments;
    return [];
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Admin (CRUD parity)</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
        <div className="dc-tabs" role="tablist" aria-label="Admin tabs">
          <button className="dc-tab" type="button" data-active={tab === 'approvals' ? 'true' : 'false'} onClick={() => setTab('approvals')}>
            Approvals
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'roles' ? 'true' : 'false'} onClick={() => setTab('roles')}>
            Roles
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'plans' ? 'true' : 'false'} onClick={() => setTab('plans')}>
            Plans
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'specialities' ? 'true' : 'false'} onClick={() => setTab('specialities')}>
            Specialities
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'countries' ? 'true' : 'false'} onClick={() => setTab('countries')}>
            Countries
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'appointments' ? 'true' : 'false'} onClick={() => setTab('appointments')}>
            Appointments
          </button>
        </div>
      </div>

      {tab !== 'approvals' ? (
        <div className="dc-card" style={{ padding: 16, background: '#f6e7e7' }}>
          <div style={{ display: 'flex', gap: 12, alignItems: 'center', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
              <div className="dc-avatar">🧩</div>
              <div>
                <div style={{ fontWeight: 950, fontSize: 18 }}>{tab.toUpperCase()}</div>
                <div style={{ color: 'var(--dc-muted)', fontSize: 13, fontWeight: 800 }}>Connected to backend API</div>
              </div>
            </div>
            <button className="dc-btn" onClick={() => window.location.reload()} style={{ fontWeight: 950 }}>
              ↻
            </button>
          </div>
        </div>
      ) : null}

      {tab === 'roles' ? (
        roles.loading ? (
          <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
            Loading…
          </div>
        ) : roles.error ? (
          <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
            {roles.error}
          </div>
        ) : (
          <div className="dc-list">
            {unwrapList(roles.data).slice(0, 200).map((r, idx) => (
              <div key={r?.id || idx} className="dc-list-row">
                <div className="dc-list-left">
                  <div className="dc-avatar">🛡️</div>
                  <div className="dc-list-text">
                    <div className="dc-list-title">{(r?.name || 'Role').toString()}</div>
                    <div className="dc-list-sub">{(r?.description || r?.status || '').toString()}</div>
                  </div>
                </div>
                <div style={{ color: 'var(--dc-muted)', fontWeight: 900 }}>{(r?.status || '').toString()}</div>
              </div>
            ))}
          </div>
        )
      ) : null}

      {tab === 'plans' ? (
        plans.loading ? (
          <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
            Loading…
          </div>
        ) : plans.error ? (
          <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
            {plans.error}
          </div>
        ) : (
          <div className="dc-list">
            {unwrapList(plans.data).slice(0, 200).map((p, idx) => (
              <div key={p?.id || idx} className="dc-list-row">
                <div className="dc-list-left">
                  <div className="dc-avatar">💳</div>
                  <div className="dc-list-text">
                    <div className="dc-list-title">{(p?.plan_name || 'Plan').toString()}</div>
                    <div className="dc-list-sub">
                      {(p?.duration || '').toString()} · ${(p?.price || '').toString()} · appts: {(p?.number_appointments || '').toString()}
                    </div>
                  </div>
                </div>
                <div style={{ color: 'var(--dc-muted)', fontWeight: 900 }}>{(p?.ai_bot || '').toString()}</div>
              </div>
            ))}
          </div>
        )
      ) : null}

      {tab === 'countries' ? (
        countries.loading ? (
          <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
            Loading…
          </div>
        ) : countries.error ? (
          <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
            {countries.error}
          </div>
        ) : (
          <div className="dc-list">
            {unwrapList(countries.data).slice(0, 200).map((c, idx) => (
              <div key={c?.id || idx} className="dc-list-row">
                <div className="dc-list-left">
                  <div className="dc-avatar">🌍</div>
                  <div className="dc-list-text">
                    <div className="dc-list-title">{(c?.country_name || 'Country').toString()}</div>
                    <div className="dc-list-sub">{(c?.country_code || '').toString()}</div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )
      ) : null}

      {tab === 'specialities' ? (
        specialities.loading ? (
          <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
            Loading…
          </div>
        ) : specialities.error ? (
          <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
            {specialities.error}
          </div>
        ) : (
          <div className="dc-list">
            {unwrapList(specialities.data).slice(0, 200).map((sp, idx) => (
              <div key={sp?.id || idx} className="dc-list-row">
                <div className="dc-list-left">
                  <div className="dc-avatar">🩺</div>
                  <div className="dc-list-text">
                    <div className="dc-list-title">{(sp?.speciality_name || 'Speciality').toString()}</div>
                    <div className="dc-list-sub">{(sp?.country_id || sp?.country || '').toString()}</div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )
      ) : null}

      {tab === 'appointments' ? (
        allAppts.loading ? (
          <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
            Loading…
          </div>
        ) : allAppts.error ? (
          <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
            {allAppts.error}
          </div>
        ) : (
          <div className="dc-list">
            {unwrapList(allAppts.data).slice(0, 200).map((a, idx) => (
              <div key={a?.id || idx} className="dc-list-row">
                <div className="dc-list-left">
                  <div className="dc-avatar">📅</div>
                  <div className="dc-list-text">
                    <div className="dc-list-title">
                      {(a?.patient?.name || 'Patient').toString()} → {(a?.provider?.full_name || 'Provider').toString()}
                    </div>
                    <div className="dc-list-sub">
                      {(a?.date || '').toString()} {(a?.time || '').toString()}
                    </div>
                  </div>
                </div>
                <div style={{ color: 'var(--dc-muted)', fontWeight: 900 }}>{(a?.approved || '').toString()}</div>
              </div>
            ))}
          </div>
        )
      ) : null}

      <div className="dc-card" style={{ padding: 16, background: '#f6e7e7' }}>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <div className="dc-avatar">🛡️</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 950, fontSize: 18 }}>Providers approvals</div>
            <div style={{ color: 'var(--dc-muted)', fontSize: 13, fontWeight: 800 }}>Pending registrations</div>
          </div>
          <button className="dc-btn" onClick={() => window.location.reload()} disabled={busy} style={{ fontWeight: 950 }}>
            ↻
          </button>
        </div>
      </div>

      {tab !== 'approvals' ? null : s.loading ? (
        <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
          Loading…
        </div>
      ) : s.error ? (
        <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
          {s.error}
        </div>
      ) : providers.length === 0 ? (
        <div style={{ color: 'var(--dc-muted)', fontWeight: 800, paddingLeft: 6 }}>No pending registrations.</div>
      ) : (
        <div className="dc-list">
          {providers.slice(0, 50).map((p) => (
            <div className="dc-list-row" key={p.id}>
              <div className="dc-list-left">
                <div className="dc-avatar">👥</div>
                <div className="dc-list-text">
                  <div className="dc-list-title">{(p.full_name || p.name || 'Provider').toString()}</div>
                  <div className="dc-list-sub">{(p.email || '').toString()}</div>
                </div>
              </div>
              <button className="dc-btn dc-btn-primary" onClick={() => approve('provider', p.id)} disabled={busy} style={{ fontWeight: 950 }}>
                Approve
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="dc-card" style={{ padding: 16, background: '#f6e7e7' }}>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <div className="dc-avatar">👤</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 950, fontSize: 18 }}>Patients approvals</div>
            <div style={{ color: 'var(--dc-muted)', fontSize: 13, fontWeight: 800 }}>Pending registrations</div>
          </div>
        </div>
      </div>

      {tab !== 'approvals' ? null : s.loading ? null : s.error ? null : patients.length === 0 ? (
        <div style={{ color: 'var(--dc-muted)', fontWeight: 800, paddingLeft: 6 }}>No pending registrations.</div>
      ) : (
        <div className="dc-list">
          {patients.slice(0, 50).map((p) => (
            <div className="dc-list-row" key={p.id}>
              <div className="dc-list-left">
                <div className="dc-avatar">👤</div>
                <div className="dc-list-text">
                  <div className="dc-list-title">{(p.name || p.full_name || 'Patient').toString()}</div>
                  <div className="dc-list-sub">{(p.email || '').toString()}</div>
                </div>
              </div>
              <button className="dc-btn dc-btn-primary" onClick={() => approve('patient', p.id)} disabled={busy} style={{ fontWeight: 950 }}>
                Approve
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

