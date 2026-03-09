# Plan: `sql-and-duckdb-playbook`

> DE Portfolio — Project 2 | Status: Approved, ready to build

---

## Overview

A SQL portfolio project demonstrating advanced PostgreSQL patterns and DuckDB as a benchmarked alternative OLAP engine.

**Dataset:** TPC-H at `sf=1` (~1 GB, ~6M `lineitem` rows) — the industry-standard OLAP benchmark, generated in-process via DuckDB's built-in `dbgen` extension, exported to Parquet, and loaded into PostgreSQL. Fully reproducible with no external data sources.

**Core architecture:** `.sql` files are the primary artifacts — well-commented, standalone, run-anywhere. Notebooks load them via `open().read()` and add narrative, executed outputs, and visualisations. No SQL is duplicated between the two.

---

## Repo Structure

```
sql-and-duckdb-playbook/
├── data/
│   └── parquet/                              # gitignored — generated locally
├── notebooks/
│   ├── 01_setup_and_data.ipynb
│   ├── 02_window_functions.ipynb
│   ├── 03_ctes_and_recursive.ipynb
│   ├── 04_explain_plans.ipynb
│   ├── 05_duckdb_vs_postgres.ipynb
│   ├── 06_duckdb_parquet.ipynb
│   └── 07_benchmarking.ipynb
├── sql/
│   ├── schema/
│   │   ├── tpch_tables.sql                   # DDL for all 8 TPC-H tables
│   │   └── seed_employees.sql                # synthetic dim_employee for recursive CTE demo
│   ├── window_functions/
│   │   ├── 01_ranking.sql
│   │   ├── 02_lag_lead.sql
│   │   └── 03_running_totals_and_moving_avg.sql
│   ├── ctes/
│   │   ├── 01_chained_ctes.sql
│   │   └── 02_recursive_cte.sql
│   └── explain/
│       ├── 01_seq_vs_index_scan.sql
│       └── 02_join_strategies.sql
├── scripts/
│   ├── generate_data.py                      # DuckDB dbgen(sf=1) → Parquet export
│   └── seed_postgres.py                      # Parquet → PostgreSQL via COPY
├── config.py                                 # pydantic-settings Settings class
├── docker-compose.yml                        # PostgreSQL 16
├── pyproject.toml                            # uv
├── .env.example
├── .python-version                           # 3.12
├── .gitignore
└── README.md
```

---

## Stack

| Tool | Role |
|---|---|
| PostgreSQL 16 (Docker) | Primary SQL engine — OLTP patterns, window functions, EXPLAIN plans |
| DuckDB | In-process OLAP engine — benchmarking, Parquet querying, postgres_scan |
| Python 3.12 | Scripts and notebooks |
| uv | Package management |
| Jupyter | Notebook execution and narrative |
| pandas + matplotlib | Benchmark results and visualisation |
| pydantic-settings | `.env` validation — same pattern as project 1 |

---

## Phases

### Phase 0 — Scaffolding & Data Pipeline

**Files:** `pyproject.toml`, `docker-compose.yml`, `.env.example`, `.gitignore`, `.python-version`, `config.py`, `scripts/generate_data.py`, `scripts/seed_postgres.py`, `sql/schema/`

**Dependencies (uv):** `duckdb`, `psycopg2-binary`, `pandas`, `jupyterlab`, `matplotlib`, `pydantic-settings`

**What gets built:**

- `config.py` — `pydantic-settings` `BaseSettings` with `POSTGRES_*` fields. Validates all connection vars at startup and raises a clear `ValidationError` if any are missing. Imported by both scripts and notebooks — one config pattern everywhere.
- `docker-compose.yml` — PostgreSQL 16, health-checked, persistent volume (mirrors project 1 pattern).
- `generate_data.py` — `INSTALL tpch; LOAD tpch; CALL dbgen(sf=1)` → exports all 8 TPC-H tables to `data/parquet/`. Also exports `orders` partitioned by year for the Hive partitioning demo in Phase 5.
- `seed_postgres.py` — DuckDB reads Parquet; psycopg2 `COPY` bulk-loads into PostgreSQL.
- `tpch_tables.sql` — Full DDL for all 8 TPC-H tables (PKs, FKs, correct types, comments).
- `seed_employees.sql` — ~10-row synthetic `dim_employee(id, name, manager_id)` table for the recursive CTE demo.
- **Notebook 01** — Schema diagram, `SUMMARIZE` output per table, row counts, sample data. Explains why TPC-H was chosen.

