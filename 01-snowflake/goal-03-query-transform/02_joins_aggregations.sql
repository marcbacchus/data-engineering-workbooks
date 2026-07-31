-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 3  : Query and Transform Data
-- Sub-task 3.2 : Joins and aggregations at scale
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~35 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : 01_sql_fundamentals.sql completed
-- COF-C03 domain   : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Single-table queries only get you so far. Real analytical
--   work joins multiple tables — customers to orders, orders to
--   products, products to suppliers — and aggregates the results
--   into metrics that drive business decisions.
--
--   This sub-task covers joins and aggregations on a dataset
--   with over 10 million rows across 10 related tables. The
--   queries here are representative of what you would build
--   in a production analytics environment.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: JOIN TYPES
-- ══════════════════════════════════════════════════════════════
--
-- INNER JOIN
--   Returns rows that have a match in BOTH tables.
--   Rows with no match on either side are excluded.
--   Most common join type in analytical SQL.
--
-- LEFT JOIN (LEFT OUTER JOIN)
--   Returns ALL rows from the left table plus matching rows
--   from the right table. Non-matching right side = NULL.
--   Use when you want to keep all left-side rows regardless
--   of whether a match exists on the right.
--
-- RIGHT JOIN (RIGHT OUTER JOIN)
--   Opposite of LEFT JOIN — keeps all right-side rows.
--   Rarely used in practice — rewrite as LEFT JOIN by
--   swapping table order for consistency.
--
-- FULL OUTER JOIN
--   Returns all rows from BOTH tables. NULLs where no match.
--   Use for reconciliation — finding rows that exist in one
--   table but not the other.
--
-- CROSS JOIN
--   Returns every combination of rows from both tables.
--   (rows in A) × (rows in B) — use with extreme care.
--   Useful for generating combinations or test data.
--
-- SELF JOIN
--   A table joined to itself using an alias.
--   Used for hierarchical data or comparing rows within
--   the same table.
--
-- Oracle equivalent:
--   Oracle uses the same JOIN syntax as Snowflake (ANSI standard).
--   The old Oracle comma-join syntax (FROM a, b WHERE a.id = b.id)
--   works in Snowflake but avoid it — explicit JOIN syntax is
--   clearer and less error-prone.

