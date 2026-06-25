-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 2 : Get Data In
-- Sub-task 2.2 : Stage files for loading
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~25 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : 01_file_formats.sql completed
--                    SnowSQL installed and connected
--                    Dataset CSVs at:
--                    ~/projects/data-engineering-workbooks/dataset/
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
--   This sub-task uses SnowSQL to PUT all 8 e-commerce CSV
--   files into the named internal stage created in Goal 1.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE PUT COMMAND
-- ══════════════════════════════════════════════════════════════
--
-- PUT uploads files from your local machine to a Snowflake stage.
-- It runs from SnowSQL only — not from Snowsight UI.
--
-- Basic syntax:
--   PUT file://<local_path> @<stage_name> <options>;
--
-- Key options:
--   AUTO_COMPRESS = FALSE  — do not compress files on upload
--                            (our files are already uncompressed)
--   OVERWRITE = TRUE       — replace existing files in stage
--                            (useful when re-uploading corrected files)
--   PARALLEL = 4           — number of parallel upload threads
--                            (default 4, increase for large files)
--
-- Mac/Linux path syntax:   file:///Users/marc/path/to/file.csv
-- Windows path syntax:     file://C:/Users/marc/path/to/file.csv
--
-- Oracle equivalent:
--   SQL*Loader requires files to be accessible on the database
--   server or via a directory object. PUT is simpler — files
--   upload directly from your laptop to Snowflake storage.
--   No server access, no directory objects, no shared drives.
--
-- ══════════════════════════════════════════════════════════════
-- SETUP — Run in Snowsight
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Confirm the stage exists from Goal 1 Sub-task 1.5
-- If it does not exist, create it:
CREATE STAGE IF NOT EXISTS ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE
    COMMENT = 'Named internal stage for e-commerce raw CSV files'
;

-- Confirm it is empty before we upload
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;
-- Should return zero rows

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Connect to Snowflake via SnowSQL
-- ══════════════════════════════════════════════════════════════
-- Open Terminal on your Mac and connect using your named profile.
-- The PUT command runs from the SnowSQL prompt, not Snowsight.
--
-- ── In Terminal ───────────────────────────────────────────────
-- snowsql -c workbook
--
-- SnowSQL password prompt notes:
--   · The cursor will NOT move as you type — this is normal
--   · Cmd+V paste DOES work even though nothing appears
--   · Press Enter when done — login proceeds silently
--
-- Your prompt should show:
--   MBACCHUS#WORKBOOK_WH@ECOMMERCE.RAW>
--
-- If you see (no database).(no schema) in the prompt,
-- run these commands in SnowSQL:
--   USE DATABASE ECOMMERCE;
--   USE SCHEMA RAW;
--   USE WAREHOUSE WORKBOOK_WH;
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Upload the smaller reference tables first
-- ══════════════════════════════════════════════════════════════
-- Run these PUT commands from the SnowSQL prompt.
-- Upload in order of table size — small files first
-- so you can verify the process works before the large files.
--
-- ── In SnowSQL ────────────────────────────────────────────────