> **Signal:** A reproducible data pipeline as the foundation of a SQL project demonstrates engineering discipline, not just SQL knowledge.

---

### Phase 1 — Window Functions (PostgreSQL)

**Files:** `notebooks/02_window_functions.ipynb`, `sql/window_functions/`

**Core pattern:** Every query first shown as a naive subquery or self-join → rewritten with window functions → outputs compared side by side. This shows *why* window functions exist, not just how to use them.

| File | Function(s) | Business Question | What It Teaches |
|---|---|---|---|
| `01_ranking.sql` | `ROW_NUMBER`, `RANK`, `DENSE_RANK` | Rank customers by total spend per nation | Tie-handling differences |
| `01_ranking.sql` | `NTILE(4)` | Segment orders into revenue quartiles | Segmentation pattern |
| `02_lag_lead.sql` | `LAG`, `LEAD` | Month-over-month order value change per clerk | Time-series comparison |
| `03_running_totals.sql` | `SUM OVER (ROWS BETWEEN...)` | Cumulative revenue by date | Frame clause |
| `03_running_totals.sql` | `AVG OVER (ROWS BETWEEN 2 PRECEDING...)` | 3-month moving average | Sliding window |
| `03_running_totals.sql` | `FIRST_VALUE`, `LAST_VALUE` | Best-ever order alongside every order for a customer | Anchor value pattern |

---

### Phase 2 — CTEs & Recursive Queries (PostgreSQL)

**Files:** `notebooks/03_ctes_and_recursive.ipynb`, `sql/ctes/`

**`01_chained_ctes.sql`**
- A 5-join aggregation decomposed into named CTE steps — demonstrates readability gain
- `WITH a AS (...), b AS (...) SELECT ... FROM b JOIN a` pattern
- Brief note on `MATERIALIZED` vs default (PostgreSQL 12+ behaviour)

**`02_recursive_cte.sql`** — the showpiece of this phase
- Uses `dim_employee(id, name, manager_id)` — a universally recognised hierarchy (not TPC-H — that hierarchy is too shallow to be meaningful)
- Built progressively in the notebook:
  1. Basic anchor + recursion (immediate reports)
  2. Add `depth` column
  3. Add `path` string accumulation: `CEO / VP-Sales / Alice`
  4. Add cycle detection guard (`WHERE id <> ALL(path_array)`)
- Explicitly connects to real-world uses: org charts, category trees, bill-of-materials, network traversal

---

### Phase 3 — EXPLAIN Plans & Indexing (PostgreSQL)

**Files:** `notebooks/04_explain_plans.ipynb`, `sql/explain/`

> This is the most differentiating section in the repo — almost no portfolio projects demonstrate this.

**`01_seq_vs_index_scan.sql`**
- Run filter query cold → `EXPLAIN ANALYZE` → note `Seq Scan` + actual timing
- `CREATE INDEX` on `orders(orderdate)`, `lineitem(shipdate)`
- Re-run → `Index Scan` → compare cost estimates and wall-clock time
- Notebook has annotated output — callout boxes explaining `cost=X..Y`, `rows`, `actual time`, `buffers`

**`02_join_strategies.sql`**
- Small × large → Nested Loop
- Large × large → Hash Join
- Pre-sorted → Merge Join
- EXPLAIN outputs annotated — explains *when* PostgreSQL picks each strategy

**Additional notebook content:**
- What each EXPLAIN node means (`Seq Scan`, `Bitmap Index Scan`, `Hash`, `Sort`)
- What `cost=X..Y` means (startup cost vs total cost)
- Rows estimate vs actual rows — what large discrepancies signal
- The `ANALYZE` command — why stale statistics mislead the planner

