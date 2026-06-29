-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 2 : Get Data In
-- Sub-task 2.4 : Handle load errors
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~25 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : 03_copy_into.sql completed
--                    All 8 CSV tables loaded in ECOMMERCE.RAW
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Every practitioner eventually hits a load error. A type
--   mismatch, a malformed row, a date in the wrong format,
--   an extra column, a file with Windows line endings.
--
--   Knowing how to diagnose and handle these errors is what
--   separates practitioners who get stuck for hours from those
--   who fix the issue in minutes. This sub-task teaches you:
--   · How to validate files before loading
--   · What the ON_ERROR options actually do
--   · How to inspect rejected rows
--   · How to use LOAD_HISTORY and COPY_HISTORY for diagnosis
--   · How to recover from a failed load
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE THREE ON_ERROR OPTIONS
-- ══════════════════════════════════════════════════════════════
--
-- ABORT_STATEMENT (default)
--   Stop immediately on the first error. No rows are loaded.
--   The table remains unchanged. Safe for production loads
--   where you want all-or-nothing behaviour.
--   Use when: data quality is critical, partial loads are
--   worse than no load at all.
--
-- CONTINUE
--   Skip bad rows and load everything else. Rejected rows
--   are written to a separate error file in the stage.
--   The load completes with a summary of errors.
--   Use when: some bad rows are acceptable and you want
--   maximum throughput. Always check error counts after.
--
-- SKIP_FILE
--   If any row in a file fails, skip the entire file.
--   Other files in the same COPY INTO still load.
--   Use when: loading multiple files and one bad file
--   should not block the others.
--
-- VALIDATION_MODE (not an ON_ERROR option — a separate parameter)
--   Checks the file against the table definition without
--   loading any data. Returns errors that would have occurred.
--   Use this BEFORE every production load as a dry run.
--
-- Oracle equivalent:
--   SQL*Loader ON_ERROR behaviour is similar but controlled
--   via ERRORS= in the control file. VALIDATION_MODE has no
--   direct equivalent — the closest is SQL*Loader SKIP= with
--   a test run. Snowflake's approach is cleaner and faster.
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create a deliberately broken CSV file for testing
-- ══════════════════════════════════════════════════════════════
-- We need bad data to demonstrate error handling.
-- Create a test table and stage a broken CSV using SnowSQL PUT.
--
-- First create the target table:

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ERROR_TEST (
    id          INTEGER,
    name        VARCHAR(100),
    price       FLOAT,
    created_at  DATE
)
COMMENT = 'Error handling test table — dropped in cleanup'
;

-- ══════════════════════════════════════════════════════════════
-- ACTION REQUIRED: Run a script to create and stage the test file
-- ══════════════════════════════════════════════════════════════
-- Scripts are in: goal-02-get-data-in/scripts/
-- They create a broken CSV and upload it to your stage via SnowSQL.
-- Run the script for your platform BEFORE continuing in Snowsight.
--
-- Mac / Linux — open Terminal:
--   cd ~/projects/data-engineering-workbooks
--   bash 01-snowflake/goal-02-get-data-in/scripts/create_error_test_mac.sh
--
-- Windows — open PowerShell:
--   cd C:\Users\YourName\projects\data-engineering-workbooks
--   .\01-snowflake\goal-02-get-data-in\scripts\create_error_test_windows.ps1
--
--   Note: if you see an execution policy error run this first:
--   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
--
-- The script will:
--   1. Create error_test.csv with 5 rows (2 deliberately broken)
--   2. Upload it to ECOMMERCE_RAW_STAGE via SnowSQL automatically
--   3. Confirm success and tell you to return to Snowsight
--
-- Broken rows intentionally created:
--   Row 2: NOT_A_NUMBER in the price column (FLOAT) — type mismatch
--   Row 3: NOT_A_DATE in the created_at column (DATE) — type mismatch
--   Rows 1, 4, 5: valid — will load successfully with ON_ERROR=CONTINUE
-- ══════════════════════════════════════════════════════════════

-- Verify it was staged (run in Snowsight):
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE PATTERN='.*error_test.*';

-- ══════════════════════════════════════════════════════════════
-- STEP 2: VALIDATION_MODE — check before you load
-- ══════════════════════════════════════════════════════════════
-- Always validate before loading in production.
-- VALIDATION_MODE checks the file against your table definition
-- and file format without loading any data.
-- Think of it as a dry run.

