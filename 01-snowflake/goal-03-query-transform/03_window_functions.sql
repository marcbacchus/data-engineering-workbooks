-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 3  : Query and Transform Data
-- Sub-task 3.3 : Window functions
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~35 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : 02_joins_aggregations.sql completed
-- COF-C03 domain   : Domain 5 — Data Transformations (17%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Window functions are one of the most powerful features in
--   modern SQL — and one of the most underused. They let you
--   perform calculations ACROSS rows without collapsing them
--   into groups the way GROUP BY does.
--
--   With GROUP BY: 2 million order rows → 10 category rows
--   With window functions: 2 million order rows → still 2 million
--   rows, but each row now carries its category rank, running
--   total, or comparison to the previous row.
--
--   Once you understand window functions you will find yourself
--   replacing complex self-joins and correlated subqueries with
--   clean, readable, performant window function queries.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: HOW WINDOW FUNCTIONS WORK
-- ══════════════════════════════════════════════════════════════
--
-- Syntax:
--   function_name() OVER (
--       PARTITION BY column    -- divide rows into groups (optional)
--       ORDER BY column        -- define row order within each group
--       ROWS/RANGE BETWEEN ... -- define the window frame (optional)
--   )
--
-- KEY TERMS:
--
-- OVER()
--   The presence of OVER() is what makes a function a window
--   function. Without OVER(), COUNT() is an aggregate.
--   With OVER(), COUNT() is a window function — it counts
--   without collapsing rows.
--
-- PARTITION BY
--   Divides rows into independent groups (windows).
--   The function resets for each partition.
--   Think of it as GROUP BY but rows are not collapsed.
--   Omitting PARTITION BY = the entire result set is one window.
--
-- ORDER BY (inside OVER)
--   Defines the order of rows within each partition.
--   Required for ranking and offset functions.
--   For running totals it defines which rows come "before".
--
-- WINDOW FRAME (ROWS/RANGE BETWEEN)
--   Defines which rows relative to the current row are
--   included in the calculation.
--   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--   = all rows from the start of the partition to this row
--   = running total
--
-- WINDOW FUNCTION CATEGORIES:
--
--   Ranking    : ROW_NUMBER, RANK, DENSE_RANK, NTILE
--   Offset     : LAG, LEAD, FIRST_VALUE, LAST_VALUE
--   Aggregate  : SUM, COUNT, AVG, MIN, MAX (with OVER())
--
-- Oracle equivalent:
--   Oracle supports the same ANSI window function syntax.
--   Snowflake adds QUALIFY (cleaner than a subquery for
--   filtering window function results) — covered in Step 2.
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
-- STEP 1: ROW_NUMBER — assign a unique sequential number
-- ══════════════════════════════════════════════════════════════
-- ROW_NUMBER() assigns a unique integer to each row within
-- a partition. Numbers restart at 1 for each partition.
-- No ties — every row gets a unique number.

-- Number orders per customer by date
SELECT
    customer_id,
    order_id,
    order_total,
    created_at                          AS order_date,
    ROW_NUMBER() OVER (
        PARTITION BY customer_id        -- restart numbering per customer
        ORDER BY created_at             -- order by date within each customer
    )                                   AS order_sequence
FROM ECOMMERCE.RAW.ORDERS
WHERE customer_id IN (1, 2, 3)         -- limit to 3 customers for clarity
ORDER BY customer_id, order_sequence
;
-- Each customer's orders are numbered 1, 2, 3...
-- order_sequence = 1 is each customer's FIRST order
-- order_sequence = 2 is their second order, and so on

-- Find each customer's most recent order (order_sequence = 1 with DESC)
SELECT
    customer_id,
    order_id,
    order_total,
    created_at                          AS order_date,
    ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY created_at DESC        -- DESC = most recent first
    )                                   AS recency_rank
FROM ECOMMERCE.RAW.ORDERS
QUALIFY recency_rank = 1               -- keep only the most recent order
                                       -- QUALIFY filters on window function results
                                       -- equivalent to: WHERE in a subquery
ORDER BY customer_id
LIMIT 20
;
-- QUALIFY is Snowflake's clean alternative to wrapping in a subquery.
-- Without QUALIFY you would need:
--   SELECT * FROM (
--       SELECT ..., ROW_NUMBER() OVER (...) AS recency_rank
--       FROM orders
--   ) WHERE recency_rank = 1
-- QUALIFY eliminates that subquery entirely.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: RANK and DENSE_RANK — ranking with ties
-- ══════════════════════════════════════════════════════════════
-- When multiple rows have the same value, ranking functions
-- handle ties differently:
--
-- ROW_NUMBER  → always unique: 1, 2, 3, 4, 5 (no ties)
-- RANK        → ties get same rank, next rank skips: 1, 2, 2, 4, 5
-- DENSE_RANK  → ties get same rank, no gaps:        1, 2, 2, 3, 4
--
-- Example with ratings 5, 4, 4, 3, 2:
-- ROW_NUMBER : 1, 2, 3, 4, 5
-- RANK       : 1, 2, 2, 4, 5  ← 3 is skipped after two 2nd places
-- DENSE_RANK : 1, 2, 2, 3, 4  ← no gaps, next rank after tie is 3

