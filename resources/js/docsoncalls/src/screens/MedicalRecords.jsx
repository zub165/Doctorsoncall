import React from 'react';
import { api, ApiPaths } from '../api.js';

export function MedicalRecords() {
  const [tab, setTab] = React.useState('records'); // records | ai | docs | share
  const [prompt, setPrompt] = React.useState('');
  const [ai, setAi] = React.useState({ loading: false, error: '', data: null });
  const [impOpen, setImpOpen] = React.useState(false);
  const [docs, setDocs] = React.useState({ loading: true, items: [], error: '' });
  const [upload, setUpload] = React.useState({ loading: false, ok: '', error: '' });
  const [ocr, setOcr] = React.useState({ loading: false, ok: '', error: '', text: '' });
  const [picked, setPicked] = React.useState(null);
  const [activeDoc, setActiveDoc] = React.useState({ id: null, loading: false, error: '', data: null });
  const [share, setShare] = React.useState({
    note: '',
    provider_id: '',
    include_email: false,
    sending: false,
    error: '',
    ok: '',
  });
  const [shareMine, setShareMine] = React.useState({ loading: true, items: [], error: '' });
  const [providers, setProviders] = React.useState({ loading: true, items: [], error: '' });
  const [localShare, setLocalShare] = React.useState({ text: '', ok: '', error: '' });
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

  async function loadDocs() {
    setDocs((s) => ({ ...s, loading: true, error: '' }));
    try {
      const { data } = await api.get(ApiPaths.documents);
      const items = Array.isArray(data) ? data : data?.data?.results || data?.results || data?.data || [];
      setDocs({ loading: false, items: Array.isArray(items) ? items : [], error: '' });
    } catch (e) {
      const msg = e?.response?.data?.message || e?.message || 'Failed to load documents.';
      setDocs({ loading: false, items: [], error: msg.toString() });
    }
  }

  React.useEffect(() => {
    loadDocs();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function loadProviders() {
    setProviders({ loading: true, items: [], error: '' });
    try {
      const { data } = await api.get(ApiPaths.providers);
      const items = Array.isArray(data) ? data : data?.results || data?.data || [];
      setProviders({ loading: false, items: Array.isArray(items) ? items : [], error: '' });
    } catch (e) {
      const msg = e?.response?.data?.message || e?.message || 'Failed to load providers.';
      setProviders({ loading: false, items: [], error: msg.toString() });
    }
  }

  async function loadSharesMine() {
    setShareMine((s) => ({ ...s, loading: true, error: '' }));
    try {
      const { data } = await api.get(ApiPaths.sharesMine);
      const items = Array.isArray(data) ? data : data?.data?.results || data?.results || [];
      setShareMine({ loading: false, items: Array.isArray(items) ? items : [], error: '' });
    } catch (e) {
      const msg = e?.response?.data?.message || e?.message || 'Failed to load shares.';
      setShareMine({ loading: false, items: [], error: msg.toString() });
    }
  }

  React.useEffect(() => {
    loadProviders();
    loadSharesMine();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function sendShare(e) {
    e?.preventDefault?.();
    setShare((s) => ({ ...s, sending: true, error: '', ok: '' }));
    try {
      const provider_id = Number(share.provider_id);
      const note = share.note.trim();
      if (!provider_id || !note) throw new Error('Select doctor and write a note.');
      await api.post(ApiPaths.sharesCreate, {
        provider_id,
        patient_note: note,
        include_patient_email: Boolean(share.include_email),
      });
      setShare({ note: '', provider_id: '', include_email: false, sending: false, error: '', ok: 'Shared with doctor.' });
      loadSharesMine();
    } catch (err) {
      const msg = err?.response?.data?.message || err?.message || 'Share failed';
      setShare((s) => ({ ...s, sending: false, error: msg.toString(), ok: '' }));
    }
  }

  async function shareViaSystem() {
    const text = (localShare.text || '').trim();
    setLocalShare((s) => ({ ...s, ok: '', error: '' }));
    if (!text) {
      setLocalShare((s) => ({ ...s, error: 'Write something to share first.' }));
      return;
    }
    try {
      if (navigator.share) {
        await navigator.share({ text, title: 'Doctor On Call — share' });
        setLocalShare((s) => ({ ...s, ok: 'Shared.', error: '' }));
        return;
      }
      await navigator.clipboard?.writeText?.(text);
      setLocalShare((s) => ({
        ...s,
        ok: 'Copied to clipboard (share not supported in this browser).',
        error: '',
      }));
    } catch (e) {
      setLocalShare((s) => ({ ...s, error: (e?.message || 'Share failed').toString() }));
    }
  }

  function shareToWhatsApp() {
    const text = (localShare.text || '').trim();
    setLocalShare((s) => ({ ...s, ok: '', error: '' }));
    if (!text) {
      setLocalShare((s) => ({ ...s, error: 'Write something to share first.' }));
      return;
    }
    window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, '_blank', 'noreferrer');
  }

  function shareToSms() {
    const text = (localShare.text || '').trim();
    setLocalShare((s) => ({ ...s, ok: '', error: '' }));
    if (!text) {
      setLocalShare((s) => ({ ...s, error: 'Write something to share first.' }));
      return;
    }
    window.location.href = `sms:&body=${encodeURIComponent(text)}`;
  }

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

  async function uploadDoc(e) {
    e?.preventDefault?.();
    if (!picked) return;
    setUpload({ loading: true, ok: '', error: '' });
    try {
      const fd = new FormData();
      fd.append('file', picked);
      const { data } = await api.post(ApiPaths.documents, fd, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      const doc = data?.data?.document ?? data?.document;
      setUpload({ loading: false, ok: 'Uploaded.', error: '' });
      setPicked(null);
      await loadDocs();
      const id = doc?.id;
      if (id) setActiveDoc({ id, loading: false, error: '', data: doc });
    } catch (err) {
      const msg =
        err?.response?.data?.message ||
        err?.response?.data?.detail ||
        (err?.response?.data?.errors ? JSON.stringify(err.response.data.errors) : '') ||
        err?.message ||
        'Upload failed';
      setUpload({ loading: false, ok: '', error: msg.toString() });
    }
  }

  async function runOcrOnPicked(e) {
    e?.preventDefault?.();
    if (!picked) return;
    setOcr({ loading: true, ok: '', error: '', text: '' });
    try {
      const isPdf = (picked?.type || '').toLowerCase().includes('pdf') || picked?.name?.toLowerCase?.().endsWith?.('.pdf');
      const fd = new FormData();
      fd.append('file', picked);
      fd.append('lang', 'eng');
      if (isPdf) fd.append('dpi', '200');
      const path = isPdf ? ApiPaths.ocrPdf : ApiPaths.ocrImage;
      const { data } = await api.post(path, fd, { headers: { 'Content-Type': 'multipart/form-data' } });
      const text =
        (data?.data?.text ?? data?.text ?? data?.data?.ocr_text ?? data?.ocr_text ?? data?.result ?? '').toString();
      setOcr({ loading: false, ok: 'OCR done.', error: '', text: text || JSON.stringify(data ?? {}, null, 2) });
    } catch (err) {
      const msg =
        err?.response?.data?.message ||
        err?.response?.data?.detail ||
        (err?.response?.data?.errors ? JSON.stringify(err.response.data.errors) : '') ||
        err?.message ||
        'OCR failed';
      setOcr({ loading: false, ok: '', error: msg.toString(), text: '' });
    }
  }

  async function processDoc(id) {
    if (!id) return;
    setActiveDoc({ id, loading: true, error: '', data: null });
    try {
      const { data } = await api.post(ApiPaths.documentDetail(id));
      setActiveDoc({ id, loading: false, error: '', data });
      await loadDocs();
    } catch (err) {
      const msg = err?.response?.data?.message || err?.response?.data?.detail || err?.message || 'Process failed';
      setActiveDoc({ id, loading: false, error: msg.toString(), data: null });
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
          <button className="dc-tab" type="button" data-active={tab === 'docs' ? 'true' : 'false'} onClick={() => setTab('docs')}>
            <span aria-hidden="true">📎</span>
            Documents
          </button>
          <button className="dc-tab" type="button" data-active={tab === 'share' ? 'true' : 'false'} onClick={() => setTab('share')}>
            <span aria-hidden="true">↗️</span>
            Share
          </button>
        </div>
      </div>

      {tab === 'share' ? (
        <div className="dc-row" style={{ gap: 14 }}>
          <div className="dc-card" style={{ padding: 16 }}>
            <div style={{ fontWeight: 950, marginBottom: 8 }}>HIPAA / Safety disclaimer</div>
            <div style={{ color: 'var(--dc-muted)', fontWeight: 800, fontSize: 13 }}>
              For care coordination only. Do not share highly sensitive information unless necessary. AI summaries may be incomplete; clinicians must verify against source records. If emergency, call local emergency services.
            </div>
          </div>

          <div className="dc-card" style={{ padding: 16 }}>
            <div style={{ fontWeight: 950, marginBottom: 8 }}>Share via apps (Bluetooth · Messages · WhatsApp)</div>
            <div style={{ color: 'var(--dc-muted)', fontWeight: 800, fontSize: 13 }}>
              Uses your device/browser share sheet when available.
            </div>
            <textarea
              className="dc-input"
              rows={4}
              placeholder="Text to share…"
              value={localShare.text}
              onChange={(e) => setLocalShare((s) => ({ ...s, text: e.target.value }))}
              style={{ marginTop: 10 }}
            />
            <div style={{ display: 'flex', gap: 12, marginTop: 12, flexWrap: 'wrap' }}>
              <button className="dc-btn dc-btn-primary" type="button" onClick={shareViaSystem} style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}>
                📤 Share
              </button>
              <button className="dc-btn" type="button" onClick={shareToWhatsApp} style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}>
                💬 WhatsApp
              </button>
              <button className="dc-btn" type="button" onClick={shareToSms} style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}>
                💬 Messages
              </button>
            </div>
            {localShare.error ? <div style={{ marginTop: 10, color: 'var(--dc-danger)', fontWeight: 900 }}>{localShare.error}</div> : null}
            {localShare.ok ? <div style={{ marginTop: 10, color: 'var(--dc-primary)', fontWeight: 950 }}>{localShare.ok}</div> : null}
          </div>

          <div className="dc-card" style={{ padding: 16 }}>
            <div style={{ fontWeight: 950, marginBottom: 10 }}>Share with doctor</div>
            <form className="dc-row" onSubmit={sendShare} style={{ gap: 12 }}>
              <select className="dc-input" value={share.provider_id} onChange={(e) => setShare((s) => ({ ...s, provider_id: e.target.value }))}>
                <option value="">Select doctor…</option>
                {(providers.items || []).map((p) => (
                  <option key={p?.id} value={p?.id}>
                    {(p?.full_name || p?.name || `Provider #${p?.id}`).toString()}
                  </option>
                ))}
              </select>
              <textarea
                className="dc-input"
                rows={5}
                placeholder="Symptoms, concerns, key history, questions…"
                value={share.note}
                onChange={(e) => setShare((s) => ({ ...s, note: e.target.value }))}
              />
              <label style={{ display: 'flex', gap: 10, alignItems: 'center', fontWeight: 850, color: 'rgba(17,24,39,0.8)' }}>
                <input type="checkbox" checked={share.include_email} onChange={(e) => setShare((s) => ({ ...s, include_email: e.target.checked }))} />
                Allow doctor to email me the summary
              </label>
              {share.error ? <div style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>{share.error}</div> : null}
              {share.ok ? <div style={{ color: 'var(--dc-primary)', fontWeight: 950 }}>{share.ok}</div> : null}
              <button className="dc-btn dc-btn-primary" disabled={share.sending} style={{ padding: 14, borderRadius: 16, fontWeight: 950 }}>
                {share.sending ? 'Sharing…' : 'Share'}
              </button>
            </form>
          </div>

          <div style={{ fontWeight: 950, fontSize: 16 }}>My shares</div>
          {shareMine.loading ? (
            <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
              Loading…
            </div>
          ) : shareMine.error ? (
            <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
              {shareMine.error}
            </div>
          ) : shareMine.items.length === 0 ? (
            <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
              No shares yet.
            </div>
          ) : (
            <div className="dc-list">
              {shareMine.items.slice(0, 50).map((s, idx) => (
                <div className="dc-list-row" key={s?.id || `s-${idx}`}>
                  <div className="dc-list-left">
                    <div className="dc-avatar">↗️</div>
                    <div className="dc-list-text">
                      <div className="dc-list-title">{(s?.provider?.full_name || 'Doctor').toString()}</div>
                      <div className="dc-list-sub">{(s?.ai_summary || s?.patient_note || '').toString().slice(0, 90)}</div>
                    </div>
                  </div>
                  <div className="dc-chevron">›</div>
                </div>
              ))}
            </div>
          )}
        </div>
      ) : tab === 'docs' ? (
        <div className="dc-row" style={{ gap: 14 }}>
          <div className="dc-card" style={{ padding: 16 }}>
            <div style={{ fontWeight: 950, fontSize: 18, marginBottom: 10 }}>Upload document (PDF or image)</div>
            <form className="dc-row" onSubmit={uploadDoc} style={{ gap: 10 }}>
              <input
                className="dc-input"
                type="file"
                accept="application/pdf,image/*,text/plain"
                onChange={(e) => setPicked(e.target.files?.[0] || null)}
              />
              {upload.error ? <div style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>{upload.error}</div> : null}
              {upload.ok ? <div style={{ color: 'var(--dc-primary-dark)', fontWeight: 900 }}>{upload.ok}</div> : null}
              <button className="dc-btn dc-btn-primary" disabled={upload.loading || !picked} style={{ fontWeight: 950, padding: 14, borderRadius: 16 }}>
                {upload.loading ? 'Uploading…' : 'Upload'}
              </button>
            </form>
            <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginTop: 10 }}>
              <button className="dc-btn" type="button" onClick={runOcrOnPicked} disabled={ocr.loading || !picked} style={{ fontWeight: 950 }}>
                {ocr.loading ? 'Running OCR…' : 'Run OCR (direct)'}
              </button>
              {ocr.error ? <div style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>{ocr.error}</div> : null}
              {ocr.ok ? <div style={{ color: 'var(--dc-primary-dark)', fontWeight: 900 }}>{ocr.ok}</div> : null}
            </div>
            {ocr.text ? (
              <div className="dc-card" style={{ marginTop: 12, background: 'white' }}>
                <div style={{ fontWeight: 950, marginBottom: 8 }}>OCR text</div>
                <pre style={{ margin: 0, whiteSpace: 'pre-wrap', fontSize: 12 }}>{ocr.text}</pre>
              </div>
            ) : null}
            <div style={{ marginTop: 10, color: 'var(--dc-muted)', fontSize: 12, fontWeight: 800 }}>
              After upload, click “Process” to run text extraction/OCR and generate the doctor report.
            </div>
          </div>

          {docs.loading ? (
            <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
              Loading documents…
            </div>
          ) : docs.error ? (
            <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
              {docs.error}
            </div>
          ) : docs.items.length === 0 ? (
            <div className="dc-card" style={{ color: 'var(--dc-muted)' }}>
              No documents yet.
            </div>
          ) : (
            <div className="dc-list">
              {docs.items.slice(0, 60).map((d) => {
                const doc = d?.document ?? d;
                const id = doc?.id;
                return (
                  <div key={id} className="dc-list-row" style={{ alignItems: 'flex-start' }}>
                    <div className="dc-list-left">
                      <div className="dc-avatar">📎</div>
                      <div className="dc-list-text">
                        <div className="dc-list-title">{(doc?.original_name || doc?.file || `Document #${id}`).toString()}</div>
                        <div className="dc-list-sub" style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                          <span>Status: {(doc?.status || 'uploaded').toString()}</span>
                          {doc?.created_at ? <span>• {doc.created_at.toString()}</span> : null}
                        </div>
                        {doc?.ai_summary ? (
                          <div className="dc-card" style={{ marginTop: 10, background: 'white' }}>
                            <pre style={{ margin: 0, whiteSpace: 'pre-wrap', fontSize: 13 }}>{doc.ai_summary.toString()}</pre>
                          </div>
                        ) : null}
                        {doc?.error_message ? (
                          <div style={{ marginTop: 8, color: 'var(--dc-danger)', fontWeight: 900 }}>{doc.error_message.toString()}</div>
                        ) : null}
                      </div>
                    </div>
                    <div style={{ display: 'grid', gap: 8, justifyItems: 'end' }}>
                      <button className="dc-btn" type="button" onClick={() => processDoc(id)} disabled={activeDoc.loading && activeDoc.id === id}>
                        {activeDoc.loading && activeDoc.id === id ? 'Processing…' : 'Process'}
                      </button>
                      {doc?.file_url ? (
                        <a className="dc-btn" href={doc.file_url.toString()} target="_blank" rel="noreferrer">
                          View
                        </a>
                      ) : null}
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {activeDoc.error ? (
            <div className="dc-card" style={{ color: 'var(--dc-danger)', fontWeight: 900 }}>
              {activeDoc.error}
            </div>
          ) : activeDoc.data ? (
            <div className="dc-card">
              <div style={{ fontWeight: 950, marginBottom: 8 }}>Processing result</div>
              <pre style={{ margin: 0, whiteSpace: 'pre-wrap', fontSize: 12 }}>{JSON.stringify(activeDoc.data, null, 2)}</pre>
            </div>
          ) : null}
        </div>
      ) : tab === 'ai' ? (
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

