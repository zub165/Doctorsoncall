import React from 'react';
import { api, ApiPaths } from '../api.js';
import { Link } from 'react-router-dom';

function unwrapMe(payload) {
  const d = payload?.data ?? payload ?? {};
  const user = d.user ?? {};
  return {
    role: (d.role ?? d.portal ?? 'guest').toString(),
    name: (user.full_name ?? user.first_name ?? user.username ?? user.email ?? 'User').toString(),
    email: (user.email ?? '').toString(),
    username: (user.username ?? '').toString(),
    isStaff: Boolean(user.is_staff || user.is_superuser),
  };
}

export function Dashboard() {
  const [state, setState] = React.useState({
    loading: true,
    me: null,
    error: '',
    health: null,
    counts: null,
  });

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [meRes, healthRes, apptRes, hospRes, provRes] = await Promise.allSettled([
          api.get(ApiPaths.docOnCallMe),
          api.get(ApiPaths.health),
          api.get(ApiPaths.myAppointments),
          api.get(ApiPaths.hospitals),
          api.get(ApiPaths.providers),
        ]);
        const meData = meRes.status === 'fulfilled' ? meRes.value.data : null;
        const healthData = healthRes.status === 'fulfilled' ? healthRes.value.data : null;

        const list = (x) => (Array.isArray(x) ? x : x?.results || x?.data || []);
        const appts = apptRes.status === 'fulfilled' ? list(apptRes.value.data) : [];
        const hosps = hospRes.status === 'fulfilled' ? list(hospRes.value.data) : [];
        const provs = provRes.status === 'fulfilled' ? list(provRes.value.data) : [];

        if (!alive) return;
        setState({
          loading: false,
          me: meData,
          health: healthData,
          counts: {
            appointments: appts.length,
            hospitals: hosps.length,
            providers: provs.length,
          },
          error: '',
        });
      } catch {
        if (!alive) return;
        setState({
          loading: false,
          me: null,
          health: null,
          counts: null,
          error: 'Failed to load profile.',
        });
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const me = state.me ? unwrapMe(state.me) : null;
  const welcomeName = me?.name ? me.name.split(' ')[0] : 'there';
  const counts = state.counts || { appointments: 0, hospitals: 0, providers: 0 };
  const healthOk = state.health?.status === 'success';

  return (
    <div className="dc-row">
      {state.loading ? (
        <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
          Loading…
        </div>
      ) : state.error ? (
        <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
          {state.error}
        </div>
      ) : (
        <>
          <div className="dc-hero">
            <div className="dc-hero-title">Doctor On Call</div>
            <div className="dc-hero-welcome">Welcome back, {welcomeName}!</div>
            <div className="dc-hero-sub">
              {me?.email || me?.username || ''}{me?.role ? ` · role: ${me.role}` : ''}
            </div>
          </div>

          <div className="dc-section-title">Quick Overview</div>
          <div className="dc-grid-2">
            <div className="dc-tile">
              <div className="dc-tile-top">
                <div className="dc-pill" style={{ background: 'rgba(34,197,94,0.14)', color: '#166534' }}>
                  📅
                </div>
              </div>
              <div className="dc-tile-value">{counts.appointments}</div>
              <div className="dc-tile-label">Appointments</div>
            </div>
            <div className="dc-tile">
              <div className="dc-tile-top">
                <div className="dc-pill" style={{ background: 'rgba(59,130,246,0.14)', color: '#1d4ed8' }}>
                  🏥
                </div>
              </div>
              <div className="dc-tile-value">{counts.hospitals}</div>
              <div className="dc-tile-label">Hospitals</div>
            </div>
            <div className="dc-tile">
              <div className="dc-tile-top">
                <div className="dc-pill" style={{ background: 'rgba(168,85,247,0.14)', color: '#6b21a8' }}>
                  👥
                </div>
              </div>
              <div className="dc-tile-value">{counts.providers}</div>
              <div className="dc-tile-label">Providers</div>
            </div>
            <div className="dc-tile">
              <div className="dc-tile-top">
                <div className="dc-pill" style={{ background: 'rgba(245,158,11,0.14)', color: '#92400e' }}>
                  🩺
                </div>
              </div>
              <div className="dc-tile-value">{healthOk ? 'OK' : '—'}</div>
              <div className="dc-tile-label">System</div>
            </div>
          </div>

          <div className="dc-section-title">Quick Actions</div>
          <div className="dc-grid-2">
            <Link className="dc-action" to="/shell/8">
              ➕ Book Appt
            </Link>
            <Link className="dc-action" to="/shell/1">
              🏥 Hospitals
            </Link>
            <Link className="dc-action" to="/shell/6">
              📅 My Appts
            </Link>
            <Link className="dc-action" to="/shell/11">
              ❗ Feedback
            </Link>
            <Link className="dc-action" to="/shell/17">
              🗂️ Medical records
            </Link>
            <Link className="dc-action" to="/shell/4">
              🤖 AI assistant
            </Link>
          </div>

          {healthOk ? (
            <div className="dc-banner-ok">
              <div style={{ fontSize: 20, lineHeight: '20px' }}>✅</div>
              <div>
                <div style={{ fontWeight: 950 }}>System Healthy</div>
                <div style={{ opacity: 0.9, fontSize: 13, marginTop: 2 }}>
                  API is reachable
                </div>
              </div>
            </div>
          ) : null}
        </>
      )}
    </div>
  );
}

