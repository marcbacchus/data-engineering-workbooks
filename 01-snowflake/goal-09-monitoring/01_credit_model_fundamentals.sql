/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9       : Monitor and Manage Costs
  Sub-task 9.1 : Credit Model Fundamentals
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~20 min
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : Goals 1-2 complete (WORKBOOK_WH configured,
                           ECOMMERCE database loaded)
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  Before you can monitor or control Snowflake spend, you need the mental
  model the rest of Goal 9 builds on: what a credit actually pays for, who
  burns credits (warehouses vs. Snowflake-managed serverless features), and
  the billing mechanics (per-second, 60-second minimum) that make auto-
  suspend the single highest-leverage cost control in the platform.

  This sub-task is inspection-only — no destructive DML, nothing to roll
  back. You're building vocabulary and looking at the objects you'll
  measure starting in 9.2.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════

  A Snowflake credit is the unit of compute consumption. Two categories
  spend credits:

    1. VIRTUAL WAREHOUSE compute — user-managed clusters that run queries,
       loads, and DML. You choose the size and control the auto-suspend/
       auto-resume behavior directly.
    2. SERVERLESS compute — features Snowflake runs FOR you with no
       warehouse attached (Snowpipe, Snowpipe Streaming, Automatic
       Clustering, Search Optimization Service, Materialized View
       maintenance, database replication, some Task/Alert executions).
       These show up in ACCOUNT_USAGE.METERING_HISTORY under their own
       service type, not under a warehouse name — that distinction
       matters starting in 9.4.

  Warehouse sizing is a doubling scale — each T-shirt size up doubles both
  compute resources and credits/hour:

      X-Small   1 credit/hr        X-Large    16 credits/hr
      Small     2 credits/hr       2X-Large   32 credits/hr
      Medium    4 credits/hr       3X-Large   64 credits/hr
      Large     8 credits/hr       4X-Large  128 credits/hr
                                   5X-Large  256 credits/hr
                                   6X-Large  512 credits/hr

  (Reference table only — there is no single SQL object that returns
  credit-per-hour rates directly; this is documented in Snowflake's
  Service Consumption Table, not queryable from within the account.)

  Billing mechanics: the first charge on ANY warehouse start (or resize)
  is a 60-second minimum, even if the warehouse only runs for 10 seconds.
  After that first minute, billing switches to per-second for as long as
  the warehouse keeps running. This is why AUTO_SUSPEND is the highest-
  leverage cost lever in the platform — every unnecessary idle minute
  after a query finishes is pure waste, and every unnecessary START
  re-triggers the 60-second minimum.

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  Oracle and SQL Server license compute continuously — you pay for
  provisioned cores/instances whether or not a query is running at 3am on
  a Sunday. There's no equivalent of "suspend the database and stop
  paying." Snowflake inverts this: a warehouse that's SUSPENDED costs
  nothing at all, and the unit of pricing is elapsed running time on a
  named warehouse, not a perpetual license tied to hardware. The practical
  consequence: in Oracle/SQL Server, cost control is mostly a licensing
  and hardware-provisioning exercise done up front. In Snowflake, cost
  control is an ongoing operational habit — right-sizing warehouses and
  tuning auto-suspend — because the meter runs in real time, per second,
  as long as compute is up.
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Confirm session and account context
═══════════════════════════════════════════════════════════════════════════

  Note: Snowflake edition (Standard/Enterprise/Business Critical) is NOT
  exposed through a SQL function — it's only visible in Snowsight under
  Admin » Billing & Terms, or via ORGANIZATION_USAGE views if you have an
  Organization account. Confirm your edition there if you need it; don't
  assume it from SQL output.
*/

SELECT
    CURRENT_ACCOUNT()        AS account_locator,
    CURRENT_ACCOUNT_NAME()   AS account_name,
    CURRENT_REGION()         AS region,
    CURRENT_WAREHOUSE()      AS active_warehouse,
    CURRENT_ROLE()           AS active_role;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Warehouse inventory
═══════════════════════════════════════════════════════════════════════════

  SHOW WAREHOUSES surfaces the columns that matter for cost control:
  size, state (STARTED/SUSPENDED), auto_suspend (seconds), auto_resume,
  and running/queued query counts. This is your at-a-glance cost-risk
  dashboard — any warehouse showing STARTED with a long auto_suspend and
  zero running queries is bleeding credits for nothing.
*/

SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Warehouse detail
═══════════════════════════════════════════════════════════════════════════

  DESCRIBE WAREHOUSE gives the same core columns as SHOW WAREHOUSES for a
  single warehouse — useful when you want one object's full config without
  scanning a filtered SHOW result.
*/

