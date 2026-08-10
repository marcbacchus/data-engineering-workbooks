-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 6       : Automate Workflows
-- Sub-task 6.7 : Handle Pipeline Errors and Observability
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~45-55 min
-- Warehouse size    : X-Small (WORKBOOK_WH)
-- Database          : ECOMMERCE.RAW
-- Run in            : Snowsight
-- Prerequisites     : Sub-tasks 6.1-6.6 complete
-- COF-C03 domain    : Domain 4.0 — Performance Optimization,
--                      Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════
--   Every sub-task so far has quietly built observability without
--   naming it: TASK_HISTORY(), DYNAMIC_TABLE_REFRESH_HISTORY(),
--   error_code/error_message columns. This sub-task formalizes two
--   remaining pieces: what to do with data that FAILS your
--   pipeline's own rules (dead-letter pattern), and how to get
--   PROACTIVELY notified when something needs attention (Alerts),
--   instead of only finding out when you happen to check.
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- CONCEPT
-- ══════════════════════════════════════════════════════════════
--   Dead-letter pattern: instead of a pipeline step failing
--   entirely the moment it hits one bad row, route rows that don't
--   meet your rules to a separate table and let everything else
--   keep flowing. This is a general ELT resilience pattern, not a
--   Snowflake-specific feature — implemented here as plain SQL
--   with a WHERE clause splitting valid from invalid rows.
--
--   An ALERT is a distinct schema-level object from a TASK, though
--   structurally similar (WAREHOUSE, SCHEDULE, created SUSPENDED,
--   needs explicit RESUME). The difference: a Task's body is
--   whatever SQL you want run unconditionally on schedule. An
--   Alert has a required CONDITION (an IF(EXISTS(...)) check) and
--   a required ACTION that ONLY runs if the condition is true —
--   the condition/action split is built into the object itself,
--   not something you construct yourself the way 6.4 built
--   conditional branching by hand with WHEN and SYSTEM$STREAM_HAS_DATA.
--
--   CREATE ALERT syntax:
--     CREATE [OR REPLACE] ALERT <name>
--       WAREHOUSE = <warehouse_name>
--       SCHEDULE = '<num> MINUTE'  -- or USING CRON <expr> <tz>
--       IF (EXISTS (<condition query>))
--       THEN <action statement>;
--
--   ALERT_HISTORY() (an INFORMATION_SCHEMA table function, same
--   family as TASK_HISTORY()) shows whether each scheduled check
--   found its condition true or false.
--
--   Proactive email notification needs a NOTIFICATION INTEGRATION
--   created first (requires ACCOUNTADMIN — global CREATE INTEGRATION
--   privilege) with a verified recipient email address, THEN
--   SYSTEM$SEND_EMAIL can be called as an alert's action. This is
--   shown as an optional step since it requires account-level setup
--   and a real verified email address to actually test end-to-end.
--
-- ── ORACLE / SQL SERVER COMPARISON ──────────────────────────────
--   Oracle       : DBMS_ALERT for the condition/wake-up mechanism,
--                  combined with UTL_MAIL or UTL_SMTP for email —
--                  several separate packages wired together rather
--                  than one object.
--   SQL Server   : SQL Server Agent Alerts (often paired with SQL
--                  Server Agent Jobs) plus Database Mail
--                  (sp_send_dbmail) for the email piece — again a
--                  multi-part configuration across the Agent and
--                  Database Mail subsystems.
--   Snowflake    : One object (ALERT) owns condition, action, and
--                  schedule together. Email specifically needs the
--                  separate NOTIFICATION INTEGRATION setup, but the
--                  condition-checking mechanism itself needs nothing
--                  external to configure.
-- ──────────────────────────────────────────────────────────────
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE ECOMMERCE.RAW.REJECTED_ORDERS (
    order_id         NUMBER,
    customer_id      NUMBER,
    order_status     VARCHAR,
    created_at       TIMESTAMP_NTZ,
    rejection_reason VARCHAR,
    rejected_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ALERT_LOG (
    alert_name VARCHAR,
    fired_at   TIMESTAMP_NTZ,
    note       VARCHAR
);

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Dead-letter pattern — route invalid rows separately
-- ══════════════════════════════════════════════════════════════
-- NOTE: adjust the valid order_status list below to match what
-- actually exists in YOUR ORDERS data — this is illustrative, not
-- verified against your real status values.

-- Highlight from BEGIN through COMMIT and run together
BEGIN;

-- Manufacture one deliberately invalid row to prove the pattern
INSERT INTO ECOMMERCE.RAW.ORDERS (order_id, customer_id, order_status, created_at)
VALUES (900000006, NULL, 'pending', CURRENT_TIMESTAMP());

COMMIT;

INSERT INTO ECOMMERCE.RAW.REJECTED_ORDERS (order_id, customer_id, order_status, created_at, rejection_reason)
SELECT
    order_id,
    customer_id,
    order_status,
    created_at,
    CASE
        WHEN customer_id IS NULL THEN 'missing customer_id'
        WHEN order_status NOT IN ('pending', 'shipped', 'delivered', 'cancelled', 'placed', 'confirmed', 'returned') THEN 'unrecognized order_status'
    END
FROM ECOMMERCE.RAW.ORDERS
WHERE customer_id IS NULL
   OR order_status NOT IN ('pending', 'shipped', 'delivered', 'cancelled', 'placed', 'confirmed', 'returned');

SELECT * FROM ECOMMERCE.RAW.REJECTED_ORDERS ORDER BY rejected_at DESC;
-- The manufactured row (900000006) should appear with reason
-- 'missing customer_id' — everything else in ORDERS is untouched
-- and unaffected by this rejection.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create an Alert that watches for new rejected rows
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE ALERT ECOMMERCE.RAW.REJECTED_ORDERS_ALERT
    WAREHOUSE = WORKBOOK_WH
    SCHEDULE = '2 MINUTE'
    IF (EXISTS (
        SELECT 1 FROM ECOMMERCE.RAW.REJECTED_ORDERS
        WHERE rejected_at > DATEADD('minute', -2, CURRENT_TIMESTAMP())
    ))
    THEN
        INSERT INTO ECOMMERCE.RAW.ALERT_LOG (alert_name, fired_at, note)
        VALUES ('REJECTED_ORDERS_ALERT', CURRENT_TIMESTAMP(), 'New rejected orders detected in the last check window');

SHOW ALERTS LIKE 'REJECTED_ORDERS_ALERT';
-- Alerts are created SUSPENDED by default, same as Tasks.

-- Resuming requires the EXECUTE ALERT privilege, which is NOT
-- granted to SYSADMIN by default even though SYSADMIN owns the
-- alert — same pattern as EXECUTE TASK in 6.1. Confirmed live
-- (error 392000: "EXECUTE ALERT privilege must be granted to
-- owner role"). This grant itself requires ACCOUNTADMIN.

USE ROLE ACCOUNTADMIN;

GRANT EXECUTE ALERT ON ACCOUNT TO ROLE SYSADMIN;

USE ROLE SYSADMIN;

ALTER ALERT ECOMMERCE.RAW.REJECTED_ORDERS_ALERT RESUME;

-- ══════════════════════════════════════════════════════════════
-- STEP 2b: Manufacture a FRESH rejected row before the next check
-- ══════════════════════════════════════════════════════════════
-- Step 1's rejected row will age out of the alert's 2-minute
-- lookback window quickly. Run this right before a scheduled
-- check to actually see CONDITION_TRUE fire, not just
-- CONDITION_FALSE.

BEGIN;

INSERT INTO ECOMMERCE.RAW.ORDERS (order_id, customer_id, order_status, created_at)
VALUES (900000007, NULL, 'pending', CURRENT_TIMESTAMP());

COMMIT;

INSERT INTO ECOMMERCE.RAW.REJECTED_ORDERS (order_id, customer_id, order_status, created_at, rejection_reason)
SELECT order_id, customer_id, order_status, created_at, 'missing customer_id'
FROM ECOMMERCE.RAW.ORDERS
WHERE order_id = 900000007;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Wait for a scheduled check, then inspect the result
-- ══════════════════════════════════════════════════════════════

SELECT
    name,
    state,
    scheduled_time,
    completed_time,
    condition,
    action,
    sql_error_code,
    sql_error_message
FROM TABLE(
    INFORMATION_SCHEMA.ALERT_HISTORY(
        ALERT_NAME => 'REJECTED_ORDERS_ALERT'
    )
)
ORDER BY scheduled_time DESC;
-- STATE reflects the outcome per row — confirmed live values are
-- TRIGGERED (action ran) and CONDITION_FALSE (condition checked,
-- nothing to do). Confirmed columns: NAME, DATABASE_NAME,
-- SCHEMA_NAME, CONDITION, CONDITION_QUERY_ID, ACTION,
-- ACTION_QUERY_ID, STATE, SQL_ERROR_CODE, SQL_ERROR_MESSAGE,
-- SCHEDULED_TIME, COMPLETED_TIME, SCHEDULED_FROM, RUNBOOK,
-- WAS_AUTO_SUSPENDED, CONFIG — no condition_state column exists.

SELECT * FROM ECOMMERCE.RAW.ALERT_LOG ORDER BY fired_at DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 4 (OPTIONAL): Real email notification — full working test
-- ══════════════════════════════════════════════════════════════
-- Requires ACCOUNTADMIN and a verified email address for a real
-- user in your account. Skip this step entirely if you'd rather
-- not set up email — Steps 1-3 already demonstrate the full
-- observability pattern without it. Replace <your_verified_email>
-- and <your_username> below before running.

USE ROLE ACCOUNTADMIN;

-- If you're not sure your email is verified, trigger verification
-- first (sends a confirmation link to that address — must be
-- clicked before SYSTEM$SEND_EMAIL will actually deliver anything):
CALL SYSTEM$START_USER_EMAIL_VERIFICATION('<your_username>');

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS workbook_email_int
    TYPE = EMAIL
    ENABLED = TRUE
    DEFAULT_RECIPIENTS = ('<your_verified_email>')
    DEFAULT_SUBJECT = 'Workbook Alert: Rejected Orders Detected';

GRANT USAGE ON INTEGRATION workbook_email_int TO ROLE SYSADMIN;

USE ROLE SYSADMIN;

ALTER ALERT ECOMMERCE.RAW.REJECTED_ORDERS_ALERT SUSPEND;

ALTER ALERT ECOMMERCE.RAW.REJECTED_ORDERS_ALERT MODIFY ACTION
    CALL SYSTEM$SEND_EMAIL(
        'workbook_email_int',
        '<your_verified_email>',
        'Workbook Alert: Rejected Orders Detected',
        'New rejected orders were found in ECOMMERCE.RAW.REJECTED_ORDERS.'
    );

ALTER ALERT ECOMMERCE.RAW.REJECTED_ORDERS_ALERT RESUME;

-- Manufacture a fresh rejected row so the next scheduled check has
-- something to actually trigger on — same pattern as Step 2b.
BEGIN;

INSERT INTO ECOMMERCE.RAW.ORDERS (order_id, customer_id, order_status, created_at)
VALUES (900000008, NULL, 'pending', CURRENT_TIMESTAMP());

COMMIT;

INSERT INTO ECOMMERCE.RAW.REJECTED_ORDERS (order_id, customer_id, order_status, created_at, rejection_reason)
SELECT order_id, customer_id, order_status, created_at, 'missing customer_id'
FROM ECOMMERCE.RAW.ORDERS
WHERE order_id = 900000008;

-- Wait past the next 2-minute scheduled check, then verify delivery
-- was actually ATTEMPTED — a faster diagnostic than waiting on an
-- inbox, and it will show WHY delivery failed if it did (e.g. an
-- unverified recipient silently fails with no other error anywhere).
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.NOTIFICATION_HISTORY(
        START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
    )
)
ORDER BY created DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Cleanup — suspend the alert
-- ══════════════════════════════════════════════════════════════
-- ⚠️ Real ongoing background credit cost while active, same
-- discipline as Tasks and Dynamic Tables elsewhere in this goal.

ALTER ALERT ECOMMERCE.RAW.REJECTED_ORDERS_ALERT SUSPEND;

SHOW ALERTS LIKE 'REJECTED_ORDERS_ALERT';
-- STATE should read "suspended"

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
-- Your turn:
--   1. Build the same dead-letter pattern for RETURNS — decide
--      what makes a row "invalid" for your own data (missing
--      order_id reference, negative quantity, whatever fits).
--   2. Create an Alert that checks for new rejected RETURNS rows
--      every 2 minutes and logs to ALERT_LOG.
--   3. Confirm it fires via ALERT_HISTORY() after manufacturing
--      one bad row, then suspend it.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
-- Q: Why did resuming the alert fail with "EXECUTE ALERT privilege
--    must be granted to owner role" (error 392000)?
-- A: Same pattern confirmed with EXECUTE TASK back in 6.1 —
--    SYSADMIN owns the alert but isn't automatically granted the
--    privilege to actually run it. GRANT EXECUTE ALERT ON ACCOUNT
--    TO ROLE SYSADMIN (as ACCOUNTADMIN) resolves it, and the fix
--    takes effect on the alert's next scheduled run with no need
--    to suspend/resume again.
--
-- Q: Why not just let the pipeline fail when it hits bad data?
-- A: A hard failure stops ALL rows in that run, including the
--    valid ones, and (depending on design) might repeatedly fail
--    on the same bad row every scheduled run until someone
--    manually intervenes. Dead-lettering isolates the damage to
--    just the rows that actually have a problem.
--
-- Q: Could an Alert's action be a Task, or vice versa?
-- A: No — different object types with different creation syntax,
--    though both are schema-level, both need WAREHOUSE + SCHEDULE,
--    both are created SUSPENDED, and both need explicit RESUME.
--    An Alert's action is a single statement executed only when
--    its condition is true; a Task's body always runs (subject to
--    its own optional WHEN clause, which is a different mechanism
--    covered in 6.3/6.4).
--
-- Q: What happens if SYSTEM$SEND_EMAIL is called with an
--    unverified recipient address?
-- A: The email silently isn't sent — confirmed in Snowflake's own
--    documentation. Administrators verify a user's email via
--    SYSTEM$START_USER_EMAIL_VERIFICATION before that address can
--    receive anything through a notification integration.
--
-- Q: How far back does ALERT_HISTORY() actually show?
-- A: Up to the last 7 days by default, same retention window as
--    TASK_HISTORY() — for longer retention, ACCOUNT_USAGE.ALERT_HISTORY
--    exists as a view, at the cost of the usual ACCOUNT_USAGE
--    latency discovered back in Goal 5.
-- ══════════════════════════════════════════════════════════════