-- ── JOIN types illustrated with sample data ───────────────────
--
-- LEFT TABLE: Customers          RIGHT TABLE: Orders
-- ┌─────────────────────┐        ┌────────────────────────-──┐
-- │ id │ name           │        │ cust_id │ order           │
-- ├────┼────────────────┤        ├─────────┼──────────────-──┤
-- │  1 │ Alice          │        │       1 │ Order A         │
-- │  2 │ Bob            │        │       2 │ Order B         │
-- │  3 │ Carol          │        │       3 │ Order C         │
-- │  4 │ Dave  ←no order│        │       9 │ Order D ←no cust│
-- │  5 │ Eve   ←no order│        │       9 │ Order E ←no cust│
-- └─────────────────────┘        └──────────────────────────-┘
--
-- INNER JOIN → 3 rows (matched only)
-- ┌────┬───────┬─────────┬─────────┐
-- │ id │ name  │ cust_id │ order   │
-- ├────┼───────┼─────────┼─────────┤
-- │  1 │ Alice │       1 │ Order A │
-- │  2 │ Bob   │       2 │ Order B │
-- │  3 │ Carol │       3 │ Order C │
-- └────┴───────┴─────────┴─────────┘
--
-- LEFT JOIN → 5 rows (3 matched rows + 2 in left table, NULLs for no match)
-- ┌────┬───────┬─────────┬─────────┐
-- │ id │ name  │ cust_id │ order   │
-- ├────┼───────┼─────────┼─────────┤
-- │  1 │ Alice │       1 │ Order A │
-- │  2 │ Bob   │       2 │ Order B │
-- │  3 │ Carol │       3 │ Order C │
-- │  4 │ Dave  │    NULL │ NULL    │ ← no order
-- │  5 │ Eve   │    NULL │ NULL    │ ← no order
-- └────┴───────┴─────────┴─────────┘
--
-- RIGHT JOIN → 5 rows (3 matched rows + 2 in right table, NULLs for no match)
-- ┌──────┬───────┬─────────┬─────────┐
-- │ id   │ name  │ cust_id │ order   │
-- ├──────┼───────┼─────────┼─────────┤
-- │    1 │ Alice │       1 │ Order A │
-- │    2 │ Bob   │       2 │ Order B │
-- │    3 │ Carol │       3 │ Order C │
-- │ NULL │ NULL  │       9 │ Order D │ ← no customer
-- │ NULL │ NULL  │       9 │ Order E │ ← no customer
-- └──────┴───────┴─────────┴─────────┘
--
-- FULL OUTER JOIN → 7 rows (3 rows matched + 2 left unmatched + 2 rows right unmatched)
-- ┌──────┬───────┬─────────┬─────────┐
-- │ id   │ name  │ cust_id │ order   │
-- ├──────┼───────┼─────────┼─────────┤
-- │    1 │ Alice │       1 │ Order A │ ← matched
-- │    2 │ Bob   │       2 │ Order B │ ← matched
-- │    3 │ Carol │       3 │ Order C │ ← matched
-- │    4 │ Dave  │    NULL │ NULL    │ ← left only
-- │    5 │ Eve   │    NULL │ NULL    │ ← left only
-- │ NULL │ NULL  │       9 │ Order D │ ← right only
-- │ NULL │ NULL  │       9 │ Order E │ ← right only
-- └──────┴───────┴─────────┴─────────┘
--
-- RULE: LEFT JOIN  = INNER JOIN + unmatched LEFT rows
--       RIGHT JOIN = INNER JOIN + unmatched RIGHT rows
--       FULL OUTER = INNER JOIN + unmatched LEFT + unmatched RIGHT
-- ─────────────────────────────────────────────────────────────
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
-- STEP 1: INNER JOIN — the most common join
-- ══════════════════════════════════════════════════════════════
-- ── Table order in FROM and JOIN clauses ──────────────────────
-- In Snowflake, table order in JOIN clauses does NOT affect
-- correctness — the query optimizer determines the most
-- efficient join order regardless of how you write it.
--
-- However, convention and readability matter:
--   · Start with the driving table — the one you are primarily
--     interested in (e.g. ORDERS if analyzing orders)
--   · Join dimension tables to the driving table
--     (CUSTOMERS, PRODUCTS, SUPPLIERS)
--   · Join fact tables last if adding detail
--     (ORDER_ITEMS, RETURNS)
--
-- This convention makes queries easier to read and maintain
-- even though Snowflake's optimizer may reorder joins internally.
--
-- Oracle note: Oracle's older rule-based optimizer WAS sensitive
-- to table order — the last table in FROM was the driving table.
-- Snowflake's cost-based optimizer makes this irrelevant.
-- Write for readability, not for optimizer hints.
-- ─────────────────────────────────────────────────────────────


-- Returns only rows that have a match in both tables.
-- Customers with no orders are excluded.
-- Orders with no matching customer are excluded.


-- Note: JOIN and INNER JOIN are identical — INNER is implied
-- Both of these produce the same result:
--   FROM customers c JOIN orders o ON c.customer_id = o.customer_id
--   FROM customers c INNER JOIN orders o ON c.customer_id = o.customer_id
--
-- Most practitioners omit INNER for brevity.
-- This workbook uses INNER JOIN explicitly for clarity —
-- so the join type is always visible when reading the code.
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name  AS customer_name,
    c.country,
    c.segment,
    o.order_id,
    o.order_status,
    o.order_total,
    o.created_at                        AS order_date
FROM ECOMMERCE.RAW.CUSTOMERS c
INNER JOIN ECOMMERCE.RAW.ORDERS o
    ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_total  > 500
