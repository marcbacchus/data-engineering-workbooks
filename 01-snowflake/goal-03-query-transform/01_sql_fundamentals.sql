-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 3  : Query and Transform Data
-- Sub-task 3.1 : SQL fundamentals and query patterns
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Goal 2 complete
--                    All 10 tables loaded in ECOMMERCE.RAW
--                    10,370,254 rows available
-- COF-C03 domain   : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Goals 1 and 2 built the environment and loaded the data.
--   Goal 3 is where you actually use it.
--
--   This sub-task covers the SQL patterns practitioners use
--   every day on large datasets — not toy examples, but real
--   queries on 10 million rows where choices about filtering,
--   casting, and NULL handling have measurable performance impact.
--
--   We assume basic SQL familiarity (SELECT, FROM, WHERE,
--   GROUP BY). This sub-task covers the patterns that go beyond
--   the basics — the things that separate clean, maintainable
--   production SQL from the kind that breaks at 3am.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: SNOWFLAKE SQL DIALECT
-- ══════════════════════════════════════════════════════════════
--
-- Snowflake uses ANSI SQL with extensions. Key differences
-- from Oracle and SQL Server practitioners should know:
--
-- IDENTIFIER CASE:
--   Snowflake stores identifiers in UPPERCASE by default.
--   SELECT customer_id works. SELECT CUSTOMER_ID works.
--   SELECT "customer_id" (quoted) looks for lowercase — fails.
--   Avoid quoted identifiers unless the column was created quoted.
--
-- STRING LITERALS:
--   Single quotes only — 'value' not "value"
--   Double quotes are for identifiers, not strings.
--
-- DATE/TIMESTAMP LITERALS:
--   '2024-01-15'::DATE or TO_DATE('2024-01-15')
--   CURRENT_DATE(), CURRENT_TIMESTAMP() — with parentheses
--
-- NULL HANDLING:
--   NULL != NULL — always. Use IS NULL / IS NOT NULL.
--   NVL() is Oracle syntax — works in Snowflake too.
--   COALESCE() is the ANSI standard — prefer this.
--   ZEROIFNULL() is Snowflake-specific for numeric NULLs.
--
-- BOOLEAN:
--   TRUE / FALSE (not 1/0 or 'Y'/'N')
--   IS TRUE / IS FALSE / IS NULL checks
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Confirm data is loaded
SELECT
    TABLE_NAME,
    ROW_COUNT
FROM ECOMMERCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_TYPE   = 'BASE TABLE'
ORDER BY ROW_COUNT DESC
;
-- Should show 10 tables with 10,370,254 total rows

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Filtering patterns — WHERE clause best practices
-- ══════════════════════════════════════════════════════════════
-- Filters on large tables are your primary performance lever.
-- Snowflake uses micro-partition pruning — filters on columns
-- that align with how data is physically ordered eliminate
-- entire partitions from being scanned.

-- Basic filter — order_status is low cardinality, fast to filter
SELECT
    order_id,
    customer_id,
    order_status,
    order_total,
    created_at
FROM ECOMMERCE.RAW.ORDERS
WHERE order_status = 'delivered'
LIMIT 10
;

-- Date range filter — created_at is time-ordered
-- Snowflake prunes partitions efficiently on timestamp columns
SELECT
    COUNT(*)                        AS order_count,
    ROUND(SUM(order_total), 2)      AS total_revenue
FROM ECOMMERCE.RAW.ORDERS
WHERE created_at >= '2022-01-01' AND created_at <  '2023-01-01'
;
-- Note: use >= start AND < end+1 for date ranges
-- Avoids edge cases with time components in TIMESTAMP columns

-- Alternative: BETWEEN also works for date range filtering
-- Note: BETWEEN is inclusive on both ends — '2023-01-01' is included
-- The >= / < pattern excludes the end date which is more precise
-- for TIMESTAMP columns where '2023-01-01' = '2023-01-01 00:00:00'
-- and misses records from the rest of that day.
-- For DATE columns both approaches are equivalent.
-- For TIMESTAMP columns: prefer >= start AND < end for safety.
SELECT
    COUNT(*)                        AS order_count,
    ROUND(SUM(order_total), 2)      AS total_revenue
