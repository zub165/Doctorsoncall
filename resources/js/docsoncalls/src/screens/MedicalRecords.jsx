import React from 'react';
import { api, ApiPaths } from '../api.js';

export function MedicalRecords() {
  const [tab, setTab] = React.useState('records'); // records | ai
  const [prompt, setPrompt] = React.useState('');
  const [ai, setAi] = React.useState({ loading: false, error: '', data: null });
  const [impOpen, setImpOpen] = React.useState(false);
  const [imp, setImp] = React.useState({
    source_url: '',
    patient_email: '',
    patient_hint: '',
    raw_payload: '',
    ai_summary: '',
  });
  const [impState, setImpState] = React.useState({ loading: false, ok: '', error: '' });
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
      const { data } = await api.post(ApiPaths.medicalRecordsAiAssist, { query: q });
      setAi({ loading: false, error: '', data });
    } catch (err) {
      const msg = err?.response?.data?.message || err?.response?.data?.detail || 'AI request failed';
      setAi({ loading: false, error: msg.toString(), data: null });
    }
  }

  function exportRecords() {
    const items = Array.isArray(state.items) ? state.items : [];
    const payload = {
      exported_at: new Date().toISOString(),
      count: items.length,
      records: items,
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'medical-records.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  async function submitImport(e) {
    e?.preventDefault?.();
    setImpState({ loading: true, ok: '', error: '' });
    try {
      const payload = {
        source_url: imp.source_url,
        patient_email: imp.patient_email,
        patient_hint: imp.patient_hint,
        raw_payload: imp.raw_payload,
        ai_summary: imp.ai_summary,
      };
      const { data } = await api.post(ApiPaths.importsSubmit, payload);
      const importId = data?.data?.import_id ?? data?.import_id;
      setImpState({ loading: false, ok: importId ? `Submitted (import #${importId}).` : 'Submitted.', error: '' });
      setImpOpen(false);
      setImp({ source_url: '', patient_email: '', patient_hint: '', raw_payload: '', ai_summary: '' });
    } catch (err) {
      const msg =
        err?.response?.data?.message ||
        err?.response?.data?.detail ||
        (err?.response?.data?.errors ? JSON.stringify(err.response.data.errors) : '') ||
        err?.message ||
        'Import submit failed';
      setImpState({ loading: false, ok: '', error: msg.toString() });
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
          <button className="dc-tab" type="button" data-active={impOpen ? 'true' : 'false'} onClick={() => setImpOpen((v) => !v)}>
            <span aria-hidden="true">＋</span>
            Import
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
              <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                <button className="dc-btn" type="button" onClick={exportRecords} style={{ fontWeight: 950 }} disabled={state.loading}>
                  Export
                </button>
                <button className="dc-btn dc-btn-primary" type="button" onClick={() => setImpOpen(true)} style={{ fontWeight: 950 }}>
                  + Import
                </button>
              </div>
            </div>
          </div>

          {impState.error ? (
            <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
              {impState.error}
            </div>
          ) : impState.ok ? (
            <div className="dc-card" style={{ color: 'var(--dc-primary-dark)', fontWeight: 950 }}>
              {impState.ok}
            </div>
          ) : null}

          {impOpen ? (
            <div className="dc-card" style={{ padding: 16 }}>
              <div style={{ fontWeight: 950, fontSize: 16, marginBottom: 10 }}>Submit import</div>
              <form className="dc-row" onSubmit={submitImport}>
                <input
                  className="dc-input"
                  placeholder="Source URL (required)"
                  value={imp.source_url}
                  onChange={(e) => setImp((s) => ({ ...s, source_url: e.target.value }))}
                  required
                />
                <input
                  className="dc-input"
                  placeholder="Patient email (optional)"
                  value={imp.patient_email}
                  onChange={(e) => setImp((s) => ({ ...s, patient_email: e.target.value }))}
                />
                <input
                  className="dc-input"
                  placeholder="Patient hint (optional)"
                  value={imp.patient_hint}
                  onChange={(e) => setImp((s) => ({ ...s, patient_hint: e.target.value }))}
                />
                <textarea
                  className="dc-input"
                  rows={4}
                  placeholder="Raw payload (JSON or text)"
                  value={imp.raw_payload}
                  onChange={(e) => setImp((s) => ({ ...s, raw_payload: e.target.value }))}
                />
                <textarea
                  className="dc-input"
                  rows={3}
                  placeholder="AI summary (optional)"
                  value={imp.ai_summary}
                  onChange={(e) => setImp((s) => ({ ...s, ai_summary: e.target.value }))}
                />
                <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                  <button className="dc-btn" type="button" onClick={() => setImpOpen(false)} style={{ fontWeight: 950 }}>
                    Cancel
                  </button>
                  <button className="dc-btn dc-btn-primary" disabled={impState.loading} style={{ fontWeight: 950 }}>
                    {impState.loading ? 'Submitting…' : 'Submit import'}
                  </button>
                </div>
              </form>
            </div>
          ) : null}

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

