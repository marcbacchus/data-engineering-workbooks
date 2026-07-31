/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Sub-task 5.4 : Result & Warehouse Caching
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 30-35 min
  Warehouse size     : WORKBOOK_WH (X-Small)
  Database           : ECOMMERCE.RAW
  Run in             : Snowsight (per 5.1-5.3 correction — Query Profile's
                        visual cache indicators, and manually suspending/
                        resuming the warehouse mid-worksheet, are both more
                        natural here than in SnowSQL)
  Prerequisites      : Sub-tasks 5.1-5.3 complete. 5.1 already surfaced a
                        "QUERY RESULT REUSE" operator by accident when a
                        query was re-run unintentionally — this sub-task
                        makes that same mechanism deliberate and adds the
                        two other cache layers around it
  COF-C03 domain     : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════════
/*
Snowflake actually has THREE separate caching layers, not one, and they
have very different lifetimes, scopes, and invalidation rules. Confusing
them is one of the most common sources of "why did this query suddenly get
slower" surprises. Today you'll deliberately trigger and observe each one:

  1. Result cache    — whole query results, Cloud Services layer, 24hr+
  2. Warehouse cache  — raw micro-partition data, local SSD, per-warehouse
  3. Metadata cache   — table statistics, Cloud Services layer, always on

5.1's accidental "QUERY RESULT REUSE" discovery was layer 1. Today you'll
also get layers 2 and 3, and see exactly what breaks each one.
*/


-- ══════════════════════════════════════════════════════════════════════
--  CONCEPT
-- ══════════════════════════════════════════════════════════════════════
/*
RESULT CACHE (Cloud Services layer, account-wide)
  - Stores the complete result of a query, not just scanned data.
  - Retained 24 hours; every reuse within that window resets the 24-hour
    clock, up to a hard ceiling of 31 days from the FIRST execution.
  - Requires: syntactically identical query text (same case, aliases,
    whitespace), no non-deterministic functions (CURRENT_TIMESTAMP(),
    RANDOM(), UUID_STRING(), etc.), underlying data unchanged since the
    cached result was generated, and the requesting session/role must have
    the same access privileges on all referenced objects.
  - Free — zero compute, zero credits, doesn't need a running warehouse.
  - Controlled by USE_CACHED_RESULT (ACCOUNT / USER / SESSION level).

WAREHOUSE CACHE (Compute layer, local SSD, per-warehouse)
  - Caches raw micro-partition data as it's read from remote storage, so a
    LATER query — even a completely different one — that touches the same
    micro-partitions can skip the round-trip to cloud storage.
  - Scoped to ONE warehouse. Two warehouses reading the same table do not
    share this cache.
  - Lost entirely when the warehouse suspends. This is the direct,
    practical tension behind AUTO_SUSPEND: suspend too aggressively and
    you keep losing a warm cache; leave it running and you pay idle
    compute credits to keep it warm. Sub-task 5.9 covers tuning this
    tradeoff more formally.
  - Visible in Query Profile / query history as "percentage scanned from
    cache" — this is DIFFERENT from a result-cache hit; a query can show
    partial cache usage here while still doing real compute work.

METADATA CACHE (Cloud Services layer, always on)
  - Snowflake maintains per-table statistics (row counts, min/max per
    column, etc.) automatically, with no caching decision to make — it's
    just always current.
  - Enables certain queries (COUNT(*), some MIN/MAX aggregates with no
    filtering) to be answered directly from metadata, without ever
    touching a warehouse — meaning no warehouse needs to even be running.

──────────────────────────────────────────────────────────────────────────
Oracle / SQL Server comparison:
  Oracle    : Has a Result Cache too, but it's opt-in — you request it
              explicitly with a  RESULT_CACHE  hint or a session/
              system parameter, rather than it being automatic for every
              query. Oracle's Buffer Cache (data blocks in SGA) is the
              rough equivalent of Snowflake's warehouse cache, but it
              persists as long as the INSTANCE is up, not tied to
              anything like a warehouse suspend/resume cycle.
  SQL Server: Buffer pool caches data pages similarly, persisting for the
              life of the instance. There's no automatic whole-result
              cache layer at all — the closest analogue, Query Store,
              caches execution PLANS, not results, and exists for
              plan-stability/tuning history rather than skipping
              re-execution.
  Key difference: Snowflake's three-layer split, with automatic (not
  opt-in) result caching AND a compute-layer cache that's explicitly tied
  to warehouse lifecycle, has no single direct equivalent in either
  platform — the AUTO_SUSPEND credit/cache-warmth tradeoff in particular
  is a distinctly Snowflake concern.
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  SETUP
-- ══════════════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Throwaway scratch table so Step 2's data-change test doesn't touch any
-- real ECOMMERCE table.
CREATE OR REPLACE TABLE ECOMMERCE.RAW.CACHE_TEST_SCRATCH AS
    SELECT * FROM ECOMMERCE.RAW.ORDER_ITEMS LIMIT 1000
;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 1 — Result cache: deliberate hit
-- ══════════════════════════════════════════════════════════════════════
/*
Run this EXACT query text twice in a row. Don't change anything between
runs — the whole point is byte-for-byte identical SQL.
*/

