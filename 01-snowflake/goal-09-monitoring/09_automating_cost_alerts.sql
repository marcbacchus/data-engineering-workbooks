/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9       : Monitor and Manage Costs
  Sub-task 9.9 : Automating Cost Alerts
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~25 min
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : 9.8 complete; ACCOUNTADMIN; Goal 6's
                           NOTIFICATION INTEGRATION discovery (verified
                           recipient + ACCOUNTADMIN-created integration)
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  9.7's resource monitor NOTIFY trigger sends a built-in, fixed-format
  notification — useful, but blunt. This sub-task closes Goal 9 by
  building something richer: a Snowflake ALERT that runs a real SQL
  condition against 9.4's METERING_HISTORY on a schedule, and only fires
  a custom email when that condition is actually true. This is the same
  Task/Alert automation machinery from Goal 6, pointed at a cost
  question instead of a data-pipeline question.

  ⚠️ Unlike everything else in Goal 9, an ACTIVE alert has a real,
  ongoing background credit cost — every scheduled evaluation runs a
  query against a warehouse. This file ends with an explicit suspend
  step, following the same "flag it, don't leave it running unattended"
  discipline as every other real recurring cost in this workbook series.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════

  An ALERT is a schema-level object with three parts:

      CREATE [OR REPLACE] ALERT <name>
          WAREHOUSE = <warehouse_name>
          SCHEDULE  = '<num> MINUTE' | 'USING CRON <expr> <timezone>'
      IF( EXISTS( <condition_query> ))
      THEN <action_statement>;

  Key mechanics, several of them direct carry-forwards from Goal 6's
  Task automation work:

      - Alerts run their condition AND action on a real WAREHOUSE — this
        is compute you pay for, unlike a resource monitor's evaluation,
        which needs no warehouse at all.
      - A newly created alert is SUSPENDED by default — exactly like a
        newly created Task, it does nothing until you explicitly
        ALTER ALERT <name> RESUME.
      - Neither the condition nor the action SQL is validated at
        CREATE/ALTER time — only at actual execution. The same "verify
        uncertain syntax before trusting it" discipline from every prior
        goal applies here even more than usual; check ALERT_HISTORY
        after the first scheduled run rather than assuming success.
      - Inside the condition ONLY, SNOWFLAKE.ALERT.LAST_SUCCESSFUL_
        SCHEDULED_TIME() and SNOWFLAKE.ALERT.SCHEDULED_TIME() let you
        scope a query to just the window since the last successful run
        — avoiding re-alerting on the same already-reported usage every
        time the schedule fires.
      - EXECUTE ALERT is a privilege that, per Goal 6's discovery about
        EXECUTE TASK, is NOT automatically available even to the
        creating/owning role — expect to need an explicit ACCOUNTADMIN
        grant, the same pattern as Task execution.
      - SYSTEM$SEND_EMAIL requires the same two prerequisites Goal 6
        already discovered for Task-driven notifications: a verified
        recipient and an ACCOUNTADMIN-created NOTIFICATION INTEGRATION.
        Reuse whichever integration Goal 6 already built rather than
        creating a duplicate — check SHOW NOTIFICATION INTEGRATIONS
        first.

  The schedule choice matters here specifically because of Goal 9's own
  latency discoveries: METERING_HISTORY has up to 3-hour latency (6 for
  cloud services, 12 for Snowpipe Streaming, all from 9.4). A 1-minute
  alert schedule checking that view would mostly just re-check data that
  hasn't changed yet — wasted compute for no informational gain. A daily
  CRON schedule is the sensible match for a view with hours of latency.

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  Oracle's closest equivalent is hand-assembling DBMS_SCHEDULER (a
  scheduled job) with a PL/SQL block that queries AWR and calls
  UTL_MAIL or UTL_SMTP to send the result — genuinely the same shape
  (scheduled condition check → custom action), but built from three or
  four separate pieces a DBA wires together themselves, each with its
  own setup and failure modes. Snowflake's ALERT fuses condition,
  schedule, and action into one first-class object, and SYSTEM$SEND_EMAIL
  is a single built-in call once the notification integration exists —
  less assembly required for the same underlying idea.
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE ROLE ACCOUNTADMIN;

