-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 2 : Get Data In
-- Sub-task 2.6 : Automate ingestion with Snowpipe
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~25 minutes
-- Warehouse size   : Serverless (Snowpipe manages its own compute)
-- Database         : ECOMMERCE
-- Run in           : Snowsight (all steps)
-- Prerequisites    : 03_copy_into.sql completed
--                    All 8 CSV tables loaded in ECOMMERCE.RAW
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Sub-task 2.3 showed you how to load files manually with
--   COPY INTO. That works perfectly for batch loads — but what
--   about data that arrives continuously? New orders every
--   minute, clickstream events every second, log files every
--   hour?
--
--   Snowpipe is Snowflake's continuous ingestion service. It
--   monitors a stage for new files and loads them automatically
--   the moment they arrive — without any manual COPY INTO.
--
--   This sub-task covers how Snowpipe works, how to create and
--   monitor a pipe, and how it differs from batch COPY INTO.
--   Full cloud event notification setup (S3 SQS, Azure Event Grid)
--   requires cloud provider configuration covered in the Azure
--   and AWS workbooks. Here we focus on Snowpipe fundamentals
--   using REST API calls — available on all cloud providers.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: HOW SNOWPIPE WORKS
-- ══════════════════════════════════════════════════════════════
--
-- COPY INTO (batch):
--   You run it manually or on a schedule (Task).
--   One warehouse processes all files in a single operation.
--   Best for: large batch loads, nightly ETL, controlled loads.
--
-- Snowpipe (continuous):
--   Files arrive in a stage → Snowpipe detects them → loads them
--   automatically. No warehouse needed — Snowpipe uses its own
--   serverless compute managed by Snowflake.
--   Best for: real-time or near-real-time ingestion, streaming
--   data, IoT events, log files, API webhooks.
--
-- TWO TRIGGER MECHANISMS:
--   1. Cloud event notifications (recommended for production)
--      S3 → SQS → Snowpipe
--      Azure Blob → Event Grid → Snowpipe
--      GCS → Pub/Sub → Snowpipe
--      Files trigger Snowpipe the moment they land in storage.
--      Covered in Azure (Workbook 4) and AWS (Workbook 6).
--
--   2. REST API (covered here)
--      Your application calls Snowpipe's REST endpoint to signal
--      that new files are ready. Snowpipe loads them on demand.
--      More control, slightly more complexity.
--      Works on any cloud provider without event notification setup.
--
-- COST MODEL:
--   Snowpipe does NOT consume your virtual warehouse credits.
--   It uses Snowflake-managed serverless compute billed separately
--   at a per-second rate. Typically more expensive per-credit than
--   a warehouse but only runs when actively loading — no idle cost.
--
-- KEY DIFFERENCE FROM COPY INTO:
--   COPY INTO:  you control when it runs, warehouse credits consumed
--   Snowpipe:   runs automatically, serverless credits consumed,
--               lower latency (seconds vs minutes for batch)
--
-- Oracle equivalent:
--   Oracle has no direct equivalent. The closest is Oracle GoldenGate
--   for continuous replication or external tables with scheduler jobs.
--   Snowpipe is significantly simpler to configure and operate.
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
-- STEP 1: Create a target table for Snowpipe
-- ══════════════════════════════════════════════════════════════
-- We create a separate table for Snowpipe-loaded orders so
-- it does not conflict with the batch-loaded ORDERS table.
-- In production you would typically pipe into the main table.

