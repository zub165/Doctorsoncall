import React from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { api, ApiPaths, tokenStore } from '../api.js';

function errMessage(err) {
  const status = err?.response?.status;
  const data = err?.response?.data;
  const serverMsg =
    (data && (data.message || data.detail)) ||
    (typeof data === 'string' ? data : '') ||
    '';
  if (status && serverMsg) return `${status}: ${serverMsg}`;
  if (status) return `Request failed (${status})`;
  return 'Registration failed.';
}

export function Register() {
  const nav = useNavigate();
  const [form, setForm] = React.useState({
    name: '',
    email: '',
    password: '',
  });
  const [state, setState] = React.useState({ loading: false, error: '' });

  async function onSubmit(e) {
    e.preventDefault();
    setState({ loading: true, error: '' });
    try {
      // Django `auth/register/` expects `first_name` (not `name`).
      const payload = {
        first_name: form.name,
        email: form.email,
        password: form.password,
        portal: 'patient',
        role: 'patient',
      };
      const { data } = await api.post(ApiPaths.authRegister, payload);
      const token =
        (data && (data.token ?? data.key ?? data.auth_token))?.toString()?.trim() || '';
      if (token) tokenStore.write(token);
      nav('/', { replace: true });
    } catch (err) {
      setState({ loading: false, error: errMessage(err) });
      return;
    }
    setState({ loading: false, error: '' });
  }

  return (
    <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 18 }}>
      <div className="dc-card" style={{ width: 460, maxWidth: '92vw' }}>
        <div style={{ fontWeight: 900, fontSize: 20, marginBottom: 4 }}>Create account</div>
        <div style={{ color: 'var(--dc-muted)', fontSize: 13, marginBottom: 16 }}>
          Register for Doctor On Call.
        </div>

        <form className="dc-row" onSubmit={onSubmit}>
          <label className="dc-row" style={{ gap: 6 }}>
            <div style={{ fontSize: 13, fontWeight: 700 }}>Name</div>
            <input
              className="dc-input"
              value={form.name}
              onChange={(e) => setForm((s) => ({ ...s, name: e.target.value }))}
              autoComplete="name"
              required
            />
          </label>

          <label className="dc-row" style={{ gap: 6 }}>
            <div style={{ fontSize: 13, fontWeight: 700 }}>Email</div>
            <input
              className="dc-input"
              value={form.email}
              onChange={(e) => setForm((s) => ({ ...s, email: e.target.value }))}
              autoComplete="email"
              required
            />
          </label>

          <label className="dc-row" style={{ gap: 6 }}>
            <div style={{ fontSize: 13, fontWeight: 700 }}>Password</div>
            <input
              className="dc-input"
              type="password"
              value={form.password}
              onChange={(e) => setForm((s) => ({ ...s, password: e.target.value }))}
              autoComplete="new-password"
              required
            />
          </label>

          {state.error ? (
            <div style={{ color: 'var(--dc-danger)', fontWeight: 700, fontSize: 13 }}>
              {state.error}
            </div>
          ) : null}

          <button className="dc-btn dc-btn-primary" disabled={state.loading}>
            {state.loading ? 'Creating…' : 'Create account'}
          </button>
        </form>

        <div style={{ marginTop: 12, fontSize: 13, color: 'var(--dc-muted)' }}>
          Already have an account? <Link to="/login" style={{ fontWeight: 800 }}>Sign in</Link>
        </div>
      </div>
    </div>
  );
}

