"""Database configuration shared by the application and Alembic."""
from __future__ import annotations

import os
from pathlib import Path


DATABASE_URL_PATH = os.environ.get("DATABASE_URL_PATH", "/mnt/secrets-store/database-url")
DATABASE_URL_FALLBACK = os.environ.get("DATABASE_URL", "")


def get_database_url() -> str:
    """Return the PostgreSQL URL from the mounted secret or environment."""
    try:
        url = Path(DATABASE_URL_PATH).read_text(encoding="utf-8").strip()
    except OSError:
        url = DATABASE_URL_FALLBACK.strip()

    if not url:
        raise RuntimeError(
            "No database URL configured. Set DATABASE_URL or mount "
            f"{DATABASE_URL_PATH}."
        )

    # SQLAlchemy 2 expects an explicit driver for psycopg2.
    if url.startswith("postgres://"):
        return "postgresql+psycopg2://" + url[len("postgres://") :]
    if url.startswith("postgresql://"):
        return "postgresql+psycopg2://" + url[len("postgresql://") :]
    return url