-- Carry-forward from Goal 6: EXECUTE ALERT is not automatic even for
-- the owning role. Grant it explicitly.
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE ACCOUNTADMIN;

-- <placeholder> — check for an existing notification integration from
-- Goal 6 before creating a new one:
SHOW NOTIFICATION INTEGRATIONS;

-- If Goal 6's integration already exists, reuse its name below in
-- Step 2 instead of creating a duplicate. Only create a new one if
-- none exists:
--
--   CREATE NOTIFICATION INTEGRATION goal9_email_integration
--       TYPE = EMAIL
--       ENABLED = TRUE;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Confirm the condition query works on its own first
═══════════════════════════════════════════════════════════════════════════

  Since alert condition/action SQL isn't validated until it actually
  runs, test the exact condition logic as a standalone SELECT before
  it's ever embedded inside CREATE ALERT — catching a typo now is far
  easier than debugging it via ALERT_HISTORY after a missed scheduled run.
*/

SELECT SUM(credits_used) AS total_credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE service_type = 'WAREHOUSE_METERING'
  AND name = 'WORKBOOK_WH'
  AND start_time >= DATEADD('hours', -24, CURRENT_TIMESTAMP());

/*
  Note whatever value this returns right now — that's your baseline for
  judging whether the threshold picked in Step 2 is realistic for this
  account's actual usage pattern, not an arbitrary guess.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Create the alert
═══════════════════════════════════════════════════════════════════════════

  <placeholder> — replace 'goal9_email_integration' with whichever
  integration name Goal 6 actually used if one already exists, and
  replace the email address with a real, verified recipient.
*/

CREATE OR REPLACE ALERT GOAL9_DAILY_COST_ALERT
    WAREHOUSE = WORKBOOK_WH
    SCHEDULE = 'USING CRON 0 7 * * * UTC'
IF(
    EXISTS(
        SELECT 1
        FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
        WHERE service_type = 'WAREHOUSE_METERING'
          AND name = 'WORKBOOK_WH'
          AND start_time >= SNOWFLAKE.ALERT.LAST_SUCCESSFUL_SCHEDULED_TIME()
          AND start_time < SNOWFLAKE.ALERT.SCHEDULED_TIME()
        GROUP BY name
        HAVING SUM(credits_used) > 3
    )
)
THEN
    CALL SYSTEM$SEND_EMAIL(
        'goal9_email_integration',
        '<placeholder_verified_email>',
        'Goal 9 Cost Alert: WORKBOOK_WH usage',
        'WORKBOOK_WH used more than 3 credits since the last check. Review WAREHOUSE_METERING_HISTORY for details.'
    );

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Resume it (alerts start SUSPENDED, same as Tasks in Goal 6)
═══════════════════════════════════════════════════════════════════════════*/

ALTER ALERT GOAL9_DAILY_COST_ALERT RESUME;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Verify state and check execution history
═══════════════════════════════════════════════════════════════════════════*/

SHOW ALERTS LIKE 'GOAL9_DAILY_COST_ALERT';

-- Won't show anything until at least one scheduled evaluation has run
-- — that's expected immediately after Step 3, not an error:
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.ALERT_HISTORY(
        SCHEDULED_TIME_RANGE_START => DATEADD('hours', -1, CURRENT_TIMESTAMP()),
        ALERT_NAME => 'GOAL9_DAILY_COST_ALERT'
    )
);

/*═══════════════════════════════════════════════════════════════════════════
  STEP 5 — Suspend it: this is Goal 9's real ongoing-cost decision point
═══════════════════════════════════════════════════════════════════════════

  ⚠️ A daily CRON schedule against a single X-Small warehouse's
  METERING_HISTORY is cheap per run, but it IS a genuine, indefinitely
  recurring cost if left active — the same category of decision as
  9.8's account-level resource monitor. This workbook series doesn't run
  as a continuously operated production account, so leaving automation
  running unattended between sessions doesn't match how this account
  actually gets used.
*/

