/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9       : Monitor and Manage Costs
  Sub-task 9.5 : Storage Cost Views
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~20 min
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : 9.4 complete; ACCOUNTADMIN, or a role granted
                           IMPORTED PRIVILEGES on the SNOWFLAKE database;
                           familiarity with Goal 8's TABLE_STORAGE_METRICS
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  9.2-9.4 covered compute credits. Storage is the other half of a
  Snowflake bill, and it has its own family of ACCOUNT_USAGE views —
  STORAGE_USAGE (account-wide) and DATABASE_STORAGE_USAGE_HISTORY
  (per-database). You already met a THIRD storage view back in Goal 8:
  TABLE_STORAGE_METRICS.

  The real lesson here isn't just "here are two more views" — it's that
  these three storage views are NOT interchangeable, and Snowflake's own
  documentation is explicit about which ones you can trust to reconcile
  against an actual bill and which ones are directional only. Treating
  them as equivalent is the mistake this sub-task is built to prevent.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════

  STORAGE_USAGE (account-wide, one row per day):
      USAGE_DATE
      STORAGE_BYTES                    table storage, including Time Travel
      STAGE_BYTES                      files in all internal stages
      FAILSAFE_BYTES
      HYBRID_TABLE_STORAGE_BYTES
      ARCHIVE_STORAGE_COOL_BYTES / ARCHIVE_STORAGE_COLD_BYTES /
      ARCHIVE_STORAGE_RETRIEVAL_TEMP_BYTES
  Latency: up to 2 hours. Documented explicitly as using "a different
  measurement approach than the one used for billing" — the numbers here
  will NOT match your invoice exactly.

  DATABASE_STORAGE_USAGE_HISTORY (per-database, one row per database per
  day):
      USAGE_DATE, DATABASE_ID, DATABASE_NAME, DELETED
      AVERAGE_DATABASE_BYTES           includes Time Travel
      AVERAGE_FAILSAFE_BYTES
      AVERAGE_HYBRID_TABLE_STORAGE_BYTES
      AVERAGE_ARCHIVE_STORAGE_COOL_BYTES / _COLD_BYTES
      AVERAGE_COOL_FAILSAFE_BYTES / AVERAGE_COLD_FAILSAFE_BYTES
  Latency: up to 3 hours. Documented explicitly as NOT designed to
  reconcile with your bill — "the sum of database-level usage in this
  view won't equal the billed storage for your account." It's suitable
  for comparing RELATIVE usage between databases over time, not for
  computing an exact chargeback figure.

  Contrast that against Goal 8's TABLE_STORAGE_METRICS, which IS
  documented as the view "used to calculate the storage billing for each
  table in the account" — table grain, ACTIVE_BYTES/TIME_TRAVEL_BYTES/
  FAILSAFE_BYTES broken out, and (per the Goal 8 discovery you already
  carry forward) requiring a TABLE_DROPPED IS NULL filter to isolate
  live objects from historical/dropped ones it also retains.

  So: three storage views, three different jobs.
      - TABLE_STORAGE_METRICS   → the one that maps to actual billing,
                                    at table grain
      - DATABASE_STORAGE_USAGE_HISTORY → directional, database-level
                                    trending only — do NOT use it to
                                    compute a real chargeback number
      - STORAGE_USAGE           → directional, account-level trending
                                    only — same caveat

  If you need a number that genuinely reconciles with the bill at the
  account or organization level, Snowflake's own guidance points to
  STORAGE_DAILY_HISTORY in ORGANIZATION_USAGE instead of either view in
  this sub-task — out of scope here, but worth knowing it exists the
  next time "which storage view do I actually trust" comes up.

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  Oracle and SQL Server don't have an equivalent to this "some views
  reconcile with billing, some are directional only" distinction,
  because storage in those platforms isn't billed by the platform at
  all — you provision fixed disk (a tablespace, a data file) and monitor
  it with views like DBA_SEGMENTS or sys.dm_db_file_space_usage purely
  to avoid running out of allocated space. There's no concept of
  "storage billing accuracy" to worry about, because the DBA already
  owns the disk regardless of how full it gets. Snowflake inverts this:
  storage is metered and billed continuously by Snowflake itself, which
  is exactly why it needs — and documents — multiple views at different
  grains and different fidelity levels, some safe for real chargeback
  math and some only safe for spotting a trend.
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;

-- Same ACCOUNT_USAGE access requirement as 9.3/9.4.

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Account-wide storage trend, last 30 days
═══════════════════════════════════════════════════════════════════════════*/

SELECT
    usage_date,
    storage_bytes,
    stage_bytes,
    failsafe_bytes,
    ROUND((storage_bytes + stage_bytes + failsafe_bytes) / POWER(1024, 3), 2)
        AS total_gb_approx
FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE
WHERE usage_date >= DATEADD('days', -30, CURRENT_DATE())
ORDER BY usage_date;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — ECOMMERCE database storage trend, last 30 days
═══════════════════════════════════════════════════════════════════════════*/

SELECT
    usage_date,
    database_name,
    ROUND(average_database_bytes / POWER(1024, 3), 2) AS avg_database_gb,
    ROUND(average_failsafe_bytes / POWER(1024, 3), 2) AS avg_failsafe_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE database_name = 'ECOMMERCE'
  AND usage_date >= DATEADD('days', -30, CURRENT_DATE())
