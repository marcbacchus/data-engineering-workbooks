/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Capstone     : Diagnose and Fix a Slow Analytics Workload
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 60-75 min
  Warehouse size     : WORKBOOK_WH (X-Small)
  Database           : Dedicated schema ECOMMERCE.CAPSTONE_G5 (see NOTE
                        ON COST below — this capstone has a real, one-time
                        setup cost unlike every prior sub-task)
  Run in             : Snowsight
  Prerequisites      : Sub-tasks 5.1-5.9 complete
  COF-C03 domain     : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
──────────────────────────────────────────────────────────────────────────
  NOTE ON COST: every prior sub-task in Goal 5 used ORDER_ITEMS (~8 micro-
  partitions) and repeatedly found it too small for clustering, search
  optimization, materialized views, or QAS to show a measurable win. This
  capstone deliberately uses real TPC-H benchmark data instead — copied
  via CREATE TABLE ... AS SELECT from Snowflake's free, read-only
  SNOWFLAKE_SAMPLE_DATA share (NOT a zero-copy clone; shares can't be
  cloned, so this is a genuine one-time copy with real compute + storage
  cost, unlike everything else in this goal).

  CONFIRMED ON THIS WORKBOOK: TPCH_SF1.LINEITEM (6,001,215 rows) STILL
  only produces 8 micro-partitions after the copy — TPC-H data is highly
  repetitive/low-cardinality and compresses so well that row count alone
  doesn't predict partition count; compressed size does. SF1 is NOT
  large enough for this capstone's purpose. TPCH_SF10 (~60M rows) was
  confirmed to produce 48 micro-partitions instead — 6x the ceiling that
  blocked every result from Sub-task 5.3 onward, and the SETUP step below
  now uses this as the working default.
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  SCENARIO
-- ══════════════════════════════════════════════════════════════════════
/*
You've inherited a workload built on an order-line-items table (real TPC-H
LINEITEM data standing in for a production fact table) with three known
complaints:

  1. A customer-service lookup tool filters by a single part number
     (l_partkey) and is slow — a POINT LOOKUP problem.
  2. A monthly reporting job filters by a shipping date RANGE
     (l_shipdate BETWEEN ...) and is slow — a RANGE QUERY problem.
  3. A BI dashboard re-runs the same revenue-by-status aggregation
     (grouped by l_returnflag, l_linestatus — the classic TPC-H Q1 shape)
     dozens of times a day — a REPEATED AGGREGATION problem.

Your job: diagnose each with the 5.1/5.2 methodology, pick the RIGHT tool
for each problem's shape (not just any tool), apply it, and prove the
improvement with real numbers — not just "it should be faster."
*/


-- ══════════════════════════════════════════════════════════════════════
--  TOOLKIT RECAP (this capstone applies, not re-teaches, these)
-- ══════════════════════════════════════════════════════════════════════
/*
  5.1  Query Profile / GET_QUERY_OPERATOR_STATS — read what actually ran
  5.2  SYSTEM$CLUSTERING_INFORMATION — measure natural clustering quality
  5.3  Clustering keys — best for RANGE queries / lookups returning many rows
  5.4  Result & warehouse caching — remember USE_CACHED_RESULT=FALSE for
       any before/after comparison
  5.7  Materialized views — best for repeated aggregations over ONE table
  5.8  Search optimization — best for POINT LOOKUPS returning few rows
  5.9  QAS / resource monitors — outlier-query offload and credit governance
*/


-- ══════════════════════════════════════════════════════════════════════
--  SETUP
-- ══════════════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;

-- Dedicated schema so the ENTIRE capstone can be torn down with one
-- command at the end (DROP SCHEMA CASCADE) — a new technique for this
-- workbook, since every prior sub-task dropped objects individually.
CREATE OR REPLACE SCHEMA ECOMMERCE.CAPSTONE_G5;

-- The one real-cost step in this capstone: a genuine copy, not a clone
-- (shares can't be cloned). CONFIRMED on this workbook: TPCH_SF1 (6M
-- rows) still only produces 8 micro-partitions after copying — TPC-H
-- data compresses too well for row count alone to guarantee enough
-- partitions. Using TPCH_SF10 (~60M rows) instead.
CREATE TABLE ECOMMERCE.CAPSTONE_G5.LINEITEM AS
    SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
