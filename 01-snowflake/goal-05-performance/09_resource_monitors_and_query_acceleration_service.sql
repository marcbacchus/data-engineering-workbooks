/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Sub-task 5.9 : Resource Monitors & Query Acceleration Service
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 25-30 min
  Warehouse size     : WORKBOOK_WH (X-Small)
  Database           : ECOMMERCE.RAW
  Run in             : Snowsight
  Prerequisites      : Sub-tasks 5.1-5.8 complete. Query Acceleration
                        Service requires Enterprise Edition — confirmed
                        available (same requirement as 5.6/5.7/5.8).
                        Resource monitors require ACCOUNTADMIN to create.
  COF-C03 domain     : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════════
/*
Two unrelated features share this final sub-task because they're both
governance/elasticity tools rather than data-layout tools like 5.2-5.8:

Query Acceleration Service (QAS) offloads part of a SINGLE query's work
to elastic serverless compute, when that query is scan-heavy with a
selective filter — reducing how much one "outlier" query can slow down
everything else sharing its warehouse. Worth checking now specifically
because 5.6's SHOW WAREHOUSES output already showed WORKBOOK_WH has
ENABLE_QUERY_ACCELERATION = true and QUERY_ACCELERATION_MAX_SCALE_FACTOR
= 2 — it's apparently been on since this workbook's initial setup,
unnoticed until now.

Resource monitors are the credit-governance safety net this sub-task was
always meant to be, per the Goal 5 plan set at the very start: build one
on WORKBOOK_WH with a low quota and a SUSPEND trigger. Unlike every other
object created in Goal 5, this one is NOT meant to be dropped at the end —
it's meant to stay as ongoing protection for the rest of this workbook
series.
*/


-- ══════════════════════════════════════════════════════════════════════
--  CONCEPT
-- ══════════════════════════════════════════════════════════════════════
/*
QUERY ACCELERATION SERVICE (QAS)
  - Targets two query shapes: large scans with a selective filter or
    aggregation, and large INSERT/COPY/UPDATE/DELETE operations.
  - Offloads the eligible PORTION of that one query's work to serverless
    compute Snowflake provides on demand — not a bigger warehouse (5.5)
    and not more warehouses (5.6), but extra elastic capacity recruited
    per-query, automatically, only when eligible and beneficial.
  - Controlled per-warehouse via ENABLE_QUERY_ACCELERATION (boolean) and
    QUERY_ACCELERATION_MAX_SCALE_FACTOR (how many multiples of the
    warehouse's own size QAS is allowed to recruit — 0 means unlimited).
  - Eligibility is per-query, not automatic for everything: check with
    SYSTEM$ESTIMATE_QUERY_ACCELERATION('<query_id>') on an already-run
    query (must be within the last 14 days), or the account-wide
    QUERY_ACCELERATION_ELIGIBLE view.
  - Billed separately as serverless credits, only when actually used —
    not a flat ongoing cost like automatic clustering (5.3) or search
    optimization maintenance (5.8).

RESOURCE MONITORS
  - Account-level objects: CREDIT_QUOTA, an optional FREQUENCY (DAILY,
    WEEKLY, MONTHLY, YEARLY, or NEVER) and START_TIMESTAMP for when the
    quota resets, and TRIGGERS — percentage thresholds mapped to an
    action (NOTIFY, SUSPEND, SUSPEND_IMMEDIATE).
  - SUSPEND waits for currently running queries to finish before
    stopping the warehouse (meaning actual spend can still slightly
    exceed the quota); SUSPEND_IMMEDIATE cancels running queries right
    away.
  - Only ACCOUNTADMIN can CREATE one by default (though the privilege can
    be delegated). A monitor is assigned to one or more warehouses via
    ALTER WAREHOUSE ... SET RESOURCE_MONITOR, or to the whole account
    (max one account-level monitor).
  - CRITICAL LIMITATION, and the reason this sub-task closes out Goal 5
    rather than opening it: resource monitors CANNOT govern Snowflake's
    own serverless warehouses — MATERIALIZED_VIEW_MAINTENANCE (5.7),
    automatic clustering (5.3), or search optimization maintenance (5.8).
    A resource monitor on WORKBOOK_WH would NOT have protected against
    any of that background spend earlier in Goal 5 — only against
    WORKBOOK_WH's own compute (and anything like 5.5's SCALE_TEST_WH or
    5.6's second cluster, if it had been assigned the same monitor).

──────────────────────────────────────────────────────────────────────────
Oracle / SQL Server comparison:
  Oracle    : Database Resource Manager controls how CPU/IO is shared
              among competing sessions WITHIN one running instance — it
              throttles contention, it doesn't shut anything down at a
              dollar/credit threshold. There's no built-in "kill switch at
              $X spent" primitive analogous to a Snowflake resource
              monitor. Parallel Query / Auto DOP is the closest analogue
              to QAS, but it parallelizes using the instance's OWN fixed,
              already-provisioned resources — it can't recruit genuinely
              additional compute from outside the instance the way QAS
              elastically does.
  SQL Server: Resource Governor similarly manages CPU/memory contention
              between workload groups on the same instance — again, a
              throttling tool, not a budget cap. No equivalent to QAS's
              on-demand elastic offload exists at all.
  Key difference: both of Snowflake's tools here are fundamentally about
  ELASTICITY — spend caps that act automatically at a threshold (resource
  monitors), and genuinely extra compute recruited on demand for a single
  query (QAS) — neither of which map cleanly onto Oracle or SQL Server's
  fixed-capacity, contention-management approach to the same problems.
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
--  STEP 1 — Confirm QAS is already on (per 5.6's SHOW WAREHOUSES output)
-- ══════════════════════════════════════════════════════════════════════

SHOW WAREHOUSES LIKE 'WORKBOOK_WH';
-- Check enable_query_acceleration and query_acceleration_max_scale_factor
-- — 5.6's output already showed true / 2 for these on this warehouse.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Check eligibility on a real, already-run query
-- ══════════════════════════════════════════════════════════════════════
/*
SYSTEM$ESTIMATE_QUERY_ACCELERATION needs a query_id from the last 14
days — reuse a real one from earlier in this workbook rather than
generating a fresh throwaway query. The 5.1 join+sort (ORDERS x
ORDER_ITEMS, unfiltered, with a sort) is a good candidate — large scan,
real aggregation-adjacent work.
*/

