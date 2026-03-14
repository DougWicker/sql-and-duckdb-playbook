"""
Generate TPC-H data at scale factor 1 and export to Parquet.

Usage
-----
    uv run python scripts/generate_data.py

What this script does
---------------------
1. Opens an in-memory DuckDB connection.
2. Installs and loads DuckDB's built-in ``tpch`` extension.
3. Calls ``dbgen(sf=1)`` to materialise ~1 GB of TPC-H data across 8 tables
   (~6 million ``lineitem`` rows) entirely inside DuckDB — no external
   download required.
4. Exports each table to ``data/parquet/<table>.parquet`` using DuckDB's
   native Parquet writer (columnar, compressed, fast to read back).
5. Also exports ``orders`` partitioned by year into
   ``data/parquet/orders_partitioned/year=YYYY/`` — the Hive-compatible
   layout used by the Phase 5 predicate-pushdown demo.

Output
------
    data/parquet/
    ├── region.parquet
    ├── nation.parquet
    ├── supplier.parquet
    ├── part.parquet
    ├── partsupp.parquet
    ├── customer.parquet
    ├── orders.parquet
    ├── lineitem.parquet
    └── orders_partitioned/
        ├── year=1992/
        ├── year=1993/
        └── ...

Notes
-----
* The ``data/`` directory is gitignored — re-run this script to regenerate.
* Typical runtime: ~30–60 seconds on a modern laptop.
* DuckDB writes Parquet with Snappy compression by default, which gives a
  good balance of file size and read speed.
"""

import pathlib

import duckdb

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT = pathlib.Path(__file__).resolve().parent.parent
PARQUET_DIR = ROOT / "data" / "parquet"
PARTITIONED_DIR = PARQUET_DIR / "orders_partitioned"

# Eight standard TPC-H tables, declared here for documentation purposes.
# DuckDB's ``dbgen`` creates them all as virtual tables in the connection.
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


def generate() -> None:
    """Install the tpch extension, generate TPC-H data, and write Parquet files.

    The function is idempotent — running it again overwrites the existing
    Parquet files with a freshly generated dataset.
    """
    PARQUET_DIR.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect()

    # ── Install extension ─────────────────────────────────────────────────────
    # INSTALL only downloads if not already cached locally (~once per machine).
    # LOAD activates it for this connection.
    print("Installing and loading the tpch extension...")
    con.execute("INSTALL tpch; LOAD tpch;")

    # ── Generate data ─────────────────────────────────────────────────────────
    # sf=1 → scale factor 1 (~1 GB, the standard OLAP benchmark size).
    # All 8 TPC-H tables are created as in-memory virtual tables.
    print("Generating TPC-H data at sf=1 (allow ~30–60 s)...")
    con.execute("CALL dbgen(sf=1);")

    # ── Export flat Parquet files ─────────────────────────────────────────────
    print("\nExporting tables to Parquet:")
    for table in TPCH_TABLES:
        out = PARQUET_DIR / f"{table}.parquet"
        con.execute(f"COPY {table} TO '{out}' (FORMAT PARQUET);")
        row_count = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {table:12s}  {row_count:>10,} rows  →  {out.relative_to(ROOT)}")

    # ── Export year-partitioned orders (Hive layout) ──────────────────────────
    # Partitioning by year lets DuckDB skip entire directories when a query
    # filters on year — demonstrated in notebook 06.
    PARTITIONED_DIR.mkdir(parents=True, exist_ok=True)
    con.execute(f"""
        COPY (
            SELECT *, YEAR(o_orderdate) AS year
            FROM orders
        )
        TO '{PARTITIONED_DIR}'
        (FORMAT PARQUET, PARTITION_BY (year), OVERWRITE_OR_IGNORE);
    """)
    year_dirs = sorted(PARTITIONED_DIR.iterdir())
    print(
        f"\n  orders (partitioned) → "
        f"{PARTITIONED_DIR.relative_to(ROOT)}/"
        f"  ({len(year_dirs)} year partitions)"
    )

    print("\nDone. All Parquet files written to data/parquet/")
    con.close()


if __name__ == "__main__":
    generate()
