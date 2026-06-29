-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 1 : Set Up Your Environment
-- Sub-task 1.1 : Understand the Snowflake architecture
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~20 minutes
-- Warehouse size   : X-Small (COMPUTE_WH)
-- Starting point   : Fresh Snowflake session, no database selected
-- COF-C03 domain   : Domain 1 — Architecture & Features (25%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Before writing a single query, you need a mental model of what
--   Snowflake actually is. Most platform problems — slow queries,
--   unexpected costs, confusing behaviour — trace back to a gap in
--   this mental model. This sub-task builds that foundation.
--
--   If you are coming from Oracle or SQL Server: the biggest shift
--   is that storage and compute are completely separate. There is no
--   concept of a single database server that owns both. This changes
--   how you think about scaling, cost, and concurrency entirely.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE THREE-LAYER ARCHITECTURE
-- ══════════════════════════════════════════════════════════════
--
--  ┌─────────────────────────────────────────────────────────┐
--  │                  CLOUD SERVICES LAYER                   │
--  │  Authentication · Query parsing · Optimisation          │
--  │  Metadata · Transaction management · Security           │
--  │  Always on · Shared · No user configuration needed      │
--  └─────────────────────────────────────────────────────────┘
--                            │
--  ┌─────────────────────────────────────────────────────────┐
--  │                    COMPUTE LAYER                        │
--  │  Virtual Warehouses (MPP clusters you create/control)   │
--  │  Each warehouse is independent — no resource fighting   │
--  │  Billed per second · Auto-suspend when idle             │
--  └─────────────────────────────────────────────────────────┘
--                            │
--  ┌─────────────────────────────────────────────────────────┐
--  │                    STORAGE LAYER                        │
--  │  All data stored in Snowflake-managed cloud storage     │
--  │  Columnar format · Compressed · Micro-partitioned       │
--  │  Shared by ALL virtual warehouses simultaneously        │
--  └─────────────────────────────────────────────────────────┘
--
-- LAYER 1 — STORAGE
--   Snowflake stores all data in its own internal format on cloud
--   object storage (S3, Azure Blob, or GCS depending on your cloud).
--   You never access this directly. Data is stored in compressed,
--   columnar micro-partitions — typically 50–500 MB each before
--   compression. Snowflake automatically handles organisation,
--   compression, and statistics. You do not manage tablespaces,
--   extents, or data files. There is no concept of a DBA manually
--   reorganising storage.
--
--   Key point: storage is SHARED. Every virtual warehouse reads
--   from the same underlying data. This means you can run 10
--   different workloads against the same tables simultaneously
--   without copying data.
--
-- LAYER 2 — COMPUTE (Virtual Warehouses)
--   This is what actually runs your queries. A virtual warehouse is
--   an MPP (massively parallel processing) cluster of compute nodes
--   that Snowflake provisions on demand. You choose the size. It
--   starts, runs your query, and can suspend automatically when idle.
--   You are only billed while it is running.
--
--   Key point: compute is ISOLATED. Two warehouses running against
--   the same data do not compete for resources. A heavy ETL job on
--   one warehouse does not slow down your analysts on another.
--   This is one of the most significant architectural differences
--   from traditional data warehouses.
--
-- LAYER 3 — CLOUD SERVICES
--   This is Snowflake's "brain" — always running, always available,
--   shared across all users. It handles:
--     · Authentication and authorisation
--     · Query parsing and optimisation
--     · Transaction management
--     · Metadata management (table definitions, statistics, etc.)
--     · Infrastructure management (provisioning warehouses, etc.)
--
--   Cloud services has its own credit consumption model. Most
--   operations are free (covered by the 10% of daily compute usage
--   allowance). You only pay extra if cloud services usage exceeds
--   10% of your daily warehouse credits — which is rare in normal
--   usage but worth knowing exists.
--
-- WHY THIS MATTERS DAY TO DAY
--   · You scale compute independently of storage — no migration needed
--   · Multiple teams can work simultaneously without resource conflict
--   · You pay for compute only when it is running (auto-suspend is
--     your friend and your cost control mechanism)
--   · There are no indexes to build or maintain — Snowflake's
--     micro-partition metadata serves that purpose
--   · There is no VACUUM, ANALYZE, or REORG — Snowflake handles this
--
-- ══════════════════════════════════════════════════════════════
-- STEP 1: Verify your account and cloud provider
-- ══════════════════════════════════════════════════════════════

-- This tells you which cloud platform your Snowflake account lives on
-- (AWS, Azure, or GCP) and which region. Relevant because:
--   · Data transfer costs apply when moving data to/from cloud storage
--     in a different region or cloud
--   · Some features have regional availability differences
--   · Latency to external stages depends on matching regions

SELECT
    CURRENT_ACCOUNT()       AS account_identifier,
    CURRENT_REGION()        AS region,
    CURRENT_ORGANIZATION_NAME() AS organization
;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Observe the three layers in action
-- ══════════════════════════════════════════════════════════════

-- The cloud services layer answers this query without a warehouse.
-- Notice: you do not need to have a warehouse running to query
-- metadata. Cloud services handles it entirely.
-- This is a concrete demonstration of layer separation.

SELECT
    CURRENT_USER()          AS current_user,
    CURRENT_ROLE()          AS current_role,
    CURRENT_WAREHOUSE()     AS active_warehouse,    -- may be NULL if none selected
    CURRENT_DATABASE()      AS active_database,     -- may be NULL if none selected
    CURRENT_SCHEMA()        AS active_schema,       -- may be NULL if none selected
    CURRENT_TIMESTAMP()     AS current_time
;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Inspect available virtual warehouses
-- ══════════════════════════════════════════════════════════════

-- This shows all warehouses your current role can see.
-- Key columns to understand:
--   · name         — warehouse identifier
--   · size         — compute size (X-Small through 6X-Large)
--   · state        — STARTED, SUSPENDED, or RESIZING
--   · auto_suspend — seconds of inactivity before suspension
--   · auto_resume  — whether it restarts automatically on query

SHOW WAREHOUSES;

-- After running SHOW WAREHOUSES, you can query its output using
-- RESULT_SCAN. This is a pattern you will use throughout this
-- workbook — making SHOW command output queryable.
-- We cover this in depth in Goal 9. For now, observe the pattern:

SELECT
    "name"          AS warehouse_name,
    "size"          AS warehouse_size,
    "state"         AS current_state,
    "auto_suspend"  AS auto_suspend_seconds,
    "auto_resume"   AS auto_resume_enabled
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "name"
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Confirm the storage / compute separation
-- ══════════════════════════════════════════════════════════════

-- Snowflake pre-loads sample data you can query immediately.
-- This query reads from the storage layer using the compute layer.
-- Watch the query profile after running it (Query History → the
-- query → Query Profile tab) — you will see the TableScan node
-- reading micro-partitions from storage.

USE DATABASE SNOWFLAKE_SAMPLE_DATA;
USE SCHEMA TPCH_SF1;

-- A simple query to confirm layers are working together.
-- TPCH_SF1 is a 1GB scale-factor version of the TPC-H benchmark —
-- small enough to run instantly, large enough to be non-trivial.

SELECT
    L_RETURNFLAG,
    L_LINESTATUS,
    COUNT(*)                            AS line_count,
    SUM(L_QUANTITY)                     AS total_quantity,
    SUM(L_EXTENDEDPRICE)                AS total_extended_price,
    AVG(L_DISCOUNT)                     AS avg_discount
FROM LINEITEM
GROUP BY
    L_RETURNFLAG,
    L_LINESTATUS
ORDER BY
    L_RETURNFLAG,
    L_LINESTATUS
;

-- After running: go to Query History (see below), open this query, and click
-- "Query Profile". You will see:
--   · TableScan    — reading from the storage layer
--   · Aggregate    — running on your compute (virtual warehouse)
--   · Result       — returned through cloud services to your session
-- This is the three-layer architecture made visible.

-- ── HOW TO FIND QUERY HISTORY IN SNOWSIGHT ───────────────────
-- Left sidebar → Monitoring → Query History
-- Find your LINEITEM query in the list (most recent at the top)
-- Click the Query ID link to open the query details
-- Click the "Query Profile" tab at the top of the details panel
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Observe credit consumption
-- ══════════════════════════════════════════════════════════════

-- After running the query above, check what it cost.
-- This queries the cloud services layer (no warehouse needed).

SELECT
    QUERY_ID,
    QUERY_TEXT,
    WAREHOUSE_NAME,
    WAREHOUSE_SIZE,
    EXECUTION_TIME / 1000           AS execution_seconds,
    CREDITS_USED_CLOUD_SERVICES     AS cloud_services_credits,
    BYTES_SCANNED / (1024 * 1024)   AS mb_scanned,
    ROWS_PRODUCED
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
    DATEADD('hour', -1, CURRENT_TIMESTAMP()),
    CURRENT_TIMESTAMP(),
    10
))
ORDER BY START_TIME DESC
;

