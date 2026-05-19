import React from 'react';
import { mapsApi, api as emrApi, ApiPaths } from '../api.js';
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet';
import L from 'leaflet';

export function Hospitals() {
  const [state, setState] = React.useState({
    loading: true,
    items: [],
    error: '',
  });
  const [q, setQ] = React.useState('');
  const [kind, setKind] = React.useState('all'); // all | er | urgent
  const [wait, setWait] = React.useState({ loading: false, error: '', byId: {} });
  const [geo, setGeo] = React.useState({ status: 'idle', error: '', lat: null, lon: null }); // idle | requesting | ok | denied | error

  async function loadHospitals({ lat = null, lon = null } = {}) {
    setState((s) => ({ ...s, loading: true, error: '' }));
    let alive = true;
    try {
      let data;

      // Prefer nearby search when we have coordinates.
      if (Number.isFinite(Number(lat)) && Number.isFinite(Number(lon))) {
        try {
          const res = await emrApi.get(ApiPaths.hospitalsSearch, { params: { lat, lon } });
          data = res.data;
        } catch (e) {
          // Some deployments don't support geo search yet (or error). Fallback to list.
          const res2 = await emrApi.get(ApiPaths.hospitals);
          data = res2.data;
        }
      } else {
        try {
          const res = await mapsApi.get(ApiPaths.hospitals);
          data = res.data;
        } catch (e) {
          const code = Number(e?.response?.status);
          // Some deployments require auth on Maps API. Fallback to EMR hospitals list.
          if (code === 401 || code === 403) {
            const res2 = await emrApi.get(ApiPaths.hospitals);
            data = res2.data;
          } else {
            throw e;
          }
        }
      }

      const items = Array.isArray(data) ? data : data?.results || data?.data?.results || data?.data || [];
      if (!alive) return;
      setState({ loading: false, items, error: '' });
    } catch (e) {
      if (!alive) return;
      const msg = e?.response?.data?.message || e?.message || 'Failed to load hospitals.';
      setState({ loading: false, items: [], error: msg.toString() });
    }
    return () => {
      alive = false;
    };
  }

  async function useMyLocation() {
    setGeo({ status: 'requesting', error: '', lat: null, lon: null });
    if (!navigator?.geolocation) {
      setGeo({ status: 'error', error: 'Geolocation not supported in this browser.', lat: null, lon: null });
      return;
    }
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const lat = pos?.coords?.latitude;
        const lon = pos?.coords?.longitude;
        setGeo({ status: 'ok', error: '', lat, lon });
        await loadHospitals({ lat, lon });
      },
      async (err) => {
        const msg = err?.message || 'Location permission denied.';
        setGeo({ status: err?.code === 1 ? 'denied' : 'error', error: msg.toString(), lat: null, lon: null });
        await loadHospitals();
      },
      { enableHighAccuracy: false, timeout: 8000, maximumAge: 120000 },
    );
  }

  React.useEffect(() => {
    let alive = true;
    (async () => {
      // Try to use browser location on first load; fall back gracefully if denied.
      try {
        await useMyLocation();
      } catch {
        await loadHospitals();
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  async function refreshWaitTime(hospitalId) {
    if (!hospitalId) return;
    setWait((s) => ({ ...s, loading: true, error: '' }));
    try {
      let data;
      try {
        const res = await mapsApi.get('hospitals/wait-times/', { params: { hospital_id: hospitalId } });
        data = res.data;
      } catch {
        // Back-compat: some deployments expose wait-time via EMR proxy (`/api/er-wait-times/`).
        const res = await emrApi.get(ApiPaths.erWaitTimes, { params: { hospital_id: hospitalId } });
        data = res.data;
      }
      setWait((s) => ({
        loading: false,
        error: '',
        byId: { ...s.byId, [hospitalId]: data },
      }));
    } catch (e) {
      const msg = e?.response?.data?.message || e?.message || 'Failed to load wait time';
      setWait((s) => ({ ...s, loading: false, error: msg.toString() }));
    }
  }

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

  const mapCenter = React.useMemo(() => {
    const first = items.find((x) => Number.isFinite(Number(x?.lat)) && Number.isFinite(Number(x?.lng)));
    const lat = first ? Number(first.lat) : (Number.isFinite(Number(geo.lat)) ? Number(geo.lat) : 27.9506);
    const lng = first ? Number(first.lng) : (Number.isFinite(Number(geo.lon)) ? Number(geo.lon) : -82.4572);
    return [lat, lng];
  }, [items, geo.lat, geo.lon]);

  const markers = React.useMemo(() => {
    return items
      .map((h) => {
        const lat = Number(h?.lat);
        const lng = Number(h?.lng);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
        return { h, lat, lng };
      })
      .filter(Boolean);
  }, [items]);

  const markerIcon = React.useMemo(() => {
    return L.divIcon({
      className: '',
      html:
        '<div style="width:22px;height:22px;border-radius:999px;background:rgba(211,47,47,0.95);border:3px solid rgba(255,255,255,0.95);box-shadow:0 8px 18px rgba(31,41,55,0.18)"></div>',
      iconSize: [22, 22],
      iconAnchor: [11, 11],
    });
  }, []);

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
            <button
              type="button"
              className="dc-btn"
              onClick={() => useMyLocation()}
              style={{ padding: '10px 12px', borderRadius: 14, fontWeight: 950 }}
              title="Use my location"
            >
              📍
            </button>
          </div>
          {geo.status !== 'idle' ? (
            <div style={{ fontSize: 12, fontWeight: 800, color: geo.status === 'ok' ? 'rgba(22,101,52,0.9)' : 'rgba(146,64,14,0.95)' }}>
              {geo.status === 'requesting'
                ? 'Getting your location…'
                : geo.status === 'ok'
                  ? `Using your location: ${Number(geo.lat).toFixed(4)}, ${Number(geo.lon).toFixed(4)}`
                  : `Location not used: ${geo.error || 'permission denied'}`}
            </div>
          ) : null}

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
            <div className="dc-map-wrap" style={{ background: '#f1f5f9' }}>
              <MapContainer
                center={mapCenter}
                zoom={10}
                style={{ height: '100%', width: '100%' }}
                scrollWheelZoom={false}
              >
                <TileLayer
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />
                {markers.slice(0, 120).map(({ h, lat, lng }) => (
                  <Marker key={h?.uuid || h?.id || `${lat},${lng}`} position={[lat, lng]} icon={markerIcon}>
                    <Popup>
                      <div style={{ fontWeight: 900 }}>{(h?.name || h?.title || 'Hospital').toString()}</div>
                      <div style={{ color: '#6b7280', fontWeight: 700, marginTop: 6 }}>
                        {(h?.address || h?.city || '').toString()}
                      </div>
                    </Popup>
                  </Marker>
                ))}
              </MapContainer>
            </div>
            <div
              style={{
                padding: 10,
                fontSize: 12,
                color: 'var(--dc-muted)',
                display: 'flex',
                justifyContent: 'space-between',
                gap: 10,
              }}
            >
              <span>© OpenStreetMap contributors</span>
              <span>Markers: Maps API</span>
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
              const waitMins = h?.wait_minutes ?? h?.wait_time_minutes ?? h?.ai_wait_time_minutes;
              const rating = h?.rating ?? h?.stars;
              const ai = h?.ai_score ?? h?.ai ?? h?.triage_score;
              const isOpen = h?.is_open === true || h?.open === true || h?.status === 'open';
              const type = (h?.type || h?.kind || h?.category || '').toString();
              const hid = h?.uuid || h?.id;
              const upstream = hid ? waitStateFromUpstream(waitStateById(wait, hid)) : null;
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
                    {Number.isFinite(Number(waitMins)) ? badge(`~${Number(waitMins)} min wait`, 'warn') : null}
                    {upstream?.minutes != null ? badge(`~${upstream.minutes} min wait`, 'warn') : null}
                    {Number.isFinite(Number(rating)) ? badge(`${Number(rating).toFixed(1)} ★`, 'info') : null}
                    {Number.isFinite(Number(ai)) ? badge(`AI ${Number(ai).toFixed(1)}`, 'danger') : null}
                    {isOpen ? badge('Open', 'ok') : null}
                  </div>

                  {type ? <div style={{ marginTop: 2 }}>{badge(type, 'info')}</div> : null}

                  {hid ? (
                    <button
                      className="dc-btn"
                      type="button"
                      disabled={wait.loading}
                      onClick={() => refreshWaitTime(hid)}
                      style={{ fontWeight: 950 }}
                    >
                      {wait.loading ? 'Refreshing…' : 'Refresh wait time'}
                    </button>
                  ) : null}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

function waitStateById(waitState, id) {
  return waitState?.byId?.[id] ?? null;
}

function waitStateFromUpstream(data) {
  if (!data) return null;
  // Upstream shape varies; try common fields
  const minutes =
    data?.wait_time_prediction ??
    data?.data?.wait_time_prediction ??
    data?.wait_time ??
    data?.data?.wait_time ??
    null;
  const m = Number(minutes);
  return Number.isFinite(m) ? { minutes: Math.round(m) } : null;
}

