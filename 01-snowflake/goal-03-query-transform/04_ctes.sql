-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 3  : Query and Transform Data
-- Sub-task 3.4 : CTEs and query organisation
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : 03_window_functions.sql completed
-- COF-C03 domain   : Domain 5 — Data Transformations (17%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Complex queries get hard to read fast. A 10-table join with
--   subqueries nested three levels deep is technically correct
--   but practically unmaintainable. Six months later nobody —
--   including you — knows what it does.
--
--   CTEs (Common Table Expressions) solve this by letting you
--   name and sequence the building blocks of a query. Instead
--   of one giant query, you write a series of named steps that
--   build on each other. The result is SQL that reads like
--   documentation — each step has a name, a purpose, and is
--   independently understandable.
--
--   This sub-task also covers recursive CTEs — for hierarchical
--   data like org charts, category trees, and bill of materials.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: WHAT IS A CTE?
-- ══════════════════════════════════════════════════════════════
--
-- A CTE is a named temporary result set defined at the top of
-- a query using the WITH clause. It exists only for the duration
-- of that query — not a permanent object, not a temp table.
--
-- Basic syntax:
--   WITH cte_name AS (
--       SELECT ...
--   )
--   SELECT * FROM cte_name;
--
-- Multiple CTEs:
--   WITH
--   first_cte AS (SELECT ...),
--   second_cte AS (SELECT ... FROM first_cte),
--   third_cte AS (SELECT ... FROM first_cte, second_cte)
--   SELECT * FROM third_cte;
--
-- KEY PROPERTIES:
--   · Named and reusable within the same query
--   · Can reference earlier CTEs in the same WITH clause
--   · Executed lazily — only when referenced in the final SELECT
--   · Not persisted — gone when the query ends
--   · Supported in SELECT, INSERT, UPDATE, DELETE, MERGE
--
-- CTE vs SUBQUERY:
--   Subquery: anonymous, inline, can only be used once
--   CTE: named, defined once, reusable multiple times in the query
--
-- CTE vs TEMP TABLE:
--   Temp table: persists for the session, needs CREATE/DROP
--   CTE: exists only for one query, zero cleanup required
--   Use temp tables only when the intermediate result is very
--   large and reused many times — CTEs are almost always cleaner
--
-- CTE vs VIEW:
--   View: a saved query, persists as a database object
--   CTE: single-query scope, no object created
--   Use views when multiple queries need the same logic.
--   Use CTEs when the logic is specific to one query.
--
-- Oracle equivalent:
--   Oracle supports the same WITH ... AS syntax (since 9i).
--   Syntax is identical — CTEs are fully portable between
--   Oracle and Snowflake.
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
-- STEP 1: Basic CTE — replace a subquery with a named step
-- ══════════════════════════════════════════════════════════════
-- Before CTEs: nested subquery — hard to read
SELECT
    customer_id,
    total_spent,
    order_count
FROM (
    SELECT
        customer_id,
        ROUND(SUM(order_total), 2)  AS total_spent,
        COUNT(order_id)             AS order_count
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
    GROUP BY customer_id
) customer_summary
WHERE total_spent > 1000
ORDER BY total_spent DESC
LIMIT 10
;

-- After CTEs: named step — reads like documentation
WITH customer_summary AS (
    -- Step 1: aggregate each customer's delivered orders
    SELECT
        customer_id,
        ROUND(SUM(order_total), 2)  AS total_spent,
        COUNT(order_id)             AS order_count
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
    GROUP BY customer_id
)
SELECT
    customer_id,
    total_spent,
    order_count
FROM customer_summary
WHERE total_spent > 1000
ORDER BY total_spent DESC
LIMIT 10
;
-- Same result — but the CTE version is self-documenting.
-- The name "customer_summary" tells you exactly what it contains.
-- The final SELECT is clean — one table, simple filter.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Chained CTEs — build complexity step by step
-- ══════════════════════════════════════════════════════════════
-- Multiple CTEs build on each other like named steps in a pipeline.
-- Each CTE can reference any CTE defined before it.
-- The final SELECT brings everything together.

WITH
-- Step 1: customer order summary
customer_orders AS (
    SELECT
        customer_id,
        COUNT(order_id)             AS order_count,
        ROUND(SUM(order_total), 2)  AS total_spent,
        MIN(created_at)             AS first_order_date,
        MAX(created_at)             AS last_order_date
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
    GROUP BY customer_id
),

-- Step 2: classify customers by spend tier
customer_segments AS (
    SELECT
        customer_id,
        order_count,
        total_spent,
        first_order_date,
        last_order_date,
        CASE
            WHEN total_spent >= 5000 THEN 'platinum'
            WHEN total_spent >= 2000 THEN 'gold'
            WHEN total_spent >= 500  THEN 'silver'
            ELSE                          'bronze'
        END                         AS spend_tier,
        DATEDIFF('day', first_order_date, last_order_date)
                                    AS customer_lifespan_days
    FROM customer_orders
),

-- Step 3: join with customer profile data
customer_profile AS (
    SELECT
        cs.customer_id,
        c.first_name || ' ' || c.last_name AS customer_name,
        c.country,
        c.segment                   AS crm_segment,
        cs.spend_tier,
        cs.order_count,
        cs.total_spent,
        cs.customer_lifespan_days
    FROM customer_segments cs
    INNER JOIN ECOMMERCE.RAW.CUSTOMERS c
        ON cs.customer_id = c.customer_id
)

-- Final SELECT: filter and present
SELECT
    customer_name,
    country,
    crm_segment,
    spend_tier,
    order_count,
    total_spent,
    customer_lifespan_days
FROM customer_profile
WHERE spend_tier IN ('platinum', 'gold')
ORDER BY total_spent DESC
LIMIT 20
;
-- Read this query top to bottom like a recipe:
-- 1. Aggregate each customer's orders
-- 2. Classify by spend tier
-- 3. Enrich with profile data
-- 4. Filter to top tiers and present
-- Each step has one job. No nesting. No mystery.

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Reusing a CTE multiple times
-- ══════════════════════════════════════════════════════════════
-- One of the biggest advantages of CTEs over subqueries:
-- define once, reference multiple times in the same query.
-- With subqueries you would repeat the same code twice —
-- duplicating logic and the risk of inconsistency.

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', created_at) AS order_month,
        ROUND(SUM(order_total), 2)      AS revenue
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
    GROUP BY DATE_TRUNC('month', created_at)
)

