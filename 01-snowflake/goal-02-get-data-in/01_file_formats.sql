-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 2 : Get Data In
-- Sub-task 2.1 : Create and manage file format objects
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~20 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : Goal 1 complete
--                    ECOMMERCE database exists with RAW, STAGING,
--                    ANALYTICS schemas
--                    WORKBOOK_WH exists
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Before loading a single row of data, Snowflake needs to know
--   how your files are structured. Are fields comma-separated or
--   pipe-separated? Are strings quoted? How are nulls represented?
--   What is the date format?
--
--   File format objects answer these questions once, in a named,
--   reusable object. Without them, every COPY INTO statement
--   carries inline format options — verbose, error-prone, and
--   inconsistent across scripts.
--
--   This sub-task creates the file format objects you will use
--   to load the entire e-commerce dataset in Sub-tasks 2.2 and 2.3.
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
--   CSV       — delimited text files (most common)
--   JSON      — semi-structured, key-value pairs
--   AVRO      — binary, schema-embedded
--   ORC       — columnar binary (Hive/Hadoop origin)
--   PARQUET   — columnar binary (most common in data lakes)
--   XML       — hierarchical markup
--
-- KEY CSV OPTIONS PRACTITIONERS NEED TO KNOW:
--
--   FIELD_DELIMITER          — character separating fields (default ',')
--   RECORD_DELIMITER         — character separating rows (default newline)
--   FIELD_OPTIONALLY_ENCLOSED_BY — quote character around fields (default NONE)
--   SKIP_HEADER              — number of header rows to skip (default 0)
--   NULL_IF                  — strings to treat as NULL (e.g. 'NULL', 'NA', '')
--   EMPTY_FIELD_AS_NULL      — treat empty fields as NULL (default TRUE)
--   DATE_FORMAT              — how to parse date strings (default AUTO)
--   TIMESTAMP_FORMAT         — how to parse timestamp strings (default AUTO)
--   TRIM_SPACE               — strip leading/trailing spaces (default FALSE)
--   ERROR_ON_COLUMN_COUNT_MISMATCH — fail if column count wrong (default TRUE)
--   ENCODING                 — file character encoding (default UTF8)
--   COMPRESSION              — file compression type (AUTO, GZIP, NONE, etc.)
--
-- WHERE FILE FORMATS LIVE:
--   File format objects live in a schema, just like tables and views.
--   Best practice: create them in the same schema as the stage
--   they will be used with.
--   We will create ours in ECOMMERCE.RAW.
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
-- STEP 1: Inspect your CSV files before creating formats
-- ══════════════════════════════════════════════════════════════
-- ── View your dataset files before creating formats ───────────
-- Run this in Terminal (not Snowsight) to inspect your files:
--
-- List all CSV files and their sizes:
--   ls -lh ~/projects/data-engineering-workbooks/dataset/*.csv
--
-- Preview the first few rows of any file:
--   head -5 ~/projects/data-engineering-workbooks/dataset/suppliers.csv
--
-- Count rows in a file (including header):
--   wc -l ~/projects/data-engineering-workbooks/dataset/suppliers.csv
--
-- Check the delimiter and quoting of the first row:
--   head -1 ~/projects/data-engineering-workbooks/dataset/orders.csv
--
-- This confirms your file characteristics before you encode
-- them into a file format object. Never assume — always verify.
-- ─────────────────────────────────────────────────────────────

-- Before creating a file format, understand your source data.
-- Our e-commerce dataset CSVs have these characteristics:
--   · Comma-delimited
--   · First row is a header
--   · Strings optionally enclosed in double quotes
--   · Empty fields represent NULL
--   · UTF-8 encoding
--   · Timestamps in YYYY-MM-DD HH:MI:SS format
--   · Dates in YYYY-MM-DD format
--   · Uncompressed
--
-- This matches the output of generate_dataset.py in /utils.
-- Always inspect source files before loading — assumptions
-- about format cause the most common load errors.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create the primary CSV file format
-- ══════════════════════════════════════════════════════════════
-- This format handles all 8 of our e-commerce CSV files.
-- One format object, used by all COPY INTO statements.

CREATE OR REPLACE FILE FORMAT ECOMMERCE.RAW.CSV_FORMAT
    TYPE                            = CSV
    FIELD_DELIMITER                 = ','
    RECORD_DELIMITER                = '\n'
    SKIP_HEADER                     = 1          -- skip the column header row
    FIELD_OPTIONALLY_ENCLOSED_BY    = '"'         -- handle quoted strings
    NULL_IF                         = ('NULL', 'null', 'NA', 'N/A', 'n/a', '')
    EMPTY_FIELD_AS_NULL             = TRUE
    DATE_FORMAT                     = 'YYYY-MM-DD'
    TIMESTAMP_FORMAT                = 'YYYY-MM-DD HH24:MI:SS'
    TRIM_SPACE                      = TRUE        -- strip accidental whitespace
    ERROR_ON_COLUMN_COUNT_MISMATCH  = TRUE        -- fail fast on bad files
    ENCODING                        = 'UTF8'
    COMPRESSION                     = AUTO        -- detect compression automatically
    COMMENT                         = 'Standard CSV format for e-commerce dataset'
;

-- Verify it was created
SHOW FILE FORMATS IN SCHEMA ECOMMERCE.RAW;

SELECT
    "name"          AS format_name,
    "type"          AS format_type,
    "comment"       AS description
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Inspect the file format definition
-- ══════════════════════════════════════════════════════════════
-- GET_DDL works on file formats just like tables and views.
-- Useful for documenting formats and comparing across environments.

SELECT GET_DDL('FILE_FORMAT', 'ECOMMERCE.RAW.CSV_FORMAT');

-- Query INFORMATION_SCHEMA for file format details
SELECT
    FILE_FORMAT_NAME,
    FILE_FORMAT_TYPE,
    FIELD_DELIMITER,
    SKIP_HEADER,
    NULL_IF,
    DATE_FORMAT,
    TIMESTAMP_FORMAT,
    COMMENT
FROM ECOMMERCE.INFORMATION_SCHEMA.FILE_FORMATS
WHERE FILE_FORMAT_SCHEMA = 'RAW'
ORDER BY FILE_FORMAT_NAME
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Create a JSON file format
-- ══════════════════════════════════════════════════════════════
-- Sub-task 2.5 loads semi-structured JSON data.
-- Create the format now so it is ready when needed.

CREATE OR REPLACE FILE FORMAT ECOMMERCE.RAW.JSON_FORMAT
    TYPE                = JSON
    STRIP_OUTER_ARRAY   = TRUE    -- if file is an array of JSON objects
    STRIP_NULL_VALUES   = FALSE   -- preserve explicit nulls
    IGNORE_UTF8_ERRORS  = FALSE   -- fail on encoding errors
    COMPRESSION         = AUTO
    COMMENT             = 'JSON format for semi-structured data loading'
;

-- Verify both formats exist
SELECT
    FILE_FORMAT_NAME,
    FILE_FORMAT_TYPE,
    COMMENT
FROM ECOMMERCE.INFORMATION_SCHEMA.FILE_FORMATS
WHERE FILE_FORMAT_SCHEMA = 'RAW'
ORDER BY FILE_FORMAT_NAME
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Understand inline vs named format options
-- ══════════════════════════════════════════════════════════════
-- You can specify format options inline in COPY INTO.
-- Named format objects are always preferred — they are
-- reusable, documented, and consistent.
--
-- INLINE (avoid in production):
-- COPY INTO table FROM @stage
--     FILE_FORMAT = (
--         TYPE = CSV
--         SKIP_HEADER = 1
--         FIELD_OPTIONALLY_ENCLOSED_BY = '"'
--     );
--
-- NAMED FORMAT (use this):
-- COPY INTO table FROM @stage
--     FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT');
--
-- The named format approach means:
--   · One place to update when format changes
--   · Consistent parsing across all load scripts
--   · Easier to audit and document
--   · Shorter, cleaner COPY INTO statements
--
-- Oracle equivalent:
--   SQL*Loader uses a control file (.ctl) to define parsing rules.
--   A Snowflake file format object is the direct equivalent —
--   named, reusable, and managed as a first-class database object
--   rather than a flat file on disk.

-- ══════════════════════════════════════════════════════════════
-- WHAT'S NEXT
-- ══════════════════════════════════════════════════════════════
-- In Sub-task 2.2 you will upload the e-commerce CSV files
-- to ECOMMERCE_RAW_STAGE using PUT from SnowSQL.
-- In Sub-task 2.3 you will load them into tables using
-- COPY INTO with CSV_FORMAT.
-- The file formats you created here are ready.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a third file format called PIPE_FORMAT in
--    ECOMMERCE.RAW for pipe-delimited files:
--    FIELD_DELIMITER = '|', SKIP_HEADER = 1,
--    NULL_IF = ('NULL', ''), EMPTY_FIELD_AS_NULL = TRUE.
--    When would you use this instead of CSV_FORMAT?
--
-- 2. Query INFORMATION_SCHEMA.FILE_FORMATS to find all
--    file formats across all schemas in ECOMMERCE.
--    How many exist? What schemas are they in?
--
-- 3. What happens if you load a CSV file that uses
--    semicolons as delimiters using CSV_FORMAT?
--    Answer conceptually — you will see this in action
--    in Sub-task 2.4 when we cover load error handling.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if my source files have inconsistent quoting —
--    some fields quoted, some not?
-- A: FIELD_OPTIONALLY_ENCLOSED_BY handles this.
--    "Optionally" means quoted fields are unquoted,
--    unquoted fields are left as-is. Never use
--    FIELD_ENCLOSED_BY (without OPTIONALLY) unless
--    every single field is always quoted.
--
-- Q: What if my CSV has Windows line endings (\r\n)?
-- A: Set RECORD_DELIMITER = '\r\n' or use AUTO detection.
--    Windows line endings are one of the most common
--    causes of mysterious extra characters in loaded data.
--    If you see ^M characters in your data, this is why.
--
-- Q: What if different tables need different date formats?
-- A: Create separate file format objects for each format.
--    File formats are cheap — create one per source system
--    rather than trying to handle everything with AUTO.
--
-- Q: What if I need to load compressed files?
-- A: Set COMPRESSION = GZIP (or BZIP2, DEFLATE, etc.)
--    or use AUTO to detect automatically. Snowflake
--    decompresses on the fly during load — no need to
--    decompress locally before staging.
