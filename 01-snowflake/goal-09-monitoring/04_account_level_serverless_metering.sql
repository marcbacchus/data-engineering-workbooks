/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9       : Monitor and Manage Costs
  Sub-task 9.4 : Account-Level Serverless Metering
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~20 min
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : 9.3 complete; ACCOUNTADMIN, or a role granted
                           IMPORTED PRIVILEGES on the SNOWFLAKE database
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  9.2 and 9.3 covered warehouse credits — compute you directly control.
  This sub-task covers everything else: ACCOUNT_USAGE.METERING_HISTORY,
  the one view that rolls up EVERY credit-consuming service in the
  account, warehouse and serverless alike, distinguished by a single
  SERVICE_TYPE column.

  This is where 9.1's warehouse-vs-serverless distinction stops being
  conceptual and becomes queryable: you'll confirm WORKBOOK_WH's totals
  reconcile against 9.3, then look for any serverless activity this
  workbook series has generated along the way (Goal 6's tasks, Goal 8's
  replication discussion, etc.) — and it's entirely possible you'll find
  little to none, which is itself a useful, confirmable result.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════

  METERING_HISTORY returns one row per SERVICE_TYPE per entity per hour.
  Core columns:

      SERVICE_TYPE                  what kind of service consumed credits
      START_TIME / END_TIME         hour bucket
      ENTITY_ID / ENTITY_TYPE       identifies the specific object (pipe,
                                     task, warehouse, table...) — newer
                                     columns, verify they exist (Step 4)
      NAME                          meaning varies BY SERVICE_TYPE — for
                                     WAREHOUSE_METERING this is the
                                     warehouse name; for others it may be
                                     a service label, a table name, or a
                                     composite client string
      DATABASE_NAME / SCHEMA_NAME   newer columns, NULL when the resource
                                     isn't tied to a specific db/schema
                                     (e.g. a warehouse never has one)
      CREDITS_USED_COMPUTE          compute portion
      CREDITS_USED_CLOUD_SERVICES   cloud-services portion
      CREDITS_USED                  = CREDITS_USED_COMPUTE +
                                       CREDITS_USED_CLOUD_SERVICES
      BYTES / ROWS / FILES          populated only for certain service
                                     types (e.g. FILES only for PIPE)

  SERVICE_TYPE is the column that finally makes the warehouse/serverless
  split from 9.1 concrete. A non-exhaustive but exam-relevant sample of
  values: WAREHOUSE_METERING (the warehouse compute you already measured
  in 9.2/9.3), PIPE (Snowpipe), SNOWPIPE_STREAMING, SERVERLESS_TASK,
  AUTO_CLUSTERING, MATERIALIZED_VIEW, SEARCH_OPTIMIZATION, REPLICATION,
  SERVERLESS_ALERTS, AI_SERVICES. Every one of these except
  WAREHOUSE_METERING is Snowflake-managed compute with no warehouse
  attached — exactly the distinction Step 5 of 9.1 was building toward.

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  Oracle sells extended capability as separately LICENSED options —
  Partitioning, Advanced Compression, Diagnostics Pack — each a fixed
  add-on cost you pay whether you use the feature heavily or barely at
  all. Snowflake's serverless features are separately METERED instead:
  Automatic Clustering, Search Optimization, and the rest cost nothing
  extra sitting idle, and only start consuming credits the moment
  they're actually doing work, tracked hour by hour in exactly this
  view. The practical shift: in Oracle, deciding whether to enable a
  paid feature is a procurement decision made once. In Snowflake, it's
  an ongoing usage decision you can observe and reverse — you see
  exactly what each feature cost you last week in METERING_HISTORY, and
  turning a feature off stops the meter immediately.
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;

-- Same access requirement as 9.3 — ACCOUNTADMIN or IMPORTED PRIVILEGES on
-- the SNOWFLAKE database. Confirm before Step 1 if you switched roles
-- since the last file.

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Credit usage by service type, month-to-date
═══════════════════════════════════════════════════════════════════════════

  The account-wide picture: which service types have actually consumed
  credits this month, and how much.
*/

SELECT
    service_type,
    SUM(credits_used)                AS total_credits_used,
    SUM(credits_used_compute)        AS total_credits_compute,
    SUM(credits_used_cloud_services) AS total_credits_cloud_services
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATE_TRUNC('month', CURRENT_DATE())
GROUP BY service_type
ORDER BY total_credits_used DESC;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Reconcile WAREHOUSE_METERING here against 9.3's total
═══════════════════════════════════════════════════════════════════════════

  WAREHOUSE_METERING in THIS view should match the sum across all
  warehouses from 9.3 Step 1, for the same window — same underlying
  billing, two different views into it.
*/

SELECT
    service_type,
    SUM(credits_used) AS total_credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE service_type = 'WAREHOUSE_METERING'
  AND start_time >= DATE_TRUNC('month', CURRENT_DATE())
GROUP BY service_type;

/*
  Compare this against 9.3 Step 1's SUM(credits_used) across all
  warehouses for the same month-to-date window — they should match
  (modulo the usual ACCOUNT_USAGE latency gap between two views that
  refresh on their own independent schedules).
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Isolate everything that ISN'T warehouse compute
═══════════════════════════════════════════════════════════════════════════

  This is the serverless side of the account — whatever shows up here
  has no warehouse behind it at all.
*/