COPY INTO ECOMMERCE.RAW.ERROR_TEST
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/error_test.csv
    FILE_FORMAT     = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    VALIDATION_MODE = RETURN_ERRORS
;

-- Expected output — two error rows:
-- Row 2: "NOT_A_NUMBER" cannot be cast to FLOAT (price column)
-- Row 3: "NOT_A_DATE" cannot be cast to DATE (created_at column)
--
-- Key columns in the output:
--   ERROR             — what went wrong
--   FILE              — which file contained the error
--   LINE              — line number in the file
--   CHARACTER         — character position
--   COLUMN_NAME       — which column failed
--   ROW_NUMBER        - the row in the datafile that was affected
--   COLUMN_TYPE       — expected data type
--   CELL_VALUE        — the actual value that failed
--
-- No rows were loaded — VALIDATION_MODE never touches the table.
-- Zero credits consumed for the actual load (only scan credits).
-- Fix the errors before proceeding to the real COPY INTO.

-- ══════════════════════════════════════════════════════════════
-- STEP 3: RETURN_ALL_ERRORS — see every error at once
-- ══════════════════════════════════════════════════════════════
-- RETURN_ERRORS     — returns all errors, stops processing after scanning the file
-- RETURN_ALL_ERRORS — returns all errors across ALL files if multiple files are loaded
-- Use this for a complete picture before fixing source data.

COPY INTO ECOMMERCE.RAW.ERROR_TEST
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/error_test.csv
    FILE_FORMAT     = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    VALIDATION_MODE = RETURN_ALL_ERRORS
;
-- Shows both errors (row 2 and row 3) in one result.
-- More useful than RETURN_ERRORS for files with multiple issues.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: ON_ERROR = ABORT_STATEMENT (default behaviour)
-- ══════════════════════════════════════════════════════════════
-- Now actually try to load the broken file.
-- ABORT_STATEMENT stops on the first error — nothing loads.

COPY INTO ECOMMERCE.RAW.ERROR_TEST
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/error_test.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;
-- ── Expected error ────────────────────────────────────────────
-- Numeric value 'NOT_A_NUMBER' is not recognized
-- File 'error_test.csv', line 3, character 12
-- Row 2, column "ERROR_TEST"["PRICE":3]
-- If you would like to continue loading when an error is
-- encountered, use other values such as 'SKIP_FILE' or
-- 'CONTINUE' for the ON_ERROR option.
--
-- Reading the error message:
--   · line 3         — line 3 in the file (line 1 = header,
--                       line 2 = row 1, line 3 = row 2)
--   · character 12   — position in the line where it failed
--   · "PRICE":3      — column name and position (3rd column)
--   · NOT_A_NUMBER   — the actual value that could not be cast
--
-- Snowflake even suggests the fix: use CONTINUE or SKIP_FILE.
-- This is one of the clearest error messages in the platform.
-- ─────────────────────────────────────────────────────────────

-- Verify nothing was loaded
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ERROR_TEST;
-- Expected: 0 — table is empty, ABORT left it unchanged

-- ══════════════════════════════════════════════════════════════
-- STEP 5: ON_ERROR = CONTINUE — skip bad rows, load the rest
-- ══════════════════════════════════════════════════════════════
-- CONTINUE skips rows that fail and loads everything else.
-- Bad rows are written to an error file in the stage.

COPY INTO ECOMMERCE.RAW.ERROR_TEST
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/error_test.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = CONTINUE
;
-- Expected output summary:
--   rows_loaded   = 3  (rows 1, 4, 5 — the good ones)
--   rows_parsed   = 5  (all rows attempted)
--   errors_seen   = 2  (rows 2 and 3 failed)
--   first_error   = Numeric value 'NOT_A_NUMBER'...
--   error_file    = path to rejected rows file in stage

-- Verify 3 rows loaded (the good ones)
SELECT * FROM ECOMMERCE.RAW.ERROR_TEST;
-- Expected: rows 1, 4, 5
-- Rows 2 and 3 were skipped

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Inspect rejected rows using VALIDATE()
--         Run in: Snowsight
-- ══════════════════════════════════════════════════════════════
-- With named internal stages, Snowflake does NOT write rejected
-- rows to a separate error file. Instead use VALIDATE() to
-- inspect what was rejected after an ON_ERROR = CONTINUE load.

