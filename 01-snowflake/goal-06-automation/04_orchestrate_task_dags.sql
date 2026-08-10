-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 6       : Automate Workflows
-- Sub-task 6.4 : Orchestrate with Task DAGs
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~45-55 min
-- Warehouse size    : X-Small (WORKBOOK_WH)
-- Database          : ECOMMERCE.RAW
-- Run in            : Snowsight
-- Prerequisites     : Sub-tasks 6.1-6.3 complete — reuses the
--                      EXECUTE TASK grant to SYSADMIN made in 6.1
-- COF-C03 domain    : Domain 4.0 — Performance Optimization,
--                      Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════
--   6.1-6.3 dealt with a single task doing a single job. Real
--   pipelines usually need several steps to run in a specific
--   order, some in parallel, some only under certain conditions.
--   A Task DAG (directed acyclic graph) is Snowflake's native way
--   to express that: one root task on a schedule, and child tasks
--   that fire only after their specific predecessor(s) succeed.
--
--   You will build a small DAG: a root task that kicks off a run,
--   two child tasks that do independent work in parallel off that
--   same root, a final task that only runs once BOTH of those
--   children succeed, and a conditional branch task that only
--   fires if a business condition is actually met.
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- CONCEPT
-- ══════════════════════════════════════════════════════════════
--   A DAG is built entirely through the AFTER clause:
--     · The ROOT task is the only one with a SCHEDULE — it's the
--       entry point that wakes the whole graph up.
--     · Every other task uses AFTER <predecessor> instead of its
--       own SCHEDULE. It has no schedule of its own; it fires the
--       moment its predecessor(s) succeed.
--     · AFTER can list MULTIPLE predecessors: AFTER task_a, task_b
--       means "only run once BOTH task_a AND task_b have succeeded
--       in this run of the graph" — this is how you build a join
--       point after parallel branches.
--
--   All tasks in a DAG are created SUSPENDED, same as a standalone
--   task. Resuming a DAG one task at a time is error-prone (order
--   matters), so Snowflake provides a single function to do it
--   correctly in one call:
--     SYSTEM$TASK_DEPENDENTS_ENABLE('<root_task_name>')
--   This recursively resumes the named task and every task that
--   depends on it, in the right order, in one call.
--
--   Conditional branching WITHIN a DAG uses the same WHEN clause
--   from sub-task 6.3 — but WHEN is deliberately restrictive. It
--   does NOT support arbitrary SQL (no subqueries against tables).
--   Only two functions are allowed inside a WHEN expression:
--     · SYSTEM$STREAM_HAS_DATA(...)              -- from 6.3
--     · SYSTEM$GET_PREDECESSOR_RETURN_VALUE(...)  -- reads a value
--       a predecessor task explicitly set via SYSTEM$SET_RETURN_VALUE
--   This sub-task's branch example uses SYSTEM$STREAM_HAS_DATA —
--   "only run if something changed since last consumption," reusing
--   ORDERS_STREAM from 6.2. Branching on a genuinely COMPUTED
--   business value (like "only alert if pending count exceeds a
--   threshold") needs a predecessor task that explicitly calls
--   SYSTEM$SET_RETURN_VALUE — which requires a Snowflake Scripting
--   block, not a single plain SQL statement. That's covered
--   properly in sub-task 6.5, once stored procedures are on the
--   table; introducing scripting syntax here, before it's actually
--   explained, would be teaching ahead of itself.
--
--   Compute model: every task in a DAG can share ONE warehouse
--   (as done here) for predictable, poolable cost, or each task
--   can independently be serverless. Mixing is allowed — a DAG is
--   not required to be uniform.
--
-- ── ORACLE / SQL SERVER COMPARISON ──────────────────────────────
--   Oracle       : DBMS_SCHEDULER chains (CREATE_CHAIN, chain
--                  rules with AND/OR conditions between steps) —
--                  conceptually the closest analog, configured via
--                  a series of separate procedure calls rather
--                  than declarative CREATE TASK statements.
--   SQL Server   : SQL Server Agent job steps with configured
--                  on-success/on-failure branching, or a full SSIS
--                  Control Flow with precedence constraints — the
--                  latter is the closer analog for parallel
--                  branches and join points, but again a separate
--                  product from the base scheduler.
--   Snowflake    : The entire DAG is defined as plain SQL DDL
--                  (CREATE TASK ... AFTER ...) with no separate
--                  chain/package object to design visually first —
--                  though Snowsight's task graph view gives you the
--                  visual afterward.
-- ──────────────────────────────────────────────────────────────
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════
-- A simple log table the root task writes to on every run — this
-- is what proves the root task actually fired each schedule.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.DAG_RUN_LOG (
    run_started_at    TIMESTAMP_NTZ,
    run_completed_at  TIMESTAMP_NTZ,
    status_rows       NUMBER,
    daily_counts_rows NUMBER
);

CREATE OR REPLACE TABLE ECOMMERCE.RAW.PENDING_ORDER_ALERTS (
    alerted_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    pending_count NUMBER,
    note          VARCHAR
);

-- Placeholder so FINAL_REPORT_TASK's body (which reads this table
-- via a subquery) has something valid to reference. Task bodies
-- themselves are more lenient than WHEN clauses, but this keeps
-- the table available from the start regardless. The real
-- CHILD_ORDER_STATUS_SUMMARY_TASK overwrites it with real data on
-- its first run via CREATE OR REPLACE.
CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDER_STATUS_SUMMARY (
    order_status VARCHAR,
    order_count NUMBER
);

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create the ROOT task
-- ══════════════════════════════════════════════════════════════
-- The only task in this DAG with its own SCHEDULE.

