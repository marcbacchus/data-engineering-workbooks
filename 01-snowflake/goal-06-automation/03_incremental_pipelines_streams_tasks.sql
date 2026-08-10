-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 6       : Automate Workflows
-- Sub-task 6.3 : Build Incremental Pipelines with Streams + Tasks
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~40-50 min
-- Warehouse size    : X-Small (WORKBOOK_WH)
-- Database          : ECOMMERCE.RAW
-- Run in            : Snowsight
-- Prerequisites     : Sub-tasks 6.1 and 6.2 complete — this reuses
--                      ORDERS_STREAM created in 6.2, and requires
--                      the EXECUTE TASK grant to SYSADMIN made in 6.1
-- COF-C03 domain    : Domain 4.0 — Performance Optimization,
--                      Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════
--   6.1 taught you how to schedule work. 6.2 taught you how to
--   detect exactly what changed. This sub-task combines them into
--   the pattern that actually matters: a Task that wakes up on a
--   schedule, checks whether its Stream has anything pending, and
--   if so, applies those changes downstream — automatically,
--   incrementally, without ever reprocessing rows it already saw.
--
--   You will build a real downstream table (ORDERS_MART) that
--   mirrors ORDERS, kept in sync entirely by a scheduled Task
--   consuming ORDERS_STREAM via a single idempotent MERGE.
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- CONCEPT
-- ══════════════════════════════════════════════════════════════
--   The Stream+Task pattern:
--     1. A Task runs on a schedule.
--     2. Its WHEN clause calls SYSTEM$STREAM_HAS_DATA('<stream>')
--        — if there's nothing pending, the task's SQL body never
--        even executes, so you pay no compute for empty checks
--        beyond the trivial WHEN evaluation itself.
--     3. If there IS pending data, the task body runs a MERGE
--        that reads directly from the stream and applies inserts,
--        updates, and deletes to the target in one atomic
--        statement — and that same MERGE, by reading from the
--        stream, is what advances the stream's offset.
--
--   Why MERGE specifically, and why this is idempotent:
--     A MERGE statement is atomic — it either fully commits or
--     fully rolls back. If the task's warehouse dies mid-MERGE,
--     the stream's offset does NOT advance (the read that would
--     advance it is part of the same transaction that failed), so
--     the next scheduled run sees the exact same pending rows and
--     tries again. Nothing is silently dropped, and nothing is
--     double-applied — that's what "idempotent" means here: running
--     the same MERGE against the same unconsumed stream contents
--     twice in a row produces the same end state as running it once.
--
--   Correctly consuming a STANDARD stream in a MERGE requires
--   handling three cases explicitly:
--     · METADATA$ACTION = 'INSERT'                  -> upsert
--     · METADATA$ACTION = 'DELETE' AND ISUPDATE=TRUE -> ignore
--       (this is just the "old half" of an update pair — the
--       matching INSERT row already carries the new values)
--     · METADATA$ACTION = 'DELETE' AND ISUPDATE=FALSE -> delete
--       (this is a genuine delete, not half of an update)
--
-- ── ORACLE / SQL SERVER COMPARISON ──────────────────────────────
--   Oracle       : GoldenGate's Replicat process applies captured
--                  changes to a target — conceptually similar, but
--                  Replicat is a separate running process you
--                  configure and monitor independently, not a
--                  scheduled SQL statement.
--   SQL Server   : An SSIS incremental-load package, typically
--                  polling a CDC table on a SQL Agent job schedule
--                  and applying a T-SQL MERGE — structurally the
--                  closest analog to this exact pattern, but it's
--                  two separate products (SQL Agent + SSIS) wired
--                  together rather than one native mechanism.
--   Snowflake    : Stream + Task + MERGE is entirely native SQL —
--                  no external orchestration tool, no separate
--                  polling process. The tradeoff: less flexible
--                  than a full ETL tool for complex branching
--                  logic, though stored procedures (sub-task 6.5)
--                  close most of that gap.
-- ──────────────────────────────────────────────────────────────
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════
-- The downstream target this pipeline keeps in sync. Seed it with
-- a snapshot of ORDERS as it stands right now, BEFORE the stream
-- picks up any further changes.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_MART (
    order_id     NUMBER PRIMARY KEY,
    customer_id  NUMBER,
    order_status VARCHAR,
    created_at   TIMESTAMP_NTZ
);

