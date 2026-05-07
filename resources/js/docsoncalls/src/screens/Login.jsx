import React from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { api, ApiPaths, tokenStore } from '../api.js';

export function Login() {
  const nav = useNavigate();
  const [form, setForm] = React.useState({ email: '', password: '' });
  const [state, setState] = React.useState({ loading: false, error: '' });

  async function onSubmit(e) {
    e.preventDefault();
    setState({ loading: true, error: '' });
    try {
      const { data } = await api.post(ApiPaths.authLogin, form);
      const token =
        (data && (data.token ?? data.key ?? data.auth_token))?.toString()?.trim() || '';
      if (!token) throw new Error('No token returned');
      tokenStore.write(token);
      nav('/', { replace: true });
    } catch (err) {
      setState({
        loading: false,
        error: 'Login failed. Check credentials and API base URL.',
      });
      return;
    }
    setState({ loading: false, error: '' });
  }

  return (
    <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 18 }}>
      <div className="dc-card" style={{ width: 420, maxWidth: '92vw' }}>
        <div style={{ fontWeight: 900, fontSize: 20, marginBottom: 4 }}>Doctor On Call</div>
        <div style={{ color: 'var(--dc-muted)', fontSize: 13, marginBottom: 16 }}>
          Sign in to continue.
        </div>

        <form className="dc-row" onSubmit={onSubmit}>
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
              autoComplete="current-password"
              required
            />
          </label>

          {state.error ? (
            <div style={{ color: 'var(--dc-danger)', fontWeight: 700, fontSize: 13 }}>
              {state.error}
            </div>
          ) : null}

          <button className="dc-btn dc-btn-primary" disabled={state.loading}>
            {state.loading ? 'Signing in…' : 'Sign in'}
          </button>
        </form>

        <div style={{ marginTop: 12, fontSize: 13, color: 'var(--dc-muted)' }}>
          No account? <Link to="/register" style={{ fontWeight: 800 }}>Create one</Link>
        </div>
      </div>
    </div>
  );
}

