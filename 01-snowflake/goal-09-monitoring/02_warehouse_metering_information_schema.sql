/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9       : Monitor and Manage Costs
  Sub-task 9.2 : Warehouse Metering — INFORMATION_SCHEMA
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~20 min
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : 9.1 complete; ACCOUNTADMIN or a role granted the
                           MONITOR USAGE global privilege
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  9.1 gave you the credit model. Now you go get actual numbers for
  WORKBOOK_WH: the INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY table
  function returns real, per-warehouse, per-hour credit consumption —
  no waiting on ACCOUNT_USAGE's latency, because Information Schema table
  functions read closer to real time.

  You'll also learn the two things that make this function a stepping
  stone rather than a destination: it caps at 6 months of history, and
  Snowflake's own documentation now marks it as generally deprecated in
  favor of the ACCOUNT_USAGE view — which is exactly where 9.3 goes next.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════

  WAREHOUSE_METERING_HISTORY (Information Schema) returns one row per
  warehouse per HOUR, within a date range you specify:

      WAREHOUSE_METERING_HISTORY(
          DATE_RANGE_START => <constant_expr>,
          [ DATE_RANGE_END => <constant_expr> ],
          [ WAREHOUSE_NAME => '<string>' ]
      )

  Output columns:
      START_TIME                    hour bucket start (TIMESTAMP_LTZ)
      END_TIME                      hour bucket end   (TIMESTAMP_LTZ)
      WAREHOUSE_NAME                VARCHAR
      CREDITS_USED                  total credits billed for that hour
      CREDITS_USED_COMPUTE          the compute portion of CREDITS_USED
      CREDITS_USED_CLOUD_SERVICES   the cloud-services portion

  Two constraints worth internalizing before you rely on this function:

    - Access is NOT open to every role. It returns results only for
      ACCOUNTADMIN or a role explicitly granted the MONITOR USAGE global
      privilege — unlike most INFORMATION_SCHEMA object metadata, which
      is visible more broadly.
    - It does not include Adaptive Warehouse usage, and Snowflake's docs
      mark the function itself as generally deprecated in favor of
      ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY, which has a more complete
      data set and a much longer retention window. Treat this function as
      the "what's happening right now / this week" tool, and 9.3's
      ACCOUNT_USAGE view as the system of record.

  This mirrors the INFORMATION_SCHEMA-vs-ACCOUNT_USAGE trade-off you
  already hit with QUERY_HISTORY back in Goal 5: narrower/fresher here,
  broader/laggier there.

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  Neither Oracle nor SQL Server has a built-in equivalent to per-warehouse
  hourly credit metering, because neither bills compute in metered units
  in the first place — cost tracking in those platforms means watching
  CPU/license utilization against a fixed provisioned capacity (AWR
  reports in Oracle, DMVs like sys.dm_os_performance_counters in SQL
  Server), not querying a first-class "here's what you were billed"
  table. WAREHOUSE_METERING_HISTORY is closer in spirit to a cloud
  provider's billing API than to anything in traditional on-prem
  performance monitoring — it's answering "what did this cost," not
  "how hard is this machine working."
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;

/*
  This function requires ACCOUNTADMIN or MONITOR USAGE. If your active
  role doesn't have it, switch roles before continuing:

    USE ROLE ACCOUNTADMIN;

  <placeholder> — confirm your active role has the needed privilege
  before Step 1; the query will return zero rows (not an error) if it
  doesn't.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — All warehouses, last 10 days
═══════════════════════════════════════════════════════════════════════════

  Positional arguments (no keywords) — DATE_RANGE_START only, so
  DATE_RANGE_END defaults to CURRENT_DATE and WAREHOUSE_NAME defaults to
  all warehouses that ran in the window.
*/

SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
        DATEADD('days', -10, CURRENT_DATE())
    )
)
ORDER BY warehouse_name, start_time;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — WORKBOOK_WH only, named arguments
═══════════════════════════════════════════════════════════════════════════

  Named arguments let you specify WAREHOUSE_NAME without also having to
  supply DATE_RANGE_END — order stops mattering once you use keywords.
*/

