import React from 'react';

export function Placeholder({ title, tab }) {
  return (
    <div className="dc-card">
      <div style={{ fontWeight: 900, fontSize: 18, marginBottom: 6 }}>{title}</div>
      <div style={{ color: 'var(--dc-muted)', marginBottom: 12 }}>
        This screen is scaffolded to match Flutter tab index <b>{tab}</b>.
      </div>
      <div style={{ color: 'var(--dc-muted)', fontSize: 13 }}>
        Next step is to wire the exact API calls and UI widgets from `flutter_emr/lib/screens/`.
      </div>
    </div>
  );
}

