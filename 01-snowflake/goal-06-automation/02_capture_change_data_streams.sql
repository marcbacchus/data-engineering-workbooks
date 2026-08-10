-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 6       : Automate Workflows
-- Sub-task 6.2 : Capture Change Data with Streams
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~35-45 min
-- Warehouse size    : X-Small (WORKBOOK_WH)
-- Database          : ECOMMERCE.RAW
-- Run in            : Snowsight
-- Prerequisites     : Sub-task 6.1 complete
-- COF-C03 domain    : Domain 4.0 — Performance Optimization,
--                      Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════
--   A Stream is Snowflake's native change-tracking object: it
--   doesn't store a copy of your data, it stores an offset (a
--   point in time) plus enough metadata to tell you exactly which
--   rows changed since that offset, and how.
--
--   In this sub-task you will create a stream on ORDERS, make a
--   mix of inserts/updates/deletes, preview the stream's contents
--   without consuming it, understand how updates are represented,
--   properly consume the stream, and compare a STANDARD stream
--   against an APPEND_ONLY stream. This is the building block
--   sub-task 6.3 combines with Tasks to build a real incremental
--   pipeline.
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- CONCEPT
-- ══════════════════════════════════════════════════════════════
--   A stream is NOT a copy of the table and NOT a trigger. It is
--   a pointer: "give me everything that changed in ORDERS since
--   the last time I consumed this stream." The underlying table's
--   own change-tracking metadata (enabled automatically the
--   moment a stream is created on it) is what makes this possible.
--
--   Three stream types:
--     · STANDARD (default)  -- captures inserts, updates, AND
--                               deletes. An update is represented
--                               as a delete row + insert row pair.
--     · APPEND_ONLY          -- captures inserts only. Updates and
--                               deletes are invisible to it. Ideal
--                               for pure append/log-style pipelines
--                               where you never care about history.
--     · INSERT_ONLY           -- applies ONLY to external tables /
--                               directory tables, not standard
--                               tables. Not used in this sub-task.
--
--   Critical behavior: a stream's offset only ADVANCES when the
--   stream is consumed inside a DML statement (e.g. INSERT INTO
--   ... SELECT * FROM my_stream, executed and committed). A bare
--   SELECT * FROM my_stream does NOT advance the offset — you can
--   preview the same pending changes as many times as you like
--   without losing them, which is the safety net that makes
--   Streams reliable for pipelines that might fail mid-run.
--
--   A stream can go STALE if its offset isn't consumed within the
--   source table's DATA_RETENTION_TIME_IN_DAYS window — after that,
--   the change history needed to compute the delta no longer
--   exists and the stream must be recreated.
--
-- ── ORACLE / SQL SERVER COMPARISON ──────────────────────────────
--   Oracle       : Change Data Capture historically via Oracle
--                  Streams (deprecated) or GoldenGate (separate
--                  licensed product, log-based replication) —
--                  either way, a heavyweight component to install,
--                  configure, and operate.
--   SQL Server   : Change Data Capture (CDC) feature, or the
--                  lighter-weight Change Tracking feature — both
--                  built in, but require enabling at the database
--                  and table level and querying separate CDC
--                  system functions.
--   Snowflake    : No separate feature to enable — CREATE STREAM
--                  is itself the enablement. No log shipping, no
--                  agent, no separate licensed product. The
--                  tradeoff: you're bound to the source table's
--                  retention window, whereas GoldenGate/CDC systems
--                  can retain change history independently and
--                  much longer.
-- ──────────────────────────────────────────────────────────────
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════
-- A small table to consume the stream INTO later in Step 5 — this
-- stands in for "the downstream table a real pipeline would update."

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_CHANGE_LOG (
    logged_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    order_id        NUMBER,
    metadata_action VARCHAR,
    metadata_isupdate BOOLEAN
);

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create a standard stream on ORDERS
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE STREAM ECOMMERCE.RAW.ORDERS_STREAM
    ON TABLE ECOMMERCE.RAW.ORDERS
    COMMENT = 'Goal 6.2 — standard stream, tracks insert/update/delete';

SHOW STREAMS LIKE 'ORDERS_STREAM';
-- STALE should read false, MODE should read DEFAULT (standard)

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Make a mix of changes to the source table
-- ══════════════════════════════════════════════════════════════
-- Wrapped in BEGIN/COMMIT per workbook convention for destructive
-- DML (AUTOCOMMIT = TRUE by default, but explicit is safer).

