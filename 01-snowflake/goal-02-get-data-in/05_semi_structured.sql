-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
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
-- COF-C03 domain   : Domain 3.0 — Data Loading, Unloading, and Connectivity (18%)
--                    Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
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
-- STEP 1: Build a VARIANT demo table inline
-- ══════════════════════════════════════════════════════════════
-- Before loading our own JSON, we explore VARIANT querying
-- using a small self-contained demo table built with PARSE_JSON.
-- This is self-contained — no external schemas required.
-- The structure mirrors real-world nested JSON: a city object
-- with nested coordinates and an array of daily weather data.

CREATE OR REPLACE TEMPORARY TABLE VARIANT_DEMO AS
SELECT PARSE_JSON(column1) AS v
FROM VALUES
('{
    "city": {
        "name": "New York",
        "country": "US",
        "coord": {"lat": 40.71, "lon": -74.01}
    },
    "data": [
        {"temp": {"day": 22.5, "min": 18.0, "max": 26.0},
         "weather": [{"main": "Clear"}]},
        {"temp": {"day": 19.0, "min": 15.5, "max": 23.0},
         "weather": [{"main": "Clouds"}]},
        {"temp": {"day": 17.0, "min": 13.0, "max": 21.0},
         "weather": [{"main": "Rain"}]}
    ]
}'),
('{
    "city": {
        "name": "London",
        "country": "UK",
        "coord": {"lat": 51.51, "lon": -0.13}
    },
    "data": [
        {"temp": {"day": 15.0, "min": 11.0, "max": 18.0},
         "weather": [{"main": "Rain"}]},
        {"temp": {"day": 14.0, "min": 10.0, "max": 17.0},
         "weather": [{"main": "Clouds"}]},
        {"temp": {"day": 16.0, "min": 12.0, "max": 19.0},
         "weather": [{"main": "Clear"}]}
    ]
}'),
('{
    "city": {
        "name": "Tokyo",
        "country": "JP",
        "coord": {"lat": 35.69, "lon": 139.69}
    },
    "data": [
        {"temp": {"day": 28.0, "min": 24.0, "max": 32.0},
         "weather": [{"main": "Clear"}]},
        {"temp": {"day": 30.0, "min": 25.0, "max": 34.0},
         "weather": [{"main": "Clear"}]},
        {"temp": {"day": 26.0, "min": 22.0, "max": 29.0},
         "weather": [{"main": "Clouds"}]}
    ]
}')
t
;

-- Preview the raw VARIANT data
SELECT v FROM VARIANT_DEMO;
-- Each row shows a complete JSON object.
-- This is exactly how our product_reviews.json will look
-- after loading into a VARIANT column.

-- ── First: query WITHOUT casting — see what VARIANT returns ───
-- This shows why type casting is always needed with VARIANT.
SELECT
    v:city.name             AS city_name,        -- returns VARIANT
    v:city.country          AS country,           -- returns VARIANT
    v:city.coord            AS lat_lon_json,      -- returns VARIANT object
    v:city.coord.lat        AS latitude,          -- returns VARIANT
    v:city.coord.lon        AS longitude          -- returns VARIANT
FROM VARIANT_DEMO
;
-- Every column returns as VARIANT (shown in quotes in results).
-- "New York" not New York — values are JSON-encoded strings.
-- You cannot do arithmetic on VARIANT — try adding 1 to latitude.
-- This is why ::type casting is required for real use.

-- ── Now with casting — proper SQL types ───────────────────────
SELECT
    v:city.name::VARCHAR            AS city_name,
    v:city.country::VARCHAR         AS country,
    v:city.coord                    AS lat_lon_json,   -- keep as VARIANT to see structure
    v:city.coord.lat::FLOAT         AS latitude,
    v:city.coord.lon::FLOAT         AS longitude