SELECT *
FROM TABLE(VALIDATE(
    ECOMMERCE.RAW.ERROR_TEST,
    JOB_ID => '_last'
))
;
-- Returns the rejected rows with full error details:
--   ERROR             — what went wrong
--   FILE              — which file contained the error
--   LINE              — line number in the file
--   CHARACTER         — character position
--   COLUMN_NAME       — which column failed
--   COLUMN_TYPE       — expected data type
--   CELL_VALUE        — the actual value that failed
--
-- Note: separate error files in the stage are created when
-- using EXTERNAL stages (S3/Azure/GCS). With named internal
-- stages, VALIDATE() is your primary diagnostic tool.

-- ══════════════════════════════════════════════════════════════
-- STEP 7: ON_ERROR = SKIP_FILE
-- ══════════════════════════════════════════════════════════════
-- SKIP_FILE skips the entire file if any row fails.
-- Useful when loading multiple files simultaneously.

-- First truncate the table to start fresh
TRUNCATE TABLE ECOMMERCE.RAW.ERROR_TEST;
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ERROR_TEST;
-- Expected: 0

COPY INTO ECOMMERCE.RAW.ERROR_TEST
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/error_test.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = SKIP_FILE
;
-- Expected: 0 rows loaded
-- The entire file was skipped because it contained errors.
-- No partial data — cleaner than CONTINUE for some use cases.

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ERROR_TEST;
-- Expected: 0

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Check LOAD_HISTORY for error diagnosis
-- ══════════════════════════════════════════════════════════════
-- LOAD_HISTORY tracks every COPY INTO attempt including failures.
-- Essential for post-incident diagnosis.

SELECT
    TABLE_NAME,
    FILE_NAME,
    STATUS,
    ROW_COUNT,
    ROW_PARSED,
    ERROR_COUNT,
    FIRST_ERROR_MESSAGE,
    FIRST_ERROR_LINE_NUMBER,
    FIRST_ERROR_COL_NAME,
    LAST_LOAD_TIME
   
FROM ECOMMERCE.INFORMATION_SCHEMA.LOAD_HISTORY
WHERE SCHEMA_NAME  = 'RAW'
  AND TABLE_NAME   = 'ERROR_TEST'
ORDER BY LAST_LOAD_TIME DESC
;
-- You should see multiple entries — one per COPY INTO attempt:
--   ABORT_STATEMENT run: STATUS = LOAD_FAILED
--   CONTINUE run:        STATUS = PARTIALLY_LOADED
--   SKIP_FILE run:       STATUS = LOAD_SKIPPED
--
-- FIRST_ERROR_MESSAGE tells you exactly what went wrong
-- without having to re-run the load.

-- ══════════════════════════════════════════════════════════════
-- STEP 9: Recovery pattern — truncate and reload
-- ══════════════════════════════════════════════════════════════
-- The standard recovery workflow after a failed or partial load:

-- 1. Identify the error (LOAD_HISTORY or VALIDATE())
-- 2. Fix the source data
-- 3. Re-stage the fixed file (PUT with OVERWRITE=TRUE)
-- 4. Truncate the table if partially loaded
TRUNCATE TABLE ECOMMERCE.RAW.ERROR_TEST;

-- 5. Reload with FORCE = TRUE (bypasses load deduplication)
--    since the file path is the same as the failed attempt
-- COPY INTO ECOMMERCE.RAW.ERROR_TEST
-- FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/error_test.csv
--     FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
--     ON_ERROR    = ABORT_STATEMENT
--     FORCE       = TRUE
-- ;
-- Commented out — error_test.csv still has bad rows.
-- In practice you fix the source file before this step.

-- Alternative recovery without FORCE:
-- If you fix the file and re-stage with a different name
-- (error_test_fixed.csv), load deduplication does not apply
-- because the file name is different. No FORCE needed.

