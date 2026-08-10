-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 6       : Automate Workflows
-- Sub-task 6.1 : Schedule Work with Tasks
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30-40 min
-- Warehouse size    : X-Small (WORKBOOK_WH)
-- Database          : ECOMMERCE.RAW
-- Run in            : Snowsight
-- Prerequisites     : Goals 1-5 complete
-- COF-C03 domain    : Domain 4.0 — Performance Optimization,
--                      Querying, and Transformation (21%)
--   Tasks/Streams/stored procedures/Dynamic Tables are automation
--   and transformation logic, not data loading/connectivity — same
--   domain as Goals 3 and 5. Matches the reconciled five-domain
--   COF-C03 blueprint applied across Goals 1-5.
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════
--   A Task is Snowflake's native scheduler: a wrapper around a
--   single SQL statement (or a call to a stored procedure) that
--   runs on a schedule you define, with no external scheduler,
--   cron daemon, or orchestration tool required.
--
--   In this sub-task you will create a task that periodically
--   logs a snapshot of order volume into a small monitoring
--   table, resume it, watch it fire, inspect its run history,
--   and then suspend it again. This is deliberately simple —
--   the goal here is understanding scheduling mechanics. Real
--   incremental pipeline logic (the reason Tasks matter) comes
--   in sub-task 6.3 once Streams are introduced.
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- CONCEPT
-- ══════════════════════════════════════════════════════════════
--   A Task wraps one SQL statement and a schedule. Snowflake
--   manages the execution — you never see a scheduler process.
--
--   Two scheduling styles:
--     · CRON syntax           -- e.g. 'USING CRON 0 * * * * UTC'
--     · Fixed interval        -- e.g. '1 MINUTE'
--
--   A task is created SUSPENDED by default. It will not run,
--   consume no credits, and show up as inactive until you
--   explicitly issue ALTER TASK ... RESUME.
--
--   Two compute models:
--     · Warehouse-assigned    -- runs on a warehouse you name,
--                                 predictable cost, can queue
--                                 behind other warehouse work
--     · Serverless             -- Snowflake manages compute size
--                                 automatically via
--                                 USER_TASK_MANAGED_INITIAL_SIZE,
--                                 bills separately from any
--                                 warehouse
--
-- ── ORACLE / SQL SERVER COMPARISON ──────────────────────────────
--   Oracle       : DBMS_SCHEDULER jobs (CREATE_JOB, ENABLE/DISABLE)
--   SQL Server   : SQL Server Agent jobs, with its own job history
--                  tables and a persistent agent service
--   Snowflake    : No persistent agent process exists anywhere —
--                  the "scheduler" is a cloud-managed control
--                  plane function. There is nothing to install,
--                  patch, or keep running. The tradeoff: no
--                  local debugging step-through — you diagnose
--                  entirely through TASK_HISTORY() after the
--                  fact, not by attaching to a running job.
-- ──────────────────────────────────────────────────────────────
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════
-- A small logging table for the task to write into. This is the
-- "side effect" the task will produce on each run.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.TASK_LOG (
    log_id        NUMBER AUTOINCREMENT,
    logged_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    order_count   NUMBER,
    note          VARCHAR
);

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create a task on a fixed interval (created SUSPENDED)
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TASK ECOMMERCE.RAW.LOG_ORDER_COUNT_TASK
    WAREHOUSE = WORKBOOK_WH
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Goal 6.1 — logs current ORDERS row count every minute'
AS
    INSERT INTO ECOMMERCE.RAW.TASK_LOG (order_count, note)
    SELECT COUNT(*), 'scheduled run'
    FROM ECOMMERCE.RAW.ORDERS;

-- Confirm it exists and is suspended by default
SHOW TASKS LIKE 'LOG_ORDER_COUNT_TASK';
-- STATE column should read "suspended" — no runs have happened yet

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Grant EXECUTE TASK, then resume the task
-- ══════════════════════════════════════════════════════════════
-- A task does nothing until explicitly resumed — and resuming
-- requires the EXECUTE TASK privilege, which is NOT granted to
-- SYSADMIN by default even though SYSADMIN owns the task. This
-- grant itself requires ACCOUNTADMIN.
--
-- Confirmed live (error 091089: "EXECUTE TASK privilege must be
-- granted to owner role") — same "docs say one role, account
-- actually requires ACCOUNTADMIN" pattern seen repeatedly in
-- Goals 4-5 (masking, row access, tags, network policies,
-- resource monitors).

USE ROLE ACCOUNTADMIN;

GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;

USE ROLE SYSADMIN;

ALTER TASK ECOMMERCE.RAW.LOG_ORDER_COUNT_TASK RESUME;

SHOW TASKS LIKE 'LOG_ORDER_COUNT_TASK';
-- STATE should now read "started"

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Wait for it to fire, then check the log table directly
-- ══════════════════════════════════════════════════════════════
-- Wait 2-3 minutes (the schedule is 1 minute) before running this.

SELECT *
FROM ECOMMERCE.RAW.TASK_LOG
ORDER BY logged_at DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Inspect execution history with TASK_HISTORY()
-- ══════════════════════════════════════════════════════════════
-- TASK_HISTORY() is a table function — it needs no ACCOUNT_USAGE
-- latency wait, unlike the ACCOUNT_USAGE views from Goal 5.

SELECT
    name,
    state,
    scheduled_time,
    completed_time,
    error_code,
    error_message
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'LOG_ORDER_COUNT_TASK'
    )
)
ORDER BY scheduled_time DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Alter the task's schedule
-- ══════════════════════════════════════════════════════════════
-- Tasks can be altered while suspended. Snowflake requires you
-- suspend before altering most properties — attempting to ALTER
-- a running task's SCHEDULE will fail.