-- Rank products by average rating within each category
SELECT
    p.category,
    p.product_name,
    ROUND(AVG(r.rating), 2)             AS avg_rating,
    COUNT(r.review_id)                  AS review_count,
    ROW_NUMBER() OVER (
        PARTITION BY p.category
        ORDER BY AVG(r.rating) DESC
    )                                   AS row_num,
    RANK() OVER (
        PARTITION BY p.category
        ORDER BY AVG(r.rating) DESC
    )                                   AS rank_with_gaps,
    DENSE_RANK() OVER (
        PARTITION BY p.category
        ORDER BY AVG(r.rating) DESC
    )                                   AS rank_no_gaps
FROM ECOMMERCE.RAW.PRODUCTS p
INNER JOIN ECOMMERCE.RAW.PRODUCT_REVIEWS r
    ON p.product_id = r.product_id
GROUP BY
    p.category,
    p.product_name
QUALIFY review_count >= 10             -- only products with enough reviews
ORDER BY p.category, rank_no_gaps
LIMIT 30
;
-- Compare row_num, rank_with_gaps, and rank_no_gaps side by side
-- When two products share the same avg_rating you will see
-- rank_with_gaps skip a number but rank_no_gaps does not

-- ══════════════════════════════════════════════════════════════
-- STEP 3: NTILE — divide rows into N equal buckets
-- ══════════════════════════════════════════════════════════════
-- NTILE(N) divides rows into N roughly equal groups.
-- Useful for percentile analysis and customer segmentation.

-- Divide customers into 4 quartiles by total spend
SELECT
    customer_id,
    total_spent,
    NTILE(4) OVER (
        ORDER BY total_spent DESC
    )                                   AS spend_quartile,
    -- 1 = top 25% spenders, 4 = bottom 25% spenders
    CASE NTILE(4) OVER (ORDER BY total_spent DESC)
        WHEN 1 THEN 'top_25_pct'
        WHEN 2 THEN 'upper_mid'
        WHEN 3 THEN 'lower_mid'
        WHEN 4 THEN 'bottom_25_pct'
    END                                 AS spend_segment
FROM (
    SELECT
        customer_id,
        ROUND(SUM(order_total), 2)      AS total_spent
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
    GROUP BY customer_id
) customer_totals
ORDER BY total_spent DESC
LIMIT 20
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: LAG and LEAD — access adjacent rows
-- ══════════════════════════════════════════════════════════════
-- LAG  — access a value from a PREVIOUS row in the window
-- LEAD — access a value from a FOLLOWING row in the window
--
-- Syntax: LAG(column, offset, default) OVER (ORDER BY ...)
--   offset  = how many rows back (default 1)
--   default = value if no previous row exists (default NULL)
--
-- Most common use: period-over-period comparison
-- "What was the value last month?" → LAG with ORDER BY month

-- Month-over-month revenue comparison
SELECT
    order_month,
    monthly_revenue,
    LAG(monthly_revenue) OVER (
        ORDER BY order_month
    )                                   AS prev_month_revenue,
    -- ↑ previous month's revenue — NULL for the first month
    ROUND(
        monthly_revenue
        - LAG(monthly_revenue) OVER (ORDER BY order_month)
    , 2)                                AS revenue_change,
    -- absolute change vs previous month
    ROUND(
        (monthly_revenue
        - LAG(monthly_revenue) OVER (ORDER BY order_month))
        * 100.0
        / NULLIF(LAG(monthly_revenue) OVER (ORDER BY order_month), 0)
    , 2)                                AS pct_change
    -- percentage change vs previous month
    -- NULLIF prevents division by zero if previous month = 0
FROM (
    SELECT
        DATE_TRUNC('month', created_at) AS order_month,
        ROUND(SUM(order_total), 2)      AS monthly_revenue
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
    GROUP BY DATE_TRUNC('month', created_at)
) monthly
ORDER BY order_month
;

-- LEAD — look ahead to the next row
-- Find the next order date for each customer's orders
SELECT
    customer_id,
    order_id,
    created_at                          AS order_date,
    LEAD(created_at) OVER (
        PARTITION BY customer_id
        ORDER BY created_at
    )                                   AS next_order_date,
    DATEDIFF('day',
        created_at,
        LEAD(created_at) OVER (
            PARTITION BY customer_id
            ORDER BY created_at
        )
    )                                   AS days_until_next_order
