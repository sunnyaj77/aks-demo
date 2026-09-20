// BFF route that fans out through APIM to the backend's three connectivity
// probes and returns them as one payload — powers the status panel on
// /dashboard. Useful on its own too: hitting this one URL after a fresh
// `terraform apply` tells you in one shot whether APIM, Postgres, and
// Redis are all actually reachable privately, without opening a shell.
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

async function probe(path) {
  if (!APIM_GATEWAY_URL) return { ok: false, reason: 'APIM_GATEWAY_URL not configured' };
  try {
    const r = await fetch(`${APIM_GATEWAY_URL}${path}`, {
      headers: { 'Ocp-Apim-Subscription-Key': readSubscriptionKey() },
    });
    const body = await r.json().catch(() => ({}));
    return { ok: r.ok, ...body };
  } catch (err) {
    return { ok: false, reason: String(err) };
  }
}

export default async function handler(req, res) {
  const [apim, db, cache] = await Promise.all([
    probe('/health'),
    probe('/api/db-check'),
    probe('/api/cache-check'),
  ]);
  res.status(200).json({ apim, db, cache });
}