FROM VARIANT_DEMO
;
-- Now values are proper SQL types:
-- city_name = New York (VARCHAR, no quotes)
-- latitude  = 40.71    (FLOAT, usable in arithmetic)
-- lat_lon_json shows the nested object as VARIANT — useful
-- to see the full structure before drilling into sub-fields

-- Note the chaining: v:city.coord.lat
-- v        → the VARIANT column
-- :city    → access the city object
-- .coord   → access the coord nested object
-- .lat     → access the lat field
-- ::FLOAT  → cast to FLOAT for arithmetic

-- ── Access array elements by index ───────────────────────────
-- Square bracket notation accesses array elements by position
-- [0] = first element, [1] = second, etc.
SELECT
    v:city.name::VARCHAR            AS city_name,
    v:data[0].temp.day::FLOAT       AS day1_temp,
    v:data[1].temp.day::FLOAT       AS day2_temp,
    v:data[2].temp.day::FLOAT       AS day3_temp,
    v:data[0].weather[0].main::VARCHAR AS day1_condition
FROM VARIANT_DEMO
;
-- Without casting (::type) values are returned as VARIANT.
-- Always cast to the expected SQL type for calculations.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: FLATTEN — expand arrays into rows
-- ══════════════════════════════════════════════════════════════
-- LATERAL FLATTEN is the most important semi-structured function
-- in Snowflake. It turns one row with an array into multiple
-- rows — one row per array element.
-- Use it whenever you need to aggregate or filter on array data.

-- ── First: query the array WITHOUT FLATTEN ────────────────────
-- This shows the problem FLATTEN solves.
-- Each city has 3 days of weather data in an array.
-- Without FLATTEN you can only access one element at a time.

SELECT
    v:city.name::VARCHAR            AS city_name,
    v:data                          AS all_days_as_variant,  -- entire array as one value
    v:data[0].temp.day::FLOAT       AS day1_temp,            -- must hardcode index
    v:data[1].temp.day::FLOAT       AS day2_temp,            -- and again
    v:data[2].temp.day::FLOAT       AS day3_temp             -- and again
FROM VARIANT_DEMO
WHERE v:city.name::VARCHAR = 'New York'   -- one row for clarity
;
-- Problems with this approach:
--   · You must hardcode every array index
--   · If the array has 14 elements you need 14 columns
--   · You cannot GROUP BY, filter, or aggregate across array elements
--   · all_days_as_variant shows the entire array as one opaque value

-- ── Now: use FLATTEN on that same one row ─────────────────────
-- FLATTEN turns the array into one row per element.
-- Three days of data become three rows.

SELECT
    v:city.name::VARCHAR            AS city_name,
    f.index                         AS day_number,
    f.value:temp.day::FLOAT         AS temp_day,
    f.value:temp.min::FLOAT         AS temp_min,
    f.value:temp.max::FLOAT         AS temp_max,
    f.value:weather[0].main::VARCHAR AS weather_condition
FROM VARIANT_DEMO,
    LATERAL FLATTEN(INPUT => v:data) f
WHERE v:city.name::VARCHAR = 'New York'
;
-- 3 rows returned — one per array element.
-- f.value  → content of each element
-- f.index  → position in the array (0-based)
-- Now you can filter, aggregate, and JOIN on array data.

-- ── Now apply FLATTEN to ALL cities ───────────────────────────
-- Remove the WHERE clause — 3 cities × 3 days = 9 rows.
SELECT
    v:city.name::VARCHAR            AS city_name,
    f.index                         AS day_number,
    f.value:temp.day::FLOAT         AS temp_day,
    f.value:weather[0].main::VARCHAR AS weather_condition
FROM VARIANT_DEMO,
    LATERAL FLATTEN(INPUT => v:data) f
ORDER BY city_name, day_number
;

-- Find the hottest day across all cities — only possible with FLATTEN
SELECT
    v:city.name::VARCHAR            AS city_name,
    MAX(f.value:temp.max::FLOAT)    AS max_temp_recorded