-- Copy this order_id to be used below in place of <the pre-existing order_id>
select * from ECOMMERCE.RAW.ORDERS
where order_status = 'placed'
limit 1;

-- Snowsight note: highlight from BEGIN through COMMIT (inclusive)
-- and run as a single selection — running these lines one at a
-- time breaks the explicit transaction and defeats the point of
-- wrapping this DML in BEGIN/COMMIT at all.
BEGIN;

-- Update a row that already existed BEFORE this stream's current
-- offset — this is what produces the delete+insert pair
UPDATE ECOMMERCE.RAW.ORDERS
SET order_status = 'shipped'
WHERE order_id = <the pre-existing order_id>;

-- A genuinely new row, inserted fresh — this stays a single INSERT
INSERT INTO ECOMMERCE.RAW.ORDERS (order_id, customer_id, order_status, created_at)
VALUES (900000001, 1, 'pending', CURRENT_TIMESTAMP());

COMMIT;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Preview the stream WITHOUT consuming it
-- ══════════════════════════════════════════════════════════════
-- Run this SELECT as many times as you like — it will return the
-- same rows every time because a bare SELECT never advances the
-- stream's offset.

SELECT
    order_id,
    order_status,
    metadata$action,
    metadata$isupdate,
    metadata$row_id
FROM ECOMMERCE.RAW.ORDERS_STREAM
ORDER BY metadata$action;

-- Notice both halves of the update pair share the SAME
-- METADATA$ROW_ID — that's the concrete evidence linking them as
-- one logical change, not just a coincidence of ISUPDATE = TRUE.

-- Run the SELECT above a second time right now — notice the
-- result set is identical. Nothing has been consumed yet.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Understand how the update shows up
-- ══════════════════════════════════════════════════════════════
-- The single UPDATE from Step 2 appears as TWO rows in the stream:
-- one with METADATA$ACTION = 'DELETE' (the old value) and one with
-- METADATA$ACTION = 'INSERT' (the new value), and BOTH have
-- METADATA$ISUPDATE = TRUE. This is how Snowflake represents "this
-- wasn't a fresh insert, it was a change to an existing row."
--
-- The row inserted fresh in Step 2 shows METADATA$ACTION = 'INSERT'
-- with METADATA$ISUPDATE = FALSE — that's how you tell a genuine
-- new row apart from the "new" half of an update pair.

SELECT
    order_id,
    metadata$action,
    metadata$isupdate,
    CASE
        WHEN metadata$action = 'INSERT' AND metadata$isupdate = FALSE THEN 'genuinely new row'
        WHEN metadata$action = 'INSERT' AND metadata$isupdate = TRUE  THEN 'new half of an update'
        WHEN metadata$action = 'DELETE' AND metadata$isupdate = TRUE  THEN 'old half of an update'
        WHEN metadata$action = 'DELETE' AND metadata$isupdate = FALSE THEN 'genuine delete'
    END AS change_type
FROM ECOMMERCE.RAW.ORDERS_STREAM
-- Swap in the order_id you captured and updated in Step 2
WHERE order_id IN (<the pre-existing order_id>, 900000001);

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Properly consume the stream
-- ══════════════════════════════════════════════════════════════
-- This INSERT ... SELECT reads FROM the stream inside a DML
-- statement. Once it commits, the stream's offset advances past
-- everything it just returned.

INSERT INTO ECOMMERCE.RAW.ORDERS_CHANGE_LOG (order_id, metadata_action, metadata_isupdate)
SELECT order_id, metadata$action, metadata$isupdate
FROM ECOMMERCE.RAW.ORDERS_STREAM;

-- Confirm the log captured everything
SELECT * FROM ECOMMERCE.RAW.ORDERS_CHANGE_LOG ORDER BY logged_at;

-- Run this exact query now — do not scroll back to Step 3.
-- It should return empty: the offset advanced when Step 5's
-- INSERT...SELECT consumed the stream, so there is nothing new
-- to report until ORDERS changes again.
SELECT * FROM ECOMMERCE.RAW.ORDERS_STREAM;
-- Empty. The offset advanced — there is nothing new to report
-- until the source table changes again.

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Create an APPEND_ONLY stream for comparison
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE STREAM ECOMMERCE.RAW.ORDERS_STREAM_APPEND_ONLY
    ON TABLE ECOMMERCE.RAW.ORDERS
    APPEND_ONLY = TRUE
    COMMENT = 'Goal 6.2 — append-only stream, inserts only, no update/delete visibility';

