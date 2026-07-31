/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Sub-task 5.5 : Warehouse Sizing & Scaling Policies
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 25-30 min
  Warehouse size     : WORKBOOK_WH (X-Small) stays the default throughout;
                        a throwaway SMALL warehouse is created, used once,
                        and dropped — see WHAT YOU ARE DOING AND WHY
  Database           : ECOMMERCE.RAW
  Run in             : Snowsight
  Prerequisites       : Sub-task 5.1 complete — reuses that sub-task's
                        join+sort query as the workload for this size
                        comparison, since it's already a known, measurable
                        piece of work (SortWithLimit dominated ~36% of its
                        execution time per 5.1's operator stats)
  COF-C03 domain     : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════════
/*
Per the trial-account credit constraint set at the start of Goal 5,
WORKBOOK_WH stays X-Small for good — we are NOT resizing it up. Instead,
this sub-task creates one throwaway SMALL warehouse (auto-suspend after
60 seconds of idle), runs the exact same query on it that we run on
WORKBOOK_WH, compares the two, then drops the throwaway warehouse
immediately. Total exposure: one query's worth of Small-warehouse compute,
roughly a minute of runtime — not an ongoing cost.

Scaling POLICY (STANDARD vs ECONOMY) is covered conceptually here since
it's this sub-task's namesake, but it's actually a MULTI-CLUSTER setting —
it has no observable effect on a single-cluster warehouse. The hands-on
test of it belongs in 5.6, once a real multi-cluster warehouse exists to
observe it on.
*/


-- ══════════════════════════════════════════════════════════════════════
--  CONCEPT
-- ══════════════════════════════════════════════════════════════════════
/*
WAREHOUSE SIZE ("T-shirt sizing": X-Small, Small, Medium, Large, X-Large,
2X-Large, ... up to 6X-Large)
  - Each size step doubles the compute resources (and doubles the credit
    rate): X-Small = 1 credit/hour, Small = 2, Medium = 4, Large = 8,
    X-Large = 16, and so on, doubling at each step.
  - Billing is per-second, with a 60-second minimum each time a warehouse
    starts running.
  - Resizing is (nearly) instant and does NOT require restarting or
    draining the warehouse — queries already running continue on the old
    size; NEW queries submitted after the resize use the new size.
  - Bigger size = more parallelism for a SINGLE query: more compute nodes
    to divide large scans, sorts, joins, and aggregations across. This
    helps queries that do a lot of work over a lot of data.
  - Bigger size does NOT inherently help CONCURRENCY — many small/simple
    queries competing for the same warehouse are a queuing problem, not a
    per-query horsepower problem. That's what multi-cluster warehouses
    (5.6) address instead. Sizing up a warehouse to handle more concurrent
    users, without changing what any single query does, is a common and
    avoidable cost mistake.

SCALING POLICY (STANDARD vs ECONOMY)
  - This is a property of MULTI-CLUSTER warehouses (MAX_CLUSTER_COUNT > 1)
    — it controls how eagerly Snowflake spins up an additional cluster
    when queries start queuing.
  - STANDARD favors performance: starts a new cluster quickly to reduce
    queuing, even if that cluster only ends up doing a little work.
  - ECONOMY favors credit conservation: waits longer, more willing to let
    queries queue briefly, before deciding a new cluster is worth starting.
  - On a single-cluster warehouse (MAX_CLUSTER_COUNT = 1, the default),
    this setting can be SET without error but has no effect to observe —
    there's no second cluster for a policy to govern the creation of.
    Sub-task 5.6 covers this properly, once a real multi-cluster warehouse
    exists.

──────────────────────────────────────────────────────────────────────────
Oracle / SQL Server comparison:
  Oracle    : Vertical scaling means provisioning bigger hardware (or a
              bigger VM) for the same instance — typically requires
              planned downtime or at least a restart. Oracle RAC adds
              NODES sharing the same storage for availability/horizontal
              scale, but adding a RAC node is an infrastructure project,
              not a runtime setting change.
  SQL Server: Similarly, scaling up means a bigger VM/box, generally with
              a restart. Scale-out options exist (e.g. read replicas,
              PolyBase) but again require deliberate architecture, not a
              single ALTER statement.
  Key difference: Snowflake's warehouse resize is a live ALTER WAREHOUSE
  statement, taking effect for the next query with zero downtime and zero
  migration — the size is fully decoupled from the data and storage,
  since compute and storage are separate layers to begin with. Neither
  Oracle nor SQL Server can resize this casually or this fast.
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  SETUP
-- ══════════════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 1 — Baseline: run the workload on WORKBOOK_WH (X-Small)
-- ══════════════════════════════════════════════════════════════════════
/*
Reusing 5.1's join+sort query verbatim. USE_CACHED_RESULT must be FALSE
here — the result cache is ACCOUNT-WIDE, not warehouse-scoped, so without
this, running the identical query text on a different warehouse later
would just return the cached result again instead of giving a real timing
comparison.
*/

USE WAREHOUSE WORKBOOK_WH;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    o.order_id,
    o.customer_id,
    o.created_at,
    oi.product_id,
    oi.quantity,
    oi.unit_price
FROM ECOMMERCE.RAW.ORDERS o
JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON o.order_id = oi.order_id
ORDER BY o.created_at DESC
LIMIT 500000
;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

-- Capture this run's query_id, warehouse_size, and timing:
SELECT query_id, warehouse_name, warehouse_size, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%ORDER_ITEMS%ORDER BY o.created_at%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Create the throwaway comparison warehouse
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE WAREHOUSE SCALE_TEST_WH
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Run the identical workload on SCALE_TEST_WH (Small)
-- ══════════════════════════════════════════════════════════════════════

USE WAREHOUSE SCALE_TEST_WH;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT
    o.order_id,
    o.customer_id,
    o.created_at,
    oi.product_id,
    oi.quantity,
    oi.unit_price
FROM ECOMMERCE.RAW.ORDERS o
JOIN ECOMMERCE.RAW.ORDER_ITEMS oi
    ON o.order_id = oi.order_id
ORDER BY o.created_at DESC
LIMIT 500000
;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, warehouse_name, warehouse_size, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%ORDER_ITEMS%ORDER BY o.created_at%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;

-- Switch back to the default workbook warehouse for everything else:
USE WAREHOUSE WORKBOOK_WH;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Compare
-- ══════════════════════════════════════════════════════════════════════
/*
Pull both runs side by side in one query:
*/

SELECT query_id, warehouse_name, warehouse_size, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%ORDER_ITEMS%ORDER BY o.created_at%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 2
;

-- ACTUAL RESULT on this workbook:
--   WORKBOOK_WH  (X-Small) : 5.120s elapsed, 90,880,512 bytes scanned
--   SCALE_TEST_WH (Small)  : 4.449s elapsed, 90,880,512 bytes scanned
-- Identical bytes_scanned confirms both runs did the same real work — a
-- valid comparison. Small was ~13% faster (4.449 vs 5.120s) for 2x the
-- credit rate (2 credits/hr vs 1). That's a real but modest gain, and NOT
-- proportional to the doubled cost — a good concrete example of the
-- CONCEPT section's point that doubling size doesn't double speed for
-- every workload. Given this table's small size (8 partitions on
-- ORDER_ITEMS per 5.2/5.3), there may simply not be enough data volume
-- for a Small warehouse's extra compute nodes to meaningfully parallelize
-- beyond what X-Small already handles reasonably well. For THIS
-- workload, staying at X-Small is the more cost-effective choice —
-- exactly the judgment call warehouse sizing requires in production.