CREATE TABLE IF NOT EXISTS ECOMMERCE.RAW.ORDERS_PIPE (
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
COMMENT = 'Orders table loaded via Snowpipe — continuous ingestion demo'
;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create the pipe object
-- ══════════════════════════════════════════════════════════════
-- A pipe is a named Snowflake object that defines:
--   · Which stage to monitor
--   · Which table to load into
--   · Which file format to use
-- Once created and enabled, it runs continuously.

CREATE OR REPLACE PIPE ECOMMERCE.RAW.ORDERS_PIPE
    AUTO_INGEST = FALSE         -- we will trigger via REST API
                                -- set TRUE for cloud event notifications
    COMMENT = 'Snowpipe for continuous order ingestion'
AS
COPY INTO ECOMMERCE.RAW.ORDERS_PIPE
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    PATTERN     = '.*new_orders.*\\.csv'  -- only files matching this pattern
;
-- The COPY INTO inside the pipe definition is the template.
-- Snowpipe uses this exact statement when loading new files.
-- PATTERN restricts which files in the stage trigger this pipe —
-- essential when multiple pipes share the same stage.

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Inspect the pipe
-- ══════════════════════════════════════════════════════════════

SHOW PIPES IN SCHEMA ECOMMERCE.RAW;

SELECT
    "name"              AS pipe_name,
    "database_name"     AS database_name,
    "schema_name"       AS schema_name,
    "definition"        AS copy_statement,
    "owner"             AS owned_by,
    "comment"           AS description
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;

-- Get the pipe definition including the notification channel
-- (needed for cloud event notification setup)
SELECT SYSTEM$PIPE_STATUS('ECOMMERCE.RAW.ORDERS_PIPE');
-- Returns a JSON object with pipe status information:
--   executionState  — RUNNING or STOPPED
--   pendingFileCount — files waiting to be loaded
--   notificationChannelName — SQS/Event Grid endpoint for auto_ingest

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Understand AUTO_INGEST vs REST API
-- ══════════════════════════════════════════════════════════════
--
-- AUTO_INGEST = TRUE (cloud event notifications):
--   File lands in S3/Azure/GCS
--     → Cloud sends notification to Snowflake
--       → Snowpipe loads automatically
--   Zero manual intervention after setup.
--   Requires: storage integration + cloud event notification config.
--   Covered in Azure Workbook (Workbook 4) and AWS Workbook (Workbook 6).
--
-- AUTO_INGEST = FALSE (REST API — what we are using):
--   Your application or script calls:
--   POST https://<account>.snowflakecomputing.com/v1/data/pipes/<pipe>/insertFiles
--   with a list of staged file names.
--   Snowpipe loads those specific files immediately.
--   More control, works everywhere, no cloud config needed.
--
-- For this workbook we use AUTO_INGEST = FALSE because:
--   · It works on any cloud provider without additional setup
--   · It demonstrates the core Snowpipe concept clearly
--   · The AUTO_INGEST = TRUE setup is cloud-provider specific
--     and covered in the cloud workbooks

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Simulate a Snowpipe load using COPY INTO
-- ══════════════════════════════════════════════════════════════
-- In a real Snowpipe setup, files are loaded automatically.
-- Here we simulate what Snowpipe would do by running the
-- equivalent COPY INTO manually — so you can see the pattern
-- without needing cloud event notification setup.

-- First create a small "new orders" file to simulate
-- a file arriving in the stage. In production this would
-- come from your application or pipeline.
--
-- We extract a sample from the existing ORDERS table
-- and stage it as a new file using a COPY INTO <stage>:
COPY INTO @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/new_orders_sample.csv
FROM (
    SELECT
        order_id, customer_id, order_status, payment_method,
        shipping_method, shipping_country, order_total,
        shipping_date, delivery_date, created_at, shipping_region
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'placed'
    LIMIT 100
)
FILE_FORMAT = (
    TYPE                         = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('')
    TIMESTAMP_FORMAT             = 'YYYY-MM-DD HH24:MI:SS'
)
SINGLE    = TRUE
OVERWRITE = TRUE
;
-- This creates new_orders_sample.csv in the stage —
-- simulating a file that arrived from an upstream system.
-- SINGLE = TRUE writes one file instead of multiple parts.

-- Verify the file is staged
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE PATTERN='.*new_orders.*';

-- Now simulate what Snowpipe would do automatically —
-- load the new file into the pipe target table
COPY INTO ECOMMERCE.RAW.ORDERS_PIPE
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/new_orders_sample.csv
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.CSV_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;


SELECT COUNT(*) AS rows_loaded FROM ECOMMERCE.RAW.ORDERS_PIPE;
-- Expected: 100 rows — the placed orders we extracted

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Monitor pipe activity
-- ══════════════════════════════════════════════════════════════
-- In production, monitor your pipes regularly to catch
-- failures, backlogs, and performance issues.

-- Current pipe status
SELECT PARSE_JSON(SYSTEM$PIPE_STATUS('ECOMMERCE.RAW.ORDERS_PIPE'))
                                        AS pipe_status
;

-- Extract key fields from the status JSON
SELECT
    PARSE_JSON(SYSTEM$PIPE_STATUS('ECOMMERCE.RAW.ORDERS_PIPE')):executionState::VARCHAR
                                        AS execution_state,
    PARSE_JSON(SYSTEM$PIPE_STATUS('ECOMMERCE.RAW.ORDERS_PIPE')):pendingFileCount::INTEGER
                                        AS pending_files,
    PARSE_JSON(SYSTEM$PIPE_STATUS('ECOMMERCE.RAW.ORDERS_PIPE')):lastIngestedTimestamp::VARCHAR
                                        AS last_ingested_at
;


SELECT *
FROM TABLE(INFORMATION_SCHEMA.PIPE_USAGE_HISTORY(
    DATE_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
    DATE_RANGE_END   => CURRENT_TIMESTAMP(),
    PIPE_NAME        => 'ECOMMERCE.RAW.ORDERS_PIPE'
))
ORDER BY START_TIME DESC
;
-- Returns zero rows when load was simulated via manual COPY INTO.
-- In production with AUTO_INGEST = TRUE each row shows:
--   START_TIME, END_TIME  — when Snowpipe was active
--   PIPE_NAME             — which pipe ran
--   CREDITS_USED          — serverless compute credits consumed
--   BYTES_INSERTED        — data volume loaded
--   BYTES_BILLED          — data volume billed (minimum 128MB)
--   FILES_INSERTED        — number of files processed
--
-- Note: PIPE_USAGE_HISTORY tracks Snowpipe CREDIT consumption
-- not individual file loads. For file-level detail use
-- ACCOUNT_USAGE.COPY_HISTORY (2-3 hour latency).

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Pause and resume a pipe
-- ══════════════════════════════════════════════════════════════
-- Pipes can be paused for maintenance without being dropped.
-- Files that arrive while paused are queued and loaded
-- when the pipe resumes (within a 14-day window).

-- Pause the pipe
ALTER PIPE ECOMMERCE.RAW.ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = TRUE;

-- Verify pause state using SYSTEM$PIPE_STATUS
SELECT PARSE_JSON(SYSTEM$PIPE_STATUS('ECOMMERCE.RAW.ORDERS_PIPE')):executionState::VARCHAR
    AS execution_state
;
-- Expected: PAUSED

-- Resume the pipe
ALTER PIPE ECOMMERCE.RAW.ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = FALSE;

-- Verify resumed
SELECT PARSE_JSON(SYSTEM$PIPE_STATUS('ECOMMERCE.RAW.ORDERS_PIPE')):executionState::VARCHAR
    AS execution_state
;
-- Expected: RUNNING

-- Other useful fields from SYSTEM$PIPE_STATUS:
--   pendingFileCount — files waiting to be loaded
--   executionState  — RUNNING, PAUSED, or STOPPED_CLONED

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Snowpipe vs COPY INTO — when to use each
-- ══════════════════════════════════════════════════════════════
--
-- USE COPY INTO when:
--   · Loading historical data in bulk (millions of rows)
--   · Running scheduled nightly or hourly batch loads
--   · You need exact control over when data is loaded
--   · Loading large files where warehouse parallelism helps
--   · Cost predictability is important (warehouse credits)
--
-- USE SNOWPIPE when:
--   · Data arrives continuously and latency matters
--   · Files arrive unpredictably throughout the day
--   · You want zero-maintenance ingestion after setup
--   · Small files arrive frequently (sensors, events, logs)
--   · You are building near-real-time pipelines
--
-- COST COMPARISON (approximate):
--   COPY INTO:  warehouse credits (e.g. $2-4/credit)
--               billed while warehouse runs
--   Snowpipe:   serverless credits (~$0.06/1000 files + compute)
--               billed only when actively loading
--   For large batch loads: COPY INTO is usually cheaper.
--   For continuous small file loads: Snowpipe is usually cheaper.

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- Drop the pipe and demo table created in this sub-task.
-- The ORDERS table from Sub-task 2.3 is not affected.

DROP PIPE  IF EXISTS ECOMMERCE.RAW.ORDERS_PIPE;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_PIPE;
REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE PATTERN='.*new_orders.*';

-- Verify
SHOW PIPES IN SCHEMA ECOMMERCE.RAW;
-- Should return zero rows

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a pipe called CUSTOMERS_PIPE that targets a new
--    table CUSTOMERS_PIPE in ECOMMERCE.RAW.
--    Use a PATTERN that only matches files named 'new_customers*.csv'.
--    Verify the pipe definition with SHOW PIPES.
--
-- 2. Use SYSTEM$PIPE_STATUS to check the pipe status.
--    What is the executionState?
--    What is the notificationChannelName?
--    (This channel name is what you would configure in S3/Azure
--    for AUTO_INGEST = TRUE event notifications.)
--
-- 3. Pause your CUSTOMERS_PIPE, verify it is paused,
--    then resume it. What commands did you use?
--    When would pausing a pipe be useful in production?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if a file fails to load through Snowpipe?
-- A: Check PIPE_USAGE_HISTORY for STATUS = LOAD_FAILED.
--    Failed files do not block subsequent files — Snowpipe
--    continues loading other files. Fix the source data,
--    re-stage the file, and use the REST API insertFiles
--    endpoint to trigger a reload. FORCE is not needed —
--    Snowpipe retries failed files automatically for 14 days.
--
-- Q: What if Snowpipe falls behind — too many files arriving?
-- A: Check pendingFileCount in SYSTEM$PIPE_STATUS.
--    Snowpipe scales its serverless compute automatically
--    but very high file volumes can cause temporary backlogs.
--    Consider batching small files into larger ones before
--    staging, or splitting the load across multiple pipes.
--
-- Q: What if I need to reload files that Snowpipe already loaded?
-- A: Use the REST API insertFiles endpoint with the file names.
--    Snowpipe has its own load deduplication — files already
--    loaded within the last 14 days are skipped by default.
--    For intentional reloads, recreate the pipe (DROP + CREATE)
--    which resets the load history, then trigger via REST API.
--
-- Q: What is the latency of Snowpipe?
-- A: Typically 30 seconds to a few minutes from file arrival
--    to data available in the table. This is "near-real-time"
--    not true real-time streaming. For sub-second latency
--    consider Snowflake's Streaming API (Snowflake Ingest SDK)
--    which bypasses staging entirely — covered in the
--    Databricks workbook.
--
-- Q: What is the Oracle equivalent of Snowpipe?
-- A: There is no direct equivalent in standard Oracle.
--    Oracle GoldenGate provides continuous replication but
--    is a separate licensed product requiring significant setup.
--    Snowpipe is simpler to configure, fully managed, and
--    natively integrated with Snowflake's security model.