-- =============================================================================
-- EXPLAIN Plans 02 — Join Strategies
-- =============================================================================
-- Demonstrates the three join algorithms PostgreSQL uses and the conditions
-- that cause the planner to choose each one.
--
-- PostgreSQL chooses a join strategy based on:
--   * Estimated size of the two inputs
--   * Whether the inputs are already sorted on the join key
--   * Available memory (work_mem)
--   * Presence of indexes on the join columns
--
-- Run against: PostgreSQL 16
-- Tables used: nation, customer, orders, lineitem
-- Indexes from 01_seq_vs_index_scan.sql must exist for some plans to appear.
-- =============================================================================

-- § nested_loop_join
-- ─────────────────────────────────────────────────────────────────────────────
-- Nested Loop: one small input, one large input with an index
-- ─────────────────────────────────────────────────────────────────────────────
-- Nested Loop iterates every row of the outer table and probes the inner table
-- for matching rows.  Cost = outer_rows × inner_lookup_cost.
-- Efficient only when the outer table is small OR the inner has an index.
--
-- nation (25 rows) × customer (150 K rows, indexed on c_nationkey):
-- PostgreSQL scans nation, and for each of 25 rows does an index lookup on
-- customer.  25 × cheap_index_lookup << sequential scan of 150 K rows.
--
-- Expected plan node: Nested Loop → Seq Scan (nation) + Index Scan (customer)
EXPLAIN (ANALYZE, FORMAT TEXT)
SELECT n.n_name, c.c_name
FROM   nation   n
JOIN   customer c ON c.c_nationkey = n.n_nationkey
WHERE  n.n_name = 'GERMANY';

-- § hash_join
-- ─────────────────────────────────────────────────────────────────────────────
-- Hash Join: two large inputs, no useful index on the join key
-- ─────────────────────────────────────────────────────────────────────────────
-- Hash Join builds an in-memory hash table from the smaller input (the "build"
-- side), then probes it for each row of the larger input (the "probe" side).
-- Cost = O(N + M).  High startup cost (must build the hash table first) but
-- optimal for large unindexed inputs.
--
-- customer (150 K) × orders (1.5 M): both large, no index on o_custkey.
-- Expected plan node: Hash Join → Seq Scan (customer, build) +
--                                 Seq Scan (orders, probe)
EXPLAIN (ANALYZE, FORMAT TEXT)
SELECT c.c_name, COUNT(*) AS order_count
FROM   customer c
JOIN   orders   o ON o.o_custkey = c.c_custkey
GROUP  BY c.c_custkey, c.c_name
LIMIT  20;

-- § merge_join
-- ─────────────────────────────────────────────────────────────────────────────
-- Merge Join: both inputs explicitly sorted on the join key
-- ─────────────────────────────────────────────────────────────────────────────
-- Merge Join requires both sides to be sorted on the join key.  It then
-- advances two pointers simultaneously — O(N + M) comparisons, zero hashing.
-- PostgreSQL will add an explicit Sort node if the inputs are not already
-- sorted; if an index provides pre-sorted order, no Sort is needed.
--
-- Forcing a merge join to appear: join lineitem and orders on o_orderkey,
-- both sorted, with a SET enable_hashjoin = off hint so PostgreSQL must
-- choose merge or nested loop instead.  This is a demonstration technique —
-- never use enable_* hints in production.
--
-- Expected plan node: Merge Join → Sort (lineitem) + Sort (orders)
-- or Index Scan (if the PK index covers the sort order)
EXPLAIN (ANALYZE, FORMAT TEXT)
SELECT o.o_orderdate, SUM(l.l_extendedprice) AS line_total
FROM   orders   o
JOIN   lineitem l ON l.l_orderkey = o.o_orderkey
WHERE  o.o_orderdate BETWEEN DATE '1995-01-01' AND DATE '1995-01-31'
GROUP  BY o.o_orderkey, o.o_orderdate
ORDER  BY o.o_orderdate
LIMIT  50;

-- § join_strategy_summary
-- ─────────────────────────────────────────────────────────────────────────────
-- Reference: when does PostgreSQL choose each join strategy?
-- ─────────────────────────────────────────────────────────────────────────────
-- This is a comment-only section — no runnable SQL.
-- Its content is rendered as a reference table in the notebook.
--
-- | Strategy     | Outer rows | Inner rows | Inner index? | Pre-sorted? |
-- |:-------------|:-----------|:-----------|:-------------|:------------|
-- | Nested Loop  | Small      | Any        | Yes          | No          |
-- | Hash Join    | Any        | Any        | No           | No          |
-- | Merge Join   | Any        | Any        | Optional     | Yes (both)  |
--
-- PostgreSQL can use Parallel versions of all three for large tables when
-- max_parallel_workers_per_gather > 0 (default: 2).
SELECT 1;  -- placeholder to keep the section executable
