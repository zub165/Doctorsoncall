import React from 'react';
import { api, ApiPaths } from '../api.js';

export function MedicalRecords() {
  const [tab, setTab] = React.useState('records'); // records | ai
  const [prompt, setPrompt] = React.useState('');
  const [ai, setAi] = React.useState({ loading: false, error: '', data: null });
  const [state, setState] = React.useState({
    loading: true,
    items: [],
    error: '',
  });

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const { data } = await api.get(ApiPaths.medicalRecords);
        const items = Array.isArray(data) ? data : data?.results || [];
        if (!alive) return;
        setState({ loading: false, items, error: '' });
      } catch {
        if (!alive) return;
        setState({ loading: false, items: [], error: 'Failed to load medical records.' });
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  async function runAi(e) {
    e?.preventDefault?.();
    const q = prompt.trim();
    if (!q) return;
    setAi({ loading: true, error: '', data: null });
    try {
      const { data } = await api.post(ApiPaths.medicalRecordsAiAssist, { prompt: q });
      setAi({ loading: false, error: '', data });
    } catch (err) {
      const msg = err?.response?.data?.message || err?.response?.data?.detail || 'AI request failed';
      setAi({ loading: false, error: msg.toString(), data: null });
    }
  }

  return (
    <div className="dc-row" style={{ gap: 14 }}>
      <div className="dc-appbar">
        <div className="dc-appbar-title">
          <h2>Medical records & AI</h2>
          <span style={{ opacity: 0.9, fontWeight: 900 }}>☰</span>
        </div>
        <div className="dc-tabs" role="tablist" aria-label="Medical records tabs">
          <button className="dc-tab" type="button" data-active={tab === 'records' ? 'true' : 'false'} onClick={() => setTab('records')}>
            <span aria-hidden="true">🗂️</span>
            Records
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'ai' ? 'true' : 'false'} onClick={() => setTab('ai')}>
            <span aria-hidden="true">🧠</span>
            AI assistant
          </button>
          <button className="dc-tab" type="button" data-active="false" disabled>
            <span aria-hidden="true">＋</span>
            Create
          </button>
        </div>
      </div>

      {tab === 'ai' ? (
        <div className="dc-row" style={{ gap: 14 }}>
          <div className="dc-card" style={{ background: '#eef2ff', borderColor: 'rgba(99, 102, 241, 0.25)' }}>
            <div style={{ fontWeight: 900, color: '#3730a3' }}>
              AI responses are informational only — not a diagnosis. Always follow your clinician&apos;s advice.
              Backend must implement POST …/medical-records/ai-assist/
            </div>
          </div>

          <form className="dc-row" onSubmit={runAi} style={{ gap: 12 }}>
            <input className="dc-input" placeholder="Ask about your records" value={prompt} onChange={(e) => setPrompt(e.target.value)} />
            {ai.error ? <div style={{ color: 'var(--dc-danger)', fontWeight: 900, fontSize: 13 }}>{ai.error}</div> : null}
            {ai.data ? (
              <div className="dc-card" style={{ background: 'white' }}>
                <pre style={{ margin: 0, whiteSpace: 'pre-wrap', fontSize: 13 }}>{JSON.stringify(ai.data, null, 2)}</pre>
              </div>
            ) : null}
            <button className="dc-btn dc-btn-primary" disabled={ai.loading} style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}>
              {ai.loading ? 'Working…' : 'Get AI insight'}
            </button>
          </form>
        </div>
      ) : (
        <div className="dc-row" style={{ gap: 14 }}>
          <div className="dc-card" style={{ padding: 16, background: '#f6e7e7' }}>
            <div style={{ display: 'flex', gap: 12, alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                <div className="dc-avatar">🔗</div>
                <div>
                  <div style={{ fontWeight: 950, fontSize: 18 }}>Import via API link</div>
                  <div style={{ color: 'var(--dc-muted)', fontSize: 13, fontWeight: 800 }}>
                    Fetch a facility API → AI summary → Admin merges into your file
                  </div>
                </div>
              </div>
              <button className="dc-btn dc-btn-primary" type="button" disabled style={{ fontWeight: 950 }}>
                + Create
              </button>
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
          ) : state.items.length === 0 ? (
            <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
              No records returned by API.
            </div>
          ) : (
            <div className="dc-list">
              {state.items.slice(0, 40).map((r, idx) => (
                <div key={r?.uuid || r?.id || idx} className="dc-list-row">
                  <div className="dc-list-left">
                    <div className="dc-avatar">📄</div>
                    <div className="dc-list-text">
                      <div className="dc-list-title">{(r?.title || r?.type || 'Record').toString()}</div>
                      <div className="dc-list-sub">{(r?.created_at || r?.date || '').toString()}</div>
                    </div>
                  </div>
                  <div className="dc-chevron">›</div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

