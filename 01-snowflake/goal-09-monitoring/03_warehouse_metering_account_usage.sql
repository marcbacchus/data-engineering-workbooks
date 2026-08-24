/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9       : Monitor and Manage Costs
  Sub-task 9.3 : Warehouse Metering — ACCOUNT_USAGE
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~20 min
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : 9.2 complete; ACCOUNTADMIN, or a role granted
                           IMPORTED PRIVILEGES on the SNOWFLAKE database
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  9.2 got you real numbers fast, but capped at 6 months and flagged as
  deprecated. Now you move to the view Snowflake actually recommends for
  this: SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY — a full year
  of retention, a richer column set, and the same latency trade-off
  you've hit with every other ACCOUNT_USAGE view since Goal 5: it's not
  live, and different columns on the SAME view can lag by different
  amounts.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════

  ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY is a plain VIEW, not a table
  function — no TABLE(...) wrapper, no positional/named arguments. You
  filter it with an ordinary WHERE clause instead.

  Core columns:
      START_TIME                    hour bucket start
      END_TIME                      hour bucket end
      WAREHOUSE_ID                  numeric warehouse identifier
      WAREHOUSE_NAME                VARCHAR
      CREDITS_USED                  total credits billed for that hour
      CREDITS_USED_COMPUTE          compute portion
      CREDITS_USED_CLOUD_SERVICES   cloud-services portion

  Some accounts, depending on which behavior-change bundles are enabled,
  may also expose CREDITS_ATTRIBUTED_COMPUTE_QUERIES (credits actually
  tied to running queries, excluding idle time) — check for it with
  DESCRIBE VIEW before relying on it; don't assume it's present.

  Two things carried forward from Goal 5 and worth re-confirming here
  rather than assuming:

    - Retention: 1 year, vs. 6 months for the Information Schema
      function in 9.2.
    - Latency: up to 180 minutes (3 hours) for most columns, but up to
      360 minutes (6 hours) specifically for CREDITS_USED_CLOUD_SERVICES.
      This is exactly the "don't assume a blanket ~3hr figure applies
      uniformly across every ACCOUNT_USAGE view — or even every column
      on the same view" lesson from Goal 5/8: here it's two different
      latencies on ONE view, not two different views.

  Access: by default only ACCOUNTADMIN can query anything in the
  SNOWFLAKE database's ACCOUNT_USAGE schema. To grant a narrower role
  access, ACCOUNTADMIN runs:

      GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE <role_name>;

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  ACCOUNT_USAGE's async-materialized-with-defined-latency design isn't
  unprecedented — it's the same shape as Oracle's AWR (Automatic
  Workload Repository): both capture activity into periodic snapshots
  rather than exposing it live, and both have a defined retention window
  after which older snapshots are purged. The difference is what drives
  the snapshot cycle: AWR snapshots on a fixed interval (default hourly)
  that a DBA configures, while ACCOUNT_USAGE's refresh cadence is fully
  managed by Snowflake and varies by view — you don't get a knob to make
  it faster, only the documented latency figure to plan around.
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;

/*
  <placeholder> — confirm your active role can query ACCOUNT_USAGE before
  Step 1. If not, as ACCOUNTADMIN:

    GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE <your_role>;

  As with 9.2, a missing privilege here returns zero rows, not an error —
  don't mistake it for "no usage."
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Total credits per warehouse, month-to-date
═══════════════════════════════════════════════════════════════════════════*/

SELECT
    warehouse_name,
    SUM(credits_used) AS total_credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATE_TRUNC('month', CURRENT_DATE())
GROUP BY warehouse_name
ORDER BY total_credits_used DESC;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Daily trend for WORKBOOK_WH
═══════════════════════════════════════════════════════════════════════════

  Rolling hourly buckets up to a daily grain makes it far easier to spot
  a day where usage spiked versus scanning raw hourly rows.
*/

SELECT
    start_time::DATE       AS usage_date,
    warehouse_name,
    SUM(credits_used)      AS daily_credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'WORKBOOK_WH'
  AND start_time >= DATEADD('days', -30, CURRENT_DATE())
GROUP BY usage_date, warehouse_name
ORDER BY usage_date;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Reconcile against 9.2's INFORMATION_SCHEMA total
═══════════════════════════════════════════════════════════════════════════

  Same warehouse, same 10-day window, two sources. They should be close.
  If they don't match exactly, that's expected — ACCOUNT_USAGE latency
  means the most recent hour or two may not have landed here yet even
  though INFORMATION_SCHEMA already showed it in 9.2.