;

-- From here on, these ARE zero-copy clones — cheap — since the source is
-- now a native table in your own schema, not the read-only share.
CREATE TABLE ECOMMERCE.CAPSTONE_G5.LINEITEM_SOS_TEST
    CLONE ECOMMERCE.CAPSTONE_G5.LINEITEM;
CREATE TABLE ECOMMERCE.CAPSTONE_G5.LINEITEM_CLUSTER_TEST
    CLONE ECOMMERCE.CAPSTONE_G5.LINEITEM;

USE SCHEMA ECOMMERCE.CAPSTONE_G5;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 1 — Diagnose Problem 1: the point-lookup tool (5.1/5.2 method)
-- ══════════════════════════════════════════════════════════════════════

SELECT l_partkey FROM LINEITEM_SOS_TEST LIMIT 1;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT * FROM LINEITEM_SOS_TEST WHERE l_partkey = '<partkey_from_above>';
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%LINEITEM_SOS_TEST%WHERE l_partkey%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;

SELECT
    operator_statistics:pruning:partitions_scanned::NUMBER AS partitions_scanned,
    operator_statistics:pruning:partitions_total::NUMBER    AS partitions_total
FROM TABLE(GET_QUERY_OPERATOR_STATS('<step1_query_id>'))
WHERE operator_type = 'TableScan'
;
-- On a table this size, expect a real partition count (dozens+, not 8) —
-- check whether the scan is already well-pruned or not before deciding
-- a fix is even needed.

-- WRITE DOWN THESE BASELINE NUMBERS NOW — Step 4 needs them for an AFTER
-- comparison, and you won't want to scroll back for them later:
--   BEFORE elapsed_seconds : ______
--   BEFORE bytes_scanned   : ______
--   BEFORE partitions_scanned / partitions_total : ______ / 48


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Diagnose Problem 2: the range-query report (5.1/5.2 method)
-- ══════════════════════════════════════════════════════════════════════

SELECT MIN(l_shipdate), MAX(l_shipdate) FROM LINEITEM_CLUSTER_TEST;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT * FROM LINEITEM_CLUSTER_TEST
WHERE l_shipdate BETWEEN '<start_date>' AND DATEADD(month, 1, '<start_date>');
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%LINEITEM_CLUSTER_TEST%WHERE l_shipdate%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;

SELECT
    operator_statistics:pruning:partitions_scanned::NUMBER AS partitions_scanned,
    operator_statistics:pruning:partitions_total::NUMBER    AS partitions_total
FROM TABLE(GET_QUERY_OPERATOR_STATS('<step2_query_id>'))
WHERE operator_type = 'TableScan'
;

-- WRITE DOWN THESE BASELINE NUMBERS NOW — Step 5 needs them for an AFTER
-- comparison, and you won't want to scroll back for them later:
--   BEFORE elapsed_seconds : ______
--   BEFORE bytes_scanned   : ______
--   BEFORE partitions_scanned / partitions_total : ______ / 48


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Check natural clustering on both target columns (5.2 method)
-- ══════════════════════════════════════════════════════════════════════

SELECT
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('LINEITEM_SOS_TEST', '(L_PARTKEY)')):average_depth::FLOAT AS avg_depth,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('LINEITEM_SOS_TEST', '(L_PARTKEY)')):total_partition_count::NUMBER AS total_partitions
;

SELECT
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('LINEITEM_CLUSTER_TEST', '(L_SHIPDATE)')):average_depth::FLOAT AS avg_depth,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('LINEITEM_CLUSTER_TEST', '(L_SHIPDATE)')):total_partition_count::NUMBER AS total_partitions
;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Fix Problem 1 with Search Optimization (point lookup → SOS)
-- ══════════════════════════════════════════════════════════════════════
/*
Per 5.8's finding: search optimization is the RIGHT tool for a point
lookup returning few rows — not clustering. Estimate first, per the
Goal 5 discipline.
*/

SELECT SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS(
    'ECOMMERCE.CAPSTONE_G5.LINEITEM_SOS_TEST',
    'EQUALITY("L_PARTKEY")'
);

ALTER TABLE LINEITEM_SOS_TEST ADD SEARCH OPTIMIZATION ON EQUALITY(l_partkey);

