import React from 'react';
import { Link } from 'react-router-dom';
import { api, ApiPaths } from '../api.js';

function ymd(d) {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

function addMonths(date, delta) {
  const d = new Date(date);
  d.setDate(1);
  d.setMonth(d.getMonth() + delta);
  return d;
}

function startOfCalendarGrid(monthDate) {
  const d = new Date(monthDate);
  d.setDate(1);
  // JS: 0=Sun..6=Sat. We want a Sunday-start grid like typical US calendars.
  const offset = d.getDay();
  d.setDate(d.getDate() - offset);
  return d;
}

export function Appointments({ isAdmin = false, isDoctor = false } = {}) {
  const [state, setState] = React.useState({
    loading: true,
    items: [],
    error: '',
  });
  const [month, setMonth] = React.useState(() => {
    const d = new Date();
    d.setDate(1);
    return d;
  });
  const [selected, setSelected] = React.useState(() => ymd(new Date()));

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const path = isAdmin || isDoctor ? ApiPaths.allAppointments : ApiPaths.myAppointments;
        const { data } = await api.get(path);
        const root = data ?? {};
        const d = root?.data ?? root;
        const items =
          (Array.isArray(root) && root) ||
          (Array.isArray(root?.results) && root.results) ||
          (Array.isArray(d) && d) ||
          (Array.isArray(d?.results) && d.results) ||
          (Array.isArray(d?.appointments) && d.appointments) ||
          (Array.isArray(root?.appointments) && root.appointments) ||
          [];
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
  }, [isAdmin, isDoctor]);

  const appts = React.useMemo(() => {
    return Array.isArray(state.items) ? state.items : [];
  }, [state.items]);

  const apptsOnSelected = React.useMemo(() => {
    const sel = selected;
    return appts.filter((a) => {
      const raw = (a?.date || a?.scheduled_at || a?.scheduledAt || a?.starts_at || a?.created_at || '').toString();
      // Accept `YYYY-MM-DD...` (ISO), or `MM/DD/YYYY` (US), etc.
      if (raw.startsWith(sel)) return true;
      const mdy = raw.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/);
      if (mdy) {
        const mm = String(mdy[1]).padStart(2, '0');
        const dd = String(mdy[2]).padStart(2, '0');
        const yyyy = String(mdy[3]);
        return `${yyyy}-${mm}-${dd}` === sel;
      }
      return false;
    });
  }, [appts, selected]);

  const gridStart = React.useMemo(() => startOfCalendarGrid(month), [month]);
  const days = React.useMemo(() => {
    const out = [];
    const d = new Date(gridStart);
    for (let i = 0; i < 42; i += 1) {
      out.push(new Date(d));
      d.setDate(d.getDate() + 1);
    }
    return out;
  }, [gridStart]);

  const today = ymd(new Date());
  const monthLabel = month.toLocaleString(undefined, { month: 'long', year: 'numeric' });

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Appointments</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
      </div>

      <div className="dc-calendar">
        <div className="dc-cal-header">
          <div className="dc-cal-month">{monthLabel}</div>
          <div style={{ display: 'flex', gap: 10 }}>
            <button className="dc-btn" type="button" onClick={() => setMonth((m) => addMonths(m, -1))}>
              ‹
            </button>
            <button className="dc-btn" type="button" onClick={() => setMonth((m) => addMonths(m, 1))}>
              ›
            </button>
          </div>
        </div>

        <div className="dc-cal-grid" aria-label="Calendar days of week">
          {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((x) => (
            <div key={x} className="dc-cal-dow">
              {x}
            </div>
          ))}
        </div>

        <div className="dc-cal-grid" aria-label="Calendar day grid">
          {days.map((d) => {
            const key = ymd(d);
            const muted = d.getMonth() !== month.getMonth();
            const isToday = key === today;
            const isSelected = key === selected;
            return (
              <div
                key={key}
                className="dc-cal-day"
                data-muted={muted ? 'true' : 'false'}
                data-today={isToday ? 'true' : 'false'}
                data-selected={isSelected ? 'true' : 'false'}
                onClick={() => setSelected(key)}
                role="button"
                tabIndex={0}
                onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ' ? setSelected(key) : null)}
              >
                {d.getDate()}
              </div>
            );
          })}
        </div>
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, padding: '0 2px' }}>
        <div style={{ fontWeight: 950, fontSize: 16 }}>Bookings on {selected}</div>
        <Link to="/shell/8" style={{ fontWeight: 950, color: 'var(--dc-primary)' }}>
          + Book
        </Link>
      </div>

      {state.loading ? (
        <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
          Loading…
        </div>
      ) : state.error ? (
        <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
          {state.error}
        </div>
      ) : apptsOnSelected.length === 0 ? (
        <div className="dc-card" style={{ textAlign: 'center', padding: 26 }}>
          <div style={{ fontSize: 54, opacity: 0.55, marginBottom: 8 }}>🗓️</div>
          <div style={{ fontWeight: 950, fontSize: 18 }}>No Appointments Yet</div>
          <div style={{ color: 'var(--dc-muted)', fontWeight: 800, marginTop: 6 }}>
            Your appointments will appear here
          </div>
          <div style={{ marginTop: 14 }}>
            <Link className="dc-btn dc-btn-primary" to="/shell/8" style={{ display: 'inline-block', padding: 14, borderRadius: 16, fontWeight: 950 }}>
              + Book Appointment
            </Link>
          </div>
        </div>
      ) : (
        <div className="dc-list">
          {apptsOnSelected.slice(0, 50).map((a, idx) => (
            <div className="dc-list-row" key={a?.id || a?.uuid || `a-${idx}`}>
              <div className="dc-list-left">
                <div className="dc-avatar">📅</div>
                <div className="dc-list-text">
                  <div className="dc-list-title">
                    {(() => {
                      const p = a?.patient || a?.patient_data || a?.client || null;
                      const prov = a?.provider || a?.doctor || a?.provider_data || null;
                      const patientName = (p?.name || p?.full_name || p?.fullName || p?.first_name || '').toString().trim();
                      const providerName = (prov?.full_name || prov?.name || prov?.fullName || '').toString().trim();
                      if (patientName && providerName) return `${patientName} → ${providerName}`;
                      if (providerName) return `With ${providerName}`;
                      if (patientName) return `Booked by ${patientName}`;
                      return (a?.title || a?.reason || 'Appointment').toString();
                    })()}
                  </div>
                  <div className="dc-list-sub">
                    {[
                      (a?.date || '').toString(),
                      (a?.time || '').toString(),
                      (a?.approved || a?.status || '').toString(),
                    ]
                      .map((x) => x.trim())
                      .filter(Boolean)
                      .join(' • ') || (a?.scheduled_at || a?.created_at || '').toString()}
                  </div>
                </div>
              </div>
              <div className="dc-chevron">›</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

