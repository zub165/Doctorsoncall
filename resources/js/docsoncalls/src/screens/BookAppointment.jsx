import React from 'react';
import { api, ApiPaths } from '../api.js';

export function BookAppointment() {
  const [providers, setProviders] = React.useState({ loading: true, items: [], error: '' });
  const [form, setForm] = React.useState({
    q: '',
    provider_id: '',
    date: '',
    time: '',
  });
  const [state, setState] = React.useState({ loading: false, ok: false, error: '' });

  const times = ['09:00', '10:00', '11:00', '14:00', '15:00', '16:00'];

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const { data } = await api.get(ApiPaths.providers);
        const items = Array.isArray(data) ? data : data?.results || data?.data || [];
        if (!alive) return;
        setProviders({ loading: false, items: Array.isArray(items) ? items : [], error: '' });
      } catch {
        if (!alive) return;
        setProviders({ loading: false, items: [], error: 'Failed to load providers.' });
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const filteredProviders = React.useMemo(() => {
    const qq = form.q.trim().toLowerCase();
    const items = providers.items || [];
    if (!qq) return items;
    return items.filter((p) => {
      const s = `${p?.full_name ?? ''} ${p?.name ?? ''} ${p?.email ?? ''} ${p?.speciality_name ?? ''}`.toLowerCase();
      return s.includes(qq);
    });
  }, [providers.items, form.q]);

  async function onSubmit(e) {
    e.preventDefault();
    setState({ loading: true, ok: false, error: '' });
    try {
      await api.post(ApiPaths.storeAppointment, {
        provider_id: Number(form.provider_id),
        date: form.date,
        time: form.time,
      });
      setState({ loading: false, ok: true, error: '' });
    } catch {
      setState({ loading: false, ok: false, error: 'Failed to book appointment.' });
    }
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Book appointment</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
      </div>

      <div className="dc-hero" style={{ padding: 16 }}>
        <div className="dc-hero-title">Book appointment</div>
        <div className="dc-hero-sub">Pick provider, date & time to confirm.</div>
      </div>

      <div className="dc-card" style={{ padding: 16 }}>
        <div style={{ fontWeight: 950, fontSize: 18, marginBottom: 10 }}>Schedule appointment</div>
        <form className="dc-row" onSubmit={onSubmit}>
          <input
            className="dc-input"
            placeholder="Search provider"
            value={form.q}
            onChange={(e) => setForm((s) => ({ ...s, q: e.target.value }))}
          />

          <label className="dc-row" style={{ gap: 6 }}>
            <div style={{ fontSize: 13, fontWeight: 900 }}>Provider</div>
            {providers.loading ? (
              <div style={{ color: 'var(--dc-muted)', fontWeight: 800 }}>Loading providers…</div>
            ) : providers.error ? (
              <div style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>{providers.error}</div>
            ) : (
              <select
                className="dc-input"
                value={form.provider_id}
                onChange={(e) => setForm((s) => ({ ...s, provider_id: e.target.value }))}
                required
              >
                <option value="" disabled>
                  Select provider
                </option>
                {filteredProviders.slice(0, 200).map((p) => (
                  <option key={p?.id} value={p?.id}>
                    {(p?.full_name || p?.name || `Provider #${p?.id}`).toString()}
                  </option>
                ))}
              </select>
            )}
          </label>

          <label className="dc-row" style={{ gap: 6 }}>
            <div style={{ fontSize: 13, fontWeight: 900 }}>Date</div>
            <input
              className="dc-input"
              type="date"
              value={form.date}
              onChange={(e) => setForm((s) => ({ ...s, date: e.target.value }))}
              required
            />
          </label>

          <div className="dc-row" style={{ gap: 8 }}>
            <div style={{ fontSize: 13, fontWeight: 900 }}>Time</div>
            <div className="dc-time-grid">
              {times.map((t) => (
                <button
                  key={t}
                  type="button"
                  className="dc-time-chip"
                  data-selected={form.time === t ? 'true' : 'false'}
                  onClick={() => setForm((s) => ({ ...s, time: t }))}
                >
                  {t.includes(':') ? t.replace(/^0/, '') : t}
                </button>
              ))}
            </div>
            {!form.time ? <div style={{ color: 'var(--dc-muted)', fontSize: 12, fontWeight: 800 }}>Select a time</div> : null}
          </div>

          {state.error ? (
            <div style={{ color: 'var(--dc-danger)', fontWeight: 900, fontSize: 13 }}>
              {state.error}
            </div>
          ) : state.ok ? (
            <div style={{ color: 'var(--dc-primary)', fontWeight: 950, fontSize: 13 }}>
              Appointment created.
            </div>
          ) : null}

          <button className="dc-btn dc-btn-primary" disabled={state.loading || !form.time} style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}>
            {state.loading ? 'Confirming…' : 'Confirm booking'}
          </button>
        </form>
      </div>
    </div>
  );
}