-- Poll until 100%:
SHOW TABLES LIKE 'LINEITEM_SOS_TEST' IN SCHEMA ECOMMERCE.CAPSTONE_G5;

-- Re-test (same value as Step 1 if you still have it, or a new one):
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT * FROM LINEITEM_SOS_TEST WHERE l_partkey = '<same_or_new_partkey>';
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%LINEITEM_SOS_TEST%WHERE l_partkey%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;
-- Compare bytes_scanned and elapsed_seconds against Step 1's baseline —
-- on real-scale data, expect this comparison to actually move, unlike
-- 5.8's result on the 8-partition table.

-- Check the operator types directly (no operator_type filter this time —
-- see the actual confirmed result below for why):
SELECT operator_id, operator_type,
       operator_statistics:pruning:partitions_scanned::NUMBER AS partitions_scanned,
       operator_statistics:pruning:partitions_total::NUMBER    AS partitions_total
FROM TABLE(GET_QUERY_OPERATOR_STATS('<step4_retest_query_id>'))
;

-- ACTUAL RESULT — a genuine, measurable win, the first in this workbook:
--   Baseline (Step 1, TableScan):              48/48 partitions scanned
--   After search optimization:                 17/48 partitions scanned
-- ~65% fewer partitions read. This ALSO resolves 5.8's open question
-- about what operator GET_QUERY_OPERATOR_STATS shows when search
-- optimization is actually engaged: it's a distinct operator type,
-- "Search Optimization Access" — NOT a relabeled TableScan, and NOT
-- something operator_type = 'TableScan' filters will catch. Any future
-- check for search-optimization usage should look for this operator name
-- specifically, not assume it still reports as TableScan.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 5 — Fix Problem 2 with a Clustering Key (range query → clustering)
-- ══════════════════════════════════════════════════════════════════════
/*
Per 5.3/5.8's guidance: clustering is the RIGHT tool for a RANGE query —
not search optimization. This is the first time this workbook has tested
that guidance against an actual range predicate, not just an equality one.
*/

ALTER TABLE LINEITEM_CLUSTER_TEST CLUSTER BY (l_shipdate);

SELECT
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('LINEITEM_CLUSTER_TEST')):average_depth::FLOAT AS avg_depth,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('LINEITEM_CLUSTER_TEST')):total_constant_partition_count::NUMBER AS constant_partitions
;
-- Re-check periodically until this shows real improvement over Step 3's
-- baseline depth for l_shipdate.

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT * FROM LINEITEM_CLUSTER_TEST
WHERE l_shipdate BETWEEN '<same_start_date>' AND DATEADD(month, 1, '<same_start_date>');
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%LINEITEM_CLUSTER_TEST%WHERE l_shipdate%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;

-- Check pruning — no operator_type filter, per 5.8/Step 4's confirmed
-- discovery that a differently-named operator (e.g. clustering may show
-- under a different label too) could otherwise be silently excluded:
SELECT operator_id, operator_type,
       operator_statistics:pruning:partitions_scanned::NUMBER AS partitions_scanned,
       operator_statistics:pruning:partitions_total::NUMBER    AS partitions_total
FROM TABLE(GET_QUERY_OPERATOR_STATS('<step5_retest_query_id>'))
;

-- AFTER vs BEFORE (fill in from the values you saved above):
--   elapsed_seconds        : BEFORE ______  ->  AFTER ______
--   bytes_scanned           : BEFORE ______  ->  AFTER ______
--   partitions_scanned/total: BEFORE ______  ->  AFTER ______