DESCRIBE WAREHOUSE WORKBOOK_WH;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Auto-suspend mechanics
═══════════════════════════════════════════════════════════════════════════

  Set an explicit, short auto_suspend so idle time after this session
  doesn't quietly bill. 60 seconds is the practical floor worth using day
  to day — going lower buys nothing, because 60 seconds is already the
  minimum billing unit on every warehouse start.
*/

ALTER WAREHOUSE WORKBOOK_WH SET AUTO_SUSPEND = 60;

-- Confirm the change took
SHOW WAREHOUSES LIKE 'WORKBOOK_WH';

/*
  What just happened, mechanically:
    - If WORKBOOK_WH was SUSPENDED before this ALTER, it stayed
      SUSPENDED — changing AUTO_SUSPEND does not itself start a warehouse.
    - The next query you run against WORKBOOK_WH will trigger a fresh
      START and immediately incur the 60-second minimum charge — that
      charge happens regardless of how short the query actually is.
    - After that, if WORKBOOK_WH sits idle for 60 continuous seconds, it
      auto-suspends and billing stops until the next query resumes it.
*/

/*═══════════════════════════════════════════════════════════════════════════
  STEP 5 — Warehouse vs. serverless: spotting the difference in object DDL
═══════════════════════════════════════════════════════════════════════════

  Tasks are a good place to SEE the warehouse/serverless split concretely:
  a task can either run on a named warehouse (WAREHOUSE = <name> in its
  DDL) or run on Snowflake-managed serverless compute (USER_TASK_MANAGED_
  INITIAL_WAREHOUSE_SIZE instead of WAREHOUSE). SHOW TASKS surfaces which
  one each task is using.
*/

SHOW TASKS IN SCHEMA ECOMMERCE.RAW;

/*
  Look at the "warehouse" column in the result:
    - A populated warehouse name  -> this task's runs bill against that
      warehouse's metering, exactly like any other query you'd find in
      9.2's WAREHOUSE_METERING_HISTORY.
    - NULL/blank                  -> this task runs on serverless compute;
      its cost shows up in 9.4's account-level METERING_HISTORY under a
      service type, with no warehouse name attached at all.

  Every task built earlier in this workbook series was pinned to
  WORKBOOK_WH explicitly, so don't be surprised if every row here shows a
  warehouse — that's expected, and it's WHY 9.4 is the sub-task that
  actually exercises the serverless side of METERING_HISTORY.
*/

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. Without looking back at the CONCEPT section, write down the
     credits/hour for Small, Large, and 2X-Large. Check your answer
     against the doubling rule (X-Small = 1, double per step up).

  2. If a query runs for 12 seconds on a freshly-resumed X-Small
     warehouse, how many seconds of compute are actually billed? Why?

  3. Suppose a warehouse has AUTO_SUSPEND = 600 (10 minutes) and a team
     runs one 5-second query every 10 minutes throughout an 8-hour
     workday. Roughly how much of that 8 hours is billed versus idle?
     What AUTO_SUSPEND value would eliminate most of the waste without
     hurting the team's experience?

  4. Using SHOW WAREHOUSES output from Step 2, identify every column
     that is directly cost-relevant (i.e., would change how many
     credits this warehouse burns) versus every column that is not.
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: If I never touch AUTO_SUSPEND, what's the default, and is it safe?
  A: New warehouses default to a 5-minute (300 second) AUTO_SUSPEND.
     It's not unsafe, but it's rarely optimal — for interactive/ad-hoc
     workloads, 60 seconds usually costs nothing in user experience and
     removes 4 minutes of pure idle billing per suspend cycle. Longer
     values only make sense when you know queries arrive in tight
     bursts and you're deliberately trading idle credits for avoiding
     repeated 60-second minimums on resume.

  Q: Does resizing a running warehouse cost anything by itself?
  A: Yes — a resize while running (e.g. Medium to Large) bills one
     minute at the NEW, higher rate, then reverts to per-second billing
     at that new rate. Resizing a SUSPENDED warehouse costs nothing
     until it next starts.

  Q: Are Cloud Services credits part of this same warehouse billing?
  A: No — Cloud Services (query compilation, authentication, metadata
     operations) is a separate meter, and Snowflake doesn't bill it at
     all as long as it stays under 10% of your daily warehouse compute
     credits. It's out of scope for this sub-task; ACCOUNT_USAGE views
     used later in Goal 9 focus on warehouse and serverless credits, not
     Cloud Services.

  Q: Why isn't edition (Standard/Enterprise/Business Critical) queryable
     via SQL?
  A: It's account-configuration metadata tied to your contract, not a
     session or warehouse property — Snowflake surfaces it in Snowsight's
     billing UI and in ORGANIZATION_USAGE for multi-account orgs, not
     through a CURRENT_*() function. Don't guess it from behavior; check
     the UI if a downstream step depends on it.
*/
