/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Sub-task 5.6 : Multi-Cluster Warehouses & Concurrency
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 30-40 min
  Warehouse size     : WORKBOOK_WH stays X-Small — only CLUSTER COUNT
                        changes in this sub-task, not size
  Database           : ECOMMERCE.RAW
  Run in             : Snowsight — REQUIRED this time, not just preferred.
                        Steps 3-4 need multiple worksheet TABS open and run
                        simultaneously to generate real concurrent load;
                        this can't be done from a single sequential script.
  Prerequisites      : Sub-task 5.5 complete. Multi-cluster warehouses are
                        an Enterprise Edition feature — confirmed available
                        on this account per the workbook's Enterprise
                        Snowflake account.
  COF-C03 domain     : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════════
/*
5.5 established that warehouse SIZE helps a single query do more work in
parallel, but does nothing for many queries competing for the same
warehouse at once. That's what multi-cluster warehouses solve: instead of
one warehouse getting bigger, Snowflake can spin up additional identical
clusters of the SAME size to absorb concurrent load, then spin them back
down when demand drops.

Per the Goal 5 credit-safety plan: WORKBOOK_WH itself gets converted to
multi-cluster (MIN=1, MAX=2) for this test — X-Small × 2 clusters briefly
is still cheap — and is converted BACK to single-cluster at the end. This
is the one sub-task in Goal 5 that needs real concurrent sessions to
observe anything, so the mechanics of the test itself look different from
5.1-5.5.
*/


-- ══════════════════════════════════════════════════════════════════════
--  CONCEPT
-- ══════════════════════════════════════════════════════════════════════
/*
A multi-cluster warehouse is a set of MIN_CLUSTER_COUNT to
MAX_CLUSTER_COUNT identical clusters, all the same size, sharing one
warehouse name. When queries start QUEUING on the active cluster(s) —
not when a single query is slow, but when there's more concurrent demand
than the current cluster(s) can absorb — Snowflake starts an additional
cluster to take the overflow. When demand drops, extra clusters shut back
down (subject to normal auto-suspend-style idle behavior per cluster).

SCALING POLICY governs how eagerly that additional cluster gets started
(this is the setting that had nothing to observe in 5.5's single-cluster
warehouse):
  - STANDARD: starts a new cluster quickly at the first sign of queuing,
    prioritizing avoiding wait time over conserving credits.
  - ECONOMY: waits longer, tolerating some queuing, before deciding the
    extra cluster is worth starting — favors credit efficiency.

Billing: each cluster that's actually running bills independently, at the
warehouse's size-based credit rate. Two X-Small clusters running
simultaneously for an hour bills 2 credits for that hour (1 each) — same
per-cluster rate as always, just potentially more than one cluster billing
at once.

Critically: this is a CONCURRENCY tool, not a per-query speed tool. A
single slow query does not get faster by adding more clusters — only by
increasing the SIZE of the cluster it runs on (5.5). Multi-cluster only
helps when the problem is queries queuing behind each other, not any one
query being slow on its own.

──────────────────────────────────────────────────────────────────────────
Oracle / SQL Server comparison:
  Oracle    : Oracle RAC (Real Application Clusters) lets multiple instances
              share access to the same storage, primarily for high
              availability and manual horizontal scale — but RAC doesn't
              automatically add or remove instances based on real-time
              query queuing the way Snowflake's multi-cluster warehouses
              do. Scaling RAC up or down is a deliberate infrastructure
              change, not an automatic response to load.
  SQL Server: No direct equivalent. Always On Availability Groups address
              high availability/read-scale, not workload-driven autoscaling
              of compute in response to concurrent query volume.
  Key difference: automatic, workload-driven scaling of concurrent compute
  capacity — spinning clusters up and down based on real-time queuing,
  with no manual intervention — has no close analogue in either platform.
──────────────────────────────────────────────────────────────────────────
*/


-- ══════════════════════════════════════════════════════════════════════
--  SETUP
-- ══════════════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;
USE WAREHOUSE WORKBOOK_WH;


-- ══════════════════════════════════════════════════════════════════════
--  STEP 1 — Convert WORKBOOK_WH to multi-cluster
-- ══════════════════════════════════════════════════════════════════════
/*
Size stays X-Small — only cluster count changes. SCALING_POLICY =
'STANDARD' is deliberate here: we WANT the second cluster to start quickly
so the test is observable in a reasonable amount of time. Try ECONOMY as a
Practice Gap variant afterward.
*/