ORDER BY o.order_total DESC
LIMIT 20
;
-- Table aliases (c, o) make multi-table queries readable.
-- Always qualify column names with the table alias when
-- joining — avoids ambiguity and makes the query self-documenting.

-- Three-table join — the most common analytical pattern
-- customers → orders → order_items
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name  AS customer_name,
    c.segment,
    COUNT(DISTINCT o.order_id)          AS total_orders,
    COUNT(oi.order_item_id)             AS total_items,
    ROUND(SUM(oi.line_total), 2)        AS total_revenue
FROM ECOMMERCE.RAW.CUSTOMERS c
INNER JOIN ECOMMERCE.RAW.ORDERS o
    ON c.customer_id = o.customer_id
INNER JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY
    c.customer_id,
    c.first_name || ' ' || c.last_name,
    c.segment
ORDER BY total_revenue DESC
LIMIT 10
;
-- Top 10 customers by revenue across delivered orders
-- COUNT(DISTINCT o.order_id) — unique orders per customer
-- COUNT(oi.order_item_id)    — total line items purchased

-- ══════════════════════════════════════════════════════════════
-- STEP 2: LEFT JOIN — keep all rows from the left table
-- ══════════════════════════════════════════════════════════════
-- LEFT JOIN keeps every row from the left table (CUSTOMERS)
-- even if there is no matching row in the right table (ORDERS).
-- Non-matching rows get NULL for all right-table columns.

-- Customers with no orders in 2019
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name  AS customer_name,
    c.country,
    c.segment,
    o.order_id
FROM ECOMMERCE.RAW.CUSTOMERS c
LEFT JOIN ECOMMERCE.RAW.ORDERS o
    ON c.customer_id = o.customer_id
   AND YEAR(o.created_at) = 2019       -- filter on right side in ON clause
WHERE o.order_id IS NULL               -- customers with no 2019 orders
LIMIT 20
;
-- 100,000 total customers - 86,572 with 2019 orders
-- = ~13,428 customers with no orders in 2019
--
-- Note: YEAR(o.created_at) = 2019 is in the ON clause not WHERE
-- Putting it in WHERE would turn the LEFT JOIN into an INNER JOIN
-- because WHERE filters AFTER joining — eliminating the NULL rows
-- ON filters BEFORE joining — preserving the LEFT JOIN behaviour

 
-- Order items with and without returns
-- LEFT JOIN preserves all order items even those never returned
SELECT
    oi.order_item_id,
    oi.order_id,
    oi.product_id,
    oi.line_total,
    r.return_id,                        -- NULL if never returned
    r.return_reason,                    -- NULL if never returned
    COALESCE(r.return_status, 'not_returned') AS return_status
FROM ECOMMERCE.RAW.ORDER_ITEMS oi
LEFT JOIN ECOMMERCE.RAW.RETURNS r
    ON oi.order_item_id = r.order_item_id
LIMIT 20
;
-- Most rows will have NULL return_id — most items are never returned
-- COALESCE converts NULL return_status to 'not_returned'
-- making NULL values meaningful in the output

-- ── RIGHT JOIN — mirror image of LEFT JOIN ────────────────────
-- RIGHT JOIN keeps ALL rows from the RIGHT table.
-- In practice: swap the table order and use LEFT JOIN instead.
-- These two queries return identical results:

-- RIGHT JOIN (uncommon in practice)
-- ORDERS(left) RIGHT JOIN CUSTOMERS(right)
SELECT c.customer_id, o.order_id
FROM ECOMMERCE.RAW.ORDERS o
RIGHT JOIN ECOMMERCE.RAW.CUSTOMERS c
    ON o.customer_id = c.customer_id
LIMIT 5;


-- LEFT JOIN (preferred — same result, more readable)
SELECT c.customer_id, o.order_id
FROM ECOMMERCE.RAW.CUSTOMERS c
LEFT JOIN ECOMMERCE.RAW.ORDERS o
    ON c.customer_id = o.customer_id
LIMIT 5;

