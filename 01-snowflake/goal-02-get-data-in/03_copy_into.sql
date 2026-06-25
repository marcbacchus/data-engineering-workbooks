-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 2 : Get Data In
-- Sub-task 2.3 : Load data with COPY INTO
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : 01_file_formats.sql completed
--                    02_staging_files.sql completed
--                    All 8 CSV files staged in ECOMMERCE_RAW_STAGE
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   COPY INTO is Snowflake's bulk data loading command. It reads
--   files from a stage and loads them into a table in a single,
--   atomic operation. It is fast, parallelised, and restartable.
--
--   This sub-task creates all 8 target tables and loads the
--   complete e-commerce dataset into Snowflake. After this
--   sub-task, every subsequent goal in this workbook has
--   real data to work with.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: COPY INTO
-- ══════════════════════════════════════════════════════════════
--
-- Basic syntax:
--   COPY INTO <table>
--   FROM @<stage>/<file_pattern>
--   FILE_FORMAT = (FORMAT_NAME = '<format>')
--   <options>;
--
-- KEY OPTIONS:
--   ON_ERROR = CONTINUE    — skip bad rows, load the rest
--   ON_ERROR = SKIP_FILE   — skip the entire file if any error
--   ON_ERROR = ABORT_STATEMENT — stop immediately on first error (default)
--   PURGE = TRUE           — delete files from stage after load
--   FORCE = TRUE           — reload files even if already loaded
--   VALIDATION_MODE        — check without loading (covered in 2.4)
--
-- HOW SNOWFLAKE TRACKS LOADS:
--   Snowflake maintains a load history for each table.
--   If you run COPY INTO again on the same files, Snowflake
--   skips them by default — it knows they were already loaded.
--   Use FORCE = TRUE to override this and reload.
--   This is called "load deduplication" — a key safety feature.
--
-- Oracle equivalent:
--   SQL*Loader (sqlldr) performs the equivalent function.
--   COPY INTO is faster, parallelised across warehouse nodes,
--   and requires no control files — the file format object
--   and stage replace the .ctl file entirely.
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Confirm files are staged before creating tables
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

SELECT COUNT(*) AS files_staged
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- Should show 8 — if less, go back to Sub-task 2.2

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create the SUPPLIERS table and load
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE ECOMMERCE.RAW.SUPPLIERS (
    supplier_id     INTEGER,
    supplier_name   VARCHAR(255),
    contact_name    VARCHAR(255),
    contact_email   VARCHAR(255),
    phone           VARCHAR(100),
    country         VARCHAR(100),
    region          VARCHAR(100),
    is_active       BOOLEAN,
    created_at      TIMESTAMP_NTZ
)
COMMENT = 'Supplier / vendor master data — 1,000 rows'
;

COPY INTO ECOMMERCE.RAW.SUPPLIERS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv.gz
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

-- Verify
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.SUPPLIERS;
-- Expected: 1,000

SELECT * FROM ECOMMERCE.RAW.SUPPLIERS LIMIT 5;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create the PRODUCTS table and load
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE ECOMMERCE.RAW.PRODUCTS (
    product_id      INTEGER,
    product_name    VARCHAR(500),
    category        VARCHAR(100),
    subcategory     VARCHAR(100),
    supplier_id     INTEGER,
    unit_price      FLOAT,
    cost_price      FLOAT,
    weight_kg       FLOAT,
    is_active       BOOLEAN,
    created_at      TIMESTAMP_NTZ
)
COMMENT = 'Product catalog — 10,000 rows'
;

COPY INTO ECOMMERCE.RAW.PRODUCTS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/products.csv.gz
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.PRODUCTS;
-- Expected: 10,000

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Create the CUSTOMERS table and load
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE ECOMMERCE.RAW.CUSTOMERS (
    customer_id     INTEGER,
    first_name      VARCHAR(100),
    last_name       VARCHAR(100),
    email           VARCHAR(255),
    phone           VARCHAR(100),
    country         VARCHAR(100),
    city            VARCHAR(100),
    postal_code     VARCHAR(50),
    segment         VARCHAR(50),
    is_active       BOOLEAN,
    created_at      TIMESTAMP_NTZ,
    region          VARCHAR(100)
)
COMMENT = 'Customer accounts — 100,000 rows'
;

COPY INTO ECOMMERCE.RAW.CUSTOMERS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/customers.csv.gz
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.CUSTOMERS;
-- Expected: 100,000

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Create the ORDERS table and load
-- ══════════════════════════════════════════════════════════════
-- Largest single-table load in this workbook.
-- 2 million rows — expect 1-3 minutes on X-Small warehouse.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS (
    order_id            INTEGER,
    customer_id         INTEGER,
    order_status        VARCHAR(50),
    payment_method      VARCHAR(50),
    shipping_method     VARCHAR(50),
    shipping_country    VARCHAR(100),
    order_total         FLOAT,
    shipping_date       DATE,
    delivery_date       DATE,
    created_at          TIMESTAMP_NTZ,
    shipping_region     VARCHAR(100)
)
COMMENT = 'Customer orders — 2,000,000 rows'
;

