-- =============================================================================
-- CTEs 01 — Chained CTEs
-- =============================================================================
-- Demonstrates how to decompose a complex multi-join aggregation into named,
-- readable CTE steps using the TPC-H dataset.
--
-- Business question:
--   Which are the top 10 nations by net revenue from high-priority orders
--   shipped in 1995, and what share of their total order count do those
--   orders represent?
--
-- Without CTEs this would be a single deeply-nested subquery.
-- With chained CTEs each transformation step is named and independently
-- readable — the final SELECT reads like a summary of the steps above it.
--
-- Run against: PostgreSQL 16
-- Tables used: lineitem, orders, customer, nation, region
-- =============================================================================

-- § chained_ctes
-- ─────────────────────────────────────────────────────────────────────────────
-- Step-by-step decomposition using five named CTEs
-- ─────────────────────────────────────────────────────────────────────────────
--
-- CTE execution order in PostgreSQL 12+ (default: NOT MATERIALIZED):
--   The planner may inline any CTE that is referenced once and has no
--   side-effects.  To guarantee one execution regardless of reference count,
--   use WITH name AS MATERIALIZED (...).
--
-- Here `high_priority_lines` is referenced only in `order_revenue` so the
-- planner will inline it.  `nation_totals` is referenced in the final SELECT
-- only, so it is also inlined.  This is the correct default behaviour — the
-- planner can push predicates through inlined CTEs for better index use.
WITH

-- 1. Filter to shipped lineitems from high-priority orders in 1995.
--    Net price = extended price after discount, before tax.
high_priority_lines AS (
    SELECT
        l.l_orderkey,
        l.l_extendedprice * (1 - l.l_discount)  AS net_price
    FROM   lineitem l
    JOIN   orders   o ON l.l_orderkey = o.o_orderkey
    WHERE  o.o_orderpriority IN ('1-URGENT', '2-HIGH')
      AND  l.l_shipdate BETWEEN DATE '1995-01-01' AND DATE '1995-12-31'
),

-- 2. Aggregate net revenue per order, then join to customer for the nation key.
order_revenue AS (
    SELECT
        o.o_custkey,
        SUM(hpl.net_price)  AS order_net_revenue
    FROM   high_priority_lines   hpl
    JOIN   orders                o   ON hpl.l_orderkey = o.o_orderkey
    GROUP  BY o.o_custkey
),

-- 3. Attach nation and region names from the geographical hierarchy.
customer_nation AS (
    SELECT
        c.c_custkey,
        n.n_name    AS nation,
        r.r_name    AS region
    FROM   customer c
    JOIN   nation   n ON c.c_nationkey = n.n_nationkey
    JOIN   region   r ON n.n_regionkey = r.r_regionkey
),

-- 4. Join revenue to geography and roll up to nation level.
nation_revenue AS (
    SELECT
        cn.region,
        cn.nation,
        SUM(orv.order_net_revenue)  AS total_net_revenue,
        COUNT(DISTINCT orv.o_custkey) AS contributing_customers
    FROM   order_revenue    orv
    JOIN   customer_nation  cn  ON orv.o_custkey = cn.c_custkey
    GROUP  BY cn.region, cn.nation
),

-- 5. Compute each nation's total order count (all priorities, all years) for
--    the share calculation in the final SELECT.
--    MATERIALIZED forces this CTE to execute once and store the result even
--    though it is only referenced once.  Justified here if the planner would
--    otherwise produce a poor plan by inlining a full-table GROUP BY alongside
--    the filtered CTEs above.
nation_totals AS MATERIALIZED (
    SELECT
        n.n_name        AS nation,
        COUNT(*)        AS total_orders
    FROM   orders   o
    JOIN   customer c ON o.o_custkey   = c.c_custkey
    JOIN   nation   n ON c.c_nationkey = n.n_nationkey
    GROUP  BY n.n_name
)

-- Final SELECT — reads as a plain-English summary of the five steps above.
SELECT
    nr.region,
    nr.nation,
    ROUND(nr.total_net_revenue::NUMERIC, 2)          AS net_revenue_1995,
    nr.contributing_customers,
    nt.total_orders,
    ROUND(
        100.0 * nr.contributing_customers / nt.total_orders,
        2
    )                                                AS pct_customers_with_priority_order
FROM   nation_revenue  nr
JOIN   nation_totals   nt ON nr.nation = nt.nation
ORDER  BY net_revenue_1995 DESC
LIMIT  10;