ALTER TASK ECOMMERCE.RAW.LOG_ORDER_COUNT_TASK SUSPEND;

ALTER TASK ECOMMERCE.RAW.LOG_ORDER_COUNT_TASK
    SET SCHEDULE = 'USING CRON */5 * * * * UTC';
-- Now fires every 5 minutes instead of every 1 minute

ALTER TASK ECOMMERCE.RAW.LOG_ORDER_COUNT_TASK RESUME;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Create a serverless variant for comparison
-- ══════════════════════════════════════════════════════════════
-- No WAREHOUSE clause — Snowflake sizes and bills compute for
-- this task independently of WORKBOOK_WH.

CREATE OR REPLACE TASK ECOMMERCE.RAW.LOG_ORDER_COUNT_SERVERLESS_TASK
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = '5 MINUTE'
    COMMENT = 'Goal 6.1 — serverless variant, no WAREHOUSE clause'
AS
    INSERT INTO ECOMMERCE.RAW.TASK_LOG (order_count, note)
    SELECT COUNT(*), 'serverless run'
    FROM ECOMMERCE.RAW.ORDERS;

SHOW TASKS LIKE 'LOG_ORDER_COUNT_SERVERLESS_TASK';
-- Note there is no WAREHOUSE column value for a serverless task

-- Leave the serverless task suspended — do not resume it. Its
-- purpose here is purely to show the SHOW TASKS output difference.

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Cleanup — suspend before moving on
-- ══════════════════════════════════════════════════════════════
-- Per workbook convention: any object with real ongoing background
-- credit cost gets suspended/dropped as soon as its teaching
-- purpose is served, not left running into the next sub-task.

ALTER TASK ECOMMERCE.RAW.LOG_ORDER_COUNT_TASK SUSPEND;

SHOW TASKS LIKE 'LOG_ORDER_COUNT%';
-- Both tasks should show STATE = "suspended" before you continue

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
-- Your turn:
--   1. Create a task that logs a row count from RETURNS instead
--      of ORDERS, on a 2-minute interval.
--   2. Resume it, wait for two runs, confirm both appear in
--      TASK_HISTORY() with STATE = 'SUCCEEDED'.
--   3. Alter its schedule to CRON '0 */1 * * * UTC' (top of every
--      hour) without dropping and recreating the task.
--   4. Suspend it before moving to sub-task 6.2.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
-- Q: What happens if the SQL inside a task fails?
-- A: The task run is marked FAILED in TASK_HISTORY() with an
--    error_message populated. The task itself is NOT automatically
--    suspended — it will attempt its next scheduled run normally.
--    (Automatic suspension after repeated failures is configurable
--    via SUSPEND_TASK_AFTER_NUM_FAILURES, covered in sub-task 6.7.)
--
-- Q: Can I run a task manually, outside its schedule?
-- A: Yes — EXECUTE TASK <task_name> triggers an immediate run
--    regardless of the schedule. Useful for testing without
--    waiting for the next scheduled interval.
--
-- Q: Does suspending a task lose its definition?
-- A: No. SUSPEND only stops future scheduled runs. The task
--    definition, warehouse assignment, and schedule are all
--    preserved — RESUME picks up on the same schedule.
--
-- Q: Why did ALTER TASK ... SET SCHEDULE fail with an error?
-- A: Most task property changes require the task to be suspended
--    first. If you see this error, run ALTER TASK ... SUSPEND,
--    make your change, then RESUME.
--
-- Q: Why did RESUME fail with error 091089?
-- A: EXECUTE TASK is not implicitly granted to SYSADMIN, even as
--    task owner. Grant it explicitly: GRANT EXECUTE TASK ON
--    ACCOUNT TO ROLE SYSADMIN — that grant itself requires
--    ACCOUNTADMIN. Confirmed live in this sub-task.
-- ══════════════════════════════════════════════════════════════
