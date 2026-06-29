-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 2 : Get Data In
-- Sub-task 2.3 : Load data with COPY INTO (CSV tables)
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : 01_file_formats.sql completed
--                    02_staging_files.sql completed
--                    All 10 files staged in ECOMMERCE_RAW_STAGE
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   COPY INTO is Snowflake's bulk data loading command. It reads
--   files from a stage and loads them into tables in a single,
--   atomic, parallelised operation.
--
--   This sub-task focuses on the 8 CSV tables — the core
--   e-commerce dataset. JSON and Parquet loading is covered
--   in Sub-task 2.5 (semi-structured data).
--
--   After this sub-task: 10.3 million rows in Snowflake,
--   ready for every exercise from Goal 3 onward.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: COPY INTO
-- ══════════════════════════════════════════════════════════════
--
-- Basic syntax:
--   COPY INTO <table>
--   FROM @<stage>/<filename>
--       FILE_FORMAT = (FORMAT_NAME = '<format>')
--       <options>;
--
-- KEY OPTIONS:
--   ON_ERROR = ABORT_STATEMENT — stop on first error (default)
--   ON_ERROR = CONTINUE        — skip bad rows, load the rest
--   ON_ERROR = SKIP_FILE       — skip entire file if any error
--   PURGE    = TRUE            — delete files from stage after load
--   FORCE    = TRUE            — reload even if already loaded
--   VALIDATION_MODE            — check without loading (Sub-task 2.4)
--
-- HOW SNOWFLAKE TRACKS LOADS (load deduplication):
--   Snowflake maintains a load history per table. Running
--   COPY INTO again on the same file skips it by default —
--   Snowflake knows it was already loaded. This prevents
--   duplicate data from accidental re-runs.
--   Use FORCE = TRUE only when you intentionally want to reload.
--
-- FILE REFERENCE FORMAT:
--   Files in the stage are referenced without the stage prefix:
--   FROM @stage/filename.csv  (not ecommerce_raw_stage/filename.csv)
--   Snowflake resolves the full path internally.
--
-- Oracle equivalent:
--   SQL*Loader (sqlldr) with a control file (.ctl).
--   COPY INTO is faster, parallelised across warehouse nodes,
--   and requires no control files — the file format object
--   replaces .ctl entirely. No .log, .bad, or .dsc files.
--   Load history is tracked in Snowflake automatically.
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
-- Should show 10 — if less, go back to Sub-task 2.2

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create and load SUPPLIERS
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE ECOMMERCE.RAW.SUPPLIERS (
    supplier_id     INTEGER,
    supplier_name   VARCHAR(255),
    contact_name    VARCHAR(255),
    contact_email   VARCHAR(255),
    phone           VARCHAR(100),
    country         VARCHAR(100),
    is_active       BOOLEAN,
    created_at      TIMESTAMP_NTZ,
    region          VARCHAR(100)
)
COMMENT = 'Supplier / vendor master data — 1,000 rows'
;

COPY INTO ECOMMERCE.RAW.SUPPLIERS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.SUPPLIERS;
-- Expected: 1,000

SELECT * FROM ECOMMERCE.RAW.SUPPLIERS LIMIT 5;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create and load PRODUCTS
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
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/products.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.PRODUCTS;
-- Expected: 10,000

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Create and load CUSTOMERS
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
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/customers.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.CUSTOMERS;
-- Expected: 100,000

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Create and load ORDERS
-- ══════════════════════════════════════════════════════════════
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


COPY INTO ECOMMERCE.RAW.ORDERS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/orders.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS;
-- Expected: 2,000,000

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Create and load ORDER_ITEMS
-- ══════════════════════════════════════════════════════════════
-- Largest table — 4.6 million rows.

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


COPY INTO ECOMMERCE.RAW.ORDER_ITEMS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/order_items.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDER_ITEMS;
-- Expected: 4,659,254

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Create and load PRODUCT_REVIEWS (CSV)
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
COMMENT = 'Customer product reviews CSV — 500,000 rows'
;

COPY INTO ECOMMERCE.RAW.PRODUCT_REVIEWS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.PRODUCT_REVIEWS;
-- Expected: 500,000

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Create and load RETURNS
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
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/returns.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.RETURNS;
-- Expected: 80,000

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Create and load CLICKSTREAM_EVENTS
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


COPY INTO ECOMMERCE.RAW.CLICKSTREAM_EVENTS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/clickstream_events.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS;
-- Expected: 3,000,000


-- ── What about product_reviews.json and product_reviews.parquet? ──
-- You staged 10 files in Sub-task 2.2 but only 8 are loaded here.
-- The JSON and Parquet files require a different loading approach:
--
--   · JSON loads into a VARIANT column, not standard typed columns
--   · Parquet uses MATCH_BY_COLUMN_NAME instead of positional mapping
--   · Both require understanding dot-notation and FLATTEN first
--
-- Sub-task 2.5 (Semi-structured data) covers all of this:
--   1. How Snowflake stores semi-structured data (VARIANT)
--   2. How to query nested JSON fields
--   3. How to flatten arrays
--   4. Then loads product_reviews.json and product_reviews.parquet
--
-- The staged files are ready and waiting — nothing is lost.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 9: Verify the complete dataset
-- ══════════════════════════════════════════════════════════════

SELECT
    TABLE_NAME,
    ROW_COUNT,
    ROUND(BYTES / 1024 / 1024, 1)  AS size_mb,
    CREATED                         AS created_at
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