-- Use the same CTE twice in the final SELECT
SELECT
    m.order_month,
    m.revenue                           AS monthly_revenue,
    -- Reference monthly_revenue CTE a second time via window function
    ROUND(AVG(m.revenue) OVER (
        ORDER BY m.order_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2)                               AS revenue_3mo_avg,
    ROUND(m.revenue * 100.0
        / SUM(m.revenue) OVER ()
    , 2)                                AS pct_of_annual
FROM monthly_revenue m
ORDER BY m.order_month
;
-- monthly_revenue CTE defined once, used in two window calculations
-- Without the CTE you would repeat the entire aggregation subquery twice

-- ══════════════════════════════════════════════════════════════
-- STEP 4: CTEs replacing correlated subqueries
-- ══════════════════════════════════════════════════════════════
-- In Sub-task 3.2 we learned that correlated subqueries run
-- once per row — extremely expensive on large tables.
-- CTEs are the clean fix: aggregate once, join the result.

-- BEFORE: correlated subquery (runs once per order row — avoid)
-- SELECT
--     order_id,
--     customer_id,
--     order_total,
--     (SELECT AVG(order_total)
--      FROM ECOMMERCE.RAW.ORDERS o2
--      WHERE o2.customer_id = o1.customer_id) AS customer_avg
-- FROM ECOMMERCE.RAW.ORDERS o1
-- WHERE order_status = 'delivered';
-- ↑ Correlated: references o1.customer_id from the outer query
--   Runs the subquery for EVERY row — millions of executions

-- AFTER: CTE aggregates once, join once (fast)
WITH customer_avg_order AS (
    -- Aggregate once across all customers
    SELECT
        customer_id,
        ROUND(AVG(order_total), 2)      AS avg_order_value
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = 'delivered'
    GROUP BY customer_id
)
SELECT
    o.order_id,
    o.customer_id,
    o.order_total,
    ca.avg_order_value                  AS customer_avg,
    ROUND(o.order_total - ca.avg_order_value, 2) AS vs_customer_avg
FROM ECOMMERCE.RAW.ORDERS o
INNER JOIN customer_avg_order ca
    ON o.customer_id = ca.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_total > ca.avg_order_value * 1.5
  -- orders that are 50% above the customer's own average
ORDER BY vs_customer_avg DESC
LIMIT 20
;
-- customer_avg_order executes ONCE and is joined.
-- This replaces a correlated subquery that would execute
-- millions of times. Same result, dramatically faster.

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Recursive CTEs — hierarchical data
-- ══════════════════════════════════════════════════════════════
-- A recursive CTE references itself to traverse hierarchical data.
-- Classic use cases: org charts, category trees, bill of materials.
--
-- Structure:
--   WITH RECURSIVE cte AS (
--       -- Anchor: the starting point (root nodes)
--       SELECT ...
--       UNION ALL
--       -- Recursive: join cte to itself to get next level
--       SELECT ... FROM table JOIN cte ON parent = cte.id
--   )
--
-- Our e-commerce dataset does not have a natural hierarchy,
-- so we build a small product category hierarchy inline
-- to demonstrate the pattern clearly.

-- Build a sample category hierarchy
WITH RECURSIVE category_tree AS (
    -- Anchor: top-level categories (no parent)
    SELECT
        category_id,
        category_name,
        parent_id,
        0                               AS depth,
        category_name                   AS path
    FROM (VALUES
        (1, 'Electronics',       NULL),
        (2, 'Computers',         1),
        (3, 'Laptops',           2),
        (4, 'Gaming Laptops',    3),
        (5, 'Phones',            2),
        (6, 'Clothing',          NULL),
        (7, 'Mens',              6),
        (8,'Womens',             6)
    ) AS categories(category_id, category_name, parent_id)
--  ↑ table alias  ↑ column names for each position in VALUES 
    WHERE parent_id IS NULL             -- root nodes only

    UNION ALL

    -- Recursive: join back to get child nodes
    SELECT
        c.category_id,
        c.category_name,
        c.parent_id,
        ct.depth + 1,
        ct.path || ' > ' || c.category_name
    FROM (VALUES
        (1, 'Electronics',       NULL),
        (2, 'Computers',         1),
        (3, 'Laptops',           2),
        (4, 'Gaming Laptops',    3),
        (5, 'Phones',            2),
        (6, 'Clothing',          NULL),
        (7, 'Mens',              6),
        (8, 'Womens',            6)
    ) AS c(category_id, category_name, parent_id)
 --  ↑ table alias  ↑ column names for each position in VALUES    
    INNER JOIN category_tree ct
        ON c.parent_id = ct.category_id
)
SELECT
    REPEAT('  ', depth) || category_name AS indented_name,
    depth,
    path
FROM category_tree
ORDER BY path
;
-- Output shows the full hierarchy with indentation:
-- Electronics
--   Computers
--     Laptops
--       Gaming Laptops
--     Phones
-- Clothing
--   Mens
--   Womens
--
-- The path column shows the full breadcrumb for each node.
-- Real-world use: traverse any parent-child structure where
-- depth is unknown at query time.

-- ══════════════════════════════════════════════════════════════
-- STEP 6: CTEs for data quality checks
-- ══════════════════════════════════════════════════════════════
-- CTEs make data quality queries readable and auditable.
-- Define each check as a named CTE, union the results.

WITH
-- Check 1: orders with no matching customer
orphaned_orders AS (
    SELECT
        'orphaned_order'            AS issue_type,
        o.order_id::VARCHAR         AS record_id,
        'order_id=' || o.order_id  AS detail
    FROM ECOMMERCE.RAW.ORDERS o
    LEFT JOIN ECOMMERCE.RAW.CUSTOMERS c
        ON o.customer_id = c.customer_id
    WHERE c.customer_id IS NULL
),

-- Check 2: order items with no matching order
orphaned_order_items AS (
    SELECT
        'orphaned_order_item'           AS issue_type,
        oi.order_item_id::VARCHAR       AS record_id,
        'order_item_id=' || oi.order_item_id AS detail
    FROM ECOMMERCE.RAW.ORDER_ITEMS oi
    LEFT JOIN ECOMMERCE.RAW.ORDERS o
        ON oi.order_id = o.order_id
    WHERE o.order_id IS NULL
),

-- Check 3: products with negative prices
negative_prices AS (
    SELECT
        'negative_price'                AS issue_type,
        product_id::VARCHAR             AS record_id,
        'product_id=' || product_id || ' price=' || unit_price AS detail
    FROM ECOMMERCE.RAW.PRODUCTS
    WHERE unit_price < 0
       OR cost_price < 0
),

-- Check 4: returns with no matching order item
orphaned_returns AS (
    SELECT
        'orphaned_return'               AS issue_type,
        r.return_id::VARCHAR            AS record_id,
        'return_id=' || r.return_id    AS detail
    FROM ECOMMERCE.RAW.RETURNS r
    LEFT JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
        ON r.order_item_id = oi.order_item_id
    WHERE oi.order_item_id IS NULL
)

-- Combine all checks into one data quality report
SELECT issue_type, COUNT(*) AS issue_count
FROM (
    SELECT * FROM orphaned_orders
    UNION ALL
    SELECT * FROM orphaned_order_items
    UNION ALL
    SELECT * FROM negative_prices
    UNION ALL
    SELECT * FROM orphaned_returns
) all_issues
GROUP BY issue_type
ORDER BY issue_count DESC
;
-- Each issue type has its own named CTE — easy to add, remove,
-- or debug individual checks without touching the others.
-- Zero rows = clean dataset. Any rows = data quality issues to investigate.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Rewrite this nested subquery using CTEs:
--    SELECT product_id, product_name, category, unit_price
--    FROM (
--        SELECT p.*, AVG(r.rating) AS avg_rating
--        FROM products p
--        LEFT JOIN product_reviews r ON p.product_id = r.product_id
--        GROUP BY p.product_id, p.product_name, p.category,
--                 p.unit_price, p.cost_price, p.weight_kg,
--                 p.is_active, p.created_at, p.supplier_id
--    ) rated_products
--    WHERE avg_rating >= 4.0
--    ORDER BY unit_price DESC;
--    How many CTEs did you need? Is the result more readable?
--
-- 2. Using chained CTEs, build a supplier scorecard:
--    CTE 1: total revenue per supplier
--    CTE 2: average product rating per supplier
--    CTE 3: return rate per supplier
--    Final: join all three and rank suppliers by overall score
--    (you define what "overall score" means)
--
-- 3. Write a data quality CTE report that checks:
--    · Customers with no orders
--    · Products with no reviews
--    · Orders where delivery_date < shipping_date
--    Which check finds the most issues in this dataset?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: Does Snowflake materialise CTEs or re-execute them?
-- A: Snowflake may or may not materialise a CTE depending on
--    the query plan. If a CTE is referenced once, Snowflake
--    typically inlines it (treats it like a subquery).
--    If referenced multiple times, it may or may not materialise.
--    For large CTEs referenced many times, consider a temporary
--    table to guarantee materialisation and avoid re-execution.
--    Check Query Profile (Goal 5) to see how Snowflake treated
--    your CTE in any given query.
--
-- Q: What is the maximum recursion depth for recursive CTEs?
-- A: Snowflake defaults to 100 iterations. Increase with:
--    ALTER SESSION SET RECURSIVE_CTE_MAX_DEPTH = 200;
--    For very deep hierarchies check your data for cycles —
--    a parent pointing to a child that points back to the parent
--    causes infinite recursion and hits the limit.
--
-- Q: Can I use a CTE in an INSERT, UPDATE, or DELETE?
-- A: Yes — CTEs work with all DML statements:
--    WITH flagged_orders AS (SELECT order_id FROM orders WHERE ...)
--    DELETE FROM orders WHERE order_id IN (SELECT order_id FROM flagged_orders);
--    This makes complex DML readable by separating the filter
--    logic (CTE) from the DML action (DELETE/UPDATE).
--
-- Q: When should I use a CTE vs a view?
-- A: CTE  → logic used in one query, no need to persist
--    View  → logic reused across many queries or by multiple users
--    If you find yourself copying the same CTE into multiple
--    queries, that CTE wants to be a view. Create it once,
--    reference it by name everywhere.
--
-- Q: What is the Oracle equivalent?
-- A: Oracle supports the same WITH ... AS syntax.
--    Recursive CTEs (WITH RECURSIVE) require the RECURSIVE
--    keyword in some Oracle versions — Snowflake does not
--    require it (WITH alone works for recursive CTEs).
--    Otherwise the syntax is identical and fully portable.
