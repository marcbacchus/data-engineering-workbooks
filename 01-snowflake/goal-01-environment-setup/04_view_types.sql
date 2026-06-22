-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 1 : Set Up Your Environment
-- Sub-task 1.4 : Know your view types
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~20 minutes
-- Warehouse size   : X-Small (COMPUTE_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : 03_table_types.sql completed
--                    ECOMMERCE database exists with RAW, STAGING,
--                    ANALYTICS schemas
-- COF-C03 domain   : Domain 1 — Architecture & Features (25%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Views are one of the most versatile tools in Snowflake.
--   They are used for security, performance, abstraction, and
--   data sharing. But Snowflake has three distinct view types
--   with very different behaviours, costs, and use cases.
--
--   Most practitioners use only standard views and miss out on
--   secure views for data sharing and materialized views for
--   query acceleration. This sub-task covers all three so you
--   choose deliberately.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE THREE VIEW TYPES
-- ══════════════════════════════════════════════════════════════
--
--  ┌──────────────────┬────────────┬───────────-┬─────────────┐
--  │ Type             │ Definition │ Pre-       │ Extra cost  │
--  │                  │ visible?   │ computed?  │             │
--  ├──────────────────┼────────────┼──────────-─┼─────────────┤
--  │ Standard         │ Yes        │ No         │ None        │
--  │ Secure           │ No         │ No         │ None        │
--  │ Materialized     │ Yes        │ Yes        │ Storage +   │
--  │                  │            │            │ compute     │
--  └──────────────────┴────────────┴──────────-─┴─────────────┘
--
-- STANDARD VIEW
--   A saved SQL query with a name. No data is stored — every
--   time you query the view, Snowflake executes the underlying
--   query against the base tables. The view definition (the SQL)
--   is visible to anyone who can access the view.
--   Use for: abstracting complexity, logical data organisation,
--   column aliasing, presenting a consistent interface to users.
--
-- SECURE VIEW
--   Like a standard view but the definition is hidden from
--   non-privileged users. Even with SELECT access, users cannot
--   see the underlying SQL. Required for Snowflake data sharing —
--   you cannot share a standard view externally.
--   Also bypasses certain query optimisations to prevent data
--   inference through query timing attacks.
--   Use for: data sharing, masking sensitive logic, compliance.
--   Trade-off: slightly slower than standard views due to
--   optimisation bypass.
--
-- MATERIALIZED VIEW
--   Pre-computes and stores the query result. Snowflake
--   automatically refreshes the result when base data changes.
--   Queries against a materialized view read the stored result
--   rather than re-executing the underlying query — much faster
--   for expensive aggregations on large tables.
--   Use for: frequently queried aggregations, dashboards,
--   pre-joining large tables that change infrequently.
--   Trade-off: storage cost for the pre-computed result plus
--   background compute cost for automatic refresh.
--   Requires: Enterprise edition. Limited to a single base table
--   (no joins in the materialized view definition).
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'COMPUTE_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);

-- Recreate ECOMMERCE if you ran the full cleanup in 1.3
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

USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Create a base table to demonstrate all three view types
-- We use a subset of the ORDERS structure as a realistic example
CREATE TABLE IF NOT EXISTS ECOMMERCE.RAW.ORDERS_DEMO (
    order_id        INTEGER         NOT NULL,
    customer_id     INTEGER         NOT NULL,
    customer_email  VARCHAR(255),
    order_status    VARCHAR(50),
    order_total     FLOAT,
    profit_margin   FLOAT,          -- sensitive business data
    created_at      TIMESTAMP_NTZ
)
COMMENT = 'Demo table for view type exercises — dropped in cleanup'
;

-- Insert sample rows
INSERT INTO ECOMMERCE.RAW.ORDERS_DEMO VALUES
    (1,  1001, 'alice@example.com',  'delivered', 150.00, 0.42, '2023-01-15 09:23:00'),
    (2,  1002, 'bob@example.com',    'delivered', 89.99,  0.38, '2023-01-16 14:05:00'),
    (3,  1003, 'carol@example.com',  'shipped',   220.50, 0.51, '2023-02-01 11:30:00'),
    (4,  1001, 'alice@example.com',  'delivered', 45.00,  0.29, '2023-02-14 16:45:00'),
    (5,  1004, 'dave@example.com',   'cancelled', 175.00, 0.44, '2023-03-01 08:00:00'),
    (6,  1002, 'bob@example.com',    'delivered', 310.00, 0.55, '2023-03-15 13:20:00'),
    (7,  1005, 'eve@example.com',    'returned',  95.00,  0.33, '2023-04-01 10:10:00'),
    (8,  1003, 'carol@example.com',  'delivered', 430.00, 0.48, '2023-04-20 15:55:00')
;

SELECT * FROM ECOMMERCE.RAW.ORDERS_DEMO;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create a standard view
-- ══════════════════════════════════════════════════════════════
-- Standard views abstract complexity and present a clean
-- interface. Here we expose order data without the sensitive
-- profit_margin column — a common access pattern.

CREATE OR REPLACE VIEW ECOMMERCE.ANALYTICS.ORDERS_PUBLIC_V AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_total,
    DATE_TRUNC('month', created_at)     AS order_month,
    created_at
FROM ECOMMERCE.RAW.ORDERS_DEMO
WHERE order_status != 'cancelled'       -- business rule enforced in view
;

-- Query the view — behaves exactly like a table
SELECT * FROM ECOMMERCE.ANALYTICS.ORDERS_PUBLIC_V;

-- The view definition is visible to anyone with access
-- Run this to see the underlying SQL:
SELECT GET_DDL('VIEW', 'ECOMMERCE.ANALYTICS.ORDERS_PUBLIC_V');
-- You can see the full SELECT statement including the WHERE clause.
-- Anyone with access to this view can see your business logic.
-- This is the key weakness of standard views for sensitive use cases.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create a secure view
-- ══════════════════════════════════════════════════════════════
-- SECURE keyword is added before VIEW.
-- Same query, completely hidden definition.
-- Required for Snowflake data sharing (Goal 7).

CREATE OR REPLACE SECURE VIEW ECOMMERCE.ANALYTICS.ORDERS_SECURE_V AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_total,
    DATE_TRUNC('month', created_at)     AS order_month,
    created_at
FROM ECOMMERCE.RAW.ORDERS_DEMO
WHERE order_status != 'cancelled'
;

-- Query it — identical results to the standard view
SELECT * FROM ECOMMERCE.ANALYTICS.ORDERS_SECURE_V;

-- As ACCOUNTADMIN you can see the definition of both view types.
-- The real difference only shows when a lower-privilege user
-- tries to inspect the definition — demonstrated in Step 2b below.
SELECT GET_DDL('VIEW', 'ECOMMERCE.ANALYTICS.ORDERS_SECURE_V');

-- Check which views are secure via INFORMATION_SCHEMA
SELECT
    TABLE_NAME      AS view_name,
    VIEW_DEFINITION,
    IS_SECURE
FROM ECOMMERCE.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'ANALYTICS'
ORDER BY TABLE_NAME
;
-- IS_SECURE = YES for ORDERS_SECURE_V
-- IS_SECURE = NO  for ORDERS_PUBLIC_V
-- VIEW_DEFINITION is NULL for secure views when queried
-- by non-privileged roles — as ACCOUNTADMIN you see it here

-- ══════════════════════════════════════════════════════════════
-- STEP 2b: Prove the difference — create a user and test both views
-- ══════════════════════════════════════════════════════════════
-- We create a demo user with identical SELECT access on both views.
-- This user can query data from both — but can only inspect
-- the definition of the standard view, not the secure view.

-- Create a demo role and user
CREATE ROLE IF NOT EXISTS ANALYST_DEMO;
CREATE USER IF NOT EXISTS DEMO_USER
    PASSWORD             = 'Demo1234!'
    DEFAULT_ROLE         = ANALYST_DEMO
    MUST_CHANGE_PASSWORD = FALSE
    COMMENT              = 'Demo user for secure view exercise — drop after testing'
;

-- Grant role to demo user and to yourself for role-switching
GRANT ROLE ANALYST_DEMO TO USER DEMO_USER;
GRANT ROLE ANALYST_DEMO TO USER MBACCHUS;  -- replace with your Snowflake username
                                            -- run SELECT CURRENT_USER() if unsure

-- Grant all required privileges — all four levels are required
-- Missing any one of these breaks the access chain
GRANT USAGE  ON DATABASE  ECOMMERCE                          TO ROLE ANALYST_DEMO;
GRANT USAGE  ON SCHEMA    ECOMMERCE.ANALYTICS                TO ROLE ANALYST_DEMO;
GRANT USAGE  ON WAREHOUSE COMPUTE_WH                         TO ROLE ANALYST_DEMO;
GRANT SELECT ON VIEW      ECOMMERCE.ANALYTICS.ORDERS_PUBLIC_V  TO ROLE ANALYST_DEMO;
GRANT SELECT ON VIEW      ECOMMERCE.ANALYTICS.ORDERS_SECURE_V  TO ROLE ANALYST_DEMO;

-- ── TEST OPTION 1: Switch roles in this session ───────────────
-- Switch to ANALYST_DEMO role — note: you will see ACCOUNTADMIN
-- can still see secure view definitions. This is because
-- ACCOUNTADMIN privileges persist at the account level.
-- Use Test Option 2 for the true demonstration.

USE ROLE ANALYST_DEMO;
USE WAREHOUSE COMPUTE_WH;

-- Confirm you are running as the demo role
SELECT CURRENT_USER(), CURRENT_ROLE();

-- BOTH views return data — SELECT access works on both
SELECT * FROM ECOMMERCE.ANALYTICS.ORDERS_PUBLIC_V;
SELECT * FROM ECOMMERCE.ANALYTICS.ORDERS_SECURE_V;

-- Standard view — definition IS visible
SELECT GET_DDL('VIEW', 'ECOMMERCE.ANALYTICS.ORDERS_PUBLIC_V');
-- Returns full SQL including WHERE clause and column list.
-- Business logic is completely exposed.

-- Secure view — definition is NOT visible
SELECT GET_DDL('VIEW', 'ECOMMERCE.ANALYTICS.ORDERS_SECURE_V');
-- Expected result:
-- SQL compilation error: Object does not exist,
-- or operation cannot be performed.
-- This is CORRECT and EXPECTED — not a mistake.
-- Same SELECT privilege, definition completely protected.

-- Switch back to ACCOUNTADMIN
USE ROLE ACCOUNTADMIN;

-- ── TEST OPTION 2: Log in as DEMO_USER (recommended) ─────────
-- This gives the cleanest demonstration with no ACCOUNTADMIN
-- privilege bleed-through.
--
-- 1. Find your Snowflake login URL:
--    Run this query and copy the result:
SELECT CONCAT('https://', CURRENT_ACCOUNT(), '.snowflakecomputing.com') AS login_url;
--
-- 2. Open an incognito browser window
-- 3. Paste the URL and log in with:
--    Username : DEMO_USER
--    Password : Demo1234!
-- 4. Open a new worksheet and run:

--    USE WAREHOUSE COMPUTE_WH;
--    USE DATABASE ECOMMERCE;
--    USE SCHEMA ANALYTICS;

--    -- Confirm data access works on both views
--    SELECT * FROM ORDERS_PUBLIC_V;   -- returns data ✓
--    SELECT * FROM ORDERS_SECURE_V;   -- returns data ✓

--    -- Standard view — definition visible
--    SELECT GET_DDL('VIEW', 'ECOMMERCE.ANALYTICS.ORDERS_PUBLIC_V');
--    -- Returns full SQL ✓

--    -- Secure view — definition hidden
--    SELECT GET_DDL('VIEW', 'ECOMMERCE.ANALYTICS.ORDERS_SECURE_V');
--    -- SQL compilation error: Object does not exist... ✓
--    -- Definition is completely protected.

-- ── CLEANUP FOR STEP 2b ──────────────────────────────────────
-- Run after completing both tests above
DROP USER IF EXISTS DEMO_USER;
DROP ROLE IF EXISTS ANALYST_DEMO;


-- ══════════════════════════════════════════════════════════════
-- STEP 3: Create a materialized view
-- ══════════════════════════════════════════════════════════════
-- Materialized views pre-compute and store results.
-- Snowflake automatically refreshes them when base data changes.
-- Best for: expensive aggregations queried frequently.
-- Requires: Enterprise edition.
-- Limitation: single base table only — no joins allowed.

CREATE OR REPLACE MATERIALIZED VIEW ECOMMERCE.ANALYTICS.ORDERS_MV AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_total,
    created_at
FROM ECOMMERCE.RAW.ORDERS_DEMO
WHERE order_status = 'delivered'
;

-- Query the materialized view — should return 5 delivered rows
SELECT * FROM ECOMMERCE.ANALYTICS.ORDERS_MV
ORDER BY order_id
;
-- Expected: order_ids 1, 2, 4, 6, 8 (delivered orders only)
-- This result is pre-computed and stored — no re-execution
-- of the WHERE clause happens at query time.

-- Now insert a new delivered order into the base table
INSERT INTO ECOMMERCE.RAW.ORDERS_DEMO VALUES
    (10, 1006, 'frank@example.com', 'delivered', 280.00, 0.46, '2023-04-25 12:00:00')
;

-- Check refresh status before querying
--SHOW MATERIALIZED VIEWS IN SCHEMA ECOMMERCE.ANALYTICS;
-- Look at the refreshed_on column.
-- If behind_by shows > 0, force a manual refresh:
--ALTER MATERIALIZED VIEW ECOMMERCE.ANALYTICS.ORDERS_MV REFRESH;

-- Query again — should now return 6 rows including order_id 9
SELECT * FROM ECOMMERCE.ANALYTICS.ORDERS_MV
ORDER BY order_id
;
-- The new row appears without re-running any query logic.
-- Snowflake maintained the result automatically.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Compare view types in INFORMATION_SCHEMA
-- ══════════════════════════════════════════════════════════════

SELECT
    TABLE_NAME          AS view_name,
    IS_SECURE,
    IS_UPDATABLE
FROM ECOMMERCE.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'ANALYTICS'
ORDER BY TABLE_NAME
;
-- Note: materialized views do not appear in
-- INFORMATION_SCHEMA.VIEWS — they have their own view:

SELECT
    TABLE_NAME          AS materialized_view_name,
    TABLE_TYPE,
    LAST_ALTERED        AS last_refreshed
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'ANALYTICS'
  AND TABLE_TYPE   = 'MATERIALIZED VIEW'
;

-- Or use SHOW to see all views including materialized:
SHOW MATERIALIZED VIEWS IN SCHEMA ECOMMERCE.ANALYTICS;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Understand the naming convention
-- ══════════════════════════════════════════════════════════════
-- Snowflake has no enforced naming convention for views.
-- The _V and _MV suffixes used here are a common practice
-- that makes object types immediately clear in queries and
-- in INFORMATION_SCHEMA results.
--
-- Conventions used in this workbook:
--   ORDERS_PUBLIC_V    → standard view   (_V suffix)
--   ORDERS_SECURE_V    → secure view     (_V suffix, noted in comments)
--   ORDERS_MONTHLY_MV  → materialized    (_MV suffix)
--
-- Apply these conventions consistently in your own work.
-- Your future self and your teammates will thank you.

-- Verify all objects in ANALYTICS schema
SHOW OBJECTS IN SCHEMA ECOMMERCE.ANALYTICS;

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- Option 1 — Remove view type demo objects only
-- Use this if you are continuing to sub-task 1.5
-- ──────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS ECOMMERCE.ANALYTICS.ORDERS_MV;
DROP VIEW IF EXISTS ECOMMERCE.ANALYTICS.ORDERS_SECURE_V;
DROP VIEW IF EXISTS ECOMMERCE.ANALYTICS.ORDERS_PUBLIC_V;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_DEMO;

-- Verify
SHOW OBJECTS IN SCHEMA ECOMMERCE.ANALYTICS;
-- Should return zero rows

-- Option 2 — Full reset, drop the entire ECOMMERCE database
-- NOTE: Sub-task 1.5 SETUP block will recreate everything needed
-- ──────────────────────────────────────────────────────────────
-- DROP DATABASE IF EXISTS ECOMMERCE;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a standard view called ORDERS_DELIVERED_V in
--    ECOMMERCE.ANALYTICS that shows only delivered orders
--    and excludes the customer_email and profit_margin columns.
--    Run GET_DDL on it — can you see the WHERE clause?
--
-- 2. Convert it to a secure view called ORDERS_DELIVERED_SECURE_V.
--    Run GET_DDL on it as ACCOUNTADMIN — you can still see it.
--    Now create a new role called ANALYST_ROLE, grant it SELECT
--    on the view, switch to that role, and run GET_DDL again.
--    What happens?
--    (Hint: USE ROLE ANALYST_ROLE; after granting access)
--
-- 3. Create a materialized view called CUSTOMER_ORDER_SUMMARY_MV
--    that shows total orders and total revenue per customer_id
--    from ORDERS_DEMO. Insert two new rows into ORDERS_DEMO
--    for an existing customer_id. Query the materialized view
--    — does the summary update automatically?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I try to JOIN two tables in a materialized view?
-- A: It will fail. Materialized views in Snowflake support only
--    a single base table. If you need to pre-compute joined
--    results, use a Dynamic Table instead (Goal 6, Sub-task 6.5)
--    which supports multi-table transformations with automatic
--    refresh.
--
-- Q: What if the base table of a materialized view is updated
--    frequently — does that cause problems?
-- A: Snowflake handles refresh automatically but high-frequency
--    updates increase background compute costs. For tables
--    updated every few seconds, a materialized view may not
--    be cost-effective. Consider a standard view or Dynamic
--    Table instead.
--
-- Q: What if I want to share a standard view with another
--    Snowflake account?
-- A: You cannot. Data sharing in Snowflake requires secure views.
--    The definition must be hidden to protect your business logic
--    from the consumer account. Convert to a secure view first.
--    Covered in Goal 7 (Sub-task 7.1).
--
-- Q: Can I make a materialized view secure?
-- A: Yes — CREATE OR REPLACE SECURE MATERIALIZED VIEW.
--    Combines pre-computation with definition hiding.
--    Required if you want to share a materialized view
--    externally via Snowflake data sharing.
--
-- Q: What if I need to refresh a materialized view manually?
-- A: ALTER MATERIALIZED VIEW view_name REFRESH;
--    Snowflake refreshes automatically but you can force
--    an immediate refresh if needed — for example after a
--    large bulk load where you do not want to wait.