CREATE OR REPLACE TASK ECOMMERCE.RAW.DAG_ROOT_TASK
    WAREHOUSE = WORKBOOK_WH
    SCHEDULE = '2 MINUTE'
    COMMENT = 'Goal 6.4 — DAG root: marks the start of each pipeline run'
AS
    INSERT INTO ECOMMERCE.RAW.DAG_RUN_LOG (run_started_at)
    VALUES (CURRENT_TIMESTAMP());

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create two child tasks that run in PARALLEL off the root
-- ══════════════════════════════════════════════════════════════
-- Neither has its own SCHEDULE — both use AFTER DAG_ROOT_TASK, so
-- both fire as soon as the root succeeds, independently of each
-- other.

CREATE OR REPLACE TASK ECOMMERCE.RAW.CHILD_ORDER_STATUS_SUMMARY_TASK
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6.4 — recomputes order counts by status'
    AFTER ECOMMERCE.RAW.DAG_ROOT_TASK
AS
    CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDER_STATUS_SUMMARY AS
    SELECT order_status, COUNT(*) AS order_count
    FROM ECOMMERCE.RAW.ORDERS
    GROUP BY order_status;

CREATE OR REPLACE TASK ECOMMERCE.RAW.CHILD_DAILY_ORDER_COUNTS_TASK
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6.4 — recomputes order counts by day'
    AFTER ECOMMERCE.RAW.DAG_ROOT_TASK
AS
    CREATE OR REPLACE TABLE ECOMMERCE.RAW.DAILY_ORDER_COUNTS AS
    SELECT DATE(created_at) AS order_date, COUNT(*) AS order_count
    FROM ECOMMERCE.RAW.ORDERS
    GROUP BY DATE(created_at);

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Create a JOIN-POINT task — waits for BOTH children
-- ══════════════════════════════════════════════════════════════
-- Lists both parallel tasks in AFTER — this task will not fire
-- until BOTH have succeeded in the same run.

CREATE OR REPLACE TASK ECOMMERCE.RAW.FINAL_REPORT_TASK
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6.4 — join point, only fires once both summaries are ready'
    AFTER ECOMMERCE.RAW.CHILD_ORDER_STATUS_SUMMARY_TASK, ECOMMERCE.RAW.CHILD_DAILY_ORDER_COUNTS_TASK
