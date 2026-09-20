import { useState } from 'react';
import { useRouter } from 'next/router';

// Demo login form — posts to this app's own /api/login (same-origin, no
// CORS). See backend/main.py for the demo credentials (default
// demo / demo-password-change-me unless overridden via Key Vault).
export default function Login() {
  const router = useRouter();
  const [username, setUsername] = useState('demo');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  async function onSubmit(e) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch('/api/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      });
      const body = await res.json();
      if (!res.ok) {
        setError(body.error || 'login failed');
        return;
      }
      router.push('/dashboard');
    } catch (err) {
      setError(String(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main style={{ fontFamily: 'sans-serif', padding: '3rem', maxWidth: 420 }}>
      <h1>Sign in</h1>
      <p style={{ color: '#666', fontSize: 14 }}>
        Demo credentials only — see <code>backend/main.py</code>. This form
        posts to this app&apos;s own <code>/api/login</code>, which is the
        only thing that ever talks to APIM directly.
      </p>
      <form onSubmit={onSubmit} style={{ display: 'grid', gap: 12, marginTop: 24 }}>
        <label>
          Username
          <input value={username} onChange={(e) => setUsername(e.target.value)} style={{ display: 'block', width: '100%', padding: 8 }} />
        </label>
        <label>
          Password
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} style={{ display: 'block', width: '100%', padding: 8 }} />
        </label>
        {error && <p style={{ color: '#b6473b' }}>{error}</p>}
        <button type="submit" disabled={submitting} style={{ padding: '10px 16px' }}>
          {submitting ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </main>
  );
}
