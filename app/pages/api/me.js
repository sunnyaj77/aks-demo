// BFF route — reads the httpOnly cookie set by /api/login, forwards it to
// the backend (via APIM) as a header, and reports whether the session is
// still valid. This is the round trip that proves the whole chain works:
// browser -> frontend -> APIM -> backend -> Redis -> back again.
import { parse } from '../../lib/cookie';

const APIM_GATEWAY_URL = process.env.APIM_GATEWAY_URL;
const APIM_SUBSCRIPTION_KEY_PATH = process.env.APIM_SUBSCRIPTION_KEY_PATH || '/mnt/secrets-store/apim-subscription-key';

function readSubscriptionKey() {
  try {
    // eslint-disable-next-line global-require
    const fs = require('fs');
    return fs.readFileSync(APIM_SUBSCRIPTION_KEY_PATH, 'utf8').trim();
  } catch {
    return process.env.APIM_SUBSCRIPTION_KEY || '';
  }
}

export default async function handler(req, res) {
  const cookies = parse(req.headers.cookie || '');
  const token = cookies.session_token;
  if (!token) {
    return res.status(401).json({ error: 'no session cookie' });
  }
  if (!APIM_GATEWAY_URL) {
    return res.status(500).json({ error: 'APIM_GATEWAY_URL is not configured on this pod' });
  }

  let apimResponse;
  try {
    apimResponse = await fetch(`${APIM_GATEWAY_URL}/api/me`, {
      headers: {
        'Ocp-Apim-Subscription-Key': readSubscriptionKey(),
        'x-session-token': token,
      },
    });
  } catch (err) {
    return res.status(502).json({ error: 'could not reach APIM', detail: String(err) });
  }

  if (!apimResponse.ok) {
    const body = await apimResponse.json().catch(() => ({}));
    return res.status(apimResponse.status).json({ error: body.detail || 'session invalid' });
  }

  const { username } = await apimResponse.json();
  return res.status(200).json({ username });
}
