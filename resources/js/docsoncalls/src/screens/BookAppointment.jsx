import React from 'react';
import { api, ApiPaths } from '../api.js';

export function BookAppointment() {
  const [form, setForm] = React.useState({
    reason: '',
    date: '',
  });
  const [state, setState] = React.useState({ loading: false, ok: false, error: '' });

  async function onSubmit(e) {
    e.preventDefault();
    setState({ loading: true, ok: false, error: '' });
    try {
      await api.post(ApiPaths.storeAppointment, form);
      setState({ loading: false, ok: true, error: '' });
    } catch {
      setState({ loading: false, ok: false, error: 'Failed to book appointment.' });
    }
  }

  return (
    <div className="dc-card">
      <div style={{ fontWeight: 900, fontSize: 18, marginBottom: 8 }}>Book appointment</div>
      <form className="dc-row" onSubmit={onSubmit} style={{ maxWidth: 520 }}>
        <label className="dc-row" style={{ gap: 6 }}>
          <div style={{ fontSize: 13, fontWeight: 700 }}>Reason</div>
          <input
            className="dc-input"
            value={form.reason}
            onChange={(e) => setForm((s) => ({ ...s, reason: e.target.value }))}
            required
          />
        </label>

        <label className="dc-row" style={{ gap: 6 }}>
          <div style={{ fontSize: 13, fontWeight: 700 }}>Date</div>
          <input
            className="dc-input"
            type="date"
            value={form.date}
            onChange={(e) => setForm((s) => ({ ...s, date: e.target.value }))}
            required
          />
        </label>

        {state.error ? (
          <div style={{ color: 'var(--dc-danger)', fontWeight: 800, fontSize: 13 }}>
            {state.error}
          </div>
        ) : state.ok ? (
          <div style={{ color: 'var(--dc-primary)', fontWeight: 900, fontSize: 13 }}>
            Appointment created.
          </div>
        ) : null}

        <button className="dc-btn dc-btn-primary" disabled={state.loading}>
          {state.loading ? 'Booking…' : 'Book'}
        </button>
      </form>
    </div>
  );
}

