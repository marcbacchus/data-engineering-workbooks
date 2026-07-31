/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Sub-task 5.3 : Clustering Keys
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 30-35 min
  Warehouse size     : WORKBOOK_WH (X-Small) — reclustering itself runs on
                        Snowflake-managed serverless compute, NOT this
                        warehouse; WORKBOOK_WH is only used for the setup/
                        query steps below
  Database           : ECOMMERCE.RAW
  Run in             : Snowsight
  Prerequisites      : Sub-task 5.2 complete — this picks up exactly where
                        5.2 left off: PRODUCT_ID filters on ORDER_ITEMS
                        scanned 8/8 partitions (zero pruning) due to poor
                        natural clustering
  COF-C03 domain     : Performance & Query Optimization (~10-15% of exam)
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════════
/*
5.2 measured the problem: PRODUCT_ID filters on ORDER_ITEMS get zero
pruning benefit, because product IDs are scattered evenly across every
micro-partition. A clustering key is Snowflake's mechanism for fixing
that — you tell it which column(s) should be physically co-located, and a
background service incrementally reorganizes micro-partitions over time to
make that true.

This costs real (serverless) credits, so — matching the plan from the
start of Goal 5 — today's test runs against a throwaway clone of
ORDER_ITEMS, not the production table. We'll add a clustering key on
PRODUCT_ID, watch what happens to clustering quality and pruning, check
what it cost, then drop the clone. Nothing here touches the real
ORDER_ITEMS table other than read-only SELECTs.
*/


-- ══════════════════════════════════════════════════════════════════════
--  CONCEPT
-- ══════════════════════════════════════════════════════════════════════
/*
A clustering key is declared with CLUSTER BY (col1 [, col2 ...]) — either
at CREATE TABLE time or added later with ALTER TABLE ... CLUSTER BY. Once
defined, Snowflake's automatic clustering service monitors the table in
the background and incrementally re-sorts micro-partitions to keep the
clustered column(s) well-organized, WITHOUT locking the table or requiring
you to run anything manually.

Key mechanics worth knowing before you turn one on:
  - It's asynchronous. Adding a clustering key does not instantly
    reorganize the table — the service picks up the work over time, on
    Snowflake's own serverless compute (separate from any warehouse you
    own).
  - It's incremental. Once a micro-partition is well-clustered relative to
    the key, the service leaves it alone — SYSTEM$CLUSTERING_INFORMATION's
    total_constant_partition_count tracks this. This is why reclustering a
    large table is usually far cheaper than a full manual re-sort would
    be, and cheaper the second time than the first.
  - It costs credits every time it runs, indefinitely, for as long as the
    key exists — this isn't a one-time cost. That's the actual tradeoff:
    faster reads on the clustered column(s) vs. an ongoing background
    credit spend that scales with how much new/updated data keeps drifting
    the table out of clustered order.
  - There is no manual "recluster now" command. You cannot force an
    immediate reorganization — clustering is fully managed, background-
    only. (Older Snowflake versions had a manual RECLUSTER command; it's
    been fully superseded by the automatic service.)

Given 5.2's finding — this exact table only has 8 total micro-partitions —
this sub-task is honestly a marginal candidate for a real clustering key in
production. That's intentional: it's cheap and safe to test the mechanics
on, and the CONCEPT/WHAT IF sections below address directly when a
clustering key is and isn't worth it size-wise.

──────────────────────────────────────────────────────────────────────────
Oracle / SQL Server comparison:
  Oracle    : Closest equivalent is partition maintenance (SPLIT/MERGE
              PARTITION) or an index rebuild — both are explicit,
              DBA-triggered operations, typically requiring a maintenance
              window, and Oracle gives you direct manual control over
              exactly when the work happens.
  SQL Server: Similarly, ALTER INDEX ... REBUILD/REORGANIZE is manual and
              scheduled by a DBA (via a maintenance plan or Agent job) —
              same story, you decide exactly when.
  Key difference: neither Oracle nor SQL Server has a background service
  that decides on its own, continuously and automatically, whether and
  when to reorganize data — you're always the one pulling the trigger.
  Snowflake's automatic clustering removes that manual control entirely in
  exchange for removing the maintenance burden; the only lever you have is
  whether the clustering key exists at all.
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
--  STEP 1 — Create a throwaway clone to test on
-- ══════════════════════════════════════════════════════════════════════
/*
Zero-copy clone: near-instant, no data duplication cost. Everything from
here on happens against this clone, never against the real ORDER_ITEMS.
*/

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST
    CLONE ECOMMERCE.RAW.ORDER_ITEMS
