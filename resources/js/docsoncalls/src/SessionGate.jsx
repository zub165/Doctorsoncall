import React from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiPaths, tokenStore } from './api.js';

function getRoleFromMe(me) {
  const v =
    (me && (me.role ?? me.portal ?? me.user_role))?.toString()?.toLowerCase()?.trim() ||
    '';
  return v;
}

function initialTabIndex(role) {
  const r = (role || '').toLowerCase();
  const isAdmin = r === 'admin' || r === 'administrator' || r === 'staff';
  const isDoctor = r === 'doctor' || r === 'provider' || r === 'physician';
  if (isAdmin) return 16;
  if (isDoctor) return 6;
  return 0;
}

export function SessionGate() {
  const nav = useNavigate();
  const [state, setState] = React.useState({
    loading: true,
    error: '',
  });

  React.useEffect(() => {
    let alive = true;
    (async () => {
      const token = tokenStore.read();
      if (!token) {
        if (!alive) return;
        setState({ loading: false, error: '' });
        nav('/login', { replace: true });
        return;
      }

      try {
        const { data } = await api.get(ApiPaths.docOnCallMe);
        const role = getRoleFromMe(data);
        const idx = initialTabIndex(role);
        if (!alive) return;
        setState({ loading: false, error: '' });
        nav(`/shell/${idx}`, { replace: true });
      } catch (e) {
        tokenStore.clear();
        if (!alive) return;
        setState({ loading: false, error: 'Session expired. Please sign in again.' });
        nav('/login', { replace: true });
      }
    })();
    return () => {
      alive = false;
    };
  }, [nav]);

  if (!state.loading) return null;

  return (
    <div className="dc-center">
      <div className="dc-card dc-center-card">
        <div
          style={{
            width: 64,
            height: 64,
            borderRadius: 999,
            margin: '0 auto 14px',
            display: 'grid',
            placeItems: 'center',
            background: 'rgba(14,165,164,0.10)',
            color: 'var(--dc-primary)',
            fontWeight: 900,
            letterSpacing: 0.2,
          }}
        >
          DC
        </div>
        <div style={{ fontWeight: 800, fontSize: 18, marginBottom: 6 }}>Loading Doctor On Call…</div>
        <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>
          {state.error || 'Please wait…'}
        </div>
      </div>
    </div>
  );
}