---

### Phase 4 — DuckDB: Feature Parity + Unique Syntax

**Files:** `notebooks/05_duckdb_vs_postgres.ipynb`

1. What DuckDB is — columnar, OLAP-optimised, in-process, zero infrastructure
2. Re-run representative Phase 1 & 2 queries — near-identical SQL, different engine
3. DuckDB-exclusive syntax PostgreSQL can't do:
   - `SELECT * EXCLUDE (col)` — drop columns without listing all others
   - `PIVOT` / `UNPIVOT` — native, no `crosstab()` required
   - `FROM df` — query a pandas DataFrame directly
   - `SUMMARIZE` — instant table profiling shortcut
4. **`postgres_scan` extension:**
   - `INSTALL postgres; LOAD postgres; ATTACH '...' AS pg (TYPE POSTGRES)`
   - Query live PostgreSQL tables from DuckDB — no file export needed
   - Demonstrates the integration pattern used in modern data lake architectures

---

### Phase 5 — DuckDB + Parquet Querying

**Files:** `notebooks/06_duckdb_parquet.ipynb`

1. Direct file query: `FROM 'data/parquet/lineitem.parquet'`
2. Glob patterns: `FROM 'data/parquet/orders_*.parquet'`
3. Hive partitioning: `orders` partitioned by year → EXPLAIN shows file pruning when filtering by year
4. Predicate pushdown: EXPLAIN showing Parquet row group skipping
5. Schema inference from Parquet metadata — no `CREATE TABLE` needed
6. Write results back: `COPY (SELECT ...) TO 'output.parquet' (FORMAT PARQUET)`

---

### Phase 6 — Benchmarking: PostgreSQL vs DuckDB

**Files:** `notebooks/07_benchmarking.ipynb`

**Queries (anchored to official TPC-H queries — principled, not cherry-picked):**

| TPC-H Query | Description | Why Chosen |
|---|---|---|
| Q1 | Pricing summary report | Pure aggregation on 6M rows, no joins — maximises DuckDB's columnar advantage |
| Q3 | Shipping priority | 3-table join + aggregation — tests join performance |
| Q5 | Local supplier volume | 6-table join + GROUP BY nation — complex OLAP shape |

**Methodology:**
- 3 runs each, median taken via `time.perf_counter`
- PostgreSQL: via psycopg2 with indexes in place
- DuckDB: against Parquet files direct
- Results → pandas DataFrame → Matplotlib grouped bar chart, committed into notebook

**Written conclusion:**
- Row-level CRUD / OLTP / strict consistency → PostgreSQL
- Analytical aggregations / Parquet / local dev / fast iteration → DuckDB
- Lakehouse future: DuckDB queries files in object storage; PostgreSQL handles transactions — both have a role

---

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Dataset | TPC-H `sf=1` | Industry-standard benchmark, built into DuckDB, ~1 GB, reproduces in seconds |
| Python | 3.12 | Matches project 1 |
| Package manager | uv | Matches project 1 |
| `.env` handling | `pydantic-settings` | Matches project 1; fail-fast validation at startup; clear errors if vars missing |
| Notebooks | Committed with outputs | Portfolio visibility — renders on GitHub |
| DuckDB `postgres_scan` | Included | Demonstrates real integration pattern used in data lake architectures |
| dbt | Excluded | Out of scope for this project |

---

## Verification Checklist

- [ ] `uv run python scripts/generate_data.py` → `data/parquet/` populated with 8 table files
- [ ] `docker compose up -d` → `uv run python scripts/seed_postgres.py` → all rows load without error
- [ ] Each `.sql` file runs standalone against PostgreSQL (no notebook required)
- [ ] All 7 notebooks execute top-to-bottom with no errors; outputs committed
- [ ] Notebook 04 EXPLAIN outputs show `Seq Scan` before index, `Index Scan` after
- [ ] Benchmark chart in notebook 07 renders and is committed