-- Copy another order_id with status = 'placed' before running this
--order_id replaces <the pre-existing order_id> below
SELECT * FROM ECOMMERCE.RAW.ORDERS
WHERE order_status = 'placed'
LIMIT 1;

BEGIN;

-- Highlight from BEGIN through COMMIT and run together
-- A genuinely new row — both streams should capture this as INSERT
INSERT INTO ECOMMERCE.RAW.ORDERS (order_id, customer_id, order_status, created_at)
VALUES (900000002, 1, 'pending', CURRENT_TIMESTAMP());

-- An update to a PRE-EXISTING row (not the one just inserted above) —
-- this is what the two stream types will disagree on
UPDATE ECOMMERCE.RAW.ORDERS
SET order_status = 'shipped'
WHERE order_id = 200802;

COMMIT;

-- The standard stream shows the fresh insert AND the update pair
SELECT order_id, metadata$action, metadata$isupdate
FROM ECOMMERCE.RAW.ORDERS_STREAM
WHERE order_id IN (<the pre-existing order_id>,900000002);

-- The append-only stream shows ONLY the fresh insert — the update
-- to the pre-existing row is invisible to it
SELECT order_id, metadata$action, metadata$isupdate
FROM ECOMMERCE.RAW.ORDERS_STREAM_APPEND_ONLY
WHERE order_id IN (<the pre-existing order_id>,900000002);

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Check staleness and retention dependency
-- ══════════════════════════════════════════════════════════════

DESCRIBE STREAM ECOMMERCE.RAW.ORDERS_STREAM;
-- Look at the STALE_AFTER column — this is the timestamp beyond
-- which the stream becomes unusable if not consumed by then. It
-- tracks the source table's DATA_RETENTION_TIME_IN_DAYS setting.

SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE ECOMMERCE.RAW.ORDERS;

-- ══════════════════════════════════════════════════════════════
-- CLEANUP NOTE
-- ══════════════════════════════════════════════════════════════
-- Unlike Tasks (sub-task 6.1), a Stream sitting idle costs
-- nothing — there is no schedule, nothing runs in the background.
-- The only cost is the source table's change-tracking metadata,
-- which is already implied by the table's existing retention
-- setting. No suspend/drop step is required here for cost reasons.
-- Both demo streams (ORDERS_STREAM, ORDERS_STREAM_APPEND_ONLY) are
-- left in place — sub-task 6.3 reuses ORDERS_STREAM directly.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
-- Your turn:
--   1. Create a standard stream on RETURNS.
--   2. Insert two new rows and delete one existing row (use a
--      real existing return_id from a prior goal's data).
--   3. Query the stream and identify which rows are genuine
--      inserts vs genuine deletes using METADATA$ACTION alone
--      (there should be no METADATA$ISUPDATE = TRUE rows here,
--      since nothing was updated).
--   4. Consume the stream via an INSERT ... SELECT into a new
--      log table, then confirm a second SELECT from the stream
--      returns empty.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
-- Q: Does querying a stream from a different session/worksheet
--    consume it?
-- A: Only if that query is a DML statement that reads from the
--    stream and commits. A plain SELECT from any session is just
--    a preview, regardless of which session runs it.
--
-- Q: What happens if two separate processes both try to consume
--    the same stream at the same time?
-- A: Only one will succeed in advancing the offset — the other's
--    transaction will either see no new rows (if it reads after
--    the first commits) or will need to handle a concurrent
--    modification conflict. Real pipelines typically have exactly
--    one consumer per stream to avoid this entirely.
--
-- Q: Can I have multiple streams on the same table?
-- A: Yes — each stream tracks its own independent offset. Two
--    streams on ORDERS (like the two created in this sub-task)
--    do not interfere with each other at all.
--
-- Q: What happens if I query a STALE stream?
-- A: The query fails — Snowflake can no longer reconstruct the
--    change history needed. The stream must be recreated, which
--    starts a fresh offset from the current moment (any changes
--    between the old offset and recreation are permanently lost
--    from that stream's perspective).
-- ══════════════════════════════════════════════════════════════