-- KEY RULE:
-- LEFT JOIN  → ALL rows from the table on the LEFT of JOIN
-- RIGHT JOIN → ALL rows from the table on the RIGHT of JOIN
-- The table position relative to the JOIN keyword is what matters
-- Most practitioners always use LEFT JOIN and swap table order
-- for consistency — RIGHT JOIN is rarely seen in production code

-- ══════════════════════════════════════════════════════════════
-- STEP 3: FULL OUTER JOIN — reconciliation pattern
-- ══════════════════════════════════════════════════════════════
-- Returns all rows from both tables.
-- NULLs on the left where no match in right table.
-- NULLs on the right where no match in left table.
-- Most useful for data reconciliation and auditing.

-- Compare product counts: products that have been ordered
-- vs products that have never been ordered
SELECT
    p.product_id                        AS catalog_product_id,
    p.product_name,
    p.category,
    oi.product_id                       AS ordered_product_id,
    COUNT(oi.order_item_id)             AS times_ordered
FROM ECOMMERCE.RAW.PRODUCTS p
FULL OUTER JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON p.product_id = oi.product_id
GROUP BY
    p.product_id,
    p.product_name,
    p.category,
    oi.product_id
ORDER BY times_ordered DESC NULLS LAST
LIMIT 20
;

 
-- Products with times_ordered = NULL have never been ordered
-- Products where catalog_product_id is NULL exist in ORDER_ITEMS
-- but not in the PRODUCTS catalog — data quality issue

-- Simpler reconciliation: which products have never been ordered?
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.unit_price
FROM ECOMMERCE.RAW.PRODUCTS p
LEFT JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON p.product_id = oi.product_id
ORDER BY p.unit_price DESC
;
-- Note: A LEFT JOIN with IS NULL check is usually cleaner
-- than FULL OUTER JOIN for simple "not in" scenarios


-- ⚠ PERFORMANCE WARNING:
-- FULL OUTER JOIN on large tables is expensive.
-- Snowflake must scan ALL rows from BOTH tables,
-- hold them in memory, and match every combination.
-- On tables with millions of rows this can be very slow
-- and consume significant warehouse credits.
--
-- Use FULL OUTER JOIN for:
--   · Small reconciliation datasets
--   · Data quality checks (run once, not in dashboards)
--   · Audit queries where completeness matters
--
-- Avoid FULL OUTER JOIN for:
--   · Production dashboards and reports
--   · Large fact tables (millions of rows)
--   · Any query that runs frequently
--
-- Alternative: run two separate LEFT JOINs and UNION ALL
-- the results — more readable and easier to optimize.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: JOIN conditions and common mistakes
-- ══════════════════════════════════════════════════════════════

-- ── Multiple join conditions ──────────────────────────────────
-- Sometimes you need to join on more than one column
SELECT
    r.return_id,
    r.order_id,
    r.product_id,
    r.return_reason,
    oi.quantity,
    oi.line_total
FROM ECOMMERCE.RAW.RETURNS r
INNER JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON r.order_id      = oi.order_id
   AND r.product_id    = oi.product_id
   AND r.order_item_id = oi.order_item_id
LIMIT 10
;
-- Multiple AND conditions in the ON clause narrow the match
-- All conditions must be true for a row to join


-- ── Common mistake: Cartesian product from missing ON clause ──
-- Missing or wrong join condition multiplies rows unexpectedly
-- NEVER do this accidentally:
-- SELECT * FROM CUSTOMERS, ORDERS  ← old Oracle syntax without WHERE
-- This returns 100,000 × 2,000,000 = 200 billion rows
--
-- Always verify row counts after joins on large tables:
SELECT COUNT(*) AS joined_rows
FROM ECOMMERCE.RAW.ORDERS o
INNER JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON o.order_id = oi.order_id
;
-- Expected: ~4.6M rows (multiple items per order — fan-out)
-- If you see an unexpectedly large number check your join condition