-- Key columns:
--   · CREDITS_USED_CLOUD_SERVICES — usually tiny (< 0.001 per query)
--   · BYTES_SCANNED                — how much data was read from storage
--   · PARTITIONS_SCANNED vs TOTAL  — how many micro-partitions were read
--     vs how many exist. A low ratio = good pruning. A ratio near 1.0
--     = full table scan. You will learn to improve this in Goal 5.

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Confirm storage/compute independence
-- ══════════════════════════════════════════════════════════════

-- Suspend your warehouse. Then run a metadata query.
-- The metadata query will succeed — because cloud services answers
-- it, not your warehouse. This is the separation made tangible.

-- Suspend your warehouse (replace COMPUTE_WH with your warehouse name)
ALTER WAREHOUSE COMPUTE_WH SUSPEND;

-- Note: if you see "Invalid state. Warehouse cannot be suspended"
-- your warehouse is either already suspended or auto-suspend
-- handled it first. This is normal. Continue to the next query.

-- This query works even with no warehouse running.
-- Cloud services layer answers it from metadata alone.
SELECT
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    ROW_COUNT,
    BYTES / (1024 * 1024)   AS size_mb
FROM SNOWFLAKE_SAMPLE_DATA.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'TPCH_SF1'
ORDER BY ROW_COUNT DESC
;

