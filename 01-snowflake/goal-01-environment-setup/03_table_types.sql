-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 1 : Set Up Your Environment
-- Sub-task 1.3 : Know your table types
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~25 minutes
-- Warehouse size   : X-Small (COMPUTE_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : 02_object_hierarchy.sql completed
--                    ECOMMERCE database exists with RAW, STAGING,
--                    ANALYTICS schemas
-- COF-C03 domain   : Domain 1 — Architecture & Features (25%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Snowflake has four table types. Most practitioners only ever
--   use permanent tables — and then wonder why their storage bill
--   is higher than expected, or why their test data is affecting
--   production queries.
--
--   Choosing the right table type is a cost and architecture
--   decision, not just a syntax choice. This sub-task makes that
--   decision explicit so you make it deliberately every time.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE FOUR TABLE TYPES
-- ══════════════════════════════════════════════════════════════
--
--  ┌─────────────────┬──────────────┬───────────┬─────────────┐
--  │ Type            │ Time Travel  │ Fail-Safe │ Persists    │
--  ├─────────────────┼──────────────┼───────────┼─────────────┤
--  │ Permanent       │ 0–90 days    │ 7 days    │ Until DROP  │
--  │ Transient       │ 0–1 day      │ None      │ Until DROP  │
--  │ Temporary       │ 0–1 day      │ None      │ Session end │
--  │ External        │ None         │ None      │ You manage  │
--  └─────────────────┴──────────────┴───────────┴─────────────┘
--
-- PERMANENT TABLE (default)
--   The standard table type. Data persists until explicitly
--   dropped. Full Time Travel (up to 90 days on Enterprise)
--   and 7-day Fail-Safe. Most expensive to store because
--   Snowflake retains historical versions of all data changes.
--   Use for: production data, anything that needs recovery options.
--
-- TRANSIENT TABLE
--   Like a permanent table but with no Fail-Safe and maximum
--   1-day Time Travel. Lower storage cost because Snowflake
--   does not retain the 7-day Fail-Safe copy.
--   Use for: staging data, intermediate transformation results,
--   large working tables you can recreate if lost.
--   Avoid for: anything where you need recovery beyond 1 day.
--
-- TEMPORARY TABLE
--   Exists only for the duration of your current session.
--   Automatically dropped when you close the session or
--   disconnect. Invisible to other users even in the same DB.
--   No Time Travel, no Fail-Safe.
--   Use for: intermediate results within a single session,
--   ad-hoc analysis, testing logic before writing to permanent.
--
-- EXTERNAL TABLE
--   A metadata layer over files in cloud storage (S3, Azure
--   Blob, GCS). Data never enters Snowflake storage — you query
--   it in place. Read-only. No Time Travel, no Fail-Safe.
--   Use for: data lake integration, querying files without
--   loading them, hybrid lake/warehouse architectures.
--   Covered in depth in Goal 2 (Sub-task 2.8).
--
-- THE COST IMPLICATION PRACTITIONERS MISS
--   Snowflake charges for storage in three buckets:
--   1. Active storage     — your current data
--   2. Time Travel storage — historical versions (up to 90 days)
--   3. Fail-Safe storage  — 7-day disaster recovery copy
--
--   A large permanent table with 90-day Time Travel can cost
--   3x its active storage size in total storage charges.
--   Transient tables eliminate Fail-Safe entirely and cap
--   Time Travel at 1 day — significantly cheaper for data
--   that can be recreated (staging, intermediate results).
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════
-- If you ran the cleanup block in 02_object_hierarchy.sql,
-- recreate the ECOMMERCE database and schemas first:

CREATE DATABASE IF NOT EXISTS ECOMMERCE
    COMMENT = 'Workbook e-commerce dataset — Data Engineering Workbook Series'
;
CREATE SCHEMA IF NOT EXISTS ECOMMERCE.RAW
    COMMENT = 'Raw ingested data — source of truth, never modified'
;
CREATE TRANSIENT SCHEMA IF NOT EXISTS ECOMMERCE.STAGING
    COMMENT = 'Cleaned and typed data — transient, no Fail-Safe'
;
CREATE SCHEMA IF NOT EXISTS ECOMMERCE.ANALYTICS
    COMMENT = 'Business-ready tables and views for end-user querying'
;

SET my_warehouse = 'COMPUTE_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create a permanent table (the default)
-- ══════════════════════════════════════════════════════════════
-- No keyword needed — CREATE TABLE creates a permanent table.
-- This is what most practitioners use without thinking about it.

CREATE TABLE IF NOT EXISTS ECOMMERCE.RAW.CUSTOMERS_PERMANENT (
    customer_id     INTEGER         NOT NULL,
    first_name      VARCHAR(100)    NOT NULL,
    last_name       VARCHAR(100)    NOT NULL,
    email           VARCHAR(255)    NOT NULL,
    country         VARCHAR(100),
    created_at      TIMESTAMP_NTZ
)
COMMENT = 'Permanent table — full Time Travel and Fail-Safe'
;

-- Verify it was created and check its type
SHOW TABLES LIKE 'CUSTOMERS_PERMANENT' IN SCHEMA ECOMMERCE.RAW;

SELECT
    "name"          AS table_name,
    "kind"          AS table_type,
    "rows"          AS row_count,
    "bytes"         AS size_bytes,
    "retention_time" AS time_travel_days
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- table_type should show: TABLE
-- retention_time: 1 (default — can be increased to 90 on Enterprise)

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create a transient table
-- ══════════════════════════════════════════════════════════════
-- TRANSIENT keyword is required — it is not the default.
-- Same syntax as permanent, one keyword difference.
-- This is the table type most practitioners should use for
-- staging and intermediate data but rarely do.

CREATE TRANSIENT TABLE IF NOT EXISTS ECOMMERCE.STAGING.CUSTOMERS_TRANSIENT (
    customer_id     INTEGER         NOT NULL,
    first_name      VARCHAR(100)    NOT NULL,
    last_name       VARCHAR(100)    NOT NULL,
    email           VARCHAR(255)    NOT NULL,
    country         VARCHAR(100),
    created_at      TIMESTAMP_NTZ
)
COMMENT = 'Transient table — no Fail-Safe, max 1-day Time Travel'
;

SHOW TABLES LIKE 'CUSTOMERS_TRANSIENT' IN SCHEMA ECOMMERCE.STAGING;

SELECT
    "name"          AS table_name,
    "kind"          AS table_type,
    "retention_time" AS time_travel_days
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- table_type: TABLE (same display as permanent)
-- retention_time: 1 (capped at 1 for transient — cannot increase)
-- Note: SHOW TABLES does not explicitly label transient tables.
-- Check INFORMATION_SCHEMA for the IS_TRANSIENT flag (Step 5).

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Create a temporary table
-- ══════════════════════════════════════════════════════════════
-- TEMPORARY keyword required. Visible only in this session.
-- If another user queries ECOMMERCE.RAW right now, they will
-- not see this table at all — it is session-scoped.

CREATE TEMPORARY TABLE CUSTOMERS_TEMP (
    customer_id     INTEGER,
    full_name       VARCHAR(200),
    created_at      TIMESTAMP_NTZ
)
COMMENT = 'Temporary table — session only, invisible to others'
;

-- Insert a test row to make it tangible
INSERT INTO CUSTOMERS_TEMP VALUES
    (1, 'Marc Bacchus', CURRENT_TIMESTAMP()),
    (2, 'Test User',    CURRENT_TIMESTAMP())
;

SELECT * FROM CUSTOMERS_TEMP;

-- Notice: no schema prefix needed because we are in ECOMMERCE.RAW
-- and the temp table is visible in the current session context.
-- The temp table shadows any permanent table of the same name
-- in the same schema — important to know if you reuse names.

SHOW TABLES LIKE 'CUSTOMERS_TEMP';

SELECT
    "name"          AS table_name,
    "kind"          AS table_type,
    "retention_time" AS time_travel_days
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- table_type: TEMPORARY
-- retention_time: 0 (no Time Travel on temporary tables)

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Understand Time Travel retention settings
-- ══════════════════════════════════════════════════════════════
-- You can set retention at table creation or alter it later.
-- Enterprise edition supports 0–90 days on permanent tables.
-- Standard edition supports 0–1 day only.

-- Increase Time Travel retention on the permanent table
-- (Enterprise edition required for values above 1)
ALTER TABLE ECOMMERCE.RAW.CUSTOMERS_PERMANENT
    SET DATA_RETENTION_TIME_IN_DAYS = 7
;

-- Verify the change
SHOW TABLES LIKE 'CUSTOMERS_PERMANENT' IN SCHEMA ECOMMERCE.RAW;

SELECT
    "name"              AS table_name,
    "retention_time"    AS time_travel_days
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- retention_time should now show 7

-- Try to set retention on a transient table — this will fail
-- Uncomment to see the error:
-- ALTER TABLE ECOMMERCE.STAGING.CUSTOMERS_TRANSIENT
--     SET DATA_RETENTION_TIME_IN_DAYS = 7;
-- Error: cannot set retention > 1 on a transient table.
-- This confirms the architectural difference between the types.

-- Reset to 1 day for cost efficiency in this workbook
ALTER TABLE ECOMMERCE.RAW.CUSTOMERS_PERMANENT
    SET DATA_RETENTION_TIME_IN_DAYS = 1
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Distinguish table types via INFORMATION_SCHEMA
-- ══════════════════════════════════════════════════════════════
-- SHOW TABLES does not clearly label permanent vs transient.
-- INFORMATION_SCHEMA.TABLES has the IS_TRANSIENT column
-- which makes the distinction explicit.

SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    TABLE_TYPE,
    IS_TRANSIENT,
    RETENTION_TIME,
    COMMENT
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('RAW', 'STAGING')
  AND TABLE_NAME LIKE 'CUSTOMERS%'
ORDER BY TABLE_SCHEMA, TABLE_NAME
;

-- Expected output:
-- RAW     | CUSTOMERS_PERMANENT | BASE TABLE | N | 1 | Permanent table...
-- STAGING | CUSTOMERS_TRANSIENT | BASE TABLE | Y | 1 | Transient table...
--
-- IS_TRANSIENT = YES confirms the table has no Fail-Safe.
-- Temporary tables do NOT appear in INFORMATION_SCHEMA —
-- they are session-scoped and invisible to metadata views.

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Create a schema-level transient default
-- ══════════════════════════════════════════════════════════════
-- You can create a schema where ALL tables are transient by
-- default — useful for staging schemas where you never want
-- Fail-Safe costs accumulating.

CREATE TRANSIENT SCHEMA IF NOT EXISTS ECOMMERCE.STAGING_TRANSIENT
    COMMENT = 'All tables created here are transient by default'
;

-- Create a table in it without the TRANSIENT keyword
CREATE TABLE IF NOT EXISTS ECOMMERCE.STAGING_TRANSIENT.TEST_TABLE (
    id INTEGER,
    val VARCHAR(100)
)
;

-- Check its type — it inherits transient from the schema
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    IS_TRANSIENT,
    RETENTION_TIME
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'STAGING_TRANSIENT'
;
-- IS_TRANSIENT = YES even though we did not use the TRANSIENT keyword
-- The schema-level setting cascades to all tables created within it.

-- ══════════════════════════════════════════════════════════════
-- STEP 7: The right table type for the right job
-- ══════════════════════════════════════════════════════════════
-- Applying what we have learned to the ECOMMERCE workbook schema:

-- RAW schema: permanent tables — source of truth, needs recovery
-- (already set up as permanent in the steps above)

-- STAGING schema: transient tables — intermediate, recreatable
-- The STAGING schema itself should be transient to cascade the
-- setting to all tables created within it.

-- First drop the existing STAGING schema
DROP SCHEMA IF EXISTS ECOMMERCE.STAGING;

-- Recreate it as transient
CREATE TRANSIENT SCHEMA IF NOT EXISTS ECOMMERCE.STAGING
    COMMENT = 'Cleaned and typed data — transient, no Fail-Safe'
;

-- ANALYTICS schema: permanent tables — business-ready, needs recovery
-- Already created as permanent in 02_object_hierarchy.sql — no change needed.

-- Verify the final schema setup
SELECT
    SCHEMA_NAME,
    IS_TRANSIENT,
    COMMENT
FROM ECOMMERCE.INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME NOT IN ('INFORMATION_SCHEMA', 'PUBLIC',
                           'STAGING_TRANSIENT')
ORDER BY SCHEMA_NAME
;

-- Expected:
-- ANALYTICS | NO | Business-ready tables...  (permanent)
-- RAW       | NO | Raw ingested data...       (permanent)
-- STAGING   | YES | Cleaned and typed data...  (transient)

-- ══════════════════════════════════════════════════════════════
-- FULL CLEANUP (optional)
-- ══════════════════════════════════════════════════════════════
-- Option 1 — Remove test tables only, keep ECOMMERCE intact
-- Use this if you are continuing to sub-task 1.4
-- ──────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS ECOMMERCE.RAW.CUSTOMERS_PERMANENT;
DROP TABLE IF EXISTS ECOMMERCE.STAGING.CUSTOMERS_TRANSIENT;
DROP TABLE IF EXISTS CUSTOMERS_TEMP;
DROP SCHEMA IF EXISTS ECOMMERCE.STAGING_TRANSIENT;

-- Option 2 — Full reset, drop the entire ECOMMERCE database
-- Use this only if you want to start Goal 1 completely fresh
-- NOTE: Sub-task 1.4 SETUP block will recreate everything needed
-- ──────────────────────────────────────────────────────────────
-- DROP DATABASE IF EXISTS ECOMMERCE;

-- Verify
SELECT TABLE_SCHEMA, TABLE_NAME
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE 'CUSTOMERS%'
;
-- Should return zero rows (CUSTOMERS_TEMP may still show
-- if session is active — it drops automatically on session end)

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a permanent table called ORDERS_PERMANENT in
--    ECOMMERCE.RAW with these columns:
--    order_id (INTEGER), customer_id (INTEGER),
--    order_total (FLOAT), created_at (TIMESTAMP_NTZ)
--    Set its Time Travel retention to 3 days.
--    Verify IS_TRANSIENT = N in INFORMATION_SCHEMA.
--
-- 2. Create the same table as a transient table called
--    ORDERS_TRANSIENT in ECOMMERCE.STAGING.
--    Try to set its retention to 3 days — what happens?
--    What does the error tell you about the architectural
--    difference between the two types?
--
-- 3. Create a temporary table called ORDERS_WORKING in the
--    current session. Insert 3 rows. Query it.
--    Now open a SECOND Snowsight worksheet (new tab).
--    Try to query ECOMMERCE.RAW.ORDERS_WORKING from there.
--    What happens and why?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I created a permanent table when I should have
--    used transient — can I convert it?
-- A: No direct conversion exists. You would need to:
--    1. CREATE TRANSIENT TABLE new_table AS SELECT * FROM old_table
--    2. DROP TABLE old_table
--    3. ALTER TABLE new_table RENAME TO old_table
--    Plan your table types upfront — retrofitting is disruptive.
--
-- Q: What if my session ends and I need data from a temp table?
-- A: It is gone. Temporary tables are not recoverable after
--    session end — no Time Travel, no Fail-Safe, no UNDROP.
--    If you need data to survive beyond a session, use a
--    permanent or transient table instead.
--
-- Q: What if I use CREATE OR REPLACE TABLE on a permanent table —
--    does it stay permanent?
-- A: Yes — CREATE OR REPLACE preserves the table type.
--    CREATE OR REPLACE TABLE stays permanent.
--    CREATE OR REPLACE TRANSIENT TABLE stays transient.
--    The type is set at creation and preserved on replace.
--
-- Q: What if I want to query data in S3 without loading it?
-- A: That is what external tables are for. Covered in
--    Goal 2 Sub-task 2.8. External tables are read-only,
--    have no Time Travel or Fail-Safe, and the data stays
--    in your own cloud storage — Snowflake never copies it.
--
-- Q: What is the actual cost difference between permanent
--    and transient tables?
-- A: Snowflake charges $23 per TB per month for storage
--    (on-demand pricing — varies by region and contract).
--    A 1TB permanent table with 7-day Time Travel and
--    Fail-Safe can accumulate up to 3TB of total storage
--    (1TB active + up to 1TB Time Travel + 1TB Fail-Safe).
--    The same table as transient: ~1TB active + up to
--    ~0.14TB Time Travel (1 day) = ~1.14TB total.
--    For large staging tables this difference is significant.