AS
    INSERT INTO ECOMMERCE.RAW.DAG_RUN_LOG (run_completed_at, status_rows, daily_counts_rows)
    SELECT
        CURRENT_TIMESTAMP(),
        (SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDER_STATUS_SUMMARY),
        (SELECT COUNT(*) FROM ECOMMERCE.RAW.DAILY_ORDER_COUNTS);

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Create a CONDITIONAL BRANCH task
-- ══════════════════════════════════════════════════════════════
-- NOTE: If the DAG is already active (root resumed), Snowflake
-- will refuse to CREATE OR REPLACE any task inside it — confirmed
-- live: "Unable to update graph with root task ... since that root
-- task is not suspended." Suspend the root first, make your
-- changes, then re-run SYSTEM$TASK_DEPENDENTS_ENABLE (Step 5) to
-- bring the whole tree back up. This applies to ANY change to ANY
-- task in an active graph, not just this one — expect to repeat
-- this suspend/edit/re-enable cycle any time you iterate on a DAG.
--
-- ALTER TASK ECOMMERCE.RAW.DAG_ROOT_TASK SUSPEND;
--
-- This branch fires only if ORDERS_STREAM (from sub-task 6.2) has
-- unconsumed changes since its last consumption — reusing
-- SYSTEM$STREAM_HAS_DATA from 6.3 rather than a computed business
-- value, which needs stored procedures (6.5) to do properly.

CREATE OR REPLACE TASK ECOMMERCE.RAW.PENDING_ORDER_ALERT_TASK
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6.4 — conditional branch: only fires if ORDERS_STREAM has unconsumed changes'
    AFTER ECOMMERCE.RAW.CHILD_ORDER_STATUS_SUMMARY_TASK
    WHEN SYSTEM$STREAM_HAS_DATA('ECOMMERCE.RAW.ORDERS_STREAM')
AS
    INSERT INTO ECOMMERCE.RAW.PENDING_ORDER_ALERTS (pending_count, note)
    SELECT
        (SELECT order_count FROM ECOMMERCE.RAW.ORDER_STATUS_SUMMARY WHERE order_status = 'pending'),
        'order changes detected since last stream consumption';

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Activate the entire DAG in one call
-- ══════════════════════════════════════════════════════════════
-- Resuming five tasks individually, in the wrong order, is a
-- common mistake — this single call resumes the root and every
-- dependent task recursively, in the correct order.

SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ECOMMERCE.RAW.DAG_ROOT_TASK');

SHOW TASKS;
-- Every task in this DAG should now show STATE = 'started'

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Wait for a run, then inspect the whole graph
-- ══════════════════════════════════════════════════════════════
-- Wait 3-4 minutes past the schedule before checking.

SELECT
    name,
    state,
    scheduled_time,
    completed_time,
    error_code
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY()
)
WHERE name IN (
    'DAG_ROOT_TASK',
    'CHILD_ORDER_STATUS_SUMMARY_TASK',
    'CHILD_DAILY_ORDER_COUNTS_TASK',
    'FINAL_REPORT_TASK',
    'PENDING_ORDER_ALERT_TASK'
)
ORDER BY scheduled_time DESC, name;

-- Also worth doing: open this DAG's Task Graph view in Snowsight
-- (Catalog [under Horizon Catalog] > Database Explorer > ECOMMERCE
-- > RAW > Tasks > DAG_ROOT_TASK > Graph tab) to see the actual
-- dependency shape rendered visually — confirmed live, this is
-- where it actually lives in the current Snowsight UI.

SELECT * FROM ECOMMERCE.RAW.DAG_RUN_LOG ORDER BY run_started_at DESC;
SELECT * FROM ECOMMERCE.RAW.PENDING_ORDER_ALERTS ORDER BY alerted_at DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Cleanup — suspend the ROOT only
-- ══════════════════════════════════════════════════════════════
-- Suspending the root is sufficient — child tasks never fire on
-- their own schedule, so with the root suspended, nothing in this
-- DAG runs again regardless of the children's own state.

ALTER TASK ECOMMERCE.RAW.DAG_ROOT_TASK SUSPEND;

