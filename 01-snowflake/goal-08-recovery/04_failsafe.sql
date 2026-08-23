/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8       : Recover from Mistakes
  Sub-task 8.4 : Fail-Safe — The Non-Configurable Last Resort
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~20 minutes
  Warehouse size    : X-Small (WORKBOOK_WH)
  Database          : ECOMMERCE
  Run in            : Snowsight
  Prerequisites     : 8.1-8.3 complete
  COF-C03 domain    : 1.0 Snowflake AI Data Cloud Features & Architecture (31%)
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  Unlike 8.1-8.3, there's nothing to self-service recover here — Fail-safe
  is Snowflake-support-only, so this sub-task is entirely about
  observability: understanding what Fail-safe actually protects, seeing
  how much storage it's costing you right now via TABLE_STORAGE_METRICS,
  and knowing what to do (and who to call) if you ever actually need it.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════
  Fail-safe is a separate, non-configurable 7-day protection period that
  starts the moment an object's Time Travel retention period ends. During
  those 7 days, historical data may still be recoverable — but only by
  Snowflake Support, on a best-effort basis, as a last resort after every
  self-service option (Time Travel, UNDROP) has been exhausted.

  Key differences from Time Travel:
    - Not configurable at all — always exactly 7 days for eligible objects
    - PERMANENT tables only. Transient and temporary tables have ZERO
      Fail-safe — once their Time Travel window closes, that's it,
      nothing behind it.
    - Not self-service — no SQL command reaches it. Recovery requires
      opening a support ticket, can take hours to days, and Snowflake
      may determine the data isn't recoverable at all.
    - Recovery uses Snowflake-managed serverless compute billed
      separately from storage (metering history service type
      FAILSAFE_RECOVERY) — Fail-safe has a real cost dimension beyond
      just the storage it occupies while waiting.
    - Not supported at all for tables ingested via Snowpipe Streaming
      Classic — Fail-safe operations on those tables fail outright.

  You can't test Fail-safe recovery yourself the way 8.1-8.2 tested Time
  Travel and UNDROP live — there's no self-service trigger, and it
  wouldn't be responsible to actually burn a support ticket for a
  workbook exercise. What you CAN do is see it: every table you own is
  already reporting how many bytes it's holding in Fail-safe right now.

  ── Oracle / SQL Server comparison ─────────────────────────────────────
  Neither Oracle nor SQL Server has a direct analog to Fail-safe as an
  automatic, zero-setup safety net behind the self-service recovery
  window. Oracle's closest tools — RMAN backups, Flashback Database (which
  itself requires a configured Flash Recovery Area) — are infrastructure
  YOU provision and maintain; nothing comparable exists automatically just
  because a table is permanent. SQL Server is the same story: recovery
  past what your own backup strategy covers doesn't exist. Fail-safe's
  real distinction for this audience isn't that it's better than a backup
  strategy — it's that it exists automatically, for every permanent
  table, whether or not anyone set up a backup strategy at all. The
  tradeoff is control: you can't test it, tune it, or self-serve it.
  ────────────────────────────────────────────────────────────────────────
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE DATABASE ECOMMERCE;
USE SCHEMA RAW;
USE WAREHOUSE WORKBOOK_WH;
USE ROLE ACCOUNTADMIN;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — See current Fail-safe storage by table
═══════════════════════════════════════════════════════════════════════════
  TABLE_STORAGE_METRICS breaks storage into ACTIVE / TIME_TRAVEL /
  FAILSAFE / RETAINED_FOR_CLONE bytes. Requires ACCOUNTADMIN. This view's
  latency is up to ~90 minutes specifically (a tighter number than the
  general ~3 hr ACCOUNT_USAGE latency noted back in Goal 5 — worth
  distinguishing per-view rather than assuming the general figure
  everywhere).
───────────────────────────────────────────────────────────────────────────*/

SELECT
    table_catalog,
    table_schema,
    table_name,
    active_bytes / (1024*1024*1024)      AS active_gb,
    time_travel_bytes / (1024*1024*1024) AS time_travel_gb,
    failsafe_bytes / (1024*1024*1024)    AS failsafe_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE table_catalog = 'ECOMMERCE'
ORDER BY failsafe_bytes DESC
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Identify which tables are the biggest Fail-safe cost drivers
═══════════════════════════════════════════════════════════════════════════
  High FAILSAFE_BYTES relative to ACTIVE_BYTES points at high-churn
  tables (frequent UPDATE/DELETE/MERGE) with long retention — exactly the
  candidates worth reconsidering as transient, per the Oracle-comparison
  note above about Fail-safe having a real, if usually small, cost.
───────────────────────────────────────────────────────────────────────────*/

SELECT
    table_name,
    active_bytes / (1024*1024*1024)   AS active_gb,
    failsafe_bytes / (1024*1024*1024) AS failsafe_gb,
    CASE
        WHEN active_bytes = 0 THEN NULL
        ELSE ROUND(failsafe_bytes / active_bytes, 4)
    END AS failsafe_to_active_ratio
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE table_catalog = 'ECOMMERCE'
  AND active_bytes > 0
