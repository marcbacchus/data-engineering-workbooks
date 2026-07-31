-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 2 : Get Data In
-- Sub-task 2.7 : Unload data from Snowflake
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~20 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight (all steps)
-- Prerequisites    : 03_copy_into.sql completed
--                    All 8 CSV tables loaded in ECOMMERCE.RAW
-- COF-C03 domain   : Domain 3.0 — Data Loading, Unloading, and Connectivity (18%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Data does not only flow INTO Snowflake — it flows out too.
--   Downstream systems, data science teams, reporting tools,
--   and external partners all need data exported from Snowflake
--   in formats they can consume.
--
--   COPY INTO <stage> is the reverse of COPY INTO <table>.
--   It exports query results to files in a stage, which can
--   then be downloaded locally or consumed by external systems.
--
--   This sub-task covers:
--   · Unloading to internal stages (download to local machine)
--   · Controlling output format (CSV, JSON, Parquet)
--   · Splitting large exports into multiple files
--   · Downloading staged files using GET in SnowSQL
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: COPY INTO <stage>
-- ══════════════════════════════════════════════════════════════
--
-- Basic syntax:
--   COPY INTO @<stage>/<filename_prefix>
--   FROM <table or query>
--   FILE_FORMAT = (...)
--   <options>;
--
-- KEY OPTIONS:
--   SINGLE = TRUE        — write one file (default: multiple parts)
--   SINGLE = FALSE       — write multiple part files (parallel)
--   MAX_FILE_SIZE        — max bytes per file when SINGLE = FALSE
--   OVERWRITE = TRUE     — replace existing files in stage
--   HEADER = TRUE        — include column headers in CSV output
--   PARTITION BY         — partition output into subfolders
--
-- SINGLE vs MULTIPLE FILES:
--   SINGLE = TRUE:  one file, simpler, slower for large datasets
--   SINGLE = FALSE: multiple part files, faster (parallel write),
--                   standard for large exports
--                   Files named: prefix_0_0_0.csv, prefix_0_0_1.csv...
--
-- Oracle equivalent:
--   Oracle uses SPOOL command in SQL*Plus or UTL_FILE package
--   to write query results to files. COPY INTO <stage> is
--   significantly more powerful — parallel, compressed, and
--   supports multiple output formats natively.
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Create a dedicated export stage to keep exports separate
-- from the load stage
CREATE STAGE IF NOT EXISTS ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE
    COMMENT = 'Named internal stage for data exports'
;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Unload a simple query result to CSV
-- ══════════════════════════════════════════════════════════════
-- Export top 1000 delivered orders to a single CSV file.
-- SINGLE = TRUE keeps it as one file for easy download.

COPY INTO @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_export.csv
FROM (
    SELECT
        o.order_id,
        o.customer_id,
        c.first_name || ' ' || c.last_name   AS customer_name,
        c.country,
        o.order_status,
        o.order_total,
        o.created_at
    FROM ECOMMERCE.RAW.ORDERS o
    JOIN ECOMMERCE.RAW.CUSTOMERS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    ORDER BY o.order_total DESC
    LIMIT 1000
)
FILE_FORMAT = (
    TYPE                         = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('')
    COMPRESSION                  = NONE        -- uncompressed for easy reading
)
SINGLE      = TRUE
OVERWRITE   = TRUE
HEADER      = TRUE                             -- include column headers
;

-- Verify the file was created
LIST @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE;

SELECT
    "name"                          AS export_file,
    ROUND("size" / 1024, 1)         AS size_kb,
    "last_modified"                 AS exported_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;

-- Preview the exported file from the stage
SELECT $1, $2, $3, $4, $5, $6, $7
FROM @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_export.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;
-- Confirm headers are present, values look correct,
-- and NULLs are represented as empty fields not \N

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Unload a large dataset to multiple part files
-- ══════════════════════════════════════════════════════════════
-- For large exports, SINGLE = FALSE writes multiple files
-- in parallel — much faster than a single file.
-- Snowflake names part files automatically.

COPY INTO @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_full/data_
FROM (
    SELECT
        order_id,
        customer_id,
        order_status,
        order_total,
        created_at
    FROM ECOMMERCE.RAW.ORDERS
)
FILE_FORMAT = (
    TYPE                         = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('')
    COMPRESSION                  = GZIP       -- compress for smaller files
)
SINGLE          = FALSE
OVERWRITE       = TRUE
HEADER          = TRUE
MAX_FILE_SIZE   = 104857600                   -- 100MB per file
;

-- Check how many part files were created
LIST @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE PATTERN='.*orders_full.*';

SELECT
    "name"                              AS export_file,
    ROUND("size" / 1024 / 1024, 1)     AS size_mb,
    "last_modified"                     AS exported_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;
-- Multiple part files named: orders_full/data__0_0_0.csv.gz,
--                             orders_full/data__0_1_0.csv.gz, etc.
-- Note the double underscore (__) before the part number —
-- this is because our prefix ends with _ and Snowflake adds
-- its own _ separator.
--
-- File sizes are much smaller than MAX_FILE_SIZE (100MB) because
-- GZIP compression on repetitive CSV data achieves 10-20x
-- compression ratio. 2 million order rows compressed to ~30MB total.
--
-- Number of files is determined by Snowflake's internal parallelism
-- not just MAX_FILE_SIZE — expect 6-10 files for this dataset.
-- Each file is independently loadable — no dependency between parts.

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Unload to JSON format
-- ══════════════════════════════════════════════════════════════
-- Export product reviews as JSON — each row becomes
-- a JSON object. Useful for APIs and downstream systems
-- that consume JSON natively.

-- JSON UNLOAD REQUIREMENT:
--   COPY INTO <stage> with FILE_FORMAT = JSON requires the
--   SELECT to return a single VARIANT or OBJECT column.
--   Use OBJECT_CONSTRUCT() to build the JSON object explicitly
--   from typed columns before unloading.

COPY INTO @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/reviews_export.json
FROM (
    SELECT OBJECT_CONSTRUCT(
        'review_id',    review_id,
        'product_id',   product_id,
        'customer_id',  customer_id,
        'rating',       rating,
        'review_text',  review_text,
        'is_verified',  is_verified,
        'created_at',   created_at
    ) AS review_json
    FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
    LIMIT 1000
)
FILE_FORMAT = (
    TYPE        = JSON
    COMPRESSION = NONE
)
SINGLE    = TRUE
OVERWRITE = TRUE
;

-- Verify
LIST @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE PATTERN='.*reviews.*';

-- Preview the JSON export
SELECT $1
FROM @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/reviews_export.json
    (FILE_FORMAT => 'ECOMMERCE.RAW.JSON_FORMAT')
LIMIT 3
;

-- NOTE: When previewing staged files with SELECT, always use
-- a named file format object rather than inline format options:
--   CORRECT: (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
--   INCORRECT: (FILE_FORMAT => (TYPE = CSV FIELD_DELIMITER = ','))
-- Inline format options are not supported in stage SELECT queries.


-- Each row is a JSON object with the selected columns.
-- Note: Snowflake exports JSON as NDJSON (one object per line)
-- not as a JSON array — set STRIP_OUTER_ARRAY = FALSE to load it back.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Export to year-specific subfolders
--         Run in: Snowsight
-- ══════════════════════════════════════════════════════════════
-- Organise exports into subfolders by year — useful for
-- downstream systems that consume data incrementally.
-- We manually specify the subfolder path in the stage reference
-- rather than using PARTITION BY which has limited support.

-- Export delivered orders year by year
-- 2019
COPY INTO @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_by_year/2019/data_
FROM (
    SELECT order_id, customer_id, order_status, order_total, created_at
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
      AND YEAR(created_at) = 2019
)
FILE_FORMAT = (
    TYPE                         = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('')
    COMPRESSION                  = GZIP
)
SINGLE    = FALSE
OVERWRITE = TRUE
HEADER    = TRUE
;

-- Repeat for other years as needed:
-- 2020: replace 2019 with 2020 in both the path and WHERE clause
-- 2021, 2022, 2023: same pattern

-- Verify folder structure
LIST @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE PATTERN='.*orders_by_year.*';

SELECT
    "name"                              AS export_file,
    ROUND("size" / 1024, 1)            AS size_kb,
    "last_modified"                     AS exported_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;
-- Files organised as:
-- orders_by_year/2019/data__0_0_0.csv.gz
-- orders_by_year/2019/data__0_0_1.csv.gz
-- This folder structure is compatible with Spark, Databricks,
-- and AWS Glue which can read partitioned data natively.

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Download exported files using GET
--         Run in: SnowSQL
-- ══════════════════════════════════════════════════════════════
-- GET downloads files from a Snowflake internal stage to your
-- local machine. Runs from SnowSQL — not from Snowsight.
-- This is the reverse of PUT from Sub-task 2.2.

-- ── Connect to SnowSQL first ──────────────────────────────────
-- Mac / Linux — open Terminal:
--   snowsql -c workbook
--
-- Windows — open Command Prompt or PowerShell:
--   snowsql -c workbook
--
-- Your prompt should show:
--   MBACCHUS#WORKBOOK_WH@ECOMMERCE.RAW>
--
-- ── Reading the SnowSQL prompt ────────────────────────────────
-- Pattern: <username>#<warehouse>@<database>.<schema>>
-- If any component shows (no database) or (no schema):
--   USE DATABASE ECOMMERCE;
--   USE SCHEMA RAW;
--   USE WAREHOUSE WORKBOOK_WH;
-- ─────────────────────────────────────────────────────────────

-- Download a specific file:
-- Mac / Linux:
--   GET @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_export.csv file:///Users/marc/Downloads/;

-- Windows:
--   GET @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_export.csv file://C:/Users/YourName/Downloads/;

-- Download all files from a stage prefix (subfolder):

-- Note: The local destination directory must exist before running GET.
-- Create it first:
--
-- Mac / Linux:
--   mkdir -p ~/Downloads/orders_full
--   GET @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_full/ file:///Users/marc/Downloads/orders_full/;
--
-- Windows (PowerShell):
--   New-Item -ItemType Directory -Path C:\Users\YourName\Downloads\orders_full -Force
--   GET @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_full/ file://C:/Users/YourName/Downloads/orders_full/;
--
-- Unlike PUT which uploads from any existing path,
-- GET requires the destination directory to already exist.


-- Mac / Linux:
--   GET @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_full/ file:///Users/marc/Downloads/orders_full/;

-- Windows:
--   GET @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_full/ file://C:/Users/YourName/Downloads/orders_full/;

-- Note: GET does not support PATTERN filtering.
-- To download specific files, either:
--   1. Use a stage subfolder prefix (as above)
--   2. GET each file individually by name
--   3. Use the Snowsight UI — Data → Stages → select files → Download

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Check export history
-- ══════════════════════════════════════════════════════════════
-- COPY_HISTORY tracks both loads AND unloads.

SELECT
    TABLE_NAME,
    FILE_NAME,
    ROW_COUNT,
    ROW_PARSED,
    STATUS,
    LAST_LOAD_TIME
FROM ECOMMERCE.INFORMATION_SCHEMA.LOAD_HISTORY
WHERE SCHEMA_NAME = 'RAW'
ORDER BY LAST_LOAD_TIME DESC
LIMIT 10
;
-- Note: LOAD_HISTORY tracks table-level operations.
-- For stage-level unload history use ACCOUNT_USAGE.COPY_HISTORY
-- which covers both COPY INTO <table> and COPY INTO <stage>.

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- Remove exported files and the export stage.
-- Source tables in ECOMMERCE.RAW are not affected.

REMOVE @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE;
DROP STAGE IF EXISTS ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE;

-- Verify
SHOW STAGES IN SCHEMA ECOMMERCE.RAW;
-- Should show only ECOMMERCE_RAW_STAGE — the export stage is gone

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Export the top 500 products by unit_price to a CSV file
--    called products_premium.csv in the export stage.
--    Include: product_name, category, unit_price, cost_price,
--    and a calculated margin column (unit_price - cost_price).
--    Use HEADER = TRUE and COMPRESSION = NONE.
--    Preview the file from the stage to verify the margin column.
--
-- 2. Export PRODUCT_REVIEWS to a partitioned structure
--    partitioned by rating (1 through 5).
--    How many files are created?
--    Which partition has the most data?
--
-- 3. Export CUSTOMERS as JSON (SINGLE = TRUE).
--    Preview the exported JSON from the stage.
--    How does the output differ from the JSON we loaded in
--    Sub-task 2.5? (Hint: array vs NDJSON)

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I want to export directly to S3 or Azure Blob?
-- A: Use an external stage instead of internal.
--    Create the external stage pointing to your S3 bucket
--    or Azure container, then COPY INTO that stage.
--    Files land directly in your cloud storage — no GET needed.
--    Covered in Sub-task 2.8 (external tables) and the
--    Azure and AWS workbooks.
--
-- Q: What if my export file is too large to download?
-- A: Use SINGLE = FALSE with a small MAX_FILE_SIZE to split
--    into manageable chunks. Then GET each part file separately
--    or use PATTERN matching to download all parts at once.
--
-- Q: What if I need to export with a specific delimiter
--    (pipe, tab, semicolon)?
-- A: Set FIELD_DELIMITER in the FILE_FORMAT:
--    FILE_FORMAT = (TYPE = CSV FIELD_DELIMITER = '|')
--    Common for legacy systems that expect pipe-delimited files.
--
-- Q: What if the exported JSON needs to be a JSON array
--    instead of NDJSON?
-- A: Snowflake exports JSON as NDJSON by default — one object
--    per line, no outer array. To create a JSON array you would
--    need to post-process the file, or use ARRAY_AGG in your
--    SELECT to create a single array value:
--    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) FROM table
--    This creates one row containing a JSON array of all records.
--
-- Q: What is the Oracle equivalent?
-- A: Oracle uses SPOOL in SQL*Plus for simple exports or
--    UTL_FILE for programmatic file writing — both require
--    server-side file access. COPY INTO <stage> is cleaner:
--    it runs entirely within Snowflake, supports compression
--    and partitioning natively, and downloads via GET without
--    needing server access.

-- Q: What about PARTITION BY in COPY INTO?
-- A: PARTITION BY is documented but has limited support depending
--    on Snowflake version and account configuration. The manual
--    subfolder approach used in Step 4 is more reliable and
--    gives you explicit control over the folder structure.