SHOW TASKS;
-- DAG_ROOT_TASK should show "suspended". Children may still show
-- "started" individually, but that's expected and harmless — they
-- have no schedule of their own and cannot fire without the root.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
-- Your turn:
--   1. Add a THIRD parallel child off DAG_ROOT_TASK that computes
--      a summary of your choice from any Goal 6 table.
--   2. Update FINAL_REPORT_TASK's AFTER clause to require all
--      three children, not two.
--   3. Re-run SYSTEM$TASK_DEPENDENTS_ENABLE and confirm the new
--      child appears correctly in the graph and in TASK_HISTORY().
--   4. Suspend the root before moving to sub-task 6.5.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
-- Q: Why did CREATE OR REPLACE TASK fail with "Unable to update
--    graph with root task ... since that root task is not
--    suspended"?
-- A: Snowflake will not let you modify ANY task inside an active
--    DAG — the root must be suspended first, for every single
--    change, no exceptions. This isn't limited to CREATE OR
--    REPLACE — DROP TASK on a task within an active graph hits the
--    same restriction; that individual task must be suspended
--    first, even with the root already suspended. Suspend, make
--    the change (or drop), then re-run
--    SYSTEM$TASK_DEPENDENTS_ENABLE to reactivate the whole tree.
--    Confirmed live — this applies broadly, not just to one task.
--
-- Q: Why did PENDING_ORDER_ALERT_TASK's WHEN clause fail with
--    "Invalid expression for task condition... only
--    SYSTEM$GET_PREDECESSOR_RETURN_VALUE, SYSTEM$STREAM_HAS_DATA
--    are allowed"?
-- A: A WHEN clause cannot query a table directly, even as a
--    simple scalar subquery — only those two system functions
--    (plus basic type conversions) are permitted, full stop.
--    Confirmed live: an earlier version of this sub-task tried
--    WHEN (SELECT order_count FROM ORDER_STATUS_SUMMARY ...) > 0,
--    which is invalid regardless of whether the table exists —
--    this sub-task's final design uses SYSTEM$STREAM_HAS_DATA
--    instead, which sidesteps the restriction entirely.
--
-- Q: Could I branch on a genuinely computed value instead of just
--    "did the stream have data" — like "only alert if pending
--    orders exceed 100"?
-- A: Yes, via SYSTEM$GET_PREDECESSOR_RETURN_VALUE, but it requires
--    a predecessor task that explicitly calls
--    SYSTEM$SET_RETURN_VALUE(...) — confirmed live that this
--    function's argument must be a literal constant, not a
--    subquery or expression, so resolving a computed count into it
--    requires a Snowflake Scripting block (DECLARE/BEGIN/CALL/END),
--    not a single plain SQL statement. That's covered properly in
--    sub-task 6.5 once stored procedures are introduced.
--
-- Q: What happens if one of the two parallel children fails?
-- A: FINAL_REPORT_TASK will NOT run — AFTER requires ALL listed
--    predecessors to succeed. The other, successful child's work
--    is still committed; only the join-point task is blocked for
--    that run of the graph.
--
-- Q: Can a child task have its own SCHEDULE in addition to AFTER?
-- A: No — a task uses either SCHEDULE or AFTER, never both. A
--    task with AFTER is entirely driven by its predecessor(s).
--
-- Q: Does SYSTEM$TASK_DEPENDENTS_ENABLE need to be re-run every
--    time, or just once?
-- A: Just once, to resume the whole tree. After that, the root's
--    own SCHEDULE keeps the graph running automatically. You'd
--    only re-run it after suspending and wanting to restart, or
--    after adding a new task to the graph that needs enabling.
--
-- Q: How is this different from just chaining logic inside one
--    big stored procedure (covered in 6.5)?
-- A: A DAG gives you independent success/failure tracking per
--    step, visible in TASK_HISTORY() and the graph view, and lets
--    unrelated branches run in parallel on the same or different
--    warehouses. A single stored procedure is one atomic unit as
--    far as scheduling/monitoring is concerned — sub-task 6.5
--    covers when that tradeoff makes more sense.
-- ══════════════════════════════════════════════════════════════
