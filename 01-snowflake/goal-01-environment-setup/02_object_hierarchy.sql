-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 1 : Set Up Your Environment
-- Sub-task 1.2 : Navigate the object hierarchy
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~25 minutes
-- Warehouse size   : X-Small (COMPUTE_WH)
-- Starting point   : Fresh Snowflake session, no database selected
-- COF-C03 domain   : Domain 1 — Architecture & Features (25%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Everything in Snowflake lives inside a hierarchy of objects.
--   Before you create a single table or run a single query, you
--   need to know exactly where you are in that hierarchy and how
--   to navigate it deliberately.
--
--   Practitioners who skip this end up creating tables in the
--   wrong schema, querying the wrong database, or wondering why
--   their objects are invisible to their teammates. This sub-task
--   makes the hierarchy explicit and builds the habit of always
--   knowing your context.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE OBJECT HIERARCHY
-- ══════════════════════════════════════════════════════════════
--
--   ACCOUNT
--   └── DATABASE          (logical container — like a project)
--       └── SCHEMA        (organisational namespace — like a folder)
--           ├── TABLE     (structured data)
--           ├── VIEW      (saved query)
--           ├── STAGE     (landing zone for files)
--           ├── SEQUENCE  (auto-increment number generator)
--           ├── PIPE      (continuous ingestion config)
--           ├── STREAM    (change tracking object)
--           ├── TASK      (scheduled job)
--           └── UDF / PROCEDURE (custom functions and logic)
--
--   Every object in Snowflake has a fully qualified name:
--   DATABASE_NAME.SCHEMA_NAME.OBJECT_NAME
--
--   Example:
--   ECOMMERCE.RAW.ORDERS        ← table named ORDERS
--                                 in schema RAW
--                                 in database ECOMMERCE
--
--   You can omit the prefix if you have already set the active
--   database and schema with USE DATABASE / USE SCHEMA.
--   Snowflake resolves the rest automatically.
--
--   SYSTEM DATABASES YOU WILL SEE IN EVERY ACCOUNT:
--   · SNOWFLAKE            — account metadata, ACCOUNT_USAGE views
--   · SNOWFLAKE_SAMPLE_DATA — pre-loaded TPC-H, TPC-DS sample data
--   · YOUR_DB              — whatever you create
--
--   EVERY DATABASE STARTS WITH TWO BUILT-IN SCHEMAS:
--   · INFORMATION_SCHEMA   — ANSI standard metadata views
--                            (tables, columns, query history, etc.)
--   · PUBLIC               — default schema, available to all roles
--
-- ══════════════════════════════════════════════════════════════
-- SETUP: Session variable for your warehouse
-- ══════════════════════════════════════════════════════════════
-- Using a variable means you set your warehouse name once and
-- reference it throughout. If your warehouse is named differently
-- from COMPUTE_WH, change it here only — nothing else needs updating.

SET my_warehouse = 'COMPUTE_WH';

-- Resume the warehouse and set it as active for this session
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Survey the full account — what databases exist?
-- ══════════════════════════════════════════════════════════════
-- SHOW DATABASES lists every database your current role can see.
-- This is the top of the hierarchy — start here to orient yourself
-- in any Snowflake account you work in.

SHOW DATABASES;

-- Make the output queryable with RESULT_SCAN
-- (You will use this pattern constantly — always know your context)
SELECT
    "name"          AS database_name,
    "owner"         AS owned_by,
    "comment"       AS description,
    "created_on"    AS created_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;

-- You should see at minimum:
--   · SNOWFLAKE              — system database (read-only)
--   · SNOWFLAKE_SAMPLE_DATA  — pre-loaded sample data (read-only)
-- Any databases you or your organisation have created will also appear.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Drop into a database and survey its schemas
-- ══════════════════════════════════════════════════════════════
-- USE DATABASE sets your active database for the session.
-- After this, any unqualified object reference resolves within
-- this database. Think of it as cd-ing into a directory.

USE DATABASE SNOWFLAKE_SAMPLE_DATA;

SHOW SCHEMAS;

SELECT
    "name"          AS schema_name,
    "owner"         AS owned_by,
    "comment"       AS description
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;

-- You will see INFORMATION_SCHEMA plus several TPC-H and TPC-DS
-- schemas at different scale factors:
--   · TPCH_SF1    — TPC-H at 1GB scale
--   · TPCH_SF10   — TPC-H at 10GB scale
--   · TPCH_SF100  — TPC-H at 100GB scale
--   · TPCH_SF1000 — TPC-H at 1TB scale
-- Scale factor = roughly GB of data. SF1 is fast for learning.
-- SF1000 is what you use for serious performance exercises.

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Drop into a schema and survey its tables
-- ══════════════════════════════════════════════════════════════

USE SCHEMA TPCH_SF1;

SHOW TABLES;

SELECT
    "name"          AS table_name,
    "rows"          AS row_count,
    "bytes"         AS size_bytes,
    "owner"         AS owned_by,
    "created_on"    AS created_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "rows" DESC
;

-- Notice: you now have DATABASE → SCHEMA → TABLE fully navigated
-- using three USE statements and three SHOW commands.
-- This is the fastest way to orient yourself in an unfamiliar account.

-- Confirm your current context at any time:
SELECT
    CURRENT_DATABASE()  AS active_database,
    CURRENT_SCHEMA()    AS active_schema,
    CURRENT_WAREHOUSE() AS active_warehouse,
    CURRENT_ROLE()      AS active_role
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Build your own database and schema hierarchy
-- ══════════════════════════════════════════════════════════════
-- Now you create the structure that will hold your workbook data.
-- This is the database you will use for the rest of the workbook.

-- Create the main workbook database
CREATE DATABASE IF NOT EXISTS ECOMMERCE
    COMMENT = 'Workbook e-commerce dataset — Data Engineering Workbook Series'
;

-- Verify it was created
SHOW DATABASES LIKE 'ECOMMERCE';

-- Switch to it
USE DATABASE ECOMMERCE;

-- Every database has PUBLIC schema by default.
-- We will create three schemas to organise data by layer —
-- a pattern you will see again in the dbt workbook.

-- RAW: data exactly as it arrives — no transformations
CREATE SCHEMA IF NOT EXISTS RAW
    COMMENT = 'Raw ingested data — source of truth, never modified'
;

-- STAGING: lightly cleaned and typed, not yet business-modelled
CREATE SCHEMA IF NOT EXISTS STAGING
    COMMENT = 'Cleaned and typed data, ready for transformation'
;

-- ANALYTICS: business-ready tables and views for querying
CREATE SCHEMA IF NOT EXISTS ANALYTICS
    COMMENT = 'Business-ready tables and views for end-user querying'
;

-- Verify all three schemas exist
SHOW SCHEMAS;

SELECT
    "name"          AS schema_name,
    "comment"       AS description,
    "created_on"    AS created_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "name" NOT IN ('INFORMATION_SCHEMA', 'PUBLIC')
ORDER BY "name"
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Understand fully qualified object names
-- ══════════════════════════════════════════════════════════════
-- You can reference any object in Snowflake using its full path,
-- regardless of what your active database or schema is.
-- This is critical when joining across databases or writing
-- scripts that must be context-independent.

-- Fully qualified reference — works from any context:
SELECT
    TABLE_CATALOG   AS database_name,
    TABLE_SCHEMA    AS schema_name,
    TABLE_NAME,
    TABLE_TYPE,
    ROW_COUNT,
    BYTES
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
ORDER BY TABLE_SCHEMA, TABLE_NAME
;
-- Currently returns nothing (no tables yet — that is Goal 2).
-- Run this again after Goal 2 and you will see all your tables.

-- Cross-database fully qualified reference:
-- You can query SNOWFLAKE_SAMPLE_DATA from within ECOMMERCE context
SELECT COUNT(*) AS lineitem_count
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
;
-- This works because the full path resolves regardless of active DB.
-- This is how you join your data with sample data or other databases.

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Explore INFORMATION_SCHEMA — your in-database dictionary
-- ══════════════════════════════════════════════════════════════
-- Every database has its own INFORMATION_SCHEMA — a set of
-- read-only views that describe everything inside that database.
-- This is your first reference point when exploring an unfamiliar DB.

-- What schemas exist in ECOMMERCE?
SELECT
    SCHEMA_NAME,
    SCHEMA_OWNER,
    CREATED                 AS created_at,
    LAST_ALTERED            AS last_modified
FROM ECOMMERCE.INFORMATION_SCHEMA.SCHEMATA
ORDER BY SCHEMA_NAME
;

-- What tables exist? (None yet — returns empty. Bookmark this query.)
SELECT
    TABLE_CATALOG           AS database_name,
    TABLE_SCHEMA            AS schema_name,
    TABLE_NAME,
    TABLE_TYPE,             -- BASE TABLE, VIEW, etc.
    ROW_COUNT,
    BYTES,
    CREATED                 AS created_at,
    LAST_ALTERED            AS last_modified
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA')
ORDER BY TABLE_SCHEMA, TABLE_NAME
;

-- What columns does a table have?
-- (Using SNOWFLAKE_SAMPLE_DATA since ECOMMERCE has no tables yet)
SELECT
    COLUMN_NAME,
    ORDINAL_POSITION        AS column_order,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH AS max_length,
    IS_NULLABLE,
    COLUMN_DEFAULT
FROM SNOWFLAKE_SAMPLE_DATA.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'TPCH_SF1'
  AND TABLE_NAME   = 'ORDERS'
ORDER BY ORDINAL_POSITION
;
-- You will run the equivalent query on your ECOMMERCE tables
-- in Goal 2 after loading data. Bookmark this pattern.

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Navigate using the three-part name in practice
-- ══════════════════════════════════════════════════════════════
-- Switch context deliberately and confirm at each step.
-- This builds the habit of always knowing where you are.

-- Set context to your workbook database and raw schema
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Confirm
SELECT
    CURRENT_DATABASE()  AS active_database,
    CURRENT_SCHEMA()    AS active_schema
;
-- Should show: ECOMMERCE | RAW

-- Switch to analytics
USE SCHEMA ANALYTICS;

-- Confirm again
SELECT
    CURRENT_DATABASE()  AS active_database,
    CURRENT_SCHEMA()    AS active_schema
;
-- Should show: ECOMMERCE | ANALYTICS

-- Switch to a completely different database without losing warehouse
USE DATABASE SNOWFLAKE_SAMPLE_DATA;
USE SCHEMA TPCH_SF1;

SELECT
    CURRENT_DATABASE()  AS active_database,
    CURRENT_SCHEMA()    AS active_schema,
    CURRENT_WAREHOUSE() AS active_warehouse
;
-- Warehouse persists across USE DATABASE / USE SCHEMA commands.
-- Changing context never changes your active warehouse.

-- Return home to your workbook database
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Drop and recreate safely (DDL habits)
-- ══════════════════════════════════════════════════════════════
-- Two DDL patterns every practitioner should use by default:
-- CREATE IF NOT EXISTS  — safe to re-run, never errors if exists
-- CREATE OR REPLACE     — overwrites silently, use with caution

-- Safe pattern — always prefer this for schemas and databases:
CREATE SCHEMA IF NOT EXISTS ECOMMERCE.RAW
    COMMENT = 'Raw ingested data — source of truth, never modified'
;
-- Running this again produces no error and changes nothing.
-- This is what makes setup scripts idempotent (safe to re-run).

-- Destructive pattern — use deliberately, not by default:
-- CREATE OR REPLACE TABLE will silently drop and recreate.
-- The old table and ALL its data are gone immediately.
-- We will cover safe alternatives (CLONE, UNDROP) in Goal 8.

-- Confirm your final hierarchy is in place
SHOW SCHEMAS IN DATABASE ECOMMERCE;

SELECT
    "name"          AS schema_name,
    "comment"       AS description
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "name" NOT IN ('INFORMATION_SCHEMA', 'PUBLIC')
ORDER BY "name"
;



-- Expected output:
--   ANALYTICS  | Business-ready tables and views for end-user querying
--   RAW        | Raw ingested data — source of truth, never modified
--   STAGING    | Cleaned and typed data, ready for transformation

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Without using USE DATABASE or USE SCHEMA, write a single
--    SELECT that returns the row count of SNOWFLAKE_SAMPLE_DATA
--    .TPCH_SF10.ORDERS using a fully qualified table name.
--    Then do the same for TPCH_SF100.ORDERS.
--    What do you notice about the counts?
--
-- 2. Add a fourth schema to your ECOMMERCE database called
--    SANDBOX with the comment 'Personal workspace for ad-hoc work'.
--    Verify it appears in INFORMATION_SCHEMA.SCHEMATA.
--
-- 3. Query INFORMATION_SCHEMA.TABLES across the TPCH_SF1 and
--    TPCH_SF10 schemas in SNOWFLAKE_SAMPLE_DATA.
--    Which tables exist in SF10 that do not exist in SF1?
--    (Hint: there are none — but the query to verify that is
--    a useful EXCEPT pattern to practise.)

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I create a table without specifying a schema?
-- A: It goes into whatever schema is currently active
--    (CURRENT_SCHEMA()). If no schema is active, Snowflake
--    errors. Always confirm your context with
--    SELECT CURRENT_DATABASE(), CURRENT_SCHEMA() before
--    running CREATE TABLE in a new session.
--
-- Q: What if I accidentally drop a schema?
-- A: UNDROP SCHEMA schema_name recovers it within the Time
--    Travel retention window (1 day on Standard, up to 90 days
--    on Enterprise). We cover this in Goal 8. For now: be
--    deliberate about DROP commands and always double-check
--    CURRENT_DATABASE() and CURRENT_SCHEMA() first.
--
-- Q: What if two roles have databases with the same name?
-- A: Database names are unique per account — no two databases
--    in the same account can share a name regardless of role.
--    What changes per role is VISIBILITY — a role may not be
--    able to see a database that exists, but the name is still
--    taken. SHOW DATABASES only shows what your current role
--    has privileges to see.
--
-- Q: What is the PUBLIC schema and should I use it?
-- A: PUBLIC is created automatically in every database and is
--    accessible to all roles by default. In a team environment
--    it becomes a dumping ground — avoid it for anything
--    serious. Use named schemas (RAW, STAGING, ANALYTICS) with
--    explicit access controls instead. We cover schema-level
--    grants in Goal 4.
--
-- Q: What if I want my scripts to work regardless of which
--    database is active?
-- A: Always use fully qualified three-part names in any script
--    that will be run by others or scheduled as a Task.
--    Unqualified names work for interactive exploration but
--    are fragile in automation. The pattern:
--    DATABASE_NAME.SCHEMA_NAME.OBJECT_NAME
--    is always safe, always explicit, always recommended
--    in production code.


-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- Run this block when you want to reset and start fresh.
-- This permanently drops the ECOMMERCE database and everything
-- inside it — all schemas, tables, views, and stages.
--
-- NOTE: Snowflake's Time Travel gives you a safety net.
-- If you drop this by mistake you can recover it with:
--   UNDROP DATABASE ECOMMERCE;
-- within your Time Travel retention window (1 day Standard,
-- up to 90 days Enterprise). Covered in detail in Goal 8.
--
-- WARNING: Do NOT run this if you have already loaded data
-- in Goal 2. Only use this to reset Goal 2 work.
-- ══════════════════════════════════════════════════════════════

-- Drop all schemas first (optional — dropping the DB cascades)
-- Shown explicitly so you understand what is being removed
DROP SCHEMA IF EXISTS ECOMMERCE.ANALYTICS;
DROP SCHEMA IF EXISTS ECOMMERCE.STAGING;
DROP SCHEMA IF EXISTS ECOMMERCE.RAW;

-- Drop the database — this cascades and removes everything inside
DROP DATABASE IF EXISTS ECOMMERCE;

-- Verify it is gone
SHOW DATABASES LIKE 'ECOMMERCE';
-- Should return zero rows