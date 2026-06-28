-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 2 : Get Data In
-- Sub-task 2.8 : Work with external tables
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~20 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight (all steps)
-- Prerequisites    : 03_copy_into.sql completed
--                    All 8 CSV tables loaded in ECOMMERCE.RAW
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Sub-tasks 2.3 through 2.7 all moved data INTO Snowflake.
--   External tables take a different approach — the data stays
--   exactly where it is (S3, Azure Blob, or GCS) and Snowflake
--   queries it in place using a SQL interface.
--
--   No data movement. No storage cost in Snowflake. No load time.
--   Just a metadata layer that makes files look like tables.
--
-- ── IMPORTANT NOTE ON THIS SUB-TASK ──────────────────────────
-- External tables require an EXTERNAL stage pointing to cloud
-- storage (S3, Azure Blob, or GCS). They cannot be created
-- over internal stages — Snowflake enforces this restriction.
--
-- This sub-task covers:
--   PART A — Concepts and syntax (reference — not runnable here)
--   PART B — Direct stage querying (runnable now with our data)
--   PART C — Comparison and when to use each approach
--
-- Full external table hands-on exercises are in:
--   Workbook 4 — Azure Data Engineering (Azure Blob + Event Grid)
--   Workbook 6 — AWS Data Engineering (S3 + SQS)
-- ─────────────────────────────────────────────────────────────
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: EXTERNAL TABLES
-- ══════════════════════════════════════════════════════════════
--
-- An external table is a read-only metadata object that maps
-- a cloud storage location to a SQL table interface. Snowflake
-- reads files directly from S3/Azure/GCS at query time.
--
-- KEY CHARACTERISTICS:
--   · Read-only     — no INSERT, UPDATE, DELETE, or MERGE
--   · No Time Travel — data is not in Snowflake storage
--   · No Fail-Safe  — same reason
--   · Slower queries — reads raw files vs optimised micro-partitions
--   · Always current — queries always read the latest files
--   · VALUE column  — all data arrives as VARIANT before casting
--   · Requires external stage — cannot use internal stages
--
-- WHEN TO USE EXTERNAL TABLES:
--   · Data lake integration — query S3/Azure/GCS files via SQL
--   · Schema-on-read — define structure at query time not load time
--   · Large cold data that is rarely queried
--   · Joining Snowflake tables with data lake files
--   · Exploring files before deciding whether to load them
--
-- WHEN NOT TO USE EXTERNAL TABLES:
--   · Frequently queried data — load it for performance
--   · Data that needs updating — external tables are read-only
--   · Production dashboards — latency is higher than loaded tables
--
-- Oracle equivalent:
--   Oracle External Tables (CREATE TABLE ... ORGANIZATION EXTERNAL)
--   serve the same purpose. Snowflake's implementation works
--   natively with cloud object storage without server-side
--   file access or directory objects.
--
-- ══════════════════════════════════════════════════════════════
-- PART A: EXTERNAL TABLE SYNTAX (reference — not runnable here)
-- ══════════════════════════════════════════════════════════════
--
-- The following shows the complete CREATE EXTERNAL TABLE syntax.
-- Replace @YOUR_EXTERNAL_STAGE with a real external stage
-- when you have one configured (Workbooks 4 and 6).

-- ── Understanding the column definition syntax ────────────────
-- Every row in a staged file arrives as a single VARIANT
-- called VALUE. Snowflake assigns positional names automatically:
--   c1 = first column, c2 = second column, c3 = third, etc.
--
-- The column definition pattern is:
--   column_name   SQL_TYPE   AS (VALUE:cN::SQL_TYPE)
--                                │     │   │
--                                │     │   └── cast to SQL type
--                                │     └────── Nth column in the file
--                                └──────────── raw row as VARIANT
--
-- Column order MUST match column order in the source file.
-- ─────────────────────────────────────────────────────────────

-- ── CREATE EXTERNAL TABLE syntax (commented — reference only) ─

