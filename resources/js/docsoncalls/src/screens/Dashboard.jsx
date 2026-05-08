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
  });

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [meRes, healthRes] = await Promise.allSettled([
          api.get(ApiPaths.docOnCallMe),
          api.get(ApiPaths.health),
        ]);
        const meData = meRes.status === 'fulfilled' ? meRes.value.data : null;
        const healthData =
          healthRes.status === 'fulfilled' ? healthRes.value.data : null;
        if (!alive) return;
        setState({ loading: false, me: meData, health: healthData, error: '' });
      } catch {
        if (!alive) return;
        setState({
          loading: false,
          me: null,
          health: null,
          error: 'Failed to load profile.',
        });
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const me = state.me ? unwrapMe(state.me) : null;

  return (
    <div className="dc-row">
      <div className="dc-card">
        <div style={{ fontWeight: 900, fontSize: 18, marginBottom: 8 }}>Welcome</div>
        {state.loading ? (
          <div style={{ color: 'var(--dc-muted)' }}>Loading…</div>
        ) : state.error ? (
          <div style={{ color: 'var(--dc-danger)', fontWeight: 800 }}>{state.error}</div>
        ) : me ? (
          <div>
            <div style={{ fontSize: 22, fontWeight: 950, letterSpacing: -0.3 }}>{me.name}</div>
            <div style={{ color: 'var(--dc-muted)', marginTop: 4 }}>
              Signed in as <b>{me.role}</b>
              {me.isStaff ? ' (staff)' : ''}
              {me.email ? ` · ${me.email}` : me.username ? ` · ${me.username}` : ''}
            </div>

            <div style={{ marginTop: 14 }}>
              <div
                style={{
                  padding: 12,
                  borderRadius: 14,
                  border: '1px solid var(--dc-border)',
                  background: 'rgba(14,165,164,0.06)',
                }}
              >
                <div style={{ fontWeight: 900, marginBottom: 4 }}>System status</div>
                <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>
                  Health:{' '}
                  <b>{state.health?.status === 'success' ? 'Connected' : 'Unknown'}</b>
                </div>
              </div>
            </div>
          </div>
        ) : null}
      </div>

      <div className="dc-card">
        <div style={{ fontWeight: 900, fontSize: 18, marginBottom: 8 }}>Quick actions</div>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <Link className="dc-btn dc-btn-primary" to="/shell/1">
            Browse hospitals
          </Link>
          <Link className="dc-btn" to="/shell/6">
            My appointments
          </Link>
          <Link className="dc-btn" to="/shell/8">
            Book appointment
          </Link>
          <Link className="dc-btn" to="/shell/17">
            Medical records
          </Link>
        </div>
      </div>
    </div>
  );
}

