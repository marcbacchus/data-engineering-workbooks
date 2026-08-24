/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author    : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9    : Monitor and Manage Costs
  Capstone  : Cost Incident — Diagnose, Attribute, Contain
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~30 min (placeholder — confirm after live test)
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : 9.1-9.9 complete (GOAL9_WORKBOOK_MONITOR exists
                           and is assigned to WORKBOOK_WH from 9.7)
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  Every prior Goal 9 file exercised ONE technique at a time. This
  capstone runs a single simulated incident end to end, the same way
  Goal 8's capstone combined Time Travel + UNDROP + clone-and-swap into
  one recovery narrative instead of testing each in isolation.

  The scenario: WORKBOOK_WH's spend looks higher than expected this
  week. You need to (1) confirm there really is a spike rather than
  normal variance, (2) find the specific query or job responsible, and
  (3) put a guardrail in place so the same pattern gets caught
  automatically next time — combining 9.2/9.3 (warehouse-level metering),
  9.6 (query-level attribution via QUERY_TAG), and 9.7/9.8 (resource
  monitor containment) into one investigation.

  A genuine constraint worth stating up front: this account can't
  ethically or economically manufacture a REAL multi-credit cost spike
  just to investigate it (that's exactly the "burn ~1 hour and 1 credit
  to watch a trigger fire" trade-off 9.7 already declined for the same
  reason). So Step 1 SIMULATES the incident with a small number of
  deliberately wasteful but genuinely cheap queries, clearly tagged as
  synthetic. Steps 2 onward then investigate that real (if small)
  footprint using the exact same techniques you'd use on a genuinely
  expensive incident — the diagnostic method is real even though the
  underlying dollar amount is deliberately kept trivial.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT — this capstone doesn't introduce new material
═══════════════════════════════════════════════════════════════════════════

  Every technique below was covered in its own file earlier in Goal 9:
      9.2  INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY (fresh, narrow)
      9.3  ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY (laggy, complete)
      9.6  QUERY_TAG + QUERY_ATTRIBUTION_HISTORY (per-query cost)
      9.7  CREATE/ALTER RESOURCE MONITOR (containment)
      9.8  Resource monitor assignment & scope (confirming containment
           actually applies where you think it does)

  What's new here is the ORDER and PURPOSE they're chained in: a real
  incident investigation almost never starts with "let me query
  QUERY_ATTRIBUTION_HISTORY" — it starts with "does the warehouse-level
  number even look wrong," and only drills down to query-level once
  that's confirmed. Skipping straight to query-level detail without
  first confirming there's a real anomaly at the warehouse level is a
  common practical mistake this capstone is structured to avoid.

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  This diagnose-attribute-contain sequence mirrors how an Oracle DBA
  would approach a sudden CPU/IO spike: first confirm the anomaly at the
  instance level (AWR/OS-level metrics), then drill into DBA_HIST_SQLSTAT
  for the specific SQL_ID responsible, then apply a Resource Manager
  consumer-group limit to contain that specific workload going forward.
  The investigative SHAPE transfers directly across platforms even
  though the underlying billing model (metered credits vs. fixed
  provisioned capacity) is completely different — confirming, once
  again, that operational discipline generalizes even where the
  specific tools don't.
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE ROLE ACCOUNTADMIN;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — SIMULATE: a synthetic "suspect job" runs, tagged distinctly
═══════════════════════════════════════════════════════════════════════════

  A deliberately wasteful pattern — repeated full scans instead of one
  — standing in for a badly-written ETL job. Genuinely cheap on this
  table/warehouse size, but real, executed queries with real (small)
  credit attribution, not a hypothetical.
*/

ALTER SESSION SET QUERY_TAG = 'suspect_etl_job_v2';

SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS;
SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS;
SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS;
SELECT o.order_id, c.customer_id
FROM ECOMMERCE.RAW.ORDERS o
JOIN ECOMMERCE.RAW.CUSTOMERS c ON o.customer_id = c.customer_id;

