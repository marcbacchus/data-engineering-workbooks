/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Sub-task 5.7 : Materialized Views
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 30-35 min
  Warehouse size     : WORKBOOK_WH (X-Small) — materialized view maintenance
                        itself runs on Snowflake's own MATERIALIZED_VIEW_
                        MAINTENANCE serverless warehouse, not this one
  Database           : ECOMMERCE.RAW
  Run in             : Snowsight
  Prerequisites      : Sub-tasks 5.1-5.6 complete. Materialized views require
                        Enterprise Edition — confirmed available on this
                        account (same requirement as 5.6's multi-cluster
                        warehouses).
  COF-C03 domain     : Performance & Query Optimization (~10-15% of exam)
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════════
/*
A materialized view (MV) precomputes and stores a query's result, then
maintains it automatically in the background as the underlying table
changes — unlike a normal view, which recomputes from scratch every time
it's queried. Today you'll build one over a common real pattern (a
per-product aggregate), confirm Snowflake's optimizer can transparently
redirect a matching query to it WITHOUT you referencing the MV by name,
then test what happens when the base table changes.

Per the established Goal 5 pattern: anything involving DML on test data
happens on a throwaway clone, never on the real ORDER_ITEMS table.
*/


-- ══════════════════════════════════════════════════════════════════════
--  CONCEPT
-- ══════════════════════════════════════════════════════════════════════
/*
A materialized view stores its result set as an actual physical structure
(closer to a table than a view, despite the name) and is kept up to date
by a Snowflake-managed background service whenever the base table's data
changes — similar in spirit to automatic clustering (5.3): asynchronous,
serverless, billed separately from your warehouse, and with no manual
"refresh now" trigger you control directly.

Query rewrite is the key feature: if you write a query against the BASE
TABLE that the optimizer recognizes as equivalent to (or a subset of) an
existing materialized view's definition, it can automatically substitute
the MV — even if your query never mentions the MV's name. This is
different from explicitly querying a view.

Restrictions are significant and worth knowing before reaching for one:
  - SINGLE TABLE ONLY. No joins, not even self-joins. This is probably the
    biggest practical limitation — a lot of real reporting queries join
    multiple tables, and those simply aren't eligible for a materialized
    view at all.
  - No subqueries, no window functions, no HAVING, no ORDER BY, no LIMIT.
  - Only a limited subset of aggregate functions is supported (MIN, MAX,
    SUM, COUNT, AVG, and a few others — check current docs for the exact
    list, as it's the kind of thing Snowflake extends periodically).
  - No non-deterministic functions (CURRENT_TIMESTAMP(), RANDOM(), etc.).
  - Read-only — no direct INSERT/UPDATE/DELETE against the MV itself.
  - Best suited for queries where the result is small relative to the base
    table (aggregates, projections, filters) over data that doesn't change
    constantly — the CONCEPT payoff shrinks fast on high-churn tables,
    since every DML on the base table can trigger a refresh.

Cost model: refresh credits are billed under a Snowflake-provided virtual
warehouse called MATERIALIZED_VIEW_MAINTENANCE — NOT your own warehouse,
and NOT controllable by a resource monitor on your warehouse (5.9 covers
resource monitors, but they can't govern this one). Refresh history and
credit cost are visible via SNOWFLAKE.ACCOUNT_USAGE.MATERIALIZED_VIEW_
REFRESH_HISTORY, with the by-now-familiar ACCOUNTADMIN/MONITOR USAGE
privilege requirement and up to 3 hours of latency.

──────────────────────────────────────────────────────────────────────────
Oracle / SQL Server comparison:
  Oracle    : Oracle materialized views are considerably more flexible —
              they DO support joins, and refresh behavior is explicit and
              configurable (ON COMMIT vs ON DEMAND, FAST/COMPLETE/FORCE
              refresh modes), with query rewrite often needing to be
              explicitly enabled or hinted.
  SQL Server: Indexed Views are the closest analogue — they support INNER
              joins (though not outer joins) under strict conditions
              (SCHEMABINDING required, all functions deterministic), and
              are refreshed synchronously as part of the same transaction
              that modifies the base table, not asynchronously in the
              background.
  Key difference: Snowflake's single-table-only restriction is notably
  tighter than either Oracle or SQL Server's materialized/indexed views,
  which both allow joins under some conditions. In exchange, Snowflake's
  refresh is fully automatic and asynchronous — you configure nothing
  about WHEN it refreshes, unlike Oracle's explicit refresh scheduling or
  SQL Server's synchronous, transaction-bound update.
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  SETUP
-- ══════════════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Throwaway clone so Step 5's INSERT test never touches real ORDER_ITEMS.
CREATE OR REPLACE TABLE ECOMMERCE.RAW.MV_TEST_SCRATCH
    CLONE ECOMMERCE.RAW.ORDER_ITEMS
;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 1 — Baseline: the aggregate query without a materialized view
-- ══════════════════════════════════════════════════════════════════════

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT product_id, SUM(quantity) AS total_qty, SUM(quantity * unit_price) AS total_revenue
FROM ECOMMERCE.RAW.MV_TEST_SCRATCH
GROUP BY product_id
;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%MV_TEST_SCRATCH%GROUP BY product_id%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Create the materialized view
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE MATERIALIZED VIEW ECOMMERCE.RAW.MV_ORDER_ITEMS_BY_PRODUCT AS
    SELECT product_id, SUM(quantity) AS total_qty, SUM(quantity * unit_price) AS total_revenue
    FROM ECOMMERCE.RAW.MV_TEST_SCRATCH
    GROUP BY product_id
;

-- Confirm it exists and check its properties:
SHOW MATERIALIZED VIEWS LIKE 'MV_ORDER_ITEMS_BY_PRODUCT' IN SCHEMA ECOMMERCE.RAW;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Query the base table again (NOT the MV by name) — check rewrite
-- ══════════════════════════════════════════════════════════════════════
/*
Same exact query as Step 1, still pointed at MV_TEST_SCRATCH — never
mentioning MV_ORDER_ITEMS_BY_PRODUCT. If the optimizer's automatic query
rewrite kicks in, the execution plan should show it using the materialized
view instead of scanning/aggregating the base table directly.
*/

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT product_id, SUM(quantity) AS total_qty, SUM(quantity * unit_price) AS total_revenue
FROM ECOMMERCE.RAW.MV_TEST_SCRATCH
GROUP BY product_id
;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%MV_TEST_SCRATCH%GROUP BY product_id%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 1
;

