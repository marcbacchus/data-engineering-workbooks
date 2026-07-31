/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Sub-task 5.2 : Micro-partitions & Pruning
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 25-30 min
  Warehouse size     : WORKBOOK_WH (X-Small)
  Database           : ECOMMERCE.RAW
  Run in             : Snowsight
  Prerequisites      : Sub-task 5.1 complete (EXPLAIN / GET_QUERY_OPERATOR_STATS
                        pruning methodology carries over directly here)
  COF-C03 domain     : Performance & Query Optimization (~10-15% of exam)
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════════
/*
5.1 showed you how to READ pruning stats. This sub-task is about
understanding WHERE those stats come from: micro-partitions, the storage
unit underneath every Snowflake table, and why a query either skips most of
a table or has to read all of it.

You'll inspect the natural clustering of ECOMMERCE.RAW.ORDER_ITEMS using
SYSTEM$CLUSTERING_INFORMATION, then compare pruning on an unfiltered query
against a filtered one to see the metadata-pruning mechanism actually work.
No clustering KEY gets created in this sub-task — that's 5.3. Today is
about reading the clustering Snowflake already gave you for free, based on
how data landed on disk during load.
*/


-- ══════════════════════════════════════════════════════════════════════
--  CONCEPT
-- ══════════════════════════════════════════════════════════════════════
/*
Every Snowflake table is physically stored as a set of immutable
micro-partitions — contiguous units of storage, roughly 50-500MB of
uncompressed data each, stored in a compressed columnar format. Snowflake
creates these automatically as data is loaded; there's no manual partition
DDL, no partition maintenance job, no "add partition" statement.

For every column in every micro-partition, Snowflake stores metadata: the
MIN and MAX value present in that partition for that column. When a query
has a WHERE clause, the optimizer checks this metadata BEFORE reading any
actual data — if a partition's min/max range can't possibly satisfy the
filter, that partition is skipped entirely. This is pruning, and it's why
partitions_scanned can be far lower than partitions_total.

Clustering is about how well-sorted a column's values are ACROSS
partitions. If a column's values are scattered randomly across every
partition (poor clustering), the min/max ranges overlap heavily and
pruning barely helps — most partitions have to be scanned anyway even with
a narrow filter. If a column's values are naturally grouped together in
sequential partitions (good clustering — like an auto-incrementing ID
loaded in order), a filter on that column can skip the vast majority.

SYSTEM$CLUSTERING_INFORMATION quantifies this with two key metrics:
  - average_depth  : average number of partitions containing any given
                      value's range for the given column. Lower is better
                      (a value of 1 means every value lives in exactly one
                      partition — ideal).
  - average_overlaps: average number of other partitions whose range
                      overlaps with a given partition's range, for the
                      given column. Lower is better.

──────────────────────────────────────────────────────────────────────────
Oracle / SQL Server comparison:
  Oracle    : Partitioning is explicit and manual — you declare
              PARTITION BY RANGE/LIST/HASH at table creation, and adding,
              splitting, or merging partitions is a DBA maintenance task.
              Oracle also supports indexes, which Snowflake does not use
              at all; pruning here is Snowflake's closest equivalent to
              Oracle's partition pruning, but automatic and metadata-only.
  SQL Server: Similarly manual — partition functions and partition schemes
              are explicitly defined and mapped to filegroups, with
              ongoing index/statistics maintenance required for the
              optimizer to prune effectively.
  Key difference: Snowflake micro-partitioning requires zero DDL and zero
  maintenance to exist — every table has it automatically. What you DO
  control is data layout (load order, or an explicit CLUSTER BY key in
  5.3) to influence how well pruning works, not whether partitioning
  exists at all.
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  SETUP
-- ══════════════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 1 — Check natural clustering on a candidate column
-- ══════════════════════════════════════════════════════════════════════
/*
ORDER_ITEMS has no row access policy (unlike ORDERS in 5.1), so its
TableScan pruning stats are directly visible — a cleaner table to learn
pruning mechanics on before 5.3 introduces an actual clustering key.

PRODUCT_ID is the candidate here: a common real-world filter pattern is
"show me all order lines for product X" (returns/inventory/analytics
queries), and product_id was NOT the load order for this table, so it's a
reasonable guess for naturally poor clustering. Adjust the column below if
you want to test a different one.
*/

SELECT SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS', '(PRODUCT_ID)');

-- The function returns a single VARCHAR containing JSON text, not a parsed
-- object — wrap in PARSE_JSON to pull out individual fields directly:
SELECT
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS', '(PRODUCT_ID)')):average_depth::FLOAT     AS average_depth,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS', '(PRODUCT_ID)')):average_overlaps::FLOAT AS average_overlaps,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS', '(PRODUCT_ID)')):total_partition_count::NUMBER AS total_partition_count
;

-- <if this errors on the column name, run the following to confirm actual
--  column names on ORDER_ITEMS, then substitute below>
-- DESCRIBE TABLE ECOMMERCE.RAW.ORDER_ITEMS;

