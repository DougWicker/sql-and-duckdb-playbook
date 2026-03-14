"""
Seed PostgreSQL with TPC-H data from Parquet files.

Usage
-----
    uv run python scripts/seed_postgres.py

Prerequisites
-------------
1. ``docker compose up -d``
   PostgreSQL container must be running and healthy (check with
   ``docker compose ps``).

2. ``uv run python scripts/generate_data.py``
   Parquet files must exist in ``data/parquet/``.

3. A ``.env`` file must exist in the project root (copy from ``.env.example``).

Strategy
--------
For each table, DuckDB reads the corresponding Parquet file and returns the
rows as Python tuples.  These are written to a ``StringIO`` buffer as
tab-separated values and then streamed into PostgreSQL via psycopg2's
``copy_from`` — the fastest single-connection bulk-load path available through
psycopg2, equivalent to running ``COPY … FROM STDIN`` at the psql prompt.

DuckDB handles all type conversions:
* ``DATE`` values become Python ``datetime.date`` objects whose ``str()``
  produces ISO-8601 strings (``YYYY-MM-DD``) accepted directly by PostgreSQL.
* ``DECIMAL`` values become Python ``decimal.Decimal`` objects whose ``str()``
  produces exact decimal strings.

Load order
----------
Tables are loaded in FK-safe order so foreign key constraints are never
violated during the load:

    region → nation → supplier
                    → part → partsupp
           → customer → orders → lineitem
"""

import io
import pathlib
import sys
from typing import TYPE_CHECKING

import duckdb
import psycopg2

if TYPE_CHECKING:
    import psycopg2.extensions

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT = pathlib.Path(__file__).resolve().parent.parent
PARQUET_DIR = ROOT / "data" / "parquet"
SCHEMA_FILE = ROOT / "sql" / "schema" / "tpch_tables.sql"

# Allow ``from config import settings`` regardless of the current working dir.
sys.path.insert(0, str(ROOT))
from config import settings  # noqa: E402  (must follow sys.path insert)

# FK-safe insertion order (parent tables before child tables).
TPCH_TABLES = [
    "region",
    "nation",
    "supplier",
    "part",
    "partsupp",
    "customer",
    "orders",
    "lineitem",
]


def _build_csv_buffer(
    duck: duckdb.DuckDBPyConnection,
    parquet_file: pathlib.Path,
) -> tuple[io.StringIO, int]:
    """Read *parquet_file* via DuckDB and return a tab-separated CSV buffer.

    DuckDB handles type-coercion (dates → ISO-8601, decimals → exact strings)
    so the resulting text is accepted directly by PostgreSQL's TEXT-format COPY.

    Parameters
    ----------
    duck:
        An active DuckDB connection — kept open across multiple calls to avoid
        repeated initialisation overhead.
    parquet_file:
        Absolute path to the ``.parquet`` file to read.

    Returns
    -------
    tuple[io.StringIO, int]
        A seeked-to-zero StringIO buffer ready for ``copy_from``, and the
        total row count (for logging).
    """
    rows = duck.execute(f"SELECT * FROM read_parquet('{parquet_file}')").fetchall()

    buf = io.StringIO()
    for row in rows:
        # None → empty string (PostgreSQL TEXT-format COPY treats empty as NULL
        # when combined with the ``null=''`` argument to copy_from).
        buf.write("\t".join("" if v is None else str(v) for v in row) + "\n")
    buf.seek(0)
    return buf, len(rows)


def create_schema(pg: "psycopg2.extensions.connection") -> None:
    """Execute the TPC-H DDL against PostgreSQL.

    Reads ``sql/schema/tpch_tables.sql`` and runs it in a single statement.
    The DDL starts with ``DROP TABLE … CASCADE`` statements, making this
    function safe to call repeatedly — each run produces a clean schema.

    Parameters
    ----------
    pg:
        An active psycopg2 connection with autocommit disabled.
    """
    ddl = SCHEMA_FILE.read_text(encoding="utf-8")
    with pg.cursor() as cur:
        cur.execute(ddl)
    pg.commit()
    print("Schema created (all tables dropped and re-created).")


def seed_table(
    pg: "psycopg2.extensions.connection",
    duck: duckdb.DuckDBPyConnection,
    table: str,
) -> None:
    """Bulk-load one TPC-H table from its Parquet file into PostgreSQL.

    Parameters
    ----------
    pg:
        An active psycopg2 connection.
    duck:
        An active DuckDB connection used to read the Parquet file.
    table:
        Table name — must match a file in ``data/parquet/`` and a table
        created by the DDL in ``sql/schema/tpch_tables.sql``.

    Raises
    ------
    FileNotFoundError
        If the expected Parquet file does not exist (i.e. ``generate_data.py``
        has not been run yet).
    """
    parquet_file = PARQUET_DIR / f"{table}.parquet"
    if not parquet_file.exists():
        raise FileNotFoundError(
            f"Missing: {parquet_file}\n"
            "Run ``uv run python scripts/generate_data.py`` first."
        )

    buf, row_count = _build_csv_buffer(duck, parquet_file)

    with pg.cursor() as cur:
        # copy_from uses COPY … FROM STDIN (TEXT format) — the fastest path.
        # sep="\t" matches the tab-separated buffer; null="" maps empty strings
        # back to SQL NULL.
        cur.copy_from(buf, table, sep="\t", null="")
    pg.commit()
    print(f"  {table:12s}  {row_count:>10,} rows loaded")


def main() -> None:
    """Orchestrate schema creation and full TPC-H data load."""
    pg = psycopg2.connect(settings.dsn)
    duck = duckdb.connect()

    try:
        create_schema(pg)
        print("\nLoading tables (this may take 1–3 minutes for sf=1):")
        for table in TPCH_TABLES:
            seed_table(pg, duck, table)
        print("\nAll tables loaded successfully.")
    finally:
        pg.close()
        duck.close()


if __name__ == "__main__":
    main()
