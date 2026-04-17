-- § direct_query
-- Direct file query: no CREATE TABLE, no schema declaration needed.
-- DuckDB infers column names and types from the Parquet metadata footer.
SELECT
    l_returnflag,
    l_linestatus,
    COUNT(*)                                            AS line_count,
    SUM(l_quantity)                                     AS total_qty,
    ROUND(SUM(l_extendedprice), 2)                     AS total_ext_price,
    ROUND(SUM(l_extendedprice * (1 - l_discount)), 2)  AS total_disc_price
FROM read_parquet('data/parquet/lineitem.parquet')
GROUP BY l_returnflag, l_linestatus
ORDER BY l_returnflag, l_linestatus;

-- § glob_query
-- Glob pattern: read multiple files as a single virtual table.
-- DuckDB unifies the schemas automatically — column names must match.
-- Here we read the 8 flat TPC-H Parquet files that have an 'o_orderkey' column
-- by targeting orders.parquet directly, then show the glob pattern on a
-- multi-file scenario using the partitioned layout.
SELECT
    o_orderstatus,
    COUNT(*)              AS order_count,
    ROUND(SUM(o_totalprice), 2) AS total_price
FROM read_parquet('data/parquet/orders_partitioned/**/*.parquet',
                  hive_partitioning = false)
GROUP BY o_orderstatus
ORDER BY order_count DESC;

-- § schema_inference
-- DuckDB's schema inference: inspect column names and types
-- that Parquet metadata provides — no CREATE TABLE required.
DESCRIBE SELECT * FROM read_parquet('data/parquet/lineitem.parquet');
