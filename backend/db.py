"""Database configuration shared by the application and Alembic.

Supports two modes:
1. Microsoft Entra authentication (GitHub Actions via OIDC / AKS workload identity)
   - PGACCESS_TOKEN: short-lived Entra access token
   - or Azure workload identity / managed identity to fetch a token automatically
   - PGHOST, PGPORT, PGDATABASE, PGUSER: connection details
     (or DATABASE_URL, which is parsed for the same details)

2. Local password authentication
   - DATABASE_URL: traditional PostgreSQL connection string
   - DATABASE_URL_PATH: mount path for mounted secrets
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL, make_url


DATABASE_URL_PATH = os.environ.get(
    "DATABASE_URL_PATH",
    "/mnt/secrets-store/database-url",
)
DATABASE_URL_FALLBACK = os.environ.get("DATABASE_URL", "")
AZURE_POSTGRES_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"
_ENTRA_CREDENTIALS = None


def get_database_url() -> str:
    """Build a PostgreSQL connection URL."""
    access_token = os.environ.get("PGACCESS_TOKEN")

    if access_token:
        return _build_entra_url(access_token, _resolve_entra_config(required=True))

    if os.environ.get("PG_AUTH_MODE", "").strip().lower() == "entra":
        return _build_entra_url(
            _get_entra_access_token(),
            _resolve_entra_config(required=True),
        )

    return _build_password_url()


def _resolve_entra_config(required: bool = False) -> dict[str, str | int] | None:
    """Resolve PostgreSQL connection details for Entra authentication."""
    env_config = {
        "host": os.environ.get("PGHOST"),
        "database": os.environ.get("PGDATABASE"),
        "username": os.environ.get("PGUSER"),
        "port": int(os.environ.get("PGPORT", "5432")),
    }

    if all(env_config[key] for key in ("host", "database", "username")):
        return env_config

    database_url = _read_password_database_url()
    if database_url:
        parsed_url = make_url(_normalize_database_url(database_url))
        if parsed_url.host and parsed_url.database and parsed_url.username:
            return {
                "host": parsed_url.host,
                "database": parsed_url.database,
                "username": parsed_url.username,
                "port": parsed_url.port or 5432,
            }

    if required:
        raise RuntimeError(
            "Missing PostgreSQL Entra configuration: "
            "set PGHOST, PGUSER, and PGDATABASE or provide DATABASE_URL."
        )

    return None


def _get_entra_access_token() -> str:
    """Fetch a PostgreSQL access token using the pod's Azure identity."""
    from azure.core.exceptions import ClientAuthenticationError
    from azure.identity import CredentialUnavailableError

    errors = []
    saw_authentication_failure = False
    for credential in _get_entra_credentials():
        try:
            return credential.get_token(AZURE_POSTGRES_SCOPE).token
        except CredentialUnavailableError as exc:
            errors.append(exc.message)
        except ClientAuthenticationError as exc:
            saw_authentication_failure = True
            errors.append(str(exc))
            continue

    message = (
        "; ".join(errors)
        or "No Azure workload identity or managed identity credential is available."
    )
    if saw_authentication_failure:
        raise ClientAuthenticationError(message=message)

    raise CredentialUnavailableError(message=message)


def _get_entra_credentials() -> tuple[Any, ...]:
    """Create the Azure credentials lazily so they can be reused."""
    global _ENTRA_CREDENTIALS

    if _ENTRA_CREDENTIALS is None:
        from azure.identity import ManagedIdentityCredential, WorkloadIdentityCredential

        credentials = []
        if all(
            os.environ.get(name)
            for name in (
                "AZURE_FEDERATED_TOKEN_FILE",
                "AZURE_CLIENT_ID",
                "AZURE_TENANT_ID",
            )
        ):
            credentials.append(WorkloadIdentityCredential())

        credentials.append(
            ManagedIdentityCredential(client_id=os.environ.get("AZURE_CLIENT_ID"))
        )
        _ENTRA_CREDENTIALS = tuple(credentials)

    return _ENTRA_CREDENTIALS


def _build_entra_url(
    access_token: str,
    entra_config: dict[str, str | int],
) -> str:
    """Build a PostgreSQL URL using Microsoft Entra access token."""
    url = URL.create(
        drivername="postgresql+psycopg2",
        username=str(entra_config["username"]),
        password=access_token,
        host=str(entra_config["host"]),
        port=int(entra_config["port"]),
        database=str(entra_config["database"]),
        query={"sslmode": "require"},
    )

    return url.render_as_string(hide_password=False)


def _read_password_database_url() -> str:
    """Read the password-based DATABASE_URL from the mounted secret or env."""
    try:
        database_url = Path(DATABASE_URL_PATH).read_text(
            encoding="utf-8"
        ).strip()
    except OSError:
        database_url = DATABASE_URL_FALLBACK.strip()

    return database_url


def _normalize_database_url(database_url: str) -> str:
    """Ensure the PostgreSQL URL uses the psycopg2 driver."""
    if database_url.startswith("postgres://"):
        return "postgresql+psycopg2://" + database_url[len("postgres://") :]

    if database_url.startswith("postgresql://"):
        return "postgresql+psycopg2://" + database_url[len("postgresql://") :]

    return database_url


def _build_password_url() -> str:
    """Build a PostgreSQL URL using password authentication."""
    database_url = _read_password_database_url()

    if not database_url:
        raise RuntimeError(
            "No database configuration found. "
            "Set either DATABASE_URL or PGACCESS_TOKEN with PGHOST, PGUSER, "
            "and PGDATABASE."
        )

    return _normalize_database_url(database_url)


def check_database_connectivity() -> None:
    """Verify the configured PostgreSQL endpoint is reachable."""
    engine = create_engine(get_database_url())
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    finally:
        engine.dispose()
