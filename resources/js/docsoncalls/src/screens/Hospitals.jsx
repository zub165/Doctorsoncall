import React from 'react';
import { api, ApiPaths } from '../api.js';

export function Hospitals() {
  const [state, setState] = React.useState({
    loading: true,
    items: [],
    error: '',
  });
  const [q, setQ] = React.useState('');
  const [kind, setKind] = React.useState('all'); // all | er | urgent

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const { data } = await api.get(ApiPaths.hospitals);
        const items = Array.isArray(data) ? data : data?.results || [];
        if (!alive) return;
        setState({ loading: false, items, error: '' });
      } catch {
        if (!alive) return;
        setState({ loading: false, items: [], error: 'Failed to load hospitals.' });
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const items = React.useMemo(() => {
    const qq = q.trim().toLowerCase();
    return (state.items || [])
      .filter((h) => {
        if (!qq) return true;
        const s = `${h?.name ?? ''} ${h?.title ?? ''} ${h?.address ?? ''} ${h?.city ?? ''} ${h?.type ?? ''} ${h?.kind ?? ''}`.toLowerCase();
        return s.includes(qq);
      })
      .filter((h) => {
        if (kind === 'all') return true;
        const t = (h?.type || h?.kind || '').toString().toLowerCase();
        if (kind === 'er') return t.includes('emergency');
        if (kind === 'urgent') return t.includes('urgent');
        return true;
      });
  }, [state.items, q, kind]);

  const openCount = React.useMemo(() => {
    let n = 0;
    for (const h of items) {
      if (h?.is_open === true || h?.open === true || h?.status === 'open') n += 1;
    }
    return n;
  }, [items]);

  const mapUrl = React.useMemo(() => {
    // Lightweight OSM embed. If API returns lat/lng on any item, center there; otherwise default to Bay Area.
    const first = items.find((x) => Number.isFinite(Number(x?.lat)) && Number.isFinite(Number(x?.lng)));
    const lat = first ? Number(first.lat) : 37.3382;
    const lng = first ? Number(first.lng) : -121.8863;
    const dLat = 0.06;
    const dLng = 0.09;
    const left = lng - dLng;
    const right = lng + dLng;
    const top = lat + dLat;
    const bottom = lat - dLat;
    return `https://www.openstreetmap.org/export/embed.html?bbox=${encodeURIComponent(
      `${left},${bottom},${right},${top}`,
    )}&layer=mapnik&marker=${encodeURIComponent(`${lat},${lng}`)}`;
  }, [items]);

  function badge(text, tone) {
    const bg =
      tone === 'ok'
        ? 'rgba(34, 197, 94, 0.14)'
        : tone === 'warn'
          ? 'rgba(245, 158, 11, 0.14)'
          : tone === 'info'
            ? 'rgba(59, 130, 246, 0.14)'
            : 'rgba(211, 47, 47, 0.12)';
    const fg =
      tone === 'ok'
        ? '#166534'
        : tone === 'warn'
          ? '#92400e'
          : tone === 'info'
            ? '#1d4ed8'
            : 'var(--dc-primary-dark)';
    return (
      <span
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '6px 10px',
          borderRadius: 999,
          fontSize: 12,
          fontWeight: 900,
          background: bg,
          color: fg,
          border: '1px solid rgba(229,231,235,0.9)',
          whiteSpace: 'nowrap',
        }}
      >
        {text}
      </span>
    );
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-hero" style={{ padding: 16 }}>
        <div className="dc-hero-title">Hospitals</div>
        <div className="dc-hero-sub">Search by name, address, type…</div>
      </div>

      <div className="dc-card" style={{ padding: 14 }}>
        <div style={{ display: 'grid', gap: 12 }}>
          <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
            <div
              style={{
                width: 38,
                height: 38,
                borderRadius: 999,
                display: 'grid',
                placeItems: 'center',
                background: 'rgba(211, 47, 47, 0.12)',
                border: '1px solid rgba(211, 47, 47, 0.25)',
                fontWeight: 900,
                color: 'var(--dc-primary-dark)',
              }}
            >
              ⌕
            </div>
            <input
              className="dc-input"
              placeholder="Search by name, address, type…"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              style={{ fontWeight: 700 }}
            />
          </div>

          <div className="dc-chip-row">
            <button type="button" className="dc-chip" data-active={kind === 'all' ? 'true' : 'false'} onClick={() => setKind('all')}>
              All
            </button>
            <button type="button" className="dc-chip" data-active={kind === 'er' ? 'true' : 'false'} onClick={() => setKind('er')}>
              Emergency Room
            </button>
            <button
              type="button"
              className="dc-chip"
              data-active={kind === 'urgent' ? 'true' : 'false'}
              onClick={() => setKind('urgent')}
            >
              Urgent Care
            </button>
          </div>
        </div>
      </div>

      {state.loading ? (
        <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
          Loading…
        </div>
      ) : state.error ? (
        <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
          {state.error}
        </div>
      ) : items.length === 0 ? (
        <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
          No results.
        </div>
      ) : (
        <div className="dc-row" style={{ gap: 14 }}>
          <div className="dc-card" style={{ padding: 0, overflow: 'hidden' }}>
            <div style={{ height: 220, background: '#f1f5f9' }}>
              <iframe
                title="OpenStreetMap"
                src={mapUrl}
                style={{ border: 0, width: '100%', height: '100%' }}
                loading="lazy"
                referrerPolicy="no-referrer-when-downgrade"
              />
            </div>
            <div style={{ padding: 10, fontSize: 12, color: 'var(--dc-muted)', display: 'flex', justifyContent: 'space-between', gap: 10 }}>
              <span>© OpenStreetMap contributors</span>
              <span>Markers: GET /api/hospitals/</span>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '0 2px' }}>
            <div style={{ fontWeight: 950, fontSize: 18 }}>{items.length} Results</div>
            {openCount ? (
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, color: '#166534', fontWeight: 900 }}>
                <span
                  style={{
                    width: 18,
                    height: 18,
                    borderRadius: 999,
                    background: 'rgba(34,197,94,0.16)',
                    display: 'grid',
                    placeItems: 'center',
                    border: '1px solid rgba(34,197,94,0.28)',
                  }}
                >
                  ✓
                </span>
                {openCount} Open
              </div>
            ) : null}
          </div>

          <div className="dc-row" style={{ gap: 12 }}>
            {items.slice(0, 30).map((h, idx) => {
              const name = (h?.name || h?.title || 'Hospital').toString();
              const address = (h?.address || h?.city || '').toString();
              const wait = h?.wait_minutes ?? h?.wait_time_minutes ?? h?.ai_wait_time_minutes;
              const rating = h?.rating ?? h?.stars;
              const ai = h?.ai_score ?? h?.ai ?? h?.triage_score;
              const isOpen = h?.is_open === true || h?.open === true || h?.status === 'open';
              const type = (h?.type || h?.kind || h?.category || '').toString();
              return (
                <div
                  key={h?.uuid || h?.id || idx}
                  className="dc-card"
                  style={{
                    padding: 14,
                    display: 'grid',
                    gap: 10,
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'flex-start' }}>
                    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
                      <div
                        style={{
                          width: 44,
                          height: 44,
                          borderRadius: 14,
                          background: 'rgba(211, 47, 47, 0.08)',
                          border: '1px solid rgba(211, 47, 47, 0.16)',
                          display: 'grid',
                          placeItems: 'center',
                          fontWeight: 900,
                          color: 'var(--dc-primary-dark)',
                        }}
                      >
                        ✚
                      </div>
                      <div>
                        <div style={{ fontWeight: 950, fontSize: 16 }}>{name}</div>
                        <div style={{ color: 'var(--dc-muted)', fontSize: 13, marginTop: 2 }}>{address}</div>
                      </div>
                    </div>
                    <div style={{ color: 'var(--dc-muted)', fontWeight: 900 }}>›</div>
                  </div>

                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10 }}>
                    {Number.isFinite(Number(wait)) ? badge(`~${Number(wait)} min wait`, 'warn') : null}
                    {Number.isFinite(Number(rating)) ? badge(`${Number(rating).toFixed(1)} ★`, 'info') : null}
                    {Number.isFinite(Number(ai)) ? badge(`AI ${Number(ai).toFixed(1)}`, 'danger') : null}
                    {isOpen ? badge('Open', 'ok') : null}
                  </div>

                  {type ? <div style={{ marginTop: 2 }}>{badge(type, 'info')}</div> : null}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