-- Total rows across all tables
SELECT SUM(ROW_COUNT) AS total_rows
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_TYPE   = 'BASE TABLE'
;
-- Expected: 10,350,254

-- ══════════════════════════════════════════════════════════════
-- STEP 10: Run your first real queries on the dataset
-- ══════════════════════════════════════════════════════════════
-- 10.3 million rows loaded. Let's use them.

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

-- Return rate by product category
SELECT
    p.category,
    COUNT(DISTINCT oi.order_item_id)    AS total_items_sold,
    COUNT(DISTINCT r.return_id)         AS total_returns,
    ROUND(COUNT(DISTINCT r.return_id) * 100.0
        / COUNT(DISTINCT oi.order_item_id), 2) AS return_rate_pct
FROM ECOMMERCE.RAW.ORDER_ITEMS oi
JOIN ECOMMERCE.RAW.PRODUCTS p
    ON oi.product_id = p.product_id
LEFT JOIN ECOMMERCE.RAW.RETURNS r
    ON oi.order_item_id = r.order_item_id
GROUP BY p.category
ORDER BY return_rate_pct DESC
;

-- ══════════════════════════════════════════════════════════════
-- STEP 11: Check load history
-- ══════════════════════════════════════════════════════════════

SELECT
    TABLE_NAME,
    FILE_NAME,
    ROW_COUNT,
    ROW_PARSED,
    ERROR_COUNT,
    STATUS,
    LAST_LOAD_TIME
FROM ECOMMERCE.INFORMATION_SCHEMA.LOAD_HISTORY
WHERE SCHEMA_NAME = 'RAW'
ORDER BY LAST_LOAD_TIME DESC
;
-- STATUS = LOADED        — successful load
-- ERROR_COUNT = 0        — clean data, no rejected rows
-- ROW_COUNT = ROW_PARSED — no rows were skipped

-- ══════════════════════════════════════════════════════════════
-- STEP 12: Demonstrate load deduplication
-- ══════════════════════════════════════════════════════════════
-- Run COPY INTO on SUPPLIERS again — Snowflake skips the file.

COPY INTO ECOMMERCE.RAW.SUPPLIERS
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
;
-- Result: Copy executed with 0 files processed.
-- Snowflake remembers the file was already loaded.
-- This prevents duplicate data from accidental re-runs.

-- To force a reload (use deliberately, not by default):
-- COPY INTO ECOMMERCE.RAW.SUPPLIERS
-- FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv
--     FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
--     FORCE = TRUE
-- ;
-- FORCE = TRUE ignores load history. Use only when
-- you intentionally want to reload — for example after
-- fixing a data issue and reloading from scratch.

-- ══════════════════════════════════════════════════════════════
-- WHAT'S NEXT
-- ══════════════════════════════════════════════════════════════
-- CSV loading complete. 10.3 million rows in Snowflake.
-- Remaining sub-tasks in Goal 2:
--   2.4 — Handle load errors (what happens when things go wrong)
--   2.5 — Semi-structured data (JSON and Parquet loading)
--   2.6 — Snowpipe (continuous automated ingestion)
--   2.7 — Unload data (COPY INTO stage for exports)
--   2.8 — External tables (query without loading)
--   2.9 — Schema evolution (ALTER TABLE, safe DDL patterns)

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Write a query joining CUSTOMERS, ORDERS, and ORDER_ITEMS
--    to find the top 5 customers by total revenue.
--    Include: customer name, country, total orders, total revenue.
--
-- 2. Check LOAD_HISTORY for ORDER_ITEMS specifically.
--    How many files were processed? How many rows were parsed?
--    What was the status?
--
-- 3. How many unique product categories are in the dataset?
--    What is the average unit_price per category?
--    Order by average price descending.
--
-- 4. What percentage of orders are in each order_status?
--    Which status has the highest percentage?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if COPY INTO fails halfway through a large file?
-- A: Snowflake loads in micro-batches. A failure mid-file
--    may leave partial data in the table. Check LOAD_HISTORY
--    for ERROR_COUNT. Use TRUNCATE TABLE and reload with
--    FORCE = TRUE after fixing the issue.
--    Covered in depth in Sub-task 2.4 (error handling).
--
-- Q: What if I want to load only specific columns from a file?
-- A: Use a column list in COPY INTO:
--    COPY INTO table (col1, col2, col3) FROM @stage/file.csv ...
--    Unspecified columns receive NULL or their default value.
--
-- Q: What if my table has more columns than the file?
-- A: Specify the column list explicitly. Without it,
--    ERROR_ON_COLUMN_COUNT_MISMATCH in CSV_FORMAT fails the load.
--
-- Q: What if I need to transform data during load?
-- A: COPY INTO supports a SELECT clause:
--    COPY INTO table FROM (
--        SELECT $1, UPPER($2), TO_DATE($3, 'MM/DD/YYYY')
--        FROM @stage/file.csv
--    ) FILE_FORMAT = (...);
--    For complex transformations, load raw then transform
--    with SQL — the pattern used throughout Goal 3.
--
-- Q: What is the Oracle SQL*Loader equivalent?
-- A: sqlldr userid=user/pass control=file.ctl log=file.log
--    Key differences: COPY INTO is parallel by default,
--    no client-side control files, load history tracked
--    automatically in Snowflake — no .log or .bad files to manage.
