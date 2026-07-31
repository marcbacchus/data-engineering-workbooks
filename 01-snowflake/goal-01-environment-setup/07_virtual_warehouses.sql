-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 1 : Set Up Your Environment
-- Sub-task 1.7 : Configure virtual warehouses
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30 minutes
-- Warehouse size   : X-Small (COMPUTE_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : 06_editions.sql completed
-- COF-C03 domain   : Domain 1.0 — Snowflake AI Data Cloud Features & Architecture (31%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Virtual warehouses are the compute layer of Snowflake.
--   Every query you run, every COPY INTO you execute, every
--   transformation you apply — all of it runs on a warehouse.
--
--   Warehouses are also your primary cost driver. A warehouse
--   left running overnight with no queries is pure waste.
--   A warehouse sized too small for your workload means slow
--   queries and frustrated users. Sized too large means
--   unnecessary spend.
--
--   This sub-task teaches you to create, configure, size,
--   monitor, and manage warehouses deliberately — not just
--   accept the defaults and hope for the best.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: VIRTUAL WAREHOUSE FUNDAMENTALS
-- ══════════════════════════════════════════════════════════════
--
-- SIZING
--   Warehouses are sized from X-Small to 6X-Large.
--   Each size up roughly doubles the compute nodes and
--   doubles the credit consumption per hour.
--
--   Size        Credits/hour    Typical use
--   ─────────── ───────────     ──────────────────────────────
--   X-Small          1          Development, light queries
--   Small            2          Small ETL, moderate queries
--   Medium           4          Production ETL, dashboards
--   Large            8          Heavy transformation, bulk loads
--   X-Large         16          Very large datasets, complex ML
--   2X-Large        32          Extreme workloads
--   3X-Large        64          Rare — specialised use cases
--   4X-Large       128          Rare — specialised use cases
--
--   Rule of thumb: start small and scale up based on Query
--   Profile results. Do not guess — measure first.
--
-- AUTO-SUSPEND
--   Warehouses can suspend automatically after a period of
--   inactivity. While suspended, zero credits are consumed.
--   The default is 600 seconds (10 minutes). For development
--   warehouses, 60 seconds is more cost-efficient.
--   For production warehouses serving dashboards, a longer
--   suspend time (300–600 seconds) avoids cold-start latency.
--
-- AUTO-RESUME
--   When AUTO_RESUME = TRUE, a suspended warehouse restarts
--   automatically when a query is submitted. The cold-start
--   takes 2–5 seconds typically. Almost always set to TRUE
--   in production — the alternative is manually resuming
--   before every query which is impractical.
--
-- MULTI-CLUSTER WAREHOUSES (Enterprise edition)
--   A single warehouse cluster handles one query at a time
--   (or a small queue). When many users submit queries
--   simultaneously, they queue behind each other.
--   Multi-cluster warehouses spin up additional clusters
--   automatically to handle concurrent demand — horizontal
--   scaling for concurrency, not just query speed.
--   Use for: BI tools, dashboards, high-concurrency workloads.
--
-- WAREHOUSE TYPES
--   Standard     — general purpose, all workloads
--   Snowpark-optimised — memory-optimised for Python/ML workloads
--                        (16x memory per node vs Standard)
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'COMPUTE_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Inspect your existing warehouse
-- ══════════════════════════════════════════════════════════════
-- Before creating new warehouses, understand what you already have.

SHOW WAREHOUSES;

SELECT
    "name"              AS warehouse_name,
    "size"              AS warehouse_size,
    "state"             AS current_state,
    "type"              AS warehouse_type,
    "auto_suspend"      AS auto_suspend_seconds,
    "auto_resume"       AS auto_resume_enabled,
    "min_cluster_count" AS min_clusters,
    "max_cluster_count" AS max_clusters,
    "scaling_policy"    AS scaling_policy
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;

-- Key things to note about COMPUTE_WH:
-- · size: what it is currently set to
-- · auto_suspend: how long before it suspends (seconds)
-- · auto_resume: should be true for normal operation
-- · min/max_cluster_count: 1/1 means single-cluster (Standard)
--   >1 max means multi-cluster is configured (Enterprise)

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create a dedicated workbook warehouse
-- ══════════════════════════════════════════════════════════════
-- Best practice: create separate warehouses for separate workloads.
-- We create a dedicated warehouse for this workbook so exercises
-- do not interfere with other workloads on COMPUTE_WH.

CREATE WAREHOUSE IF NOT EXISTS WORKBOOK_WH
    WAREHOUSE_SIZE      = 'X-SMALL'
    AUTO_SUSPEND        = 300         -- 5 minutes, enough time to observe state
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Dedicated warehouse for Data Engineering Workbook exercises'
;

-- Switch to the new warehouse
USE WAREHOUSE WORKBOOK_WH;

-- Verify it was created and is suspended
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

SELECT
    "name"              AS warehouse_name,
    "size"              AS warehouse_size,
    "state"             AS current_state,
    "auto_suspend"      AS auto_suspend_seconds,
    "auto_resume"       AS auto_resume_enabled
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- ── PROVING AUTO_RESUME ───────────────────────────────────────
-- Three things can prevent a warehouse from resuming:
--   1. Query resolved by cloud services (SELECT 1+1)
--   2. Query resolved by metadata cache (SELECT COUNT(*))
--   3. Query resolved by result cache (same query run before)
--
-- To guarantee warehouse compute is required, add
-- CURRENT_TIMESTAMP() — makes every execution unique,
-- bypasses result cache, forces actual compute:

SELECT SUM(L_EXTENDEDPRICE), CURRENT_TIMESTAMP()
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM;

-- Now check state immediately:
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

-- state = STARTED confirms AUTO_RESUME worked.
-- Always read state from SHOW raw output directly —
-- not from RESULT_SCAN which may run after auto-suspend.

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Modify warehouse configuration
-- ══════════════════════════════════════════════════════════════
-- ALTER WAREHOUSE lets you change any warehouse property
-- without dropping and recreating it.

-- Increase auto-suspend to 120 seconds
ALTER WAREHOUSE WORKBOOK_WH
    SET AUTO_SUSPEND = 120
;

-- Add a comment update
ALTER WAREHOUSE WORKBOOK_WH
    SET COMMENT = 'Dedicated warehouse for workbook exercises — X-Small, 120s auto-suspend'
;

-- Verify changes
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

SELECT
    "name"          AS warehouse_name,
    "auto_suspend"  AS auto_suspend_seconds,
    "comment"       AS description
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Manually control warehouse state
-- ══════════════════════════════════════════════════════════════
-- You can suspend and resume warehouses manually at any time.
-- Useful for cost control during off-hours or maintenance.

-- Suspend the warehouse manually
ALTER WAREHOUSE WORKBOOK_WH SUSPEND;

-- Verify it suspended
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

SELECT "name", "state"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- state should show SUSPENDED

-- Resume it manually
ALTER WAREHOUSE WORKBOOK_WH RESUME;

-- Verify it resumed
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

SELECT "name", "state"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- state should show STARTED

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Resize a warehouse
-- ══════════════════════════════════════════════════════════════
-- Resizing takes effect immediately on the next query.
-- You can resize up or down at any time — no data movement,
-- no downtime, no reconfiguration required.
-- This is one of the most powerful operational capabilities
-- in Snowflake — resize for a heavy load, then resize back.

-- Scale up to Small for a heavier workload
ALTER WAREHOUSE WORKBOOK_WH
    SET WAREHOUSE_SIZE = 'SMALL'
;

SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

SELECT "name", "size", "state"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- size should now show SMALL

-- Scale back down to X-Small
ALTER WAREHOUSE WORKBOOK_WH
    SET WAREHOUSE_SIZE = 'X-SMALL'
;

SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

SELECT "name", "size"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- size should now show X-SMALL again

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Configure a multi-cluster warehouse (Enterprise)
-- ══════════════════════════════════════════════════════════════
-- Multi-cluster warehouses handle concurrency by spinning up
-- additional clusters when demand exceeds a single cluster.
-- Requires Enterprise edition.

-- Create a multi-cluster warehouse
CREATE WAREHOUSE IF NOT EXISTS WORKBOOK_MC_WH
    WAREHOUSE_SIZE      = 'X-SMALL'
    MIN_CLUSTER_COUNT   = 1           -- minimum clusters always running
    MAX_CLUSTER_COUNT   = 3           -- maximum clusters under peak load
    SCALING_POLICY      = 'STANDARD'  -- STANDARD or ECONOMY
    AUTO_SUSPEND        = 120
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Multi-cluster warehouse demo — Enterprise edition'
;

SHOW WAREHOUSES LIKE 'WORKBOOK_MC_WH';

SELECT
    "name"              AS warehouse_name,
    "size"              AS warehouse_size,
    "min_cluster_count" AS min_clusters,
    "max_cluster_count" AS max_clusters,
    "scaling_policy"    AS scaling_policy,
    "state"             AS current_state
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- min_cluster_count: 1
-- max_cluster_count: 3
-- This warehouse will scale from 1 to 3 clusters automatically
-- based on query queue depth

-- SCALING POLICY options:
-- STANDARD — adds clusters as soon as queuing is detected
--            optimises for query speed over cost
-- ECONOMY  — waits longer before adding clusters
--            optimises for cost over query speed
-- For most production BI workloads: STANDARD
-- For batch workloads where latency is acceptable: ECONOMY

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Monitor warehouse credit consumption
-- ══════════════════════════════════════════════════════════════
-- Understanding credit consumption is essential for cost control.
-- INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY shows credit
-- usage per warehouse per hour for the last 14 days.

SELECT
    WAREHOUSE_NAME,
    START_TIME,
    END_TIME,
    CREDITS_USED,
    CREDITS_USED_COMPUTE,
    CREDITS_USED_CLOUD_SERVICES
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
    DATEADD('day', -1, CURRENT_TIMESTAMP()),
    CURRENT_TIMESTAMP()
))
ORDER BY START_TIME DESC
;
-- CREDITS_USED_COMPUTE      — warehouse compute credits
-- CREDITS_USED_CLOUD_SERVICES — metadata/cloud services credits
-- Total cost = credits × your contracted credit price
-- On-demand pricing: ~$2–4 per credit depending on cloud/region

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Switch warehouses within a session
-- ══════════════════════════════════════════════════════════════
-- You can switch between warehouses mid-session at any time.
-- The next query after USE WAREHOUSE runs on the new warehouse.
-- This is useful for routing different workload types to
-- appropriately sized warehouses.

