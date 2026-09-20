// Tiny hand-rolled cookie helpers — deliberately not pulling in a new npm
// dependency for two functions. Good enough for this demo's one cookie;
// reach for a real package if this grows past that.

export function serialize(name, value, opts = {}) {
  let str = `${name}=${encodeURIComponent(value)}`;
  if (opts.maxAge != null) str += `; Max-Age=${Math.floor(opts.maxAge)}`;
  if (opts.path) str += `; Path=${opts.path}`;
  if (opts.httpOnly) str += '; HttpOnly';
  if (opts.sameSite) str += `; SameSite=${opts.sameSite}`;
  if (opts.secure) str += '; Secure';
  return str;
}

export function parse(cookieHeader = '') {
  const out = {};
  cookieHeader.split(';').forEach((pair) => {
    const idx = pair.indexOf('=');
    if (idx === -1) return;
    const key = pair.slice(0, idx).trim();
    const value = pair.slice(idx + 1).trim();
    if (key) out[key] = decodeURIComponent(value);
  });
  return out;
}