ALTER ALERT GOAL9_DAILY_COST_ALERT SUSPEND;

-- <placeholder> — if you want this alert to actually run on an ongoing
-- basis going forward (e.g. you're keeping this Snowflake account
-- active long-term beyond the workbook series), re-run:
--   ALTER ALERT GOAL9_DAILY_COST_ALERT RESUME;
-- and confirm the notification integration/recipient are both real,
-- verified, and something you intend to keep receiving mail from.

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. Rewrite Step 2's SCHEDULE from CRON to the simpler '<num> MINUTE'
     form, set to something unreasonably frequent like '5 MINUTE'.
     Given METERING_HISTORY's up-to-3-hour latency (from 9.4), explain
     specifically why this would waste compute without adding any real
     detection speed.

  2. The condition in Step 2 uses SNOWFLAKE.ALERT.LAST_SUCCESSFUL_
     SCHEDULED_TIME() and SNOWFLAKE.ALERT.SCHEDULED_TIME() to bound the
     window. What would go wrong — specifically, what would happen on
     the SECOND and every subsequent firing — if you used a fixed
     DATEADD('hours', -24, CURRENT_TIMESTAMP()) window instead?

  3. Query INFORMATION_SCHEMA.ALERT_HISTORY (or ACCOUNT_USAGE.ALERT_
     HISTORY for a longer window) to distinguish an alert execution
     where the condition evaluated to FALSE from one that genuinely
     failed with an error. What column tells you which happened?

  4. This alert checks only WORKBOOK_WH by name. Rewrite the condition
     to check EVERY warehouse in the account for the same 3-credit
     threshold, rather than hardcoding one warehouse name — useful if
     this account ever runs more than one warehouse, per 9.8's pooling
     discussion.
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: Why not just rely entirely on 9.7's resource monitor NOTIFY trigger
     instead of building a separate alert?
  A: They solve different problems. A resource monitor's NOTIFY is
     built-in, requires zero extra compute to evaluate, and fires based
     purely on percentage-of-quota — but its message is fixed-format and
     it can't express arbitrary logic (e.g. "alert me only if THIS
     specific warehouse spiked, even though the account overall is
     fine"). An alert costs a small amount of compute per scheduled run
     but can encode any SQL condition and any custom message. Use
     resource monitors for hard guardrails with automatic enforcement
     (NOTIFY/SUSPEND/SUSPEND_IMMEDIATE); use alerts for flexible,
     informational monitoring that doesn't need to actually stop a
     warehouse.

  Q: I got a permissions error on CREATE NOTIFICATION INTEGRATION even
     as ACCOUNTADMIN — what's missing?
  A: Notification integrations sometimes require the account to have
     email notifications enabled at the account level first, separate
     from the integration object itself. If Goal 6 already solved this
     when it first built Task-driven email notifications, reusing that
     existing integration (per the SHOW NOTIFICATION INTEGRATIONS check
     in Setup) sidesteps the issue entirely rather than re-solving it.

  Q: The alert fired but I never got an email — what should I check
     first?
  A: In order: (1) ALERT_HISTORY to confirm the condition actually
     evaluated to TRUE and the action ran without error, (2) whether the
     recipient email is genuinely verified in Snowsight, (3) whether the
     notification integration name in the CALL SYSTEM$SEND_EMAIL
     statement exactly matches a real, ENABLED integration via SHOW
     NOTIFICATION INTEGRATIONS. A silent action failure shows up in
     ALERT_HISTORY's error columns, not as a loud error anywhere else.

  Q: Does suspending the alert in Step 5 lose the credit-usage history
     it already checked?
  A: No — SUSPEND only stops future scheduled evaluations. Nothing
     about the alert object's definition, its past ALERT_HISTORY
     records, or the underlying METERING_HISTORY data it was querying
     is affected. Resuming it later picks up on the next scheduled
     CRON time going forward, using LAST_SUCCESSFUL_SCHEDULED_TIME()
     from whenever it last actually ran.
*/
