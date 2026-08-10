-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 6       : Automate Workflows
-- Capstone     : Three-Way Incremental Pipeline Comparison
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~60-75 min
-- Warehouse size    : X-Small (WORKBOOK_WH)
-- Database          : ECOMMERCE.RAW
-- Run in            : Snowsight
-- Prerequisites     : Sub-tasks 6.1-6.7 all complete
-- COF-C03 domain    : Domain 4.0 — Performance Optimization,
--                      Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════
--   This capstone builds the SAME pipeline — keep a mart table in
--   sync with ORDERS — three different ways, side by side:
--     1. Stream + Task + hand-written MERGE (6.3's pattern)
--     2. Stream + Task + stored procedure wrapping the MERGE (6.5's
--        pattern applied to 6.3's problem)
--     3. A Dynamic Table (6.6's pattern) — no stream, no task at all
--
--   Approaches 1 and 2 are wired into a small DAG (6.4) with a
--   shared root that generates test changes, and a failure-
--   watching Alert (6.7) monitors the whole thing. Approach 3
--   refreshes independently, since Dynamic Tables aren't Task
--   objects and can't join a Task DAG.
--
--   Every piece here reuses a pattern already proven working
--   earlier in Goal 6 — this capstone is about INTEGRATION, not
--   new syntax.
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════
-- A dedicated stream for Approach 2, separate from 6.2/6.3's
-- ORDERS_STREAM — confirmed in 6.2's WHAT IF that two streams on
-- the same table track independent offsets and don't interfere,
-- which is exactly what lets Approaches 1 and 2 both see every
-- change without competing over one shared stream's offset.

CREATE OR REPLACE STREAM ECOMMERCE.RAW.ORDERS_STREAM_FOR_PROC
    ON TABLE ECOMMERCE.RAW.ORDERS
    COMMENT = 'Goal 6 Capstone — dedicated stream for Approach 2 (stored procedure)';

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_MART_PROC (
    order_id     NUMBER,
    customer_id  NUMBER,
    order_status VARCHAR,
    created_at   TIMESTAMP_NTZ
);

INSERT INTO ECOMMERCE.RAW.ORDERS_MART_PROC (order_id, customer_id, order_status, created_at)
SELECT order_id, customer_id, order_status, created_at
FROM ECOMMERCE.RAW.ORDERS;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Approach 2 — a stored procedure wrapping the MERGE
-- ══════════════════════════════════════════════════════════════
-- Same MERGE logic proven in 6.3, now wrapped in a procedure per
-- 6.5's pattern — demonstrates the two techniques (raw MERGE vs
-- procedure-wrapped MERGE) side by side against the SAME source.

CREATE OR REPLACE PROCEDURE ECOMMERCE.RAW.SYNC_ORDERS_MART_PROC()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    MERGE INTO ECOMMERCE.RAW.ORDERS_MART_PROC tgt
    USING ECOMMERCE.RAW.ORDERS_STREAM_FOR_PROC src
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

    RETURN 'sync complete';
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Build the DAG — root generates changes, two children
-- run Approaches 1 and 2 in parallel, a final task compares them
-- ══════════════════════════════════════════════════════════════
-- Redefines 6.3's SYNC_ORDERS_MART_TASK to join this DAG (AFTER
-- instead of its own SCHEDULE) — safe to redefine since it should
-- currently be suspended and standalone from 6.3's own cleanup.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.CAPSTONE_COMPARISON_LOG (
    compared_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    merge_row_count     NUMBER,
    proc_row_count      NUMBER,
    dynamic_table_count NUMBER
);

CREATE OR REPLACE TASK ECOMMERCE.RAW.CAPSTONE_ROOT_TASK
    WAREHOUSE = WORKBOOK_WH
    SCHEDULE = '2 MINUTE'
    COMMENT = 'Goal 6 Capstone — DAG root, marks the start of each comparison run'
AS
    INSERT INTO ECOMMERCE.RAW.DAG_RUN_LOG (run_started_at)
    VALUES (CURRENT_TIMESTAMP());

CREATE OR REPLACE TASK ECOMMERCE.RAW.SYNC_ORDERS_MART_TASK
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6 Capstone — Approach 1: raw MERGE (originally built in 6.3)'
    AFTER ECOMMERCE.RAW.CAPSTONE_ROOT_TASK
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

CREATE OR REPLACE TASK ECOMMERCE.RAW.SYNC_ORDERS_MART_PROC_TASK
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6 Capstone — Approach 2: stored procedure wrapping the same MERGE'
    AFTER ECOMMERCE.RAW.CAPSTONE_ROOT_TASK
    WHEN SYSTEM$STREAM_HAS_DATA('ECOMMERCE.RAW.ORDERS_STREAM_FOR_PROC')
AS
    CALL ECOMMERCE.RAW.SYNC_ORDERS_MART_PROC();