-- Suppliers (1,000 rows — 0.1 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/suppliers.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Products (10,000 rows — 1.0 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/products.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Returns (80,000 rows — 6.6 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/returns.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ── Expected output per file ──────────────────────────────────
-- source           target                  source_size  target_size  source_compression  target_compression  status
-- suppliers.csv    suppliers.csv.gz        105000       28000        NONE                GZIP                UPLOADED
--
-- Note: Even with AUTO_COMPRESS=FALSE, SnowSQL may compress
-- files during transfer for efficiency. The stage stores
-- them compressed. This is normal and transparent to COPY INTO.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Verify the small files uploaded successfully
-- ══════════════════════════════════════════════════════════════
-- Run this in Snowsight after each PUT batch to verify.

LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

SELECT
    "name"          AS staged_file,
    "size"          AS file_size_bytes,
    "last_modified" AS uploaded_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;
-- Should show suppliers.csv.gz, products.csv.gz, returns.csv.gz

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Upload the medium-sized tables
-- ══════════════════════════════════════════════════════════════
-- Run from SnowSQL prompt.
--
-- ── In SnowSQL ────────────────────────────────────────────────

-- Customers (100,000 rows — 12.7 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/customers.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Product Reviews (500,000 rows — 53.2 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/product_reviews.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ── Expected upload time ──────────────────────────────────────
-- customers.csv:       ~5-10 seconds
-- product_reviews.csv: ~30-60 seconds
-- Upload speed depends on your internet connection.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Upload the large tables
-- ══════════════════════════════════════════════════════════════
-- These are the three large files. Use PARALLEL=8 to speed
-- up the upload by using more concurrent upload threads.
--
-- ── In SnowSQL ────────────────────────────────────────────────

-- Orders (2,000,000 rows — 210.8 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/orders.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=8;

-- Order Items (4,659,254 rows — 171.8 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/order_items.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=8;

-- Clickstream Events (3,000,000 rows — 237.7 MB)
-- PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/clickstream_events.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=8;

-- ── Expected upload time ──────────────────────────────────────
-- orders.csv:            ~2-5 minutes
-- order_items.csv:       ~2-4 minutes
-- clickstream_events.csv ~3-6 minutes
-- Total: roughly 10-15 minutes for all three large files.
-- This varies significantly with internet speed.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Verify all 8 files are staged
-- ══════════════════════════════════════════════════════════════
-- Run in Snowsight after all uploads are complete.

LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

SELECT
    "name"                              AS staged_file,
    ROUND("size" / 1024 / 1024, 1)     AS size_mb,
    "last_modified"                     AS uploaded_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;

-- Expected output — 8 files:
-- clickstream_events.csv.gz   (large)
-- customers.csv.gz            (medium)
-- order_items.csv.gz          (large)
-- orders.csv.gz               (large)
-- product_reviews.csv.gz      (medium)
-- products.csv.gz             (small)
-- returns.csv.gz              (small)
-- suppliers.csv.gz            (small)
--
-- If any file is missing, re-run the PUT for that file.
-- PUT is safe to re-run with OVERWRITE=TRUE.

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Preview a staged file without loading it
-- ══════════════════════════════════════════════════════════════
-- SELECT from a stage using the $N column notation
-- to preview file contents without a COPY INTO.
-- $1 = first column, $2 = second column, etc.

SELECT
    $1  AS col1,
    $2  AS col2,
    $3  AS col3,
    $4  AS col4,
    $5  AS col5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/suppliers.csv.gz
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 10
;
-- This reads directly from the stage — no table involved.
-- Useful for verifying format parsing before committing to load.
-- If columns look wrong, your file format options need adjusting.

-- Try the same for customers
SELECT $1, $2, $3, $4, $5
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/customers.csv.gz
    (FILE_FORMAT => 'ECOMMERCE.RAW.CSV_FORMAT')
LIMIT 5
;

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Remove a file from the stage (if needed)
-- ══════════════════════════════════════════════════════════════
-- If you upload the wrong file or need to clean up:

-- Remove a specific file:
-- REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/wrong_file.csv.gz;

-- Remove all files matching a pattern:
-- REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE PATTERN='.*wrong.*';

-- Remove all files (use with caution):
-- REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

-- As covered in Goal 1 Sub-task 1.5:
-- Files in a stage have NO effect on any table until
-- COPY INTO explicitly reads them. Staging and loading
-- are always two completely separate steps.

-- ══════════════════════════════════════════════════════════════
-- WHAT'S NEXT
-- ══════════════════════════════════════════════════════════════
-- All 8 CSV files are now staged and ready.
-- In Sub-task 2.3 you will:
--   · Create the 8 target tables in ECOMMERCE.RAW
--   · Run COPY INTO for each table
--   · Verify row counts match expectations
--   · Query the loaded data for the first time

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Use SELECT $1, $2, $3 FROM @stage to preview
--    the orders.csv.gz file. How many columns does it have?
--    Do the values look correct for the first few rows?
--
-- 2. What is the size difference between the original
--    CSV files on your Mac and the compressed .gz files
--    in the stage? Run LIST @stage and compare to the
--    file sizes in ~/projects/data-engineering-workbooks/dataset/.
--    What compression ratio did Snowflake achieve?
--
-- 3. Run REMOVE on a test file you do not need:
--    Upload any small text file from your Mac using PUT,
--    verify it appears in LIST, then REMOVE it.
--    Confirm it is gone with LIST again.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if PUT fails with a permissions error?
-- A: Check that your role has WRITE privilege on the stage.
--    In Goal 1 Sub-task 1.5 we granted READ and WRITE on
--    ECOMMERCE_RAW_STAGE to SYSADMIN. Confirm your current
--    role with SELECT CURRENT_ROLE() and that it has access.
--
-- Q: What if PUT times out on large files?
-- A: Increase PARALLEL (up to 99) to use more upload threads.
--    Also check your internet connection — a 200MB file on
--    a slow connection will take significantly longer.
--    SnowSQL automatically resumes interrupted uploads.
--
-- Q: What if I need to upload files from a server, not my laptop?
-- A: Use an external stage pointing to S3/Azure/GCS instead.
--    Files in cloud storage are accessible to Snowflake directly
--    without PUT — COPY INTO reads them from the cloud URL.
--    Covered in Sub-task 2.8 (external tables).
--
-- Q: What if the same file already exists in the stage?
-- A: Without OVERWRITE=TRUE, PUT skips files that already
--    exist in the stage. With OVERWRITE=TRUE it replaces them.
--    Default behaviour (no overwrite) protects against
--    accidental re-uploads — use OVERWRITE deliberately.
--
-- Q: What is the equivalent in Oracle?
-- A: Oracle requires files to be on the database server or
--    accessible via a CREATE DIRECTORY object and UTL_FILE.
--    PUT is far simpler — direct upload from your local machine
--    to Snowflake storage with no server access required.
