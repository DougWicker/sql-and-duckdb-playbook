-- =============================================================================
-- CTEs 02 — Recursive CTEs
-- =============================================================================
-- Demonstrates recursive CTEs using the dim_employee org hierarchy.
-- Built progressively: each query adds one concept to the previous one.
--
-- Real-world applications of recursive CTEs:
--   * Org charts (this demo)
--   * Category / folder trees (e-commerce, file systems)
--   * Bill-of-materials (manufacturing — parts that contain sub-parts)
--   * Network traversal (graph edges stored as parent-child rows)
--
-- Run against: PostgreSQL 16
-- Tables used: dim_employee (see sql/schema/seed_employees.sql)
--
-- Org hierarchy for reference:
--   Alice Chen (CEO)
--   ├─ Bob Patel (VP Engineering)
--   │  ├─ Dan Okafor (Engineering Manager)
--   │  │  ├─ Grace Kim (Senior Engineer)
--   │  │  └─ Hiro Tanaka (Engineer)
--   │  └─ Eve Larsson (Engineering Manager)
--   │     └─ Isla Brown (Senior Engineer)
--   └─ Carol Diaz (VP Sales)
--      └─ Frank Müller (Sales Manager)
--         └─ Jake Williams (Account Executive)
-- =============================================================================

-- § basic_recursion
-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1 — Traverse the hierarchy from root
-- ─────────────────────────────────────────────────────────────────────────────
-- A recursive CTE has two mandatory parts separated by UNION ALL:
--
--   ANCHOR   — the non-recursive SELECT that seeds the recursion (the root).
--              Must return the same columns as the recursive term.
--   RECURSIVE TERM — references the CTE name itself to walk one level deeper.
--              Executed repeatedly until it produces no new rows.
--
-- RECURSIVE is a keyword modifier on WITH, not on the individual CTE.
-- All CTEs in a WITH RECURSIVE block may use recursion — but only this one does.
WITH RECURSIVE org_tree AS (

    -- Anchor: the root node — the employee with no manager.
    SELECT
        id,
        name,
        title,
        manager_id
    FROM   dim_employee
    WHERE  manager_id IS NULL

    UNION ALL

    -- Recursive term: join each already-found employee to their direct reports.
    -- PostgreSQL executes this repeatedly; each pass adds one more level.
    -- Terminates when the JOIN produces no new rows (leaf nodes have no reports).
    SELECT
        e.id,
        e.name,
        e.title,
        e.manager_id
    FROM   dim_employee   e
    JOIN   org_tree       ot ON e.manager_id = ot.id
)
SELECT id, name, title, manager_id
FROM   org_tree
ORDER  BY id;

-- § depth_column
-- ─────────────────────────────────────────────────────────────────────────────
-- Step 2 — Add a depth counter
-- ─────────────────────────────────────────────────────────────────────────────
-- The anchor initialises depth = 0.  Each recursive pass increments depth + 1.
-- This produces the level in the hierarchy for every employee.
WITH RECURSIVE org_tree AS (

    SELECT
        id,
        name,
        title,
        manager_id,
        0  AS depth                  -- root sits at depth 0
    FROM   dim_employee
    WHERE  manager_id IS NULL

    UNION ALL

    SELECT
        e.id,
        e.name,
        e.title,
        e.manager_id,
        ot.depth + 1                 -- each level adds 1
    FROM   dim_employee  e
    JOIN   org_tree      ot ON e.manager_id = ot.id
)
SELECT
    depth,
    REPEAT('    ', depth) || name  AS indented_name,   -- visual indent
    title
FROM   org_tree
ORDER  BY depth, name;

-- § path_accumulation
-- ─────────────────────────────────────────────────────────────────────────────
-- Step 3 — Accumulate a full path string from root to each node
-- ─────────────────────────────────────────────────────────────────────────────
-- The anchor seeds path with just the root name.
-- Each recursive pass appends ' / ' and the current employee's name.
-- Result: "Alice Chen / Bob Patel / Dan Okafor / Grace Kim"
--
-- path_array (TEXT[]) is built in parallel and used for cycle detection
-- in the next query step.
WITH RECURSIVE org_tree AS (

    SELECT
        id,
        name,
        title,
        manager_id,
        0                       AS depth,
        name                    AS path,            -- root: just the name
        ARRAY[id]               AS path_array       -- root: [1]
    FROM   dim_employee
    WHERE  manager_id IS NULL

    UNION ALL

    SELECT
        e.id,
        e.name,
        e.title,
        e.manager_id,
        ot.depth + 1,
        ot.path || ' / ' || e.name,                -- append name
        ot.path_array || e.id                       -- append id
    FROM   dim_employee  e
    JOIN   org_tree      ot ON e.manager_id = ot.id
)
SELECT
    depth,
    title,
    path
FROM   org_tree
ORDER  BY path;

-- § cycle_detection
-- ─────────────────────────────────────────────────────────────────────────────
-- Step 4 — Cycle detection guard
-- ─────────────────────────────────────────────────────────────────────────────
-- In a well-maintained org chart, cycles cannot exist (FK prevents them).
-- In real-world data (category trees, network graphs) cycles are common.
-- The guard: only follow an edge if the target node is NOT already in our path.
--
-- e.id <> ALL(ot.path_array) — true only when e.id has not been visited yet.
-- Without this guard a cyclic graph would cause infinite recursion.
--
-- PostgreSQL also supports the SQL:1999 CYCLE clause (v14+) as a cleaner
-- alternative, but the array guard is widely portable and explicit.
WITH RECURSIVE org_tree AS (

    SELECT
        id,
        name,
        title,
        manager_id,
        0                       AS depth,
        name                    AS path,
        ARRAY[id]               AS path_array
    FROM   dim_employee
    WHERE  manager_id IS NULL

    UNION ALL

    SELECT
        e.id,
        e.name,
        e.title,
        e.manager_id,
        ot.depth + 1,
        ot.path || ' / ' || e.name,
        ot.path_array || e.id
    FROM   dim_employee  e
    JOIN   org_tree      ot ON e.manager_id = ot.id
    WHERE  e.id <> ALL(ot.path_array)              -- cycle guard
)
SELECT
    depth,
    title,
    path
FROM   org_tree
ORDER  BY path;