SELECT product_id, SUM(quantity) AS total_qty
FROM ECOMMERCE.RAW.CACHE_TEST_SCRATCH
GROUP BY product_id
;

-- <run the identical query again here, unchanged>
SELECT product_id, SUM(quantity) AS total_qty
FROM ECOMMERCE.RAW.CACHE_TEST_SCRATCH
GROUP BY product_id
;

-- Check both executions:
SELECT query_id, query_text, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%CACHE_TEST_SCRATCH%GROUP BY product_id%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA.QUERY_HISTORY%'
ORDER BY start_time DESC
LIMIT 2
;

-- NOTE: without the NOT ILIKE exclusion above, this lookup query can match
-- ITSELF — its own WHERE clause literally contains the search string
-- ('%CACHE_TEST_SCRATCH%GROUP BY product_id%'), so a plain ILIKE filter
-- treats the lookup query's own query_text as a hit. Confirmed on this
-- workbook: it showed up with a nonsensical, huge negative elapsed_seconds
-- (a query capturing its own history mid-execution doesn't have a real
-- total_elapsed_time yet). Worth remembering for ANY future query_history
-- self-lookup with an ILIKE filter, not just this one.

-- ACTUAL RESULT (with the exclusion fix in place):
--   1st run: 0.469s elapsed, bytes_scanned = 23040  → real execution
--   2nd run: 0.183s elapsed, bytes_scanned = 0       → result cache hit
-- Clean confirmation: same query, zero bytes scanned the second time, and
-- meaningfully faster. Use the 2nd run's query_id below to confirm the
-- operator type directly.

-- Confirm the SECOND run's (most recent) operator type from above —
-- expect QUERY RESULT REUSE, per the 5.1 discovery:
SELECT DISTINCT operator_type
FROM TABLE(GET_QUERY_OPERATOR_STATS('<second_run_query_id>'))
;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Result cache: invalidation on data change
-- ══════════════════════════════════════════════════════════════════════
/*
Same query text as Step 1, but now we change the underlying data first.
Expect the cache to be bypassed — a real execution, not a reuse.
*/

INSERT INTO ECOMMERCE.RAW.CACHE_TEST_SCRATCH
    SELECT * FROM ECOMMERCE.RAW.ORDER_ITEMS LIMIT 1
;

-- Same exact query text as Step 1:
SELECT product_id, SUM(quantity) AS total_qty
FROM ECOMMERCE.RAW.CACHE_TEST_SCRATCH
GROUP BY product_id
;

SELECT query_id, query_text, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%CACHE_TEST_SCRATCH%GROUP BY product_id%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA.QUERY_HISTORY%'
ORDER BY start_time DESC
LIMIT 1
;

SELECT DISTINCT operator_type
FROM TABLE(GET_QUERY_OPERATOR_STATS('<this_query_id>'))
;
-- Expect something other than QUERY RESULT REUSE this time — the INSERT
-- changed the table's data, invalidating the cached result even though
-- the query text is identical to Step 1.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Warehouse (local disk) cache: same data, different query
-- ══════════════════════════════════════════════════════════════════════
/*
Two DIFFERENT queries (so result cache can never apply to either one),
both touching the same underlying data. If the warehouse cache is warm
from the first, the second may scan partially or entirely from cache even
though its SQL text has never been seen before.
*/

SELECT COUNT(*) FROM ECOMMERCE.RAW.CACHE_TEST_SCRATCH WHERE quantity > 1;

SELECT AVG(unit_price) FROM ECOMMERCE.RAW.CACHE_TEST_SCRATCH WHERE quantity > 1;

-- CONFIRMED (per actual error): percentage_scanned_from_cache is NOT a
-- column on INFORMATION_SCHEMA.QUERY_HISTORY() — same pattern as 5.1's
-- partitions_scanned/bytes_spilled discovery. It only exists on
-- SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY, which needs ACCOUNTADMIN (or a
-- role granted IMPORTED PRIVILEGES on the SNOWFLAKE database) and carries
-- up to ~45 minutes of latency — so this check won't show results
-- immediately after running the two queries above. Come back to it once
-- that latency has passed.

USE ROLE ACCOUNTADMIN;

SELECT query_id, query_text, bytes_scanned, percentage_scanned_from_cache
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_text ILIKE '%CACHE_TEST_SCRATCH%quantity > 1%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
  AND query_text NOT ILIKE '%ACCOUNT_USAGE.QUERY_HISTORY%'
ORDER BY start_time DESC
LIMIT 2
;

USE ROLE SYSADMIN;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Warehouse cache: lost on suspend
-- ══════════════════════════════════════════════════════════════════════

