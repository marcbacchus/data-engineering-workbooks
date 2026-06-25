-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 2 : Get Data In
-- Sub-task 2.1 : Create and manage file format objects
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~20 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Goal 1 complete
--                    ECOMMERCE database with RAW, STAGING,
--                    ANALYTICS schemas
--                    WORKBOOK_WH exists
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Before loading a single row of data, Snowflake needs to know
--   how your files are structured. Are fields comma-separated?
--   Are strings quoted? How are nulls represented?
--   What is the date format? Is the file compressed?
--
--   File format objects answer these questions once, in a named,
--   reusable object. Without them, every COPY INTO statement
--   carries inline format options — verbose, error-prone, and
--   inconsistent across scripts.
--
--   This sub-task creates three file format objects:
--   · CSV_FORMAT    — for all 8 e-commerce CSV tables
--   · JSON_FORMAT   — for the product_reviews JSON supplement
--   · PARQUET_FORMAT — for the product_reviews Parquet supplement
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: FILE FORMAT OBJECTS
-- ══════════════════════════════════════════════════════════════
--
-- A file format object is a named, reusable set of parsing
-- instructions that tells Snowflake how to interpret files
-- in a stage before loading them into tables.
--
-- Supported file types:
--   CSV      — delimited text (most common for tabular data)
--   JSON     — semi-structured key-value (APIs, event streams)
--   PARQUET  — columnar binary (data lakes, Spark, Databricks)
--   AVRO     — binary with embedded schema (Kafka pipelines)
--   ORC      — columnar binary (Hive/Hadoop origin, declining)
--   XML      — hierarchical markup
--
-- KEY CSV OPTIONS:
--   FIELD_DELIMITER          — character separating fields (default ',')
--   RECORD_DELIMITER         — character separating rows (default newline)
--   FIELD_OPTIONALLY_ENCLOSED_BY — quote character around fields
--   SKIP_HEADER              — number of header rows to skip
--   NULL_IF                  — strings to treat as NULL
--   EMPTY_FIELD_AS_NULL      — treat empty fields as NULL
--   DATE_FORMAT              — how to parse date strings
--   TIMESTAMP_FORMAT         — how to parse timestamp strings
--   TRIM_SPACE               — strip leading/trailing spaces
--   ERROR_ON_COLUMN_COUNT_MISMATCH — fail if column count wrong
--   ENCODING                 — file character encoding
--   COMPRESSION              — file compression type
--
-- Oracle equivalent:
--   SQL*Loader control files (.ctl) define parsing rules.
--   A Snowflake file format object is the direct equivalent —
--   named, reusable, managed as a first-class database object
--   rather than a flat file on disk.
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);

-- Recreate ECOMMERCE if needed
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

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Inspect your source files before creating formats
-- ══════════════════════════════════════════════════════════════
-- Run in Terminal (Mac/Linux) or Command Prompt / PowerShell (Windows)
-- Always verify file characteristics before encoding them into
-- a format object — assumptions cause the most common load errors.

-- ── Mac / Linux ───────────────────────────────────────────────
-- List all files and sizes:
--   ls -lh ~/projects/data-engineering-workbooks/dataset/
--
-- Preview first 5 rows of a CSV:
--   head -5 ~/projects/data-engineering-workbooks/dataset/suppliers.csv
--
-- Count rows including header:
--   wc -l ~/projects/data-engineering-workbooks/dataset/suppliers.csv
--
-- Preview JSON structure:
--   head -20 ~/projects/data-engineering-workbooks/dataset/product_reviews.json

-- ── Windows (Command Prompt) ──────────────────────────────────
-- List files:
--   dir C:\Users\YourName\projects\data-engineering-workbooks\dataset\
--
-- Preview CSV first rows:
--   type C:\Users\YourName\projects\data-engineering-workbooks\dataset\suppliers.csv | more
--
-- ── Windows (PowerShell) ──────────────────────────────────────
-- List files with sizes:
--   Get-ChildItem ~\projects\data-engineering-workbooks\dataset\
--
-- Preview first 5 rows:
--   Get-Content ~\projects\data-engineering-workbooks\dataset\suppliers.csv -TotalCount 5

