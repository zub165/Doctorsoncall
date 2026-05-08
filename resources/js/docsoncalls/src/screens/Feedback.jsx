import React from 'react';
import { api, ApiPaths } from '../api.js';

export function Feedback() {
  const [form, setForm] = React.useState({ message: '' });
  const [state, setState] = React.useState({ loading: false, ok: false, error: '' });
  const [quick, setQuick] = React.useState('');

  async function onSubmit(e) {
    e.preventDefault();
    setState({ loading: true, ok: false, error: '' });
    try {
      const message = (form.message || '').trim() || quick;
      await api.post(ApiPaths.feedbackSubmit, { message });
      setState({ loading: false, ok: true, error: '' });
      setForm({ message: '' });
      setQuick('');
    } catch {
      setState({ loading: false, ok: false, error: 'Failed to submit feedback.' });
    }
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Feedback</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
      </div>

      <div className="dc-card" style={{ padding: 16 }}>
        <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
          <div className="dc-avatar" style={{ width: 44, height: 44 }}>
            !
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 950, fontSize: 18 }}>Send Feedback</div>
            <div style={{ color: 'var(--dc-muted)', fontSize: 13, marginTop: 2 }}>
              We value your opinion. Share your thoughts, suggestions, or report any issues.
            </div>
          </div>
        </div>

        <form className="dc-row" onSubmit={onSubmit} style={{ marginTop: 12 }}>
          <textarea
            className="dc-input"
            rows={6}
            placeholder="Write your feedback here…"
            value={form.message}
            onChange={(e) => setForm((s) => ({ ...s, message: e.target.value }))}
          />

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
            {state.loading ? 'Submitting…' : 'Submit Feedback'}
          </button>
        </form>
      </div>

      <div className="dc-card" style={{ padding: 16 }}>
        <div style={{ fontWeight: 950, fontSize: 16, marginBottom: 12 }}>Quick Feedback</div>
        <div className="dc-grid-2">
          <button
            type="button"
            className="dc-btn"
            onClick={() => setQuick('Great')}
            style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}
          >
            👍 Great
          </button>
          <button
            type="button"
            className="dc-btn"
            onClick={() => setQuick('Good')}
            style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}
          >
            🙂 Good
          </button>
          <button
            type="button"
            className="dc-btn"
            onClick={() => setQuick('Poor')}
            style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}
          >
            🙁 Poor
          </button>
          <button
            type="button"
            className="dc-btn"
            onClick={() => setQuick('Issue')}
            style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}
          >
            ⚠️ Issue
          </button>
        </div>

        {quick ? (
          <div style={{ marginTop: 10, color: 'var(--dc-muted)', fontSize: 13, fontWeight: 800 }}>
            Selected: {quick}
          </div>
        ) : null}
      </div>
    </div>
  );
}

