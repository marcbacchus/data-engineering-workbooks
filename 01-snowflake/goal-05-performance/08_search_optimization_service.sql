/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Sub-task 5.8 : Search Optimization Service
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 30-40 min (includes wait time for the background
                        index build — see WHAT YOU ARE DOING AND WHY)
  Warehouse size     : WORKBOOK_WH (X-Small) — Search Optimization Service
                        maintenance runs on Snowflake's own serverless
                        compute, not this warehouse. A warehouse IS needed
                        to run the cost-estimate function, though (see
                        Step 2) — X-Small is fine, size has no effect on it.
  Database           : ECOMMERCE.RAW
  Run in             : Snowsight
  Prerequisites      : Sub-tasks 5.1-5.7 complete. Search Optimization
                        Service requires Enterprise Edition — confirmed
                        available on this account, same requirement as
                        5.6's multi-cluster warehouses and 5.7's MVs.
                        Directly reuses 5.2's finding: PRODUCT_ID filters
                        on ORDER_ITEMS scanned 8/8 partitions (zero
                        pruning) — the textbook case this service targets.
  COF-C03 domain     : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════════
/*
5.2 already proved PRODUCT_ID is a bad column for pruning on ORDER_ITEMS —
naturally scattered evenly across every partition, so an equality filter
on it scans 100% of partitions no matter what. 5.3 showed a clustering key
could shrink that, but clustering only helps ONE column's layout at a
time, and it only helps range/equality filters on the clustered column(s)
specifically.

Search Optimization Service (SOS) takes a different approach: instead of
reorganizing the table's physical layout, it builds a separate index-like
structure (the "search access path") that lets Snowflake skip partitions
for point-lookup queries — WITHOUT touching the table's clustering at all.
It's purpose-built for exactly the PRODUCT_ID scenario 5.2 already proved
is a real problem here.

Per the Goal 5 credit-safety plan set at the start: estimate the cost
FIRST, enable it on the smallest reasonable throwaway table, capture
before/after performance, then disable it in the same session.
*/


-- ══════════════════════════════════════════════════════════════════════
--  CONCEPT
-- ══════════════════════════════════════════════════════════════════════
/*
The search optimization service builds and maintains a "search access
path" — metadata that tracks which values of a column might appear in
each micro-partition, allowing partitions to be skipped for point-lookup
queries even when the column isn't well-clustered. This is fundamentally
different from clustering: clustering physically reorganizes DATA;
search optimization builds an additional INDEX-LIKE structure alongside
the data, without moving it.

Best suited for:
  - Equality and IN-list point lookups (WHERE product_id = X, or
    WHERE product_id IN (...)) — the direct callback to 5.2's finding.
  - Substring/pattern searches (LIKE, ILIKE, RLIKE).
  - Certain predicates on semi-structured data (VARIANT/OBJECT/ARRAY) —
    equality, IN, NULL checks, ARRAY_CONTAINS.
  - Queries returning a SMALL number of rows relative to the table. If a
    query returns a large fraction of the table, clustering is generally
    the better tool (per Snowflake's own guidance) — these two features
    solve different shaped problems, not competing versions of the same
    fix.

Cost model: like automatic clustering (5.3) and materialized views (5.7),
this is a Snowflake-managed background service — no warehouse of yours is
involved in maintenance, billed separately, visible (with the usual
ACCOUNTADMIN + ~3hr latency) via SNOWFLAKE.ACCOUNT_USAGE.
SEARCH_OPTIMIZATION_HISTORY. Storage overhead for the search access path
is typically around 1/4 of the base table's size, though it can approach
the table's full size in the extreme case of all-unique, all-indexed
columns.

Progress is tracked via SHOW TABLES' SEARCH_OPTIMIZATION and
SEARCH_OPTIMIZATION_PROGRESS columns — 0% means enabled but not yet built;
100% means the search access path is fully populated and usable.

Cost estimation via SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS is a
best-effort — Snowflake's own documentation notes actual realized costs
can vary by up to 50%, or in rare cases several times, from the estimate.
Treat it as a sanity check, not a guarantee.

──────────────────────────────────────────────────────────────────────────
Oracle / SQL Server comparison:
  Oracle    : The closest analogue is a B-tree or bitmap INDEX — an
              explicit DDL object you create, name, and maintain (rebuild,
              monitor fragmentation, etc.) directly.
  SQL Server: Similarly, non-clustered indexes are explicit objects you
              create and maintain, with visible maintenance plans and
              fragmentation monitoring as a routine DBA task.
  Key difference: Snowflake's search access path is NOT a named, directly
  manipulable index object the way Oracle/SQL Server indexes are — it's a
  property of the table (ADD/DROP SEARCH OPTIMIZATION), maintained
  entirely automatically, with no manual rebuild, no fragmentation to
  monitor, and no index name to reference in a query hint. You enable or
  disable it; Snowflake handles everything else.
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  SETUP
-- ══════════════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Throwaway clone, consistent with the rest of Goal 5's pattern.
CREATE OR REPLACE TABLE ECOMMERCE.RAW.SEARCH_OPT_TEST_SCRATCH
    CLONE ECOMMERCE.RAW.ORDER_ITEMS
;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 1 — Baseline: the same poorly-clustered lookup from 5.2
-- ══════════════════════════════════════════════════════════════════════

-- Grab a real product_id to filter on:
SELECT product_id FROM ECOMMERCE.RAW.SEARCH_OPT_TEST_SCRATCH LIMIT 1;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT * FROM ECOMMERCE.RAW.SEARCH_OPT_TEST_SCRATCH WHERE product_id = '<product_id_from_above>';

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%SEARCH_OPT_TEST_SCRATCH%WHERE product_id%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;

-- Check actual pruning on this baseline run (same methodology as 5.2):
SELECT
    operator_id,
    operator_statistics:pruning:partitions_scanned::NUMBER AS partitions_scanned,
    operator_statistics:pruning:partitions_total::NUMBER    AS partitions_total
FROM TABLE(GET_QUERY_OPERATOR_STATS('<step1_query_id>'))
WHERE operator_type = 'TableScan'
;
-- Expect 100% scanned, matching 5.2's PRODUCT_ID finding on this same table.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Estimate the cost BEFORE enabling anything
-- ══════════════════════════════════════════════════════════════════════
/*
Must run this BEFORE search optimization is added — the function only
works on a table/columns that don't already have it enabled. Needs an
active warehouse (already set above); size doesn't matter for this
function specifically. Can take anywhere from ~20 seconds to several
minutes.
*/