FROM ECOMMERCE.RAW.ORDERS
WHERE customer_id IN (1, 2, 3)
ORDER BY customer_id, order_date
;
-- next_order_date = NULL for each customer's most recent order
-- days_until_next_order = NULL for the last order (no next order)

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Running totals and cumulative aggregates
-- ══════════════════════════════════════════════════════════════
-- Aggregate functions with OVER() calculate across a window
-- of rows rather than the entire result set.
-- The ROWS BETWEEN clause defines the window frame.

-- Running total of revenue by month
SELECT
    order_month,
    monthly_revenue,
    SUM(monthly_revenue) OVER (
        ORDER BY order_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        -- ↑ from the very first row up to and including this row
    )                                   AS cumulative_revenue,
    ROUND(
        SUM(monthly_revenue) OVER (
            ORDER BY order_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
        * 100.0
        / SUM(monthly_revenue) OVER ()  -- total across ALL rows
    , 2)                                AS pct_of_total_revenue
    -- ↑ OVER() with no PARTITION BY or ORDER BY = entire result set
FROM (
    SELECT
        DATE_TRUNC('month', created_at) AS order_month,
        ROUND(SUM(order_total), 2)      AS monthly_revenue
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
    GROUP BY DATE_TRUNC('month', created_at)
) monthly
ORDER BY order_month
;
-- cumulative_revenue grows each month — running total
-- pct_of_total_revenue shows how much of annual revenue
-- was earned by the end of each month

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Moving averages — smoothing time series data
-- ══════════════════════════════════════════════════════════════
-- A moving average smooths out short-term fluctuations
-- to reveal the underlying trend. Common in financial and
-- operational reporting.

-- 3-month moving average of revenue
SELECT
    order_month,
    monthly_revenue,
    ROUND(AVG(monthly_revenue) OVER (
        ORDER BY order_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        -- ↑ this row plus the 2 rows before it = 3-month window
    ), 2)                               AS revenue_3mo_avg,
    -- 3-month moving average
    ROUND(AVG(monthly_revenue) OVER (
        ORDER BY order_month
        ROWS BETWEEN 5 PRECEDING AND CURRENT ROW
        -- ↑ this row plus the 5 rows before it = 6-month window
    ), 2)                               AS revenue_6mo_avg
    -- 6-month moving average — smoother, slower to react
FROM (
    SELECT
        DATE_TRUNC('month', created_at) AS order_month,
        ROUND(SUM(order_total), 2)      AS monthly_revenue
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
    GROUP BY DATE_TRUNC('month', created_at)
) monthly
ORDER BY order_month
;
-- First 2 months will show smaller averages — not enough
-- preceding rows to fill the full window. Snowflake uses
-- whatever rows are available rather than returning NULL.
-- This is called a shrinking window at the start of the series.

-- ══════════════════════════════════════════════════════════════
-- STEP 7: FIRST_VALUE and LAST_VALUE
-- ══════════════════════════════════════════════════════════════
-- FIRST_VALUE — return the first value in the window
-- LAST_VALUE  — return the last value in the window
-- Useful for comparing each row to the best or worst in its group

-- Compare each product's rating to the best in its category
SELECT
    p.category,
    p.product_name,
    ROUND(AVG(r.rating), 2)             AS avg_rating,
    FIRST_VALUE(p.product_name) OVER (
        PARTITION BY p.category
        ORDER BY AVG(r.rating) DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                   AS best_product_in_category,
    -- ↑ the product with the highest avg rating in this category
    ROUND(FIRST_VALUE(AVG(r.rating)) OVER (
        PARTITION BY p.category
        ORDER BY AVG(r.rating) DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ), 2)                               AS best_rating_in_category,
    ROUND(AVG(r.rating) - FIRST_VALUE(AVG(r.rating)) OVER (
        PARTITION BY p.category
        ORDER BY AVG(r.rating) DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ), 2)                               AS gap_from_best
    -- ↑ negative = below the best, 0 = IS the best
FROM ECOMMERCE.RAW.PRODUCTS p
INNER JOIN ECOMMERCE.RAW.PRODUCT_REVIEWS r
    ON p.product_id = r.product_id
GROUP BY p.category, p.product_name
QUALIFY COUNT(r.review_id) >= 10
ORDER BY p.category, avg_rating DESC
LIMIT 30
;
-- gap_from_best = 0 for the top product in each category
-- Negative values show how far below the category leader each product is

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Putting it together — a real analytical use case
-- ══════════════════════════════════════════════════════════════
-- Customer purchase behaviour analysis combining multiple
-- window functions in one query — the kind of query that
-- powers customer analytics dashboards.

SELECT
    o.customer_id,
    o.order_id,
    o.order_total,
    o.created_at                        AS order_date,

    -- Order sequence for this customer
    ROW_NUMBER() OVER (
        PARTITION BY o.customer_id
        ORDER BY o.created_at
    )                                   AS order_number,

    -- Running total spend per customer
    SUM(o.order_total) OVER (
        PARTITION BY o.customer_id
        ORDER BY o.created_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                   AS cumulative_spend,

    -- Days since previous order (NULL for first order)
    DATEDIFF('day',
        LAG(o.created_at) OVER (
            PARTITION BY o.customer_id
            ORDER BY o.created_at
        ),
        o.created_at
    )                                   AS days_since_last_order,

    -- Order value vs customer's own average
    ROUND(o.order_total
        - AVG(o.order_total) OVER (
            PARTITION BY o.customer_id
        )
    , 2)                                AS vs_personal_avg,
    -- positive = above their usual spend, negative = below

    -- Order value rank within customer (1 = their biggest order)
    RANK() OVER (
        PARTITION BY o.customer_id
        ORDER BY o.order_total DESC
    )                                   AS spend_rank

FROM ECOMMERCE.RAW.ORDERS o
WHERE o.order_status = 'delivered'
  AND o.customer_id  IN (
        SELECT customer_id
        FROM ECOMMERCE.RAW.ORDERS
        GROUP BY customer_id
        HAVING COUNT(*) >= 5            -- customers with at least 5 orders
        LIMIT 3                         -- pick 3 for readability
    )
ORDER BY o.customer_id, order_date
;
-- Read this result row by row for one customer:
-- · order_number shows their purchase sequence
-- · cumulative_spend grows with each order
-- · days_since_last_order reveals purchase frequency
-- · vs_personal_avg shows whether this was a big or small order for them
-- · spend_rank shows where this order ranks in their history

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Using ROW_NUMBER and QUALIFY, find each supplier's
--    highest-rated product (by average review rating).
--    Return: supplier_name, product_name, avg_rating.
--    Each supplier should appear exactly once.
--
-- 2. Calculate a 3-month moving average of return counts
--    by month. Which 3-month period had the highest
--    average return rate?
--
-- 3. Using LAG, find the month-over-month change in
--    unique customers placing orders. Which month had
--    the biggest increase in new buyers?
--    Which had the biggest drop?
--
-- 4. Using NTILE(10), divide all products into deciles
--    by unit_price. What is the average unit_price
--    and average review rating for each decile?
--    Is there a correlation between price and rating?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What is the difference between PARTITION BY in a window
--    function and GROUP BY?
-- A: GROUP BY collapses rows — 1,000 rows grouped by category
--    becomes 10 rows (one per category). All detail is lost.
--    PARTITION BY in a window function keeps all rows — 1,000
--    rows stay 1,000 rows, but each row now carries category-
--    level calculations alongside its own values.
--    Rule of thumb: if you need the detail AND the summary
--    on the same row — use window functions, not GROUP BY.
--
-- Q: What if I forget ORDER BY inside OVER() for a ranking function?
-- A: ROW_NUMBER, RANK, DENSE_RANK, LAG, and LEAD all require
--    ORDER BY inside OVER(). Without it Snowflake will error.
--    Aggregate window functions (SUM, AVG) do not require it
--    but without ORDER BY the window frame is the entire
--    partition — you get a group total, not a running total.
--
-- Q: What if QUALIFY is not available in my environment?
-- A: QUALIFY is Snowflake-specific. In other databases wrap
--    in a subquery instead:
--    SELECT * FROM (
--        SELECT ..., ROW_NUMBER() OVER (...) AS rn
--        FROM table
--    ) WHERE rn = 1
--    In Snowflake always use QUALIFY — it is cleaner and faster.
--
-- Q: What is the performance impact of window functions?
-- A: Window functions require sorting data within partitions —
--    this uses warehouse memory and compute. On large tables:
--    · Use WHERE to filter rows before the window function runs
--    · Avoid window functions in WHERE or HAVING (use QUALIFY)
--    · Multiple window functions with the same OVER() clause
--      are optimised by Snowflake into a single sort pass
--    · Different OVER() clauses each require a separate sort
--
-- Q: What is the Oracle equivalent?
-- A: Oracle supports the same ANSI window function syntax —
--    ROW_NUMBER, RANK, LAG, LEAD, SUM OVER all work identically.
--    The one Snowflake advantage: QUALIFY has no Oracle equivalent.
--    In Oracle you always need a subquery to filter on window
--    function results. Snowflake's QUALIFY eliminates that overhead.
