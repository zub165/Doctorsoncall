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
  return 'Login failed.';
}

export function Login() {
  const nav = useNavigate();
  const [form, setForm] = React.useState({ email: '', password: '' });
  const [portal, setPortal] = React.useState('patient');
  const [state, setState] = React.useState({ loading: false, error: '' });

  async function onSubmit(e) {
    e.preventDefault();
    setState({ loading: true, error: '' });
    try {
      const payload = {
        email: form.email,
        password: form.password,
        portal,
        role: portal,
      };
      const { data } = await api.post(ApiPaths.authLogin, payload);
      const token =
        (data && (data.data?.token ?? data.token ?? data.key ?? data.auth_token))?.toString()?.trim() ||
        '';
      if (!token) throw new Error('No token returned');
      tokenStore.write(token);
      nav('/', { replace: true });
    } catch (err) {
      setState({
        loading: false,
        error: errMessage(err),
      });
      return;
    }
    setState({ loading: false, error: '' });
  }

  return (
    <div className="dc-auth-shell">
      <div className="dc-hero dc-auth-hero">
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div className="dc-brand-badge" style={{ background: 'rgba(255,255,255,0.2)' }}>
            +
          </div>
          <div>
            <div className="dc-hero-title">Doctor On Call</div>
            <div className="dc-hero-sub">On-call care · Hospital finder</div>
          </div>
        </div>
      </div>

      <div className="dc-auth-wrap">
        <div className="dc-card dc-auth-card">
          <div style={{ fontWeight: 950, fontSize: 20, marginBottom: 8 }}>Sign in</div>

          <div style={{ color: 'var(--dc-muted)', fontSize: 13, marginBottom: 10 }}>
            Choose portal, then sign in to continue.
          </div>

          <div className="dc-chip-row" style={{ marginBottom: 12 }}>
            <button
              type="button"
              className="dc-chip"
              data-active={portal === 'patient' ? 'true' : 'false'}
              onClick={() => setPortal('patient')}
            >
              Patient
            </button>
            <button
              type="button"
              className="dc-chip"
              data-active={portal === 'doctor' ? 'true' : 'false'}
              onClick={() => setPortal('doctor')}
            >
              Doctor
            </button>
            <button
              type="button"
              className="dc-chip"
              data-active={portal === 'admin' ? 'true' : 'false'}
              onClick={() => setPortal('admin')}
            >
              Admin
            </button>
          </div>

          <form className="dc-row" onSubmit={onSubmit}>
            <label className="dc-row" style={{ gap: 6 }}>
              <div style={{ fontSize: 13, fontWeight: 800 }}>Email</div>
              <input
                className="dc-input"
                value={form.email}
                onChange={(e) => setForm((s) => ({ ...s, email: e.target.value }))}
                autoComplete="email"
                placeholder="you@example.com"
                required
              />
            </label>

            <label className="dc-row" style={{ gap: 6 }}>
              <div style={{ fontSize: 13, fontWeight: 800 }}>Password</div>
              <input
                className="dc-input"
                type="password"
                value={form.password}
                onChange={(e) => setForm((s) => ({ ...s, password: e.target.value }))}
                autoComplete="current-password"
                placeholder="••••••••"
                required
              />
            </label>

            {state.error ? (
              <div style={{ color: 'var(--dc-danger)', fontWeight: 800, fontSize: 13 }}>
                {state.error}
              </div>
            ) : null}

            <button className="dc-btn dc-btn-primary" disabled={state.loading}>
              {state.loading ? 'Signing in…' : 'Sign in'}
            </button>
          </form>

          <div style={{ marginTop: 12, fontSize: 13, color: 'var(--dc-muted)' }}>
            No account?{' '}
            <Link to="/register" style={{ fontWeight: 900, color: 'var(--dc-primary)' }}>
              Create one
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
}

