-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 3  : Query and Transform Data
-- Sub-task 3.5 : DML and transactions
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : 04_ctes.sql completed
-- COF-C03 domain   : Domain 5 — Data Transformations (17%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   SELECT reads data. DML changes it.
--   INSERT, UPDATE, DELETE, and MERGE are the four DML commands
--   that modify rows in Snowflake tables.
--
--   This sub-task covers each command on a working copy of the
--   e-commerce dataset — we never modify the original loaded
--   tables. It also covers transactions — the mechanism that
--   ensures your DML either completes fully or not at all.
--
--   The most important thing to know before writing a single
--   line of DML in Snowflake: AUTOCOMMIT = TRUE by default.
--   Every statement commits the moment it completes.
--   A DELETE without BEGIN is permanent. There is no implicit
--   ROLLBACK safety net. Covered in depth in Step 2.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: DML COMMANDS
-- ══════════════════════════════════════════════════════════════
--
-- INSERT  — add new rows to a table
-- UPDATE  — modify existing rows (with WHERE — otherwise all rows affected)
-- DELETE  — remove rows (with WHERE — otherwise all rows affected)
-- TRUNCATE — remove all rows instantly (faster than DELETE)
-- MERGE   — upsert — insert new rows, update existing ones
--           in a single atomic statement
--
-- TRUNCATE vs DELETE:
--   DELETE FROM table               → slow, logged, Time Travel recoverable
--   DELETE FROM table WHERE 1=1     → same as above, all rows
--   TRUNCATE TABLE table            → fast, minimal logging,
--                                     NOT recoverable via Time Travel
--                                     for the truncated data
--   Use DELETE when you need row-level control or Time Travel recovery.
--   Use TRUNCATE when you need to empty a table fast and
--   recovery is not a concern (staging tables, temp tables).
--
-- Oracle equivalent:
--   Same DML syntax — INSERT, UPDATE, DELETE, MERGE all work
--   identically. Key difference: Oracle AUTOCOMMIT = FALSE by
--   default. Snowflake AUTOCOMMIT = TRUE. This is the single
--   most dangerous difference for Oracle practitioners.
--
-- ══════════════════════════════════════════════════════════════
-- SETUP — create working copies to protect original tables
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Create working copies — zero-copy clones (instant, no extra storage)
-- We NEVER run DML on the original loaded tables
CREATE OR REPLACE TABLE ECOMMERCE.RAW.PRODUCTS_WORK
    CLONE ECOMMERCE.RAW.PRODUCTS
    COMMENT = 'DML exercises working copy — safe to modify'
;

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_WORK
    CLONE ECOMMERCE.RAW.ORDERS
    COMMENT = 'DML exercises working copy — safe to modify'
;

SELECT COUNT(*) AS products_rows FROM ECOMMERCE.RAW.PRODUCTS_WORK;
-- Expected: 10,000
SELECT COUNT(*) AS orders_rows FROM ECOMMERCE.RAW.ORDERS_WORK;
-- Expected: 2,000,000

-- ══════════════════════════════════════════════════════════════
-- STEP 1: INSERT — adding new rows
-- ══════════════════════════════════════════════════════════════

-- INSERT single row
INSERT INTO ECOMMERCE.RAW.PRODUCTS_WORK (
    product_id,
    product_name,
    category,
    subcategory,
    supplier_id,
    unit_price,
    cost_price,
    weight_kg,
    is_active,
    created_at
)
VALUES (
    99001,
    'Workbook Test Product',
    'Test Category',
    'Test Subcategory',
    1,
    49.99,
    25.00,
    0.5,
    TRUE,
    CURRENT_TIMESTAMP()
)
;

-- Verify the insert
SELECT * FROM ECOMMERCE.RAW.PRODUCTS_WORK WHERE product_id = 99001;

-- INSERT multiple rows in one statement
INSERT INTO ECOMMERCE.RAW.PRODUCTS_WORK (
    product_id, product_name, category, subcategory,
    supplier_id, unit_price, cost_price, weight_kg,
    is_active, created_at
)
VALUES
    (99002, 'Workbook Product 2', 'Test Category', 'Sub A', 1, 29.99, 15.00, 0.3, TRUE, CURRENT_TIMESTAMP()),
    (99003, 'Workbook Product 3', 'Test Category', 'Sub B', 1, 79.99, 40.00, 1.2, TRUE, CURRENT_TIMESTAMP()),
    (99004, 'Workbook Product 4', 'Test Category', 'Sub C', 2, 19.99, 10.00, 0.2, FALSE, CURRENT_TIMESTAMP())
;

SELECT COUNT(*) AS test_products
FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE product_id >= 99001
;
-- Expected: 4

-- INSERT ... SELECT — insert results of a query
-- Useful for populating summary or staging tables
CREATE OR REPLACE TABLE ECOMMERCE.RAW.HIGH_VALUE_ORDERS AS
SELECT
    order_id,
    customer_id,
    order_total,
    created_at,
    'high_value'    AS order_tier
FROM ECOMMERCE.RAW.ORDERS_WORK
WHERE order_total >= 500
  AND order_status = 'delivered'
;

SELECT COUNT(*) AS high_value_count FROM ECOMMERCE.RAW.HIGH_VALUE_ORDERS;
-- High-value delivered orders

-- ══════════════════════════════════════════════════════════════
-- STEP 2: The AUTOCOMMIT trap — critical reminder
-- ══════════════════════════════════════════════════════════════
-- Covered in depth in Goal 1 Sub-task 1.8.
-- Revisited here because it matters most when running DML.
--
-- AUTOCOMMIT = TRUE in Snowflake (default)
-- Every DML statement commits the moment it completes.
--
-- ┌─────────────────────────────────────────────────────────┐
-- │  DELETE FROM table WHERE condition;                     │
-- │  -- Already committed. ROLLBACK has no effect.          │
-- │  ROLLBACK; -- too late                                  │
-- └─────────────────────────────────────────────────────────┘
--
-- The ONLY safe pattern for destructive DML:
-- ┌─────────────────────────────────────────────────────────┐
-- │  BEGIN;                                                 │
-- │      DELETE FROM table WHERE condition;                 │
-- │      SELECT COUNT(*) FROM table; -- verify first        │
-- │  COMMIT;  -- only when satisfied                        │
-- │  -- or ROLLBACK; if something looks wrong               │
-- └─────────────────────────────────────────────────────────┘
--
-- Demonstrate AUTOCOMMIT behaviour:

-- Without BEGIN — commits immediately
DELETE FROM ECOMMERCE.RAW.PRODUCTS_WORK WHERE product_id = 99004;
ROLLBACK; -- has NO effect — already committed

SELECT * FROM ECOMMERCE.RAW.PRODUCTS_WORK WHERE product_id = 99004;
-- Returns 0 rows — row is gone, ROLLBACK did nothing

-- With BEGIN — transaction is open, ROLLBACK works
BEGIN;
    DELETE FROM ECOMMERCE.RAW.PRODUCTS_WORK WHERE product_id = 99003;
    --SELECT * FROM ECOMMERCE.RAW.PRODUCTS_WORK WHERE product_id = 99003;
    -- Row appears deleted within the transaction
ROLLBACK; -- undo the delete

SELECT * FROM ECOMMERCE.RAW.PRODUCTS_WORK WHERE product_id = 99003;
-- Row is back — ROLLBACK worked because BEGIN was used

-- ══════════════════════════════════════════════════════════════
-- STEP 3: UPDATE — modifying existing rows
-- ══════════════════════════════════════════════════════════════
-- UPDATE requires a WHERE clause in production.
-- UPDATE without WHERE modifies EVERY row in the table.
-- Always run a SELECT with the same WHERE first to verify scope.

-- Always verify scope before UPDATE
SELECT COUNT(*) AS rows_to_update
FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE category = 'Test Category'
;
-- Confirm you know how many rows will be affected

-- UPDATE with WHERE — safe
UPDATE ECOMMERCE.RAW.PRODUCTS_WORK
    SET unit_price = unit_price * 1.10,  -- 10% price increase
        cost_price = cost_price * 1.05   -- 5% cost increase
WHERE category = 'Test Category'
  AND is_active = TRUE
;

-- Verify the update
SELECT
    product_id,
    product_name,
    unit_price,
    cost_price
FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE category = 'Test Category'
ORDER BY product_id
;

-- UPDATE using a subquery — update based on data from another table
-- Deactivate products from suppliers with no active products
UPDATE ECOMMERCE.RAW.PRODUCTS_WORK
    SET is_active = FALSE
WHERE supplier_id IN (
    SELECT supplier_id
    FROM ECOMMERCE.RAW.SUPPLIERS
    WHERE is_active = FALSE
)
;

SELECT COUNT(*) AS deactivated
FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE is_active = FALSE
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: DELETE — removing rows safely
-- ══════════════════════════════════════════════════════════════
-- Same pattern as UPDATE: verify scope first, then delete.
-- Use BEGIN/COMMIT for any destructive DELETE in production.

-- Verify scope first
SELECT COUNT(*) AS rows_to_delete
FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE category = 'Test Category'
;

-- Safe DELETE pattern with explicit transaction
BEGIN;

DELETE FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE category = 'Test Category'
;

-- Verify result before committing
SELECT COUNT(*) AS remaining_test_products
FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE category = 'Test Category'
;
-- Expected: 0

-- Only commit when satisfied
COMMIT;

-- Confirm committed
SELECT COUNT(*) AS total_products FROM ECOMMERCE.RAW.PRODUCTS_WORK;
-- Expected: 9,997 (10,000 original - 3 test products we deleted)
-- Note: product 99004 was deleted earlier without BEGIN

-- ══════════════════════════════════════════════════════════════
-- STEP 5: TRUNCATE — emptying a table instantly
-- ══════════════════════════════════════════════════════════════
-- TRUNCATE removes all rows from a table instantly.
-- Much faster than DELETE for large tables.
-- Cannot be rolled back — does not participate in transactions.
-- Use for staging tables, temp tables, and tables you reload completely.

-- Create a staging table to demonstrate TRUNCATE
CREATE OR REPLACE TRANSIENT TABLE ECOMMERCE.RAW.ORDERS_STAGING
    CLONE ECOMMERCE.RAW.ORDERS_WORK
    COMMENT = 'Staging table — transient, TRUNCATE safe to use'
;

SELECT COUNT(*) AS staging_rows FROM ECOMMERCE.RAW.ORDERS_STAGING;
-- Expected: 2,000,000

-- TRUNCATE — instant, all rows gone
TRUNCATE TABLE ECOMMERCE.RAW.ORDERS_STAGING;

SELECT COUNT(*) AS staging_rows FROM ECOMMERCE.RAW.ORDERS_STAGING;
-- Expected: 0

-- Table structure preserved — only data is removed
SHOW COLUMNS IN TABLE ECOMMERCE.RAW.ORDERS_STAGING;
-- All columns still exist

-- ══════════════════════════════════════════════════════════════
-- STEP 6: MERGE — upsert in one atomic statement
-- ══════════════════════════════════════════════════════════════
-- MERGE combines INSERT and UPDATE into one statement.
-- For each row in the source:
--   · If it matches a row in the target → UPDATE
--   · If it does not match → INSERT
-- This is called an UPSERT (update or insert).
--
-- MERGE is the standard pattern for:
--   · Loading incremental data (new + changed records)
--   · Synchronising two tables
--   · SCD Type 1 (slowly changing dimensions)

-- Create a small source table with new and updated products
CREATE OR REPLACE TEMPORARY TABLE product_updates AS
SELECT * FROM VALUES
    -- Existing product — will be UPDATED (product_id exists)
    (1, 'Updated Product Name', 'Electronics', 'Gadgets', 1, 999.99, 500.00, 0.8, TRUE, CURRENT_TIMESTAMP()),
    -- New product — will be INSERTED (product_id does not exist)
    (99999, 'Brand New Product', 'Electronics', 'Gadgets', 1, 149.99, 75.00, 0.5, TRUE, CURRENT_TIMESTAMP())
AS t(product_id, product_name, category, subcategory, supplier_id,
     unit_price, cost_price, weight_kg, is_active, created_at)
;

-- MERGE — upsert source into target
MERGE INTO ECOMMERCE.RAW.PRODUCTS_WORK AS target
USING product_updates AS source
    ON target.product_id = source.product_id   -- match condition

-- When a match is found → UPDATE
WHEN MATCHED THEN
    UPDATE SET
        target.product_name = source.product_name,
        target.unit_price   = source.unit_price,
        target.cost_price   = source.cost_price,
        target.is_active    = source.is_active

-- When no match is found → INSERT
WHEN NOT MATCHED THEN
    INSERT (product_id, product_name, category, subcategory,
            supplier_id, unit_price, cost_price, weight_kg,
            is_active, created_at)
    VALUES (source.product_id, source.product_name, source.category,
            source.subcategory, source.supplier_id, source.unit_price,
            source.cost_price, source.weight_kg, source.is_active,
            source.created_at)
;
-- Output shows: number of rows inserted, updated, deleted

-- Verify: existing product updated
SELECT product_id, product_name, unit_price
FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE product_id = 1
;
-- product_name and unit_price should show the updated values

-- Verify: new product inserted
SELECT product_id, product_name, unit_price
FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE product_id = 99999
;
-- New row exists

-- MERGE also supports WHEN NOT MATCHED BY SOURCE (delete unmatched)
-- and multiple WHEN MATCHED conditions — covered in Goal 6
-- (Automate Pipelines) where MERGE is used for CDC patterns.

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Transaction control
-- ══════════════════════════════════════════════════════════════
-- Transactions group multiple DML statements into one atomic unit.
-- Either ALL statements succeed and commit, or ALL are rolled back.
-- This is the foundation of data integrity.

-- Multi-statement transaction — all or nothing
BEGIN;

-- Statement 1: deactivate a product
UPDATE ECOMMERCE.RAW.PRODUCTS_WORK
    SET is_active = FALSE
WHERE product_id = 99999
;

-- Statement 2: verify the update within the same transaction
SELECT product_id, product_name, is_active
FROM ECOMMERCE.RAW.PRODUCTS_WORK
WHERE product_id = 99999
;
-- is_active = FALSE confirmed — safe to commit

COMMIT;

-- If either statement failed you would ROLLBACK:
-- ROLLBACK; -- undoes BOTH statements atomically

-- Check current transaction status
SELECT CURRENT_TRANSACTION();
-- NULL = no open transaction (AUTOCOMMIT mode or after COMMIT/ROLLBACK)
-- A transaction ID = there is an open transaction

-- Note: Snowflake does NOT support SAVEPOINT.
-- Unlike Oracle and PostgreSQL, partial rollbacks within
-- a transaction are not possible in Snowflake.
-- A ROLLBACK in Snowflake always undoes the ENTIRE transaction.
--
-- The Snowflake pattern for partial undo:
-- · Break the work into separate smaller transactions
-- · Commit each step independently
-- · Use Time Travel to recover if something goes wrong later
--
-- Example: instead of one big transaction with a savepoint,
-- use two separate transactions:

BEGIN;
    UPDATE ECOMMERCE.RAW.PRODUCTS_WORK SET unit_price = 9999 WHERE product_id = 1;
COMMIT;
-- If this looks wrong → use Time Travel to recover (Goal 8)

BEGIN;
    UPDATE ECOMMERCE.RAW.PRODUCTS_WORK SET unit_price = 8888 WHERE product_id = 2;
COMMIT;
-- Independent — rolling back this one does not affect the first

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════

DROP TABLE IF EXISTS ECOMMERCE.RAW.PRODUCTS_WORK;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_WORK;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_STAGING;
DROP TABLE IF EXISTS ECOMMERCE.RAW.HIGH_VALUE_ORDERS;

-- Verify only original tables remain
SELECT TABLE_NAME
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_TYPE   = 'BASE TABLE'
ORDER BY TABLE_NAME
;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Clone CUSTOMERS into CUSTOMERS_WORK.
--    Write a transaction that:
--    a. Updates all customers in 'United States' segment 'Standard'
--       to segment 'Premium' where they have more than 5 orders
--    b. Verifies the count of updated rows
--    c. COMMITs only if the count is between 100 and 10,000 rows
--    If outside that range — ROLLBACK and investigate.
--
-- 2. Create a PRODUCTS_STAGING table and MERGE it into
--    PRODUCTS_WORK with these rules:
--    · If product exists and is_active = FALSE → reactivate it
--    · If product does not exist → insert it
--    · If product exists and unit_price changed → update price
--    How many rows were inserted vs updated?
--
-- 3. Write a DELETE that removes all orders from ORDERS_WORK
--    where the customer no longer exists in CUSTOMERS.
--    Use BEGIN/COMMIT. How many rows were deleted?
--    What does this tell you about data integrity in the dataset?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I accidentally run DELETE without WHERE?
-- A: Without WHERE, DELETE removes every row in the table.
--    With AUTOCOMMIT = TRUE it is already committed.
--    Recovery options:
--    1. Time Travel: SELECT * FROM table AT (OFFSET => -300)
--       (if within your retention window — covered in Goal 8)
--    2. Clone from backup if you have one
--    Prevention: always run SELECT COUNT(*) with the same WHERE
--    before DELETE. Better yet, always use BEGIN/COMMIT for
--    any destructive DML.
--
-- Q: What if MERGE produces unexpected duplicate rows?
-- A: MERGE requires the source to have at most one row matching
--    each target row. If source has duplicates on the join key,
--    Snowflake may error or produce unpredictable results.
--    Always deduplicate the source before MERGE:
--    WITH deduped_source AS (
--        SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
--        FROM source_table
--    )
--    SELECT * FROM deduped_source WHERE rn = 1
--
-- Q: What is the difference between TRUNCATE and DROP TABLE?
-- A: TRUNCATE removes all rows but keeps the table structure,
--    grants, and comments. DROP TABLE removes the table entirely.
--    Use TRUNCATE when you want to reload a table.
--    Use DROP TABLE when you are done with it permanently.
--    Both are fast. DROP TABLE can be undone with UNDROP TABLE
--    within the Time Travel window.
--
-- Q: Can I UPDATE or DELETE using a JOIN in Snowflake?
-- A: Not directly — Snowflake does not support UPDATE ... JOIN
--    or DELETE ... JOIN syntax. Use a subquery or MERGE instead:
--    UPDATE table SET col = value
--    WHERE id IN (SELECT id FROM other_table WHERE condition);
--    For complex multi-table updates, MERGE is the cleanest option.
--
-- Q: What is the Oracle equivalent of MERGE?
-- A: Oracle has had MERGE since Oracle 9i — identical syntax.
--    The WHEN NOT MATCHED BY SOURCE clause (delete unmatched rows)
--    exists in Snowflake but not in standard Oracle MERGE.
--    Everything else is fully portable between Oracle and Snowflake.
--
-- Q: Does Snowflake support SAVEPOINT for partial rollbacks?
-- A: No — Snowflake does not support SAVEPOINT.
--    ROLLBACK always undoes the entire open transaction.
--    Design your transactions to be small and atomic.
--    For partial undo use separate transactions + Time Travel.