FROM ECOMMERCE.RAW.ORDERS
WHERE created_at BETWEEN '2022-01-01' AND '2022-12-31 23:59:59'
-- This makes the inclusive end explicit for TIMESTAMP columns.


-- Multiple conditions
SELECT
    order_id,
    order_status,
    payment_method,
    order_total
FROM ECOMMERCE.RAW.ORDERS
WHERE order_status   IN ('delivered', 'shipped')
  AND payment_method IN ('credit_card', 'paypal')
  AND order_total     > 100
ORDER BY order_total DESC
LIMIT 20
;

-- ── IN vs OR — why IN is safer ───────────────────────────────
-- These two are equivalent:
--   WHERE order_status IN ('delivered', 'shipped')
--   WHERE (order_status = 'delivered' OR order_status = 'shipped')
--
-- OR without parentheses is dangerous:
--   WHERE order_status = 'delivered'
--      OR order_status = 'shipped'
--     AND order_total > 100          ← AND binds tighter than OR
--
-- This is NOT the same as:
--   WHERE (order_status = 'delivered' OR order_status = 'shipped')
--     AND order_total > 100
--
-- Without parentheses, AND takes precedence over OR and the
-- query returns ALL delivered orders PLUS shipped orders
-- over $100 — not what was intended.
--
-- IN is always safer and cleaner for multiple value checks:
--   · No operator precedence traps
--   · Easier to read and maintain
--   · Easy to add or remove values
--   · Performs identically to OR in Snowflake
-- ─────────────────────────────────────────────────────────────

-- BETWEEN for numeric ranges — inclusive on both ends
SELECT
    product_id,
    product_name,
    category,
    unit_price
FROM ECOMMERCE.RAW.PRODUCTS
WHERE unit_price BETWEEN 50 AND 200
ORDER BY unit_price DESC
LIMIT 10
;

-- LIKE for pattern matching — use sparingly on large tables
-- Leading wildcards (%value) prevent partition pruning
SELECT
    product_id,
    product_name,
    category
FROM ECOMMERCE.RAW.PRODUCTS
WHERE product_name ILIKE '%elite%'    -- ILIKE = case-insensitive LIKE
LIMIT 10
;
-- LIKE  — case-sensitive pattern match (ANSI standard)
-- ILIKE — case-insensitive pattern match (Snowflake-specific)
--
-- 'Elite' LIKE '%elite%'  → FALSE (case mismatch)
-- 'Elite' ILIKE '%elite%' → TRUE  (case ignored)
--
-- Equivalent to: LOWER(product_name) LIKE '%elite%'
-- but ILIKE is cleaner and avoids the extra function call.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: NULL handling — the patterns that matter
-- ══════════════════════════════════════════════════════════════
-- NULLs are one of the most common sources of subtle bugs
-- in production SQL. Know how each function handles them.

-- ── NULL arithmetic — the silent data killer ──────────────────
-- Any arithmetic operation involving NULL returns NULL.
-- This causes silent wrong results in aggregations and calculations.

SELECT NULL + 5                         AS null_plus_5,       -- NULL
       NULL * 100                       AS null_times_100,    -- NULL
       NULL || ' suffix'                AS null_concat        -- NULL
;

-- The fix — replace NULL with a safe default before operating
SELECT COALESCE(NULL, 0) + 5           AS coalesce_plus_5,   -- 5
       COALESCE(NULL, 0) * 100         AS coalesce_times_100 -- 0
;

-- Why this matters on real data:
-- If helpful_votes has NULL values, SUM(helpful_votes) ignores them
-- but helpful_votes + 1 returns NULL for those rows.
-- Always use COALESCE when doing arithmetic on nullable columns.
-- ─────────────────────────────────────────────────────────────

