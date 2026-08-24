/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author    : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9    : Monitor and Manage Costs
  Exam Prep : 15 questions — COF-C03 Domain 2.0 (Account Management and
              Data Governance, 20%)
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Format   : Multiple choice / multiple select, matching COF-C03's actual
             question types. One correct answer unless marked
             "(Select TWO)". Explanation follows each answer — read it
             even if you got the question right; the reasoning is the
             point, not just the letter.
  Coverage : Every question maps to material actually built and tested
             live in 9.1-9.9 and the capstone — nothing here is untested
             theory bolted on for exam-count padding.
  Domain   : All 15 questions are Domain 2.0 (Account Management and Data
             Governance) — unlike Goal 8, Goal 9 doesn't span multiple
             domains, so there's no per-question domain split table here.
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  Q1 — Credit billing mechanics (9.1)
═══════════════════════════════════════════════════════════════════════════

  A warehouse has been suspended for 2 hours. A user runs a query that
  takes 8 seconds to complete. How many seconds of compute are billed?

    A) 8 seconds
    B) 10 seconds
    C) 60 seconds
    D) 0 seconds, because 8 seconds rounds down to nothing

  ANSWER: C

  EXPLANATION: Every warehouse start (including resuming from suspend)
  incurs a 60-second minimum charge, regardless of how short the actual
  query is. Only after that first 60 seconds does billing switch to
  per-second. An 8-second query on a freshly-resumed warehouse still
  bills the full 60-second minimum.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q2 — Warehouse sizing (9.1)
═══════════════════════════════════════════════════════════════════════════

  A Large warehouse consumes 8 credits/hour. How many credits/hour does
  a 2X-Large warehouse consume?

    A) 16
    B) 24
    C) 32
    D) 64

  ANSWER: C

  EXPLANATION: Each size step doubles both compute resources and
  credit rate. Large (8) → X-Large (16) → 2X-Large (32). The scale is
  geometric, not linear — a common source of underestimated cost when
  someone bumps a warehouse up "just one size."
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q3 — Warehouse vs. serverless credits (9.1, 9.4)
═══════════════════════════════════════════════════════════════════════════

  Which of the following is billed as SERVERLESS compute rather than
  warehouse compute? (Select TWO)

    A) A query run against a named virtual warehouse
    B) Automatic Clustering reclustering a table
    C) A task with WAREHOUSE = 'MY_WH' specified in its DDL
    D) Snowpipe loading files from a stage

  ANSWER: B, D

  EXPLANATION: Automatic Clustering and Snowpipe both run on
  Snowflake-managed compute with no warehouse attached — their credits
  show up under their own SERVICE_TYPE in METERING_HISTORY (AUTO_
  CLUSTERING and PIPE respectively), not under any WAREHOUSE_METERING
  row. A is warehouse compute by definition. C is a task explicitly
  pinned to a named warehouse, so it bills as WAREHOUSE_METERING too —
  a task only becomes serverless if it omits WAREHOUSE in favor of
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q4 — INFORMATION_SCHEMA vs. ACCOUNT_USAGE metering (9.2, 9.3)
═══════════════════════════════════════════════════════════════════════════

  Which statement correctly distinguishes INFORMATION_SCHEMA.WAREHOUSE_
  METERING_HISTORY from ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY?

    A) The Information Schema version has longer retention and is
       preferred by Snowflake's own documentation
    B) The Account Usage version has longer retention (1 year vs.
       6 months) but higher latency, and is documented as the
       preferred source
    C) Both have identical retention and latency; the only difference
       is syntax (function vs. view)
    D) The Information Schema version requires ACCOUNTADMIN; the
       Account Usage version does not

  ANSWER: B

  EXPLANATION: ACCOUNT_USAGE's version retains a full year vs. the
  function's 6-month cap, and Snowflake's own docs mark the
  Information Schema function as "generally deprecated" in favor of
  it — but that longer retention comes with real ACCOUNT_USAGE latency
  (up to 3 hours), where the Information Schema function reflects
  activity much closer to real time. D is backwards — the Information
  Schema function requires MONITOR USAGE (or ACCOUNTADMIN), and
  ACCOUNT_USAGE requires ACCOUNTADMIN or IMPORTED PRIVILEGES — neither
  is privilege-free, but ACCOUNT_USAGE's requirement isn't lighter.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q5 — METERING_HISTORY SERVICE_TYPE (9.4)
═══════════════════════════════════════════════════════════════════════════

  In SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY, what does the NAME
  column represent when SERVICE_TYPE = 'WAREHOUSE_METERING'?

    A) The name of the query that ran
    B) The name of the warehouse
    C) The name of the database the warehouse most recently queried
    D) NAME is always NULL for WAREHOUSE_METERING rows

  ANSWER: B

  EXPLANATION: NAME's meaning genuinely varies by SERVICE_TYPE — for
  WAREHOUSE_METERING it's the warehouse name, but for other service
  types (like SNOWPIPE_STREAMING) it can be a target table name or a
  composite client string instead. There's no single universal meaning
  for the column; you have to check the documented semantics for
  whichever SERVICE_TYPE you're filtering on.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q6 — Storage view billing accuracy (9.5)