FROM VARIANT_DEMO,
    LATERAL FLATTEN(INPUT => v:data) f
GROUP BY v:city.name::VARCHAR
ORDER BY max_temp_recorded DESC
;

-- ── PARSE_JSON — convert a string to VARIANT ─────────────────
-- Useful when JSON arrives as VARCHAR from a source system.
SELECT
    PARSE_JSON('{"review_id": 1, "rating": 5, "text": "Excellent!"}')
                                    AS parsed_json,
    PARSE_JSON('{"review_id": 1, "rating": 5, "text": "Excellent!"}'):rating::INTEGER
                                    AS rating,
    PARSE_JSON('{"review_id": 1, "rating": 5, "text": "Excellent!"}'):text::VARCHAR
                                    AS review_text
;

-- PARSE_JSON with an array — FLATTEN into rows
SELECT
    f.value::VARCHAR                AS tag
FROM TABLE(FLATTEN(INPUT => PARSE_JSON('["electronics", "review", "rating_5"]'))) f
;
-- Returns 3 rows — one per array element.
-- This is the same technique used on metadata.tags in our JSON file.

-- ══════════════════════════════════════════════════════════════
-- PART B: LOAD AND QUERY THE JSON FILE
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Preview the JSON file from the stage
-- ══════════════════════════════════════════════════════════════
-- ── First: SELECT * to see the raw stage output ───────────────
SELECT *
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.json
    (FILE_FORMAT => 'ECOMMERCE.RAW.JSON_FORMAT')
LIMIT 3
;
-- Returns one column called $1 containing the entire JSON object.
-- This shows that JSON files load as a single VARIANT column —
-- there are no separate columns like a CSV would have.
-- The entire JSON object lands in $1 as one value.

-- ── Then: SELECT $1 explicitly ────────────────────────────────
-- $1 is the positional reference to the first (and only) column.
-- For JSON files $1 and * return the same result —
-- but $1 makes it explicit that you are working with
-- a single VARIANT value, not a table with multiple columns.
SELECT $1
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.json
    (FILE_FORMAT => 'ECOMMERCE.RAW.JSON_FORMAT')
LIMIT 3
;
-- Each row is one complete JSON review object.
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
    review_data:created_at::TIMESTAMP_NTZ AS created_at,
    review_data:product                 AS product_json   -- raw VARIANT — no cast
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON
LIMIT 10
;
-- product_json shows the entire nested product object as VARIANT.
-- Compare to the individual fields extracted in Step 6 using
-- dot notation — same data, different access pattern.
-- Seeing the raw VARIANT helps you understand what dot notation
-- is drilling into.

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

-- ── Without FLATTEN — the problem ────────────────────────────
-- The tags field is an array. Without FLATTEN you can only
-- access one tag at a time by index.
SELECT
    review_data:review_id::INTEGER          AS review_id,
    review_data:metadata.tags               AS all_tags_as_variant,
    review_data:metadata.tags[0]::VARCHAR   AS first_tag_only
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_JSON
LIMIT 1
;
-- all_tags_as_variant shows the entire array as one opaque value.
-- You cannot filter, count, or aggregate across tags this way.

-- ── With FLATTEN — one row per tag ───────────────────────────
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

SELECT $1 -- instead of select * 
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
-- STEP 10: Load Parquet — encounter, diagnose, and fix a
--          real-world timestamp issue
--          Run in: Snowsight
-- ══════════════════════════════════════════════════════════════
-- This step deliberately shows a common Parquet loading problem
-- and walks through the diagnosis and fix.
-- This is the pattern you will use in production.

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

-- ── ATTEMPT 1: Load with MATCH_BY_COLUMN_NAME ─────────────────
-- The natural first attempt — let Snowflake match columns by name.
COPY INTO ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.parquet
    FILE_FORMAT          = (FORMAT_NAME = 'ECOMMERCE.RAW.PARQUET_FORMAT')
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    ON_ERROR             = ABORT_STATEMENT
;