-- Switch to the multi-cluster warehouse
USE WAREHOUSE WORKBOOK_MC_WH;
SELECT CURRENT_WAREHOUSE();
-- Shows WORKBOOK_MC_WH

-- Switch back to the standard workbook warehouse
USE WAREHOUSE WORKBOOK_WH;
SELECT CURRENT_WAREHOUSE();
-- Shows WORKBOOK_WH

-- Switch back to the default COMPUTE_WH
USE WAREHOUSE IDENTIFIER($my_warehouse);
SELECT CURRENT_WAREHOUSE();
-- Shows COMPUTE_WH

-- Note: switching warehouses never affects your active database
-- or schema — only the compute changes
SELECT
    CURRENT_WAREHOUSE()     AS active_warehouse,
    CURRENT_DATABASE()      AS active_database,
    CURRENT_SCHEMA()        AS active_schema
;

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- Drop the demo warehouses created in this sub-task.
-- NOTE: Keep COMPUTE_WH — it is your default warehouse.
-- We will use WORKBOOK_WH going forward in this workbook
-- so only drop it if you are resetting completely.

-- Drop the multi-cluster demo warehouse (not needed going forward)
DROP WAREHOUSE IF EXISTS WORKBOOK_MC_WH;

-- Optional: drop WORKBOOK_WH if resetting
-- We recommend KEEPING it for the rest of the workbook
-- DROP WAREHOUSE IF EXISTS WORKBOOK_WH;

