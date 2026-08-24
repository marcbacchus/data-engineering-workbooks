/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9       : Monitor and Manage Costs
  Sub-task 9.8 : Resource Monitors — Assignment & Scope
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~20 min
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : 9.7 complete (GOAL9_WORKBOOK_MONITOR exists and
                           is assigned to WORKBOOK_WH); ACCOUNTADMIN
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  9.7 built a resource monitor and attached it to a single warehouse.
  This sub-task covers the two things that change once more than one
  warehouse — or the whole account — is in the picture: account-level
  assignment (ALTER ACCOUNT) versus warehouse-level assignment (ALTER
  WAREHOUSE, already used in 9.7), and what happens when several
  warehouses share ONE monitor's quota as a pool.

  Every object created here is a genuinely live, working configuration —
  but because account-level and pooled monitors can affect warehouses
  beyond just WORKBOOK_WH going forward, this file ends with an explicit
  cleanup decision rather than leaving new monitors silently active.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════

  Two assignment commands, already contrasted in 9.7's SETUP-adjacent
  material but worth stating side by side:

      ALTER WAREHOUSE <name> SET RESOURCE_MONITOR = <monitor_name>;
      ALTER ACCOUNT   SET RESOURCE_MONITOR = <monitor_name>;

  Scope rules:
      - Each warehouse can be assigned to only ONE resource monitor
        below the account level — no splitting one warehouse's quota
        across two monitors.
      - The SAME monitor CAN be assigned to multiple warehouses at once.
        When it is, their combined credit usage is POOLED against that
        one shared quota — Warehouse A and Warehouse B together count
        toward the same CREDIT_QUOTA, not separately.
      - Only ONE resource monitor can be the account-level monitor at a
        time. Assigning a second one via ALTER ACCOUNT doesn't error —
        it SILENTLY replaces the first, which reverts to having no
        account-level assignment (its "level" becomes NULL again in
        SHOW RESOURCE MONITORS, though it may still hold its
        warehouse-level assignment, if any, unaffected). This is the
        same "no error, silent replacement" shape as CREATE OR REPLACE
        landing on an already-referenced governance object from Goal 4
        — a class of gotcha this workbook has hit before.
      - An account-level monitor does NOT override warehouse-level
        monitors, and vice versa — BOTH are enforced independently at
        the same time. If either one reaches its own threshold, the
        warehouse gets suspended. A warehouse with a generous
        warehouse-level quota can still get suspended early by a
        stingier account-level monitor, and there's no precedence rule
        that lets one "win" over the other — whichever fires first
        fires.
      - An account-level resource monitor does not control credit usage
        by Snowflake-PROVIDED warehouses (the ones backing cloud
        services) — only user-created virtual warehouses.
      - NOTIFY_USERS must be NULL on a monitor before it can be set at
        the account level — non-administrator user notifications are a
        warehouse-monitor-only feature.

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  Oracle's Database Resource Manager has a loosely analogous "only one
  thing active at a time" constraint — a database instance can have only
  ONE resource plan active at once, governing how consumer groups share
  CPU. But DBRM plans can nest sub-plans into a hierarchy, letting a DBA
  express "Finance gets 60% of whatever's left after Batch," a
  genuinely hierarchical allocation. Snowflake's scope model is flatter
  by comparison: account-level and warehouse-level monitors don't nest
  or share quota with each other at all — they're two entirely
  independent trip-wires watching the same warehouse, not a parent plan
  allocating shares to child plans. Simpler to reason about, but it also
  means there's no way to express "this warehouse gets 20% of the
  account's remaining budget" directly — you'd size each monitor's own
  quota by hand to approximate that.
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE ROLE ACCOUNTADMIN;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Create a separate monitor for account-level assignment
═══════════════════════════════════════════════════════════════════════════

  A second, distinct monitor rather than reusing 9.7's
  GOAL9_WORKBOOK_MONITOR — this keeps the warehouse-level and
  account-level examples cleanly separable, and avoids any ambiguity
  about whether one monitor can simultaneously hold both scopes (not
  something worth guessing at without a documented answer).