SELECT
    start_time,
    end_time,
    warehouse_name,
    credits_used,
    credits_used_compute,
    credits_used_cloud_services
FROM TABLE(
    INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
        DATE_RANGE_START => DATEADD('days', -10, CURRENT_DATE()),
        WAREHOUSE_NAME   => 'WORKBOOK_WH'
    )
)
ORDER BY start_time;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Roll up to a single total
═══════════════════════════════════════════════════════════════════════════

  The hourly grain is useful for spotting spikes, but for a quick "how
  much has this warehouse cost me lately" answer, aggregate it.
*/

SELECT
    warehouse_name,
    SUM(credits_used)                AS total_credits_used,
    SUM(credits_used_compute)        AS total_credits_compute,
    SUM(credits_used_cloud_services) AS total_credits_cloud_services,
    COUNT(*)                         AS billed_hours
FROM TABLE(
    INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
        DATE_RANGE_START => DATEADD('days', -10, CURRENT_DATE()),
        WAREHOUSE_NAME   => 'WORKBOOK_WH'
    )
)
GROUP BY warehouse_name;

/*
  billed_hours here counts distinct HOUR BUCKETS with activity, not
  wall-clock hours of runtime — a warehouse that runs for 3 minutes
  inside a single clock hour still produces exactly one row for that
  hour. Don't read this column as "hours the warehouse was up."
*/

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. Re-run Step 1 without ORDER BY. Confirm the result is already sorted
     — by which two columns, per the documented output guarantee?

  2. Change Step 3's window to the last 30 days instead of 10. Does
     billed_hours grow roughly in proportion to how often you've been
     running WORKBOOK_WH through Goals 1-8, or does it look sparse? What
     does a sparse result tell you about how disciplined the AUTO_SUSPEND
     setting from 9.1 has been?

  3. Try calling the function with a DATE_RANGE_START more than 6 months
     in the past. What happens, and why — tie your answer back to the
     documented range limit.

  4. If CREDITS_USED_CLOUD_SERVICES is consistently 0 or near-0 across
     every row for WORKBOOK_WH, what does that tell you about how much
     of this warehouse's billing is compute vs. cloud services? (Recall
     from 9.1's WHAT IF: Cloud Services isn't billed at all until it
     exceeds 10% of daily compute credits — small numbers here are
     expected, not a bug.)
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: I ran this as a role without MONITOR USAGE and got zero rows, not
     an error. How do I know it's a privilege problem and not just "no
     usage in this window"?
  A: Switch to ACCOUNTADMIN (or a role you know has MONITOR USAGE) and
     re-run the identical query. If rows appear, it was a privilege gap;
     Snowflake silently returns an empty result set here rather than
     raising an access-denied error — worth remembering, since it can
     look identical to "genuinely no activity."

  Q: This function is deprecated — should I even be learning it, or
     should I skip straight to ACCOUNT_USAGE in 9.3?
  A: Learn it. "Generally deprecated" means ACCOUNT_USAGE is now the
     recommended source of truth for anything beyond quick, recent
     checks — it doesn't mean this function is gone or exam-irrelevant.
     COF-C03 domain 2.0 explicitly calls out calculating virtual
     warehouse credit usage and the ACCOUNT_USAGE schema as separate
     study points, which implies you're expected to know both the
     Information Schema and ACCOUNT_USAGE paths, and when each applies.

  Q: Why does the function return HOURLY buckets instead of per-query or
     per-second detail?
  A: Warehouse billing itself settles into hourly credit totals for
     reporting purposes even though the underlying meter runs per-second
     (per 9.1). If you need query-level cost attribution instead of
     warehouse-level totals, that's a different tool — QUERY_HISTORY
     (execution time, bytes scanned) or, later, QUERY_TAG-based
     attribution in 9.6 — not this function.

  Q: Does WAREHOUSE_METERING_HISTORY include serverless costs like
     Snowpipe or Automatic Clustering?
  A: No — this function is scoped to WAREHOUSE compute only, by
     definition (it's keyed on WAREHOUSE_NAME). Serverless credit usage
     has no warehouse to attach to and shows up separately in
     ACCOUNT_USAGE.METERING_HISTORY, which is 9.4's topic.
*/