ALTER SESSION UNSET QUERY_TAG;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — DIAGNOSE: is WORKBOOK_WH's usage actually elevated?
═══════════════════════════════════════════════════════════════════════════

  Start at the warehouse level, per the CONCEPT section's ordering —
  confirm there's a real signal before drilling into query detail.
  INFORMATION_SCHEMA first for the freshest possible read (9.2):
*/

SELECT
    start_time,
    end_time,
    credits_used
FROM TABLE(
    INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
        DATE_RANGE_START => DATEADD('hours', -6, CURRENT_TIMESTAMP()),
        WAREHOUSE_NAME   => 'WORKBOOK_WH'
    )
)
ORDER BY start_time;

-- Then the longer trend from ACCOUNT_USAGE (9.3), to judge today
-- against a realistic recent baseline rather than against nothing:
SELECT
    start_time::DATE  AS usage_date,
    SUM(credits_used) AS daily_credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'WORKBOOK_WH'
  AND start_time >= DATEADD('days', -14, CURRENT_DATE())
GROUP BY usage_date
ORDER BY usage_date;

/*
  Judgment call, not a hard threshold: compare today's total against
  the trailing days above. On a training account with generally light,
  irregular usage, a "spike" may be genuinely small in absolute credits
  — the investigative METHOD matters here more than hitting some
  dramatic number.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — ATTRIBUTE: which query pattern is actually responsible?
═══════════════════════════════════════════════════════════════════════════

  Now drill into query-level detail (9.6), using the QUERY_TAG from
  Step 1 as the filter — exactly how a real investigation would use a
  team/job tag to isolate a suspect workload from everything else
  running on the same warehouse.
*/

SELECT
    qh.query_id,
    qh.query_tag,
    qh.execution_time,
    qh.bytes_scanned,
    qa.credits_attributed_compute
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY qa
  ON qh.query_id = qa.query_id
WHERE qh.query_tag = 'suspect_etl_job_v2'
  AND qh.start_time >= DATEADD('hours', -1, CURRENT_TIMESTAMP())
ORDER BY qa.credits_attributed_compute DESC;

/*
  Remember 9.6's latency note: QUERY_ATTRIBUTION_HISTORY can lag up to
  8 hours. If this returns nothing yet, that's the expected gap, not a
  failed investigation — the INFORMATION_SCHEMA-based confirmation in
  Step 1's own session output (or plain QUERY_HISTORY) is your
  immediate-term evidence while you wait for attribution to catch up.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — CONTAIN: tighten the guardrail so this gets caught earlier
═══════════════════════════════════════════════════════════════════════════

  Rather than create a third monitor, tighten 9.7's existing
  GOAL9_WORKBOOK_MONITOR — reusing and adjusting a real guardrail is
  more realistic incident response than spinning up a new object every
  time. Adding an earlier NOTIFY threshold is the concrete containment
  action: it doesn't stop THIS incident (already happened), it shortens
  the detection window for the NEXT one.

  DISCOVERY: ALTER RESOURCE MONITOR ... SET requires at least one
  property = value pair before TRIGGERS can follow — a bare
  "SET TRIGGERS ..." with no property first is a syntax error, even
  though it reads as logically equivalent. CREDIT_QUOTA is restated
  below (unchanged) purely to satisfy that requirement.
*/

