"""Alembic migration environment configuration.

Handles both Microsoft Entra and password-based PostgreSQL authentication.
The connection URL is built dynamically at runtime from environment variables.
"""
from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from db import get_database_url
from models import Base


config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Import all model modules here as they are added so autogenerate can see them.
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations in offline mode (SQL generation without DB connection)."""

    config.set_main_option(
        "sqlalchemy.url",
        get_database_url(),
    )

    context.configure(
        url=get_database_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations using a live PostgreSQL connection.

    The connection URL is constructed from environment variables at runtime.
    For Entra auth, the PGACCESS_TOKEN is used as the password.
    """
    configuration = config.get_section(config.config_ini_section, {})
    configuration["sqlalchemy.url"] = get_database_url()

    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