SELECT
    service_type,
    name,
    SUM(credits_used) AS total_credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE service_type <> 'WAREHOUSE_METERING'
  AND start_time >= DATEADD('days', -90, CURRENT_DATE())
GROUP BY service_type, name
ORDER BY total_credits_used DESC;

/*
  Given the discovery from 9.1 Step 5 — every task in this workbook
  series was pinned to WORKBOOK_WH rather than run serverless — don't
  be surprised if this returns few or zero rows. An empty result here
  is a real, confirmable finding: it means this account's cost profile
  is almost entirely warehouse-driven, not a query mistake. That's
  actually the expected, common shape for a workbook/training account,
  and worth stating explicitly rather than assuming something's broken.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Check for the newer entity/database/schema columns
═══════════════════════════════════════════════════════════════════════════

  ENTITY_ID, ENTITY_TYPE, DATABASE_NAME, DATABASE_ID, SCHEMA_NAME, and
  SCHEMA_ID were added via a behavior-change bundle — confirm they exist
  on your account before writing anything that depends on them, same
  discipline as 9.3 Step 4.
*/

DESCRIBE VIEW SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY;

-- <placeholder> — confirm ENTITY_TYPE / DATABASE_NAME / SCHEMA_NAME
-- appear in the output above before running the query below.

/*
  If present, this breaks down credit usage by the actual Snowflake
  object type consuming them — a materially richer view than SERVICE_TYPE
  alone once your account has real serverless activity:

    SELECT
        service_type,
        entity_type,
        database_name,
        SUM(credits_used) AS total_credits_used
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
    WHERE start_time >= DATEADD('days', -90, CURRENT_DATE())
    GROUP BY service_type, entity_type, database_name
    ORDER BY total_credits_used DESC;

  Left commented out — uncomment only after confirming the columns exist.
*/

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. Re-run Step 1 with the window widened to the last 90 days instead of
     month-to-date. Does any SERVICE_TYPE besides WAREHOUSE_METERING show
     non-zero credits anywhere in that longer window? If so, which one,
     and can you tie it back to a specific Goal in this workbook series?

  2. CREDITS_USED is documented as NOT adjusted for the cloud-services
     rebate, meaning it can overstate actual billed cost. Rewrite Step 1
     to instead sum CREDITS_USED_COMPUTE alone, and compare the two
     totals for WAREHOUSE_METERING specifically. How large is the gap
     for this account?

  3. Snowpipe (SERVICE_TYPE = 'PIPE') populates a FILES column that
     WAREHOUSE_METERING never does. Write a query that would surface
     total files loaded via Snowpipe in the last 90 days, structured so
     it returns a clean zero (not an error) if no Snowpipe activity
     exists.

  4. Given the latency notes in this file, if you wanted the freshest
     possible confirmation that a resource monitor you're about to build
     in 9.7 is actually seeing recent credit activity, would you trust
     METERING_HISTORY for that, or reach back to 9.2's INFORMATION_SCHEMA
     function? Justify your answer using the specific latency figures
     documented in 9.2 vs. this file.
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: Step 3 came back completely empty. Did I do something wrong?
  A: No — as flagged in Step 3's comment, this workbook series has run
     every task on WORKBOOK_WH rather than serverless compute, and
     features like Automatic Clustering or Search Optimization were
     never enabled on ECOMMERCE's tables. A genuinely empty result is
     the expected finding for this specific account's history, not a
     query defect. If you want to SEE a non-empty row here for learning
     purposes, the cheapest way is to enable Search Optimization on a
     small table temporarily, run a qualifying query, then check back —
     optional, and not required to complete this sub-task.

  Q: Why does SNOWPIPE_STREAMING get its own 12-hour latency figure
     instead of the general 3-hour one?
  A: Snowpipe Streaming's billing model ingests rows continuously rather
     than in discrete batch loads, and Snowflake's documentation calls
     out a longer, separate latency window for when that continuous
     usage finally lands in METERING_HISTORY — a third, even longer
     latency tier layered on top of the general 3-hour and the
     cloud-services-specific 6-hour figures you already saw in 9.3.
     Three different latencies on one view, not two — worth remembering
     for the exam.

  Q: If NAME means something different for every SERVICE_TYPE, how do I
     know what it means for a type I haven't looked up yet?
  A: You don't guess — Snowflake's own column documentation spells out
     the NAME semantics per SERVICE_TYPE explicitly (warehouse name for
     WAREHOUSE_METERING, target table name for SNOWPIPE_STREAMING's
     first cost entry, a colon-separated client string for its second,
     the database name for COPY_FILES, and so on). Treat NAME as
     context-dependent and check the docs for any SERVICE_TYPE you
     haven't worked with before building a query that filters or groups
     on it.

  Q: Does this view replace WAREHOUSE_METERING_HISTORY from 9.3 for
     warehouse-specific analysis?
  A: No — METERING_HISTORY gives you the WAREHOUSE_METERING total per
     warehouse (via NAME) but nothing like 9.3's dedicated columns or
     its role as the documented, recommended source specifically for
     warehouse credit analysis. Use 9.3's view when warehouses are the
     whole story; use this view when you need the full account picture,
     warehouse and serverless together, in one place.
*/