-- ACTUAL RESULT — the biggest win in this capstone:
--   BEFORE (Step 2, TableScan): 48/48 partitions scanned (100%)
--   AFTER  (Step 5, TableScan):  3/49 partitions scanned (~6.1%)
-- ~94% fewer partitions read — even more dramatic than Step 4's search
-- optimization result (17/48, ~65% reduction) on the point lookup. Makes
-- sense: l_shipdate is a natural range column, and clustering is
-- specifically the right tool for range queries — exactly the guidance
-- this capstone was built to test empirically, not just quote.
--
-- Two things worth noting:
-- 1. partitions_total shifted 48 -> 49 — same phenomenon confirmed back
--    in 5.3 on the small table: reclustering physically rewrites the
--    table into a new partition layout, so the total itself can change,
--    not just the arrangement of data within a fixed partition count.
--    Confirmed again here at real scale.
-- 2. The operator is still plain TableScan — NOT a distinct named
--    operator like Step 4's "Search Optimization Access". This is the
--    real mechanistic difference between the two techniques: clustering
--    doesn't add a new access path, it improves the metadata an ORDINARY
--    TableScan's own pruning already relies on. Search optimization adds
--    a separate structure; clustering makes the existing one work better.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 6 — Fix Problem 3 with a Materialized View (repeated aggregation)
-- ══════════════════════════════════════════════════════════════════════
/*
Classic TPC-H Q1 shape: single table, GROUP BY, supported aggregates
(SUM, COUNT) — squarely within the MV single-table restriction from 5.7.
*/

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT l_returnflag, l_linestatus, SUM(l_quantity) AS sum_qty, SUM(l_extendedprice) AS sum_price, COUNT(*) AS cnt
FROM LINEITEM
GROUP BY l_returnflag, l_linestatus
;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%FROM LINEITEM%GROUP BY l_returnflag%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;
-- This is your baseline. BEFORE YOU CONTINUE, write these down:
--   BEFORE elapsed_seconds : ______
--   BEFORE bytes_scanned   : ______

CREATE MATERIALIZED VIEW MV_LINEITEM_STATUS_SUMMARY AS
    SELECT l_returnflag, l_linestatus, SUM(l_quantity) AS sum_qty, SUM(l_extendedprice) AS sum_price, COUNT(*) AS cnt
    FROM LINEITEM
    GROUP BY l_returnflag, l_linestatus
;

SHOW MATERIALIZED VIEWS LIKE 'MV_LINEITEM_STATUS_SUMMARY' IN SCHEMA ECOMMERCE.CAPSTONE_G5;
-- Wait for behind_by = 0s / invalid = false before proceeding.

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT l_returnflag, l_linestatus, sum_qty, sum_price, cnt FROM MV_LINEITEM_STATUS_SUMMARY;
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%MV_LINEITEM_STATUS_SUMMARY%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
  AND query_text NOT ILIKE '%SHOW MATERIALIZED%'
ORDER BY start_time DESC
LIMIT 1
;
-- AFTER vs BEFORE (fill in from the values you saved above):
--   elapsed_seconds : BEFORE ______  ->  AFTER ______
--   bytes_scanned   : BEFORE ______  ->  AFTER ______
-- On SF10-scale data (~60M rows), expect elapsed_seconds itself to move
-- this time, not just bytes_scanned (unlike 5.7's result on the small
-- 8-partition table).

-- ACTUAL RESULT — the cleanest confirmation in this capstone:
--   BEFORE (base table aggregate): 0.845s elapsed, 1,431,718,912 bytes scanned
--   AFTER  (MV direct read):       0.294s elapsed,        15,360 bytes scanned
-- elapsed_seconds dropped ~65% — the FIRST time in this entire workbook
-- a materialized view has moved wall-clock time, not just bytes_scanned.
-- This directly confirms the prediction made back in 5.7: on the tiny
-- 8-partition table, the ~31x byte reduction was real but invisible in
-- elapsed_seconds because fixed per-query overhead dominated at that
-- scale. Here, with a genuinely large base-table scan to eliminate, the
-- same underlying mechanism produces a difference you can actually see
-- in wall-clock time. bytes_scanned tells the more extreme story:
-- ~93,000x fewer bytes read (1.43GB down to 15KB) — reading a handful of
-- precomputed summary rows instead of aggregating 60M rows from scratch.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 7 — Check QAS eligibility on the original diagnostic query
-- ══════════════════════════════════════════════════════════════════════

SELECT PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION('<a_full_unpruned_scan_query_id>'));
-- IMPORTANT: use a query_id from a FULL, UNPRUNED scan (before any fix
-- was applied) — a query against the MV or the search-optimized/
-- clustered tables will trivially read too little to ever be eligible,
-- which isn't a meaningful test of this step's actual question.

