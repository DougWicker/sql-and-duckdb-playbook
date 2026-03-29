-- =============================================================================
-- Window Functions 01 — Ranking
-- =============================================================================
-- Demonstrates ROW_NUMBER, RANK, DENSE_RANK, and NTILE(4) on TPC-H data.
--
-- Business questions:
--   • Which customers are the biggest spenders within each nation?
--   • How should tied spends be handled for different reporting needs?
--   • How can orders be segmented into revenue quartiles?
--
-- Run against: PostgreSQL 16
-- Tables used: customer, orders, nation
-- =============================================================================

-- § ranking_window
-- ─────────────────────────────────────────────────────────────────────────────
-- ROW_NUMBER / RANK / DENSE_RANK  (customer × orders × nation)
-- ─────────────────────────────────────────────────────────────────────────────
-- All three rank variants computed in a single pass — no self-join needed.
--
--   ROW_NUMBER  — unique sequential integer; tied rows receive different values
--   RANK        — tied rows share a rank; the next distinct rank skips (gap)
--   DENSE_RANK  — tied rows share a rank; the next distinct rank is consecutive
--
-- WINDOW w AS (...)  names the window definition once so PARTITION BY /
-- ORDER BY is not repeated for each function call.
SELECT
    c.c_name,
    n.n_name                                              AS nation,
    SUM(o.o_totalprice)                                   AS total_spend,
    ROW_NUMBER() OVER w                                   AS row_num,
    RANK()       OVER w                                   AS rnk,
    DENSE_RANK() OVER w                                   AS dense_rnk
FROM   customer c
JOIN   orders   o  ON c.c_custkey   = o.o_custkey
JOIN   nation   n  ON c.c_nationkey = n.n_nationkey
GROUP  BY c.c_custkey, c.c_name, n.n_nationkey, n.n_name
WINDOW w AS (
    PARTITION BY n.n_nationkey
    ORDER BY SUM(o.o_totalprice) DESC
)
ORDER  BY nation, rnk
LIMIT  60;

-- § ntile_quartiles
-- ─────────────────────────────────────────────────────────────────────────────
-- NTILE(4) — segment all orders into revenue quartiles
-- ─────────────────────────────────────────────────────────────────────────────
-- NTILE(n) distributes rows into n equal-sized buckets ordered by the window
-- ORDER BY.  The output is always exactly 1..n — no ties produce duplicate IDs.
--
-- Quartile 1 = highest-value 25% of orders;  quartile 4 = lowest-value 25%.
-- The outer GROUP BY rolls up each bucket to show its size and price range.
SELECT
    revenue_quartile,
    COUNT(*)                                    AS order_count,
    MIN(o_totalprice)                           AS min_price,
    MAX(o_totalprice)                           AS max_price,
    ROUND(AVG(o_totalprice)::NUMERIC, 2)        AS avg_price
FROM (
    SELECT
        o_orderkey,
        o_totalprice,
        NTILE(4) OVER (ORDER BY o_totalprice DESC) AS revenue_quartile
    FROM orders
) t
GROUP  BY revenue_quartile
ORDER  BY revenue_quartile;
