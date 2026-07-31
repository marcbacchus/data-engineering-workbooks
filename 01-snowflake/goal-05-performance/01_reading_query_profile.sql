/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Sub-task 5.1 : Reading Query Profile
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 25-30 min
  Warehouse size     : WORKBOOK_WH (X-Small)
  Database           : ECOMMERCE.RAW
  Run in             : Snowsight
  Prerequisites      : Goals 1-4 complete, ECOMMERCE tables loaded
  COF-C03 domain     : Performance & Query Optimization (~10-15% of exam)
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════════
/*
Before you can optimize anything, you need to be able to read what Snowflake
already tells you about a query. Query Profile is the single most important
diagnostic tool on the platform — it's where you'll spend most of your time
in Goal 5, because every fix (clustering, warehouse sizing, materialized
views, search optimization) is a response to something Query Profile showed
you first.

Today you will run a deliberately inefficient query, then read its profile
two ways: visually in Snowsight, and programmatically via SQL functions that
expose the same underlying data. The SQL path matters because it's scriptable
— you can build monitoring around it later. The Snowsight path matters
because the operator graph makes bottlenecks obvious in a way raw numbers
don't.
*/


-- ══════════════════════════════════════════════════════════════════════
--  CONCEPT
-- ══════════════════════════════════════════════════════════════════════
/*
Query Profile shows the actual execution plan Snowflake ran — not the plan
it intended to run (that's EXPLAIN, which is a prediction). Profile is a
post-mortem. Each node in the graph is an "operator" (TableScan, Join,
Aggregate, Sort, etc.), and each operator reports:

  - Rows produced / rows scanned
  - Bytes scanned vs. partitions scanned vs. total partitions (pruning)
  - Time spent in that operator, as a % of total query time
  - Bytes spilled to local disk or remote storage (the two red flags)

The single most useful skill in this sub-task is spotting spilling. If an
operator spills to LOCAL STORAGE, the warehouse ran out of memory for that
step and used local SSD instead — slower, but tolerable. If it spills to
REMOTE STORAGE, it ran out of local disk too and is writing to the storage
layer — this is a much bigger performance cliff, and on X-Small it happens
fast on anything with a large intermediate result (unfiltered joins,
wide GROUP BY, ORDER BY over big row counts).

──────────────────────────────────────────────────────────────────────────
Oracle / SQL Server comparison:
  Oracle    : Closest equivalent is an AWR/ASH report plus SQL Trace +
              TKPROF, or Real-Time SQL Monitoring in Enterprise Manager for
              the live operator-level view. TKPROF output is the row-source
              tree with elapsed time per step — same idea as Profile's
              operator graph, just text instead of a rendered DAG.
  SQL Server: Closest equivalent is the Actual Execution Plan (graphical,
              in SSMS) plus sys.dm_exec_query_stats for the historical/
              programmatic view. Spilling maps to "Sort Warnings" /
              tempdb spills you'd catch via sys.dm_exec_query_stats or
              Extended Events — same red flag, different vocabulary.
  Key difference: Snowflake has no indexes, no execution plan hints, and no
  manual statistics collection — Profile is reactive-only. You cannot force
  a different plan the way you'd use an Oracle hint or SQL Server query
  hint; you change the data layout (clustering) or the warehouse
  (size/multi-cluster) and re-run.
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
--  STEP 1 — Run a query worth profiling
-- ══════════════════════════════════════════════════════════════════════
/*
This join is intentionally unfiltered across two large tables so it
produces a profile with something to look at (join fan-out, no pruning).
On X-Small this should still complete — if it runs long, add a LIMIT and
re-run; the point is to generate a profile, not to punish the warehouse.
*/

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


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Find the query in history and grab its QUERY_ID
-- ══════════════════════════════════════════════════════════════════════
/*
INFORMATION_SCHEMA.QUERY_HISTORY is session/account-scoped and near
real-time (unlike SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY, which has up to a
45-minute latency). Use INFORMATION_SCHEMA for anything you want to inspect
immediately after running it, like right now.
*/

SELECT
    query_id,
    query_text,
    total_elapsed_time / 1000 AS elapsed_seconds,
    bytes_scanned,
    rows_produced
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%ORDER_ITEMS%'
ORDER BY start_time DESC
LIMIT 5
;