-- ACTUAL RESULT on this workbook's data (8 total micro-partitions):
--   average_depth = 8, average_overlaps = 7, total_partition_count = 8
-- Read this against the max possible: with only 8 partitions, the worst
-- case is average_depth = 8 (every partition's PRODUCT_ID range overlaps
-- with every other partition — a filter on any single product_id could
-- theoretically require scanning ALL 8, since there's no partition where
-- that value's range doesn't potentially appear). Hitting that max exactly
-- means PRODUCT_ID has effectively zero natural clustering on this table:
-- product IDs are scattered evenly across every partition rather than
-- grouped. average_overlaps = 7 confirms it — 7 is literally "overlaps
-- with all 7 OTHER partitions," i.e. total overlap.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Compare against the table's natural load-order column
-- ══════════════════════════════════════════════════════════════════════
/*
ORDER_ID is likely close to load order (sequential inserts as orders came
in), so it should show much better natural clustering than PRODUCT_ID —
lower average_depth, lower average_overlaps. This comparison is the whole
point of the sub-task: same table, two columns, very different pruning
potential.
*/

SELECT
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS', '(ORDER_ID)')):average_depth::FLOAT     AS average_depth,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS', '(ORDER_ID)')):average_overlaps::FLOAT AS average_overlaps,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS', '(ORDER_ID)')):total_partition_count::NUMBER AS total_partition_count
;

-- ACTUAL RESULT on this workbook's data:
--   average_depth = 6.25, average_overlaps = 5.25, total_partition_count = 8
-- Better than PRODUCT_ID (8 / 7), but "better" is relative here — 6.25 out
-- of a possible 8 is still poor clustering in absolute terms, not the
-- near-1 "ideal" the CONCEPT section describes. Reading the comparison:
--   - ORDER_ID:   depth 6.25 / 8  → ~78% of worst-case (some grouping exists)
--   - PRODUCT_ID: depth 8    / 8  → 100% of worst-case (zero grouping)
-- The gap between them is the real signal: ORDER_ID rows landed on disk in
-- something closer to insert order (as expected for an auto-incrementing
-- or sequentially-issued ID), so a filter on ORDER_ID has a better chance
-- of skipping partitions than the same filter shape on PRODUCT_ID — even
-- though neither column would be called "well-clustered" on its own. This
-- is the baseline Step 3/4 will test directly, and what a clustering key
-- in 5.3 would exist to improve upon.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Run a filtered query on the naturally well-clustered column
-- ══════════════════════════════════════════════════════════════════════
/*
Pick an order_id you know exists (check Step 3a first if you don't have
one handy), then force a fresh execution and check actual pruning via the
5.1 methodology.
*/

-- 3a. Grab a real order_id to filter on
SELECT order_id FROM ECOMMERCE.RAW.ORDER_ITEMS LIMIT 1;

-- 3b. Force a fresh execution (bypass result cache, per the 5.1 discovery)
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT *
FROM ECOMMERCE.RAW.ORDER_ITEMS
WHERE order_id = '<order_id_from_3a>'
;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

-- 3c. Grab the query_id
SELECT query_id, query_text, total_elapsed_time / 1000 AS elapsed_seconds
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%WHERE order_id%'
ORDER BY start_time DESC
LIMIT 3
;

-- 3d. Check actual pruning on this filtered query
SELECT
    operator_id,
    operator_attributes:table_name::VARCHAR                AS scanned_table,
    operator_statistics:pruning:partitions_scanned::NUMBER   AS partitions_scanned,
    operator_statistics:pruning:partitions_total::NUMBER     AS partitions_total,
    ROUND(
        operator_statistics:pruning:partitions_scanned::NUMBER
        / NULLIF(operator_statistics:pruning:partitions_total::NUMBER, 0) * 100, 1
    ) AS pct_scanned
FROM TABLE(GET_QUERY_OPERATOR_STATS('<query_id_from_3c>'))
WHERE operator_type = 'TableScan'
;

-- ACTUAL RESULT: partitions_scanned = 5, partitions_total = 8 → 62.5% scanned
-- A single-value filter on ORDER_ID skipped 3 of 8 partitions (37.5%
-- pruned). That's real, working pruning — but notice it's actually BETTER
-- than Step 2's raw clustering ratio (6.25/8 = 78%) would suggest. This is
-- expected: average_depth is an aggregate across ALL values of the column,
-- while a single filtered query only cares about the partitions touching
-- ONE specific value's range, which can prune better or worse than the
-- table-wide average depending on where that particular value happens to
-- land. Keep this number (62.5%) as your baseline — compare directly
-- against Step 4d's result on PRODUCT_ID below.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Run the same shape of filter on the poorly-clustered column
-- ══════════════════════════════════════════════════════════════════════
/*
Same pattern, filtering on PRODUCT_ID instead. Expect a higher
pct_scanned than Step 3 if Step 1's clustering info showed PRODUCT_ID is
less naturally clustered than ORDER_ID.
*/

-- 4a. Grab a real product_id to filter on
SELECT product_id FROM ECOMMERCE.RAW.ORDER_ITEMS LIMIT 1;

-- 4b. Force a fresh execution
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT *
FROM ECOMMERCE.RAW.ORDER_ITEMS
WHERE product_id = '<product_id_from_4a>'
;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

