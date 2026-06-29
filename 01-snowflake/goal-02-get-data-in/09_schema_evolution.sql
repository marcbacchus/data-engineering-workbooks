-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 2 : Get Data In
-- Sub-task 2.9 : Manage schema evolution
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~25 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight (all steps)
-- Prerequisites    : 03_copy_into.sql completed
--                    All 8 CSV tables loaded in ECOMMERCE.RAW
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
--                    Domain 5 — Data Transformations (17%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Schemas change. Source systems add columns, rename fields,
--   change data types. The tables you create today will not
--   look the same in six months.
--
--   How you handle schema changes determines whether your
--   pipelines break or adapt gracefully. This sub-task covers
--   the DDL commands practitioners use every day to evolve
--   table structures safely — without breaking downstream
--   queries, views, or dependent objects.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: SCHEMA EVOLUTION IN SNOWFLAKE
-- ══════════════════════════════════════════════════════════════
--
-- Snowflake supports online DDL — most schema changes happen
-- immediately without locking the table or blocking queries.
-- This is a significant advantage over traditional databases
-- where ALTER TABLE can lock tables for minutes or hours.
--
-- KEY DDL COMMANDS:
--   ALTER TABLE ... ADD COLUMN      — add a new column
--   ALTER TABLE ... DROP COLUMN     — remove a column
--   ALTER TABLE ... RENAME COLUMN   — rename a column
--   ALTER TABLE ... ALTER COLUMN    — change type, default, nullability
--   ALTER TABLE ... RENAME TO       — rename the table
--   ALTER TABLE ... SWAP WITH       — atomic swap between two tables
--
-- SAFE SCHEMA EVOLUTION PATTERNS:
--   · Add nullable columns first, populate later
--   · Never change a column type that downstream depends on
--   · Use RENAME not DROP when retiring columns
--   · Use SWAP for zero-downtime table replacements
--   · Clone before destructive changes (Goal 8)
--
-- SEQUENCES AND IDENTITY:
--   Snowflake provides sequences and identity columns for
--   auto-incrementing primary keys — covered in Step 6.
--
-- Oracle equivalent:
--   Oracle ALTER TABLE works similarly but locks tables during
--   some operations. Snowflake ALTER TABLE is nearly always
--   online (non-blocking). SWAP has no Oracle equivalent —
--   the closest is RENAME with multiple steps.
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Create a working copy of SUPPLIERS for safe DDL exercises
-- We never alter the original loaded table
CREATE OR REPLACE TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
    CLONE ECOMMERCE.RAW.SUPPLIERS
    COMMENT = 'Schema evolution demo — safe to modify'
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.SUPPLIERS_EVOLVE;
-- Expected: 1,000 — identical to SUPPLIERS

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Add a new column safely
-- ══════════════════════════════════════════════════════════════
-- The safest schema change — adding a column.
-- New columns are always nullable by default which means
-- existing rows get NULL for the new column.
-- Downstream queries that do not reference the new column
-- are completely unaffected.

-- Check current columns
SHOW COLUMNS IN TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE;

-- Add a new column
ALTER TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
    ADD COLUMN rating FLOAT
    COMMENT 'Supplier quality rating 1-5 — added in v2'
;

-- Add multiple columns in one statement
-- List all columns after ADD COLUMN separated by commas
-- No parentheses needed
ALTER TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE ADD COLUMN 
    last_order_date    DATE        COMMENT 'Date of most recent order',
    contract_value     FLOAT       COMMENT 'Annual contract value USD',
    preferred_supplier BOOLEAN     DEFAULT FALSE
;

-- Verify the new columns exist
SHOW COLUMNS IN TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE;

-- New columns are NULL for existing rows
SELECT
    supplier_id,
    supplier_name,
    rating,             -- NULL for all existing rows
    preferred_supplier  -- FALSE (has default)
FROM ECOMMERCE.RAW.SUPPLIERS_EVOLVE
LIMIT 5
;

-- Populate the new column for some rows
UPDATE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
    SET rating = ROUND(UNIFORM(3.0, 5.0, RANDOM()), 1)
WHERE is_active = TRUE
;

SELECT
    supplier_id,
    supplier_name,
    rating,
    is_active
FROM ECOMMERCE.RAW.SUPPLIERS_EVOLVE
WHERE is_active = TRUE
ORDER BY rating DESC
LIMIT 10
;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Rename a column
-- ══════════════════════════════════════════════════════════════
-- Renaming is safer than dropping — dependent queries can be
-- updated gradually. Use RENAME before DROP in production.

-- Rename contact_name to primary_contact (clearer naming)
ALTER TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
    RENAME COLUMN contact_name TO primary_contact
;

-- Verify the rename
SELECT supplier_id, primary_contact, contact_email
FROM ECOMMERCE.RAW.SUPPLIERS_EVOLVE
LIMIT 5
;

-- Note: any views or queries that referenced contact_name
-- will now fail. Always update dependent objects after renaming.
-- In production: rename column → update all dependencies → done.

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Modify a column
-- ══════════════════════════════════════════════════════════════
-- ALTER COLUMN supports a limited set of changes:
--   · NOT NULL constraint  — add or remove
--   · Column comment       — update description
--   · Data type widening   — VARCHAR(100) → VARCHAR(200)
--
-- NOT supported on existing columns:
--   · SET DEFAULT          — must be set at column creation
--   · Incompatible type changes (VARCHAR → INTEGER, FLOAT → INTEGER)

-- Add a NOT NULL constraint to supplier_name
-- Only works if no NULLs exist in the column
ALTER TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
    ALTER COLUMN supplier_name SET NOT NULL
;

-- Widen a VARCHAR column — always safe
ALTER TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
    ALTER COLUMN phone TYPE VARCHAR(200)
;

-- Update column comment
ALTER TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
    ALTER COLUMN rating COMMENT 'Supplier quality rating 1.0-5.0 — updated quarterly'
;

-- Verify changes
SHOW COLUMNS IN TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE;

-- ── Column default note ───────────────────────────────────────
-- Snowflake does not support ALTER COLUMN SET DEFAULT on
-- existing columns. Defaults must be set at column creation.
-- To verify preferred_supplier has its DEFAULT FALSE from creation:
SELECT
    COLUMN_NAME,
    COLUMN_DEFAULT,
    IS_NULLABLE
FROM ECOMMERCE.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME   = 'SUPPLIERS_EVOLVE'
  AND TABLE_SCHEMA = 'RAW'
  AND COLUMN_NAME  IN ('PREFERRED_SUPPLIER', 'SUPPLIER_NAME', 'PHONE')
ORDER BY ORDINAL_POSITION
;

-- ── Type change restrictions ───────────────────────────────────
-- Snowflake allows widening type changes but NOT narrowing:
--   VARCHAR(200) → VARCHAR(500)  ✓ widening — allowed
--   INTEGER → FLOAT              ✓ widening — allowed
--   VARCHAR → INTEGER            ✗ incompatible — not allowed
--   FLOAT → INTEGER              ✗ narrowing — not allowed
--   VARCHAR(200) → VARCHAR(100)  ✗ narrowing — not allowed
--
-- For incompatible type changes:
--   1. ADD new column with correct type
--   2. UPDATE new column from old using TRY_CAST
--   3. Verify no NULLs from failed casts
--   4. DROP old column
--   5. RENAME new column to old name

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Drop a column
-- ══════════════════════════════════════════════════════════════
-- Dropping a column is destructive — data is permanently lost.
-- Best practice: rename first, verify no dependencies, then drop.

-- First check if anything depends on contract_value
-- (in production check views, tasks, and stored procedures too)
SELECT *
FROM ECOMMERCE.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME   = 'SUPPLIERS_EVOLVE'
  AND COLUMN_NAME  = 'CONTRACT_VALUE'
  AND TABLE_SCHEMA = 'RAW'
;

-- Drop the column
ALTER TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
    DROP COLUMN contract_value
;

-- Verify it is gone
SHOW COLUMNS IN TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE;

-- Note: Time Travel can recover dropped column DATA if you
-- need to restore it — but the column definition is gone.
-- You would need to re-add the column and populate from
-- a Time Travel query:
--   SELECT contract_value
--   FROM ECOMMERCE.RAW.SUPPLIERS_EVOLVE
--   BEFORE (STATEMENT => '<query_id_of_drop>')
-- Covered in Goal 8.

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Rename and swap tables
-- ══════════════════════════════════════════════════════════════
-- TABLE SWAP is one of Snowflake's most powerful operational
-- features — atomic swap of two tables with no downtime.
-- Used for zero-downtime deployments: build new → swap → done.

-- Create a "new version" of the suppliers table
-- (simulating a full reload with schema changes)
CREATE OR REPLACE TABLE ECOMMERCE.RAW.SUPPLIERS_NEW
    CLONE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
;

-- Add a new column to the new version
ALTER TABLE ECOMMERCE.RAW.SUPPLIERS_NEW
    ADD COLUMN supplier_tier VARCHAR(20) DEFAULT 'standard'
;

UPDATE ECOMMERCE.RAW.SUPPLIERS_NEW
    SET supplier_tier = CASE
        WHEN rating >= 4.5 THEN 'platinum'
        WHEN rating >= 4.0 THEN 'gold'
        WHEN rating >= 3.5 THEN 'silver'
        ELSE 'standard'
    END
WHERE rating IS NOT NULL
;

-- Verify the new table looks right
SELECT supplier_id, supplier_name, rating, supplier_tier
FROM ECOMMERCE.RAW.SUPPLIERS_NEW
WHERE rating IS NOT NULL
LIMIT 5
;

-- ATOMIC SWAP — happens instantaneously, no downtime
-- Any query hitting SUPPLIERS_EVOLVE after this swap
-- will see the new table's data and schema immediately
ALTER TABLE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
    SWAP WITH ECOMMERCE.RAW.SUPPLIERS_NEW
;

-- Verify SUPPLIERS_EVOLVE now has the new schema
SELECT supplier_id, supplier_name, rating, supplier_tier
FROM ECOMMERCE.RAW.SUPPLIERS_EVOLVE
LIMIT 5
;
-- supplier_tier column now exists in SUPPLIERS_EVOLVE
-- SUPPLIERS_NEW now contains the old version (pre-swap)

-- Clean up the old version
DROP TABLE IF EXISTS ECOMMERCE.RAW.SUPPLIERS_NEW;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Sequences and identity columns
-- ══════════════════════════════════════════════════════════════
-- Snowflake provides sequences and identity columns for
-- auto-incrementing surrogate keys — common in dimension tables.

-- ── IDENTITY column ───────────────────────────────────────────
-- Defined at column creation — auto-increments on INSERT
CREATE OR REPLACE TABLE ECOMMERCE.RAW.SEQUENCE_DEMO (
    id          INTEGER         AUTOINCREMENT PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL,
    created_at  TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
)
;

INSERT INTO ECOMMERCE.RAW.SEQUENCE_DEMO (name) VALUES
    ('Alpha'), ('Beta'), ('Gamma'), ('Delta')
;

SELECT * FROM ECOMMERCE.RAW.SEQUENCE_DEMO ORDER BY id;
-- Expected: ids 1, 2, 3, 4

-- ── Important: Snowflake sequence caching behaviour ───────────
-- Snowflake caches sequence values in blocks for performance.
-- If you run the same INSERT again or start a new session,
-- the next block of IDs may jump significantly:
--   First INSERT:  1, 2, 3, 4
--   Second INSERT: 101, 102, 103, 104  (new cache block)
--
-- This means Snowflake AUTOINCREMENT sequences are:
--   · Unique        ✓ — no duplicates ever
--   · Monotonically increasing ✓ — always goes up
--   · NOT strictly sequential ✗ — gaps are expected and normal
--
-- Oracle sequences with NOCACHE are strictly sequential.
-- Snowflake prioritises performance over strict sequencing.
-- If your application depends on sequential IDs with no gaps,
-- use a different approach — Snowflake sequences are not
-- designed for that guarantee.
--
-- For surrogate keys in data warehousing, gaps do not matter —
-- uniqueness is what counts.

-- ── Standalone SEQUENCE object ────────────────────────────────
-- More flexible — can be used across multiple tables

-- Create a sequence with no caching (strictly sequential)
CREATE OR REPLACE SEQUENCE ECOMMERCE.RAW.SUPPLIER_SEQ_NOCACHE
    START     = 1
    INCREMENT = 1
    ORDER               -- guarantees sequential order, no gaps
    COMMENT   = 'Strictly sequential sequence — no caching'
;

CREATE OR REPLACE SEQUENCE ECOMMERCE.RAW.SUPPLIER_SEQ
    START     = 10000
    INCREMENT = 1
    CACHE     = 1       -- cache only 1 value = effectively no caching
    ORDER,
    COMMENT = 'Sequence for supplier surrogate keys starting at 10000'
;

--No caching (ORDER is missing)
CREATE OR REPLACE SEQUENCE ECOMMERCE.RAW.SUPPLIER_SEQ
    START = 10000
    INCREMENT = 1
    COMMENT = 'Sequence for supplier surrogate keys starting at 10000'
;

-- ORDER / CACHE=1  → strictly sequential, no gaps
--                  → slower — Snowflake must coordinate across nodes
--                  → not recommended for high-concurrency inserts
-- 
-- NOORDER (default) → gaps possible between sessions/caches
--                   → much faster — each node has its own cache block
--                   → fine for surrogate keys in data warehousing

-- Use the sequence in an INSERT
INSERT INTO ECOMMERCE.RAW.SEQUENCE_DEMO (id, name) VALUES
    (ECOMMERCE.RAW.SUPPLIER_SEQ.NEXTVAL, 'Epsilon'),
    (ECOMMERCE.RAW.SUPPLIER_SEQ.NEXTVAL, 'Zeta')
;

SELECT * FROM ECOMMERCE.RAW.SEQUENCE_DEMO ORDER BY id;
-- New rows get IDs from the sequence: 10000, 10001
-- Mixed with auto-increment IDs from earlier inserts

-- Get the current sequence value
--Snowflake does not have a CURRVAL
--SELECT ECOMMERCE.RAW.SUPPLIER_SEQ.CURRVAL AS current_value;

-- Note: Snowflake does not support CURRVAL like Oracle sequences.
-- Use SHOW SEQUENCES to inspect the current sequence state:
SHOW SEQUENCES LIKE 'SUPPLIER_SEQ';

SELECT "next_value"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- next_value shows what the sequence will generate next
-- This is the Snowflake equivalent of Oracle's CURRVAL

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Safe DDL patterns for production
-- ══════════════════════════════════════════════════════════════
-- A checklist of safe practices for schema changes in production.

-- ── Pattern 1: Add nullable before populating ─────────────────
-- WRONG (breaks if NOT NULL before data exists):
-- ALTER TABLE t ADD COLUMN new_col INTEGER NOT NULL;
--
-- RIGHT (add nullable, populate, then constrain):
-- ALTER TABLE t ADD COLUMN new_col INTEGER;
-- UPDATE t SET new_col = <value>;
-- ALTER TABLE t ALTER COLUMN new_col SET NOT NULL;

-- ── Pattern 2: Clone before destructive changes ───────────────
-- Before dropping columns or doing bulk updates:
CREATE TABLE ECOMMERCE.RAW.SUPPLIERS_BACKUP
    CLONE ECOMMERCE.RAW.SUPPLIERS_EVOLVE
;
-- Zero-copy clone — instant, no extra storage until data diverges
-- Drop the backup when you are confident the change is good
-- DROP TABLE ECOMMERCE.RAW.SUPPLIERS_BACKUP;

-- ── Pattern 3: Verify with INFORMATION_SCHEMA before dropping ─
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMN_DEFAULT,
    COMMENT
FROM ECOMMERCE.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME   = 'SUPPLIERS_EVOLVE'
  AND TABLE_SCHEMA = 'RAW'
ORDER BY ORDINAL_POSITION
;
-- Always know exactly what you have before changing it.

-- ── Pattern 4: Use SWAP not RENAME for zero-downtime deploys ──
-- If you RENAME a table that is being queried, in-flight queries
-- will fail. SWAP is atomic — the switchover is instantaneous.
-- BUILD new table → verify → SWAP → drop old table.

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════

DROP TABLE    IF EXISTS ECOMMERCE.RAW.SUPPLIERS_EVOLVE;
DROP TABLE    IF EXISTS ECOMMERCE.RAW.SUPPLIERS_NEW;
DROP TABLE    IF EXISTS ECOMMERCE.RAW.SUPPLIERS_BACKUP;
DROP TABLE    IF EXISTS ECOMMERCE.RAW.SEQUENCE_DEMO;
DROP SEQUENCE IF EXISTS ECOMMERCE.RAW.SUPPLIER_SEQ;
DROP SEQUENCE IF EXISTS ECOMMERCE.RAW.SUPPLIER_SEQ_NOCACHE;

-- Verify
SHOW TABLES IN SCHEMA ECOMMERCE.RAW;
-- Should show 10 tables — the original 8 CSV tables
-- plus PRODUCT_REVIEWS_JSON and PRODUCT_REVIEWS_PARQUET
-- created in Sub-task 2.5. All schema evolution demo tables
-- (SUPPLIERS_EVOLVE, SUPPLIERS_NEW, SUPPLIERS_BACKUP,
-- SEQUENCE_DEMO) should be gone.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Clone ECOMMERCE.RAW.PRODUCTS into PRODUCTS_EVOLVE.
--    Add these columns one at a time:
--    · discontinued BOOLEAN DEFAULT FALSE
--    · replacement_product_id INTEGER (nullable)
--    · last_updated TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
--    After adding, UPDATE discontinued = TRUE for all products
--    in the 'Automotive' category.
--    How many rows were updated?
--
-- 2. Create a table called ORDER_STAGING with an AUTOINCREMENT
--    primary key column called staging_id, plus order_id,
--    customer_id, and load_timestamp columns.
--    Insert 5 rows without specifying staging_id.
--    Confirm auto-increment worked correctly.
--
-- 3. Clone PRODUCTS_EVOLVE into PRODUCTS_V2.
--    Add a calculated column category_code VARCHAR(10) and
--    populate it with the first 3 characters of category.
--    SWAP PRODUCTS_EVOLVE with PRODUCTS_V2.
--    Verify PRODUCTS_EVOLVE now has category_code.
--    What happened to PRODUCTS_V2 after the swap?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I need to change a column from VARCHAR to INTEGER
--    but data already exists?
-- A: You cannot directly change incompatible types.
--    The safe pattern:
--    1. ADD COLUMN new_col INTEGER
--    2. UPDATE t SET new_col = TRY_CAST(old_col AS INTEGER)
--    3. Check for NULLs (TRY_CAST returns NULL on failure)
--    4. DROP COLUMN old_col
--    5. RENAME COLUMN new_col TO old_col
--    TRY_CAST is safer than CAST — returns NULL instead of erroring.
--
-- Q: What if a downstream view breaks after a column rename?
-- A: The view will fail with "column not found" on next query.
--    Best practice: use SHOW VIEWS to find all views, check
--    each definition for the old column name, update them.
--    In production: communicate schema changes to all teams
--    BEFORE making them. Schema changes are team-level decisions.
--
-- Q: What if SWAP fails because the tables have different schemas?
-- A: SWAP works regardless of schema differences — it swaps
--    the entire table objects including their schemas.
--    After swap, the table names point to different schemas.
--    This is the feature that makes it useful for deployments —
--    you can swap old and new schemas atomically.
--
-- Q: What if I accidentally drop a column with important data?
-- A: Use Time Travel to recover the data:
--    SELECT dropped_column
--    FROM table
--    BEFORE (STATEMENT => '<query_id_of_alter_table_drop>');
--    Then re-add the column and populate from the Time Travel
--    query. Covered in detail in Goal 8.
--
-- Q: What is the Oracle equivalent of SWAP?
-- A: Oracle has no direct equivalent. The closest pattern is:
--    RENAME old_table TO old_table_backup;
--    RENAME new_table TO old_table;
--    These are two separate operations — not atomic.
--    Between the two renames, the table does not exist and
--    any query will fail. Snowflake's SWAP has no downtime.