-- Grab a recent, real, large query_id from this session if you don't have
-- one handy. Filtering on a byte-scanned floor is more reliable than
-- exact text matching (confirmed fragile on this workbook — see WHAT IF):
SELECT query_id, query_text, total_elapsed_time / 1000 AS elapsed_seconds, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE bytes_scanned > 10000000
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
ORDER BY start_time DESC
LIMIT 10
;
-- Any real, recent query_id works for Step 2 — it doesn't need to be
-- large specifically, it just needs to actually demonstrate the function.

SELECT PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION('<query_id_from_above>'));
-- Review the "status" field: "eligible" or "ineligible". If eligible, the
-- JSON includes estimated execution time at different scale factors
-- (1, 2, 4, 8, 10) — compare those against the query's actual elapsed
-- time to see the projected benefit.

-- ACTUAL RESULT (query: point lookup on the now-DROPPED
-- SEARCH_OPT_TEST_SCRATCH table from 5.8):
--   {"estimatedQueryTimes":{},"ineligibleReason":"NO_LARGE_ENOUGH_SCAN",
--    "originalQueryTime":0.309,"status":"ineligible","upperLimitScaleFactor":0}
--
-- Two confirmed findings from this single result:
-- 1. The function works fine against a query_id whose underlying object
--    has since been DROPPED — it only needs the recorded execution
--    stats from query history, not a live object. Settles the earlier
--    open question definitively.
-- 2. "NO_LARGE_ENOUGH_SCAN" is an explicit, named ineligibility reason —
--    and it's the same recurring story as 5.3, 5.7, and 5.8: this
--    table's small size (8 partitions, sub-second queries) puts it below
--    the threshold where QAS, clustering, materialized views, or search
--    optimization show a measurable difference. Consistent, not a
--    coincidence — every storage/compute-elasticity feature in Goal 5
--    has hit the same wall on this specific dataset.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Check account-wide QAS-eligible queries (latency applies)
-- ══════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

SELECT query_id, warehouse_name, eligible_query_acceleration_time, upper_limit_scale_factor
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ACCELERATION_ELIGIBLE
ORDER BY eligible_query_acceleration_time DESC
LIMIT 10
;
-- <if the exact column names above don't match, run SELECT * with no
--  column list first to see this view's real columns — consistent with
--  the pattern of ACCOUNT_USAGE views not always matching assumptions
--  from earlier in Goal 5>

USE ROLE SYSADMIN;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Build the resource monitor (this one STAYS — no cleanup step)
-- ══════════════════════════════════════════════════════════════════════
/*
Check for an existing resource monitor first — always good practice
before creating one, since Snowflake only allows a single account-level
monitor per account, and a redundant monitor adds confusion without
adding protection.
*/

SHOW RESOURCE MONITORS;

/*
Deliberately low quota and DAILY frequency for a trial account — this is
meant to be a real, permanent safety net for the rest of this workbook
series, not a one-off test. Adjust CREDIT_QUOTA up if 5/day proves too
tight for normal workbook usage.
*/

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE RESOURCE MONITOR WORKBOOK_DAILY_LIMIT
    WITH CREDIT_QUOTA = 5
    FREQUENCY = DAILY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 50 PERCENT DO NOTIFY
        ON 90 PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE
