-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 2 : Get Data In
-- Sub-task 2.5 : Semi-structured data (JSON and Parquet)
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~40 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight (all steps)
-- Prerequisites    : 03_copy_into.sql completed
--                    product_reviews.json staged
--                    product_reviews.parquet staged
-- COF-C03 domain   : Domain 4 — Data Loading & Unloading (15%)
--                    Domain 5 — Data Transformations (17%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Not all data arrives as tidy rows and columns. APIs return
--   JSON. Data lakes store Parquet. Event streams produce nested
--   objects with arrays inside objects inside arrays.
--
--   Snowflake handles all of this through the VARIANT data type —
--   a flexible column that stores any semi-structured data without
--   a fixed schema. You load it first, query it second, and only
--   enforce structure when you need to.
--
--   This sub-task covers:
--   PART A — Understanding VARIANT and querying JSON
--   PART B — Loading product_reviews.json into Snowflake
--   PART C — Loading product_reviews.parquet into Snowflake
--   PART D — Comparing all three formats side by side
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE VARIANT DATA TYPE
-- ══════════════════════════════════════════════════════════════
--
-- VARIANT is Snowflake's universal semi-structured type.
-- It can store JSON, Avro, Parquet, ORC, or XML data
-- in a single column — up to 16MB per value.
--
-- KEY QUERYING TECHNIQUES:
--
-- Dot notation — access nested fields:
--   col:field          → top-level field
--   col:field.nested   → nested field
--   col:field::type    → cast to a SQL type
--
-- Bracket notation — access array elements:
--   col:array[0]       → first element of an array
--   col:array[1]::type → second element, cast to type
--
-- FLATTEN — expand arrays into rows:
--   LATERAL FLATTEN(INPUT => col:array)
--   Turns one row with an array into multiple rows —
--   one row per array element.
--
-- PARSE_JSON — convert a string to VARIANT:
--   PARSE_JSON('{"key": "value"}')
--   Useful when JSON arrives as VARCHAR and needs querying.
--
-- Oracle equivalent:
--   Oracle 12c+ has JSON_VALUE, JSON_QUERY, and JSON_TABLE.
--   Snowflake's dot-notation is simpler and more readable.
--   FLATTEN has no direct Oracle equivalent — JSON_TABLE
--   is the closest but requires more verbose syntax.
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Confirm both supplement files are staged
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE
    PATTERN = '.*(json|parquet).*'
;
-- Should show:
-- ecommerce_raw_stage/product_reviews.json
-- ecommerce_raw_stage/product_reviews.parquet

-- ══════════════════════════════════════════════════════════════
-- PART A: UNDERSTANDING VARIANT AND QUERYING JSON
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Explore VARIANT using Snowflake sample data
-- ══════════════════════════════════════════════════════════════
-- Before loading our own JSON, let's explore VARIANT querying
-- using Snowflake's built-in weather dataset which already
-- has a VARIANT column — no loading required.

-- Check what semi-structured sample data is available
SHOW SCHEMAS IN DATABASE SNOWFLAKE_SAMPLE_DATA;

-- The WEATHER schema has real semi-structured data
SELECT *
FROM SNOWFLAKE_SAMPLE_DATA.WEATHER.DAILY_14_TOTAL
LIMIT 3
;
-- You will see a V column of type VARIANT containing
-- nested weather observation data as JSON objects.

-- ── Dot notation — access a top-level field ───────────────────
SELECT
    V:city::VARCHAR                 AS city_name,
    V:country::VARCHAR              AS country,
    V:time::TIMESTAMP_NTZ           AS observation_time
FROM SNOWFLAKE_SAMPLE_DATA.WEATHER.DAILY_14_TOTAL
LIMIT 10
;

-- ── Nested field access ───────────────────────────────────────
SELECT
    V:city.name::VARCHAR            AS city_name,
    V:city.country::VARCHAR         AS country,
    V:city.coord.lat::FLOAT         AS latitude,
    V:city.coord.lon::FLOAT         AS longitude
FROM SNOWFLAKE_SAMPLE_DATA.WEATHER.DAILY_14_TOTAL
LIMIT 10
;

-- ── Access array elements ─────────────────────────────────────
-- The data field contains an array of daily observations
SELECT
    V:city.name::VARCHAR            AS city_name,
    V:data[0]:temp.day::FLOAT       AS day0_temp,
    V:data[1]:temp.day::FLOAT       AS day1_temp,
    V:data[2]:temp.day::FLOAT       AS day2_temp
FROM SNOWFLAKE_SAMPLE_DATA.WEATHER.DAILY_14_TOTAL
LIMIT 5
;

-- ── FLATTEN — expand array into rows ──────────────────────────
-- Each city has multiple days of data in an array.
-- FLATTEN turns that array into one row per day.
SELECT
    V:city.name::VARCHAR            AS city_name,
    f.value:dt::TIMESTAMP_NTZ       AS forecast_date,
    f.value:temp.day::FLOAT         AS temp_day,
    f.value:temp.min::FLOAT         AS temp_min,
    f.value:temp.max::FLOAT         AS temp_max,
    f.value:weather[0].main::VARCHAR AS weather_condition
FROM SNOWFLAKE_SAMPLE_DATA.WEATHER.DAILY_14_TOTAL,
    LATERAL FLATTEN(INPUT => V:data) f
LIMIT 20
;
-- LATERAL FLATTEN creates one row per array element.
-- f.value gives you the content of each element.
-- This is the core technique for querying JSON arrays.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: PARSE_JSON — build VARIANT from a string
-- ══════════════════════════════════════════════════════════════
-- PARSE_JSON converts a JSON string into a queryable VARIANT.
-- Useful when JSON arrives as VARCHAR from a source system.

SELECT
    PARSE_JSON('{"review_id": 1, "rating": 5, "text": "Excellent!"}')
                                    AS parsed_json,
    PARSE_JSON('{"review_id": 1, "rating": 5, "text": "Excellent!"}'):rating::INTEGER
                                    AS rating,
    PARSE_JSON('{"review_id": 1, "rating": 5, "text": "Excellent!"}'):text::VARCHAR
                                    AS review_text
;

-- PARSE_JSON with an array
SELECT
    f.value::VARCHAR                AS tag
FROM TABLE(FLATTEN(INPUT => PARSE_JSON('["electronics", "review", "rating_5"]'))) f
;
-- Returns 3 rows — one per array element.

-- ══════════════════════════════════════════════════════════════
-- PART B: LOAD AND QUERY THE JSON FILE
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Preview the JSON file from the stage
-- ══════════════════════════════════════════════════════════════
-- Each row in the stage returns one complete JSON object
-- as a VARIANT in $1.

SELECT $1
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.json
    (FILE_FORMAT => 'ECOMMERCE.RAW.JSON_FORMAT')
LIMIT 3
;
-- Each row shows one review as a complete JSON object.
-- You can see the nested product object and metadata.tags array.
-- This confirms JSON_FORMAT is parsing correctly before loading.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Create the JSON target table and load
-- ══════════════════════════════════════════════════════════════
-- JSON loads into a single VARIANT column.
-- The entire JSON object for each record goes into one cell.
-- We then query the nested fields using dot notation.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON (
    review_data     VARIANT
)
COMMENT = 'Product reviews in raw JSON format — 10,000 records'
;

COPY INTO ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.json
    FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.JSON_FORMAT')
    ON_ERROR    = ABORT_STATEMENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON;
-- Expected: 10,000

-- Preview the raw VARIANT data
SELECT review_data
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON
LIMIT 3
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Query the JSON data using dot notation
-- ══════════════════════════════════════════════════════════════
-- Extract flat fields from the top level of each JSON object.

SELECT
    review_data:review_id::INTEGER      AS review_id,
    review_data:customer_id::INTEGER    AS customer_id,
    review_data:rating::INTEGER         AS rating,
    review_data:review_text::VARCHAR    AS review_text,
    review_data:is_verified::BOOLEAN    AS is_verified,
    review_data:created_at::TIMESTAMP_NTZ AS created_at
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON
LIMIT 10
;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Query nested objects using dot notation
-- ══════════════════════════════════════════════════════════════
-- The product field is a nested JSON object.
-- Access it with dot notation chaining.

SELECT
    review_data:review_id::INTEGER              AS review_id,
    review_data:rating::INTEGER                 AS rating,
    review_data:product.product_name::VARCHAR   AS product_name,
    review_data:product.category::VARCHAR       AS category,
    review_data:product.subcategory::VARCHAR    AS subcategory
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON
LIMIT 10
;

-- Aggregate using nested fields — no JOIN needed
-- Category average rating directly from JSON
SELECT
    review_data:product.category::VARCHAR       AS category,
    COUNT(*)                                    AS review_count,
    ROUND(AVG(review_data:rating::INTEGER), 2)  AS avg_rating
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON
GROUP BY review_data:product.category::VARCHAR
ORDER BY avg_rating DESC
;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Flatten the tags array using LATERAL FLATTEN
-- ══════════════════════════════════════════════════════════════
-- The metadata.tags field is an array of strings.
-- FLATTEN expands it — one row per tag per review.

SELECT
    review_data:review_id::INTEGER          AS review_id,
    review_data:rating::INTEGER             AS rating,
    review_data:product.category::VARCHAR   AS category,
    f.value::VARCHAR                        AS tag
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON,
    LATERAL FLATTEN(INPUT => review_data:metadata.tags) f
LIMIT 20
;
-- 10,000 reviews × ~3 tags each = ~30,000 rows after flatten.
-- Each review appears once per tag.

-- Count reviews per tag
SELECT
    f.value::VARCHAR                        AS tag,
    COUNT(*)                                AS review_count,
    ROUND(AVG(review_data:rating::INTEGER), 2) AS avg_rating
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON,
    LATERAL FLATTEN(INPUT => review_data:metadata.tags) f
GROUP BY f.value::VARCHAR
ORDER BY review_count DESC
LIMIT 15
;

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Join JSON data with structured tables
-- ══════════════════════════════════════════════════════════════
-- Semi-structured data does not exist in isolation.
-- Join JSON reviews with the structured CUSTOMERS table.

SELECT
    c.first_name || ' ' || c.last_name  AS customer_name,
    c.country,
    r.review_data:rating::INTEGER        AS rating,
    r.review_data:review_text::VARCHAR   AS review_text,
    r.review_data:product.category::VARCHAR AS category
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON r
JOIN ECOMMERCE.RAW.CUSTOMERS c
    ON r.review_data:customer_id::INTEGER = c.customer_id
WHERE r.review_data:rating::INTEGER = 1
LIMIT 10
;
-- Joining VARIANT fields to structured tables is seamless.
-- Cast the VARIANT field to the correct type for the JOIN.

-- ══════════════════════════════════════════════════════════════
-- PART C: LOAD AND QUERY THE PARQUET FILE
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- STEP 9: Preview the Parquet file from the stage
-- ══════════════════════════════════════════════════════════════
-- Parquet files return as a single VARIANT per row
-- containing all columns as key-value pairs.

SELECT $1
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.parquet
    (FILE_FORMAT => 'ECOMMERCE.RAW.PARQUET_FORMAT')
LIMIT 3
;
-- Each row shows all columns as a VARIANT object.
-- Column names and types from the Parquet schema are preserved.
-- Compare to JSON preview — both return VARIANT but:
--   JSON:    types are inferred from values
--   Parquet: types are strongly typed from embedded schema

-- ══════════════════════════════════════════════════════════════
-- STEP 10: Load Parquet using MATCH_BY_COLUMN_NAME
-- ══════════════════════════════════════════════════════════════
-- Parquet files have an embedded schema with column names.
-- MATCH_BY_COLUMN_NAME maps Parquet columns to table columns
-- by name rather than by position — safer and more readable.
-- This is the recommended approach for Parquet loading.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET (
    review_id       INTEGER,
    product_id      INTEGER,
    customer_id     INTEGER,
    order_id        INTEGER,
    rating          INTEGER,
    review_text     VARCHAR(2000),
    is_verified     BOOLEAN,
    helpful_votes   INTEGER,
    created_at      TIMESTAMP_NTZ,
    product_name    VARCHAR(500),
    category        VARCHAR(100),
    subcategory     VARCHAR(100)
)
COMMENT = 'Product reviews loaded from Parquet — 10,000 rows'
;

COPY INTO ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.parquet
    FILE_FORMAT         = (FORMAT_NAME = 'ECOMMERCE.RAW.PARQUET_FORMAT')
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    ON_ERROR            = ABORT_STATEMENT
;
-- MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE means:
-- Parquet column 'review_id' → table column 'REVIEW_ID'
-- No need to specify column order — names do the mapping.
-- This is robust against column reordering in the source file.

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET;
-- Expected: 10,000

-- Query the Parquet table — behaves like any structured table
SELECT
    review_id,
    product_name,
    category,
    rating,
    review_text,
    created_at
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET
LIMIT 10
;
-- No dot notation needed — Parquet loaded into typed columns.
-- This is the key difference from JSON loading:
--   JSON   → VARIANT column, dot-notation to query
--   Parquet → typed columns, standard SQL to query

-- ══════════════════════════════════════════════════════════════
-- PART D: COMPARE ALL THREE FORMATS
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- STEP 11: Same data — three formats compared
-- ══════════════════════════════════════════════════════════════
-- All three tables contain product review data.
-- Compare how you query each format.

-- Average rating by category — CSV version (structured)
SELECT
    p.category,
    COUNT(*)                        AS review_count,
    ROUND(AVG(r.rating), 2)         AS avg_rating
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS r
JOIN ECOMMERCE.RAW.PRODUCTS p
    ON r.product_id = p.product_id
GROUP BY p.category
ORDER BY avg_rating DESC
;

-- Average rating by category — JSON version (VARIANT)
SELECT
    review_data:product.category::VARCHAR   AS category,
    COUNT(*)                                AS review_count,
    ROUND(AVG(review_data:rating::INTEGER), 2) AS avg_rating
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON
GROUP BY review_data:product.category::VARCHAR
ORDER BY avg_rating DESC
;

-- Average rating by category — Parquet version (typed columns)
SELECT
    category,
    COUNT(*)                        AS review_count,
    ROUND(AVG(rating), 2)           AS avg_rating
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET
GROUP BY category
ORDER BY avg_rating DESC
;

-- ── Format comparison summary ─────────────────────────────────
-- ┌────────────┬──────────────┬───────────────┬──────────────┐
-- │ Format     │ File size    │ Load method   │ Query style  │
-- ├────────────┼──────────────┼───────────────┼──────────────┤
-- │ CSV        │ 54 MB        │ COPY INTO     │ Standard SQL │
-- │ JSON       │ 5.9 MB       │ COPY INTO     │ Dot notation │
-- │ Parquet    │ 0.4 MB       │ COPY INTO +   │ Standard SQL │
-- │            │              │ MATCH_BY_COL  │              │
-- └────────────┴──────────────┴───────────────┴──────────────┘
--
-- WHEN TO USE EACH:
--   CSV     — simple tabular data from databases, exports, ETL
--   JSON    — API responses, event streams, nested/flexible data
--   Parquet — data lake files, Spark/Databricks output,
--             large datasets where compression matters

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- The JSON and Parquet tables are kept — they are used in
-- Goal 3 (Query and Transform) for Cortex AI exercises.
-- The supplement files stay in the stage for the same reason.
--
-- To drop them if resetting:
-- DROP TABLE IF EXISTS ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON;
-- DROP TABLE IF EXISTS ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET;
-- REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.json;
-- REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.parquet;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Using PRODUCT_REVIEWS_JSON, find the top 3 most helpful
--    reviews (highest helpful_votes) for each star rating.
--    Include: rating, review_text, helpful_votes, product_name.
--    Use dot notation to extract all fields from VARIANT.
--
-- 2. Using LATERAL FLATTEN on the metadata.tags array,
--    find which tag has the highest average rating.
--    Which category of product tends to get the best reviews?
--
-- 3. Join PRODUCT_REVIEWS_PARQUET with PRODUCTS (from the
--    CSV load) using product_id. Compare the product_name
--    in the Parquet table vs the PRODUCTS table.
--    Are they identical? Why or why not?
--
-- 4. Write a single query that UNION ALLs results from all
--    three review tables (CSV, JSON, Parquet) and returns
--    a total review count and average rating per source.
--    Which source has the most reviews?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if my JSON is newline-delimited (NDJSON / JSON Lines)
--    rather than a JSON array?
-- A: Set STRIP_OUTER_ARRAY = FALSE in JSON_FORMAT.
--    NDJSON has one JSON object per line — no outer [] wrapper.
--    Common in event streaming systems like Kafka and Kinesis.
--
-- Q: What if a VARIANT field is sometimes a string and
--    sometimes a number depending on the record?
-- A: This is the nature of semi-structured data. Use TRY_CAST
--    instead of :: to avoid errors:
--    TRY_CAST(col:field AS INTEGER)
--    Returns NULL instead of erroring on type mismatches.
--
-- Q: What if my Parquet file has columns the table does not?
-- A: With MATCH_BY_COLUMN_NAME extra Parquet columns are
--    silently ignored — only columns that match table column
--    names are loaded. This makes Parquet loading robust
--    against schema evolution in the source system.
--
-- Q: What if I want to query JSON without loading it?
-- A: Use the stage SELECT with $1 and dot notation:
--    SELECT $1:field::VARCHAR
--    FROM @stage/file.json (FILE_FORMAT => 'JSON_FORMAT')
--    This reads directly from the stage — no COPY INTO needed.
--    Useful for exploration before committing to a schema.
--
-- Q: What is the performance difference between querying
--    JSON in a VARIANT column vs a structured table?
-- A: Structured tables (like PRODUCT_REVIEWS_PARQUET) are
--    generally faster for analytical queries because Snowflake
--    can use column-level statistics and pruning. VARIANT
--    columns require parsing on every query. For frequently
--    queried JSON data, consider flattening into a structured
--    table using a CTAS (CREATE TABLE AS SELECT) pattern.
--    Covered in Goal 3.
