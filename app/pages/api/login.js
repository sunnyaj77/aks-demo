// BFF route — Option 1 from the plan's "Who actually calls APIM" decision.
// The browser posts here (same-origin, no CORS needed). This server-side
// code is the only thing that ever calls out to APIM directly — the
// APIM subscription key lives only here, never shipped to browser JS.
import { serialize } from '../../lib/cookie';

const APIM_GATEWAY_URL = process.env.APIM_GATEWAY_URL; // e.g. https://api.aks-demo.internal
const APIM_SUBSCRIPTION_KEY_PATH = process.env.APIM_SUBSCRIPTION_KEY_PATH || '/mnt/secrets-store/apim-subscription-key';

function readSubscriptionKey() {
  // Falls back to a plain env var so `next dev` works locally without the
  // Secrets Store CSI driver mounted — same pattern as the backend's
  // _read_secret() helper.
  try {
    // eslint-disable-next-line global-require
    const fs = require('fs');
    return fs.readFileSync(APIM_SUBSCRIPTION_KEY_PATH, 'utf8').trim();
  } catch {
    return process.env.APIM_SUBSCRIPTION_KEY || '';
  }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'method not allowed' });
  }
  if (!APIM_GATEWAY_URL) {
    return res.status(500).json({ error: 'APIM_GATEWAY_URL is not configured on this pod' });
  }

  const { username, password } = req.body || {};
  if (!username || !password) {
    return res.status(400).json({ error: 'username and password are required' });
  }

  let apimResponse;
  try {
    apimResponse = await fetch(`${APIM_GATEWAY_URL}/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Ocp-Apim-Subscription-Key': readSubscriptionKey(),
      },
      body: JSON.stringify({ username, password }),
    });
  } catch (err) {
    // Almost always means the private path to APIM isn't wired up yet —
    // surfacing the raw error here is deliberate, it's the fastest way to
    // tell "DNS didn't resolve" from "connection refused" from "timeout"
    // while you're bringing this up for the first time.
    return res.status(502).json({ error: 'could not reach APIM', detail: String(err) });
  }

  if (!apimResponse.ok) {
    const body = await apimResponse.json().catch(() => ({}));
    return res.status(apimResponse.status).json({ error: body.detail || 'login failed' });
  }

  const { token, expiresInSeconds } = await apimResponse.json();

  // httpOnly cookie — never readable by browser JS, which is the whole
  // point of doing this server-side instead of handing the browser a
  // token directly (see the plan's Option 1 vs Option 2 writeup).
  res.setHeader(
    'Set-Cookie',
    serialize('session_token', token, {
      httpOnly: true,
      sameSite: 'lax',
      path: '/',
      maxAge: expiresInSeconds,
    })
  );
  return res.status(200).json({ ok: true });
}
