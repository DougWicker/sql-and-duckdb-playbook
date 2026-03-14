-- =============================================================================
-- TPC-H Schema — all 8 standard tables
-- =============================================================================
-- Transaction Processing Performance Council (TPC) Benchmark H
-- Specification: https://www.tpc.org/tpch/
--
-- Tables are dropped in reverse FK order and re-created in FK order so this
-- file can be run multiple times without error (idempotent).
--
-- Column names, types, and constraints follow the TPC-H specification v3.0.1.
-- CHAR(n) intentionally not padded to VARCHAR — matches the spec and lets
-- PostgreSQL validate fixed-width code values at insert time.
-- =============================================================================

-- ── Drop in reverse FK order ──────────────────────────────────────────────────
DROP TABLE IF EXISTS lineitem  CASCADE;
DROP TABLE IF EXISTS orders    CASCADE;
DROP TABLE IF EXISTS partsupp  CASCADE;
DROP TABLE IF EXISTS customer  CASCADE;
DROP TABLE IF EXISTS part      CASCADE;
DROP TABLE IF EXISTS supplier  CASCADE;
DROP TABLE IF EXISTS nation    CASCADE;
DROP TABLE IF EXISTS region    CASCADE;

-- ── region ────────────────────────────────────────────────────────────────────
-- Root of the geographical hierarchy. 5 rows (Africa, America, Asia, Europe,
-- Middle East). Referenced by nation.
CREATE TABLE region (
    r_regionkey  INTEGER       NOT NULL,
    r_name       CHAR(25)      NOT NULL,
    r_comment    VARCHAR(152),
    PRIMARY KEY (r_regionkey)
);

-- ── nation ────────────────────────────────────────────────────────────────────
-- 25 rows. Each nation belongs to one region.
-- Referenced by supplier and customer.
CREATE TABLE nation (
    n_nationkey  INTEGER       NOT NULL,
    n_name       CHAR(25)      NOT NULL,
    n_regionkey  INTEGER       NOT NULL,
    n_comment    VARCHAR(152),
    PRIMARY KEY (n_nationkey),
    FOREIGN KEY (n_regionkey) REFERENCES region (r_regionkey)
);

-- ── supplier ──────────────────────────────────────────────────────────────────
-- 10,000 rows at sf=1. Each supplier is located in one nation.
-- Referenced by partsupp and lineitem.
CREATE TABLE supplier (
    s_suppkey    INTEGER       NOT NULL,
    s_name       CHAR(25)      NOT NULL,
    s_address    VARCHAR(40)   NOT NULL,
    s_nationkey  INTEGER       NOT NULL,
    s_phone      CHAR(15)      NOT NULL,
    s_acctbal    DECIMAL(15,2) NOT NULL,
    s_comment    VARCHAR(101),
    PRIMARY KEY (s_suppkey),
    FOREIGN KEY (s_nationkey) REFERENCES nation (n_nationkey)
);

-- ── part ──────────────────────────────────────────────────────────────────────
-- 200,000 rows at sf=1. Describes the products bought and sold.
-- Referenced by partsupp and lineitem.
CREATE TABLE part (
    p_partkey     INTEGER       NOT NULL,
    p_name        VARCHAR(55)   NOT NULL,
    p_mfgr        CHAR(25)      NOT NULL,
    p_brand       CHAR(10)      NOT NULL,
    p_type        VARCHAR(25)   NOT NULL,
    p_size        INTEGER       NOT NULL,
    p_container   CHAR(10)      NOT NULL,
    p_retailprice DECIMAL(15,2) NOT NULL,
    p_comment     VARCHAR(23),
    PRIMARY KEY (p_partkey)
);

