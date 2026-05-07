import React from 'react';
import { api, ApiPaths } from '../api.js';

export function Feedback() {
  const [form, setForm] = React.useState({ message: '' });
  const [state, setState] = React.useState({ loading: false, ok: false, error: '' });

  async function onSubmit(e) {
    e.preventDefault();
    setState({ loading: true, ok: false, error: '' });
    try {
      await api.post(ApiPaths.feedbackSubmit, form);
      setState({ loading: false, ok: true, error: '' });
      setForm({ message: '' });
    } catch {
      setState({ loading: false, ok: false, error: 'Failed to submit feedback.' });
    }
  }

  return (
    <div className="dc-card">
      <div style={{ fontWeight: 900, fontSize: 18, marginBottom: 8 }}>Feedback</div>
      <form className="dc-row" onSubmit={onSubmit} style={{ maxWidth: 640 }}>
        <label className="dc-row" style={{ gap: 6 }}>
          <div style={{ fontSize: 13, fontWeight: 700 }}>Message</div>
          <textarea
            className="dc-input"
            rows={6}
            value={form.message}
            onChange={(e) => setForm((s) => ({ ...s, message: e.target.value }))}
            required
          />
        </label>

        {state.error ? (
          <div style={{ color: 'var(--dc-danger)', fontWeight: 800, fontSize: 13 }}>
            {state.error}
          </div>
        ) : state.ok ? (
          <div style={{ color: 'var(--dc-primary)', fontWeight: 900, fontSize: 13 }}>
            Thanks — feedback submitted.
          </div>
        ) : null}

        <button className="dc-btn dc-btn-primary" disabled={state.loading}>
          {state.loading ? 'Sending…' : 'Send feedback'}
        </button>
      </form>
    </div>
  );
}