ORDER BY usage_date;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Reconciliation check: directional view vs. billing-accurate view
═══════════════════════════════════════════════════════════════════════════

  Pull the most recent day's directional figure from Step 2 alongside
  the same-day sum of ACTIVE_BYTES from Goal 8's TABLE_STORAGE_METRICS,
  filtered to live objects only — the same TABLE_DROPPED IS NULL
  discipline from Goal 8's discoveries.
*/

SELECT
    'DATABASE_STORAGE_USAGE_HISTORY (directional)' AS source_view,
    MAX(usage_date)                                 AS as_of_date,
    ROUND(MAX(average_database_bytes) / POWER(1024, 3), 2) AS gb_reported
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE database_name = 'ECOMMERCE'
  AND usage_date = (
        SELECT MAX(usage_date)
        FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
        WHERE database_name = 'ECOMMERCE'
      )

UNION ALL

SELECT
    'TABLE_STORAGE_METRICS (billing-accurate)' AS source_view,
    CURRENT_DATE()                             AS as_of_date,
    ROUND(SUM(active_bytes) / POWER(1024, 3), 2) AS gb_reported
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE table_catalog = 'ECOMMERCE'
  AND table_dropped IS NULL;

/*
  Expect these two numbers to be in the same ballpark but NOT identical
  — different bytes counted (ACTIVE_BYTES alone vs. AVERAGE_DATABASE_
  BYTES which includes Time Travel), different measurement windows (a
  point-in-time snapshot vs. an averaged day), and DATABASE_STORAGE_
  USAGE_HISTORY's own documentation already tells you not to expect an
  exact match. A close-but-different result here is success, not a bug —
  it's the confirmation that these two views really do measure different
  things.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Fail-safe bytes: observability only, same as Goal 8
═══════════════════════════════════════════════════════════════════════════

  Carrying forward the Goal 8 discovery: Fail-safe is observability-only,
  no self-service recovery. These bytes are worth watching because they
  cost money, not because you can act on them directly the way you can
  with Time Travel retention.
*/

SELECT
    usage_date,
    database_name,
    ROUND(average_failsafe_bytes / POWER(1024, 3), 2) AS avg_failsafe_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE database_name = 'ECOMMERCE'
  AND usage_date >= DATEADD('days', -7, CURRENT_DATE())
ORDER BY usage_date;

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. STORAGE_USAGE is account-wide and includes STAGE_BYTES; DATABASE_
     STORAGE_USAGE_HISTORY is per-database and has no stage column at
     all. Why do you think stage storage isn't tracked per-database?
     (Hint: think about what a stage actually belongs to — a database
     schema, a table, or a user — and whether that mapping is always
     one-to-one with "a database.")

  2. Rewrite Step 2 to compare ECOMMERCE against every OTHER database in
     the account side by side for the most recent usage_date, ranked by
     avg_database_gb descending.

  3. If DATABASE_STORAGE_USAGE_HISTORY explicitly can't be trusted for
     exact chargeback, why would Snowflake ship a view that's admittedly
     imprecise for that purpose? What's it actually good for that
     TABLE_STORAGE_METRICS isn't?

  4. Using Step 1, identify whether STAGE_BYTES has grown meaningfully
     over the 30-day window. Given this workbook's usage of internal
     stages (Goal 2's data loading, Goal 7's sharing work), does a flat
     or shrinking STAGE_BYTES trend make sense, or would you have
     expected growth?
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: I need an exact number for what storage actually cost last month.
     Which of these views do I use?
  A: None of the three, strictly speaking — TABLE_STORAGE_METRICS gets
     you closest at table grain, but Snowflake's own guidance for a
     number that reconciles with billing at the account level points to
     STORAGE_DAILY_HISTORY in the ORGANIZATION_USAGE schema, not
     ACCOUNT_USAGE. If chargeback accuracy actually matters, that's the
     view to reach for — outside this sub-task's scope, but worth
     knowing it's there.

  Q: Why does DATABASE_STORAGE_USAGE_HISTORY even include a DELETED
     column if dropped databases can't accrue new storage usage?
  A: A dropped database can still be incurring Fail-safe storage cost
     for a period after it's dropped — the same "cost continues after
     the object is gone" pattern you saw with dropped tables in Goal 8's
     TABLE_STORAGE_METRICS. DELETED lets you distinguish an active
     database's row from a dropped one still showing historical usage,
     the same way TABLE_DROPPED IS NULL does for tables.

  Q: Step 3's two numbers were noticeably far apart, not just slightly
     different — did I do something wrong?
  A: Check first whether AVERAGE_DATABASE_BYTES in Step 2/3 is including
     Time Travel bytes that TABLE_STORAGE_METRICS's ACTIVE_BYTES
     deliberately excludes — that alone can account for a meaningful
     gap if this database has significant Time Travel retention or
     recent large DML. If the gap still looks unreasonably large after
     accounting for that, re-check the TABLE_DROPPED IS NULL filter on
     Step 3's TABLE_STORAGE_METRICS query — a missing filter there
     would double-count historical/dropped table generations.

  Q: Does AUTO_SUSPEND or warehouse sizing from 9.1 affect any of these
     storage numbers?
  A: No — storage and compute are billed completely independently in
     Snowflake's separated-storage-and-compute architecture (9.1's
     Oracle/SQL Server comparison). A suspended warehouse doesn't reduce
     storage bytes, and a running warehouse doesn't increase them; the
     only thing that changes STORAGE_BYTES/AVERAGE_DATABASE_BYTES is
     actual data volume, Time Travel retention, and Fail-safe.
*/
