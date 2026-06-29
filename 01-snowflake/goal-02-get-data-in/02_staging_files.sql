-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 2 : Get Data In
-- Sub-task 2.2 : Stage files for loading
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~25 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : 01_file_formats.sql completed
--                    SnowSQL installed and connected
--                    All 10 dataset files at:
--                    Mac:     ~/projects/data-engineering-workbooks/dataset/
--                    Windows: C:\Users\YourName\projects\data-engineering-workbooks\dataset\
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Staging is the step between your local files and Snowflake
--   tables. Files go to the stage first — then COPY INTO reads
--   them from the stage into tables.
--
--   This two-step process is intentional:
--   · You can validate files before committing to a load
--   · Failed loads do not leave partial data in tables
--   · Staged files can be reloaded if something goes wrong
--   · Multiple tables can load from the same staged file
--
--   This sub-task stages all 10 files:
--   · 8 CSV files  — e-commerce core tables
--   · 1 JSON file  — product_reviews.json (nested structure)
--   · 1 Parquet file — product_reviews.parquet (columnar binary)
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE PUT COMMAND
-- ══════════════════════════════════════════════════════════════
--
-- PUT uploads files from your local machine to a Snowflake stage.
-- Runs from SnowSQL only — not from Snowsight UI.
--
-- Basic syntax:
--   PUT file://<local_path> @<stage_name> <options>;
--
-- Key options:
--   AUTO_COMPRESS = FALSE  — store files as-is (no compression)
--   OVERWRITE = TRUE       — replace existing files in stage
--   PARALLEL = 4           — parallel upload threads (default 4)
--
-- PATH SYNTAX BY OPERATING SYSTEM:
--   Mac/Linux:  file:///Users/YourName/path/to/file.csv
--               (three forward slashes after file:)
--   Windows:    file://C:/Users/YourName/path/to/file.csv
--               (two forward slashes, then drive letter)
--               Always use forward slashes — not backslashes
--
-- Oracle equivalent:
--   SQL*Loader requires files on the database server or via
--   a directory object. PUT uploads directly from your laptop —
--   no server access, no directory objects, no DBA needed.
--
-- ── WHERE TO RUN EACH COMMAND ────────────────────────────────
-- SnowSQL (Terminal / Command Prompt): PUT commands
--                                      Steps 3, 5, 6, 7
-- Snowsight (Browser):                 Everything else
--                                      Steps 1, 2, 4, 8, 9, 10
--
-- Quick rule: PUT → SnowSQL   |   everything else → Snowsight
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- SETUP
-- Run in: Snowsight
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Confirm the stage exists — create if not
CREATE STAGE IF NOT EXISTS ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE
    COMMENT = 'Named internal stage for e-commerce raw data files'
;

-- Confirm it is empty before we upload
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;
-- Should return zero rows (Query produced no results)

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Inspect your dataset files before uploading
--         Run in: Terminal (Mac/Linux) or Command Prompt / PowerShell (Windows)
-- ══════════════════════════════════════════════════════════════

-- ── Mac / Linux ───────────────────────────────────────────────
-- List all files with sizes:
--   ls -lh ~/projects/data-engineering-workbooks/dataset/
--
-- Preview first 5 rows of a CSV:
--   head -5 ~/projects/data-engineering-workbooks/dataset/suppliers.csv
--
-- Preview JSON structure (first 20 lines):
--   head -20 ~/projects/data-engineering-workbooks/dataset/product_reviews.json
--
-- Inspect Parquet schema (requires Python):
--   python3 -c "import pyarrow.parquet as pq; print(pq.read_table('~/projects/data-engineering-workbooks/dataset/product_reviews.parquet').schema)"

-- ── Windows (Command Prompt) ──────────────────────────────────
-- List files:
--   dir C:\Users\YourName\projects\data-engineering-workbooks\dataset\
--
-- Preview CSV:
--   type C:\Users\YourName\projects\data-engineering-workbooks\dataset\suppliers.csv | more

-- ── Windows (PowerShell) ──────────────────────────────────────
-- List files:
--   Get-ChildItem ~\projects\data-engineering-workbooks\dataset\
--
-- Preview first 5 rows:
--   Get-Content ~\projects\data-engineering-workbooks\dataset\suppliers.csv -TotalCount 5

