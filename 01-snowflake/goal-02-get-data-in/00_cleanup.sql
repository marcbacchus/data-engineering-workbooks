-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 2 : Get Data In
-- Cleanup Script : Reset Goal 2 work
-- ──────────────────────────────────────────────────────────────
-- Run in: Snowsight
-- Use   : Reset and re-run Goal 2 from scratch
--         Safe to run multiple times
-- ══════════════════════════════════════════════════════════════
--
-- WHAT THIS DOES
--   Removes all objects created in Goal 2 sub-tasks 2.1 — 2.3:
--   · File format objects (CSV_FORMAT, JSON_FORMAT, PARQUET_FORMAT)
--   · All tables in ECOMMERCE.RAW
--   · All files in ECOMMERCE_RAW_STAGE
--
--   Does NOT drop:
--   · The ECOMMERCE database or its schemas
--   · WORKBOOK_WH warehouse
--   · The named stage itself (ECOMMERCE_RAW_STAGE)
--     — you will re-upload files to it after cleanup
--
-- NOTE: Time Travel (Goal 8) can recover dropped tables
--   within your retention window. UNDROP TABLE tablename;
--
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ── Step 1: Drop all RAW tables ───────────────────────────────
DROP TABLE IF EXISTS ECOMMERCE.RAW.SUPPLIERS;
DROP TABLE IF EXISTS ECOMMERCE.RAW.PRODUCTS;
DROP TABLE IF EXISTS ECOMMERCE.RAW.CUSTOMERS;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDER_ITEMS;
DROP TABLE IF EXISTS ECOMMERCE.RAW.PRODUCT_REVIEWS;
DROP TABLE IF EXISTS ECOMMERCE.RAW.RETURNS;
DROP TABLE IF EXISTS ECOMMERCE.RAW.CLICKSTREAM_EVENTS;
DROP TABLE IF EXISTS ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON;
DROP TABLE IF EXISTS ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET;

-- ── Step 2: Drop file format objects ─────────────────────────
DROP FILE FORMAT IF EXISTS ECOMMERCE.RAW.CSV_FORMAT;
DROP FILE FORMAT IF EXISTS ECOMMERCE.RAW.JSON_FORMAT;
DROP FILE FORMAT IF EXISTS ECOMMERCE.RAW.PARQUET_FORMAT;

-- ── Step 3: Remove all files from the stage ──────────────────
REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

-- ── Step 4: Verify everything is clean ───────────────────────

-- Check tables
SELECT TABLE_NAME, ROW_COUNT
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_TYPE   = 'BASE TABLE'
ORDER BY TABLE_NAME
;
-- Should return zero rows

-- Check file formats
SHOW FILE FORMATS IN SCHEMA ECOMMERCE.RAW;
-- Should return zero rows

-- Check stage is empty
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;
-- Should return zero rows

-- ══════════════════════════════════════════════════════════════
-- CLEANUP COMPLETE
-- You are ready to re-run Goal 2 from sub-task 2.1
-- ══════════════════════════════════════════════════════════════