SELECT SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS(
    'ECOMMERCE.RAW.SEARCH_OPT_TEST_SCRATCH',
    'EQUALITY("PRODUCT_ID")'
);
-- Review the returned JSON's cost breakdown before proceeding. Remember:
-- Snowflake's own docs say actual costs can vary up to 50% (or more) from
-- this estimate — treat it as a sanity check, not a firm number.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Enable search optimization (targeted, not whole-table)
-- ══════════════════════════════════════════════════════════════════════
/*
Targeting ON EQUALITY(product_id) specifically, rather than the whole
table, keeps this to the exact scenario being tested and avoids paying to
build search access paths for columns not part of this experiment.
*/

ALTER TABLE ECOMMERCE.RAW.SEARCH_OPT_TEST_SCRATCH
    ADD SEARCH OPTIMIZATION ON EQUALITY(product_id)
;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Wait for the background build, check progress
-- ══════════════════════════════════════════════════════════════════════
/*
This is asynchronous, same pattern as 5.3's clustering key and 5.7's MV
refresh — don't expect instant completion. Re-run this until
search_optimization_progress reads 100.
*/

SHOW TABLES LIKE 'SEARCH_OPT_TEST_SCRATCH' IN SCHEMA ECOMMERCE.RAW;
-- Check the "search_optimization" (should read ON) and
-- "search_optimization_progress" (0-100) columns.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 5 — Re-run the identical lookup once progress = 100
-- ══════════════════════════════════════════════════════════════════════

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT * FROM ECOMMERCE.RAW.SEARCH_OPT_TEST_SCRATCH WHERE product_id = '<same_product_id_as_step1>';

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%SEARCH_OPT_TEST_SCRATCH%WHERE product_id%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;

SELECT
    operator_id,
    operator_type,
    operator_statistics:pruning:partitions_scanned::NUMBER AS partitions_scanned,
    operator_statistics:pruning:partitions_total::NUMBER    AS partitions_total
FROM TABLE(GET_QUERY_OPERATOR_STATS('<step5_query_id>'))
;
-- Look for BOTH a lower partitions_scanned than Step 1, AND an operator
-- type referencing search optimization (per Snowflake's docs, the query
-- profile shows a dedicated "Search Optimization Access" node when the
-- service is actually used for a query — report the exact operator_type
-- string that shows up here, since this workbook hasn't confirmed its
-- exact name yet).