-- Check the operator types on THIS query_id — look for something
-- referencing the materialized view rather than a plain TableScan +
-- Aggregate on MV_TEST_SCRATCH:
SELECT DISTINCT operator_type
FROM TABLE(GET_QUERY_OPERATOR_STATS('<step3_query_id>'))
;

-- ACTUAL RESULT: Aggregate, Result, TableScan — NOT rewritten to use the
-- MV, despite the MV being fully populated (row count matched
-- distinct product_id count) and current (behind_by = 0s, invalid = false).
-- CONFIRMED real Snowflake behavior, not a bug: query rewrite is
-- COST-BASED — the optimizer compares the MV access path's cost against
-- scanning the base table directly and picks whichever it judges cheaper,
-- even when the MV is fully eligible and current. On a table this small
-- (~8 micro-partitions, per 5.2/5.3), a direct scan+aggregate may simply
-- already be cheap enough that routing through the MV wasn't worth it to
-- the optimizer. Key takeaway: an MV existing and being current does NOT
-- guarantee it's actually being used — always verify via
-- GET_QUERY_OPERATOR_STATS/EXPLAIN on the real query, at real scale,
-- rather than assuming rewrite happened just because the MV is ready.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Direct performance comparison: base table vs. MV
-- ══════════════════════════════════════════════════════════════════════
/*
Step 3 showed the optimizer choosing NOT to rewrite — but that's a
different question from "does querying the MV directly actually run
faster than the base table aggregate?" Test that directly, matching the
result shape as closely as possible for a fair comparison (no ORDER BY/
LIMIT on either side).
*/

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT product_id, total_qty, total_revenue
FROM ECOMMERCE.RAW.MV_ORDER_ITEMS_BY_PRODUCT
;

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT query_id, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%MV_ORDER_ITEMS_BY_PRODUCT%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
  AND query_text NOT ILIKE '%SHOW MATERIALIZED%'