-- ── What to confirm ───────────────────────────────────────────
-- CSV files   : comma-delimited, header row, quoted strings
-- JSON file   : starts with [ (array), each record starts with {
-- Parquet file: binary — inspect via Python only
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Connect to Snowflake via SnowSQL
--         Run in: Terminal (Mac/Linux) or Command Prompt / PowerShell (Windows)
-- ══════════════════════════════════════════════════════════════

-- ── Mac / Linux ───────────────────────────────────────────────
-- Open Terminal:
--   snowsql -c workbook

-- ── Windows ───────────────────────────────────────────────────
-- Open Command Prompt or PowerShell:
--   snowsql -c workbook
-- (same command — SnowSQL is cross-platform)

-- ── SnowSQL password prompt notes (all platforms) ─────────────
-- · The cursor will NOT move as you type — this is normal
-- · Cmd+V (Mac) or Ctrl+V (Windows) paste DOES work
--   even though no characters appear on screen
-- · Press Enter when done

-- ── Reading the SnowSQL prompt ────────────────────────────────
-- Pattern: <username>#<warehouse>@<database>.<schema>>
-- Example: MBACCHUS#WORKBOOK_WH@ECOMMERCE.RAW>
--
--   MBACCHUS    — your Snowflake username
--   WORKBOOK_WH — active virtual warehouse
--   ECOMMERCE   — active database
--   RAW         — active schema
--
-- Oracle SQL*Plus shows only: SQL>  (no context at all)
-- SnowSQL always shows your full active context — read it
-- before running any command.
--
-- If any component shows (no database) or (no schema),
-- run these in the SnowSQL prompt:
--   USE DATABASE ECOMMERCE;
--   USE SCHEMA RAW;
--   USE WAREHOUSE WORKBOOK_WH;
--
-- Do NOT run these in Snowsight — they apply to your
-- SnowSQL session only.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Upload ONE file first — verify before continuing
--         Run in: SnowSQL
-- ══════════════════════════════════════════════════════════════
-- Always confirm the process works on a small file first.
-- suppliers.csv is 0.1 MB — fast to upload and easy to verify.

-- ── Mac / Linux ───────────────────────────────────────────────
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/suppliers.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ── Windows ───────────────────────────────────────────────────
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/suppliers.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ── Expected output ───────────────────────────────────────────
-- +---------------+---------------+-------------+-------------+--------------------+--------------------+----------+---------+
-- | source        | target        | source_size | target_size | source_compression | target_compression | status   | message |
-- |---------------+---------------+-------------+-------------+--------------------+--------------------+----------+---------|
-- | suppliers.csv | suppliers.csv |      125875 |      125888 | NONE               | NONE               | UPLOADED |         |
-- +---------------+---------------+-------------+-------------+--------------------+--------------------+----------+---------+
-- 1 Row(s) produced. Time Elapsed: 0.942s
--
-- Key columns:
--   status   = UPLOADED — file transferred successfully
--   message  = (empty)  — no errors
--   source_compression = NONE — file stored as plain .csv
--   No .gz extension — AUTO_COMPRESS=FALSE stores as-is
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Verify the first file
--         Run in: Snowsight
-- ══════════════════════════════════════════════════════════════

LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

-- ── Expected output ───────────────────────────────────────────
-- +-----------------------------------+--------+----------------------------------+-------------------------------+
-- | name                              |   size | md5                              | last_modified                 |
-- |-----------------------------------+--------+----------------------------------+-------------------------------|
-- | ecommerce_raw_stage/suppliers.csv | 125888 | 6a525e106cbf7d83d037b0d4ac44634e | Thu, 25 Jun 2026 13:55:53 GMT |
-- +-----------------------------------+--------+----------------------------------+-------------------------------+
--
-- Key observations:
--   · name includes stage prefix: ecommerce_raw_stage/suppliers.csv
--   · md5 is a checksum for verifying file integrity (may not match)
--   · No .gz extension — stored as plain .csv
-- ─────────────────────────────────────────────────────────────

SELECT
    "name"                          AS staged_file,
    ROUND("size" / 1024 / 1024, 1) AS size_mb,
    "last_modified"                 AS uploaded_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;
-- Should show 1 row: ecommerce_raw_stage/suppliers.csv | 0.1 MB
-- +-----------------------------------+---------+-------------------------------+ 
-- | STAGED_FILE                       | SIZE_MB | UPLOADED_AT                   |
-- |-----------------------------------+---------+-------------------------------|
-- | ecommerce_raw_stage/suppliers.csv |     0.1 | Thu, 25 Jun 2026 14:42:53 GMT |
+-----------------------------------+---------+-------------------------------+
-- If it appears — you are good to proceed.
-- If not — check your PUT path and try again.

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Upload the remaining CSV files
--         Run in: SnowSQL
-- ══════════════════════════════════════════════════════════════

-- ── Mac / Linux ───────────────────────────────────────────────
--replace <marc> with your username on your machine

-- Products (10,000 rows — 1.0 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/products.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Returns (80,000 rows — 6.6 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/returns.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Customers (100,000 rows — 12.7 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/customers.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Product Reviews CSV (500,000 rows — 53.2 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/product_reviews.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ── Windows ───────────────────────────────────────────────────
-- Replace <YourName> with your username on your machine

-- Products (10,000 rows — 1.0 MB)
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/products.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Returns (80,000 rows — 6.6 MB)
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/returns.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Customers (100,000 rows — 12.7 MB)
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/customers.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Product Reviews CSV (500,000 rows — 53.2 MB)
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/product_reviews.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ── Expected upload time ──────────────────────────────────────
-- products.csv:        seconds
-- returns.csv:         seconds
-- customers.csv:       ~5-10 seconds
-- product_reviews.csv: ~10-30 seconds
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Upload the three large CSV files
--         Run in: SnowSQL
-- ══════════════════════════════════════════════════════════════
-- Use PARALLEL=8 for faster uploads on large files.

-- ── Mac / Linux ───────────────────────────────────────────────
--replace <marc> with your username on your machine

-- Orders (2,000,000 rows — 210.8 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/orders.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=8;

-- Order Items (4,659,254 rows — 171.8 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/order_items.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=8;

-- Clickstream Events (3,000,000 rows — 237.7 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/clickstream_events.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=8;

-- ── Windows ───────────────────────────────────────────────────
-- Replace <YourName> with your username on your machine

-- Orders (2,000,000 rows — 210.8 MB)
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/orders.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=8;

-- Order Items (4,659,254 rows — 171.8 MB)
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/order_items.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=8;

-- Clickstream Events (3,000,000 rows — 237.7 MB)
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/clickstream_events.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=8;

-- ── Expected upload time ──────────────────────────────────────
-- Varies by internet speed:
--   1 Gbps  : ~5-10 seconds per file
--   100 Mbps: ~30-60 seconds per file
--   50 Mbps : ~2-5 minutes per file
--
-- Large files uploaded with PARALLEL=8 show a segmented MD5
-- in LIST output (e.g. abc123-30 where -30 = 30 chunks).
-- This is normal — file was uploaded in parallel chunks.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Upload the JSON and Parquet supplement files
--         Run in: SnowSQL
-- ══════════════════════════════════════════════════════════════
-- These two files contain 10,000 product reviews in different
-- formats. Used in Sub-task 2.5 (semi-structured data).
-- Same underlying data — three different file formats.
-- The size difference is the first teaching moment:
--   product_reviews.csv     = 54 MB  (500K rows, CSV)
--   product_reviews.json    = 5.9 MB (10K rows, JSON nested)
--   product_reviews.parquet = 0.4 MB (10K rows, Parquet/Snappy)

-- ── Mac / Linux ───────────────────────────────────────────────
--replace <marc> with your username on your machine

-- Product Reviews JSON (10,000 records — 5.9 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/product_reviews.json @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Product Reviews Parquet (10,000 rows — 0.4 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/product_reviews.parquet @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ── Windows ───────────────────────────────────────────────────
-- Replace <YourName> with your username on your machine

-- Product Reviews JSON (10,000 records — 5.9 MB)
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/product_reviews.json @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Product Reviews Parquet (10,000 rows — 0.4 MB)
-- PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/product_reviews.parquet @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ── Expected output for JSON ──────────────────────────────────
-- | source                | target                | status   |
-- | product_reviews.json  | product_reviews.json  | UPLOADED |
--
-- ── Expected output for Parquet ───────────────────────────────
-- | source                    | target                    | status   |
-- | product_reviews.parquet   | product_reviews.parquet   | UPLOADED |
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Verify all 10 files are staged
--         Run in: Snowsight
-- ══════════════════════════════════════════════════════════════

LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

-- ── Expected LIST output — all 10 files ──────────────────────
-- +------------------------------------------------+-----------+----------------------------------+
-- | name                                           |      size | md5                              |
-- |------------------------------------------------+-----------+----------------------------------|
-- | ecommerce_raw_stage/clickstream_events.csv     | 249195120 | a09546af...                      |
-- | ecommerce_raw_stage/customers.csv              |  13358416 | 3b457ae2...                      |
-- | ecommerce_raw_stage/order_items.csv            | 180154736 | 1e91e5a0...                      |
-- | ecommerce_raw_stage/orders.csv                 | 221077792 | 49e83272...                      |
-- | ecommerce_raw_stage/product_reviews.csv        |  55774384 | 19ffc040...                      |
-- | ecommerce_raw_stage/product_reviews.json       |   6187234 | xxxxxxxx...                      |
-- | ecommerce_raw_stage/product_reviews.parquet    |    426000 | xxxxxxxx...                      |
-- | ecommerce_raw_stage/products.csv               |   1005488 | 575b3e02...                      |
-- | ecommerce_raw_stage/returns.csv                |   6960144 | 3499c543...                      |
-- | ecommerce_raw_stage/suppliers.csv              |    125888 | 6a525e10...                      |
-- +------------------------------------------------+-----------+----------------------------------+
-- 10 Row(s) produced.
--
-- If any file is missing, re-run the PUT for that file.
-- PUT with OVERWRITE=TRUE is safe to re-run at any time.
-- ─────────────────────────────────────────────────────────────

SELECT
    "name"                              AS staged_file,
    ROUND("size" / 1024 / 1024, 1)     AS size_mb,
    "last_modified"                     AS uploaded_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;

-- ── Expected RESULT_SCAN output ───────────────────────────────
-- +------------------------------------------------+---------+
-- | STAGED_FILE                                    | SIZE_MB |
-- |------------------------------------------------+---------|
-- | ecommerce_raw_stage/clickstream_events.csv     |   237.7 |
-- | ecommerce_raw_stage/customers.csv              |    12.7 |
-- | ecommerce_raw_stage/order_items.csv            |   171.8 |
-- | ecommerce_raw_stage/orders.csv                 |   210.8 |
-- | ecommerce_raw_stage/product_reviews.csv        |    53.2 |
-- | ecommerce_raw_stage/product_reviews.json       |     5.9 |
-- | ecommerce_raw_stage/product_reviews.parquet    |     0.4 |
-- | ecommerce_raw_stage/products.csv               |     1.0 |
-- | ecommerce_raw_stage/returns.csv                |     6.6 |
-- | ecommerce_raw_stage/suppliers.csv              |     0.1 |
-- +------------------------------------------------+---------+
-- 10 Row(s) produced.
--
-- Notice the size difference for the same 10,000 product reviews:
--   product_reviews.json    = 5.9 MB
--   product_reviews.parquet = 0.4 MB
-- Same data, 15x size difference. This is why data lakes use Parquet.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 9: Preview all staged files without loading them
--         Run in: Snowsight
-- ══════════════════════════════════════════════════════════════
-- $N column notation reads directly from the stage.
-- $1 = first column, $2 = second column, etc.
-- Verify format parsing before committing to a load.

-- ── CSV files ─────────────────────────────────────────────────
SELECT $1, $2, $3, $4, $5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

SELECT $1, $2, $3, $4, $5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/products.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

SELECT $1, $2, $3, $4, $5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/customers.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

SELECT $1, $2, $3, $4, $5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/orders.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

SELECT $1, $2, $3, $4, $5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/order_items.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

SELECT $1, $2, $3, $4, $5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

SELECT $1, $2, $3, $4, $5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/returns.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

SELECT $1, $2, $3, $4, $5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/clickstream_events.csv
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

-- ── JSON file ─────────────────────────────────────────────────
-- JSON staged files return a single $1 column containing
-- the entire JSON object as a string
SELECT $1
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.json
    (FILE_FORMAT => 'ECOMMERCE.RAW.JSON_FORMAT')
LIMIT 3
;
-- Each row shows one complete JSON object.
-- You will see the nested product and metadata structure.
-- This is what gets loaded into a VARIANT column in Sub-task 2.5.

-- ── Parquet file ──────────────────────────────────────────────
-- Parquet files cannot be previewed with $N column notation.
-- Snowflake requires either MATCH_BY_COLUMN_NAME or a
-- single VARIANT column when reading Parquet from a stage.
--
-- To preview Parquet file contents use this approach:
SELECT $1
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.parquet
    (FILE_FORMAT => 'ECOMMERCE.RAW.PARQUET_FORMAT')
LIMIT 5
;
-- Returns each row as a VARIANT object — all columns visible
-- as key-value pairs within a single JSON-like structure.
-- This is how Snowflake reads Parquet internally before
-- mapping columns to a table in COPY INTO.
--
-- Example output for one row:
-- {
--   "review_id": 1,
--   "product_id": 1533,
--   "rating": 2,
--   "review_text": "Packaging was damaged...",
--   "category": "Beauty & Personal Care"
-- }

-- Parquet rows return as a single VARIANT object containing
-- all columns as key-value pairs. This is how Snowflake reads
-- Parquet internally — column names and types are preserved
-- from the embedded schema.
-- Compare to the JSON preview above — both return VARIANT,
-- but Parquet types are strongly typed (integers as integers,
-- timestamps as timestamps) while JSON types are inferred.
-- In Sub-task 2.5 we use MATCH_BY_COLUMN_NAME to map
-- Parquet columns directly to table columns during COPY INTO.

-- ── Verify checklist for all files ───────────────────────────
-- CSV     : $1 = primary key (id), dates in YYYY-MM-DD format,
--           NULL values show as NULL not as the string 'NULL'
-- JSON    : $1 shows complete JSON object with nested fields visible
-- Parquet : $1 shows a VARIANT object with all columns as
--           key-value pairs — column names visible, types preserved
--
-- If anything looks wrong — fix CSV_FORMAT / JSON_FORMAT /
-- PARQUET_FORMAT in Sub-task 2.1 BEFORE loading in 2.3.
-- Much easier to fix a format than reload 10 million rows.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 10: Remove a file from the stage if needed
--          Run in: Snowsight
-- ══════════════════════════════════════════════════════════════

-- Remove a specific file:
-- REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/wrong_file.csv;

-- Remove all files matching a pattern:
-- REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE PATTERN='.*wrong.*';

-- Remove all files (use with caution):
-- REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

-- Key reminder: files in a stage have NO effect on any table
-- until COPY INTO explicitly reads them. Staging and loading
-- are always two completely separate steps.

-- ══════════════════════════════════════════════════════════════
-- WHAT'S NEXT
-- ══════════════════════════════════════════════════════════════
-- All 10 files are staged and verified.
-- In Sub-task 2.3 you will:
--   · Create the 8 target tables in ECOMMERCE.RAW
--   · Run COPY INTO for each CSV table
--   · Verify row counts match expectations
--   · Run your first real queries on 10.3 million rows
-- The JSON and Parquet files wait for Sub-task 2.5.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Preview orders.csv using $1 through $11.
--    Can you identify which column position is order_status?
--    Which position is order_total?
--
-- 2. Compare the SIZE_MB values from the RESULT_SCAN output.
--    What is the total size of all staged files in MB?
--    How does this compare to the original files on your machine?
--
-- 3. Run REMOVE on the product_reviews.parquet file,
--    verify it is gone with LIST, then re-upload it.
--    Confirm OVERWRITE=TRUE works correctly.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if PUT fails with a permissions error?
-- A: Confirm your role has WRITE on the stage.
--    Run: SHOW GRANTS ON STAGE ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;
--    SYSADMIN was granted READ and WRITE in Goal 1 Sub-task 1.5.
--
-- Q: What if PUT times out on large files?
-- A: Increase PARALLEL (up to 99). SnowSQL automatically
--    resumes interrupted uploads — re-run the same PUT command.
--
-- Q: What if the JSON preview shows malformed output?
-- A: Check STRIP_OUTER_ARRAY = TRUE in JSON_FORMAT.
--    If the file is NDJSON (one object per line, no array),
--    set STRIP_OUTER_ARRAY = FALSE.
--
-- Q: What if I cannot preview the Parquet file?
-- A: Parquet is binary — $N notation may return raw bytes
--    depending on the column type. Use column names instead
--    of positional references when querying Parquet in COPY INTO.
--    Covered in Sub-task 2.5.
--
-- Q: What is the Oracle equivalent?
-- A: Oracle requires files on the database server or via
--    CREATE DIRECTORY and UTL_FILE. PUT uploads directly
--    from your laptop — no server access required at all.