-- ── What to confirm for CSV files ─────────────────────────────
-- · First row is the header (column names)
-- · Fields separated by commas
-- · Strings optionally enclosed in double quotes
-- · Timestamps in YYYY-MM-DD HH:MI:SS format
-- · Dates in YYYY-MM-DD format
-- · Empty fields represent NULL
-- · UTF-8 encoding, uncompressed

-- ── What to confirm for the JSON file ─────────────────────────
-- · File is a JSON array (starts with [)
-- · Each element is a JSON object (starts with {)
-- · Nested objects exist (product, metadata)
-- · Arrays exist within objects (metadata.tags)

-- ── What to confirm for the Parquet file ──────────────────────
-- · Binary file — cannot preview with head/type
-- · Use Python to inspect: python3 -c "import pyarrow.parquet as pq;
--   print(pq.read_table('dataset/product_reviews.parquet').schema)"
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create the CSV file format
-- ══════════════════════════════════════════════════════════════
-- Handles all 8 e-commerce CSV tables.
-- One format object, used by all COPY INTO statements.

CREATE OR REPLACE FILE FORMAT ECOMMERCE.RAW.CSV_FORMAT
    TYPE                            = CSV
    FIELD_DELIMITER                 = ','
    RECORD_DELIMITER                = '\n'
    SKIP_HEADER                     = 1
    FIELD_OPTIONALLY_ENCLOSED_BY    = '"'
    NULL_IF                         = ('NULL', 'null', 'NA', 'N/A', 'n/a', '')
    EMPTY_FIELD_AS_NULL             = TRUE
    DATE_FORMAT                     = 'YYYY-MM-DD'
    TIMESTAMP_FORMAT                = 'YYYY-MM-DD HH24:MI:SS'
    TRIM_SPACE                      = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH  = TRUE
    ENCODING                        = 'UTF8'
    COMPRESSION                     = AUTO
    COMMENT                         = 'Standard CSV format for e-commerce dataset'
;

-- Verify
SHOW FILE FORMATS IN SCHEMA ECOMMERCE.RAW;

SELECT
    "name"      AS format_name,
    "type"      AS format_type,
    "comment"   AS description
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Create the JSON file format
-- ══════════════════════════════════════════════════════════════
-- For loading product_reviews.json — a JSON array where each
-- element is a review object with nested product and metadata.
-- Used in Sub-task 2.5 (semi-structured data).

-- STRIP_OUTER_ARRAY = TRUE  → file is a JSON array  [ {...}, {...} ]
-- STRIP_OUTER_ARRAY = FALSE → file is NDJSON (Newline Delimited JSON)        {...}\n{...}


CREATE OR REPLACE FILE FORMAT ECOMMERCE.RAW.JSON_FORMAT
    TYPE                = JSON
    STRIP_OUTER_ARRAY   = TRUE    -- file is a JSON array — strip the outer []
    STRIP_NULL_VALUES   = FALSE   -- preserve explicit nulls
    IGNORE_UTF8_ERRORS  = FALSE   -- fail on encoding errors
    COMPRESSION         = AUTO
    COMMENT             = 'JSON format for semi-structured product reviews'
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Create the Parquet file format
-- ══════════════════════════════════════════════════════════════
-- For loading product_reviews.parquet — same data as the JSON
-- supplement but in Parquet columnar binary format with Snappy
-- compression. Used in Sub-task 2.5 alongside JSON.
--
-- Why Parquet matters:
--   · Dominant format in modern data lakes (S3, Azure, GCS)
--   · Used by Spark, Databricks, Glue, and Azure Data Factory
--   · Columnar storage = much smaller files than CSV or JSON
--   · Same 10,000 rows: CSV = 54MB, JSON = 5.9MB, Parquet = 0.4MB
--   · Schema is embedded — no need to define column types manually
--
-- Parquet format options are minimal — the schema is self-describing:
--   SNAPPY_COMPRESSION  — most common, good balance of speed and size
--   BINARY_AS_TEXT      — treat binary columns as VARCHAR
--   TRIM_SPACE          — strip whitespace from string columns

CREATE OR REPLACE FILE FORMAT ECOMMERCE.RAW.PARQUET_FORMAT
    TYPE                = PARQUET
    SNAPPY_COMPRESSION  = TRUE
    BINARY_AS_TEXT      = FALSE
    TRIM_SPACE          = TRUE
    COMMENT             = 'Parquet format for columnar binary data — Snappy compressed'
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Verify all three formats exist
-- ══════════════════════════════════════════════════════════════

SELECT
    FILE_FORMAT_NAME,
    FILE_FORMAT_TYPE,
    COMMENT
FROM ECOMMERCE.INFORMATION_SCHEMA.FILE_FORMATS
WHERE FILE_FORMAT_SCHEMA = 'RAW'
ORDER BY FILE_FORMAT_NAME
;
-- Expected:
-- CSV_FORMAT     | CSV     | Standard CSV format...
-- JSON_FORMAT    | JSON    | JSON format for semi-structured...
-- PARQUET_FORMAT | PARQUET | Parquet format for columnar...

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Inspect format definitions
-- ══════════════════════════════════════════════════════════════
-- GET_DDL works on file formats just like tables and views.

SELECT GET_DDL('FILE_FORMAT', 'ECOMMERCE.RAW.CSV_FORMAT');
SELECT GET_DDL('FILE_FORMAT', 'ECOMMERCE.RAW.JSON_FORMAT');
SELECT GET_DDL('FILE_FORMAT', 'ECOMMERCE.RAW.PARQUET_FORMAT');

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Named vs inline format — why named wins
-- ══════════════════════════════════════════════════════════════
--
-- INLINE (avoid in production):
-- COPY INTO table FROM @stage
--     FILE_FORMAT = (
--         TYPE = CSV
--         SKIP_HEADER = 1
--         FIELD_OPTIONALLY_ENCLOSED_BY = '"'
--         -- ... 8 more options
--     );
--
-- NAMED (use this):
-- COPY INTO table FROM @stage
--     FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT');
--
-- Named format benefits:
--   · One place to update when source format changes
--   · Consistent parsing across all load scripts
--   · Auditable — GET_DDL shows exactly what was used
--   · Shorter, cleaner COPY INTO statements

-- ══════════════════════════════════════════════════════════════
-- WHAT'S NEXT
-- ══════════════════════════════════════════════════════════════
-- Three file formats are ready:
--   CSV_FORMAT     → used in Sub-task 2.3 (load all 8 CSV tables)
--   JSON_FORMAT    → used in Sub-task 2.5 (semi-structured data)
--   PARQUET_FORMAT → used in Sub-task 2.5 (semi-structured data)
--
-- In Sub-task 2.2 you will stage all 10 files:
--   8 CSV files + product_reviews.json + product_reviews.parquet

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a PIPE_FORMAT for pipe-delimited files (|):
--    FIELD_DELIMITER = '|', SKIP_HEADER = 1,
--    NULL_IF = ('NULL', ''), EMPTY_FIELD_AS_NULL = TRUE.
--    When would you use this instead of CSV_FORMAT?
--
-- 2. Query INFORMATION_SCHEMA.FILE_FORMATS to find all
--    formats across all schemas in ECOMMERCE.
--    How many exist? What schemas are they in?
--
-- 3. What would happen if you tried to load the JSON file
--    using CSV_FORMAT instead of JSON_FORMAT?
--    Answer conceptually — you will see the difference
--    in Sub-task 2.5.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if my CSV has Windows line endings (\r\n)?
-- A: Set RECORD_DELIMITER = '\r\n' or use AUTO detection.
--    Windows line endings cause mysterious ^M characters
--    in loaded data if not handled correctly.
--
-- Q: What if different tables need different date formats?
-- A: Create separate file format objects — one per source
--    system or format variation. File formats are cheap.
--
-- Q: What if I need to load compressed CSV files?
-- A: Set COMPRESSION = GZIP or use AUTO to detect.
--    Snowflake decompresses on the fly during load.
--
-- Q: What makes Parquet better than CSV for large datasets?
-- A: Three things: columnar storage (only reads columns
--    you query), built-in compression (0.4MB vs 54MB for
--    the same 10,000 rows), and embedded schema (no need
--    to define types — Snowflake reads them from the file).
--    This is why data lakes use Parquet, not CSV.
--
-- Q: What if my JSON is newline-delimited (NDJSON) instead
--    of an array?
-- A: Set STRIP_OUTER_ARRAY = FALSE. NDJSON has one JSON
--    object per line — no outer array wrapper. Snowflake
--    handles both formats, you just need the right setting.