═══════════════════════════════════════════════════════════════════════════

  Which ACCOUNT_USAGE storage view is explicitly documented as the one
  used to calculate actual storage billing at the table level?

    A) STORAGE_USAGE
    B) DATABASE_STORAGE_USAGE_HISTORY
    C) TABLE_STORAGE_METRICS
    D) All three reconcile identically with the invoice

  ANSWER: C

  EXPLANATION: TABLE_STORAGE_METRICS is documented as the view used to
  calculate storage billing per table. STORAGE_USAGE and DATABASE_
  STORAGE_USAGE_HISTORY are both explicitly documented as NOT designed
  to reconcile exactly with a bill — they're directional/relative
  trending views, not billing-accurate ones. D is directly contradicted
  by Snowflake's own usage notes on two of the three views.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q7 — QUERY_TAG precedence (9.6)
═══════════════════════════════════════════════════════════════════════════

  A user has an ACCOUNT-level QUERY_TAG of 'default_tag' and a
  USER-level QUERY_TAG of 'user_tag'. In their session, they run
  ALTER SESSION SET QUERY_TAG = 'session_tag' and then execute a
  query. What QUERY_TAG value appears against that query in
  QUERY_HISTORY?

    A) default_tag
    B) user_tag
    C) session_tag
    D) All three, concatenated

  ANSWER: C

  EXPLANATION: Precedence is SESSION beats USER beats ACCOUNT. A
  session-level QUERY_TAG always overrides both user- and
  account-level tags for queries run in that session.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q8 — Per-query cost attribution (9.6)
═══════════════════════════════════════════════════════════════════════════

  Which view provides an actual CREDITS_ATTRIBUTED_COMPUTE figure per
  individual query, excluding warehouse idle time?

    A) QUERY_HISTORY
    B) QUERY_ATTRIBUTION_HISTORY
    C) WAREHOUSE_METERING_HISTORY
    D) METERING_HISTORY

  ANSWER: B

  EXPLANATION: QUERY_HISTORY has performance metrics (execution time,
  bytes scanned) but no clean per-query compute credit figure.
  QUERY_ATTRIBUTION_HISTORY specifically fills that gap with a
  weighted-average attribution per query, explicitly excluding idle
  time — which is also why it's the answer, not C or D, both of which
  report at the warehouse or account level, not per query.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q9 — Resource monitor CREDIT_QUOTA behavior (9.7)
═══════════════════════════════════════════════════════════════════════════

  A resource monitor is created with CREDIT_QUOTA = 4.75. What actually
  gets stored as the quota?

    A) 4.75, fractional quotas are fully supported
    B) 5, rounded up to the nearest whole credit
    C) 4, rounded down to the nearest whole credit
    D) The statement fails with a syntax error

  ANSWER: C

  EXPLANATION: CREDIT_QUOTA silently rounds any decimal DOWN to the
  nearest whole credit — confirmed behavior, not a syntax error and
  not rounded up. This matters practically: there's no way to set a
  sub-1-credit quota, which caps how finely you can force a monitor to
  trigger quickly for testing purposes.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q10 — Resource monitor trigger actions (9.7)
═══════════════════════════════════════════════════════════════════════════

  What is the key operational difference between SUSPEND and
  SUSPEND_IMMEDIATE as resource monitor trigger actions?

    A) SUSPEND cancels running queries immediately; SUSPEND_IMMEDIATE
       waits for them to finish first
    B) SUSPEND waits for running queries to finish before blocking new
       ones; SUSPEND_IMMEDIATE cancels whatever is running right now
    C) There is no functional difference, only a naming convention
    D) SUSPEND only applies to account-level monitors;
       SUSPEND_IMMEDIATE only applies to warehouse-level monitors

  ANSWER: B

  EXPLANATION: SUSPEND is the graceful version — let in-flight queries
  complete, then block new ones. SUSPEND_IMMEDIATE is the hard kill —
  cancel whatever's running right now. Both then block the warehouse
  from starting new work the same way afterward. A has it backwards; C
  and D misstate the actual distinction, which is about running-query
  handling, not scope.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q11 — TRIGGERS replacement behavior on ALTER (9.7, capstone)