-- Find NULLs in our dataset
-- The three COUNT variations compared:
SELECT
    COUNT(*)                            AS total_events,
    -- 3,000,000 — all rows including NULLs

    COUNT(customer_id)                  AS identified_events,
    -- 2,488,666 — non-NULL rows only

    COUNT(*) - COUNT(customer_id)       AS anonymous_events,
    -- 511,334 — NULL rows (anonymous sessions)

    COUNT(DISTINCT customer_id)         AS unique_customers
    -- how many DIFFERENT customers generated those 2.4M events
    -- one customer can have many events — this counts individuals
    -- 100,000 unique customers
FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS
;
-- COUNT(*)              → how many rows total
-- COUNT(column)         → how many rows have a value
-- COUNT(DISTINCT col)   → how many unique values exist
-- Three different questions — three different answers

-- IS NULL / IS NOT NULL
SELECT
    event_id,
    session_id,
    customer_id,
    event_type
FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS
WHERE customer_id IS NULL
LIMIT 5
;

-- COALESCE — return first non-NULL value (ANSI standard)
SELECT
    event_id,
    event_type,
    customer_id,
    COALESCE(customer_id, -1)           AS customer_id_safe,
    -- 
    -- COALESCE(customer_id, 'anonymous') AS customer_label_fail,
    -- This will fail because customer_id is a number and 'anonymous' is varchar
    -- MUST cast customer_id to varchar
    --
    COALESCE(customer_id::VARCHAR, 'anonymous') AS customer_label
FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS
LIMIT 10
;
-- COALESCE accepts multiple arguments — returns first non-NULL
-- COALESCE(a, b, c) = if a is NULL then b, if b is NULL then c

-- NVL — Oracle equivalent of COALESCE with two arguments
-- Works in Snowflake — use COALESCE for new code
SELECT
    event_id,
    NVL(customer_id, -1)                AS customer_id_nvl,
    COALESCE(customer_id, -1)           AS customer_id_coalesce
FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS
WHERE customer_id IS NULL
LIMIT 5
;
-- Both return the same result — COALESCE is preferred

-- NULLIF — return NULL if two values are equal
-- Useful for avoiding division by zero
SELECT
    product_id,
    unit_price,
    cost_price,
    unit_price - cost_price             AS margin,
    ROUND(
        (unit_price - cost_price)
        / NULLIF(unit_price, 0) * 100
    , 2)                                AS margin_pct
FROM ECOMMERCE.RAW.PRODUCTS
WHERE is_active = TRUE
ORDER BY margin_pct DESC
LIMIT 10
;
-- NULLIF(unit_price, 0) returns NULL when unit_price = 0
-- Division by NULL = NULL (not an error)
-- Without NULLIF: division by zero throws a runtime error

-- ZEROIFNULL — Snowflake-specific, converts NULL to 0
-- Useful for numeric columns where NULL should be treated as zero
SELECT
    session_id,
    customer_id,
    ZEROIFNULL(customer_id)             AS customer_id_safe
FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS
WHERE customer_id IS NULL
LIMIT 5
;
-- customer_id IS NULL → ZEROIFNULL returns 0
-- Equivalent to COALESCE(customer_id, 0) but more explicit
-- Use when NULL semantically means "zero" not "unknown"
-- Note: ZEROIFNULL only works on numeric columns
--       For VARCHAR use COALESCE(col, '')

-- ══════════════════════════════════════════════════════════════
-- STEP 3: CASE WHEN — conditional logic in SQL
-- ══════════════════════════════════════════════════════════════
-- CASE WHEN is the SQL equivalent of IF/ELSE.
-- Use it to create derived columns, segment data, and
-- build readable aggregations.

-- Simple CASE — segment orders by value
SELECT
    order_id,
    order_total,
    CASE
        WHEN order_total >= 500  THEN 'high_value'
        WHEN order_total >= 100  THEN 'mid_value'
        WHEN order_total >= 10   THEN 'low_value'
        ELSE                          'micro'
    END                             AS order_segment
FROM ECOMMERCE.RAW.ORDERS
LIMIT 10
;