-- ACTUAL RESULT, using a genuine full-table scan (1,431,718,912 bytes,
-- 0.42s elapsed — the same full scan that Step 6 measured before its MV):
--   {"ineligibleReason":"NO_LARGE_ENOUGH_SCAN","originalQueryTime":0.42,
--    "status":"ineligible","upperLimitScaleFactor":0}
--
-- Notably still ineligible — and this time NOT simply "too small," since
-- 1.43GB is a real, substantial scan. The more likely explanation: QAS
-- eligibility isn't about bytes scanned in isolation, it's about whether
-- there's an actual acceleration OPPORTUNITY worth the overhead of
-- recruiting serverless compute. A query that already finishes in well
-- under a second has little left to gain — X-Small already parallelizes
-- a scan this size efficiently enough that it isn't a slow query in
-- absolute terms, regardless of byte count. QAS specifically targets
-- OUTLIER queries (unusually long-running due to a large, slow scan),
-- not merely "scans a lot of bytes but still finishes fast."
--
-- Honest conclusion for this capstone: SF10's scale (48 partitions) was
-- large enough to prove real, measurable wins for clustering, search
-- optimization, and materialized views — but QAS sits behind a
-- meaningfully HIGHER bar than any of those three. Reaching genuine QAS
-- eligibility would likely need either a much larger table (TPCH_SF100+)
-- or a query that's slow for reasons beyond raw scan size (e.g. a
-- multi-second aggregation over a truly massive table). Not tested
-- further here given the cost/time tradeoff already discussed for SF100.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 8 — Governance check: is the safety net still watching this?
-- ══════════════════════════════════════════════════════════════════════

SHOW RESOURCE MONITORS LIKE 'WORKBOOK_DAILY_LIMIT';
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';
-- Confirm it's still attached. Given this capstone's real CTAS cost
-- (Setup) plus clustering/MV/search-optimization maintenance on ~60M
-- rows (TPCH_SF10), consider whether the 5-credit daily quota from 5.9
-- needs a temporary bump for capstone day specifically.


-- ══════════════════════════════════════════════════════════════════════
--  CLEANUP — single-command teardown
-- ══════════════════════════════════════════════════════════════════════

DROP SCHEMA ECOMMERCE.CAPSTONE_G5 CASCADE;
-- Removes the table, both clones, the clustering key, the search access
-- path, and the materialized view — everything — in one statement.


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: SF10 (~60M rows) still doesn't show a dramatic enough improvement, or
   the CTAS copy time/cost is more than you want to spend?
A: TPCH_SF100 (~600M rows) is available if you need an even larger
   effect, but is a genuinely large cost commitment — not recommended on
   a trial account without a specific reason. Going the other direction:
   TPCH_SF1 was tried on this workbook first and confirmed insufficient
   (6M rows still compressed down to just 8 micro-partitions) — don't
   go back to it expecting a different result.

Q: Why two separate CLONE copies (LINEITEM_SOS_TEST, LINEITEM_CLUSTER_TEST)
   instead of applying both fixes to one table?
A: Snowflake's own docs note that clustering and search optimization
   together cost MORE to maintain than either alone (reclustering can
   trigger extra search-access-path maintenance). Isolating each fix on
   its own copy keeps Step 4 and Step 5's measurements clean and
   independent — you're measuring each tool's effect on its own, not a
   combined, harder-to-interpret result.

Q: Why CTAS instead of CLONE for the initial LINEITEM copy?
A: SNOWFLAKE_SAMPLE_DATA is a shared, read-only database — shares cannot
   be zero-copy cloned. CTAS (SELECT * INTO a new table) is the standard,
   documented approach for pulling a working copy out of sample/shared
   data into your own schema.

Q: Step 4 or Step 5 still didn't show a dramatic improvement even at
   SF10 scale (~60M rows).
A: Worth checking SYSTEM$CLUSTERING_INFORMATION's actual total_partition_
   count for LINEITEM at this scale before concluding the fix failed —
   confirm it's genuinely well above the 8-partition ceiling this
   workbook kept hitting at smaller scale (SF1 compressed all the way
   down to 8 partitions even at 6M rows, so don't assume a bigger row
   count guarantees a bigger partition count — verify it directly). If
   partition count is confirmed high and the improvement is still real
   but modest, that's a legitimate, informative result; if you want an
   even clearer signal, TPCH_SF100 is the next step up.
*/
