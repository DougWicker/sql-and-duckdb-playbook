-- =============================================================================
-- Window Functions 03 — Running Totals and Moving Averages
-- =============================================================================
-- Demonstrates SUM / AVG with explicit frame clauses, FIRST_VALUE / LAST_VALUE.
--
-- Business questions:
--   • What is the cumulative monthly revenue since the first order?
--   • What is the 3-month moving average of monthly revenue?
--   • What is each customer's best and worst order shown alongside every order?
--
-- Run against: PostgreSQL 16
-- Tables used: orders, customer
-- =============================================================================

-- § running_total
-- ─────────────────────────────────────────────────────────────────────────────
-- SUM OVER — cumulative monthly revenue (running total)
-- ─────────────────────────────────────────────────────────────────────────────
-- The outer SUM is a window function; the inner SUM(o_totalprice) is the
-- GROUP BY aggregate.  PostgreSQL evaluates GROUP BY first, then applies
-- window functions on the aggregated rows.
--
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW defines the running frame:
-- start of the ordered partition up to and including the current row.
-- Writing the frame clause explicitly avoids relying on the implicit default,
-- which changes behaviour when ORDER BY is present or absent.
SELECT
    order_month,
    monthly_revenue,
    SUM(monthly_revenue) OVER (
        ORDER BY order_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                AS cumulative_revenue
FROM (
    SELECT
        DATE_TRUNC('month', o_orderdate)::DATE   AS order_month,
        ROUND(SUM(o_totalprice)::NUMERIC, 2)     AS monthly_revenue
    FROM   orders
    GROUP  BY DATE_TRUNC('month', o_orderdate)
) monthly
ORDER  BY order_month;

-- § moving_avg_3m
-- ─────────────────────────────────────────────────────────────────────────────
-- AVG OVER — 3-month sliding window moving average
-- ─────────────────────────────────────────────────────────────────────────────
-- ROWS BETWEEN 2 PRECEDING AND CURRENT ROW defines a window of at most 3 rows:
-- the current row plus the two immediately before it in the ordered partition.
--
-- For the first two months fewer than 3 rows are available; the average is
-- computed over however many rows exist — no values are dropped or set to NULL.
-- This is the correct edge behaviour for a sliding window.
SELECT
    order_month,
    monthly_revenue,
    ROUND(
        AVG(monthly_revenue) OVER (
            ORDER BY order_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )::NUMERIC,
        2
    )                                                AS moving_avg_3m
FROM (
    SELECT
        DATE_TRUNC('month', o_orderdate)::DATE   AS order_month,
        SUM(o_totalprice)                        AS monthly_revenue
    FROM   orders
    GROUP  BY DATE_TRUNC('month', o_orderdate)
) monthly
ORDER  BY order_month;

-- § first_last_value
-- ─────────────────────────────────────────────────────────────────────────────
-- FIRST_VALUE / LAST_VALUE — best and worst order alongside every order
-- ─────────────────────────────────────────────────────────────────────────────
-- FIRST_VALUE returns the expression from the first row of the window frame.
-- LAST_VALUE  returns the expression from the last row of the window frame.
--
-- CRITICAL GOTCHA: the default window frame is
--   RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- This means LAST_VALUE returns the *current* row's value, not the partition's
-- last row.  You MUST extend the frame to:
--   ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
-- to see the true last row of the entire partition.
--
-- Restricted to 5 high-order-count customers for readable output.
SELECT
    c.c_name                                              AS customer,
    o.o_orderkey,
    o.o_orderdate,
    o.o_totalprice,
    FIRST_VALUE(o.o_totalprice) OVER w                    AS best_order_value,
    LAST_VALUE(o.o_totalprice)  OVER w                    AS worst_order_value,
    ROUND(
        (o.o_totalprice - FIRST_VALUE(o.o_totalprice) OVER w)::NUMERIC, 2
    )                                                     AS gap_from_best
FROM   orders   o
JOIN   customer c ON o.o_custkey = c.c_custkey
WHERE  o.o_custkey IN (
    SELECT o_custkey
    FROM   orders
    GROUP  BY o_custkey
    ORDER  BY COUNT(*) DESC
    LIMIT  5
)
WINDOW w AS (
    PARTITION BY o.o_custkey
    ORDER BY o.o_totalprice DESC
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
ORDER  BY customer, o.o_totalprice DESC;
