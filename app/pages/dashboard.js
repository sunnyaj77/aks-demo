import { useEffect, useState } from 'react';

// Loads on the client so it exercises the full private path on every
// visit: browser -> this pod's /api/me and /api/system-status ->
// APIM -> backend -> Redis/Postgres -> back. Good page to bookmark while
// bringing the private networking up for the first time.
function StatusRow({ label, result }) {
  if (!result) return null;
  const ok = result.ok;
  return (
    <li>
      <strong>{label}:</strong>{' '}
      <span style={{ color: ok ? '#3f7d55' : '#b6473b' }}>{ok ? 'ok' : 'failed'}</span>
      {!ok && (result.reason || result.error) && (
        <span style={{ color: '#888' }}> — {result.reason || result.error}</span>
      )}
      {ok && result.latencyMs != null && <span style={{ color: '#888' }}> ({result.latencyMs}ms)</span>}
    </li>
  );
}

export default function Dashboard() {
  const [me, setMe] = useState({ loading: true });
  const [status, setStatus] = useState(null);

  useEffect(() => {
    fetch('/api/me')
      .then((r) => r.json().then((body) => ({ status: r.status, body })))
      .then(({ status: code, body }) => setMe({ loading: false, ok: code === 200, ...body }));

    fetch('/api/system-status')
      .then((r) => r.json())
      .then(setStatus)
      .catch((err) => setStatus({ error: String(err) }));
  }, []);

  return (
    <main style={{ fontFamily: 'sans-serif', padding: '3rem', maxWidth: 640 }}>
      <h1>Dashboard</h1>

      <section style={{ marginBottom: 24 }}>
        <h2>Session</h2>
        {me.loading && <p>checking…</p>}
        {!me.loading && me.ok && <p>Signed in as <strong>{me.username}</strong>.</p>}
        {!me.loading && !me.ok && (
          <p>
            Not signed in ({me.error}). <a href="/login">Go to login</a>.
          </p>
        )}
      </section>

      <section>
        <h2>System status</h2>
        <p style={{ color: '#666', fontSize: 14 }}>
          Each row is a separate hop through APIM to the backend — useful
          for telling &quot;APIM isn&apos;t reachable&quot; apart from
          &quot;APIM is fine but Postgres isn&apos;t&quot; while you bring
          the private networking up.
        </p>
        {!status && <p>loading…</p>}
        {status && (
          <ul>
            <StatusRow label="APIM → backend /health" result={status.apim} />
            <StatusRow label="Backend → Postgres" result={status.db} />
            <StatusRow label="Backend → Redis" result={status.cache} />
          </ul>
        )}
      </section>
    </main>
  );
}