*/

CREATE OR REPLACE RESOURCE MONITOR GOAL9_ACCOUNT_MONITOR
WITH
    CREDIT_QUOTA = 50
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
TRIGGERS
    ON 80 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Assign it at the account level, confirm both scopes coexist
═══════════════════════════════════════════════════════════════════════════*/

ALTER ACCOUNT SET RESOURCE_MONITOR = GOAL9_ACCOUNT_MONITOR;

SHOW RESOURCE MONITORS;

SELECT
    "name",
    "level",
    "credit_quota",
    "frequency"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

/*
  Expect two rows here now: GOAL9_ACCOUNT_MONITOR with level = ACCOUNT,
  and 9.7's GOAL9_WORKBOOK_MONITOR still showing level = WAREHOUSE —
  both independently watching WORKBOOK_WH at the same time, exactly per
  the CONCEPT section's "both enforced, whichever fires first" rule.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Confirm silent replacement at the account level
═══════════════════════════════════════════════════════════════════════════*/

CREATE OR REPLACE RESOURCE MONITOR GOAL9_ACCOUNT_MONITOR_V2
WITH
    CREDIT_QUOTA = 75
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
TRIGGERS
    ON 100 PERCENT DO SUSPEND;

ALTER ACCOUNT SET RESOURCE_MONITOR = GOAL9_ACCOUNT_MONITOR_V2;

SHOW RESOURCE MONITORS;

/*
  Expect: no error from that ALTER ACCOUNT statement. In the SHOW
  output, GOAL9_ACCOUNT_MONITOR_V2 now shows level = ACCOUNT, and
  GOAL9_ACCOUNT_MONITOR — which held that role a moment ago — reverts to
  level = NULL. Nothing warned you this was about to happen; that's the
  "silent replacement" gotcha from the CONCEPT section, confirmed live.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Pooled quota across multiple warehouses (zero-cost demo)
═══════════════════════════════════════════════════════════════════════════

  A throwaway warehouse created INITIALLY_SUSPENDED and never resumed —
  this incurs no compute credits at all, since a warehouse only bills
  while actually running. It exists purely to show two warehouses
  sharing one monitor's quota in SHOW WAREHOUSES output.
*/

CREATE WAREHOUSE IF NOT EXISTS GOAL9_POOL_DEMO_WH
WAREHOUSE_SIZE = 'XSMALL'
INITIALLY_SUSPENDED = TRUE
AUTO_SUSPEND = 60;

ALTER WAREHOUSE GOAL9_POOL_DEMO_WH SET RESOURCE_MONITOR = GOAL9_WORKBOOK_MONITOR;

SHOW WAREHOUSES;

/*
  Confirm both WORKBOOK_WH and GOAL9_POOL_DEMO_WH show resource_monitor
  = GOAL9_WORKBOOK_MONITOR in this output. If GOAL9_POOL_DEMO_WH were
  ever actually resumed and run, its credits would count against the
  SAME 5-credit daily quota WORKBOOK_WH is already sharing — not a
  separate 5-credit allowance of its own.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 5 — Cleanup: this file leaves nothing running unattended
═══════════════════════════════════════════════════════════════════════════

  GOAL9_POOL_DEMO_WH was purely a scope demonstration — drop it. The
  account-level monitor from Steps 1-3, however, is a real decision
  point: leaving GOAL9_ACCOUNT_MONITOR_V2 attached at the account level
  means EVERY warehouse created in this account going forward is now
  governed by its 75-credit monthly quota, whether that's intended
  long-term account policy or was just today's exercise.
*/

DROP WAREHOUSE IF EXISTS GOAL9_POOL_DEMO_WH;

