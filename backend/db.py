"""Database configuration shared by the application and Alembic.

Supports two modes:
1. Microsoft Entra authentication (GitHub Actions via OIDC)
   - PGACCESS_TOKEN: short-lived Entra access token
   - PGHOST, PGPORT, PGDATABASE, PGUSER: connection details

2. Local password authentication
   - DATABASE_URL: traditional PostgreSQL connection string
   - DATABASE_URL_PATH: mount path for mounted secrets
"""
from __future__ import annotations

import os
from pathlib import Path

from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL


DATABASE_URL_PATH = os.environ.get(
    "DATABASE_URL_PATH",
    "/mnt/secrets-store/database-url",
)
DATABASE_URL_FALLBACK = os.environ.get("DATABASE_URL", "")


def get_database_url() -> str:
    """Build a PostgreSQL connection URL.

    Entra mode is selected when PGACCESS_TOKEN is present.
    Otherwise, falls back to DATABASE_URL for local/password authentication.
    """
    access_token = os.environ.get("PGACCESS_TOKEN")
    if access_token is not None:
        access_token = access_token.strip()
        if not access_token:
            raise RuntimeError(
                "PGACCESS_TOKEN is set but empty. "
                "Verify token acquisition and environment propagation."
            )
        return _build_entra_url(access_token)

    return _build_password_url()


def _build_entra_url(access_token: str) -> str:
    """Build a PostgreSQL URL using Microsoft Entra access token.

    The access token is treated as the PostgreSQL password and is passed
    as a temporary credential. SSL is enforced.
    """
    required_values = {
        "PGHOST": os.environ.get("PGHOST"),
        "PGDATABASE": os.environ.get("PGDATABASE"),
        "PGUSER": os.environ.get("PGUSER"),
    }

    missing = [name for name, value in required_values.items() if not value]

    if missing:
        raise RuntimeError(
            "Missing PostgreSQL Entra configuration: "
            + ", ".join(missing)
        )

    url = URL.create(
        drivername="postgresql+psycopg2",
        username=required_values["PGUSER"],
        password=access_token,
        host=required_values["PGHOST"],
        port=int(os.environ.get("PGPORT", "5432")),
        database=required_values["PGDATABASE"],
        query={"sslmode": "require"},
    )

    return url.render_as_string(hide_password=False)


def _build_password_url() -> str:
    """Build a PostgreSQL URL using password authentication.

    Reads from DATABASE_URL_PATH (mounted secret) or DATABASE_URL (env var).
    Ensures the driver is explicitly set to psycopg2.
    """
    try:
        database_url = Path(DATABASE_URL_PATH).read_text(
            encoding="utf-8"
        ).strip()
    except OSError:
        database_url = DATABASE_URL_FALLBACK.strip()

    if not database_url:
        raise RuntimeError(
            "No database configuration found. "
            f"Checked DATABASE_URL_PATH ({DATABASE_URL_PATH}) and DATABASE_URL. "
            "Set either DATABASE_URL or a non-empty PGACCESS_TOKEN with "
            "PGHOST, PGUSER, and PGDATABASE."
        )

    if database_url.startswith("postgres://"):
        return "postgresql+psycopg2://" + database_url[len("postgres://") :]

    if database_url.startswith("postgresql://"):
        return "postgresql+psycopg2://" + database_url[len("postgresql://") :]

    return database_url


def check_database_connectivity() -> None:
    """Verify the configured PostgreSQL endpoint is reachable."""
    engine = create_engine(get_database_url())
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    finally:
        engine.dispose()