;

-- Confirm the clone's starting clustering quality matches 5.2's baseline
-- for PRODUCT_ID before we change anything:
SELECT
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST', '(PRODUCT_ID)')):average_depth::FLOAT           AS average_depth,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST', '(PRODUCT_ID)')):average_overlaps::FLOAT       AS average_overlaps,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST', '(PRODUCT_ID)')):total_partition_count::NUMBER  AS total_partition_count
;
-- Expected: same as 5.2 Step 1 (depth 8/8) — a clone inherits the source
-- table's physical layout exactly.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Add the clustering key
-- ══════════════════════════════════════════════════════════════════════

ALTER TABLE ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST
    CLUSTER BY (PRODUCT_ID)
;

-- Confirm the key registered:
SHOW TABLES LIKE 'ORDER_ITEMS_CLUSTER_TEST' IN SCHEMA ECOMMERCE.RAW;
-- Check the "cluster_by" column in the output.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Check clustering quality immediately (expect no change yet)
-- ══════════════════════════════════════════════════════════════════════
/*
This is checking that the ASYNC nature of clustering is real, not a
mistake. Because a clustering key is now defined, the table name alone is
enough for the function to use it automatically — no column argument
needed.
*/

SELECT
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST')):average_depth::FLOAT          AS average_depth,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST')):average_overlaps::FLOAT      AS average_overlaps,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST')):total_constant_partition_count::NUMBER AS constant_partitions,
    PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST')):notes::VARCHAR                AS notes
;

-- Report whatever this actually shows — don't assume it's unchanged just
-- because the CONCEPT section said "asynchronous." On a tiny 8-partition
-- table, the background service may act fast enough that you already see
-- movement by the time you run this. Either result is informative.

-- ACTUAL RESULT: average_depth = 3, average_overlaps = 2, constant_partitions = 0
-- Two findings here, both real:
--
-- 1. The background service already acted — fast. Depth went from 8 → 3
--    and overlaps from 7 → 2 in the time it took to run Step 2 and this
--    query. On a table this small, "asynchronous" apparently means
--    seconds/minutes, not hours — clearly not a rule to generalize to
--    large production tables, but useful to know it's not always a long
--    wait either. constant_partitions = 0 means none of the 8 partitions
--    have been marked "done" yet — expect that number to rise as
--    reclustering continues (check again later, or via Step 4).
--
-- 2. The "notes" field returned an actual cardinality warning:
--    "Clustering key columns contain high cardinality key PRODUCT_ID
--    which might result in expensive re-clustering." This is Snowflake
--    proactively flagging that PRODUCT_ID likely has many distinct
--    values relative to the table's row count — a real, general-purpose
--    signal for clustering key SELECTION (lower-cardinality columns
--    generally recluster more cheaply and stably), and it fired even on
--    this tiny 8-partition test table, not just at production scale.
--    Worth carrying forward: check this notes field on ANY real
--    clustering key candidate before committing to it in production.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Check automatic clustering activity and cost
-- ══════════════════════════════════════════════════════════════════════
/*
ACCOUNT_USAGE views carry latency (up to 3 hours for this one per
Snowflake's docs) and require either ACCOUNTADMIN or an explicit grant on
the IMPORTED PRIVILEGES of the SNOWFLAKE database — per the Goal 4
discovery that documented "SECURITYADMIN or higher" minimums in this
account consistently needed ACCOUNTADMIN instead, test this directly
rather than assuming SYSADMIN can see it.
*/