;

ALTER WAREHOUSE WORKBOOK_WH SET RESOURCE_MONITOR = WORKBOOK_DAILY_LIMIT;

USE ROLE SYSADMIN;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 5 — Confirm it's attached
-- ══════════════════════════════════════════════════════════════════════

SHOW RESOURCE MONITORS LIKE 'WORKBOOK_DAILY_LIMIT';
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';
-- Check the "resource_monitor" column on the warehouse output — should
-- now read WORKBOOK_DAILY_LIMIT.


-- ══════════════════════════════════════════════════════════════════════
--  NOTE — no CLEANUP section for the resource monitor, intentionally
-- ══════════════════════════════════════════════════════════════════════
/*
Every other sub-task in Goal 5 ended by dropping its test objects.
WORKBOOK_DAILY_LIMIT is the one deliberate exception — it's meant to
remain assigned to WORKBOOK_WH going forward as ongoing protection, per
the plan set at the very start of this goal.
*/


-- ══════════════════════════════════════════════════════════════════════
--  PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════════
/*
1. Deliberately trip the NOTIFY trigger — run enough queries in one day to
   cross 50% of the 5-credit quota (2.5 credits; likely takes meaningful
   sustained X-Small usage, not a single query) and confirm a notification
   actually arrives. Per Snowflake's docs, email notifications need to be
   enabled separately in account preferences — check that first if
   nothing arrives.

2. Try SYSTEM$ESTIMATE_QUERY_ACCELERATION on a SMALL, simple query (e.g.
   a single-row lookup) instead of the large join+sort. Confirm it
   returns "ineligible" — small/simple queries generally aren't QAS
   candidates, since there's nothing substantial to offload.

3. Check what happens to a warehouse AFTER a resource monitor's SUSPEND
   trigger fires — per Snowflake's docs, a suspended warehouse cannot
   resume until either the quota resets (next FREQUENCY interval) or an
   ACCOUNTADMIN manually intervenes (raises the quota or changes the
   trigger). Worth understanding this BEFORE it happens for real, since
   it means an accidental trip could temporarily block work on
   WORKBOOK_WH until deliberately fixed.

4. Query SNOWFLAKE.ACCOUNT_USAGE.QUERY_ACCELERATION_HISTORY (once its
   latency clears) to see whether QAS has been silently accelerating any
   queries run earlier in this workbook, given it's apparently been
   enabled on WORKBOOK_WH since before Goal 5 started.
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: CREATE RESOURCE MONITOR failed under SYSADMIN.
A: Expected — only ACCOUNTADMIN can create resource monitors by default.
   Step 4 already switches roles for this; if it still fails under
   ACCOUNTADMIN, something more fundamental is wrong with account access.

Q: SYSTEM$ESTIMATE_QUERY_ACCELERATION returned "ineligible".
A: Confirmed on this workbook with an explicit reason:
   "NO_LARGE_ENOUGH_SCAN" — consistent with every other Goal 5 finding on
   this dataset. This table's small size (8 partitions, sub-second query
   times) is below the threshold where QAS has enough work to usefully
   offload, the same underlying story as 5.3's clustering key, 5.7's MV
   rewrite, and 5.8's search optimization all showing muted or absent
   benefit. If testing this against a genuinely large table becomes
   possible in a later goal, revisit this — the mechanism itself is
   confirmed working correctly; this dataset just doesn't have a query
   shape large enough to trigger real eligibility.

Q: I'm worried the 5-credit daily quota is too aggressive and will
   suspend WORKBOOK_WH mid-session on a normal workbook day.
A: That's a legitimate concern worth testing deliberately (Practice Gap
   #1) rather than discovering by surprise mid-goal. If 5/day proves too
   tight, ALTER RESOURCE MONITOR WORKBOOK_DAILY_LIMIT SET CREDIT_QUOTA =
   <higher number> — raising it later is a normal, expected adjustment,
   not a sign the safety net was a bad idea to begin with.

Q: Does this resource monitor protect against everything tested in Goal 5?
A: No — and that's the important closing lesson. It protects
   WORKBOOK_WH's own compute (including anything like 5.5's temporary
   warehouse or 5.6's second cluster, IF those had been assigned this
   same monitor). It does NOT protect against 5.3's automatic clustering,
   5.7's materialized view maintenance, or 5.8's search optimization
   maintenance — all of which run on Snowflake's own serverless
   warehouses, which resource monitors cannot govern. The real safety net
   for those was always the explicit "estimate first, enable narrowly,
   disable when done" discipline used throughout this goal — not
   something a resource monitor could have automated away.
*/