ALTER WAREHOUSE WORKBOOK_WH SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    SCALING_POLICY = 'STANDARD'
;

-- Confirm the settings registered:
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';
-- Check min_cluster_count, max_cluster_count, scaling_policy, and
-- started_clusters (should read 1 — nothing extra running yet) columns.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 2 — Prepare the concurrent load
-- ══════════════════════════════════════════════════════════════════════
/*
SYSTEM$WAIT holds a session busy for a fixed duration without needing any
real heavy query — a simple, controllable way to occupy the warehouse
concurrently across multiple sessions. This is the query you'll run
simultaneously in Step 3.
*/

SELECT SYSTEM$WAIT(30);
-- Run this ONCE now just to confirm it works and takes ~30 seconds — this
-- single run won't trigger a second cluster on its own (one session isn't
-- concurrent load). The real test is Step 3.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 3 — Generate real concurrent load (REQUIRES MULTIPLE TABS)
-- ══════════════════════════════════════════════════════════════════════
/*
This step can't be scripted sequentially — concurrency means simultaneous,
not one-after-another. In Snowsight:

  1. Open 4-5 NEW worksheet tabs (each tab = its own session).
  2. In EACH tab, confirm it's using WORKBOOK_WH (USE WAREHOUSE WORKBOOK_WH;
     if needed) and the SYSADMIN role.
  3. In as close to the same moment as possible, run this in EVERY tab:

       SELECT SYSTEM$WAIT(45);

  4. Immediately switch to a fresh tab/worksheet and run Step 4's SHOW
     WAREHOUSES check WHILE those 4-5 SYSTEM$WAIT calls are still running.

The goal is enough simultaneous sessions that the single X-Small cluster
can't absorb them all without queuing, prompting Snowflake to start the
second cluster per MAX_CLUSTER_COUNT = 2.
*/


-- ══════════════════════════════════════════════════════════════════════
--  STEP 4 — Check cluster count WHILE the load is running
-- ══════════════════════════════════════════════════════════════════════
/*
Run this from a separate tab, DURING Step 3's concurrent SYSTEM$WAIT
calls — SHOW WAREHOUSES reflects live, current state, no ACCOUNT_USAGE
latency involved.
*/

SHOW WAREHOUSES LIKE 'WORKBOOK_WH';
-- Check:
--   started_clusters — did this go above 1?
--   running           — how many queries are currently executing?
--   queued            — did any queries actually wait before running?
-- Report the ACTUAL numbers, whatever they are — a small X-Small
-- warehouse may or may not need a second cluster for only 4-5 trivial
-- SYSTEM$WAIT sessions, and that's informative either way.


-- ══════════════════════════════════════════════════════════════════════
--  STEP 5 — Confirm after the fact via query history
-- ══════════════════════════════════════════════════════════════════════
/*
CONFIRMED (per actual result): cluster_number returns NULL on
INFORMATION_SCHEMA.QUERY_HISTORY() — same pattern as 5.1's
partitions_scanned/bytes_spilled and 5.4's percentage_scanned_from_cache.
This function's column list is broader than what it actually populates;
the real data lives on SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY, with the
usual ACCOUNTADMIN/IMPORTED PRIVILEGES and ~45-minute latency tradeoff.
*/

USE ROLE ACCOUNTADMIN;

SELECT query_id, cluster_number, warehouse_name, start_time, total_elapsed_time / 1000 AS elapsed_seconds
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'WORKBOOK_WH'
  AND query_text ILIKE '%SYSTEM$WAIT%'
  AND query_text NOT ILIKE '%INFORMATION_SCHEMA%'
  AND query_text NOT ILIKE '%ACCOUNT_USAGE.QUERY_HISTORY%'
ORDER BY start_time DESC
LIMIT 10
;

USE ROLE SYSADMIN;

-- If a second cluster started, expect to see MORE THAN ONE distinct
-- cluster_number (e.g. 0 and 1) among these rows. If everything shows
-- cluster_number = 0, the single cluster absorbed all the load without
-- needing the second one. Remember this check has ~45 min latency —
-- don't expect results immediately after the SYSTEM$WAIT sessions finish.