*/

SELECT
    warehouse_name,
    SUM(credits_used) AS total_credits_used_account_usage
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'WORKBOOK_WH'
  AND start_time >= DATEADD('days', -10, CURRENT_DATE())
GROUP BY warehouse_name;

/*
  Compare this total_credits_used_account_usage figure against 9.2 Step
  3's total_credits_used from INFORMATION_SCHEMA over the identical
  10-day window. A gap here is a latency artifact, not a data-quality
  bug — re-run this step a few hours later and expect it to converge.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Check for CREDITS_ATTRIBUTED_COMPUTE_QUERIES before using it
═══════════════════════════════════════════════════════════════════════════

  This column tracks credits genuinely tied to running queries and
  excludes idle time — useful for an "idle cost" calculation — but it
  ships via a behavior-change bundle and may not be enabled on every
  account. Confirm it exists here before writing anything downstream
  that depends on it.
*/

DESCRIBE VIEW SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY;

-- <placeholder> — scan the DESCRIBE VIEW output above for a row named
-- CREDITS_ATTRIBUTED_COMPUTE_QUERIES before running the query below.

/*
  If (and only if) that column is present, this calculates idle cost —
  compute credits billed but not attributable to any actual query:

    SELECT
        warehouse_name,
        SUM(credits_used_compute) - SUM(credits_attributed_compute_queries) AS idle_cost
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE start_time >= DATEADD('days', -10, CURRENT_DATE())
      AND end_time   <  CURRENT_DATE()
    GROUP BY warehouse_name;

  Left commented out deliberately — uncomment only after confirming the
  column exists in Step 4's DESCRIBE output; running it against an
  account without the column raises a column-not-found error.
*/

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. Run Step 3 now, wait at least 3 hours, and run it again. Did the
     total change? What does that tell you about whether the first run
     had fully "settled" data?

  2. Step 2 aggregates to a daily grain with DATE_TRUNC-style casting
     (start_time::DATE). Rewrite it to aggregate by ISO week instead.
     Which single function/expression change accomplishes that?

  3. If you ran Step 1 as a role that only has IMPORTED PRIVILEGES (not
     ACCOUNTADMIN), would you see warehouses OTHER users created, or
     only ones you have some relationship to? Test it if you have a
     second role available; if not, reason through it from what
     IMPORTED PRIVILEGES actually grants.

  4. Using Steps 1-2, identify which single day in the last 30 shows
     the highest WORKBOOK_WH credit consumption. Cross-reference that
     date against your own memory of which Goal you were working on —
     does the spike line up with a goal you know involved heavier
     compute (e.g. Goal 8's schema/database clone timing tests)?
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: 9.2's function is "deprecated" and this view is 1 year vs. 6
     months — should I ever use 9.2's function again?
  A: Yes, for anything where you want the freshest possible answer and
     can tolerate a narrower column set — INFORMATION_SCHEMA table
     functions generally reflect activity sooner than ACCOUNT_USAGE's
     latency window allows. Use 9.2 for "what's happening right now,"
     this view for "give me the full trend and let me build a real
     report on it."

  Q: Why does CREDITS_USED_CLOUD_SERVICES get its own, longer latency
     figure instead of just inheriting the view's general 3-hour number?
  A: Cloud Services credit attribution requires additional aggregation
     across account-wide metadata operations before it can be finalized
     — Snowflake documents this as a genuinely separate pipeline from
     the compute-credit rollup, which is why it's called out with its
     own number rather than folded into the general figure.

  Q: I don't have ACCOUNTADMIN and can't get IMPORTED PRIVILEGES granted
     right now — is there anything I can still do?
  A: Fall back to 9.2's INFORMATION_SCHEMA function if your role has
     MONITOR USAGE — it's a materially lower privilege bar than
     ACCOUNT_USAGE access, and for warehouse-level totals it may already
     answer your question without needing this view at all.

  Q: Is WAREHOUSE_ID ever more reliable to group by than WAREHOUSE_NAME?
  A: Yes, in one specific case: if a warehouse was ever dropped and
     re-created under the SAME name, WAREHOUSE_NAME collapses both
     "generations" of that warehouse together in a GROUP BY, while
     WAREHOUSE_ID keeps them distinct. For WORKBOOK_WH, which has never
     been dropped in this workbook series, the two group identically —
     but it's worth knowing which column to reach for if that ever
     changes.
*/
