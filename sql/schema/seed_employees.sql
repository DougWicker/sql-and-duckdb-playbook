-- =============================================================================
-- dim_employee — synthetic hierarchy for recursive CTE demo (Phase 2)
-- =============================================================================
-- A small, readable management hierarchy intentionally designed to showcase
-- every key concept in a recursive CTE:
--
--   * A root node with NULL manager_id (the anchor row)
--   * Multiple levels of depth
--   * Multiple reports per manager (fanout > 1)
--   * Meaningful path strings: "Alice Chen / Bob Patel / Dan Okafor / Grace Kim"
--
-- Why not use TPC-H for the recursive demo?
-- TPC-H has no natural parent-child hierarchy deep enough to be interesting.
-- An org chart is universally understood and maps directly to the real-world
-- uses of recursive CTEs: org charts, category trees, bill-of-materials,
-- network traversal.
-- =============================================================================

DROP TABLE IF EXISTS dim_employee CASCADE;

CREATE TABLE dim_employee (
    id          INTEGER      PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL,
    title       VARCHAR(50)  NOT NULL,
    -- Self-referencing FK: NULL for the root node (the CEO).
    -- Checked constraint ensures no row references a non-existent manager.
    manager_id  INTEGER      REFERENCES dim_employee (id)
);

-- Hierarchy (4 levels, mirrors a realistic mid-size engineering org):
--
--   Alice Chen  (CEO)
--   ├─ Bob Patel  (VP Engineering)
--   │  ├─ Dan Okafor  (Engineering Manager)
--   │  │  ├─ Grace Kim    (Senior Engineer)
--   │  │  └─ Hiro Tanaka  (Engineer)
--   │  └─ Eve Larsson  (Engineering Manager)
--   │     └─ Isla Brown  (Senior Engineer)
--   └─ Carol Diaz  (VP Sales)
--      └─ Frank Müller  (Sales Manager)
--         └─ Jake Williams  (Account Executive)

INSERT INTO dim_employee (id, name, title, manager_id) VALUES
    ( 1, 'Alice Chen',    'CEO',                    NULL),
    ( 2, 'Bob Patel',     'VP Engineering',            1),
    ( 3, 'Carol Diaz',    'VP Sales',                  1),
    ( 4, 'Dan Okafor',    'Engineering Manager',        2),
    ( 5, 'Eve Larsson',   'Engineering Manager',        2),
    ( 6, 'Frank Müller',  'Sales Manager',              3),
    ( 7, 'Grace Kim',     'Senior Engineer',            4),
    ( 8, 'Hiro Tanaka',   'Engineer',                   4),
    ( 9, 'Isla Brown',    'Senior Engineer',            5),
    (10, 'Jake Williams', 'Account Executive',          6);
