-- TPC-H Q3 — Shipping Priority
-- 3-table join (customer, orders, lineitem) + aggregation.
-- Tests join performance and partial aggregation across a large fact table.

-- § q3
SELECT
    l.l_orderkey,
    SUM(l.l_extendedprice * (1 - l.l_discount))  AS revenue,
    o.o_orderdate,
    o.o_shippriority
FROM   customer c
JOIN   orders   o  ON c.c_custkey   = o.o_custkey
JOIN   lineitem l  ON l.l_orderkey  = o.o_orderkey
WHERE  c.c_mktsegment = 'BUILDING'
  AND  o.o_orderdate  < DATE '1995-03-15'
  AND  l.l_shipdate   > DATE '1995-03-15'
GROUP  BY l.l_orderkey, o.o_orderdate, o.o_shippriority
ORDER  BY revenue DESC, o.o_orderdate
LIMIT  10;