-- Note the time before loading
SELECT CURRENT_TIMESTAMP() AS load_start_time;

COPY INTO ECOMMERCE.RAW.ORDERS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/orders.csv.gz
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT CURRENT_TIMESTAMP() AS load_end_time;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS;
-- Expected: 2,000,000

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Create the ORDER_ITEMS table and load
-- ══════════════════════════════════════════════════════════════
-- Largest table in the dataset — 4.6 million rows.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDER_ITEMS (
    order_item_id   INTEGER,
    order_id        INTEGER,
    product_id      INTEGER,
    quantity        INTEGER,
    unit_price      FLOAT,
    discount        FLOAT,
    line_total      FLOAT
)
COMMENT = 'Order line items — 4,659,254 rows'
;

SELECT CURRENT_TIMESTAMP() AS load_start_time;

COPY INTO ECOMMERCE.RAW.ORDER_ITEMS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/order_items.csv.gz
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT CURRENT_TIMESTAMP() AS load_end_time;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDER_ITEMS;
-- Expected: 4,659,254

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Create the PRODUCT_REVIEWS table and load
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE ECOMMERCE.RAW.PRODUCT_REVIEWS (
    review_id       INTEGER,
    product_id      INTEGER,
    customer_id     INTEGER,
    order_id        INTEGER,
    rating          INTEGER,
    review_text     VARCHAR(2000),
    is_verified     BOOLEAN,
    helpful_votes   INTEGER,
    created_at      TIMESTAMP_NTZ
)
COMMENT = 'Customer product reviews — 500,000 rows'
;

COPY INTO ECOMMERCE.RAW.PRODUCT_REVIEWS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.csv.gz
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.PRODUCT_REVIEWS;
-- Expected: 500,000

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Create the RETURNS table and load
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE ECOMMERCE.RAW.RETURNS (
    return_id       INTEGER,
    order_id        INTEGER,
    order_item_id   INTEGER,
    product_id      INTEGER,
    customer_id     INTEGER,
    return_reason   VARCHAR(255),
    return_status   VARCHAR(50),
    refund_amount   FLOAT,
    created_at      TIMESTAMP_NTZ
)
COMMENT = 'Return requests — 80,000 rows'
;

COPY INTO ECOMMERCE.RAW.RETURNS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/returns.csv.gz
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.RETURNS;
-- Expected: 80,000

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Create the CLICKSTREAM_EVENTS table and load
-- ══════════════════════════════════════════════════════════════
-- 3 million rows — expect 2-4 minutes on X-Small warehouse.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.CLICKSTREAM_EVENTS (
    event_id                    INTEGER,
    session_id                  VARCHAR(50),
    customer_id                 INTEGER,        -- nullable: ~17% anonymous
    event_type                  VARCHAR(50),
    product_id                  INTEGER,        -- nullable: non-product events
    device_type                 VARCHAR(50),
    browser                     VARCHAR(50),
    operating_system            VARCHAR(50),
    session_duration_seconds    INTEGER,
    created_at                  TIMESTAMP_NTZ
)
COMMENT = 'Web/app behavioural events — 3,000,000 rows'
;

SELECT CURRENT_TIMESTAMP() AS load_start_time;

COPY INTO ECOMMERCE.RAW.CLICKSTREAM_EVENTS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/clickstream_events.csv.gz
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT CURRENT_TIMESTAMP() AS load_end_time;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS;
-- Expected: 3,000,000

-- ══════════════════════════════════════════════════════════════
-- STEP 9: Verify the complete dataset
-- ══════════════════════════════════════════════════════════════

SELECT
    TABLE_NAME,
    ROW_COUNT,
    BYTES / 1024 / 1024         AS size_mb,
    CREATED                     AS created_at,
    LAST_ALTERED                AS last_modified
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_TYPE   = 'BASE TABLE'
ORDER BY ROW_COUNT DESC
;

-- Expected row counts:
-- ORDER_ITEMS          4,659,254
-- CLICKSTREAM_EVENTS   3,000,000
-- ORDERS               2,000,000
-- PRODUCT_REVIEWS        500,000
-- RETURNS                 80,000
-- CUSTOMERS              100,000
-- PRODUCTS                10,000
-- SUPPLIERS                1,000
-- TOTAL               10,350,254

-- Total row count across all tables
SELECT SUM(ROW_COUNT) AS total_rows
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_TYPE   = 'BASE TABLE'
;
-- Expected: 10,350,254

-- ══════════════════════════════════════════════════════════════
-- STEP 10: Run your first real query on the dataset
-- ══════════════════════════════════════════════════════════════
-- You have 10.3 million rows loaded. Let's use them.