-- ACTUAL RESULT: Result, Filter, TableScan (8/8 partitions) — IDENTICAL
-- to Step 1's baseline. No improvement, and no dedicated search
-- optimization operator appeared at all.
--
-- This is a coherent, explainable result, not a failed test — and it
-- traces directly back to 5.2's finding on THIS SAME COLUMN: PRODUCT_ID's
-- average_depth was 8 out of a possible 8, the absolute worst case,
-- meaning product_id values are scattered essentially evenly across
-- every partition. Search optimization works by identifying partitions
-- that DON'T contain a filtered value, so it can be skipped — but if a
-- given product_id's rows are already present in ALL 8 partitions (which
-- 5.2's depth score strongly implies), there is nothing to skip. No
-- technique that works by skipping partitions — not clustering (5.3),
-- not search optimization — can do anything when the data you're
-- filtering for already exists everywhere. This isn't a limitation of
-- search optimization specifically; it's a limitation of partition-level
-- pruning as a strategy, full stop, for a column shaped like this one.
--
-- Compounding factor: search optimization is built for point lookups
-- returning a SMALL number of rows relative to the table (per the
-- CONCEPT section). If this specific product_id returns a large number
-- of matching rows (plausible for a popular product across many order
-- lines), that's a second reason this wasn't a strong SOS candidate to
-- begin with — worth checking via SELECT COUNT(*) ... WHERE product_id =
-- '<the value used>' against the table's total row count.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 6 — Check cost (latency applies — check back later)
-- ══════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

SELECT start_time, end_time, table_name, credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.SEARCH_OPTIMIZATION_HISTORY
WHERE table_name = 'SEARCH_OPT_TEST_SCRATCH'
ORDER BY start_time DESC
;

-- Bonus: confirms actual USAGE/benefit (not just that it exists) —
-- likely also has latency, unverified in this workbook:
SELECT table_name, SUM(num_scans) AS total_scans,
       SUM(partitions_pruned_additional) AS total_additional_pruned,
       SUM(partitions_scanned) AS total_partitions_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.SEARCH_OPTIMIZATION_BENEFITS
WHERE table_name = 'SEARCH_OPT_TEST_SCRATCH'
GROUP BY table_name
;

USE ROLE SYSADMIN;


-- ══════════════════════════════════════════════════════════════════════
--  CLEANUP — disable in the same session, per the Goal 5 plan
-- ══════════════════════════════════════════════════════════════════════

ALTER TABLE ECOMMERCE.RAW.SEARCH_OPT_TEST_SCRATCH DROP SEARCH OPTIMIZATION;

DROP TABLE ECOMMERCE.RAW.SEARCH_OPT_TEST_SCRATCH;