-- CASE in aggregation — count by segment in one query
SELECT
    COUNT(*)                                    AS total_orders,
    COUNT(CASE WHEN order_total >= 500
               THEN 1 END)                      AS high_value_orders,
    COUNT(CASE WHEN order_total >= 100
                AND order_total < 500
               THEN 1 END)                      AS mid_value_orders,
    COUNT(CASE WHEN order_total < 100
               THEN 1 END)                      AS low_value_orders,
    ROUND(AVG(order_total), 2)                  AS avg_order_total
FROM ECOMMERCE.RAW.ORDERS
WHERE order_status = 'delivered'
;
-- COUNT(CASE WHEN condition THEN 1 END) counts matching rows
-- CASE returns NULL when no WHEN matches and no ELSE — COUNT ignores NULLs

-- IFF — Snowflake shorthand for simple two-way CASE
SELECT
    customer_id,
    is_active,
    IFF(is_active = TRUE, 'active', 'inactive')     AS status_label,
    IFF(segment = 'Premium', TRUE, FALSE)           AS is_premium
FROM ECOMMERCE.RAW.CUSTOMERS
LIMIT 10
;
-- IFF(condition, true_value, false_value)
-- Cleaner than CASE WHEN for simple binary conditions
--
-- Oracle equivalent: NVL2(expr, value_if_not_null, value_if_null)
-- IFF is more flexible — condition can be any boolean expression
-- NVL2 only checks whether expr is NULL or not NULL
-- IFF(is_active = TRUE, 'active', 'inactive') has no NVL2 equivalent
-- since it tests a boolean condition, not a NULL check

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Type casting — explicit is safer than implicit
-- ══════════════════════════════════════════════════════════════
-- Snowflake performs implicit casting in many situations but
-- explicit casting is always safer and more readable.
-- Two syntaxes — both valid, :: is more common in Snowflake.

-- ── CAST() — ANSI standard syntax ────────────────────────────
SELECT
    CAST('2024-01-15' AS DATE)          AS date_cast,
    CAST('123.45' AS FLOAT)             AS float_cast,
    CAST(42 AS VARCHAR)                 AS string_cast
;

-- ── :: syntax — Snowflake shorthand (more common in practice) ─
SELECT
    '2024-01-15'::DATE                  AS date_cast,
    '123.45'::FLOAT                     AS float_cast,
    42::VARCHAR                         AS string_cast,
    '2024-01-15 10:30:00'::TIMESTAMP_NTZ AS ts_cast
;
-- :: is syntactic sugar for CAST() — identical behaviour
-- Both are valid — :: is more concise and widely used in Snowflake

-- ── CAST fails on bad values ──────────────────────────────────
-- CAST throws a runtime error when the value cannot be converted
SELECT CAST('not_a_number' AS FLOAT);
-- Error: Numeric value 'not_a_number' is not recognized
-- This breaks pipelines when source data is dirty

-- ── TRY_CAST — the safe alternative ──────────────────────────
-- Returns NULL instead of erroring on bad values
SELECT
    TRY_CAST('123.45' AS FLOAT)         AS valid_cast,      -- 123.45
    TRY_CAST('not_a_number' AS FLOAT)   AS invalid_cast,    -- NULL
    TRY_CAST('2024-01-15' AS DATE)      AS valid_date,      -- 2024-01-15
    TRY_CAST('not_a_date' AS DATE)      AS invalid_date     -- NULL
;
-- TRY_CAST is essential when casting data from external sources,
-- VARIANT fields, or any column you do not fully control.
-- After TRY_CAST, check for NULLs to identify bad values:
--   WHERE TRY_CAST(col AS FLOAT) IS NULL AND col IS NOT NULL

-- TRY_CAST is the safe alternative to CAST for untrusted data
-- Use in COPY INTO transformations and when casting VARIANT fields