INSERT INTO ECOMMERCE.RAW.ORDERS_MART (order_id, customer_id, order_status, created_at)
SELECT order_id, customer_id, order_status, created_at
FROM ECOMMERCE.RAW.ORDERS;

SELECT COUNT(*) AS mart_row_count FROM ECOMMERCE.RAW.ORDERS_MART;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Confirm ORDERS_STREAM is empty before we start
-- ══════════════════════════════════════════════════════════════
-- This reuses the stream created in sub-task 6.2 — it should be
-- empty right now since 6.2 fully consumed it in its Step 5.

SELECT * FROM ECOMMERCE.RAW.ORDERS_STREAM;
-- If this returns rows, consume them manually first (see 6.2
-- Step 5) so this sub-task starts from a clean, known state.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create the Task with a WHEN clause guard
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TASK ECOMMERCE.RAW.SYNC_ORDERS_MART_TASK
    WAREHOUSE = WORKBOOK_WH
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Goal 6.3 — incremental Stream+Task sync into ORDERS_MART'
    WHEN SYSTEM$STREAM_HAS_DATA('ECOMMERCE.RAW.ORDERS_STREAM')
AS
    MERGE INTO ECOMMERCE.RAW.ORDERS_MART tgt
    USING ECOMMERCE.RAW.ORDERS_STREAM src
        ON tgt.order_id = src.order_id
    WHEN MATCHED AND src.metadata$action = 'DELETE' AND src.metadata$isupdate = FALSE THEN
        DELETE
    WHEN MATCHED AND src.metadata$action = 'INSERT' THEN
        UPDATE SET
            tgt.customer_id  = src.customer_id,
            tgt.order_status = src.order_status,
            tgt.created_at   = src.created_at
    WHEN NOT MATCHED AND src.metadata$action = 'INSERT' THEN
        INSERT (order_id, customer_id, order_status, created_at)
        VALUES (src.order_id, src.customer_id, src.order_status, src.created_at);

-- Task is created SUSPENDED. The EXECUTE TASK grant to SYSADMIN
-- from sub-task 6.1 is what allows the RESUME below to succeed —
-- if you skipped 6.1 or ran it as a fresh role, RESUME will fail
-- with error 091089 again.

ALTER TASK ECOMMERCE.RAW.SYNC_ORDERS_MART_TASK RESUME;

SHOW TASKS LIKE 'SYNC_ORDERS_MART_TASK';

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Generate changes — a fresh insert, an update to an
-- EXISTING row, and a genuine delete, each on a DIFFERENT order_id
-- ══════════════════════════════════════════════════════════════
-- Using three separate order_ids avoids the "insert and update the
-- same row in the same window collapses to one net INSERT" behavior
-- from sub-task 6.2 — each change here needs to be independently
-- visible for this test to prove anything.

-- Capture two existing order_ids first: one to update, one to delete
SELECT * FROM ECOMMERCE.RAW.ORDERS
WHERE order_status = 'placed'
LIMIT 2;

-- Highlight from BEGIN through COMMIT and run together
BEGIN;

-- A genuinely new row
INSERT INTO ECOMMERCE.RAW.ORDERS (order_id, customer_id, order_status, created_at)
VALUES (900000003, 1, 'pending', CURRENT_TIMESTAMP());

-- An update to a pre-existing row (use an order_id captured above)
UPDATE ECOMMERCE.RAW.ORDERS
SET order_status = 'shipped'
WHERE order_id = <existing_order_id_to_update>;

-- A genuine delete of a different pre-existing row
DELETE FROM ECOMMERCE.RAW.ORDERS
WHERE order_id = <existing_order_id_to_delete>;

COMMIT;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Wait for the scheduled run, then verify
-- ══════════════════════════════════════════════════════════════
-- Wait 1-2 minutes past the schedule before checking.

SELECT
    name,
    state,
    scheduled_time,
    completed_time,
    error_code,
    error_message
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'SYNC_ORDERS_MART_TASK'
    )
)
ORDER BY scheduled_time DESC;