ORDER BY failsafe_to_active_ratio DESC NULLS LAST
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Confirm transient tables report zero Fail-safe, always
═══════════════════════════════════════════════════════════════════════════
  A direct check against the transient sandbox table from 8.1/8.2/8.3 —
  expect failsafe_bytes = 0 regardless of how much DML activity it's
  seen, since transient tables never have a Fail-safe period at all.
  (This queries TABLE_STORAGE_METRICS, same as STEPs 1-2 — TABLES only
  has a single undifferentiated BYTES column, not the ACTIVE/FAILSAFE
  breakdown.)
───────────────────────────────────────────────────────────────────────────*/

SELECT
    table_name,
    active_bytes / (1024*1024*1024)   AS active_gb,
    failsafe_bytes / (1024*1024*1024) AS failsafe_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE table_catalog = 'ECOMMERCE'
  AND table_schema = 'RAW'
  AND table_name LIKE '%TT_SANDBOX%'
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Fail-safe recovery's separate compute cost
═══════════════════════════════════════════════════════════════════════════
  If Fail-safe recovery has ever been performed on this account, it shows
  up here as its own serverless service type — separate from normal
  warehouse compute and separate from storage billing. Expect zero rows
  for a training account that's never filed a Fail-safe recovery request.
───────────────────────────────────────────────────────────────────────────*/

SELECT
    service_type,
    start_time,
    end_time,
    credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE service_type = 'FAILSAFE_RECOVERY'
ORDER BY start_time DESC
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 5 — Where to look in Snowsight (no SQL for this one)
═══════════════════════════════════════════════════════════════════════════
  Account-wide Fail-safe storage is also visible in the UI, as a
  color-coded breakdown alongside active and Time Travel storage:
  Snowsight > Admin > Cost Management > Consumption. Requires
  ACCOUNTADMIN, same as the queries above.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CLEANUP
═══════════════════════════════════════════════════════════════════════════
  Nothing created in this sub-task — everything here is read-only
  observability against existing storage metrics. Switch back to
  SYSADMIN for the next sub-task.
───────────────────────────────────────────────────────────────────────────*/

USE ROLE SYSADMIN;


/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════
  1. Besides converting a table to transient, is there any way to reduce
     its Fail-safe storage cost while keeping it permanent? Consider what
     actually drives FAILSAFE_BYTES (changed/deleted data volume) versus
     what DATA_RETENTION_TIME_IN_DAYS controls (how long that data stays
     in Time Travel before Fail-safe) — does shortening retention reduce
     the Fail-safe cost, or just move the same cost earlier?

  2. Run STEP 1's query against the full account (drop the
     table_catalog filter) and find the single table account-wide with
     the highest FAILSAFE_BYTES. Is it one of the large ECOMMERCE.RAW
     source tables, or something else? What does that tell you about
     which tables are actually driving Fail-safe storage cost versus
     which ones are just large?

  3. SNOWFLAKE.ACCOUNT_USAGE.TABLES has an IS_TRANSIENT column used in
     STEP 3. Find a query that confirms whether TEMPORARY tables show up
     in this view at all, given they're session-scoped and purged when
     the session ends.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════
  Q: I set a permanent table's DATA_RETENTION_TIME_IN_DAYS to 0 (from
     8.3, STEP 5) — does that skip Fail-safe too?
  A: No. Retention 0 only removes the Time Travel window; the object is
     still permanent, so any dropped/changed data goes straight into the
     7-day Fail-safe period immediately rather than sitting in Time
     Travel first. Fail-safe for permanent tables can't be disabled —
     only the table TYPE (transient/temporary) removes it entirely.

  Q: Can ACCOUNTADMIN trigger Fail-safe recovery directly with a SQL
     command, given ACCOUNTADMIN can do almost everything else?
  A: No — there is no SQL command, role, or privilege level that reaches
     Fail-safe recovery. It's a support-ticket-only process regardless of
     role.

  Q: If I CREATE OR REPLACE a permanent table, does the replaced (old)
     version's data still eventually land in Fail-safe?
  A: Yes — CREATE OR REPLACE is an atomic drop-and-create (same fact
     noted for UNDROP purposes in 8.2's WHAT IF), so the old version
     follows the normal Time-Travel-then-Fail-safe path exactly as if it
     had been dropped directly.

  Q: Does Fail-safe protect against a compromised/malicious ACCOUNTADMIN
     deliberately trying to destroy data permanently?
  A: Not indefinitely — Fail-safe is a 7-day window, not an immutable
     audit trail. Someone with sufficient privilege who drops an object,
     waits past both Time Travel and the 7-day Fail-safe period, has
     created genuinely unrecoverable data loss. Fail-safe is protection
     against mistakes and short-notice disasters, not a substitute for
     access control or external backup strategy against insider threats.
───────────────────────────────────────────────────────────────────────────*/