-- Reference: credit rate by size (doubles each step, billed per-second
-- with a 60-second minimum) — use this alongside the timing comparison
-- to judge whether the Small warehouse's speed gain (if any) is worth its
-- 2x credit rate for a workload like this one:
--   X-Small : 1 credit/hour     Large    : 8 credits/hour
--   Small   : 2 credits/hour    X-Large  : 16 credits/hour
--   Medium  : 4 credits/hour    2X-Large : 32 credits/hour  (doubling continues)


-- ══════════════════════════════════════════════════════════════════════
--  CLEANUP
-- ══════════════════════════════════════════════════════════════════════

DROP WAREHOUSE SCALE_TEST_WH;


-- ══════════════════════════════════════════════════════════════════════
--  PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════════
/*
1. Re-create SCALE_TEST_WH at MEDIUM instead of SMALL and re-run Steps 3-4.
   Does the elapsed-time gap widen proportionally, or level off? (This
   workload may be too small for a 4x-size warehouse to show a 4x gain —
   report what actually happens rather than assuming linear scaling.)

2. Try setting a scaling policy on SCALE_TEST_WH even though it's
   single-cluster:
     ALTER WAREHOUSE SCALE_TEST_WH SET SCALING_POLICY = 'ECONOMY';
   Confirm it's accepted without error via SHOW WAREHOUSES, and confirm
   (per the CONCEPT section) that there's nothing to actually observe
   differently in behavior with only one cluster.

3. Run a trivially small query (e.g. SELECT * FROM ECOMMERCE.RAW.ORDER_ITEMS
   LIMIT 10) on both WORKBOOK_WH and a Small warehouse. Does warehouse
   size make any measurable difference on a query this small? This is the
   practical case for "bigger isn't always better" — oversized warehouses
   on trivial queries mostly just cost more per second, not run faster.

4. Once SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY catches up
   (latency applies, same as prior sub-tasks), check the actual credits
   billed for SCALE_TEST_WH's brief existence — confirm it matches
   expectations for a ~60-second minimum billing window at Small size.
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: The Small warehouse wasn't meaningfully faster than X-Small for this
   query.
A: A real, useful result if so — not every workload benefits from vertical
   scaling. This join+sort operates over a relatively modest row count for
   this table's current size (per 5.1/5.2/5.3's ~8-partition finding on
   ORDER_ITEMS); the bottleneck may be elsewhere (e.g. the row access
   policy evaluation on ORDERS, or simply not enough data volume for
   extra compute nodes to meaningfully parallelize). Report the actual
   numbers — a flat or small difference is a legitimate finding about
   THIS workload's size-sensitivity, not a sign the test failed.

Q: Running the same query twice (once per warehouse) still hit the result
   cache instead of giving a real comparison.
A: Confirm USE_CACHED_RESULT was actually set to FALSE for BOTH runs, and
   that the two query texts are byte-for-byte identical to each other
   (any difference, even whitespace, would also break the intended
   comparison in the other direction — you want them identical to each
   other, just guaranteed to bypass cache via the session parameter).

Q: Do I need to worry about SCALE_TEST_WH accumulating cost if I forget to
   run the DROP WAREHOUSE at the end?
A: AUTO_SUSPEND = 60 means it stops billing after 60 seconds idle
   regardless — it won't run up ongoing compute cost even if left alone.
   The DROP is about tidiness (not leaving stray objects around) more than
   urgent cost prevention, unlike the clustering key in 5.3 where ongoing
   background reclustering was the real exposure.

Q: Why reuse 5.1's exact query instead of writing a new one for this test?
A: Using a query with already-known behavior (from 5.1's operator stats)
   means any difference we see between warehouse sizes is attributable to
   the size change itself, not to an unfamiliar new query shape — cleaner
   signal, fewer variables changing at once.
*/