ORDER BY start_time DESC
LIMIT 1
;

-- Compare this result directly against Step 1's baseline numbers
-- (elapsed_seconds, bytes_scanned) — same logical result set, one reads a
-- small precomputed table, the other aggregates the base table from
-- scratch. THIS is the real, direct performance case for materialized
-- views — independent of whether automatic rewrite happens to trigger,
-- since here the MV is queried explicitly by name.

-- ACTUAL RESULT on this workbook:
--   Base table (Step 1) : 0.383s elapsed, 32,427,008 bytes scanned
--   MV direct  (Step 4) : 0.377s elapsed,  1,025,024 bytes scanned
--
-- bytes_scanned dropped ~31x (32.4MB -> 1.0MB) — the MV read a tiny
-- precomputed result instead of aggregating the full base table. THIS is
-- the real, measurable materialized view win, and it's substantial.
--
-- elapsed_seconds barely moved (0.383s -> 0.377s), and that's expected,
-- not a sign the MV "didn't help": at this tiny scale, wall-clock time is
-- dominated by FIXED overhead (query compilation, network round-trip,
-- session bookkeeping) rather than actual scan work — the real scan
-- itself was already a fraction of a second either way, so a 31x
-- reduction in bytes read gets swallowed by overhead that's identical
-- regardless of how much data is scanned.
--
-- On a production-scale table, where the base-table scan is the dominant
-- cost (seconds or minutes, not milliseconds), this same proportional
-- byte reduction would translate directly into a visible, meaningful
-- wall-clock improvement — because at that scale, actual scan time stops
-- being negligible relative to fixed overhead. This is the genuine,
-- Oracle-familiar "MVs are a major performance lever" case; it's real,
-- it's just scale-sensitive, and bytes_scanned is the metric that reveals
-- it here even when elapsed_seconds doesn't.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 5 — Change the base table, check refresh lag
-- ══════════════════════════════════════════════════════════════════════

INSERT INTO ECOMMERCE.RAW.MV_TEST_SCRATCH
    SELECT * FROM ECOMMERCE.RAW.ORDER_ITEMS LIMIT 1
;

-- Check the MV immediately — does it already reflect the new row, or is
-- there a visible lag before the background refresh catches up?
SELECT SUM(total_qty) AS grand_total_qty FROM ECOMMERCE.RAW.MV_ORDER_ITEMS_BY_PRODUCT;

-- Compare against querying the base table's true current total directly:
SELECT SUM(quantity) AS true_current_total_qty FROM ECOMMERCE.RAW.MV_TEST_SCRATCH;

-- If these don't match right away, wait a bit and re-run both — report
-- how long the gap actually persists.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 6 — Check refresh cost (latency applies — check back later)
-- ══════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

-- CONFIRMED (per actual error): this view has no MATERIALIZED_VIEW_NAME
-- column, despite that being the parameter name on the older, deprecated
-- INFORMATION_SCHEMA.MATERIALIZED_VIEW_REFRESH_HISTORY() table function.
-- The ACCOUNT_USAGE view instead tracks the MV under TABLE_NAME/TABLE_ID —
-- consistent with an MV being stored more like a table internally than a
-- regular view. Its actual columns: start_time, end_time, credits_used,
-- table_id, table_name, schema_id, schema_name, database_id, database_name.
SELECT start_time, end_time, table_name, credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.MATERIALIZED_VIEW_REFRESH_HISTORY
WHERE table_name = 'MV_ORDER_ITEMS_BY_PRODUCT'
ORDER BY start_time DESC
;

USE ROLE SYSADMIN;

-- Up to 3 hours of latency on this view (same as 5.3's
-- AUTOMATIC_CLUSTERING_HISTORY) — don't expect results immediately.


-- ══════════════════════════════════════════════════════════════════════
--  CLEANUP
-- ══════════════════════════════════════════════════════════════════════

DROP MATERIALIZED VIEW ECOMMERCE.RAW.MV_ORDER_ITEMS_BY_PRODUCT;
DROP TABLE ECOMMERCE.RAW.MV_TEST_SCRATCH;