-- ══════════════════════════════════════════════════════════════
-- STEP 5: GROUP BY and aggregation functions
-- ══════════════════════════════════════════════════════════════
-- Aggregation collapses multiple rows into summary values.
-- GROUP BY defines which columns to group by — all non-aggregated
-- columns in SELECT must appear in GROUP BY.

-- ── GROUP BY rule — the one rule that trips up everyone ───────
-- Every column in SELECT falls into one of two categories:
--
--   1. AGGREGATE function   → COUNT, SUM, AVG, MIN, MAX
--      These collapse many rows into one value.
--      Do NOT go in GROUP BY.
--
--   2. Non-aggregate column → plain column names
--      These define the groups.
--      MUST go in GROUP BY.
--
-- Simple test: ask yourself for each SELECT column —
--   "Is this wrapped in an aggregate function?"
--   YES → leave it out of GROUP BY
--   NO  → it must be in GROUP BY
--
-- Example:
--   SELECT category,        ← no aggregate → must be in GROUP BY
--          COUNT(*),        ← aggregate    → do NOT add to GROUP BY
--          SUM(revenue),    ← aggregate    → do NOT add to GROUP BY
--          AVG(price)       ← aggregate    → do NOT add to GROUP BY
--   FROM ...
--   GROUP BY category       ← only the non-aggregate column
--
-- Common error:
--   SELECT category, product_name, COUNT(*)
--   GROUP BY category
--   → ERROR: product_name must appear in GROUP BY or aggregate
-- ─────────────────────────────────────────────────────────────

-- ── What about functions on columns? ─────────────────────────
-- Non-aggregate functions (UPPER, LOWER, DATE_TRUNC, YEAR, etc.)
-- applied to a column do NOT make it an aggregate.
-- The result must still appear in GROUP BY — exactly as written
-- in the SELECT clause:
--
--   SELECT UPPER(country),        ← non-aggregate → GROUP BY
--          DATE_TRUNC('month', created_at), ← non-aggregate → GROUP BY
--          COUNT(*)               ← aggregate → do NOT add
--   FROM ...
--   GROUP BY UPPER(country),      ← must match SELECT exactly
--            DATE_TRUNC('month', created_at)
--
-- Rule of thumb: if you can see the column in every individual row
--                it is non-aggregate → it goes in GROUP BY
--               if it summarises multiple rows into one value
--                it is aggregate → it stays OUT of GROUP BY
-- ─────────────────────────────────────────────────────────────

-- Revenue by product category
SELECT
    p.category,
    -- ↑ GROUP BY rule: every column in SELECT that is NOT an
    --   aggregate function MUST appear in the GROUP BY clause.
    --   Here: p.category is the only non-aggregate → GROUP BY p.category
    COUNT(DISTINCT o.order_id)          AS total_orders,
    COUNT(oi.order_item_id)             AS total_items_sold,
    SUM(oi.quantity)                    AS total_units_sold,
    ROUND(SUM(oi.line_total), 2)        AS total_revenue,
    ROUND(AVG(oi.line_total), 2)        AS avg_line_value,
    ROUND(MIN(oi.unit_price), 2)        AS min_price,
    ROUND(MAX(oi.unit_price), 2)        AS max_price
FROM ECOMMERCE.RAW.ORDER_ITEMS oi
INNER JOIN ECOMMERCE.RAW.PRODUCTS p
    ON oi.product_id = p.product_id
INNER JOIN ECOMMERCE.RAW.ORDERS o
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY p.category
-- ↑ One row per unique category value.
--   If this returns 10 rows → there are exactly 10 product categories
--   in the delivered orders. The GROUP BY collapses millions of
--   order item rows into 10 summary rows — one per category.
ORDER BY total_revenue DESC
;

-- Monthly revenue trend — GROUP BY derived column
SELECT
    DATE_TRUNC('month', o.created_at)   AS order_month,
    COUNT(DISTINCT o.customer_id)       AS unique_customers,
    COUNT(DISTINCT o.order_id)          AS total_orders,
    ROUND(SUM(oi.line_total), 2)        AS monthly_revenue,
    ROUND(AVG(o.order_total), 2)        AS avg_order_value