-- CREATE OR REPLACE EXTERNAL TABLE ECOMMERCE.RAW.SUPPLIERS_EXT (
--     supplier_id     INTEGER         AS (VALUE:c1::INTEGER),
--     supplier_name   VARCHAR(255)    AS (VALUE:c2::VARCHAR),
--     contact_name    VARCHAR(255)    AS (VALUE:c3::VARCHAR),
--     contact_email   VARCHAR(255)    AS (VALUE:c4::VARCHAR),
--     phone           VARCHAR(100)    AS (VALUE:c5::VARCHAR),
--     country         VARCHAR(100)    AS (VALUE:c6::VARCHAR),
--     is_active       BOOLEAN         AS (VALUE:c7::BOOLEAN),
--     created_at      TIMESTAMP_NTZ   AS (VALUE:c8::TIMESTAMP_NTZ),
--     region          VARCHAR(100)    AS (VALUE:c9::VARCHAR)
-- )
-- WITH LOCATION = @YOUR_EXTERNAL_STAGE        -- must be external stage
--     FILE_FORMAT  = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
--     PATTERN      = '.*suppliers.*\\.csv'
--     AUTO_REFRESH = FALSE                    -- TRUE for cloud event notifications
-- COMMENT = 'External table over suppliers.csv in cloud storage'
-- ;

-- ── Once created, query syntax is identical to a regular table ─
-- SELECT * FROM ECOMMERCE.RAW.SUPPLIERS_EXT LIMIT 10;
-- SELECT COUNT(*) FROM ECOMMERCE.RAW.SUPPLIERS_EXT;
--
-- JOIN external table with a loaded table:
-- SELECT
--     s.supplier_name,
--     COUNT(p.product_id) AS product_count
-- FROM ECOMMERCE.RAW.SUPPLIERS_EXT s
-- JOIN ECOMMERCE.RAW.PRODUCTS p ON s.supplier_id = p.supplier_id
-- GROUP BY s.supplier_name
-- ORDER BY product_count DESC;
--
-- Refresh metadata when files change:
-- ALTER EXTERNAL TABLE ECOMMERCE.RAW.SUPPLIERS_EXT REFRESH;
--
-- Show external tables:
-- SHOW EXTERNAL TABLES IN SCHEMA ECOMMERCE.RAW;

-- ══════════════════════════════════════════════════════════════
-- PART B: DIRECT STAGE QUERYING — runnable now
-- ══════════════════════════════════════════════════════════════
-- While external tables require an external stage, you can
-- query staged files directly using SELECT from a stage.
-- This achieves a similar result — no data movement, query
-- files in place — without needing a table definition.
-- Think of it as an ad-hoc external table without persistence.

-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Confirm staged files are available
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Query a staged file directly — no table definition
-- ══════════════════════════════════════════════════════════════
-- SELECT $N queries files directly from a stage.
-- This is the lightweight alternative to an external table
-- for ad-hoc exploration.

-- Preview suppliers.csv with positional column references
SELECT
    $1::INTEGER     AS supplier_id,
    $2::VARCHAR     AS supplier_name,
    $3::VARCHAR     AS contact_name,
    $6::VARCHAR     AS country,
    $7::BOOLEAN     AS is_active
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 10
;

-- Count rows in the staged file — no COPY INTO needed
SELECT COUNT(*) AS row_count
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
;
-- Expected: 1,000 — same as the loaded SUPPLIERS table
-- This reads directly from the stage file every time.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Aggregate directly from a staged file
-- ══════════════════════════════════════════════════════════════
-- You can run aggregations on staged files without loading.
-- Useful for profiling data before committing to a schema.

-- Supplier count by country — reading from stage
SELECT
    $6::VARCHAR                 AS country,
    COUNT(*)                    AS supplier_count,
    SUM(CASE WHEN $7::BOOLEAN = TRUE THEN 1 ELSE 0 END)
                                AS active_suppliers
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
GROUP BY $6::VARCHAR
ORDER BY supplier_count DESC
LIMIT 10
;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Join a staged file with a loaded table
-- ══════════════════════════════════════════════════════════════
-- This is the equivalent of the external table JOIN use case —
-- bridge between staged data and loaded data without loading.

SELECT
    s.$2::VARCHAR               AS supplier_name,
    s.$6::VARCHAR               AS country,
    COUNT(p.product_id)         AS product_count,
    ROUND(AVG(p.unit_price), 2) AS avg_unit_price
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT') s
JOIN ECOMMERCE.RAW.PRODUCTS p
    ON s.$1::INTEGER = p.supplier_id
GROUP BY s.$2::VARCHAR, s.$6::VARCHAR
ORDER BY product_count DESC
LIMIT 10
;
-- Note: column references use $N positional notation since
-- there is no table definition with named columns.
-- This is the key advantage of external tables — named columns
-- make queries more readable and maintainable.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Query multiple files with a PATTERN
-- ══════════════════════════════════════════════════════════════
-- Stage queries support PATTERN to match multiple files.
-- Useful when data is split across multiple staged files.