-- Date and timestamp functions
SELECT
    CURRENT_DATE()                      AS today, --just the date
    CURRENT_TIMESTAMP()                 AS now, --date with TIME
    DATEADD('day', -30, CURRENT_DATE()) AS thirty_days_ago, --POSITIVE -> in the future, NEGATIVE -> in the past
    DATEDIFF('day', '2024-01-01'::DATE, CURRENT_DATE()) AS days_since_new_year,
    -- DATEDIFF(unit, start_date, end_date) → end minus start
    -- swap start and end to get a negative number
    DATE_TRUNC('month', CURRENT_DATE()) AS first_of_month,
    YEAR(CURRENT_DATE())                AS current_year,
    MONTH(CURRENT_DATE())               AS current_month,
    DAY(CURRENT_DATE())                 AS current_day
;

-- Apply date functions to the orders dataset
SELECT
    DATE_TRUNC('month', created_at)     AS order_month,
    -- DATE_TRUNC rounds DOWN to the start of the specified unit
    -- DATE_TRUNC('month', '2024-03-15') → '2024-03-01'
    -- DATE_TRUNC('year',  '2024-03-15') → '2024-01-01'
    -- DATE_TRUNC('day',   '2024-03-15 14:32:00') → '2024-03-15 00:00:00'
    -- Useful for grouping time-series data by month, quarter, or year
    COUNT(*)                            AS order_count,
    ROUND(SUM(order_total), 2)          AS monthly_revenue
FROM ECOMMERCE.RAW.ORDERS
WHERE order_status = 'delivered'
GROUP BY DATE_TRUNC('month', created_at)
ORDER BY order_month
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: String functions — cleaning and transforming text
-- ══════════════════════════════════════════════════════════════

SELECT
    supplier_name,
    UPPER(supplier_name)                AS name_upper,       -- all caps
    LOWER(supplier_name)                AS name_lower,       -- all lowercase
    LENGTH(supplier_name)               AS name_length,      -- character count
    TRIM(supplier_name)                 AS name_trimmed,     -- remove leading/trailing spaces
    LEFT(supplier_name, 10)             AS first_10_chars,   -- first N characters from left
    RIGHT(supplier_name, 5)             AS last_5_chars,     -- last N characters from right
    SUBSTR(supplier_name, 1, 5)         AS substr_1_5,       -- SUBSTR(string, start_pos, length)
                                                             -- start_pos=1 (1-based), length=5
                                                             -- same as LEFT(supplier_name, 5)
    REPLACE(supplier_name, 'Ltd', 'Limited') AS name_replaced, -- replace all occurrences
    SPLIT_PART(contact_email, '@', 2)   AS email_domain      -- SPLIT_PART(string, delimiter, part)
                                                             -- splits 'user@domain.com' on '@'
                                                             -- part=1 → 'user'
                                                             -- part=2 → 'domain.com'
FROM ECOMMERCE.RAW.SUPPLIERS
LIMIT 10
;

-- CONCAT and || operator
-- || is the preferred concatenation operator in Snowflake
-- CONCAT() is the ANSI alternative — identical result
-- CONCAT_WS(separator, col1, col2...) is useful when joining
-- many columns with the same separator

SELECT
    first_name || ' ' || last_name          AS full_name,           -- preferred
    CONCAT(first_name, ' ', last_name)      AS full_name_concat,    -- same result
    CONCAT_WS(', ', city, country)          AS location             -- cleaner for many columns
FROM ECOMMERCE.RAW.CUSTOMERS
LIMIT 10
;

-- REGEXP — pattern matching with regular expressions
-- ── REGEXP_LIKE — pattern matching with regular expressions ───
-- Regular expression notation quick reference:
--   ^        → start of string
--   $        → end of string
--   .        → any single character
--   *        → zero or more of the preceding character
--   +        → one or more of the preceding character
--   ?        → zero or one of the preceding character
--   [abc]    → any one of a, b, or c
--   [a-z]    → any lowercase letter
--   [A-Z]    → any uppercase letter
--   [0-9]    → any digit
--   [A-Za-z0-9] → any letter or digit (alphanumeric)
--   {2,}     → two or more of the preceding character
--   \\.      → literal dot (escaped — \\ in SQL strings)
--   +@       → literal @ sign
--   |        → OR (either pattern)
--   ( )      → group expressions together
--
-- Breaking down the email validation pattern:
-- ^[A-Za-z0-9._%+-]+   → one or more valid email characters before @
-- @                     → literal @ sign
-- [A-Za-z0-9.-]+        → one or more valid domain characters
-- \\.                   → literal dot
-- [A-Za-z]{2,}$        → two or more letters at end (TLD like .com)
-- ─────────────────────────────────────────────────────────────