FROM ECOMMERCE.RAW.ORDERS o
INNER JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY DATE_TRUNC('month', o.created_at)
ORDER BY order_month
;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: HAVING — filter on aggregated values
-- ══════════════════════════════════════════════════════════════
-- WHERE filters rows BEFORE aggregation.
-- HAVING filters groups AFTER aggregation.
-- Use HAVING to filter on the result of aggregate functions.

-- Customers who have spent more than $5,000 total
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name  AS customer_name,
    c.segment,
    c.country,
    COUNT(DISTINCT o.order_id)          AS order_count,
    ROUND(SUM(oi.line_total), 2)        AS total_spent
FROM ECOMMERCE.RAW.CUSTOMERS c
INNER JOIN ECOMMERCE.RAW.ORDERS o
    ON c.customer_id = o.customer_id
INNER JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'     -- WHERE filters rows before aggregation
GROUP BY
    c.customer_id,
    c.first_name || ' ' || c.last_name,
    c.segment,
    c.country
HAVING SUM(oi.line_total) > 5000       -- HAVING filters groups after aggregation
ORDER BY total_spent DESC
LIMIT 20
;

-- Categories with more than 10,000 items sold
SELECT
    p.category,
    COUNT(oi.order_item_id)             AS items_sold,
    ROUND(SUM(oi.line_total), 2)        AS category_revenue
FROM ECOMMERCE.RAW.ORDER_ITEMS oi
INNER JOIN ECOMMERCE.RAW.PRODUCTS p
    ON oi.product_id = p.product_id
GROUP BY p.category
HAVING COUNT(oi.order_item_id) > 10000
ORDER BY items_sold DESC
;
-- HAVING COUNT(...) > 10000 filters out low-volume categories
-- This cannot be done in WHERE because COUNT is not yet calculated
-- at the WHERE stage

-- ── WHERE vs HAVING — when to use each ───────────────────────
-- WHERE  : filter on raw column values (before aggregation)
--          faster — eliminates rows early, less data to aggregate
-- HAVING : filter on aggregated values (after aggregation)
--          only use when the filter involves an aggregate function
--
-- Wrong (will error):
-- WHERE SUM(line_total) > 5000    ← cannot use aggregate in WHERE
--
-- Right:
-- HAVING SUM(line_total) > 5000   ← correct placement


-- ── Finding duplicates with GROUP BY + HAVING ─────────────────
-- A classic GROUP BY pattern: group on the columns that should
-- be unique, then use HAVING COUNT(*) > 1 to find duplicates.

-- Example 1: Single column — find duplicate customer emails
SELECT
    email,
    COUNT(*)                            AS occurrences
FROM ECOMMERCE.RAW.CUSTOMERS
GROUP BY email
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
;
-- If this returns rows → duplicate emails exist in the data
-- If it returns 0 rows → email is unique across all customers

-- Example 2: Multiple columns — find duplicate order items
-- (same order_id + product_id combination appearing more than once)
SELECT
    order_id,
    product_id,
    COUNT(*)                            AS occurrences
FROM ECOMMERCE.RAW.ORDER_ITEMS
GROUP BY
    order_id,
    product_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 10
;
-- GROUP BY on multiple columns checks uniqueness of the COMBINATION
-- A duplicate here means the same product appears twice on the same order
-- This pattern is essential for data quality checks before loading
-- into dimension or fact tables

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Subqueries and inline views
-- ══════════════════════════════════════════════════════════════
-- A subquery is a query nested inside another query.
-- In the FROM clause it acts as a virtual table (inline view).
-- In the WHERE clause it filters against a derived value.