CREATE OR REPLACE TASK ECOMMERCE.RAW.CAPSTONE_COMPARISON_TASK
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6 Capstone — join point, logs row counts across all three approaches'
    AFTER ECOMMERCE.RAW.SYNC_ORDERS_MART_TASK, ECOMMERCE.RAW.SYNC_ORDERS_MART_PROC_TASK
AS
    INSERT INTO ECOMMERCE.RAW.CAPSTONE_COMPARISON_LOG (merge_row_count, proc_row_count, dynamic_table_count)
    SELECT
        (SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS_MART),
        (SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS_MART_PROC),
        (SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS_MART_DT);

-- ══════════════════════════════════════════════════════════════
-- STEP 3: A failure-watching Alert across the whole capstone DAG
-- ══════════════════════════════════════════════════════════════
-- Reuses ALERT_LOG from 6.7. Watches TASK_HISTORY() for any FAILED
-- run among this capstone's tasks in the last check window.

CREATE OR REPLACE ALERT ECOMMERCE.RAW.CAPSTONE_PIPELINE_FAILURE_ALERT
    WAREHOUSE = WORKBOOK_WH
    SCHEDULE = '3 MINUTE'
    IF (EXISTS (
        SELECT 1
        FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
            SCHEDULED_TIME_RANGE_START => DATEADD('minute', -3, CURRENT_TIMESTAMP())
        ))
        WHERE name IN (
            'CAPSTONE_ROOT_TASK',
            'SYNC_ORDERS_MART_TASK',
            'SYNC_ORDERS_MART_PROC_TASK',
            'CAPSTONE_COMPARISON_TASK'
        )
        AND state = 'FAILED'
    ))
    THEN
        INSERT INTO ECOMMERCE.RAW.ALERT_LOG (alert_name, fired_at, note)
        VALUES ('CAPSTONE_PIPELINE_FAILURE_ALERT', CURRENT_TIMESTAMP(), 'One or more capstone pipeline tasks failed in the last check window');

-- Uses the EXECUTE ALERT grant to SYSADMIN already made in 6.7 —
-- if running this capstone in a fresh account without that grant,
-- see 6.7 Step 2 for the ACCOUNTADMIN grant needed first.
ALTER ALERT ECOMMERCE.RAW.CAPSTONE_PIPELINE_FAILURE_ALERT RESUME;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Activate the DAG
-- ══════════════════════════════════════════════════════════════
-- Uses the EXECUTE TASK grant to SYSADMIN already made in 6.1.

SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ECOMMERCE.RAW.CAPSTONE_ROOT_TASK');

SHOW TASKS;
-- All four capstone tasks should show STATE = 'started'

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Generate a mix of changes and let the DAG process them
-- ══════════════════════════════════════════════════════════════
-- Highlight from BEGIN through COMMIT and run together

-- Used to replace <existing_order_id_to_update> below
SELECT * FROM ECOMMERCE.RAW.ORDERS
WHERE order_status = 'placed'
LIMIT 1;

BEGIN;

INSERT INTO ECOMMERCE.RAW.ORDERS (order_id, customer_id, order_status, created_at)
VALUES (900000010, 1, 'pending', CURRENT_TIMESTAMP());

-- Swap in a real, currently 'placed' order_id from your data
UPDATE ECOMMERCE.RAW.ORDERS
SET order_status = 'shipped'
WHERE order_id = <existing_order_id_to_update>;

COMMIT;

-- Wait 3-4 minutes past the next scheduled cycle before continuing.

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Compare all three approaches
-- ══════════════════════════════════════════════════════════════
-- ORDERS_MART_DT was suspended at the end of 6.6, and its
-- TARGET_LAG was switched to DOWNSTREAM during 6.6's chaining demo
-- (Step 5 there) — meaning it only refreshes to satisfy a
-- downstream consumer, which is also suspended. Left as-is, its
-- count will look "wrong" simply from being stale, not from any
-- real bug. Confirmed live: resuming it alone wasn't enough while
-- still in DOWNSTREAM mode — switch it back to a fixed lag first.

ALTER DYNAMIC TABLE ECOMMERCE.RAW.ORDERS_MART_DT SET TARGET_LAG = '1 minute';
ALTER DYNAMIC TABLE ECOMMERCE.RAW.ORDERS_MART_DT RESUME;

-- Wait past the 1-minute lag before comparing.

SELECT * FROM ECOMMERCE.RAW.CAPSTONE_COMPARISON_LOG ORDER BY compared_at DESC;
-- All three row counts should match if every approach correctly
-- processed the same underlying changes. If CAPSTONE_COMPARISON_TASK
-- hasn't fired since ORDERS_MART_DT caught up (it only fires when
-- the OTHER two tasks have new stream data to process), log a
-- fresh comparison row manually:

INSERT INTO ECOMMERCE.RAW.CAPSTONE_COMPARISON_LOG (merge_row_count, proc_row_count, dynamic_table_count)
SELECT
    (SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS_MART),
    (SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS_MART_PROC),
    (SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS_MART_DT);

SELECT * FROM ECOMMERCE.RAW.CAPSTONE_COMPARISON_LOG ORDER BY compared_at DESC;

SELECT
    name, state, scheduled_time, completed_time, error_code
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN (
    'CAPSTONE_ROOT_TASK',
    'SYNC_ORDERS_MART_TASK',
    'SYNC_ORDERS_MART_PROC_TASK',
    'CAPSTONE_COMPARISON_TASK'
)
AND scheduled_time >= DATEADD('minute', -10, CURRENT_TIMESTAMP())
ORDER BY scheduled_time DESC, name;

SELECT
    name, state, refresh_start_time, refresh_end_time, refresh_action
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
    NAME => 'ECOMMERCE.RAW.ORDERS_MART_DT'
))
ORDER BY refresh_start_time DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Cleanup
-- ══════════════════════════════════════════════════════════════
-- Suspend the DAG root (sufficient — children don't fire on their
-- own) and the alert. Dynamic Tables were already suspended at the
-- end of 6.6; leave them that way unless still actively comparing.

ALTER TASK ECOMMERCE.RAW.CAPSTONE_ROOT_TASK SUSPEND;
ALTER ALERT ECOMMERCE.RAW.CAPSTONE_PIPELINE_FAILURE_ALERT SUSPEND;

SHOW TASKS LIKE 'CAPSTONE%';
SHOW ALERTS LIKE 'CAPSTONE%';

-- ══════════════════════════════════════════════════════════════
-- COMPARISON — approach tradeoffs observed in this capstone
-- ══════════════════════════════════════════════════════════════
--   Approach 1 (raw MERGE via Task+Stream):
--     + Least code, fully visible in one place
--     - Any additional logic (validation, branching) means the
--       MERGE statement itself grows more complex
--
--   Approach 2 (stored procedure wrapping the same MERGE):
--     + Same MERGE, but now reusable/callable independently, and
--       has room to grow (error handling, multi-step logic per 6.5)
--     - One more object to maintain; a thin wrapper adds no value
--       until you actually need what a procedure offers over raw SQL
--
--   Approach 3 (Dynamic Table):
--     + Zero orchestration code at all — no Stream, no Task, no
--       MERGE, just a query and a freshness target
--     - Read-only, no custom conflict-resolution logic, and (per
--       6.6) never gets automatic query rewrite the way some other
--       materialized-result features do
--
--   For a straightforward "keep this in sync" need with no extra
--   logic: Dynamic Table. For anything needing custom logic beyond
--   a plain MERGE, error handling, or multi-step processing:
--   Stream+Task+procedure. Raw MERGE sits in between — simple
--   enough not to need a procedure yet, but still fully manual.
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
-- Q: Why does Approach 2 need its OWN stream instead of sharing
--    ORDERS_STREAM with Approach 1?
-- A: Confirmed back in 6.2: when two separate consumers try to
--    read from the SAME stream, only one succeeds in advancing the
--    offset per changeset — the other sees nothing. Two independent
--    streams on the same source table track independent offsets
--    and never compete, which is what lets both approaches see
--    every change independently for a fair comparison.
--
-- Q: Why isn't the Dynamic Table (Approach 3) part of the Task DAG?
-- A: A Dynamic Table is a different object type entirely, with its
--    own independent refresh scheduling (TARGET_LAG) — it cannot
--    be a node in a Task's AFTER chain. This is a real architectural
--    boundary, not a workbook simplification.
--
-- Q: Why did the Dynamic Table's row count not match the other two
--    even after resuming it and waiting several minutes?
-- A: Confirmed live: resuming alone wasn't enough. It was left in
--    TARGET_LAG = DOWNSTREAM mode from 6.6's chaining demo, which
--    means it only refreshes to satisfy a downstream consumer —
--    and that consumer (ORDER_STATUS_SUMMARY_DT) was ALSO still
--    suspended, so nothing was actually demanding freshness from
--    it. Switching back to a fixed TARGET_LAG resolved it. A
--    persistently stale Dynamic Table in DOWNSTREAM mode is easy
--    to mistake for a real bug when it's really just an orphaned
--    freshness contract with no active consumer.
--
-- Q: If row counts don't match across all three approaches, what
--    does that actually tell you?
-- A: Given enough time past each approach's own refresh/schedule
--    window, they should converge to the same count since all
--    three read the same ORDERS changes. A persistent mismatch
--    points to a bug in one approach's logic (check TASK_HISTORY()
--    error_message or DYNAMIC_TABLE_REFRESH_HISTORY() state_message
--    for whichever approach is behind).
-- ══════════════════════════════════════════════════════════════
