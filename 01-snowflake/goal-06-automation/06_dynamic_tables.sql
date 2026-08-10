-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 6       : Automate Workflows
-- Sub-task 6.6 : Work with Dynamic Tables
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~40-50 min
-- Warehouse size    : X-Small (WORKBOOK_WH)
-- Database          : ECOMMERCE.RAW
-- Run in            : Snowsight
-- Prerequisites     : Sub-tasks 6.1-6.5 complete
-- COF-C03 domain    : Domain 4.0 — Performance Optimization,
--                      Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════
--   Sub-task 6.3 built an incremental pipeline the IMPERATIVE way:
--   a Stream to detect changes, a Task to schedule the work, and a
--   hand-written MERGE to apply it correctly. Dynamic Tables do the
--   same job the DECLARATIVE way — you describe the END STATE you
--   want (a query) and a freshness target, and Snowflake figures
--   out how to keep it that fresh, including whether to do an
--   incremental or full refresh under the hood.
--
--   You will rebuild 6.3's ORDERS_MART as a Dynamic Table, watch
--   it refresh automatically, inspect how Snowflake chose to
--   refresh it, try to modify it directly (and see why that's not
--   allowed), and chain a second Dynamic Table on top of the first
--   to see declarative freshness propagate backward through a
--   pipeline with no Task or Stream involved anywhere.
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- CONCEPT
-- ══════════════════════════════════════════════════════════════
--   CREATE DYNAMIC TABLE takes a SELECT query and a TARGET_LAG —
--   the maximum staleness you're willing to tolerate — and a
--   warehouse to run refreshes on. Snowflake handles everything
--   else: deciding when to refresh, whether that refresh can be
--   INCREMENTAL (computing only the delta, similar in spirit to
--   what 6.3's Stream+MERGE did by hand) or must fall back to FULL
--   (recomputing the entire result), and running it — no Task, no
--   Stream, no MERGE statement written by you at all.
--
--   Dynamic Tables fully support complex queries — joins, unions,
--   aggregations, window functions, CTEs, multi-table pipelines,
--   even Cortex AI functions in the SELECT. This is a genuinely
--   different capability from Snowflake's OTHER materialized view
--   feature (Goal 5), which is restricted to a SINGLE source table
--   with no joins at all. If you're coming from Oracle materialized
--   views (which do support joins), a Dynamic Table is the much
--   closer analog on query complexity.
--
--   But there's a real gap in the OTHER direction: Snowflake never
--   automatically substitutes a Dynamic Table the way Oracle's
--   optimizer rewrites a query to use a fast-refresh MV, or the way
--   Goal 5's Snowflake Materialized View gets silently used via
--   query rewrite. Querying ORDERS directly NEVER transparently
--   routes to ORDERS_MART_DT — you must query the Dynamic Table by
--   name, explicitly, every time. This is the actual tradeoff
--   versus what you're used to from Oracle, not query complexity.
--
--   Confirmed limitations worth knowing:
--     · Minimum TARGET_LAG is 60 seconds — no sub-minute freshness
--     · No stored procedures or external functions in the defining
--       query (6.5's toolkit doesn't carry over here)
--     · Cannot source from streams, external tables, directory
--       tables, or other materialized views
--     · Max 50,000 Dynamic Tables per account
--     · Not everything is eligible for incremental refresh — some
--       query constructs force FULL refresh every time. SHOW
--       DYNAMIC TABLES exposes which mode Snowflake actually chose
--       for a given table, worth checking rather than assuming.
--
--   TARGET_LAG has two forms:
--     · A literal duration ('1 minute', '1 hour') — refresh often
--       enough that data is never staler than this.
--     · DOWNSTREAM — don't maintain your own freshness schedule at
--       all; instead, refresh only as needed to satisfy whatever
--       Dynamic Tables are built ON TOP of you. This is what makes
--       CHAINING work: freshness requirements propagate backward
--       automatically through a whole dependency graph of Dynamic
--       Tables, without you wiring up a DAG by hand.
--
--   A Dynamic Table is READ-ONLY from the outside — you cannot
--   INSERT/UPDATE/DELETE into one directly. Its contents are
--   entirely owned by its own defining query and refresh cycle.
--
-- ── ORACLE / SQL SERVER COMPARISON ──────────────────────────────
--   Oracle       : Materialized views with ON COMMIT or fast
--                  refresh and a refresh interval, SUPPORTING joins
--                  — the query-complexity story matches Dynamic
--                  Tables closely. The real difference: Oracle's
--                  fast-refresh MV participates in query rewrite
--                  (the optimizer can silently use it when you
--                  query the base tables), while a Dynamic Table
--                  never does — you always query it by name.
--   SQL Server   : Indexed views are the closest analog, but they
--                  refresh synchronously on every underlying write
--                  (no lag concept at all) and have tight
--                  restrictions on what queries qualify — no
--                  equivalent to TARGET_LAG's tolerance window.
--   Snowflake    : Two DIFFERENT materialized-result features exist
--                  side by side: the Goal 5 Materialized View
--                  (single table only, but DOES get automatic query
--                  rewrite) and the Dynamic Table (full join/
--                  aggregation support, but NEVER gets automatic
--                  query rewrite). Pick based on which tradeoff
--                  matches the need — query complexity vs.
--                  transparent substitution — not by defaulting to
--                  whichever one sounds more "materialized view"-like.
-- ──────────────────────────────────────────────────────────────
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create a Dynamic Table — the declarative equivalent
-- of 6.3's Stream+Task+MERGE pipeline
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE ECOMMERCE.RAW.ORDERS_MART_DT
    TARGET_LAG = '1 minute'
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6.6 — declarative equivalent of 6.3''s ORDERS_MART'
AS
    SELECT order_id, customer_id, order_status, created_at
    FROM ECOMMERCE.RAW.ORDERS;

SHOW DYNAMIC TABLES LIKE 'ORDERS_MART_DT';
-- Check the refresh_mode column — this is what Snowflake actually
-- chose (INCREMENTAL or FULL), not necessarily what you'd expect.

SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS_MART_DT;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Change the source, then watch it refresh automatically
-- ══════════════════════════════════════════════════════════════
-- No task to resume, no stream to consume — just change ORDERS
-- and wait past the TARGET_LAG window.

-- Highlight from BEGIN through COMMIT and run together
BEGIN;

INSERT INTO ECOMMERCE.RAW.ORDERS (order_id, customer_id, order_status, created_at)
VALUES (900000005, 1, 'pending', CURRENT_TIMESTAMP());

COMMIT;

-- Wait 1-2 minutes past TARGET_LAG, then check
SELECT * FROM ECOMMERCE.RAW.ORDERS_MART_DT WHERE order_id = 900000005;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Inspect refresh history
-- ══════════════════════════════════════════════════════════════

SELECT
    name,
    state,
    refresh_start_time,
    refresh_end_time,
    refresh_action,
    state_message
FROM TABLE(
    INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
        NAME => 'ECOMMERCE.RAW.ORDERS_MART_DT'
    )
)
ORDER BY refresh_start_time DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Confirm it's read-only from the outside
-- ══════════════════════════════════════════════════════════════