-- Note: partitions_scanned/partitions_total and the bytes_spilled_* columns
-- are NOT available on this table function — they only exist on the
-- SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY view (up to 45 min latency) and on
-- GET_QUERY_OPERATOR_STATS (Step 3), which is why we pull pruning/spilling
-- from operator stats instead of from here.

-- <copy the query_id from the row you ran in Step 1 — you'll need it below>


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Pull operator-level stats programmatically
-- ══════════════════════════════════════════════════════════════════════
/*
GET_QUERY_OPERATOR_STATS returns the same per-operator data Snowsight
renders as the visual graph. This only works AFTER the query has fully
completed — if it returns empty, the query is likely still running.
*/

SELECT
    operator_id,
    operator_type,
    operator_statistics:output_rows::NUMBER                          AS output_rows,
    operator_statistics:input_rows::NUMBER                           AS input_rows,
    execution_time_breakdown:overall_percentage::FLOAT               AS pct_of_total_time,
    operator_statistics:spilling:bytes_spilled_local_storage::NUMBER  AS spilled_local_bytes,
    operator_statistics:spilling:bytes_spilled_remote_storage::NUMBER AS spilled_remote_bytes
FROM TABLE(GET_QUERY_OPERATOR_STATS('<query_id_from_step_2>'))
ORDER BY pct_of_total_time DESC
;

-- spilling and pruning are only populated on the operator types that
-- actually do that work (spilling on Sort/Aggregate/Join/WindowFunction;
-- pruning on TableScan) — NULL elsewhere is expected, not an error.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Check pruning efficiency
-- ══════════════════════════════════════════════════════════════════════
/*
partitions_scanned vs partitions_total tells you whether Snowflake had to
read the whole table or was able to skip micro-partitions based on the
WHERE clause. On an unfiltered join like Step 1, expect this ratio to be
close to 1.0 (no pruning possible — there was nothing to prune against).
This number becomes your baseline for Sub-task 5.2.
*/

SELECT
    operator_id,
    operator_attributes:table_name::VARCHAR                      AS scanned_table,
    operator_statistics:pruning:partitions_scanned::NUMBER        AS partitions_scanned,
    operator_statistics:pruning:partitions_total::NUMBER          AS partitions_total,
    ROUND(
        operator_statistics:pruning:partitions_scanned::NUMBER
        / NULLIF(operator_statistics:pruning:partitions_total::NUMBER, 0) * 100, 1
    ) AS pct_scanned
FROM TABLE(GET_QUERY_OPERATOR_STATS('<query_id_from_step_2>'))
WHERE operator_type = 'TableScan'
;

-- NOTE: if a table in your query has a row access policy attached (see
-- Goal 4), it will NOT appear here as a TableScan. Instead it shows up as
-- a "DynamicSecureView" operator earlier in the plan, with no pruning
-- stats of its own — the policy has to evaluate its filter logic in front
-- of the scan, so Snowflake represents that as a distinct wrapper operator
-- rather than exposing the underlying scan directly. Confirm with:
--   SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
--       REF_ENTITY_NAME => '<db.schema.table>', REF_ENTITY_DOMAIN => 'TABLE'));
-- On this workbook, ORDERS carries REGION_ACCESS_POLICY (Goal 4), which is
-- why this Step 4 query only returns pruning data for ORDER_ITEMS.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 5 — Compare to EXPLAIN (predicted plan, not actual)
-- ══════════════════════════════════════════════════════════════════════
/*
EXPLAIN never executes the query — it's the optimizer's predicted plan,
useful for checking a query BEFORE you spend credits running it. Compare
this to what Query Profile showed you actually happened in Steps 3-4.
*/

EXPLAIN
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


