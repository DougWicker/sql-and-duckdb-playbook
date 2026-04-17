-- TPC-H Q5 — Local Supplier Volume
-- 6-table join (region, nation, supplier, customer, orders, lineitem).
-- Broad OLAP shape: every major dimension table in play, GROUP BY nation.

-- § q5
SELECT
    n.n_name                                             AS nation,
    SUM(l.l_extendedprice * (1 - l.l_discount))         AS revenue
FROM   region   r
JOIN   nation   n  ON n.n_regionkey  = r.r_regionkey
JOIN   customer c  ON c.c_nationkey  = n.n_nationkey
JOIN   orders   o  ON o.o_custkey    = c.c_custkey
JOIN   lineitem l  ON l.l_orderkey   = o.o_orderkey
JOIN   supplier s  ON l.l_suppkey    = s.s_suppkey
                   AND s.s_nationkey = c.c_nationkey
WHERE  r.r_name      = 'ASIA'
  AND  o.o_orderdate >= DATE '1994-01-01'
  AND  o.o_orderdate  < DATE '1994-01-01' + INTERVAL '1 year'
GROUP  BY n.n_name
ORDER  BY revenue DESC;