-- Count total rows across all CSV files in the stage
SELECT
    METADATA$FILENAME           AS source_file,
    COUNT(*)                    AS row_count
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT',
     PATTERN     => '.*\\.csv')
GROUP BY METADATA$FILENAME
ORDER BY row_count DESC
;
-- METADATA$FILENAME is a special column that shows which file
-- each row came from — useful when querying multiple files.
-- This is the same metadata column available in external tables.

-- ══════════════════════════════════════════════════════════════
-- PART C: COMPARISON — three ways to access staged data
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Compare all three approaches
-- ══════════════════════════════════════════════════════════════

-- ── Approach 1: Direct stage query ───────────────────────────
-- Ad-hoc, no persistent object, positional columns
SELECT $1::INTEGER AS supplier_id, $2::VARCHAR AS supplier_name
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

-- ── Approach 2: External table (syntax reference) ────────────
-- Named columns, persistent, joinable by name
-- Requires external stage — shown here for reference only
-- SELECT supplier_id, supplier_name
-- FROM ECOMMERCE.RAW.SUPPLIERS_EXT
-- LIMIT 5;

-- ── Approach 3: Loaded table ─────────────────────────────────
-- Fastest, full SQL, all Snowflake features
SELECT supplier_id, supplier_name
FROM ECOMMERCE.RAW.SUPPLIERS
LIMIT 5
;

-- ── Decision guide ────────────────────────────────────────────
-- Use direct stage query when:
--   · Exploring files before loading
--   · One-time analysis on staged data
--   · You have an internal stage
--
-- Use external table when:
--   · Data lives in S3/Azure/GCS and must stay there
--   · You need named columns for maintainable SQL
--   · Joining data lake files with Snowflake tables regularly
--   · You will query the same files repeatedly
--
-- Use loaded table when:
--   · Data is queried frequently
--   · Performance is important
--   · You need Time Travel, clustering, or other Snowflake features
--   · Data needs to be updated

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Using a direct stage query on products.csv, find the
--    average unit_price per category ($3::VARCHAR).
--    Compare the result to the same query on the loaded
--    ECOMMERCE.RAW.PRODUCTS table.
--    Are the results identical?
--
-- 2. Using METADATA$FILENAME, query all CSV files in the stage
--    and find which file has the most rows.
--    Does this match the row counts from Sub-task 2.3?
--
-- 3. Write a stage query that joins orders.csv (staged) with
--    ECOMMERCE.RAW.CUSTOMERS (loaded) to find the top 5
--    customers by number of orders.
--    How does the syntax differ from joining two loaded tables?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: When will I use external tables in practice?
-- A: When working with data lakes on S3, Azure Blob, or GCS.
--    Common scenarios: querying Parquet files from a Spark
--    pipeline, reading JSON event logs from S3, joining
--    Snowflake tables with files your data engineering team
--    stores in cloud storage without loading into Snowflake.
--    Workbooks 4 (Azure) and 6 (AWS) cover the full setup.
--
-- Q: What is AUTO_REFRESH and when should I use it?
-- A: AUTO_REFRESH = TRUE tells Snowflake to automatically
--    update external table metadata when new files arrive
--    in the stage. Requires cloud event notifications:
--    S3 → SQS, Azure Blob → Event Grid, GCS → Pub/Sub.
--    Use it when files arrive continuously and you want
--    the external table to always reflect the latest state.
--    Use AUTO_REFRESH = FALSE when you control refresh timing.
--
-- Q: Can external tables use Parquet or JSON files?
-- A: Yes — specify the appropriate FILE_FORMAT.
--    For JSON the VALUE column contains the entire JSON object.
--    For Parquet, column references use schema field names
--    rather than positional c1, c2 references.
--    MATCH_BY_COLUMN_NAME works in external tables too.
--
-- Q: What is the performance difference between a direct
--    stage query and an external table?
-- A: Very similar — both read raw files at query time.
--    External tables have a slight advantage because Snowflake
--    can cache file metadata (file list, partition info) and
--    use AUTO_REFRESH to maintain it. Direct stage queries
--    scan the stage directory on every execution.
--    Neither approach matches loaded table performance for
--    analytical queries on large datasets.
--
-- Q: What is the Oracle equivalent?
-- A: Oracle External Tables (CREATE TABLE ... ORGANIZATION EXTERNAL)
--    require files on the database server or accessible via
--    a directory object. Snowflake external tables work directly
--    with cloud object storage — no server access, no DBA,
--    no directory objects required.
