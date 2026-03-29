-- =============================================================================
-- Window Functions 02 — LAG and LEAD
-- =============================================================================
-- Demonstrates LAG / LEAD for time-series comparison on TPC-H data.
--
-- Business question:
--   • How does each clerk's monthly order value change month-over-month?
--   • What does the following month look like?
--
-- Run against: PostgreSQL 16
-- Tables used: orders
-- =============================================================================

-- § lag_lead
-- ─────────────────────────────────────────────────────────────────────────────
-- LAG / LEAD — month-over-month revenue per clerk
-- ─────────────────────────────────────────────────────────────────────────────
-- LAG(col)  accesses the previous row's value within the window partition.
-- LEAD(col) accesses the next row's value within the window partition.
-- Both return NULL when no such row exists (first and last month respectively).
--
-- DATE_TRUNC('month', ...) floors the order date to the first of the month,
-- enabling monthly aggregation without a separate calendar table.
--
-- A second CTE (with_lag) materialises the LAG / LEAD results so they can be
-- referenced in arithmetic expressions without repeating the window calls.
-- NULLIF(prev_month_revenue, 0) prevents division-by-zero at boundary months.
WITH monthly_clerk AS (
    SELECT
        o_clerk,
        DATE_TRUNC('month', o_orderdate)::DATE  AS order_month,
        SUM(o_totalprice)                       AS monthly_revenue
    FROM   orders
    GROUP  BY o_clerk, DATE_TRUNC('month', o_orderdate)
),
with_lag AS (
    SELECT
        o_clerk,
        order_month,
        monthly_revenue,
        LAG(monthly_revenue)  OVER w  AS prev_month_revenue,
        LEAD(monthly_revenue) OVER w  AS next_month_revenue
    FROM   monthly_clerk
    WINDOW w AS (PARTITION BY o_clerk ORDER BY order_month)
)
SELECT
    o_clerk,
    order_month,
    monthly_revenue,
    prev_month_revenue,
    next_month_revenue,
    ROUND((monthly_revenue - prev_month_revenue)::NUMERIC, 2)    AS mom_change,
    ROUND(
        100.0 * (monthly_revenue - prev_month_revenue)
            / NULLIF(prev_month_revenue, 0),
        1
    )                                                             AS mom_pct_change
FROM   with_lag
ORDER  BY o_clerk, order_month
LIMIT  40;
