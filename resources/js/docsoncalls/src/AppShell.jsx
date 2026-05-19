import React from 'react';
import { Link, Navigate, Route, Routes, useLocation, useNavigate, useParams } from 'react-router-dom';
import { api, ApiPaths, tokenStore, apiBaseUrl } from './api.js';
import { Dashboard } from './screens/Dashboard.jsx';
import { Hospitals } from './screens/Hospitals.jsx';
import { Placeholder } from './screens/Placeholder.jsx';
import { Appointments } from './screens/Appointments.jsx';
import { BookAppointment } from './screens/BookAppointment.jsx';
import { Feedback } from './screens/Feedback.jsx';
import { MedicalRecords, formatAiAssistReadable } from './screens/MedicalRecords.jsx';

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
              className="dc-icon-btn dc-menu-btn"
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

function medlinePlusSearchUrl(query) {
  const t = String(query || '').trim();
  return `https://medlineplus.gov/search.html?q=${encodeURIComponent(t)}`;
}

function extractCoursesList(payload) {
  if (!payload) return [];
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload.courses)) return payload.courses;
  if (Array.isArray(payload.results)) return payload.results;
  // Django EMR: { status: "success", data: { courses: [...] } }
  const inner = payload.data;
  if (inner && typeof inner === 'object') {
    if (Array.isArray(inner.courses)) return inner.courses;
    if (Array.isArray(inner.results)) return inner.results;
  }
  return [];
}

function Courses() {
  const [tab, setTab] = React.useState('courses'); // education | courses | maintenance
  const [educationQ, setEducationQ] = React.useState('');
  const [courseFilter, setCourseFilter] = React.useState('');
  const s = useApiCall(() => api.get(ApiPaths.coursesV1).then((r) => r.data), []);
  const itemsAll = React.useMemo(() => extractCoursesList(s.data), [s.data]);
  const items = React.useMemo(() => {
    const qq = courseFilter.trim().toLowerCase();
    if (!qq) return itemsAll;
    return itemsAll.filter((c) => JSON.stringify(c || {}).toLowerCase().includes(qq));
  }, [itemsAll, courseFilter]);

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
              <input
                className="dc-input"
                placeholder="Search topic"
                value={educationQ}
                onChange={(e) => setEducationQ(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    const t = educationQ.trim();
                    if (t) window.open(medlinePlusSearchUrl(t), '_blank', 'noopener,noreferrer');
                  }
                }}
              />
              <button
                className="dc-btn dc-btn-primary"
                type="button"
                style={{ fontWeight: 950 }}
                onClick={() => {
                  const t = educationQ.trim();
                  if (!t) return;
                  window.open(medlinePlusSearchUrl(t), '_blank', 'noopener,noreferrer');
                }}
              >
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
            <input className="dc-input" placeholder="Search…" value={courseFilter} onChange={(e) => setCourseFilter(e.target.value)} />
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
              {itemsAll.length === 0 ? 'No courses returned.' : 'No courses match your search.'}
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

const AI_ASSISTANT_INTRO =
  "Hi! I'm your AI medical assistant.\n\nI can help with basic symptoms and next steps, but I'm not a doctor.\nIf you have severe symptoms (trouble breathing, chest pain, fainting, severe bleeding, stroke signs), call emergency services immediately.";

