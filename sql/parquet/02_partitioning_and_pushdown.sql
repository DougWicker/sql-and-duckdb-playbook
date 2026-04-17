-- § hive_partition_query
-- Hive partitioning: DuckDB reads the directory name (year=YYYY) as a column
-- and skips entire year-directories when filtering by year.
-- No rows are read from unmatched partitions — file-level pruning.
SELECT
    year,
    o_orderstatus,
    COUNT(*)                    AS order_count,
    ROUND(SUM(o_totalprice), 2) AS total_price
FROM read_parquet('data/parquet/orders_partitioned/**/*.parquet',
                  hive_partitioning = true)
WHERE year = 1996
GROUP BY year, o_orderstatus
ORDER BY o_orderstatus;

-- § minmax_pruning
-- Min/max pruning: DuckDB reads the per-column min/max statistics stored in
-- the Parquet row group footer.  Row groups where the filter value falls
-- outside [min, max] are skipped entirely — no decompression, no I/O.
-- The EXPLAIN output shows 'Row Groups Read' vs 'Row Groups Total'.
EXPLAIN SELECT
    l_orderkey,
    l_shipdate,
    l_extendedprice
FROM read_parquet('data/parquet/lineitem.parquet')
WHERE l_shipdate = DATE '1998-09-01';

-- § write_parquet
-- Write query results back to Parquet.
-- COPY ... TO is DuckDB's export statement; FORMAT PARQUET is the default
-- when the path ends in .parquet.
-- COMPRESSION 'zstd' gives better compression than Snappy with similar speed.
COPY (
    SELECT
        n.n_name                                             AS nation,
        YEAR(o.o_orderdate)                                  AS order_year,
        COUNT(DISTINCT o.o_custkey)                          AS unique_customers,
        ROUND(SUM(o.o_totalprice), 2)                        AS total_revenue
    FROM read_parquet('data/parquet/orders.parquet')   o
    JOIN read_parquet('data/parquet/customer.parquet') c
        ON o.o_custkey   = c.c_custkey
    JOIN read_parquet('data/parquet/nation.parquet')   n
        ON c.c_nationkey = n.n_nationkey
    GROUP BY n.n_name, YEAR(o.o_orderdate)
    ORDER BY nation, order_year
) TO 'data/parquet/nation_revenue_by_year.parquet'
(FORMAT PARQUET, COMPRESSION 'zstd');
