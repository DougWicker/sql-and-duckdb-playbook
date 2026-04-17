-- =============================================================================
-- EXPLAIN Plans 01 — Sequential Scan vs Index Scan
-- =============================================================================
-- Demonstrates how creating an index changes the scan strategy PostgreSQL
-- chooses, and how to read the EXPLAIN ANALYZE output to confirm it.
--
-- Run against: PostgreSQL 16
-- Tables used: orders, lineitem
-- =============================================================================

-- § explain_seq_scan_orders
-- ─────────────────────────────────────────────────────────────────────────────
-- Baseline: filter orders by date — no index exists yet.
-- Expect: Seq Scan with a Filter node.  All 1.5 M rows are read; those that
-- fail the predicate are discarded.  "Rows Removed by Filter" shows the waste.
-- ─────────────────────────────────────────────────────────────────────────────
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o_orderkey, o_totalprice
FROM   orders
WHERE  o_orderdate = DATE '1995-01-15';

-- § create_index_orders
-- ─────────────────────────────────────────────────────────────────────────────
-- Create a B-tree index on orders.o_orderdate.
-- B-tree is the default and correct choice for equality and range predicates
-- on a single column with many distinct values.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_orderdate
    ON orders (o_orderdate);

-- § explain_index_scan_orders
-- ─────────────────────────────────────────────────────────────────────────────
-- After index creation: same query, new plan.
-- Expect: Index Scan (or Bitmap Index Scan + Bitmap Heap Scan for multi-page
-- results).  Startup cost rises slightly (index lookup overhead) but total
-- cost and actual time drop significantly.
-- ─────────────────────────────────────────────────────────────────────────────
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o_orderkey, o_totalprice
FROM   orders
WHERE  o_orderdate = DATE '1995-01-15';

-- § explain_seq_scan_lineitem
-- ─────────────────────────────────────────────────────────────────────────────
-- Baseline: filter lineitem by shipdate — 6 M rows, no index.
-- The larger table makes the Seq Scan cost more visible.
-- ─────────────────────────────────────────────────────────────────────────────
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT l_orderkey, l_extendedprice
FROM   lineitem
WHERE  l_shipdate = DATE '1998-09-01';

-- § create_index_lineitem
CREATE INDEX IF NOT EXISTS idx_lineitem_shipdate
    ON lineitem (l_shipdate);

-- § explain_index_scan_lineitem
-- ─────────────────────────────────────────────────────────────────────────────
-- After index on lineitem.l_shipdate.
-- At sf=1, a single date returns ~160 K rows (~2.6% of the table).
-- PostgreSQL may choose a Bitmap scan rather than a plain Index Scan when
-- the result set is large: Bitmap Index Scan builds a row-location bitmap,
-- then Bitmap Heap Scan fetches only the relevant heap pages in disk order
-- (avoiding random I/O).
-- ─────────────────────────────────────────────────────────────────────────────
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT l_orderkey, l_extendedprice
FROM   lineitem
WHERE  l_shipdate = DATE '1998-09-01';

-- § analyze_tables
-- ─────────────────────────────────────────────────────────────────────────────
-- Refresh statistics after the bulk load and new indexes.
-- ANALYZE samples the table and rebuilds the planner's histograms.
-- A large gap between estimated rows and actual rows in EXPLAIN ANALYZE
-- is the primary signal that statistics are stale.
-- ─────────────────────────────────────────────────────────────────────────────
ANALYZE orders;
ANALYZE lineitem;