function AiAssistant() {
  const [msg, setMsg] = React.useState('');
  const [busy, setBusy] = React.useState(false);
  const STORAGE_KEY = 'docsoncalls_ai_assistant_history_v1';
  const WELCOME = {
    role: 'assistant',
    text:
      "Hi! I'm your AI medical assistant.\n\nI can help with basic symptoms and next steps, but I'm not a doctor.\nIf you have severe symptoms (trouble breathing, chest pain, fainting, severe bleeding, stroke signs), call emergency services immediately.",
  };
  const [history, setHistory] = React.useState(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      const parsed = raw ? JSON.parse(raw) : null;
      if (Array.isArray(parsed) && parsed.length) return parsed;
    } catch {}
    return [WELCOME];
  });
  const [rec, setRec] = React.useState({ supported: true, listening: false, interim: '', error: '' });
  const recRef = React.useRef(null);
  const listRef = React.useRef(null);

  React.useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(history.slice(-80)));
    } catch {}
    try {
      listRef.current?.scrollTo?.({ top: listRef.current.scrollHeight, behavior: 'smooth' });
    } catch {}
  }, [history]);

  React.useEffect(() => {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) {
      setRec((s) => ({ ...s, supported: false }));
      return;
    }
    const r = new SR();
    r.continuous = true;
    r.interimResults = true;
    r.lang = 'en-US';
    r.onresult = (event) => {
      let interim = '';
      let finalText = '';
      for (let i = event.resultIndex; i < event.results.length; i += 1) {
        const res = event.results[i];
        const t = (res?.[0]?.transcript || '').toString();
        if (!t) continue;
        if (res.isFinal) finalText += t;
        else interim += t;
      }
      if (interim) setRec((s) => ({ ...s, interim: interim.trim() }));
      if (finalText.trim()) {
        setMsg((prev) => {
          const cur = (prev || '').trimEnd();
          const sep = cur ? ' ' : '';
          return `${cur}${sep}${finalText.trim()}`;
        });
        setRec((s) => ({ ...s, interim: '' }));
      }
    };
    r.onerror = (e) => {
      setRec((s) => ({ ...s, listening: false, error: (e?.error || 'Dictation error').toString() }));
    };
    r.onend = () => {
      setRec((s) => ({ ...s, listening: false, interim: '' }));
    };
    recRef.current = r;
    return () => {
      try {
        r.stop();
      } catch {}
    };
  }, []);

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

  function clearChat() {
    setHistory([WELCOME]);
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch {}
    setMsg('');
  }

  function triageInstantReply(text) {
    const t = (text || '').toLowerCase();
    const severe = [
      'chest pain',
      'shortness of breath',
      'trouble breathing',
      'difficulty breathing',
      'stroke',
      'face droop',
      'slurred speech',
      'weakness on one side',
      'severe bleeding',
      'uncontrolled bleeding',
      'fainting',
      'passed out',
      'seizure',
      'blue lips',
      'severe allergic',
      'anaphylaxis',
      'suicidal',
      'overdose',
    ];
    const hit = severe.some((k) => t.includes(k));
    if (!hit) return null;
    return (
      "This could be serious.\n\n" +
      "- If you have trouble breathing, chest pain/pressure, signs of stroke, uncontrolled bleeding, seizure, or fainting: call emergency services now.\n" +
      "- If symptoms are severe or rapidly worsening: go to the nearest ER.\n\n" +
      "If you want, tell me: your age, main symptom, when it started, and any medical history/medications—I'll help you decide next safest steps."
    );
  }

  function toggleDictation() {
    if (!rec.supported) return;
    const r = recRef.current;
    if (!r) return;
    if (rec.listening) {
      try {
        r.stop();
      } catch {}
      setRec((s) => ({ ...s, listening: false, interim: '' }));
      return;
    }
    setRec((s) => ({ ...s, error: '' }));
    try {
      r.start();
      setRec((s) => ({ ...s, listening: true }));
    } catch (e) {
      setRec((s) => ({ ...s, listening: false, error: (e?.message || 'Could not start dictation').toString() }));
    }
  }

  async function send() {
    const t = msg.trim();
    if (!t || busy) return;
    setBusy(true);
    setRec((s) => ({ ...s, error: '' }));
    setHistory((h) => [...h, { role: 'user', text: t }]);
    setMsg('');
    try {
      const instant = triageInstantReply(t);
      if (instant) {
        setHistory((h) => [...h, { role: 'assistant', text: instant }]);
      }

      const { data } = await api.post(ApiPaths.medicalRecordsAiAssist, {
        query: t,
        kind: 'patient_summary',
      });
      let reply = formatAiAssistReadable(data);
      if (!reply || !String(reply).trim()) {
        reply =
          (data && (data.message || data.detail || data.answer || data.response)) ||
          (typeof data === 'string' ? data : '') ||
          (data ? JSON.stringify(data, null, 2) : 'No response.');
      }
      setHistory((h) => [...h, { role: 'assistant', text: String(reply) }]);
    } catch (err) {
      const code = err?.response?.status;
      const serverMsg =
        err?.response?.data?.message ||
        err?.response?.data?.detail ||
        (typeof err?.response?.data === 'string' ? err.response.data : '') ||
        err?.message ||
        'AI request failed.';
      const hint =
        code === 404
          ? 'Backend AI endpoint is missing (404). Deploy `/api/medical-records/ai-assist/` on your server or point the web app to the correct API base.'
          : code === 401
            ? 'Please sign in again.'
            : code === 403
              ? 'Your account role cannot access this action.'
              : '';
      setHistory((h) => [...h, { role: 'assistant', text: `Error: ${serverMsg}${hint ? `\n\n${hint}` : ''}` }]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div
          className="dc-appbar-title"
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 12,
            width: '100%',
            flexWrap: 'wrap',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <h2 style={{ margin: 0 }}>AI assistant</h2>
            <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
          </div>
          <button type="button" className="dc-btn" onClick={clearChat} style={{ fontWeight: 800, flexShrink: 0 }}>
            Clear chat
          </button>
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
        <button type="button" className="dc-chip" onClick={clearChat} style={{ marginLeft: 'auto' }}>
          Clear chat
        </button>
      </div>

      <div className="dc-card" style={{ padding: 16 }}>
        <div ref={listRef} className="dc-chat-log">
          {history.slice(-40).map((m, idx) => (
            <div
              key={idx}
              style={{
                padding: 12,
                borderRadius: 14,
                background: m.role === 'user' ? 'rgba(211,47,47,0.08)' : '#f3f4f6',
                border: m.role === 'assistant' && (m.text || '').startsWith('This could be serious')
                  ? '1px solid rgba(245, 158, 11, 0.35)'
                  : '1px solid rgba(229,231,235,0.9)',
              }}
            >
              <div
                style={{
                  whiteSpace: 'pre-wrap',
                  fontWeight: 800,
                  color: m.role === 'user' ? 'var(--dc-primary-dark)' : 'var(--dc-text)',
                }}
              >
                {m.text}
              </div>
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 10, marginTop: 12, alignItems: 'center', flexWrap: 'wrap' }}>
          <input
            className="dc-input"
            placeholder="Send a message"
            value={msg}
            onChange={(e) => setMsg(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                send();
              }
            }}
            disabled={busy}
            style={{ flex: '1 1 auto', minWidth: 0, width: 'auto' }}
          />
          <button
            className="dc-btn"
            type="button"
            onClick={toggleDictation}
            disabled={!rec.supported || busy}
            style={{ fontWeight: 950 }}
            title={rec.supported ? 'Voice dictation' : 'Dictation not supported in this browser'}
          >
            {rec.listening ? '🎙️ Stop' : '🎙️'}
          </button>
          <button
            className="dc-btn dc-btn-primary"
            type="button"
            onClick={send}
            disabled={busy}
            aria-label="Send message"
            style={{ fontWeight: 950, flex: '0 0 auto', flexShrink: 0, whiteSpace: 'nowrap', padding: '10px 16px' }}
          >
            {busy ? '…' : 'Send'}
          </button>
        </div>
        {rec.listening || rec.interim || rec.error ? (
          <div style={{ marginTop: 10, color: 'var(--dc-muted)', fontWeight: 850 }}>
            {rec.error ? rec.error : rec.listening ? (rec.interim ? `Listening… ${rec.interim}` : 'Listening…') : null}
          </div>
        ) : null}
      </div>
    </div>
  );
}

function SoapNotes() {
  const [raw, setRaw] = React.useState('');
  const [soap, setSoap] = React.useState({ s: '', o: '', a: '', p: '' });
  const [ai, setAi] = React.useState({ loading: false, error: '' });
  const [rec, setRec] = React.useState({ supported: true, listening: false, interim: '', error: '' });
  const recRef = React.useRef(null);

  React.useEffect(() => {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) {
      setRec((s) => ({ ...s, supported: false }));
      return;
    }
    const r = new SR();
    r.continuous = true;
    r.interimResults = true;
    r.lang = 'en-US';
    r.onresult = (event) => {
      let interim = '';
      let finalText = '';
      for (let i = event.resultIndex; i < event.results.length; i += 1) {
        const res = event.results[i];
        const t = (res?.[0]?.transcript || '').toString();
        if (!t) continue;
        if (res.isFinal) finalText += t;
        else interim += t;
      }
      if (interim) setRec((s) => ({ ...s, interim: interim.trim() }));
      if (finalText.trim()) {
        setRaw((prev) => {
          const cur = (prev || '').trimEnd();
          const sep = cur ? '\n' : '';
          return `${cur}${sep}${finalText.trim()}`;
        });
        setRec((s) => ({ ...s, interim: '' }));
      }
    };
    r.onerror = (e) => {
      setRec((s) => ({ ...s, listening: false, error: (e?.error || 'Dictation error').toString() }));
    };
    r.onend = () => {
      setRec((s) => ({ ...s, listening: false, interim: '' }));
    };
    recRef.current = r;
    return () => {
      try {
        r.stop();
      } catch {}
    };
  }, []);

  function toggleDictation() {
    if (!rec.supported) return;
    const r = recRef.current;
    if (!r) return;
    if (rec.listening) {
      try {
        r.stop();
      } catch {}
      setRec((s) => ({ ...s, listening: false, interim: '' }));
      return;
    }
    setRec((s) => ({ ...s, error: '' }));
    try {
      r.start();
      setRec((s) => ({ ...s, listening: true }));
    } catch (e) {
      setRec((s) => ({ ...s, listening: false, error: (e?.message || 'Could not start dictation').toString() }));
    }
  }

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

  function pickSoapLines(v) {
    if (v == null) return '';
    if (Array.isArray(v)) return v.filter(Boolean).map(String).join('\n');
    return String(v);
  }

  /** Backend-normalized `structured` / legacy SOAP JSON from Django. */
  function soapFromStructured(st) {
    if (!st || typeof st !== 'object') return null;
    if (st.subjective == null && st.objective == null && st.assessment == null && st.plan == null) return null;
    return {
      s: pickSoapLines(st.subjective),
      o: pickSoapLines(st.objective),
      a: pickSoapLines(st.assessment),
      p: pickSoapLines(st.plan),
    };
  }

  async function aiAssist() {
    const text = raw.trim();
    if (!text) return;
    setAi({ loading: true, error: '' });
    try {
      const { data } = await api.post(ApiPaths.medicalRecordsAiAssist, {
        query: text,
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
        const fromStruct = soapFromStructured(inner?.structured);
        if (fromStruct) {
          setSoap(fromStruct);
        } else {
          const answer = String(inner?.summary ?? '').trim();
          const parsed = parseSoapFromText(answer);
          if (parsed) setSoap(parsed);
          else setSoap({ s: answer, o: '', a: '', p: '' });
        }
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
        <div style={{ display: 'flex', gap: 12, marginTop: 12, flexWrap: 'wrap', alignItems: 'center' }}>
          <button
            className={`dc-btn ${rec.listening ? 'dc-btn-danger' : ''}`}
            type="button"
            onClick={toggleDictation}
            disabled={!rec.supported}
            style={{ minWidth: 180, fontWeight: 950 }}
            title={rec.supported ? 'Voice dictation' : 'Dictation not supported in this browser'}
          >
            {rec.listening ? '🎙️ Stop dictation' : '🎙️ Start dictation'}
          </button>
          <div style={{ color: 'var(--dc-muted)', fontWeight: 850, flex: 1, minWidth: 200 }}>
            {rec.listening ? (rec.interim ? `Listening… ${rec.interim}` : 'Listening…') : rec.error ? rec.error : null}
          </div>
        </div>
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
  const nav = useNavigate();
  const fileInputRef = React.useRef(null);
  const videoRef = React.useRef(null);
  const mediaStreamRef = React.useRef(null);

  const [latest, setLatest] = React.useState({ loading: true, error: '', record: null });
  const [wa, setWa] = React.useState({ loading: true, number: '' });
  const [toolHint, setToolHint] = React.useState('');
  const [mediaBusy, setMediaBusy] = React.useState(false);
  /** null | 'video' | 'audio' — live browser capture */
  const [previewKind, setPreviewKind] = React.useState(null);

  function stopMediaTracks() {
    try {
      mediaStreamRef.current?.getTracks?.()?.forEach((t) => t.stop());
    } catch {
      /* ignore */
    }
    mediaStreamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    setPreviewKind(null);
    setMediaBusy(false);
    setToolHint('');
  }

  React.useEffect(() => {
    return () => stopMediaTracks();
  }, []);

  React.useEffect(() => {
    if (previewKind === 'video' && videoRef.current && mediaStreamRef.current) {
      videoRef.current.srcObject = mediaStreamRef.current;
    }
  }, [previewKind]);

  async function startMedia(kind) {
    stopMediaTracks();
    setToolHint(kind === 'video' ? 'Requesting camera and microphone…' : 'Requesting microphone…');
    setMediaBusy(true);
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        setToolHint('Your browser cannot access the camera/microphone from this page.');
        return;
      }
      const constraints =
        kind === 'video'
          ? { video: { facingMode: 'user' }, audio: true }
          : { video: false, audio: true };
      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      mediaStreamRef.current = stream;
      setPreviewKind(kind);
      setToolHint(
        kind === 'video'
          ? 'Preview active — tap Stop when finished (ends camera access).'
          : 'Microphone active — tap Stop when finished.',
      );
    } catch (e) {
      const name = e?.name || '';
      const msg = e?.message || String(e);
      if (name === 'NotAllowedError' || name === 'PermissionDeniedError') {
        setToolHint('Permission denied — allow camera/microphone in the browser address bar, then try again.');
      } else if (name === 'NotFoundError') {
        setToolHint('No camera/microphone found on this device.');
      } else {
        setToolHint(`Could not start: ${msg}`);
      }
    } finally {
      setMediaBusy(false);
    }
  }

  function onUploadPicked(e) {
    const f = e.target.files?.[0];
    e.target.value = '';
    if (!f) return;
    setToolHint(`Selected file: ${f.name} (${Math.round(f.size / 1024)} KB). Link this upload to your EMR workflow from Medical records.`);
  }

  function exportTextRecord() {
    const rec = latest.record;
    const body = rec ? JSON.stringify(rec, null, 2) : 'No record loaded — open Medical records & AI to create data.';
    const blob = new Blob([body], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `doctor-visit-record-${new Date().toISOString().slice(0, 10)}.txt`;
    a.click();
    URL.revokeObjectURL(url);
    setToolHint('Downloaded text export.');
  }

  function exportPdfHint() {
    setToolHint('Tip: use Export text, then print the file and choose “Save as PDF”, or use the browser Print dialog on Medical records.');
  }

  const tools = [
    { label: 'Video', icon: '🎥', onClick: () => startMedia('video') },
    { label: 'Audio', icon: '🎧', onClick: () => startMedia('audio') },
    { label: 'Upload', icon: '📎', onClick: () => fileInputRef.current?.click() },
    { label: 'Import', icon: '⬇️', onClick: () => nav('/shell/17') },
    { label: 'Export PDF', icon: '🧾', onClick: exportPdfHint },
    { label: 'Export text', icon: '📝', onClick: exportTextRecord },
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
        <div style={{ color: 'var(--dc-muted)', fontWeight: 700, fontSize: 13, marginBottom: 12 }}>
          Video/Audio use your browser camera and microphone (you may see a permission prompt — that is normal). Upload picks a file locally; Import opens Medical records.
        </div>
        {toolHint ? (
          <div className="dc-card" style={{ marginBottom: 12, padding: 12, background: '#f8fafc', fontWeight: 800, fontSize: 14 }}>
            {toolHint}
            {previewKind ? (
              <button type="button" className="dc-btn dc-btn-danger" style={{ marginLeft: 12, fontWeight: 900 }} onClick={stopMediaTracks}>
                Stop
              </button>
            ) : null}
          </div>
        ) : null}
        {previewKind === 'video' ? (
          <div style={{ marginBottom: 12 }}>
            <video
              ref={videoRef}
              autoPlay
              playsInline
              muted
              style={{ width: '100%', maxHeight: 280, borderRadius: 12, background: '#111' }}
            />
          </div>
        ) : null}
        {previewKind === 'audio' ? (
          <div className="dc-card" style={{ marginBottom: 12, padding: 16, textAlign: 'center', fontWeight: 900 }}>
            🎙️ Microphone session active (audio-only — no camera).
          </div>
        ) : null}
        <input ref={fileInputRef} type="file" style={{ display: 'none' }} accept="image/*,.pdf,.txt" onChange={onUploadPicked} />
        <div className="dc-grid-2">
          {tools.map((t) => (
            <button
              key={t.label}
              className="dc-btn dc-btn-primary"
              type="button"
              style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}
              disabled={mediaBusy}
              onClick={() => {
                setToolHint('');
                t.onClick();
              }}
            >
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
    const normalized = src
      .map((m) => m || {})
      .filter(Boolean)
      .map((m) => {
        const isCountries = tab === 'countries';
        const isSpecs = tab === 'specialities';
        const isProviders = tab === 'providers';
        const title = isCountries
          ? (m?.country_name || m?.name || 'Country')
          : isSpecs
            ? (m?.speciality_name || m?.name || 'Speciality')
            : (m?.full_name || m?.name || 'Provider');
        const code = isCountries ? (m?.country_code || m?.code || m?.iso2 || m?.abbr || '') : '';
        const sub = isCountries
          ? (code || '').toString()
          : isSpecs
            ? ((m?.country || m?.country_id || '')?.toString() || '')
            : `${(m?.email || '').toString()}${m?.status ? ` · ${m.status}` : ''}`;
        return { m, title: (title || '').toString(), sub: (sub || '').toString(), code: (code || '').toString() };
      });

    const filtered = !qq
      ? normalized
      : normalized.filter((x) => `${x.title} ${x.sub} ${x.code}`.toLowerCase().includes(qq));

    // Stable, friendly ordering for Countries.
    if (tab === 'countries') {
      filtered.sort((a, b) => a.title.toLowerCase().localeCompare(b.title.toLowerCase()));
    }
    return filtered;
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
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <input
            className="dc-input"
            placeholder="Search by name or code…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            style={{ flex: 1 }}
          />
          {q.trim() ? (
            <button className="dc-btn" type="button" onClick={() => setQ('')} style={{ fontWeight: 950 }}>
              Clear
            </button>
          ) : null}
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
        <div className="dc-card" style={{ color: 'var(--dc-muted)', textAlign: 'center', padding: 36, fontWeight: 900 }}>
          No results match.
        </div>
      ) : (
        <div className="dc-list">
          {items.slice(0, 80).map((x, idx) => {
            const m = x.m;
            const isCountries = tab === 'countries';
            const isSpecs = tab === 'specialities';
            const isProviders = tab === 'providers';

            const title = x.title || (isCountries ? 'Country' : isSpecs ? 'Speciality' : 'Provider');
            const sub = x.sub || '';
            const code = (x.code || '').toUpperCase().trim();
            const providerBadge = isProviders ? (m?.status || '').toString().trim() : '';

            return (
              <div className="dc-list-row" key={m?.id || `${tab}-${idx}`} role="button" tabIndex={0}>
                <div className="dc-list-left">
                  <div className="dc-avatar">
                    {isCountries ? '🌐' : isSpecs ? '➕' : (title || 'P').toString().slice(0, 1).toUpperCase()}
                  </div>
                  <div className="dc-list-text">
                    <div className="dc-list-title">{title?.toString()}</div>
                    {sub ? <div className="dc-list-sub">{sub}</div> : null}
                  </div>
                </div>
                <div className="dc-list-right">
                  {isCountries && code ? <div className="dc-pill">{code}</div> : null}
                  {isProviders && providerBadge ? <div className="dc-pill">{providerBadge}</div> : null}
                  <div className="dc-chevron">›</div>
                </div>
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
  const ollama = useApiCall(() => api.get(ApiPaths.ollamaStatus).then((r) => r.data), []);
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

  const ollamaInner = ollama.data?.data ?? ollama.data ?? {};
  const ollamaLinked =
    ollamaInner?.linked === true ||
    (ollamaInner?.reachable === true && ollamaInner?.model_available === true);
  const ollamaLabel = ollama.loading
    ? '…'
    : ollama.error
      ? 'Not linked'
      : ollamaLinked
        ? `Linked · ${(ollamaInner?.configured_model || 'Llama').toString()}`
        : (ollamaInner?.message || 'Not linked').toString();

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
                <div className="dc-list-title">Llama on GoDaddy (Ollama)</div>
                <div className="dc-list-sub">{ollamaLabel}</div>
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
  const loc = useLocation();
  const [tab, setTab] = React.useState('home'); // home | profile | plan
  const me = useApiCall(() => api.get(ApiPaths.docOnCallMe).then((r) => r.data), []);

  React.useEffect(() => {
    const q = new URLSearchParams(loc.search || '').get('tab');
    if (q === 'home' || q === 'profile' || q === 'plan') setTab(q);
  }, [loc.search]);
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
            <Link className="dc-action" to="/shell/14?tab=plan">
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
  const [crud, setCrud] = React.useState({ loading: false, error: '', ok: '' });

  function renderApiError(errText, endpointPath) {
    const t = (errText || '').toString();
    const is404 = t.includes('status code 404') || t.toLowerCase().includes('not found');
    const is401 = t.includes('status code 401') || t.toLowerCase().includes('unauthorized');
    const is403 = t.includes('status code 403') || t.toLowerCase().includes('forbidden');
    const hint = is404
      ? 'This tab is calling an API endpoint that is not deployed on the current backend.'
      : is401
        ? 'You are signed out (token missing/expired).'
        : is403
          ? 'Your account does not have permission for this endpoint.'
          : 'The backend returned an error for this endpoint.';

    return (
      <div className="dc-card" style={{ padding: 16 }}>
        <div style={{ fontWeight: 950, color: 'var(--dc-danger)' }}>Request failed</div>
        <div style={{ marginTop: 8, fontWeight: 900 }}>{t}</div>
        <div style={{ marginTop: 10, color: 'var(--dc-muted)', fontWeight: 850 }}>{hint}</div>
        <div style={{ marginTop: 10, fontSize: 13, fontWeight: 900, color: 'rgba(17,24,39,0.85)' }}>
          Endpoint: <span style={{ fontWeight: 950 }}>{endpointPath}</span>
        </div>
        <div style={{ marginTop: 6, fontSize: 13, fontWeight: 900, color: 'rgba(17,24,39,0.85)' }}>
          API base: <span style={{ fontWeight: 950 }}>{apiBaseUrl}</span>
        </div>
        <div style={{ display: 'flex', gap: 12, marginTop: 12, flexWrap: 'wrap' }}>
          <button className="dc-btn" type="button" onClick={() => window.location.reload()} style={{ fontWeight: 950 }}>
            Retry
          </button>
          <button className="dc-btn dc-btn-primary" type="button" onClick={() => (window.location.href = '/shell/12')} style={{ fontWeight: 950 }}>
            Open Settings
          </button>
        </div>
        {is404 ? (
          <div style={{ marginTop: 12, color: 'var(--dc-muted)', fontWeight: 850, fontSize: 13 }}>
            Fix: point the web app to the correct Django EMR API (set <code>VITE_EMR_API_BASE_URL</code>) or deploy the missing route on the server.
          </div>
        ) : null}
      </div>
    );
  }

  async function doPatch(path, patch, label) {
    setCrud({ loading: true, error: '', ok: '' });
    try {
      await api.patch(path, patch);
      setCrud({ loading: false, error: '', ok: `${label} updated` });
      window.location.reload();
    } catch (e) {
      const msg = e?.response?.data?.message || e?.response?.data?.detail || e?.message || 'Update failed';
      setCrud({ loading: false, error: msg.toString(), ok: '' });
    }
  }

  async function doDelete(path, label) {
    const yes = window.confirm(`Delete ${label}? This cannot be undone.`);
    if (!yes) return;
    setCrud({ loading: true, error: '', ok: '' });
    try {
      await api.delete(path);
      setCrud({ loading: false, error: '', ok: `${label} deleted` });
      window.location.reload();
    } catch (e) {
      const msg = e?.response?.data?.message || e?.response?.data?.detail || e?.message || 'Delete failed';
      setCrud({ loading: false, error: msg.toString(), ok: '' });
    }
  }

  async function approve(kind, id) {
    setBusy(true);
    try {
      await api.post(ApiPaths.registrationsApprove, { kind, id });
      window.location.reload();
    } catch (e) {
      const msg = e?.response?.data?.message || e?.response?.data?.detail || e?.message || 'Approve failed';
      setCrud({ loading: false, error: msg.toString(), ok: '' });
    } finally {
      setBusy(false);
    }
  }

  async function reject(kind, id) {
    const yes = window.confirm('Reject this registration?');
    if (!yes) return;
    setBusy(true);
    setCrud({ loading: false, error: '', ok: '' });
    try {
      // Backend variations exist; we send an explicit action so Django can implement safely.
      await api.post(ApiPaths.registrationsApprove, { kind, id, action: 'reject' });
      window.location.reload();
    } catch (e) {
      const msg = e?.response?.data?.message || e?.response?.data?.detail || e?.message || 'Reject failed';
      setCrud({ loading: false, error: msg.toString(), ok: '' });
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

      {crud.error ? (
        <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
          {crud.error}
        </div>
      ) : null}
      {crud.ok ? (
        <div className="dc-card" style={{ color: 'var(--dc-primary)', fontWeight: 950 }}>
          {crud.ok}
        </div>
      ) : null}

      {tab === 'roles' ? (
        roles.loading ? (
          <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
            Loading…
          </div>
        ) : roles.error ? (
          renderApiError(roles.error, `${apiBaseUrl}${ApiPaths.roles}`)
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
                <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                  <div style={{ color: 'var(--dc-muted)', fontWeight: 900 }}>{(r?.status || '').toString()}</div>
                  <button
                    className="dc-btn"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = r?.id;
                      if (!id) return;
                      const name = window.prompt('Role name', (r?.name || '').toString());
                      if (name == null) return;
                      const status = window.prompt('Status (optional)', (r?.status || '').toString());
                      if (status == null) return;
                      doPatch(`${ApiPaths.roles}${encodeURIComponent(String(id))}/`, { name, status }, 'Role');
                    }}
                    style={{ fontWeight: 950 }}
                    title="Edit"
                  >
                    Edit
                  </button>
                  <button
                    className="dc-btn dc-btn-danger"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = r?.id;
                      if (!id) return;
                      doDelete(`${ApiPaths.roles}${encodeURIComponent(String(id))}/`, 'role');
                    }}
                    style={{ fontWeight: 950 }}
                    title="Delete"
                  >
                    Delete
                  </button>
                </div>
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
          renderApiError(plans.error, `${apiBaseUrl}${ApiPaths.plans}`)
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
                <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                  <div style={{ color: 'var(--dc-muted)', fontWeight: 900 }}>{(p?.ai_bot || '').toString()}</div>
                  <button
                    className="dc-btn"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = p?.id;
                      if (!id) return;
                      const plan_name = window.prompt('Plan name', (p?.plan_name || '').toString());
                      if (plan_name == null) return;
                      const price = window.prompt('Price', (p?.price || '').toString());
                      if (price == null) return;
                      const duration = window.prompt('Duration', (p?.duration || '').toString());
                      if (duration == null) return;
                      const number_appointments = window.prompt('Number appointments', (p?.number_appointments || '').toString());
                      if (number_appointments == null) return;
                      const ai_bot = window.prompt('AI bot (yes/no)', (p?.ai_bot || '').toString());
                      if (ai_bot == null) return;
                      doPatch(
                        `${ApiPaths.plans}${encodeURIComponent(String(id))}/`,
                        { plan_name, price, duration, number_appointments, ai_bot },
                        'Plan',
                      );
                    }}
                    style={{ fontWeight: 950 }}
                  >
                    Edit
                  </button>
                  <button
                    className="dc-btn dc-btn-danger"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = p?.id;
                      if (!id) return;
                      doDelete(`${ApiPaths.plans}${encodeURIComponent(String(id))}/`, 'plan');
                    }}
                    style={{ fontWeight: 950 }}
                  >
                    Delete
                  </button>
                </div>
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
          renderApiError(countries.error, `${apiBaseUrl}${ApiPaths.countries}`)
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
                <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                  <button
                    className="dc-btn"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = c?.id;
                      if (!id) return;
                      const country_name = window.prompt('Country name', (c?.country_name || '').toString());
                      if (country_name == null) return;
                      const country_code = window.prompt('Country code', (c?.country_code || '').toString());
                      if (country_code == null) return;
                      doPatch(
                        `${ApiPaths.countries}${encodeURIComponent(String(id))}/`,
                        { country_name, country_code },
                        'Country',
                      );
                    }}
                    style={{ fontWeight: 950 }}
                  >
                    Edit
                  </button>
                  <button
                    className="dc-btn dc-btn-danger"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = c?.id;
                      if (!id) return;
                      doDelete(`${ApiPaths.countries}${encodeURIComponent(String(id))}/`, 'country');
                    }}
                    style={{ fontWeight: 950 }}
                  >
                    Delete
                  </button>
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
          renderApiError(specialities.error, `${apiBaseUrl}${ApiPaths.specialities}`)
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
                <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                  <button
                    className="dc-btn"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = sp?.id;
                      if (!id) return;
                      const speciality_name = window.prompt('Speciality name', (sp?.speciality_name || '').toString());
                      if (speciality_name == null) return;
                      const country_id = window.prompt('Country ID (optional)', (sp?.country_id || sp?.country || '').toString());
                      if (country_id == null) return;
                      doPatch(
                        `${ApiPaths.specialities}${encodeURIComponent(String(id))}/`,
                        { speciality_name, country_id: country_id || null },
                        'Speciality',
                      );
                    }}
                    style={{ fontWeight: 950 }}
                  >
                    Edit
                  </button>
                  <button
                    className="dc-btn dc-btn-danger"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = sp?.id;
                      if (!id) return;
                      doDelete(`${ApiPaths.specialities}${encodeURIComponent(String(id))}/`, 'speciality');
                    }}
                    style={{ fontWeight: 950 }}
                  >
                    Delete
                  </button>
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
          renderApiError(allAppts.error, `${apiBaseUrl}${ApiPaths.allAppointments}`)
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
                <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                  <div style={{ color: 'var(--dc-muted)', fontWeight: 900 }}>{(a?.approved || a?.status || '').toString()}</div>
                  <button
                    className="dc-btn"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = a?.id;
                      if (!id) return;
                      const date = window.prompt('Date (YYYY-MM-DD)', (a?.date || '').toString());
                      if (date == null) return;
                      const time = window.prompt('Time (HH:MM)', (a?.time || '').toString());
                      if (time == null) return;
                      const status = window.prompt('Status / approved (optional)', (a?.status || a?.approved || '').toString());
                      if (status == null) return;
                      const patch = { date, time, status: status || null };
                      doPatch(`${ApiPaths.storeAppointment}${encodeURIComponent(String(id))}/`, patch, 'Appointment');
                    }}
                    style={{ fontWeight: 950 }}
                    title="Edit"
                  >
                    Edit
                  </button>
                  <button
                    className="dc-btn dc-btn-danger"
                    type="button"
                    disabled={crud.loading}
                    onClick={() => {
                      const id = a?.id;
                      if (!id) return;
                      doDelete(`${ApiPaths.storeAppointment}${encodeURIComponent(String(id))}/`, 'appointment');
                    }}
                    style={{ fontWeight: 950 }}
                    title="Delete"
                  >
                    Delete
                  </button>
                </div>
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
              <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                <button className="dc-btn dc-btn-primary" onClick={() => approve('provider', p.id)} disabled={busy} style={{ fontWeight: 950 }}>
                  Approve
                </button>
                <button className="dc-btn dc-btn-danger" onClick={() => reject('provider', p.id)} disabled={busy} style={{ fontWeight: 950 }}>
                  Reject
                </button>
              </div>
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
              <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                <button className="dc-btn dc-btn-primary" onClick={() => approve('patient', p.id)} disabled={busy} style={{ fontWeight: 950 }}>
                  Approve
                </button>
                <button className="dc-btn dc-btn-danger" onClick={() => reject('patient', p.id)} disabled={busy} style={{ fontWeight: 950 }}>
                  Reject
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