-- ══════════════════════════════════════════════════════════════════════
--  CLEANUP — revert to single-cluster
-- ══════════════════════════════════════════════════════════════════════
/*
Per the Goal 5 plan: this was always a temporary test. Reverting prevents
any future accidental multi-cluster credit spend on this warehouse.
*/

ALTER WAREHOUSE WORKBOOK_WH SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
;

SHOW WAREHOUSES LIKE 'WORKBOOK_WH';
-- Confirm max_cluster_count is back to 1 and started_clusters is back
-- to 1 as well.


-- ══════════════════════════════════════════════════════════════════════
--  PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════════
/*
1. Repeat Steps 1-5 with SCALING_POLICY = 'ECONOMY' instead of 'STANDARD'.
   Does the second cluster take noticeably longer to start (or not start
   at all within the same ~45 second window)? This is the real behavioral
   difference 5.5 could only describe conceptually.

2. Try the same test with only 2 concurrent SYSTEM$WAIT sessions instead
   of 4-5. Is there a rough threshold where a second cluster stops being
   triggered on this X-Small warehouse?

3. Once SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY catches up
   (latency applies), check whether the brief second-cluster period
   actually billed as a separate credit line, and roughly how many extra
   credits it cost for that short a window.

4. Try MAX_CLUSTER_COUNT = 3 with enough concurrent sessions (6-8 tabs) to
   see whether Snowflake ever uses a third cluster, or whether it's more
   conservative about going beyond 2 than about going from 1 to 2.
*/


-- ══════════════════════════════════════════════════════════════════════
--  WHAT IF
-- ══════════════════════════════════════════════════════════════════════
/*
Q: started_clusters stayed at 1 even with 4-5 SYSTEM$WAIT sessions running
   concurrently.
A: A real and useful result, not a failure. SYSTEM$WAIT sessions consume
   very little actual compute — they just hold a session open — so a
   single X-Small cluster may comfortably handle several of them at once
   without any real queuing. Multi-cluster scaling triggers on QUEUING,
   not on session count alone; if nothing is actually waiting, there's no
   signal for Snowflake to add a cluster. Try increasing the number of
   concurrent tabs, or substitute a real (but still cheap) query for
   SYSTEM$WAIT if this happens, and report what changes.

Q: cluster_number came back NULL on INFORMATION_SCHEMA.QUERY_HISTORY().
A: Confirmed on this workbook — this function's column list includes
   cluster_number, but it isn't actually populated there; it only has real
   values on SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY, which Step 5 now uses
   directly. This is the THIRD time in Goal 5 this exact pattern has shown
   up (5.1's partitions_scanned/bytes_spilled, 5.4's
   percentage_scanned_from_cache, now this) — worth treating as a general
   rule going forward rather than a one-off surprise: for anything beyond
   basic query identification/timing, assume INFORMATION_SCHEMA.QUERY_HISTORY()
   may not have it and check ACCOUNT_USAGE.QUERY_HISTORY first.

Q: ALTER WAREHOUSE failed on MIN_CLUSTER_COUNT/MAX_CLUSTER_COUNT.
A: Multi-cluster warehouses require Enterprise Edition or higher — confirm
   this account's edition if this errors, since it's the one hard
   prerequisite for this entire sub-task (unlike everything else in Goal 5
   so far, which has worked on Standard Edition too).

Q: I forgot to revert MAX_CLUSTER_COUNT back to 1 — is this urgent?
A: Not urgent in the sense of ongoing background cost (a second cluster
   only bills while it's actually running to absorb real queuing), but it
   does mean WORKBOOK_WH could unexpectedly spin up a second cluster
   later during normal Goal 5 work if enough concurrent activity happens
   by accident. Worth reverting promptly, same reasoning as 5.3's
   clustering key cleanup — remove the source of surprise cost, don't
   just rely on remembering it's there.

Q: Why alter WORKBOOK_WH directly instead of creating a separate throwaway
   multi-cluster warehouse, the way 5.5 used SCALE_TEST_WH?
A: Multi-cluster behavior needs to be observed on the SAME warehouse
   multiple concurrent sessions are actually hitting — creating a fresh
   throwaway warehouse wouldn't change that requirement, and reverting
   WORKBOOK_WH's cluster count back to 1 at the end achieves the same
   "leave nothing extra behind" goal as dropping a throwaway object would.
*/