USE ROLE ACCOUNTADMIN;

SELECT
    start_time,
    end_time,
    table_name,
    credits_used,
    num_bytes_reclustered,
    num_rows_reclustered
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE table_name = 'ORDER_ITEMS_CLUSTER_TEST'
ORDER BY start_time DESC
;

USE ROLE SYSADMIN;

-- If this returns nothing, it likely just means reclustering hasn't run
-- yet (or the ~3hr view latency hasn't caught up) — not that nothing
-- will happen. Re-check later rather than assuming zero cost.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 5 — Re-run the 5.2 pruning test against the clone
-- ══════════════════════════════════════════════════════════════════════
/*
Same methodology as 5.2 Steps 3-4: force a fresh execution, filter on a
single PRODUCT_ID value, check actual pruning. Run this once right after
Step 2 (likely still near 8/8, matching Step 3's finding), and again later
after giving the background service time to work — the delta between
those two runs is the real before/after you're after.
*/

-- 5a. Grab a real product_id to filter on
SELECT product_id FROM ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST LIMIT 1;

-- 5b. Force a fresh execution
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT *
FROM ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST
WHERE product_id = '<product_id_from_5a>'
;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

-- 5c. Grab the query_id
SELECT query_id, query_text, total_elapsed_time / 1000 AS elapsed_seconds
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%ORDER_ITEMS_CLUSTER_TEST%WHERE product_id%'
ORDER BY start_time DESC
LIMIT 3
;

-- 5d. Check actual pruning
SELECT
    operator_id,
    operator_attributes:table_name::VARCHAR                 AS scanned_table,
    operator_statistics:pruning:partitions_scanned::NUMBER    AS partitions_scanned,
    operator_statistics:pruning:partitions_total::NUMBER      AS partitions_total,
    ROUND(
        operator_statistics:pruning:partitions_scanned::NUMBER
        / NULLIF(operator_statistics:pruning:partitions_total::NUMBER, 0) * 100, 1
    ) AS pct_scanned
FROM TABLE(GET_QUERY_OPERATOR_STATS('<query_id_from_5c>'))
WHERE operator_type = 'TableScan'
;

-- ACTUAL RESULT: partitions_scanned = 2, partitions_total = 3 → 66.7% scanned
--
-- IMPORTANT — don't compare 66.7% against 5.2's 100% at face value: the
-- TOTAL changed too. Before clustering, this table had 8 micro-partitions
-- (5.2's baseline); after reclustering, it now has only 3. Reclustering
-- doesn't just re-sort rows within existing partitions — it physically
-- deletes and re-inserts affected rows into a NEW set of micro-partitions
-- as part of grouping PRODUCT_ID values together, so the total partition
-- count itself can shrink (or grow) as a side effect.
--
-- The pct_scanned metric alone actually understates the real improvement
-- here — compare ABSOLUTE partitions read instead:
--   Before clustering (5.2): 8 of 8 partitions scanned  → 8 partitions read
--   After clustering  (5.3): 2 of 3 partitions scanned  → 2 partitions read
-- That's a genuine ~75% reduction in the actual amount of data this query
-- has to touch — a bigger win than the raw percentages (100% vs 66.7%)
-- suggest on their own, precisely because the denominator moved.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 6 — Clean up (this was always a throwaway test object)
-- ══════════════════════════════════════════════════════════════════════
/*
Dropping the clustering key stops future reclustering credit spend
immediately; dropping the table removes it entirely. Do this once you're
satisfied with the before/after comparison — no need to leave this object
around accumulating background cost.
*/

ALTER TABLE ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST DROP CLUSTERING KEY;

DROP TABLE ECOMMERCE.RAW.ORDER_ITEMS_CLUSTER_TEST;


-- ══════════════════════════════════════════════════════════════════════
--  PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════════
/*
1. Re-create the clone and try ALTER TABLE ... SUSPEND RECLUSTER, then
   RESUME RECLUSTER — confirm both run without error and check what SHOW
   TABLES reports for the table's reclustering state in between.

2. Step 3 already confirmed the cardinality warning fires on PRODUCT_ID
   alone. Try a composite clustering key instead, e.g.
   CLUSTER BY (PRODUCT_ID, ORDER_ID) — does adding a second column change
   or clear the warning, or make it worse?

3. Check SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY across your
   WHOLE account (drop the table_name filter) — is ORDER_ITEMS_CLUSTER_TEST
   the only thing that's ever triggered reclustering, or is anything else
   in this trial account generating background credit spend you didn't
   expect?

4. Using CREATE TABLE ... CLUSTER BY (col) syntax (declaring the key at
   creation time instead of ALTER TABLE afterward) — does clustering
   quality on a freshly-created, freshly-loaded table differ from what you
   saw altering an existing one in Step 2?
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: SYSTEM$CLUSTERING_INFORMATION in Step 3 already showed improvement,
   almost immediately — is that expected?
A: Yes, on a table this small. This workbook's actual Step 3 result went
   from depth 8/overlaps 7 (Step 1) to depth 3/overlaps 2 within roughly
   the time it took to run Step 2 and check. With only 8 micro-partitions
   to reorganize, the background service has very little work to do, so
   it can act almost immediately — that's specific to small tables, not a
   rule to expect at production scale (a multi-TB table with billions of
   rows won't fully recluster nearly this fast). constant_partitions
   staying at 0 in this same result means the service hasn't yet marked
   any partition "done" — expect that to rise on a later check.

Q: The "notes" field warned about high cardinality on PRODUCT_ID — should
   I be concerned?
A: Take it seriously, but it's not disqualifying by itself — it's
   Snowflake telling you PRODUCT_ID likely has many distinct values
   relative to row count, which tends to make ongoing reclustering more
   expensive over time (more distinct values means more potential
   partition churn as new data lands). This is real, general guidance for
   clustering key selection, not a false alarm: prefer lower-cardinality
   columns, or a leading lower-cardinality column in a composite key
   (e.g. a date/category column before a high-cardinality ID), when
   choosing a real production clustering key. Combined with 5.2's finding
   that this table is a marginal size candidate anyway, this specific
   PRODUCT_ID-only key is a reasonable one to test and drop, not one to
   keep.

Q: Step 4 (AUTOMATIC_CLUSTERING_HISTORY) came back empty.
A: Most likely reclustering simply hasn't run yet — it's asynchronous and
   the view itself has additional latency on top of that. It can also mean
   your role can't see SNOWFLAKE.ACCOUNT_USAGE at all yet — confirm
   ACCOUNTADMIN (or a role granted IMPORTED PRIVILEGES on the SNOWFLAKE
   database) can query it, per the Goal 4 privilege-minimum discovery.
   Don't treat an empty result as "it cost nothing" without ruling out
   both causes first.

Q: Step 5's partitions_total came back different (3) than 5.2's baseline
   (8) — is that a bug in the comparison?
A: No — this is real and worth remembering for any future before/after
   pruning comparison: reclustering physically deletes and re-inserts
   affected rows into a new set of micro-partitions, so the TOTAL
   partition count can change as a side effect of clustering, not just
   the arrangement of values within a fixed set of partitions. When
   comparing pruning before/after a clustering change, look at absolute
   partitions_scanned (data actually read), not just pct_scanned, since
   the denominator itself may have moved.

Q: Do I need to worry about credits from this test given I'm on a trial
   account?
A: The Step 6 cleanup (DROP CLUSTERING KEY, then DROP TABLE) stops any
   further reclustering spend the moment you run it. The exposure window
   is only between Step 2 (key added) and Step 6 (key dropped) — keep that
   window short, and check Step 4's actual credits_used once it populates
   so you know exactly what this sub-task cost, rather than guessing.

Q: Why clone instead of just testing directly on ORDER_ITEMS?
A: Matches the Goal 5 plan set at the start: clustering key changes affect
   the real table's physical layout and trigger ongoing background cost,
   so anything experimental happens on a disposable clone that gets
   dropped when you're done, leaving the production table and its Goal
   3/4 dependencies untouched.
*/