-- ── Correlated vs non-correlated subqueries ───────────────────
--
-- NON-CORRELATED subquery:
--   · Independent of the outer query
--   · Runs ONCE, result is reused for every outer row
--   · Fast — Snowflake executes it once and caches the result
--
--   SELECT product_name, unit_price
--   FROM products
--   WHERE unit_price > (SELECT AVG(unit_price) FROM products)
--                        ↑ runs once, returns one value
--
-- CORRELATED subquery:
--   · References a column from the outer query
--   · Runs ONCE PER ROW in the outer query
--   · On a table with 1 million rows → executes 1 million times
--   · AVOID on large tables — severe performance impact
--
--   SELECT customer_id, order_total
--   FROM orders o
--   WHERE order_total > (SELECT AVG(order_total)
--                        FROM orders
--                        WHERE customer_id = o.customer_id)
--                                            ↑ references outer row
--                                              reruns for every order
--
-- How to spot a correlated subquery:
--   Copy the subquery and try to run it by itself.
--   · If it runs independently → non-correlated (runs once, safe)
--   · If it errors because it references a column from the
--     outer query → correlated (runs per row, avoid on large tables)
--
-- How to fix a correlated subquery on large tables:
--   Rewrite using a JOIN or CTE — covered in Sub-task 3.4.
--   Window functions (Sub-task 3.3) eliminate most cases
--   where correlated subqueries are tempting.
-- ─────────────────────────────────────────────────────────────

-- Inline view — aggregate first, then filter
SELECT
    customer_summary.customer_name,
    customer_summary.segment,
    customer_summary.total_spent,
    customer_summary.order_count
FROM (
    SELECT
        c.customer_id,
        c.first_name || ' ' || c.last_name  AS customer_name,
        c.segment,
        COUNT(DISTINCT o.order_id)          AS order_count,
        ROUND(SUM(oi.line_total), 2)        AS total_spent
    FROM ECOMMERCE.RAW.CUSTOMERS c
    INNER JOIN ECOMMERCE.RAW.ORDERS o
        ON c.customer_id = o.customer_id
    INNER JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        c.customer_id,
        c.first_name || ' ' || c.last_name,
        c.segment
) AS customer_summary
WHERE customer_summary.total_spent > 3000
ORDER BY customer_summary.total_spent DESC
LIMIT 10
;
-- The inner query builds the aggregation
-- The outer query filters on the aggregated result
-- This is equivalent to using HAVING — CTEs (Sub-task 3.4)
-- are a cleaner alternative to deeply nested subqueries

-- Scalar subquery — returns a single value used in comparison
SELECT
    product_id,
    product_name,
    unit_price,
    (SELECT ROUND(AVG(unit_price), 2)
     FROM ECOMMERCE.RAW.PRODUCTS
     WHERE is_active = TRUE)            AS avg_price,
    unit_price - (
        SELECT ROUND(AVG(unit_price), 2)
        FROM ECOMMERCE.RAW.PRODUCTS
        WHERE is_active = TRUE
    )                                   AS price_vs_avg
FROM ECOMMERCE.RAW.PRODUCTS
WHERE is_active = TRUE
ORDER BY price_vs_avg DESC
LIMIT 10
;
-- Note: scalar subqueries that repeat the same calculation
-- are better written as CTEs — covered in Sub-task 3.4

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Putting it together — a production analytics query
-- ══════════════════════════════════════════════════════════════
-- A realistic multi-table query combining joins, aggregations,
-- HAVING, and derived columns — the kind of query that powers
-- executive dashboards and business reports.

-- Supplier performance report
-- Revenue, return rate, and average rating per supplier
SELECT
    s.supplier_id,
    s.supplier_name,
    s.country                           AS supplier_country,
    COUNT(DISTINCT o.order_id)          AS total_orders,
    COUNT(DISTINCT oi.order_item_id)    AS total_items_sold,
    ROUND(SUM(oi.line_total), 2)        AS total_revenue,
    COUNT(DISTINCT r.return_id)         AS total_returns,
    ROUND(
        COUNT(DISTINCT r.return_id) * 100.0
        / NULLIF(COUNT(DISTINCT oi.order_item_id), 0)
    , 2)                                AS return_rate_pct,
    ROUND(AVG(pr.rating), 2)            AS avg_product_rating