-- ══════════════════════════════════════════════════════════════════════
--  PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════════
/*
1. Try creating a materialized view that JOINS MV_TEST_SCRATCH to ORDERS.
   Confirm it fails, and note the exact error message — this is the
   single-table restriction from the CONCEPT section, confirmed hands-on.

2. Try creating a materialized view with an ORDER BY or LIMIT clause.
   Same idea — confirm the restriction directly rather than just taking
   the CONCEPT section's word for it.

3. Try creating a materialized view directly on ORDERS (the row-access-
   policy table from 5.1/5.3). Does CREATE MATERIALIZED VIEW succeed or
   fail on a policy-protected table? Genuinely untested territory in this
   workbook — report whatever actually happens.

4. Check SHOW MATERIALIZED VIEWS' full output (not just LIKE-filtered) —
   look at columns like "behind_by" or similar staleness indicators, if
   present, to see whether Snowflake exposes refresh lag directly rather
   than you having to infer it by comparing values like Step 5 did.

5. Repeat Step 4's comparison against a table an order of magnitude
   larger (or a query that does more real aggregation work per row) if
   one becomes available in a later goal — confirm that elapsed_seconds
   starts tracking the same ~31x bytes_scanned reduction seen here, once
   actual scan time is large enough to no longer be dominated by fixed
   per-query overhead.
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: CREATE MATERIALIZED VIEW failed with an Enterprise Edition error.
A: Confirm this account's edition — Enterprise Edition is a hard
   prerequisite here, same as 5.6's multi-cluster warehouses. If this
   account is actually Standard Edition, this entire sub-task isn't
   testable as written.

Q: Step 3's operator stats still showed a plain TableScan + Aggregate, not
   anything referencing the materialized view — even after confirming the
   MV was fully populated (row counts matched) and current (behind_by=0s,
   invalid=false).
A: Confirmed on this workbook, and it's a real, documented Snowflake
   behavior, not a bug: query rewrite is COST-BASED, not just eligibility-
   based. The optimizer compares the cost of using the MV against the
   cost of scanning the base table directly, and picks whichever it
   calculates as cheaper — even when the MV is fully eligible and current.
   Given this table's small size (the same ~8-micro-partition scale
   established in 5.2/5.3, and the modest Small-vs-X-Small speed gap seen
   in 5.5), a direct scan+aggregate over MV_TEST_SCRATCH may simply be
   cheap enough already that the optimizer sees no benefit in redirecting
   through the MV. This is a genuinely important, non-obvious finding for
   production use: creating an MV does not guarantee it gets used, and
   "the MV exists and is current" is not sufficient to confirm it's
   actually helping — always verify via GET_QUERY_OPERATOR_STATS/EXPLAIN
   on the actual query you care about, on data at the scale where it
   matters, rather than assuming rewrite kicked in.

Q: Step 5 showed the MV immediately reflecting the new row, with no
   visible refresh lag at all.
A: Possible and not necessarily surprising — on a small test table, the
   background refresh may complete fast enough that you don't catch it
   mid-lag, similar to 5.3's clustering key acting almost instantly on an
   8-partition table. Don't assume this generalizes to a high-churn
   production table, where refresh lag is much more likely to be visible
   and where MV maintenance cost is the real ongoing concern the CONCEPT
   section flags.

Q: MATERIALIZED_VIEW_REFRESH_HISTORY errored on materialized_view_name as
   an invalid identifier.
A: Confirmed on this workbook — the ACCOUNT_USAGE view's actual columns
   are start_time, end_time, credits_used, table_id, table_name,
   schema_id, schema_name, database_id, database_name. The MV is tracked
   under TABLE_NAME, not a MATERIALIZED_VIEW_NAME column (that parameter
   name only belongs to the older, deprecated INFORMATION_SCHEMA table
   function version). Filter on table_name instead — fixed in Step 6.

Q: Why not just build the MV directly on ORDER_ITEMS instead of a clone?
A: Same reasoning as 5.3 and 5.4 — Step 5 needs a real INSERT to test
   refresh behavior, and DML on a throwaway clone keeps that mutation off
   the real ECOMMERCE tables and their Goal 3/4 dependencies.
*/
