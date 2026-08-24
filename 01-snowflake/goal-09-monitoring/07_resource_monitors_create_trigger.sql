/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9       : Monitor and Manage Costs
  Sub-task 9.7 : Resource Monitors — Create & Trigger
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~20 min
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : 9.6 complete; ACCOUNTADMIN (resource monitor
                           creation is ACCOUNTADMIN-only by default)
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  9.2-9.6 were entirely about OBSERVING cost after the fact. Resource
  monitors are the one Goal 9 topic that actually ACTS on cost — a
  first-class Snowflake object that tracks credit usage against a quota
  and can notify, suspend, or hard-kill a warehouse when a threshold is
  crossed.

  A deliberate scoping decision for this file: it builds and configures
  a real resource monitor, verifies every piece of its configuration
  live, and assigns it to WORKBOOK_WH — but it does NOT attempt to force
  a live SUSPEND or SUSPEND_IMMEDIATE by actually burning through a
  quota. Here's why, worked through explicitly rather than glossed over:
  a CREDIT_QUOTA rounds any decimal down to a whole credit, so the
  smallest meaningful non-zero quota is 1 credit — and on WORKBOOK_WH's
  X-Small size (1 credit/hour, from 9.1), reaching even that 1-credit
  floor means roughly an hour of continuously running compute. That's a
  real, non-trivial credit cost and a long wait for a "let's watch it
  trigger" exercise. So this file treats the trigger MECHANICS as
  something to configure and understand precisely, with an OPTIONAL,
  clearly cost-flagged stretch step at the end for anyone who wants to
  actually watch a live suspend happen.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════

  A resource monitor has four core properties:

      CREDIT_QUOTA     number of credits allocated per FREQUENCY interval.
                        Includes BOTH warehouse compute AND the cloud
                        services credits used to support those
                        warehouses — it is not warehouse-compute-only.
                        Decimals are silently rounded down to the nearest
                        whole credit (verify this yourself if in doubt —
                        don't just trust a blog claiming otherwise).
      FREQUENCY         MONTHLY | DAILY | WEEKLY | YEARLY | NEVER — how
                        often used credits reset to 0. NEVER means
                        credits accumulate until the quota is reached and
                        never auto-reset.
      START_TIMESTAMP   when monitoring begins; IMMEDIATELY uses the
                        current timestamp. Resets always occur at
                        00:00 UTC regardless of what local time you
                        specify for the start.
      TRIGGERS          one or more (threshold PERCENT, ACTION) pairs.

  Three trigger actions, each strictly more aggressive than the last:

      NOTIFY              sends a notification only — no impact on the
                           warehouse at all.
      SUSPEND              lets currently running queries finish, then
                           blocks new queries/warehouse resume until the
                           quota is raised or the interval resets.
      SUSPEND_IMMEDIATE    cancels whatever is running RIGHT NOW and
                           blocks the warehouse the same way SUSPEND does
                           afterward.

  A monitor supports up to five NOTIFY triggers, one SUSPEND trigger, and
  one SUSPEND_IMMEDIATE trigger. Thresholds over 100 PERCENT are valid —
  useful for a "hard stop well past the expected quota" safety net.
  TRIGGERS is NOT additive on ALTER — replacing it wipes every previously
  defined trigger, so any ALTER RESOURCE MONITOR ... TRIGGERS statement
  must restate every trigger you still want, not just the new one.

  A resource monitor with no action at all — created without any
  TRIGGERS clause — silently does nothing when its quota is hit. That's
  a real, working configuration in Snowflake's eyes, not an error; it
  just means nobody gets notified and nothing gets suspended.

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  Oracle's closest analog is Database Resource Manager (DBRM) —
  consumer-group-based CPU and parallelism throttling that keeps one
  workload from starving another. The philosophy is fundamentally
  different, though: DBRM THROTTLES, it doesn't kill — a low-priority
  consumer group gets squeezed toward zero CPU share under contention,
  but the session isn't forcibly terminated just for existing. Snowflake
  resource monitors have no throttling tier at all — a warehouse runs at
  full speed right up until a threshold is crossed, and then SUSPEND or
  SUSPEND_IMMEDIATE is a hard, binary stop, not a gradual squeeze. That
  reflects the different thing each tool is protecting: DBRM protects
  fair CPU access on shared, fixed hardware; a Snowflake resource
  monitor protects a CREDIT BUDGET, where "half-speed forever" doesn't
  actually solve a runaway-spend problem the way a hard stop does.
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE ROLE ACCOUNTADMIN;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Create a resource monitor with a graduated response
═══════════════════════════════════════════════════════════════════════════

  A daily quota, small enough to be realistic for a single X-Small
  training warehouse, with four thresholds walking from a soft warning
  up to a hard kill. NOTIFY_USERS is deliberately omitted here — it
  requires real users with verified email addresses on this account, and
  the statement fails outright if any listed user lacks one. Add it as
  an optional follow-up once you've confirmed which users on this
  account have verified emails.
*/

CREATE OR REPLACE RESOURCE MONITOR GOAL9_WORKBOOK_MONITOR
WITH
    CREDIT_QUOTA = 5
    FREQUENCY = DAILY
    START_TIMESTAMP = IMMEDIATELY
TRIGGERS
    ON 50 PERCENT DO NOTIFY
    ON 75 PERCENT DO NOTIFY
    ON 90 PERCENT DO SUSPEND
    ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- <placeholder> — to add email notifications once you've confirmed
-- verified users:
--   ALTER RESOURCE MONITOR GOAL9_WORKBOOK_MONITOR SET
--       NOTIFY_USERS = ('<verified_user_name>');

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Verify the configuration
═══════════════════════════════════════════════════════════════════════════*/

SHOW RESOURCE MONITORS LIKE 'GOAL9_WORKBOOK_MONITOR';

/*
  DISCOVERY: there is no DESCRIBE RESOURCE MONITOR command — resource
  monitors are one of the object types Snowflake only exposes through
  SHOW, not DESCRIBE. Attempting it raises "Unsupported feature
  'TOK_RESOURCE_MONITOR'." SHOW RESOURCE MONITORS is the only live
  inspection command for this object type.

  SHOW output isn't always easy to read at a glance in a wide result
  set — RESULT_SCAN lets you re-query the immediately preceding SHOW
  command's output as a normal table, which is useful for picking out
  just the columns you care about. LAST_QUERY_ID() with no argument
  (equivalent to LAST_QUERY_ID(-1)) points at the statement that ran
  immediately before this one — the SHOW RESOURCE MONITORS above — so
  run these two statements back-to-back, with nothing else in between:
*/

SELECT
    "name",
    "credit_quota",
    "frequency",
    "level",
    "used_credits",
    "remaining_credits"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

/*
  Confirm in the SHOW output: credit_quota = 5, frequency = DAILY, and
  "level" is still NULL at this point — Step 3 is what changes that to
  WAREHOUSE by assigning it. SHOW RESOURCE MONITORS doesn't break the
  individual TRIGGERS out into separate rows/columns the way DESCRIBE
  does for other object types; the trigger definitions themselves are
  really only visible in full back in the CREATE statement you ran, or
  via SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS if you need to confirm
  them later with ACCOUNT_USAGE's usual latency.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Assign it to WORKBOOK_WH
═══════════════════════════════════════════════════════════════════════════

  A resource monitor does nothing on its own until it's attached to a
  warehouse (or, per 9.8, set at the account level). This is the same
  create-then-attach pattern as masking/row-access policies from Goal 4
  — the object exists independently, but has zero effect until assigned.
*/

ALTER WAREHOUSE WORKBOOK_WH SET RESOURCE_MONITOR = GOAL9_WORKBOOK_MONITOR;

-- Confirm the assignment landed
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

/*
  Check the resource_monitor column in the output — it should now show
  GOAL9_WORKBOOK_MONITOR instead of blank.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — OPTIONAL, cost-flagged: watch a real trigger fire
═══════════════════════════════════════════════════════════════════════════

  ⚠️ Skip this step unless you're deliberately willing to spend roughly
  1 credit and roughly an hour of wall-clock time watching a warehouse
  run. It is NOT required to complete this sub-task — Steps 1-3 already
  build and verify a fully working, correctly configured resource
  monitor. This step exists only if you want direct, observed proof that
  a SUSPEND trigger actually fires, rather than trusting the documented
  behavior.

  To try it: temporarily lower the quota so a short, deliberate burst of
  activity can realistically cross it —

    ALTER RESOURCE MONITOR GOAL9_WORKBOOK_MONITOR SET CREDIT_QUOTA = 1;

  Then run a query that keeps WORKBOOK_WH busy for several minutes (a
  large enough scan or a deliberate WAIT-style loop), and periodically
  check:

    SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

  Watch the STATE column — once billed credits for the day cross the
  1-credit SUSPEND_IMMEDIATE-adjacent thresholds you set, the warehouse
  should move to SUSPENDED and refuse new queries until you raise the
  quota back with ALTER RESOURCE MONITOR ... SET CREDIT_QUOTA = 5 (per
  9.7's WHAT IF on recovering from a suspended state).

  <placeholder> — if you try this, report back the actual STATE
  transition and timing you observe; that's real data worth capturing
  in this file's discoveries, not something to guess at in advance.
*/

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. Rewrite Step 1's CREATE statement using FREQUENCY = NEVER instead
     of DAILY. What operational risk does this introduce that DAILY
     doesn't have, given that credits would never auto-reset?

  2. A resource monitor's used-credit total includes cloud services
     credits, not just warehouse compute. Given 9.1's WHAT IF — Cloud
     Services isn't billed at all until it exceeds 10% of daily compute
     credits — does that 10% rebate reduce what COUNTS toward a resource
     monitor's quota, or only what gets billed? (Hint: re-read the
     CONCEPT section's note on cloud services credits carefully.)

  3. Try creating a second resource monitor and assigning it to
     WORKBOOK_WH without first detaching GOAL9_WORKBOOK_MONITOR. What
     happens, and why does it make sense given "each warehouse can only
     be assigned to one resource monitor below the account level"?

  4. Using ALTER RESOURCE MONITOR, change GOAL9_WORKBOOK_MONITOR's
     TRIGGERS to just ON 100 PERCENT DO SUSPEND — a single trigger.
     Since Step 2 already established there's no DESCRIBE for this
     object type, how would you confirm the 50/75/90 percent triggers
     from Step 1 are now GONE rather than merely supplemented? (Hint:
     SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS is the one place trigger
     definitions are queryable as data — check whether its latency
     works against a "confirm this right now" use case.) This is the
     "TRIGGERS is not additive" behavior from the CONCEPT section,
     worth confirming rather than just trusting the documentation.
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: WORKBOOK_WH got suspended by this monitor (via Step 4, or in real
     use) — how do I get it running again?
  A: Either wait for the next FREQUENCY reset, or raise the quota /
     loosen the trigger immediately:

       ALTER RESOURCE MONITOR GOAL9_WORKBOOK_MONITOR
       SET CREDIT_QUOTA = 5
       TRIGGERS
           ON 50 PERCENT DO NOTIFY
           ON 75 PERCENT DO NOTIFY
           ON 90 PERCENT DO SUSPEND
           ON 100 PERCENT DO SUSPEND_IMMEDIATE;

     Remember TRIGGERS isn't additive — that ALTER statement must
     restate every trigger you want to keep, exactly as covered in the
     CONCEPT section.

  Q: I created GOAL9_WORKBOOK_MONITOR without USE ROLE ACCOUNTADMIN and
     got a permissions error — is there any other role that can do this?
  A: By default, no — resource monitor creation is ACCOUNTADMIN-only.
     Snowflake does support granting a MODIFY-style privilege on
     resource monitors to a custom role, but that's account-governance
     setup out of scope for this sub-task; for this workbook series,
     just switch to ACCOUNTADMIN as Setup instructs.

  Q: Does SUSPEND vs SUSPEND_IMMEDIATE matter much for a single-user
     training warehouse like WORKBOOK_WH?
  A: Less than it would in production, but the distinction is still
     real and exam-relevant: SUSPEND is the "let queries finish, then
     stop accepting new ones" version, SUSPEND_IMMEDIATE is "kill
     whatever's running right now." On a shared production warehouse
     serving many concurrent users, that difference is the difference
     between a graceful cutoff and cancelling someone else's in-flight
     work — worth internalizing even if this account never has that
     multi-user contention to observe directly.

  Q: If I never explicitly set NOTIFY_USERS, does NOTIFY still do
     anything?
  A: Yes, partially — NOTIFY (and the notification component of
     SUSPEND/SUSPEND_IMMEDIATE) always alerts account administrators who
     have notifications enabled for themselves, independent of
     NOTIFY_USERS. NOTIFY_USERS adds specific additional users beyond
     that admin notification, and is the piece that fails outright if
     any named user lacks a verified email — which is exactly why it was
     left out of Step 1.
*/
