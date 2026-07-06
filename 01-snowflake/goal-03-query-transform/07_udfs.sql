-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 3  : Query and Transform Data
-- Sub-task 3.7 : User-defined functions (UDFs)
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : 06_cortex_ai.sql reviewed
-- COF-C03 domain   : Domain 5 — Data Transformations (17%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   SQL is powerful but limited. Some transformations are too
--   complex, too repetitive, or too logic-heavy for inline SQL.
--   User-defined functions let you package that logic into a
--   named, reusable function you call just like a built-in.
--
--   Once a UDF exists, SELECT my_function(col) works anywhere —
--   in SELECT lists, WHERE clauses, CTEs, and views.
--   Write the logic once. Use it everywhere. Change it once.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: UDF TYPES IN SNOWFLAKE
-- ══════════════════════════════════════════════════════════════
--
-- SCALAR UDF
--   Takes one or more inputs, returns one value per row.
--   The most common type — same behaviour as built-in functions.
--   Can be written in SQL, JavaScript, or Python.
--
-- TABLE FUNCTION (UDTF)
--   Returns a set of rows (a table) rather than a single value.
--   Used when you need to generate or expand rows from an input.
--   Called with TABLE() in the FROM clause.
--
-- AGGREGATE UDF
--   Custom aggregate function — works like SUM() or COUNT()
--   but with your own logic.
--   Written in JavaScript only.
--
-- LANGUAGE OPTIONS:
--   SQL        — simplest, best for SQL-expressible logic
--   JavaScript — available on all editions, good for string/math
--   Python     — most powerful, requires Snowpark (Step 4)
--
-- KEY PROPERTIES:
--   · Live in a schema like tables and views
--   · Support overloading — same name, different argument types
--   · Immutable by default — call with COPY GRANTS to preserve access
--   · Can be secured — SECURE UDF hides implementation
--
-- Oracle equivalent:
--   Oracle CREATE FUNCTION / CREATE OR REPLACE FUNCTION.
--   Same concept, very similar syntax for SQL functions.
--   JavaScript UDFs have no Oracle equivalent.
--   Python UDFs correspond roughly to Oracle's Java stored functions.
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
-- STEP 1: SQL UDF — the simplest starting point
-- ══════════════════════════════════════════════════════════════
-- SQL UDFs wrap a SQL expression into a named function.
-- Use when: the logic is SQL-expressible and reused in many places.

-- Calculate gross margin percentage
CREATE OR REPLACE FUNCTION ECOMMERCE.RAW.gross_margin_pct(
    unit_price FLOAT,
    cost_price FLOAT
)
RETURNS FLOAT
LANGUAGE SQL
COMMENT = 'Returns gross margin percentage: (price - cost) / price * 100'
AS $$
    ROUND(
        NULLIF(unit_price - cost_price, 0)
        / NULLIF(unit_price, 0) * 100
    , 2)
$$
;
-- NULLIF prevents division by zero
-- $$ ... $$ is the function body delimiter

-- Test it
SELECT gross_margin_pct(100.00, 60.00) AS margin_pct;
-- Expected: 40.00

-- Use it in a real query
SELECT
    product_id,
    product_name,
    category,
    unit_price,
    cost_price,
    ECOMMERCE.RAW.gross_margin_pct(unit_price, cost_price) AS margin_pct
FROM ECOMMERCE.RAW.PRODUCTS
WHERE is_active = TRUE
ORDER BY margin_pct DESC
LIMIT 10
;
-- Fully qualified name: DATABASE.SCHEMA.function_name
-- Or just function_name if USE SCHEMA is set correctly

-- Classify order value into a tier — another SQL UDF
CREATE OR REPLACE FUNCTION ECOMMERCE.RAW.order_tier(
    order_total FLOAT
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Classifies an order into value tier'
AS $$
    CASE
        WHEN order_total >= 1000 THEN 'enterprise'
        WHEN order_total >= 500  THEN 'premium'
        WHEN order_total >= 100  THEN 'standard'
        ELSE                          'micro'
    END
$$
;

-- Use it in a GROUP BY
SELECT
    ECOMMERCE.RAW.order_tier(order_total)   AS tier,
    COUNT(*)                                AS order_count,
    ROUND(SUM(order_total), 2)              AS total_revenue,
    ROUND(AVG(order_total), 2)              AS avg_order_value
FROM ECOMMERCE.RAW.ORDERS
WHERE order_status = 'delivered'
GROUP BY ECOMMERCE.RAW.order_tier(order_total)
ORDER BY total_revenue DESC
;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: JavaScript UDF — logic beyond SQL
-- ══════════════════════════════════════════════════════════════
-- JavaScript UDFs handle logic that is awkward in SQL:
-- complex string manipulation, regex, math, conditionals.
-- Available on all Snowflake editions.

-- Clean and normalise a phone number
CREATE OR REPLACE FUNCTION ECOMMERCE.RAW.clean_phone(
    raw_phone VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
COMMENT = 'Strips non-numeric characters from a phone number string'
AS $$
    if (!RAW_PHONE) return null;
    // Remove everything except digits
    var digits = RAW_PHONE.replace(/[^0-9]/g, '');
    if (digits.length === 0) return null;
    // Format as (XXX) XXX-XXXX if 10 digits
    if (digits.length === 10) {
        return '(' + digits.substr(0, 3) + ') '
               + digits.substr(3, 3) + '-'
               + digits.substr(6, 4);
    }
    // Return digits only if not 10 digits
    return digits;
$$
;
-- Note: JavaScript parameter names are UPPERCASE in the function body
-- RAW_PHONE in JS corresponds to raw_phone in the SQL signature

-- Test with various formats
SELECT
    col                             AS raw_phone,
    ECOMMERCE.RAW.clean_phone(col)  AS cleaned_phone
FROM VALUES
    ('555-123-4567'),
    ('(555) 123-4567'),
    ('5551234567'),
    ('+1 555 123 4567'),
    ('invalid'),
    (NULL)
AS t(col)
;

-- Apply to real data
SELECT
    supplier_id,
    supplier_name,
    phone                               AS raw_phone,
    ECOMMERCE.RAW.clean_phone(phone)    AS clean_phone
FROM ECOMMERCE.RAW.SUPPLIERS
LIMIT 10
;

-- Extract email domain — JavaScript UDF
CREATE OR REPLACE FUNCTION ECOMMERCE.RAW.email_domain(
    email VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
COMMENT = 'Extracts the domain portion from an email address'
AS $$
    if (!EMAIL) return null;
    var parts = EMAIL.split('@');
    if (parts.length !== 2) return null;
    return parts[1].toLowerCase();
$$
;

-- Top email domains among customers
SELECT
    ECOMMERCE.RAW.email_domain(email)   AS domain,
    COUNT(*)                            AS customer_count
FROM ECOMMERCE.RAW.CUSTOMERS
GROUP BY ECOMMERCE.RAW.email_domain(email)
ORDER BY customer_count DESC
LIMIT 10
;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: UDF overloading — same name, different types
-- ══════════════════════════════════════════════════════════════
-- Snowflake supports function overloading — the same function
-- name with different argument types. Snowflake picks the right
-- version based on the argument types at call time.

-- Note: JavaScript UDFs do not support INTEGER as an argument type.
-- Use FLOAT or NUMBER for numeric arguments in JavaScript UDFs.
-- SQL UDFs support INTEGER normally.

-- Version 1: format_currency with FLOAT input
CREATE OR REPLACE FUNCTION ECOMMERCE.RAW.format_currency(
    amount FLOAT
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
COMMENT = 'Formats a float as USD currency string'
AS $$
    if (AMOUNT === null || AMOUNT === undefined) return null;
    return '$' + AMOUNT.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
$$
;


SELECT
    ECOMMERCE.RAW.format_currency(1234.56)  AS float_formatted,
    ECOMMERCE.RAW.format_currency(1000)     AS int_formatted
;

-- Use on real data
SELECT
    product_name,
    ECOMMERCE.RAW.format_currency(unit_price)   AS formatted_price,
    ECOMMERCE.RAW.format_currency(cost_price)   AS formatted_cost
FROM ECOMMERCE.RAW.PRODUCTS
ORDER BY unit_price DESC
LIMIT 10
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Table UDFs (UDTFs) — functions that return rows
-- ══════════════════════════════════════════════════════════════
-- A UDTF returns a table (set of rows) rather than a scalar value.
-- Called with TABLE() in the FROM clause.
-- Use when: you need to generate rows from an input value.

-- Generate a date series between two dates
-- (Snowflake has no built-in date series generator)
CREATE OR REPLACE FUNCTION ECOMMERCE.RAW.date_series(
    start_date DATE,
    end_date   DATE
)
RETURNS TABLE (series_date DATE)
LANGUAGE SQL
COMMENT = 'Generates a row for each date between start_date and end_date inclusive'
AS $$
    SELECT DATEADD('day', SEQ4(), start_date) AS series_date
    FROM TABLE(GENERATOR(ROWCOUNT => 3650))  -- max 10 years of dates
    -- ROWCOUNT must be a constant — cannot use an expression.
    -- 3650 = 10 years of daily rows (more than enough for any range).
    -- The WHERE clause below filters to only the requested date range.
    -- Rows outside the range are discarded automatically.    
    WHERE DATEADD('day', SEQ4(), start_date) <= end_date
$$
;

-- Test: generate every date in January 2024
SELECT *
FROM TABLE(ECOMMERCE.RAW.date_series('2024-01-01'::DATE, '2024-01-07'::DATE))
ORDER BY series_date
;
-- Returns 7 rows — one per day

-- Practical use: join with orders to find days with no orders
SELECT
    d.series_date,
    COUNT(o.order_id)           AS order_count,
    COALESCE(ROUND(SUM(o.order_total), 2), 0) AS daily_revenue
FROM TABLE(ECOMMERCE.RAW.date_series('2023-01-01'::DATE, '2023-01-31'::DATE)) d
LEFT JOIN ECOMMERCE.RAW.ORDERS o
    ON o.created_at::DATE = d.series_date
    AND o.order_status    = 'delivered'
GROUP BY d.series_date
ORDER BY d.series_date
;
-- Days with order_count = 0 had no delivered orders
-- This pattern is essential for time-series completeness checks

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Inspect and manage UDFs
-- ══════════════════════════════════════════════════════════════

-- List all UDFs in the schema
SHOW USER FUNCTIONS IN SCHEMA ECOMMERCE.RAW;

SELECT
    "name"              AS function_name,
    "arguments"         AS argument_types,
    "language"          AS language,
    "description"       AS comment
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;

-- See the function definition
SELECT GET_DDL('FUNCTION', 'ECOMMERCE.RAW.gross_margin_pct(FLOAT, FLOAT)');
-- Note: must include argument types in the fully qualified name
-- for overloaded functions

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Secure UDFs — hide implementation from consumers
-- ══════════════════════════════════════════════════════════════
-- A SECURE UDF hides its definition from users who call it.
-- They can USE the function but cannot see how it works.
-- Use for: proprietary scoring models, business rules,
-- anything shared via data sharing or with external roles.

CREATE OR REPLACE SECURE FUNCTION ECOMMERCE.RAW.customer_score(
    order_count   INTEGER,
    total_spent   FLOAT,
    days_active   INTEGER
)
RETURNS FLOAT
LANGUAGE SQL
COMMENT = 'Proprietary customer value score — definition hidden from callers'
AS $$
    ROUND(
        (order_count * 10)
        + (total_spent * 0.01)
        + (days_active * 0.5)
    , 2)
$$
;

-- Callers can use the function but GET_DDL returns nothing
-- (or an error) for the secured implementation
SELECT ECOMMERCE.RAW.customer_score(5, 1250.00, 180) AS score;
-- Returns the score value

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS ECOMMERCE.RAW.gross_margin_pct(FLOAT, FLOAT);
DROP FUNCTION IF EXISTS ECOMMERCE.RAW.order_tier(FLOAT);
DROP FUNCTION IF EXISTS ECOMMERCE.RAW.clean_phone(VARCHAR);
DROP FUNCTION IF EXISTS ECOMMERCE.RAW.email_domain(VARCHAR);
DROP FUNCTION IF EXISTS ECOMMERCE.RAW.format_currency(FLOAT);
DROP FUNCTION IF EXISTS ECOMMERCE.RAW.format_currency(INTEGER);
DROP FUNCTION IF EXISTS ECOMMERCE.RAW.date_series(DATE, DATE);
DROP FUNCTION IF EXISTS ECOMMERCE.RAW.customer_score(INTEGER, FLOAT, INTEGER);

-- Verify
SHOW USER FUNCTIONS IN SCHEMA ECOMMERCE.RAW;
-- Should return zero rows

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a SQL UDF called shipping_status_label that maps
--    order_status values to human-readable labels:
--    'placed'     → 'Order Received'
--    'processing' → 'Being Prepared'
--    'shipped'    → 'On Its Way'
--    'delivered'  → 'Delivered'
--    'cancelled'  → 'Cancelled'
--    anything else → 'Unknown Status'
--    Apply it to the ORDERS table and verify all statuses.
--
-- 2. Create a JavaScript UDF called mask_email that
--    partially masks an email address for privacy:
--    'john.doe@example.com' → 'jo***@example.com'
--    Show the first 2 characters of the local part,
--    replace the rest with ***, keep the domain.
--    Apply to CUSTOMERS and verify the output.
--
-- 3. Create a UDTF called monthly_order_summary that accepts
--    a customer_id and returns a row per month showing:
--    · year_month (DATE_TRUNC month)
--    · order_count
--    · total_spent
--    Join it with CUSTOMERS to show the monthly history
--    for your top 3 customers by total spend.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: When should I use a UDF vs a CTE or inline CASE WHEN?
-- A: Use a UDF when:
--    · The same logic appears in 3+ queries
--    · The logic is complex enough to obscure the query
--    · Multiple teams or roles need the same transformation
--    · The logic involves JavaScript or Python (not SQL-expressible)
--    Use inline SQL (CASE WHEN, CTE) when:
--    · The logic is used in one query only
--    · Simplicity and transparency matter more than reuse
--    · Performance is critical (UDFs add function call overhead)
--
-- Q: What is the performance impact of UDFs?
-- A: SQL UDFs are generally inlined by Snowflake's optimiser —
--    the function body is expanded at compile time, similar to
--    a macro. Overhead is minimal.
--    JavaScript and Python UDFs run in a separate process —
--    there is a per-row function call overhead. On millions of
--    rows this can be significant. Vectorised Python UDFs
--    (batch mode) reduce this overhead substantially.
--    Profile with Query Profile (Goal 5) if UDF performance
--    is a concern.
--
-- Q: Can I call a UDF in a WHERE clause?
-- A: Yes — UDFs work anywhere a scalar expression is valid:
--    SELECT, WHERE, HAVING, GROUP BY, ORDER BY, JOIN ON.
--    SELECT * FROM orders WHERE order_tier(order_total) = 'premium'
--    This makes UDFs much more flexible than views for filtering.
--
-- Q: What happens to UDFs when I drop the schema?
-- A: UDFs are schema-level objects — dropping the schema drops
--    all UDFs in it. Always use IF EXISTS on DROP SCHEMA to
--    avoid accidental destruction in automation scripts.
--
-- Q: What is the Oracle equivalent?
-- A: Oracle CREATE OR REPLACE FUNCTION for scalar UDFs —
--    very similar syntax. Oracle uses PL/SQL instead of
--    JavaScript or Python for non-SQL logic.
--    UDTFs correspond roughly to Oracle pipelined table functions
--    (PIPELINED keyword) — same concept, different syntax.