FROM ECOMMERCE.RAW.SUPPLIERS s
INNER JOIN ECOMMERCE.RAW.PRODUCTS p
    ON s.supplier_id = p.supplier_id
INNER JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON p.product_id = oi.product_id
INNER JOIN ECOMMERCE.RAW.ORDERS o
    ON oi.order_id = o.order_id
LEFT JOIN ECOMMERCE.RAW.RETURNS r
    ON oi.order_item_id = r.order_item_id
LEFT JOIN ECOMMERCE.RAW.PRODUCT_REVIEWS pr
    ON p.product_id = pr.product_id
WHERE o.order_status = 'delivered'
  AND s.is_active    = TRUE
GROUP BY
    s.supplier_id,
    s.supplier_name,
    s.country
HAVING COUNT(DISTINCT oi.order_item_id) > 100   -- suppliers with meaningful volume
ORDER BY total_revenue DESC
LIMIT 20
;
-- INNER JOIN for required relationships (supplier → product → order)
-- LEFT JOIN for optional relationships (returns and reviews may not exist)
-- NULLIF prevents division by zero in return_rate_pct
-- HAVING filters out low-volume suppliers

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Write a query that finds the top 5 product categories
--    by return rate. Include:
--    · category
--    · total items sold
--    · total returns
--    · return rate percentage
--    · average refund amount
--    Only include categories with more than 500 items sold.
--    Order by return rate descending.
--
-- 2. Find customers who placed orders in 2021 but NOT in 2022.
--    Use a LEFT JOIN with IS NULL pattern (anti-join).
--    Include customer name, country, segment, and their
--    total 2021 order value.
--
-- 3. Build a monthly cohort table showing for each month:
--    · new customers (first order in that month)
--    · returning customers (had orders before that month)
--    · revenue from each group
--    Hint: Use a subquery to find each customer's first order date.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if my JOIN produces more rows than expected?
-- A: You likely have a fan-out — one row on the left matches
--    multiple rows on the right. Check with:
--    SELECT order_id, COUNT(*) FROM ORDER_ITEMS GROUP BY order_id
--    to see how many items per order. When joining ORDERS to
--    ORDER_ITEMS each order row fans out to N item rows.
--    Use COUNT(DISTINCT) on the driving table's key to verify.
--
-- Q: What if my JOIN produces fewer rows than expected?
-- A: You likely have NULLs in the join key or values that do
--    not match between tables. Check with:
--    SELECT * FROM left_table WHERE join_key IS NULL
--    Also verify data types match — joining INTEGER to VARCHAR
--    may silently fail or produce unexpected results.
--
-- Q: What is the difference between WHERE and ON in a LEFT JOIN?
-- A: In a LEFT JOIN, conditions in the ON clause filter the
--    right table BEFORE joining — left rows with no match still
--    appear with NULLs. Conditions in the WHERE clause filter
--    AFTER joining — this turns a LEFT JOIN into an INNER JOIN
--    if you filter on a right-table column.
--    Use ON for right-table filters you want to preserve NULLs.
--    Use WHERE for filters that should exclude non-matching rows.
--
-- Q: What if I need to join more than 5 tables?
-- A: Snowflake handles large multi-table joins well. The key
--    is to filter early — apply WHERE conditions that reduce
--    row counts before joining large tables. Use CTEs
--    (Sub-task 3.4) to break complex joins into readable steps.
--    Check Query Profile (Goal 5) to identify which join is
--    the bottleneck.
--
-- Q: What is the Oracle equivalent of Snowflake join syntax?
-- A: Identical — both use ANSI SQL JOIN syntax.
--    The old Oracle comma syntax (FROM a, b WHERE a.id = b.id)
--    works in Snowflake but avoid it. Explicit JOIN syntax is
--    unambiguous, easier to read, and safer when adding tables.