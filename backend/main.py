"""
aks-demo backend — FastAPI

Sample routes that exist purely to validate the private architecture end to
end, once it's built: does a request actually make it frontend -> APIM ->
here, can this pod reach Postgres and Redis privately, does a session
round-trip work. Nothing here is production-grade auth — see the big
comment on /login below before reusing this pattern anywhere real.

Routes:
  GET  /health          - liveness/readiness probe target, no dependencies
  POST /login            - demo-grade auth, issues a session token in Redis
  GET  /api/me            - resolves a session token back to a username
  GET  /api/db-check       - proves private Postgres connectivity (SELECT 1)
  GET  /api/cache-check     - proves private Redis connectivity (SET/GET)

This service is never reached directly by a browser. It sits behind its own
internal Load Balancer, which only APIM is meant to call — see the "APIM"
section of the architecture plan for why.
"""
import os
import secrets
import time

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

app = FastAPI(title="aks-demo-backend")

# ---------------------------------------------------------------------------
# Config — every one of these is meant to arrive via the Secrets Store CSI
# driver / Key Vault in the real deployment (see charts/backend-api/values.yaml).
# Falling back to permissive local defaults so `uvicorn main:app` also works
# on a laptop with nothing wired up yet.
# ---------------------------------------------------------------------------
DEMO_USERNAME = os.environ.get("DEMO_USERNAME", "demo")
DEMO_PASSWORD_PATH = os.environ.get("DEMO_PASSWORD_PATH", "/mnt/secrets-store/demo-password")
DEMO_PASSWORD_FALLBACK = os.environ.get("DEMO_PASSWORD", "demo-password-change-me")

DATABASE_URL_PATH = os.environ.get("DATABASE_URL_PATH", "/mnt/secrets-store/database-url")
DATABASE_URL_FALLBACK = os.environ.get("DATABASE_URL", "")

REDIS_URL_PATH = os.environ.get("REDIS_URL_PATH", "/mnt/secrets-store/redis-url")
REDIS_URL_FALLBACK = os.environ.get("REDIS_URL", "")

SESSION_TTL_SECONDS = 3600


def _read_secret(path: str, fallback: str) -> str:
    """Prefer the CSI-mounted file (real deployment); fall back to a plain
    env var (local dev) so this code runs identically in both places."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return fallback


def _redis_client():
    import redis  # imported lazily so /health never needs this dependency to be healthy

    url = _read_secret(REDIS_URL_PATH, REDIS_URL_FALLBACK)
    if not url:
        raise RuntimeError("no Redis connection info configured")
    return redis.from_url(url, socket_connect_timeout=3, socket_timeout=3)


def _pg_connection():
    import psycopg2  # imported lazily, same reasoning as above

    dsn = _read_secret(DATABASE_URL_PATH, DATABASE_URL_FALLBACK)
    if not dsn:
        raise RuntimeError("no Postgres connection info configured")
    return psycopg2.connect(dsn, connect_timeout=3)


# ---------------------------------------------------------------------------
# /health — kept dependency-free on purpose, same reasoning as the
# frontend's /api/health: a slow Postgres/Redis must never look like a
# crashed pod to the kubelet.
# ---------------------------------------------------------------------------
@app.get("/health")
def health():
    return {"status": "ok", "pod": os.environ.get("HOSTNAME", "unknown")}


# ---------------------------------------------------------------------------
# /login
#
# DEMO-GRADE AUTH — deliberately simplified so this repo can validate the
# plumbing (frontend -> APIM -> backend -> Redis) without also building a
# real identity system. Do not copy this password-comparison pattern into
# anything that isn't a learning demo:
#   - single hardcoded demo user, no hashing, no lockout/rate-limit logic
#     of its own (APIM is the layer meant to rate-limit login attempts —
#     see the plan's APIM section)
#   - session token is a random opaque string, not a signed JWT
# ---------------------------------------------------------------------------
class LoginRequest(BaseModel):
    username: str
    password: str


@app.post("/login")
def login(body: LoginRequest):
    expected_password = _read_secret(DEMO_PASSWORD_PATH, DEMO_PASSWORD_FALLBACK)
    if body.username != DEMO_USERNAME or body.password != expected_password:
        raise HTTPException(status_code=401, detail="invalid username or password")

    token = secrets.token_urlsafe(32)
    try:
        r = _redis_client()
        r.setex(f"session:{token}", SESSION_TTL_SECONDS, body.username)
    except Exception as exc:  # noqa: BLE001 - surfaced to the caller on purpose
        raise HTTPException(status_code=503, detail=f"session store unavailable: {exc}") from exc

    return {"token": token, "expiresInSeconds": SESSION_TTL_SECONDS}


# ---------------------------------------------------------------------------
# /api/me — resolves a session token back to a username. The frontend's
# /api/me BFF route calls this with the token it got from the login cookie;
# this is the round-trip that proves the whole chain actually works.
# ---------------------------------------------------------------------------
@app.get("/api/me")
def me(request: Request):
    token = request.headers.get("x-session-token")
    if not token:
        raise HTTPException(status_code=401, detail="missing x-session-token header")
    try:
        r = _redis_client()
        username = r.get(f"session:{token}")
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=503, detail=f"session store unavailable: {exc}") from exc

    if username is None:
        raise HTTPException(status_code=401, detail="session expired or invalid")
    return {"username": username.decode("utf-8")}


# ---------------------------------------------------------------------------
# /api/db-check, /api/cache-check — isolated connectivity probes, separate
# from /login and /api/me on purpose: if the private network path to
# Postgres or Redis is misconfigured, you want that to fail here with a
# clear reason, not show up as a confusing 503 on the login form.
# ---------------------------------------------------------------------------
@app.get("/api/db-check")
def db_check():
    start = time.monotonic()
    try:
        conn = _pg_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        conn.close()
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "reason": str(exc)}
    return {"ok": True, "latencyMs": round((time.monotonic() - start) * 1000, 1)}


@app.get("/api/cache-check")
def cache_check():
    start = time.monotonic()
    try:
        r = _redis_client()
        probe_key = "aks-demo:cache-check"
        r.set(probe_key, "ok", ex=30)
        value = r.get(probe_key)
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "reason": str(exc)}
    return {"ok": value == b"ok", "latencyMs": round((time.monotonic() - start) * 1000, 1)}