-- Now try to run the LINEITEM query from Step 4 with the warehouse
-- suspended. It will either:
--   a) Resume automatically (if AUTO_RESUME = true) — the warehouse
--      spins up in seconds. Notice the startup latency.
--   b) Fail with "No active warehouse" (if AUTO_RESUME = false)
--
-- Resume your warehouse when done:
ALTER WAREHOUSE COMPUTE_WH RESUME;

-- Note: if you see "Invalid state. Warehouse cannot be resumed"
-- your warehouse was never suspended and is still running.
-- This is fine — continue to the next step.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Run Step 5 (query history) BEFORE and AFTER running the
--    LINEITEM aggregation in Step 4. Compare PARTITIONS_SCANNED.
--    Now add a WHERE clause to filter to a single L_RETURNFLAG value
--    and run Step 5 again. Did the partition count drop?
--    What does that tell you about how Snowflake stores data?
--
-- 2. Find the QUERY_ID of your LINEITEM query from Step 4.
--    Run this and observe what the cloud services layer knows
--    about your query without re-executing it:
--
--    SELECT *
--    FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
--    WHERE QUERY_ID = '<your_query_id>'
--    ;
--
-- 3. Check whether your current warehouse has AUTO_SUSPEND enabled.
--    If it does not, what would be the cost implication of leaving
--    a size Large warehouse running overnight with no queries?
--    (Hint: a Large warehouse = 8 credits/hour)

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if two users run the same query at the same time on the
--    same warehouse?
-- A: The second user gets the result from the result cache
--    (cloud services layer) — instantly, with zero warehouse
--    credits consumed. The result cache holds identical query
--    results for 24 hours as long as the underlying data has
--    not changed. You will explore this in Goal 5.
--
-- Q: What if I want two teams to run heavy queries simultaneously
--    without affecting each other?
-- A: Create two separate virtual warehouses. Both read from the
--    same storage layer but each has its own compute. No resource
--    contention. You configure this in sub-task 1.7.
--
-- Q: What if my Snowflake account is on AWS but I want to load
--    data from an Azure Blob Storage container?
-- A: You can — but you will incur cross-cloud data transfer costs
--    and latency. Best practice is to match your Snowflake cloud
--    and region to your primary data source. If you need to bridge
--    clouds, consider Snowflake's cross-cloud replication features
--    instead of raw data movement.
--
-- Q: What happened to my query results when I suspended the
--    warehouse in Step 6?
-- A: Nothing. Results are returned to the client (your browser
--    or SQL tool) and stored in the result cache by cloud services.
--    The warehouse only needs to be running during query execution —
--    not before, and not after.