INSERT INTO ECOMMERCE.RAW.ORDERS_MART_DT (order_id, customer_id, order_status, created_at)
VALUES (999999999, 1, 'pending', CURRENT_TIMESTAMP());
-- Expect this to fail — a Dynamic Table's contents are entirely
-- owned by its own defining query and refresh cycle, not writable
-- directly by anyone, including the role that created it.

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Chain a second Dynamic Table — declarative freshness
-- propagation, no manual DAG wiring
-- ══════════════════════════════════════════════════════════════
-- Switch the first table to DOWNSTREAM — it no longer maintains
-- its own fixed schedule, only refreshing as needed to satisfy
-- whatever is built on top of it.

ALTER DYNAMIC TABLE ECOMMERCE.RAW.ORDERS_MART_DT SET TARGET_LAG = DOWNSTREAM;

CREATE OR REPLACE DYNAMIC TABLE ECOMMERCE.RAW.ORDER_STATUS_SUMMARY_DT
    TARGET_LAG = '2 minutes'
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6.6 — chained on top of ORDERS_MART_DT'
AS
    SELECT order_status, COUNT(*) AS order_count
    FROM ECOMMERCE.RAW.ORDERS_MART_DT
    GROUP BY order_status;

-- ORDERS_MART_DT will now refresh only as often as needed to keep
-- ORDER_STATUS_SUMMARY_DT within ITS 2-minute target — Snowflake
-- works this out on its own; nothing was scheduled by hand.