-- ══════════════════════════════════════════════════════════════════════
--  PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════════
/*
1. Re-run the Step 1 query with a WHERE clause filtering ORDERS to a single
   month. Compare partitions_scanned before/after — quantify the pruning
   gain in Sub-task 5.2 terms.

2. Add a GROUP BY product_id, SUM(quantity) to the Step 1 query. Check
   GET_QUERY_OPERATOR_STATS for an Aggregate operator and see whether it
   spilled to local or remote storage on X-Small.

3. Open Snowsight → Activity → Query History, find the same query_id, and
   open its Query Profile tab. Confirm the operator graph matches what
   GET_QUERY_OPERATOR_STATS returned — identify which single operator
   consumed the highest overall_percentage of execution time.

4. Run the same query twice in a row with no changes. Check
   bytes_scanned on the second run — has result caching kicked in? (This
   sets up Sub-task 5.4.)
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: GET_QUERY_OPERATOR_STATS returned zero rows — why?
A: The query hasn't finished yet, or the query_id is wrong/expired. Query
   history and operator stats are only populated for completed queries;
   re-check query_id in Step 2 and confirm status = 'SUCCESS'.

Q: Step 4 (or my TableScan filter) returned nothing, but Step 3 showed rows
   — one of them was "QUERY RESULT REUSE" instead of a real operator type.
A: The query hit the result cache — Snowflake recognized the exact query
   text and returned the cached result instead of re-executing, so there
   was no scan to profile. Force a real execution first:
     ALTER SESSION SET USE_CACHED_RESULT = FALSE;
     <run the query>
     ALTER SESSION SET USE_CACHED_RESULT = TRUE;
   then re-pull the query_id from Step 2 (it will be a new ID) and re-run
   Steps 3/4 against that one. This is expected behavior, not a bug — and
   it's a preview of what Sub-task 5.4 (result caching) covers directly.

Q: A table I queried shows up as "DynamicSecureView" instead of
   "TableScan", with no pruning stats — what happened to it?
A: That table has a row access policy attached (see Goal 4). The policy
   has to evaluate its filter condition in front of the scan, so Snowflake
   represents that as a separate wrapper operator rather than exposing the
   underlying TableScan directly — which means you can't check pruning on
   that table through operator stats the normal way. The fastest
   confirmation is EXPLAIN itself: the operator's OBJECTS column names it
   directly, e.g. "ORDERS (+ RowAccessPolicy)" — no need to query
   POLICY_REFERENCES separately unless you want the policy name too:
     SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
         REF_ENTITY_NAME => '<db.schema.table>', REF_ENTITY_DOMAIN => 'TABLE'));
   Also note: EXPLAIN's GlobalStats partitionsTotal/partitionsAssigned only
   reflects the tables that appear as real TableScan operators — a
   policy-protected table contributes nothing to those global pruning
   numbers, at both the static (EXPLAIN) and dynamic (operator stats)
   level. Worth remembering for Sub-task 5.3 (clustering keys): if you
   cluster a table that has a row access policy on it, verifying the
   pruning improvement via EXPLAIN or GET_QUERY_OPERATOR_STATS won't work
   the usual way — you'll need Snowsight's Query Profile UI, or a
   temporary unpoliced copy of the table, to see the raw TableScan
   pruning numbers.

Q: I don't see any spilling anywhere, even on the big unfiltered join —
   is that normal?
A: Yes, on X-Small this specific join over ~10M rows may still fit in
   memory depending on row width. If you want to force spilling for
   practice, remove the LIMIT or add a wide GROUP BY with many distinct
   keys — that's a good Practice Gap variant.

Q: What's the difference between bytes_spilled_local_storage and
   bytes_spilled_remote_storage in practical terms?
A: Local spill uses the warehouse's attached SSD — a performance hit but
   contained. Remote spill writes to cloud storage over the network — this
   is the one to actually worry about, and the one that scaling up the
   warehouse (5.5) or reducing the working set (better filtering,
   clustering) is meant to prevent. Both live under the "spilling" key of
   operator_statistics (Step 3) — not on INFORMATION_SCHEMA.QUERY_HISTORY(),
   which doesn't expose spill data at all.

Q: Why use INFORMATION_SCHEMA.QUERY_HISTORY here instead of
   SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY?
A: ACCOUNT_USAGE has up to 45 minutes of latency and requires the
   ACCOUNTADMIN role (or an explicit grant) by default — not useful for
   "what just happened." INFORMATION_SCHEMA is near-real-time and scoped
   to what your current role can see, which is what you want immediately
   after running a query.
*/