═══════════════════════════════════════════════════════════════════════════

  A resource monitor currently has triggers at 50%, 75%, and 100%. You
  run ALTER RESOURCE MONITOR <name> SET CREDIT_QUOTA = 10 TRIGGERS ON
  90 PERCENT DO SUSPEND. What triggers does the monitor have after this
  statement runs?

    A) 50%, 75%, 90%, 100% — the new trigger is added to the existing
       set
    B) Only 90% — TRIGGERS is not additive; it replaces the entire
       existing trigger set
    C) The statement fails because you can't reduce the number of
       triggers
    D) 90% and 100% only — SUSPEND actions are preserved, NOTIFY
       actions are dropped

  ANSWER: B

  EXPLANATION: TRIGGERS on ALTER RESOURCE MONITOR is explicitly NOT
  additive — it wipes every existing trigger and replaces the whole
  set with whatever's specified in that statement. To ADD a trigger
  while keeping existing ones, you must restate all of them together
  in one ALTER statement. This is a documented, exam-relevant gotcha,
  not an edge case.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q12 — Resource monitor scope and pooling (9.8)
═══════════════════════════════════════════════════════════════════════════

  Two warehouses, A and B, are both assigned to the same resource
  monitor with a 100-credit quota. Warehouse A uses 60 credits and
  Warehouse B uses 50 credits in the same interval. What happens?

    A) Nothing — each warehouse has its own effective 100-credit
       allowance
    B) Only Warehouse B is suspended, since it pushed the total over
       quota
    C) The monitor's SUSPEND/SUSPEND_IMMEDIATE trigger fires against
       BOTH warehouses, since their usage is pooled against one shared
       quota
    D) The monitor automatically splits the quota 50/50 between them
       going forward

  ANSWER: C

  EXPLANATION: When multiple warehouses share one resource monitor,
  their credit usage POOLS against that single quota — 60 + 50 = 110,
  which exceeds the 100-credit quota regardless of which warehouse's
  activity technically crossed the line. A SUSPEND or SUSPEND_IMMEDIATE
  trigger then suspends every warehouse assigned to that monitor, not
  just whichever one happened to be running last.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q13 — Account-level monitor replacement (9.8, capstone)
═══════════════════════════════════════════════════════════════════════════

  An account already has Monitor_A set as its account-level resource
  monitor. An administrator runs ALTER ACCOUNT SET RESOURCE_MONITOR =
  Monitor_B. What happens to Monitor_A?

    A) The statement fails — only one account-level assignment change
       is allowed per day
    B) Monitor_A is dropped entirely
    C) Monitor_A silently loses its account-level assignment (its
       LEVEL reverts to NULL) but continues to exist as an object
    D) Both Monitor_A and Monitor_B are now active at the account
       level simultaneously

  ANSWER: C

  EXPLANATION: Assigning a new account-level monitor silently replaces
  the previous one — no error, no warning. The old monitor (Monitor_A)
  isn't dropped; it simply reverts to LEVEL = NULL in SHOW RESOURCE
  MONITORS, meaning it's no longer monitoring anything at either scope
  unless separately reassigned. Only one resource monitor can hold the
  account-level role at any given time.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q14 — Alerts vs. resource monitors (9.9)
═══════════════════════════════════════════════════════════════════════════

  Which of the following is true of a newly created Snowflake ALERT?

    A) It begins evaluating its condition on its defined schedule
       immediately
    B) It is suspended by default and must be explicitly resumed
    C) It requires no warehouse, the same as a resource monitor
    D) Its condition and action SQL are validated for correctness at
       CREATE time

  ANSWER: B

  EXPLANATION: Like Tasks, a newly created Alert is SUSPENDED by
  default — ALTER ALERT ... RESUME is required before it does
  anything. C is false: unlike a resource monitor (which needs no
  compute to evaluate), an Alert's condition and action run on a real
  WAREHOUSE you specify, and that's billed compute. D is also false —
  neither the condition nor the action SQL is validated until the
  alert actually executes; a typo in either won't surface until you
  check ALERT_HISTORY after a scheduled run.
*/

/*═══════════════════════════════════════════════════════════════════════════
  Q15 — Alert scheduling functions (9.9)
═══════════════════════════════════════════════════════════════════════════

  What is the purpose of SNOWFLAKE.ALERT.LAST_SUCCESSFUL_SCHEDULED_
  TIME() inside an alert's condition query?

    A) It returns the current wall-clock time, identical to
       CURRENT_TIMESTAMP()
    B) It scopes the condition to only the window since the alert's
       last successful run, avoiding re-alerting on already-reported
       data
    C) It pauses the alert until the specified time is reached
    D) It is only usable in the alert's ACTION clause, not its
       CONDITION clause

  ANSWER: B

  EXPLANATION: Used together with SNOWFLAKE.ALERT.SCHEDULED_TIME(), it
  bounds the condition query to just the interval since the last time
  the alert successfully fired — without it, a recurring schedule would
  keep re-evaluating and re-alerting on the same already-reported
  activity every time it runs. Both functions are usable only inside an
  alert's own condition/action context, not as general-purpose
  functions elsewhere.
*/
