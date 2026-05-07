import React from 'react';
import { api, ApiPaths } from '../api.js';
import { Link } from 'react-router-dom';

export function Dashboard() {
  const [state, setState] = React.useState({
    loading: true,
    me: null,
    error: '',
  });

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const { data } = await api.get(ApiPaths.docOnCallMe);
        if (!alive) return;
        setState({ loading: false, me: data, error: '' });
      } catch {
        if (!alive) return;
        setState({ loading: false, me: null, error: 'Failed to load profile.' });
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  return (
    <div className="dc-row">
      <div className="dc-card">
        <div style={{ fontWeight: 900, fontSize: 18, marginBottom: 8 }}>Welcome</div>
        {state.loading ? (
          <div style={{ color: 'var(--dc-muted)' }}>Loading…</div>
        ) : state.error ? (
          <div style={{ color: 'var(--dc-danger)', fontWeight: 800 }}>{state.error}</div>
        ) : (
          <pre
            style={{
              margin: 0,
              padding: 12,
              borderRadius: 12,
              background: '#0b1220',
              color: '#e5e7eb',
              overflowX: 'auto',
              fontSize: 12,
            }}
          >
            {JSON.stringify(state.me, null, 2)}
          </pre>
        )}
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

