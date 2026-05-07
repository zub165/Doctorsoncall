import React from 'react';
import { api, ApiPaths } from '../api.js';

export function Appointments() {
  const [state, setState] = React.useState({
    loading: true,
    items: [],
    error: '',
  });

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const { data } = await api.get(ApiPaths.myAppointments);
        const items = Array.isArray(data) ? data : data?.results || [];
        if (!alive) return;
        setState({ loading: false, items, error: '' });
      } catch {
        if (!alive) return;
        setState({ loading: false, items: [], error: 'Failed to load appointments.' });
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  return (
    <div className="dc-card">
      <div style={{ fontWeight: 900, fontSize: 18, marginBottom: 8 }}>Appointments</div>
      {state.loading ? (
        <div style={{ color: 'var(--dc-muted)' }}>Loading…</div>
      ) : state.error ? (
        <div style={{ color: 'var(--dc-danger)', fontWeight: 800 }}>{state.error}</div>
      ) : state.items.length === 0 ? (
        <div style={{ color: 'var(--dc-muted)' }}>No appointments returned by API.</div>
      ) : (
        <div className="dc-row">
          {state.items.slice(0, 20).map((a, idx) => (
            <div
              key={a?.uuid || a?.id || idx}
              style={{
                padding: 12,
                border: '1px solid var(--dc-border)',
                borderRadius: 14,
              }}
            >
              <div style={{ fontWeight: 800 }}>
                {(a?.title || a?.reason || 'Appointment').toString()}
              </div>
              <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>
                {(a?.date || a?.scheduled_at || a?.created_at || '').toString()}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