ALTER WAREHOUSE WORKBOOK_WH SUSPEND;
ALTER WAREHOUSE WORKBOOK_WH RESUME;

-- A THIRD new query text, still touching the same scratch table/rows:
SELECT MAX(unit_price) FROM ECOMMERCE.RAW.CACHE_TEST_SCRATCH WHERE quantity > 1;

-- Same ACCOUNT_USAGE fallback as Step 3 (percentage_scanned_from_cache
-- isn't on the INFORMATION_SCHEMA function) — also subject to the same
-- ~45 min latency, so this check won't be visible right away either.

USE ROLE ACCOUNTADMIN;

SELECT query_id, query_text, bytes_scanned, percentage_scanned_from_cache
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_text ILIKE '%CACHE_TEST_SCRATCH%MAX(unit_price)%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
  AND query_text NOT ILIKE '%ACCOUNT_USAGE.QUERY_HISTORY%'
ORDER BY start_time DESC
LIMIT 1
;

USE ROLE SYSADMIN;
-- Expect percentage_scanned_from_cache back near 0 — the SUSPEND wiped
-- whatever Step 3 had warmed, even though it's the same warehouse and
-- same underlying data.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 5 — Metadata cache: no warehouse required
-- ══════════════════════════════════════════════════════════════════════

ALTER WAREHOUSE WORKBOOK_WH SUSPEND;

-- Confirm it's actually suspended before proceeding:
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';
-- Check the "state" column reads SUSPENDED.

SELECT COUNT(*) FROM ECOMMERCE.RAW.CACHE_TEST_SCRATCH;

-- Check whether the warehouse had to resume to answer that:
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';
-- If "state" still reads SUSPENDED, the count was answered entirely from
-- the metadata cache — no compute was spun up at all.


-- ══════════════════════════════════════════════════════════════════════
--  CLEANUP
-- ══════════════════════════════════════════════════════════════════════

DROP TABLE ECOMMERCE.RAW.CACHE_TEST_SCRATCH;


-- ══════════════════════════════════════════════════════════════════════
--  PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════════
/*
1. Check the current USE_CACHED_RESULT setting at both the account and
   session level:
     SHOW PARAMETERS LIKE 'USE_CACHED_RESULT';
   Then set it to FALSE at the session level and re-run Step 1's exact
   query twice — confirm the second run is NOT a QUERY RESULT REUSE this
   time, since you've explicitly disabled the mechanism.

2. Re-run Step 1's query but wrap it with a non-deterministic function,
   e.g. add a column CURRENT_TIMESTAMP() AS run_ts to the SELECT list, run
   it twice identically. Does the second run still get QUERY RESULT REUSE?
   The CONCEPT section says it shouldn't — confirm or refute directly.

3. Run a metadata-only query (Step 5's shape) but add a WHERE clause
   filter instead of a bare COUNT(*). Does adding a filter change whether
   the warehouse needs to resume, compared to the unfiltered COUNT(*)?

4. Using SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY (once its
   latency catches up), check whether the SUSPEND/RESUME cycles in Steps
   4-5 actually registered as separate credit-billing events, or whether
   they were too close together/too short to matter at X-Small.
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: percentage_scanned_from_cache errored as an invalid identifier on
   INFORMATION_SCHEMA.QUERY_HISTORY().
A: Confirmed on this workbook — same pattern as 5.1's
   partitions_scanned/bytes_spilled discovery. This column only exists on
   SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY, which Steps 3-4 now use directly
   (with the ACCOUNTADMIN role switch and ~45-minute latency that implies —
   don't expect results immediately after running the test queries).

Q: Step 4 still showed cache reuse after suspend/resume — did the suspend
   not actually happen?
A: Check SHOW WAREHOUSES output from right after the ALTER WAREHOUSE ...
   SUSPEND — if "state" doesn't read SUSPENDED, the ALTER may not have
   completed before the next statement ran (auto-resume can also kick in
   almost instantly on the very next query, depending on timing). Add a
   short pause or explicitly re-check state before Step 4's SELECT if this
   happens.

Q: Step 5's COUNT(*) still resumed the warehouse — is metadata caching not
   working?
A: Not necessarily broken — COUNT(*) without any WHERE clause is the
   textbook case for a pure metadata answer, but Snowflake's optimizer
   still gets to decide, and behavior isn't guaranteed to be identical
   across every table/situation. Report what SHOW WAREHOUSES actually
   showed rather than assuming either way — this is a case where the real
   behavior on your account is more valuable than the textbook
   expectation.

Q: Why create a scratch table instead of testing directly on ORDER_ITEMS?
A: Step 2 needs an actual INSERT to invalidate the result cache — same
   reasoning as 5.3's clone: anything that mutates data for a test stays
   off the real ECOMMERCE tables and their Goal 3/4 dependencies.
*/