-- Confirm all three changes were applied correctly. This query
-- checks three different outcomes, not one uniform result:
--   · 900000003              -> should be PRESENT, status 'pending'  (new insert)
--   · <existing_order_id_to_update> -> should be PRESENT, status 'shipped' (updated)
--   · <existing_order_id_to_delete> -> should be ABSENT entirely      (deleted)
-- Only seeing 2 of the 3 order_ids in the result is CORRECT, not a
-- bug — it means the delete branch of the MERGE worked as intended.
SELECT * FROM ECOMMERCE.RAW.ORDERS_MART
WHERE order_id IN (900000003, <existing_order_id_to_update>, <existing_order_id_to_delete>);
-- Expect: 900000003 present with status 'pending', the updated
-- order_id present with status 'shipped', the deleted order_id
-- ABSENT entirely.

-- Confirm the stream was consumed — this should be empty
SELECT * FROM ECOMMERCE.RAW.ORDERS_STREAM;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Prove the WHEN clause actually skips empty runs
-- ══════════════════════════════════════════════════════════════
-- With the stream now empty, wait through 2-3 more scheduled
-- intervals WITHOUT making any changes to ORDERS.

SELECT
    name,
    state,
    scheduled_time,
    completed_time
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'SYNC_ORDERS_MART_TASK'
    )
)
ORDER BY scheduled_time DESC
LIMIT 5;

-- You should see these runs as STATE = 'SKIPPED', not 'SUCCEEDED'
-- — the WHEN clause prevented the MERGE body from executing at all
-- because SYSTEM$STREAM_HAS_DATA returned FALSE.

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Cleanup — suspend the task
-- ══════════════════════════════════════════════════════════════
-- Per workbook convention: suspend immediately once the teaching
-- purpose is served, rather than leaving a live schedule running
-- into the next sub-task.

ALTER TASK ECOMMERCE.RAW.SYNC_ORDERS_MART_TASK SUSPEND;

SHOW TASKS LIKE 'SYNC_ORDERS_MART_TASK';
-- STATE should read "suspended" before you continue

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
-- Your turn:
--   1. Create a second Task+MERGE pipeline syncing RETURNS into a
--      new RETURNS_MART table, using the RETURNS stream you built
--      in sub-task 6.2's Practice Gap.
--   2. Make one insert, one update, and one delete to RETURNS, on
--      three different return_ids.
--   3. Confirm TASK_HISTORY() shows a SUCCEEDED run with all three
--      changes reflected correctly in RETURNS_MART.
--   4. Let it run once more with no changes pending, and confirm
--      that run shows SKIPPED rather than SUCCEEDED.
--   5. Suspend the task before moving to sub-task 6.4.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
-- Q: What happens if the MERGE fails partway — say, a data type
--    mismatch on one row?
-- A: The entire MERGE rolls back — no rows are applied, and
--    critically, the stream's offset does NOT advance, because
--    the offset-advancing read is part of the same failed
--    transaction. The next scheduled run retries against the
--    exact same pending changes. This is what makes the pattern
--    safe to leave unattended.
--
-- Q: Why did some runs show SKIPPED instead of just not appearing
--    in TASK_HISTORY() at all?
-- A: A WHEN clause evaluating to FALSE still counts as a task run
--    for history purposes — it's recorded so you can confirm the
--    guard is actually working, rather than silently doing nothing
--    with no evidence either way.
--
-- Q: Could I skip the WHEN clause and just always run the MERGE?
-- A: Yes — MERGE against an empty stream is a harmless no-op. The
--    WHEN clause is a cost optimization, not a correctness
--    requirement: it avoids spinning up warehouse compute for a
--    MERGE that would do nothing anyway.
--
-- Q: What if I need the two streams from 6.2 (standard and
--    append-only) to feed two different downstream tables on two
--    different schedules?
-- A: Create two independent Task+MERGE pairs, one per stream, each
--    with its own WHEN SYSTEM$STREAM_HAS_DATA(...) guard pointing
--    at its own stream. They don't interfere with each other.
-- ══════════════════════════════════════════════════════════════