SELECT
    contact_email,
    REGEXP_LIKE(contact_email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$')
                                        AS is_valid_email
FROM ECOMMERCE.RAW.SUPPLIERS
LIMIT 10
;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: DISTINCT and deduplication patterns
-- ══════════════════════════════════════════════════════════════
-- Deduplication: a data reduction technique that identifies
-- and eliminates redundant copies of repeating information.
--
-- In SQL, DISTINCT removes duplicate rows from a result set.
-- COUNT(DISTINCT col) counts unique values within a column.
-- Both are essential tools for data quality and profiling.

-- DISTINCT values
SELECT DISTINCT order_status
FROM ECOMMERCE.RAW.ORDERS
ORDER BY order_status
;

-- DISTINCT on multiple columns — unique COMBINATIONS not individual columns
-- This returns each unique (category, subcategory) pair
-- NOT unique categories alone AND unique subcategories alone
SELECT DISTINCT
    category,
    subcategory
FROM ECOMMERCE.RAW.PRODUCTS
ORDER BY category, subcategory
;
-- Example: if Electronics has 5 subcategories and Clothing has 3
-- you get 8 rows — one per unique combination
-- If you want unique categories only: SELECT DISTINCT category

-- COUNT DISTINCT — unique value counts
SELECT
    COUNT(DISTINCT customer_id)         AS unique_customers,
    COUNT(DISTINCT product_id)          AS unique_products,
    COUNT(DISTINCT event_id)            AS unique_events,
    COUNT(DISTINCT session_id)          AS unique_sessions
FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS
;
-- COUNT DISTINCT on large tables is expensive — use with care
-- Snowflake must scan the entire column to find all unique values
-- before it can count them — no shortcut via metadata cache
-- unlike COUNT(*) which resolves from partition metadata

-- Snowflake uses HyperLogLog approximation for very large counts
-- HyperLogLog is a probabilistic algorithm — it estimates the
-- distinct count without scanning every value, trading ~1% accuracy
-- for significantly faster performance on large datasets.

-- APPROX_COUNT_DISTINCT — faster approximation (~1% error)
SELECT
    APPROX_COUNT_DISTINCT(customer_id)  AS approx_unique_customers,
    COUNT(DISTINCT customer_id)         AS exact_unique_customers
FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS
;


-- For dashboards and monitoring where exact counts are not critical
-- APPROX_COUNT_DISTINCT is significantly faster on large tables

-- ══════════════════════════════════════════════════════════════
-- STEP 7: LIMIT, SAMPLE, and controlling result size
-- ══════════════════════════════════════════════════════════════

-- LIMIT — return first N rows
SELECT * FROM ECOMMERCE.RAW.ORDERS LIMIT 10;

-- LIMIT with OFFSET — pagination
SELECT
    order_id,
    customer_id,
    order_total
FROM ECOMMERCE.RAW.ORDERS
ORDER BY order_total DESC
LIMIT 10 OFFSET 20
-- LIMIT 10  → return 10 rows
-- OFFSET 20 → skip the first 20 rows, start at row 21
-- Combined  → returns rows 21 through 30
-- ORDER BY is applied first — LIMIT and OFFSET operate on the sorted result
;

-- TABLESAMPLE — random sample without scanning everything
-- Useful for exploring large tables quickly
SELECT *
FROM ECOMMERCE.RAW.CLICKSTREAM_EVENTS
    TABLESAMPLE (1)   -- 1% random sample
LIMIT 20
;
-- TABLESAMPLE (N) returns approximately N% of rows
-- Much faster than SELECT * ... LIMIT N for exploration
-- Results are random — different rows each run

-- SAMPLE synonym — identical behaviour
SELECT *
FROM ECOMMERCE.RAW.ORDERS
    SAMPLE (0.1)      -- 0.1% = ~2,000 rows from 2M
LIMIT 10
;

-- TABLESAMPLE and SAMPLE are the same thing in Snowflake — identical behaviour
-- TABLESAMPLE is the ANSI SQL standard keyword
-- SAMPLE is Snowflake shorthand — more commonly used in practice
-- Both accept the same syntax: (N) where N is the percentage


-- ══════════════════════════════════════════════════════════════
-- STEP 8: Sorting and ordering
-- ══════════════════════════════════════════════════════════════

-- Basic ORDER BY
SELECT
    product_name,
    category,
    unit_price
FROM ECOMMERCE.RAW.PRODUCTS
ORDER BY unit_price DESC
LIMIT 10
;

-- Multi-column sort
SELECT
    category,
    product_name,
    unit_price
FROM ECOMMERCE.RAW.PRODUCTS
WHERE is_active = TRUE
ORDER BY
    category    ASC,
    unit_price  DESC
LIMIT 20
;

-- NULL ordering — NULLs sort LAST by default in ASC
-- Use NULLS FIRST or NULLS LAST to control explicitly
SELECT
    review_id,
    helpful_votes
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
ORDER BY helpful_votes DESC NULLS LAST
LIMIT 10
;
-- NULLS LAST puts NULL helpful_votes at the bottom
-- Without it, behaviour depends on sort direction and platform

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Write a query on ORDERS that returns:
--    · order_year (extracted from created_at)
--    · order_month
--    · order_count
--    · total_revenue
--    · avg_order_value
--    · a revenue_tier column: 'high' if monthly revenue > 1M,
--      'medium' if > 500K, 'low' otherwise
--    Filter to delivered orders only. Order by year and month.
--
-- 2. In CLICKSTREAM_EVENTS, find:
--    · The percentage of events where customer_id IS NULL
--      broken down by device_type
--    · Which device type has the highest anonymous session rate?
--
-- 3. Write a query on CUSTOMERS that:
--    · Creates a full_name column (first + last)
--    · Creates a location column (city + ', ' + country)
--    · Classifies customers as 'premium', 'standard', or 'basic'
--      based on their segment column
--    · Returns only active customers in countries with
--      more than 1,000 customers total
--    · Orders by country and last_name

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I need to compare strings case-insensitively
--    without using ILIKE?
-- A: Use LOWER() on both sides:
--    WHERE LOWER(column) = LOWER('search_value')
--    Or set the session parameter:
--    ALTER SESSION SET QUOTED_IDENTIFIERS_IGNORE_CASE = TRUE
--
-- Q: What if TABLESAMPLE returns different row counts each run?
-- A: That is expected — TABLESAMPLE is probabilistic, not exact.
--    A 1% sample of 2 million rows returns approximately 20,000
--    rows but not exactly. Use LIMIT for deterministic row counts.
--
-- Q: What if TRY_CAST returns NULL for values I expect to work?
-- A: The value format does not match the target type.
--    Debug by selecting the raw value alongside TRY_CAST to see
--    what is failing. Common issues: date formats ('01/15/2024'
--    vs '2024-01-15'), numbers with commas ('1,234' vs '1234'),
--    or trailing whitespace.
--
-- Q: What if ORDER BY makes my query much slower?
-- A: Sorting is expensive on large result sets. Options:
--    1. Filter first to reduce rows before sorting
--    2. Only sort when the output order matters to the consumer
--    3. For dashboard queries, sort in the BI tool not in SQL
--    4. Consider clustering keys for columns you frequently sort on
--       — covered in Goal 5 (Performance Optimization)
--
-- Q: What is different from Oracle SQL I should watch for?
-- A: Key differences:
--    · ROWNUM does not exist — use LIMIT or ROW_NUMBER()
--    · SYSDATE → CURRENT_DATE() or CURRENT_TIMESTAMP()
--    · NVL works but COALESCE is preferred
--    · DECODE works but CASE WHEN is clearer
--    · || for string concatenation works (same as Oracle)
--    · DUAL table does not exist — SELECT 1+1 works directly