-- ══════════════════════════════════════════════════════════════════════
--  PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════════
/*
1. Compare SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS for the targeted
   EQUALITY(product_id) config against a whole-table estimate (call the
   function with just the table name, no second argument). How much does
   the estimate change when every eligible column is included instead of
   just one?

2. Test a substring search instead of equality — pick a text/VARCHAR
   column, add ON SUBSTRING(col), and compare a LIKE '%...%' query's
   pruning before and after.

3. Recall this note from the docs: cloning a table that ALREADY has
   search optimization enabled carries the property over to the clone,
   and Snowflake's own guidance is to disable it immediately on the clone
   unless you want it. None of Goal 5's prior throwaway clones were made
   from a search-optimized source, so this never came up before — but
   worth remembering for any future clone of a table that might have SOS
   enabled.

4. Compare this sub-task's PRODUCT_ID result against 5.3's clustering-key
   result on the same column. Which approach produced a bigger pruning
   improvement on this specific table — clustering or search optimization
   — and does that match Snowflake's own guidance on when to prefer one
   over the other (point lookups favor search optimization; range queries
   favor clustering)?

5. Re-run this entire sub-task's test on ORDER_ID instead of PRODUCT_ID.
   5.2 showed ORDER_ID had better (though imperfect) natural clustering
   depth (6.25/8, not the worst-case 8/8 that PRODUCT_ID hit) — meaning
   there's actual room for partitions to be skippable. If ORDER_ID shows
   a real pruning improvement where PRODUCT_ID showed none, that directly
   confirms the "nothing to skip when the value is everywhere" theory
   from Step 5's result.

   ACTUAL RESULT: 5/8 partitions scanned BOTH before and after adding
   ADD SEARCH OPTIMIZATION ON EQUALITY(order_id) — no incremental
   improvement, but for a DIFFERENT reason than PRODUCT_ID's null result.
   PRODUCT_ID showed no improvement because the value exists in every
   partition (nothing any technique can skip). ORDER_ID's 5/8 was already
   present in the Step 1-equivalent baseline BEFORE search optimization
   was ever added — meaning ordinary min/max partition metadata pruning
   was already finding the correct 5 partitions on its own. Search
   optimization's specific value-add is catching cases where a value
   falls WITHIN a partition's min/max range but isn't actually present
   there — letting it skip partitions plain min/max pruning couldn't. If
   the true answer is genuinely 5 partitions (the value legitimately
   exists in exactly those 5), there's nothing left for search
   optimization to improve on top of an already-optimal result. Two
   different columns, two different reasons for zero measured benefit —
   both real, neither a sign the feature is broken. On a table with only
   8 total partitions either scenario (value everywhere, or standard
   pruning already optimal) is plausible; a production table with
   thousands of partitions is where the gap between "min/max range
   includes this partition" and "value is actually IN this partition"
   becomes large enough for search optimization to show a real,
   measurable difference.
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: ALTER TABLE ADD SEARCH OPTIMIZATION or SYSTEM$ESTIMATE_SEARCH_
   OPTIMIZATION_COSTS failed with an Enterprise Edition error.
A: Confirm this account's edition — same hard prerequisite as 5.6 and
   5.7. If this account is actually Standard Edition, this sub-task isn't
   testable as written.

Q: SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS errored, unrelated to
   edition.
A: Confirm no warehouse is unset (it needs one active, regardless of
   size), and confirm the table doesn't already have search optimization
   enabled on the requested column/method — the function only works
   BEFORE enabling, which is why Step 2 runs ahead of Step 3.

Q: search_optimization_progress stayed at 0 for a long time.
A: Same asynchronous pattern as 5.3's clustering key and 5.7's MV
   refresh — the background build can take anywhere from minutes (small
   tables) to hours (multi-TB tables), per Snowflake's own guidance.
   Given this table's small size (~8 partitions per 5.2/5.3), expect the
   faster end of that range, but don't assume it's instant.

Q: Step 5 showed no improvement at all — same 8/8 partitions_scanned as
   Step 1, and no dedicated search-optimization operator appeared.
A: Confirmed on this workbook, and it's a coherent, explainable result:
   this traces directly back to 5.2's finding that PRODUCT_ID's
   average_depth on this table was 8 out of a possible 8 — the absolute
   worst case, meaning product_id values are scattered across every
   partition already. Search optimization works by skipping partitions
   that DON'T contain a filtered value; if the value is already present
   in ALL partitions, there's nothing to skip, regardless of how good the
   index is. This isn't a search-optimization-specific weakness — it's a
   fundamental limit of partition-level pruning as a strategy for a
   column shaped this way. Test on ORDER_ID instead (Practice Gap #5) to
   confirm: it had room to improve in 5.2 (depth 6.25/8, not the ceiling),
   so it's a fairer test of whether search optimization works AT ALL on
   this table, versus whether THIS column was simply a bad candidate.

Q: Why compare this against 5.3's clustering key result instead of just
   picking one technique?
A: They solve different-shaped problems (Snowflake's own guidance: search
   optimization for point lookups returning few rows, clustering for
   range queries or lookups returning many rows) — comparing both against
   the SAME column on the SAME table is what actually shows when each is
   the better tool, rather than treating them as interchangeable.

Q: Neither PRODUCT_ID nor ORDER_ID showed ANY measurable improvement from
   search optimization on this table — did this sub-task just fail to
   demonstrate the feature at all?
A: No — it demonstrated something more useful than a clean before/after
   win: TWO distinct, legitimate reasons a table can be a poor candidate
   for search optimization, discovered empirically rather than just
   quoted from documentation. PRODUCT_ID: the value exists in every
   partition already (average_depth 8/8 per 5.2), so no pruning technique
   has anything to skip. ORDER_ID: ordinary min/max pruning was already
   finding the optimal answer (5/8) without help. Both trace back to this
   table's small size — only 8 total micro-partitions, a scale where
   there's very little room between "worst case" and "already optimal"
   for search optimization to occupy. This is consistent with every
   storage-optimization feature tested in Goal 5 so far (5.3's clustering
   key, 5.7's materialized view rewrite) showing muted or absent benefit
   on this specific dataset — the honest, recurring conclusion across all
   three is that this table is simply too small to be a realistic
   demonstration case, not that any of these features don't work.
*/