-- Verify
SHOW WAREHOUSES;

SELECT "name", "size", "state"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;
-- Should show COMPUTE_WH and WORKBOOK_WH
-- WORKBOOK_MC_WH should be gone

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a warehouse called ANALYTICS_WH sized Medium
--    with AUTO_SUSPEND = 300 and AUTO_RESUME = TRUE.
--    This simulates a warehouse for a BI/dashboard workload
--    where slightly longer suspend time reduces cold-start
--    latency for dashboard users.
--    After creating it, alter the auto-suspend to 180 seconds.
--    Verify the change with SHOW WAREHOUSES.
--
-- 2. Run the credit consumption query in Step 7.
--    How many credits has COMPUTE_WH consumed in the last 24 hours?
--    Multiply by your estimated credit price ($3 as a rough estimate)
--    to get an approximate cost for today's work.
--    Is the cost what you expected?
--
-- 3. Resize WORKBOOK_WH to Large, run a simple query
--    (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM),
--    then resize back to X-Small.
--    Check the credit consumption in Step 7 after resizing.
--    Do you see the difference in credits between X-Small and Large?
--
-- 4. What is the credit cost per hour of a 3-cluster
--    X-Small multi-cluster warehouse running at full capacity?
--    (Hint: each cluster = 1 credit/hour for X-Small)

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I forget to set AUTO_SUSPEND and leave a Large
--    warehouse running overnight?
-- A: At 8 credits/hour × 8 hours = 64 credits overnight.
--    At $3/credit that is ~$192 for one idle night.
--    Resource monitors (Goal 9) can cap this automatically.
--    Always set AUTO_SUSPEND — there is no good reason not to.
--
-- Q: What if my queries are slow — should I always size up?
-- A: Not necessarily. Check the Query Profile first (Goal 5).
--    Slow queries are often caused by poor clustering, missing
--    filters scanning too many partitions, or inefficient SQL —
--    not insufficient warehouse size. Sizing up an inefficient
--    query just runs a bad query faster and costs more credits.
--    Fix the query first, then size if still needed.
--
-- Q: What if two heavy queries run at the same time on
--    a single-cluster warehouse?
-- A: They queue — the second waits for the first to complete.
--    On a multi-cluster warehouse a second cluster would spin up
--    to run both simultaneously. For high-concurrency workloads
--    (many users, BI tools) multi-cluster is the solution.
--
-- Q: What if I need Python or ML workloads to run faster?
-- A: Consider a Snowpark-optimised warehouse. It has 16x the
--    memory per node compared to a Standard warehouse — designed
--    for memory-intensive Python UDFs and ML inference workloads.
--    Create with: CREATE WAREHOUSE ... WAREHOUSE_TYPE = 'SNOWPARK-OPTIMIZED'
--
-- Q: What if I want to prevent a specific warehouse from
--    consuming more than a set number of credits per day?
-- A: Use a resource monitor — covered in Goal 9 Sub-task 9.5.
--    Resource monitors can notify, suspend, or immediately
--    suspend a warehouse when it hits a credit threshold.
--    Essential for production cost governance.
--
-- Q: Can two warehouses read the same data simultaneously?
-- A: Yes — this is one of Snowflake's core architectural
--    advantages. Multiple warehouses read from the same shared
--    storage layer with no resource contention between them.
--    A heavy ETL job on WORKBOOK_WH does not slow down
--    dashboard queries on ANALYTICS_WH. They are fully isolated.
