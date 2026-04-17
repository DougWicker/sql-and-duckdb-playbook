-- TPC-H Q1 — Pricing Summary Report
-- Pure aggregation on lineitem (6M rows), no joins.
-- Maximises DuckDB's columnar advantage: only 4 of 16 columns are read.

-- § q1
SELECT
    l_returnflag,
    l_linestatus,
    SUM(l_quantity)                                         AS sum_qty,
    SUM(l_extendedprice)                                    AS sum_base_price,
    SUM(l_extendedprice * (1 - l_discount))                 AS sum_disc_price,
    SUM(l_extendedprice * (1 - l_discount) * (1 + l_tax))  AS sum_charge,
    AVG(l_quantity)                                         AS avg_qty,
    AVG(l_extendedprice)                                    AS avg_price,
    AVG(l_discount)                                         AS avg_disc,
    COUNT(*)                                                AS count_order
FROM   lineitem
WHERE  l_shipdate <= DATE '1998-12-01' - INTERVAL '90 days'
GROUP  BY l_returnflag, l_linestatus
ORDER  BY l_returnflag, l_linestatus;