-- ── partsupp ──────────────────────────────────────────────────────────────────
-- 800,000 rows at sf=1 (each part has ~4 suppliers).
-- Junction table between part and supplier; also captures supply costs.
CREATE TABLE partsupp (
    ps_partkey    INTEGER       NOT NULL,
    ps_suppkey    INTEGER       NOT NULL,
    ps_availqty   INTEGER       NOT NULL,
    ps_supplycost DECIMAL(15,2) NOT NULL,
    ps_comment    VARCHAR(199),
    PRIMARY KEY (ps_partkey, ps_suppkey),
    FOREIGN KEY (ps_partkey)  REFERENCES part     (p_partkey),
    FOREIGN KEY (ps_suppkey)  REFERENCES supplier (s_suppkey)
);

-- ── customer ──────────────────────────────────────────────────────────────────
-- 150,000 rows at sf=1.  Each customer belongs to one nation.
CREATE TABLE customer (
    c_custkey    INTEGER       NOT NULL,
    c_name       VARCHAR(25)   NOT NULL,
    c_address    VARCHAR(40)   NOT NULL,
    c_nationkey  INTEGER       NOT NULL,
    c_phone      CHAR(15)      NOT NULL,
    c_acctbal    DECIMAL(15,2) NOT NULL,
    c_mktsegment CHAR(10),
    c_comment    VARCHAR(117),
    PRIMARY KEY (c_custkey),
    FOREIGN KEY (c_nationkey) REFERENCES nation (n_nationkey)
);

-- ── orders ────────────────────────────────────────────────────────────────────
-- 1,500,000 rows at sf=1. Each order is placed by one customer.
-- Referenced by lineitem (the largest table in the schema).
CREATE TABLE orders (
    o_orderkey      INTEGER       NOT NULL,
    o_custkey       INTEGER       NOT NULL,
    o_orderstatus   CHAR(1)       NOT NULL,   -- 'F'=fulfilled, 'O'=open, 'P'=partial
    o_totalprice    DECIMAL(15,2) NOT NULL,
    o_orderdate     DATE          NOT NULL,
    o_orderpriority CHAR(15)      NOT NULL,
    o_clerk         CHAR(15)      NOT NULL,
    o_shippriority  INTEGER       NOT NULL,
    o_comment       VARCHAR(79),
    PRIMARY KEY (o_orderkey),
    FOREIGN KEY (o_custkey) REFERENCES customer (c_custkey)
);

-- ── lineitem ──────────────────────────────────────────────────────────────────
-- ~6,000,000 rows at sf=1 — the fact table and primary analytical target.
-- Each row is one line on an order for a specific part from a specific supplier.
-- Most window function and aggregate queries in this repo operate on lineitem.
CREATE TABLE lineitem (
    l_orderkey      INTEGER       NOT NULL,
    l_partkey       INTEGER       NOT NULL,
    l_suppkey       INTEGER       NOT NULL,
    l_linenumber    INTEGER       NOT NULL,
    l_quantity      DECIMAL(15,2) NOT NULL,
    l_extendedprice DECIMAL(15,2) NOT NULL,   -- unit price × quantity
    l_discount      DECIMAL(15,2) NOT NULL,   -- 0.00–0.10
    l_tax           DECIMAL(15,2) NOT NULL,   -- 0.00–0.08
    l_returnflag    CHAR(1)       NOT NULL,   -- 'A'=accepted, 'R'=returned, 'N'=none
    l_linestatus    CHAR(1)       NOT NULL,   -- 'O'=open, 'F'=filled
    l_shipdate      DATE          NOT NULL,
    l_commitdate    DATE          NOT NULL,
    l_receiptdate   DATE          NOT NULL,
    l_shipinstruct  CHAR(25)      NOT NULL,
    l_shipmode      CHAR(10)      NOT NULL,
    l_comment       VARCHAR(44),
    PRIMARY KEY (l_orderkey, l_linenumber),
    FOREIGN KEY (l_orderkey)              REFERENCES orders   (o_orderkey),
    FOREIGN KEY (l_partkey, l_suppkey)    REFERENCES partsupp (ps_partkey, ps_suppkey)
);