-- Revenue by year and region
SELECT
    YEAR(o.created_at)              AS order_year,
    o.shipping_region,
    COUNT(DISTINCT o.order_id)      AS total_orders,
    COUNT(DISTINCT o.customer_id)   AS unique_customers,
    ROUND(SUM(oi.line_total), 2)    AS total_revenue
FROM ECOMMERCE.RAW.ORDERS o
JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY
    YEAR(o.created_at),
    o.shipping_region
ORDER BY
    order_year,
    total_revenue DESC
;

-- Top 10 products by revenue
SELECT
    p.product_name,
    p.category,
    COUNT(DISTINCT oi.order_id)     AS times_ordered,
    SUM(oi.quantity)                AS units_sold,
    ROUND(SUM(oi.line_total), 2)    AS total_revenue
FROM ECOMMERCE.RAW.ORDER_ITEMS oi
JOIN ECOMMERCE.RAW.PRODUCTS p
    ON oi.product_id = p.product_id
GROUP BY
    p.product_name,
    p.category
ORDER BY total_revenue DESC
LIMIT 10
;

-- ══════════════════════════════════════════════════════════════
-- STEP 11: Check load history
-- ══════════════════════════════════════════════════════════════
-- Snowflake tracks every COPY INTO operation.
-- LOAD_HISTORY shows what was loaded, when, and how many rows.

SELECT
    TABLE_NAME,
    FILE_NAME,
    ROW_COUNT,
    ROW_PARSED,
    ERROR_COUNT,
    STATUS,
    LAST_LOAD_TIME
FROM ECOMMERCE.INFORMATION_SCHEMA.LOAD_HISTORY
WHERE TABLE_SCHEMA = 'RAW'
ORDER BY LAST_LOAD_TIME DESC
;
-- STATUS = LOADED confirms successful load
-- ERROR_COUNT = 0 confirms clean data
-- ROW_COUNT = ROW_PARSED confirms no rows were skipped

-- ══════════════════════════════════════════════════════════════
-- STEP 12: Demonstrate load deduplication
-- ══════════════════════════════════════════════════════════════
-- Run COPY INTO on SUPPLIERS again — Snowflake skips the file.

COPY INTO ECOMMERCE.RAW.SUPPLIERS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv.gz
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
;
-- Result: Copy executed with 0 files processed.
-- Snowflake remembers the file was already loaded and skips it.
-- This prevents duplicate data from accidental re-runs.

-- To force a reload (use deliberately, not by default):
-- COPY INTO ECOMMERCE.RAW.SUPPLIERS
-- FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv.gz
--     FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
--     FORCE = TRUE
-- ;
-- FORCE = TRUE ignores load history and loads regardless.
-- Only use when you intentionally want to reload.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Write a query joining CUSTOMERS, ORDERS, and ORDER_ITEMS
--    to find the top 5 customers by total revenue.
--    Include: customer name, country, total orders, total revenue.
--
-- 2. Check the load history for ORDER_ITEMS specifically.
--    How long did the load take? How many rows were parsed?
--    How many files were processed?
--    (Hint: LOAD_HISTORY + QUERY_HISTORY joined on query timing)
--
-- 3. How many unique product categories are in the dataset?
--    What is the average unit price per category?
--    Order by average price descending.
--
-- 4. What percentage of orders are delivered vs other statuses?
--    Use COUNT and GROUP BY on order_status.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if COPY INTO fails halfway through a large file?
-- A: Snowflake loads in micro-batches. A failure mid-file
--    may leave partial data in the table. Check LOAD_HISTORY
--    for ERROR_COUNT and the rows loaded. Use TRUNCATE TABLE
--    and reload with FORCE = TRUE after fixing the issue.
--    Covered in depth in Sub-task 2.4 (error handling).
--
-- Q: What if I want to load only specific columns from the file?
-- A: Use a column list in COPY INTO:
--    COPY INTO table (col1, col2, col3) FROM @stage ...
--    Unspecified columns receive their default value or NULL.
--
-- Q: What if my table has more columns than the file?
-- A: Specify the column list explicitly. Without it,
--    ERROR_ON_COLUMN_COUNT_MISMATCH in your file format
--    will fail the load if counts do not match.
--
-- Q: What if I need to transform data during load?
-- A: COPY INTO supports a SELECT clause for transformations:
--    COPY INTO table FROM (
--        SELECT $1, UPPER($2), TO_DATE($3, 'MM/DD/YYYY')
--        FROM @stage
--    ) FILE_FORMAT = (...);
--    For complex transformations, load raw then transform
--    using SQL — the approach used in Goal 3.
--
-- Q: What is the Oracle equivalent?
-- A: SQL*Loader (sqlldr) with a control file.
--    Key differences: Snowflake COPY INTO is parallel by default,
--    requires no client-side installation beyond SnowSQL,
--    and tracks load history automatically. No .log, .bad,
--    or .dsc files to manage — all history is in Snowflake.