-- ══════════════════════════════════════════════════════════════
-- STEP 10: Common load errors and their causes
-- ══════════════════════════════════════════════════════════════
-- Reference guide for the errors you will encounter most often.
--
-- ERROR: "Numeric value 'X' is not recognized"
--   CAUSE:  Non-numeric value in a FLOAT or INTEGER column
--   FIX:    Check source data for nulls or text in numeric cols
--           Or load as VARCHAR and cast in a transform step
--
-- ERROR: "Date 'X' is not recognized"
--   CAUSE:  Date format does not match DATE_FORMAT in file format
--   FIX:    Update DATE_FORMAT in CSV_FORMAT to match source
--           Common culprits: MM/DD/YYYY vs YYYY-MM-DD
--
-- ERROR: "Boolean value 'X' is not recognized"
--   CAUSE:  Source uses non-standard boolean values
--           (e.g. 'Y'/'N', '1'/'0', 'yes'/'no')
--   FIX:    Load as VARCHAR, cast with IFF() in transform
--           Or use COPY INTO with a SELECT transformation
--
-- ERROR: "Number of columns in file does not match"
--   CAUSE:  Extra/missing delimiters in a row (often commas
--           inside unquoted text fields)
--   FIX:    Add FIELD_OPTIONALLY_ENCLOSED_BY = '"' to format
--           Or check source for unescaped delimiters
--
-- ERROR: "Max row size exceeded"
--   CAUSE:  A row is too large (over 16MB)
--   FIX:    Split large fields or use VARIANT column for
--           semi-structured data instead
--
-- ERROR: "UTF-8 character encoding error"
--   CAUSE:  File has non-UTF8 characters (e.g. Latin-1)
--   FIX:    Set ENCODING = 'ISO-8859-1' (or correct encoding)
--           Or re-encode the file to UTF-8 before staging
--
-- ERROR: "^M characters in data" (not a Snowflake error message
--        but a symptom you see in query results)
--   CAUSE:  Windows line endings (\r\n) not handled
--   FIX:    Set RECORD_DELIMITER = '\r\n' in CSV_FORMAT

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════

-- Drop the error test table
DROP TABLE IF EXISTS ECOMMERCE.RAW.ERROR_TEST;

-- Remove error test files from stage
REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE PATTERN='.*error_test.*';

-- Verify
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE PATTERN='.*error.*';
-- Should return zero rows

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a new broken CSV with these errors:
--    · A row with too many columns (extra comma in a text field)
--    · A row with a boolean column containing 'Y' instead of True
--    · A row with a date in MM/DD/YYYY format
--    Stage it and use VALIDATION_MODE = RETURN_ALL_ERRORS.
--    What error messages does Snowflake return for each?
--
-- 2. Load the broken file with ON_ERROR = CONTINUE.
--    How many rows loaded? How many were skipped?
--    Find the error file in the stage and query it.
--
-- 3. Look at LOAD_HISTORY for the ORDERS table from Sub-task 2.3.
--    What was the STATUS? How many rows were parsed vs loaded?
--    Was ERROR_COUNT = 0?
--
-- 4. What is the difference between TRUNCATE TABLE and
--    DELETE FROM table (no WHERE clause)?
--    When would you use each before a reload?
--    (Hint: think about Time Travel and transaction behaviour)

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I accidentally loaded duplicate data using FORCE=TRUE?
-- A: Use Time Travel to recover the pre-load state:
--    CREATE OR REPLACE TABLE table_name CLONE table_name
--        BEFORE (STATEMENT => '<query_id_of_the_copy_into>');
--    Or simply truncate and reload from the correct source.
--    Time Travel is covered in detail in Goal 8.
--
-- Q: What if my file has millions of rows and only a few are bad?
-- A: Use ON_ERROR = CONTINUE to load the good rows, then
--    fix and reload just the bad rows separately.
--    Use VALIDATE() after the load to get the full error list.
--    Then INSERT the corrected rows directly.
--
-- Q: What if LOAD_HISTORY does not show my recent load?
-- A: INFORMATION_SCHEMA.LOAD_HISTORY is near real-time but
--    scoped to the current database. For account-wide history
--    use SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY — it has up to
--    365 days of history but with a 2-3 hour latency.
--    Covered in Goal 9 (monitoring).
--
-- Q: What if the error is in the last row of a very large file?
-- A: With ABORT_STATEMENT the entire load fails even if
--    99.9% of rows were valid. For large files consider:
--    1. Run VALIDATION_MODE first to find all errors upfront
--    2. Fix the source file before loading
--    3. Use ON_ERROR = CONTINUE if some bad rows are acceptable
--    Preventing errors is always better than recovering from them.
--
-- Q: What is the Oracle SQL*Loader equivalent?
-- A: SQL*Loader writes rejected rows to a .bad file and
--    errors to a .log file. Snowflake's approach is cleaner:
--    VALIDATE() replaces the .log file inspection, and the
--    error file in the stage replaces the .bad file.
--    LOAD_HISTORY replaces manually reading .log files after
--    every load — it is queryable SQL, not a flat text file.