-- 4c. Grab the query_id
SELECT query_id, query_text, total_elapsed_time / 1000 AS elapsed_seconds
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%WHERE product_id%'
ORDER BY start_time DESC
LIMIT 3
;

-- 4d. Check actual pruning on this filtered query
SELECT
    operator_id,
    operator_attributes:table_name::VARCHAR                AS scanned_table,
    operator_statistics:pruning:partitions_scanned::NUMBER   AS partitions_scanned,
    operator_statistics:pruning:partitions_total::NUMBER     AS partitions_total,
    ROUND(
        operator_statistics:pruning:partitions_scanned::NUMBER
        / NULLIF(operator_statistics:pruning:partitions_total::NUMBER, 0) * 100, 1
    ) AS pct_scanned
FROM TABLE(GET_QUERY_OPERATOR_STATS('<query_id_from_4c>'))
WHERE operator_type = 'TableScan'
;

-- ACTUAL RESULT: partitions_scanned = 8, partitions_total = 8 → 100% scanned
-- Zero pruning. Every partition had to be read even for a single
-- product_id value — this is the direct, practical consequence of Step 1's
-- clustering finding (average_depth = 8/8, the worst possible). Put side
-- by side with Step 3d:
--   ORDER_ID   filter → 5/8 scanned (62.5%) — 3 partitions pruned
--   PRODUCT_ID filter → 8/8 scanned (100%)  — 0 partitions pruned
-- Same table, same filter shape (single-value equality), same warehouse —
-- the only variable is which column is naturally better organized on
-- disk. This gap is exactly what an explicit CLUSTER BY key (5.3) exists
-- to close: if PRODUCT_ID filters are common in this workload, clustering
-- ORDER_ITEMS by PRODUCT_ID would aim to bring that 100% down toward
-- something closer to ORDER_ID's 62.5%, or better.


-- ══════════════════════════════════════════════════════════════════════
--  PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════════
/*
1. Run SYSTEM$CLUSTERING_INFORMATION against CREATED_AT on ORDERS (the row
   access policy table from 5.1). Does the function even run, or does the
   policy block it the way it blocked TableScan visibility? Report what
   actually happens — this determines whether clustering analysis is
   possible at all on policy-protected tables.

2. Compare partition_depth_histogram between Steps 1 and 2's output — not
   just the average_depth summary number. What does the shape of the
   histogram tell you that the average alone doesn't?

3. Try SYSTEM$CLUSTERING_INFORMATION with a two-column composite key, e.g.
   '(ORDER_ID, PRODUCT_ID)' — does clustering on a composite behave like
   you'd expect from the individual single-column results in Steps 1-2?

4. Using the pct_scanned results from Steps 3d and 4d, calculate roughly
   how many fewer partitions get scanned on ORDER_ID lookups vs PRODUCT_ID
   lookups on this table at current size. This becomes your "before"
   baseline to compare against once a clustering key is added in 5.3.
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: SYSTEM$CLUSTERING_INFORMATION returned an error.
A: The most common cause is the column argument not being wrapped in
   parentheses as its own string — it must be '(PRODUCT_ID)', not
   'PRODUCT_ID' or PRODUCT_ID unquoted. The table name argument also needs
   to resolve given your current database/schema context (fully qualify it
   as done here to avoid ambiguity). If it still fails, run DESCRIBE TABLE
   ECOMMERCE.RAW.ORDER_ITEMS to confirm the exact column name exists.

Q: average_depth came back close to total_partition_count for BOTH
   columns (e.g. 8/8 and 6.25/8) — did I do something wrong?
A: No — this is the actual result on this workbook's ~10M-row ORDER_ITEMS
   table, and it's a legitimate (if slightly disappointing-looking)
   finding, not an error. With only 8 total micro-partitions, there's very
   little room for values to be meaningfully grouped — even the "better"
   column here (ORDER_ID) is still closer to worst-case than to the ideal
   depth-near-1 scenario described in the CONCEPT section. Compare the two
   RELATIVE to each other and to total_partition_count, not against an
   abstract ideal: the gap between 8/8 and 6.25/8 is the real signal, and
   it's also a preview of a genuine 5.3 question — on a table this small,
   is an explicit clustering key even worth the reclustering credits it
   would cost? Small tables are often a case where the answer is no.

Q: Do I need to run the ALTER SESSION cache-bypass every time now?
A: Only when you specifically want a guaranteed fresh execution to inspect
   real scan/pruning behavior, as in Steps 3-4 here. Day-to-day, leave
   USE_CACHED_RESULT at its default (TRUE) — the cache is a feature, not
   something to routinely work around, and Sub-task 5.4 covers when and
   why to rely on it.

Q: Why filter on a single row_id/product_id instead of a range?
A: A single-value equality filter gives the cleanest possible pruning
   signal — no ambiguity about partial-partition overlap the way a range
   filter can introduce. Once you're comfortable reading the pct_scanned
   result this way, try substituting a BETWEEN or > filter as a Practice
   Gap variant and see whether the pruning ratio changes.
*/
