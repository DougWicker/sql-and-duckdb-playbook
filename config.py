"""
Runtime configuration for sql-and-duckdb-playbook.

Uses ``pydantic-settings`` to read ``POSTGRES_*`` environment variables from a
``.env`` file (or the process environment).  The ``Settings`` singleton is
constructed at import time so a missing or malformed variable raises a
``ValidationError`` immediately — before any database call is attempted.

Usage (in scripts and notebooks)::

    from config import settings

    import psycopg2
    pg = psycopg2.connect(settings.dsn)

    import duckdb
    duck = duckdb.connect()
    duck.execute(f"ATTACH '{settings.dsn}' AS pg (TYPE POSTGRES)")
"""

from pydantic import computed_field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Validated settings loaded from ``.env`` / environment variables.

    All five ``POSTGRES_*`` fields are **required** (no defaults except
    ``POSTGRES_PORT``).  pydantic-settings will raise a ``ValidationError``
    listing every missing field if the ``.env`` file is absent or incomplete.
    Copy ``.env.example`` to ``.env`` and fill in the values before running
    any script.
    """

    model_config = SettingsConfigDict(
        # Look for a .env file relative to the working directory.
        # scripts/ and notebooks/ both set cwd to the project root via uv,
        # so this resolves correctly regardless of where the script lives.
        env_file=".env",
        env_file_encoding="utf-8",
    )

    POSTGRES_HOST: str
    POSTGRES_PORT: int = 5432
    POSTGRES_DB: str
    POSTGRES_USER: str
    POSTGRES_PASSWORD: str

    @computed_field  # type: ignore[prop-decorator]
    @property
    def dsn(self) -> str:
        """Build a libpq-style DSN from individual fields.

        The returned string is accepted directly by:

        * ``psycopg2.connect(settings.dsn)``
        * DuckDB's ``ATTACH '...' AS pg (TYPE POSTGRES)`` extension
        * Any other libpq-compatible driver (asyncpg, SQLAlchemy, etc.)

        Returns
        -------
        str
            A space-separated keyword=value connection string, e.g.
            ``"host=localhost port=5432 dbname=tpch user=postgres password=…"``
        """
        return (
            f"host={self.POSTGRES_HOST} "
            f"port={self.POSTGRES_PORT} "
            f"dbname={self.POSTGRES_DB} "
            f"user={self.POSTGRES_USER} "
            f"password={self.POSTGRES_PASSWORD}"
        )


# Module-level singleton — imported everywhere as ``from config import settings``.
# Fails fast at startup if any required variable is absent.
settings = Settings()