ALTER RESOURCE MONITOR GOAL9_WORKBOOK_MONITOR SET
    CREDIT_QUOTA = 5
    TRIGGERS
        ON 25 PERCENT DO NOTIFY
        ON 50 PERCENT DO NOTIFY
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- Confirm the scope this containment actually applies to (9.8
-- discipline — verify assignment, don't assume it):
SHOW RESOURCE MONITORS LIKE 'GOAL9_WORKBOOK_MONITOR';

SELECT
    "name",
    "level",
    "credit_quota",
    "used_credits"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

/*
  Confirm level = WAREHOUSE and the used_credits figure reflects
  something plausible relative to Step 1's simulated activity — this
  is the moment that proves containment is actually attached to the
  warehouse under investigation, not sitting unattached and useless.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 5 — INCIDENT SUMMARY (a real practice, not just workbook flavor)
═══════════════════════════════════════════════════════════════════════════

  A short, factual write-up of what was found and what changed — every
  real cost incident should end with something like this, whether in a
  ticket, a runbook, or (as here) a comment block colocated with the
  investigation itself.

  <placeholder> — fill in with your own actual findings once you've
  run Steps 2-4 live; don't leave this as a template.

    INCIDENT: WORKBOOK_WH credit usage review, <date>
    FINDING:  Query tag 'suspect_etl_job_v2' responsible for
              <X> credits across <N> queries in the review window.
    ROOT CAUSE: repeated redundant full scans instead of a single pass
              (simulated for this exercise; a real root cause would
              name the actual inefficient pattern found).
    CONTAINMENT: GOAL9_WORKBOOK_MONITOR's NOTIFY thresholds tightened
              to 25/50/75 percent (previously 50/75) for earlier
              detection of similar patterns.
    FOLLOW-UP: none required for this exercise; in a real incident,
              this is where you'd note the ticket to actually FIX the
              inefficient query, not just detect it faster next time.
*/

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. Step 2 compares today against a 14-day trend. Rewrite it to
     compute a simple average of the trailing 7 days EXCLUDING today,
     and flag today as anomalous only if it exceeds that average by
     some multiple (e.g. 2x) — a slightly more rigorous anomaly
     definition than eyeballing a list of daily totals.

  2. Step 3's join requires waiting on QUERY_ATTRIBUTION_HISTORY's
     latency. Write an interim query using only QUERY_HISTORY (no join,
     no attribution) that would give you a reasonable EARLY signal about
     which tagged queries are worth investigating, using execution_time
     and bytes_scanned as stand-ins for cost until attribution data
     lands.

  3. Step 4 tightened NOTIFY thresholds but left SUSPEND at 90 percent
     unchanged. Argue both sides: when would tightening SUSPEND too be
     the right call, and when would that be an overreaction to a single
     incident?

  4. This capstone investigated ONE warehouse. Sketch (in words, not
     necessarily full SQL) how Steps 2-3 would need to change if the
     account had multiple warehouses pooled on one resource monitor, per
     9.8 — specifically, how would you figure out WHICH pooled warehouse
     was actually responsible for a shared-quota spike?
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: Why tighten an existing monitor instead of just accepting the
     current thresholds were "good enough" since they'd have caught
     this eventually at 90 percent anyway?
  A: Detection speed matters as much as eventual detection. A monitor
     that only notifies at 90% gives you far less runway to intervene
     before SUSPEND than one that also notifies at 25/50/75% — the
     incident's real lesson isn't "the monitor failed," it's "the
     monitor could have told us sooner." That's a legitimate outcome of
     an incident review even when nothing technically broke.

  Q: This whole capstone used a simulated, cheap incident. Does that
     undermine the exercise?
  A: No — the diagnostic SEQUENCE (confirm anomaly → attribute to a
     query → contain going forward) is identical regardless of dollar
     amount, and that sequence is what COF-C03 domain 2.0 and real
     production incident response both actually test. A $2 simulated
     incident and a $20,000 real one are investigated with the exact
     same queries; only the urgency changes, not the method.

  Q: Should GOAL9_WORKBOOK_MONITOR's tightened thresholds from Step 4
     stay in place permanently now?
  A: That's a real decision, not a rhetorical question — same category
     as 9.8's account-level monitor choice. Tighter NOTIFY thresholds
     cost nothing extra to leave in place (NOTIFY doesn't suspend
     anything), so there's little downside to keeping 25/50/75/90/100
     as this account's ongoing configuration rather than reverting it
     after this exercise.
*/