-- Check the result
SELECT
    review_id,
    product_name,
    rating,
    created_at              -- this column will show Invalid date
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET
LIMIT 5
;
-- created_at = Invalid date
-- The load succeeded but timestamps are wrong.
-- This is a silent data quality issue — no error was thrown.
-- Always verify your data after loading, not just the row count.

-- ── DIAGNOSE: What is in the raw Parquet file? ────────────────
-- Query the stage directly to see the raw value.
SELECT
    $1:created_at                           AS raw_value,
    $1:review_id::INTEGER                   AS review_id
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.parquet
    (FILE_FORMAT => 'ECOMMERCE.RAW.PARQUET_FORMAT')
LIMIT 5
;
-- raw_value = 1617398772000000
-- This is a microseconds-since-epoch integer —
-- a common Parquet timestamp encoding from pandas/PyArrow.
-- Snowflake loaded it as-is into TIMESTAMP_NTZ which
-- cannot interpret epoch integers without help.

-- ── UNDERSTAND: Convert microseconds to timestamp ─────────────
-- TO_TIMESTAMP(value, scale) converts epoch integers:
--   scale = 0 → seconds since epoch
--   scale = 3 → milliseconds since epoch
--   scale = 6 → microseconds since epoch  ← our case
--   scale = 9 → nanoseconds since epoch
--
-- Verify the conversion is correct before reloading:
SELECT
    $1:created_at                               AS raw_epoch,
    TO_TIMESTAMP($1:created_at::INTEGER, 6)     AS converted_timestamp
FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.parquet
    (FILE_FORMAT => 'ECOMMERCE.RAW.PARQUET_FORMAT')
LIMIT 5
;
-- raw_epoch          = 1617398772000000
-- converted_timestamp = 2021-04-02 21:26:12
-- Confirm this looks like a realistic review timestamp
-- before committing to reloading all 10,000 rows.

-- ── FIX: Truncate and reload with SELECT transformation ───────
-- TRUNCATE removes all rows but keeps the table structure.
-- Cleaner than DROP + CREATE when you just need to reload data.
TRUNCATE TABLE ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET;
-- Expected: 0 — table is empty, ready for clean reload

-- Reload with full column transformation
-- FORCE = TRUE bypasses load deduplication since the file
-- was already loaded in Attempt 1
COPY INTO ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET
FROM (
    SELECT
        $1:review_id::INTEGER,
        $1:product_id::INTEGER,
        $1:customer_id::INTEGER,
        $1:order_id::INTEGER,
        $1:rating::INTEGER,
        $1:review_text::VARCHAR,
        $1:is_verified::BOOLEAN,
        $1:helpful_votes::INTEGER,
        TO_TIMESTAMP($1:created_at::INTEGER, 6),    -- microseconds → TIMESTAMP_NTZ
        $1:product_name::VARCHAR,
        $1:category::VARCHAR,
        $1:subcategory::VARCHAR
    FROM @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/product_reviews.parquet
)
FILE_FORMAT = (FORMAT_NAME = 'ECOMMERCE.RAW.PARQUET_FORMAT')
FORCE       = TRUE
;
-- When using SELECT transformation in COPY INTO:
--   · MATCH_BY_COLUMN_NAME is NOT used
--   · Columns map positionally — order must match CREATE TABLE
--   · Every column must be explicitly listed — no * shortcut
--   · This gives you complete control over type casting

-- ── VERIFY: Confirm the fix ───────────────────────────────────
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET;
-- Expected: 10,000

SELECT
    review_id,
    product_name,
    rating,
    created_at
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_PARQUET
LIMIT 5
;
-- created_at should now show readable timestamps
-- e.g. 2021-04-02 21:26:12.000
-- Problem diagnosed, understood, and fixed.

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