SELECT * FROM ECOMMERCE.RAW.ORDER_STATUS_SUMMARY_DT ORDER BY order_status;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Cleanup — suspend both
-- ══════════════════════════════════════════════════════════════
-- ⚠️ TARGET_LAG refresh has a real, ongoing background credit
-- cost, same discipline as Tasks in 6.1/6.3/6.4 — suspend as soon
-- as the teaching purpose is served.

ALTER DYNAMIC TABLE ECOMMERCE.RAW.ORDER_STATUS_SUMMARY_DT SUSPEND;
ALTER DYNAMIC TABLE ECOMMERCE.RAW.ORDERS_MART_DT SUSPEND;

SHOW DYNAMIC TABLES LIKE 'ORDERS_MART_DT';
SHOW DYNAMIC TABLES LIKE 'ORDER_STATUS_SUMMARY_DT';
-- Both should show scheduling_state = 'SUSPENDED'

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
-- Your turn:
--   1. Create a Dynamic Table on RETURNS with a 2-minute TARGET_LAG.
--   2. Insert a new row into RETURNS, wait past the lag window, and
--      confirm it appears via the Dynamic Table.
--   3. Check SHOW DYNAMIC TABLES to see which refresh_mode
--      Snowflake chose for it.
--   4. Suspend it when done.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
-- Q: I know Oracle materialized views well — are Dynamic Tables
--    really the same thing with joins allowed?
-- A: Close, but check which direction the difference runs before
--    assuming full equivalence. Query complexity: yes, matches —
--    joins, aggregations, multi-table pipelines all work the same
--    way. Query REWRITE: no — Oracle's fast-refresh MV can be
--    silently substituted by the optimizer when you query the base
--    tables directly; a Dynamic Table never is, you always query
--    it by name. That's the actual gap, not query capability.
--    (Confusingly, Snowflake's OTHER materialized view feature from
--    Goal 5 has the opposite tradeoff: it DOES get query rewrite,
--    but is restricted to a single table with no joins at all.)
--
-- Q: When would you choose Stream+Task+MERGE (6.3) over a Dynamic
--    Table for the exact same job?
-- A: When you need control the declarative model doesn't give you
--    — custom conflict-resolution logic beyond a straightforward
--    MERGE, multi-step procedural logic (6.5's territory), or
--    integration with something outside plain SQL. For a
--    straightforward "keep this query's result fresh" need, a
--    Dynamic Table is less code and less to maintain.
--
-- Q: Does a shorter TARGET_LAG mean a Dynamic Table refreshes
--    continuously?
-- A: No — TARGET_LAG is a ceiling on staleness, not a fixed
--    schedule. Snowflake refreshes often enough to stay within it,
--    which may be far less frequent than the lag value if the
--    source barely changes, or exactly that frequent if it changes
--    constantly.
--
-- Q: What happens if I need to fix bad data that landed in a
--    Dynamic Table?
-- A: You can't UPDATE/DELETE it directly — fix the problem at the
--    SOURCE (or in the defining query itself), and let the next
--    refresh propagate the correction. This is the same philosophy
--    as a materialized view: it's a derived, managed result, not
--    an independently editable table.
--
-- Q: Why did ORDERS_MART_DT need to switch to TARGET_LAG =
--    DOWNSTREAM before chaining, instead of keeping its own
--    1-minute lag?
-- A: It didn't strictly NEED to — a fixed lag still works upstream
--    of another Dynamic Table. DOWNSTREAM specifically means "let
--    freshness requirements flow backward from whatever's built on
--    me," which becomes valuable once you have multiple downstream
--    consumers with different freshness needs, so you're not
--    manually guessing the right fixed lag for all of them.
-- ══════════════════════════════════════════════════════════════