-- <placeholder> — decide deliberately, don't leave this unresolved:
-- to detach the account-level monitor entirely and return to no
-- account-wide quota:
--   ALTER ACCOUNT UNSET RESOURCE_MONITOR;
-- to keep it as real, ongoing account policy, raise CREDIT_QUOTA to a
-- number that reflects actual expected account-wide usage rather than
-- today's arbitrary demo value of 75.

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. Re-run SHOW RESOURCE MONITORS after Step 5's cleanup decision.
     Confirm GOAL9_WORKBOOK_MONITOR (from 9.7) still shows level =
     WAREHOUSE, unaffected by anything that happened to the two
     account-level monitors in this file — different objects, scoped
     independently.

  2. If GOAL9_WORKBOOK_MONITOR's 5-credit daily quota and
     GOAL9_ACCOUNT_MONITOR_V2's 75-credit monthly quota were BOTH still
     active on WORKBOOK_WH, and WORKBOOK_WH burned through 5 credits in
     a single day, which one would suspend it — the daily one, the
     monthly one, or does it depend on which was created first? Justify
     your answer from the CONCEPT section's "whichever fires first"
     rule, not from assumption.

  3. Try assigning GOAL9_WORKBOOK_MONITOR (which still carries a
     non-null configuration from 9.7) directly via ALTER ACCOUNT SET
     RESOURCE_MONITOR. Does NOTIFY_USERS being unset on it (as
     established in 9.7) make this succeed, consistent with the "must
     be NULL for account-level" rule?

  4. Write the ALTER WAREHOUSE statement that would move WORKBOOK_WH
     from GOAL9_WORKBOOK_MONITOR onto NO resource monitor at all (fully
     unmonitored at the warehouse level). What's the SET syntax for
     removing an assignment rather than replacing it with a different
     monitor?
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: Step 3 replaced the account-level monitor with no warning or
     confirmation prompt at all — is there any safer way to do this in
     production, where silently losing an account-wide guardrail for
     even a moment could be risky?
  A: Not through SQL DDL directly — ALTER ACCOUNT SET RESOURCE_MONITOR
     genuinely is a straight replace, by design. The safer pattern in
     practice is procedural, not technical: always SHOW RESOURCE
     MONITORS first to see what's currently at the ACCOUNT level before
     reassigning it, and treat "what monitor currently holds the
     account level" as something to check immediately before any change
     rather than assume.

  Q: Could I have skipped Step 1 and just reused GOAL9_WORKBOOK_MONITOR
     for the account-level assignment too?
  A: Possibly — nothing in Snowflake's documentation says a monitor
     can't hold both an account-level assignment AND a warehouse-level
     assignment simultaneously. But this file deliberately didn't test
     that combination, because an untested guess about dual-scope
     behavior has no place in a "test everything live before writing it
     down" workbook. If you're curious, that's a good live experiment
     to run and document the actual result of, rather than something
     to assume from this file.

  Q: If two warehouses pooled on the same monitor (Step 4's scenario, if
     GOAL9_POOL_DEMO_WH had actually run) hit the shared quota, does
     SUSPEND affect both warehouses or just whichever one pushed it over
     the edge?
  A: Both — a SUSPEND or SUSPEND_IMMEDIATE trigger suspends every
     warehouse assigned to that monitor, not just the one whose query
     happened to be running when the threshold was crossed. Pooling
     quota means pooling the consequence too.

  Q: This account has run everything on a single warehouse throughout
     the whole series — does any of Step 4's pooling material actually
     matter here, or is it purely theoretical for this specific account?
  A: Purely theoretical for THIS account's current shape, same honest
     answer as 9.4's empty serverless result — but it's exactly the
     kind of multi-warehouse governance question COF-C03 domain 2.0
     tests directly, and the mechanics demonstrated in Step 4 (shared
     quota, SHOW WAREHOUSES reflecting the same monitor name on two
     warehouses) transfer directly to any account that does run more
     than one warehouse.
*/
