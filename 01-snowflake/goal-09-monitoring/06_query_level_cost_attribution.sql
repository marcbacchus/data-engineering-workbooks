/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 9       : Monitor and Manage Costs
  Sub-task 9.6 : Query-Level Cost Attribution
═══════════════════════════════════════════════════════════════════════════*/

/*───────────────────────────────────────────────────────────────────────────
  Time to complete   : ~25 min
  Warehouse size      : X-Small (WORKBOOK_WH)
  Database             : ECOMMERCE
  Run in                : Snowsight
  Prerequisites         : 9.5 complete; ACCOUNTADMIN, or a role granted
                           IMPORTED PRIVILEGES on the SNOWFLAKE database
  COF-C03 domain        : 2.0 Account Management and Data Governance (20%)
───────────────────────────────────────────────────────────────────────────*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════

  9.2-9.5 covered credits at the WAREHOUSE and ACCOUNT level. This
  sub-task drills down one more level: attributing cost to individual
  QUERIES. Two tools do this together — QUERY_TAG lets you label queries
  with metadata BEFORE they run, so you can group cost by team, job, or
  purpose later; QUERY_ATTRIBUTION_HISTORY gives you an actual credit
  figure PER QUERY after the fact, something plain QUERY_HISTORY doesn't
  provide on its own.
*/

/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════

  QUERY_TAG — a session parameter, up to 2000 characters, that labels
  every subsequent query in that session:

      ALTER SESSION SET QUERY_TAG = '<string>';

  It can also be set at the USER level (ALTER USER <name> SET QUERY_TAG
  = '<string>') or ACCOUNT level (ALTER ACCOUNT SET QUERY_TAG =
  '<string>', ACCOUNTADMIN only). Precedence when more than one is set:
  SESSION beats USER beats ACCOUNT. Once queries run with a tag, that
  tag shows up in the QUERY_TAG column of QUERY_HISTORY (both the
  INFORMATION_SCHEMA function and the ACCOUNT_USAGE view), letting you
  filter or GROUP BY it later — exactly the "attribute cost to a team or
  job" use case COF-C03 domain 2.0 has in mind.

  QUERY_HISTORY gives you performance signals per query (EXECUTION_TIME,
  BYTES_SCANNED, WAREHOUSE_SIZE, WAREHOUSE_NAME) but does NOT give you a
  clean per-query COMPUTE credit figure — CREDITS_USED_CLOUD_SERVICES is
  there, but the warehouse compute cost of one specific query among many
  running concurrently isn't something QUERY_HISTORY breaks out on its
  own.

  QUERY_ATTRIBUTION_HISTORY closes that gap — an ACCOUNT_USAGE view that
  returns CREDITS_ATTRIBUTED_COMPUTE per query, computed as a weighted
  average share of the warehouse's resource consumption, EXCLUDING idle
  time. Covers standard warehouses over the last 365 days. Latency: up
  to 8 hours — the longest latency figure you've hit anywhere in Goal 9
  so far, worth remembering precisely because it's an outlier against
  the 2-3 hour figures from 9.3-9.5.

  ─────────────────────────────────────────────────────────────────────────
  Oracle / SQL Server comparison:

  Oracle's AWR captures per-SQL-statement resource consumption (via
  DBA_HIST_SQLSTAT — CPU time, buffer gets, elapsed time per SQL_ID),
  which is conceptually the closest on-prem analog to per-query
  attribution. The difference is what that data is FOR: in Oracle, per-
  statement stats exist to find tuning targets — the SQL_IDs burning the
  most CPU so a DBA can optimize them, with no dollar figure attached
  because Oracle licensing isn't metered per statement. Snowflake's
  QUERY_ATTRIBUTION_HISTORY answers a genuinely different question — not
  just "which query is slow" but "which query cost how many credits" —
  because in Snowflake's billing model, every query genuinely has a
  dollar-denominated answer to that question, where in Oracle it never
  did.
  ─────────────────────────────────────────────────────────────────────────
*/

/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;

-- Same ACCOUNT_USAGE access requirement as 9.3-9.5 for Steps 3-4.

/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Tag a session, run sample queries, confirm the tag lands
═══════════════════════════════════════════════════════════════════════════*/

ALTER SESSION SET QUERY_TAG = 'goal9_cost_attribution_demo';

-- Two throwaway queries against ECOMMERCE to generate tagged activity
SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS;
SELECT COUNT(*) FROM ECOMMERCE.RAW.CUSTOMERS;

-- Confirm the tag shows up — INFORMATION_SCHEMA reflects this almost
-- immediately, no ACCOUNT_USAGE latency to wait out
SELECT
    query_id,
    query_tag,
    query_text,
    warehouse_name,
    execution_time
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_tag = 'goal9_cost_attribution_demo'
ORDER BY start_time DESC;

-- Unset it once you're done tagging deliberately for this exercise —
-- leaving a stale QUERY_TAG active would mis-label unrelated queries
-- later in the session
ALTER SESSION UNSET QUERY_TAG;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Most expensive queries by execution time, last 7 days
═══════════════════════════════════════════════════════════════════════════*/

SELECT
    query_id,
    query_text,
    warehouse_name,
    warehouse_size,
    execution_time,
    bytes_scanned,
    start_time
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'WORKBOOK_WH'
  AND start_time >= DATEADD('days', -7, CURRENT_DATE())
ORDER BY execution_time DESC
LIMIT 20;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Actual credits attributed per query
═══════════════════════════════════════════════════════════════════════════*/

SELECT
    query_id,
    warehouse_name,
    credits_attributed_compute,
    start_time
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE warehouse_name = 'WORKBOOK_WH'
  AND start_time >= DATEADD('days', -7, CURRENT_DATE())
ORDER BY credits_attributed_compute DESC
LIMIT 20;

/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Join execution time against attributed cost
═══════════════════════════════════════════════════════════════════════════

  A slow query isn't automatically an expensive one, and vice versa —
  this join is what actually tells you which queries are worth
  optimizing FOR COST, not just for speed.
*/

SELECT
    qh.query_id,
    qh.warehouse_size,
    qh.execution_time,
    qh.bytes_scanned,
    qa.credits_attributed_compute
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY qa
  ON qh.query_id = qa.query_id
WHERE qh.warehouse_name = 'WORKBOOK_WH'
  AND qh.start_time >= DATEADD('days', -7, CURRENT_DATE())
ORDER BY qa.credits_attributed_compute DESC
LIMIT 20;

/*
  Given this account has run everything on a single X-Small warehouse
  throughout the workbook series, don't expect to see WAREHOUSE_SIZE
  vary in this result — every row will show X-Small. That's an expected
  limitation of a single-warehouse training account, not a query error;
  the join logic itself is what matters, and it's exactly what you'd
  reuse in a real multi-warehouse account to spot a query that's
  disproportionately expensive for a given size.
*/

/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════

  1. Set an ACCOUNT-level QUERY_TAG (ACCOUNTADMIN required), then set a
     SESSION-level tag in the same session and run one query. Which tag
     shows up against that query in QUERY_HISTORY? Confirm your answer
     matches the documented precedence order.

  2. Step 3 excludes idle time from CREDITS_ATTRIBUTED_COMPUTE by
     design. Using 9.3's idle-cost calculation (SUM(credits_used_compute)
     minus SUM(credits_attributed_compute_queries) from the warehouse-
     level view, if that column existed on your account), reason through
     why a query-level attribution view and a warehouse-level idle-cost
     calculation are answering two different but complementary
     questions.

  3. Rewrite Step 4 to group by QUERY_TAG instead of listing individual
     QUERY_IDs, summing credits_attributed_compute per tag. What would
     you need to have done differently earlier in this workbook series
     for that query to return anything more interesting than one
     untagged bucket?

  4. QUERY_ATTRIBUTION_HISTORY's 8-hour latency is the longest you've
     hit in Goal 9. If you needed a same-day answer to "which query cost
     the most today," could this view give it to you reliably? What
     would you reach for instead, and what would you give up by using it?
*/

/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════

  Q: Step 4 returned rows but every credits_attributed_compute value
     looked suspiciously small or zero. Is that a bug?
  A: Likely not — a single COUNT(*) query like the ones in Step 1 does
     very little work, and on an X-Small warehouse with fast result
     caching, actual attributed compute for trivial queries can
     legitimately round to a very small fraction of a credit. Small
     numbers here reflect small workloads, not a broken join.

  Q: Why exclude idle time from QUERY_ATTRIBUTION_HISTORY instead of
     just dividing total warehouse cost evenly across every query that
     ran in an hour?
  A: An even split would misrepresent cost — a query that ran for 2
     seconds and a query that ran for 55 seconds in the same hour didn't
     consume the same share of that warehouse's compute. The weighted-
     average approach documented for this view attributes cost
     proportionally to actual resource consumption per query, which is
     a materially more honest number for identifying genuinely expensive
     queries than an even split would be.

  Q: Can I set QUERY_TAG to a JSON string instead of plain text?
  A: Yes — QUERY_TAG is just a string up to 2000 characters, so a JSON-
     formatted tag like '{"team":"analytics","job":"daily_load"}' is a
     common pattern that lets you encode multiple attributes in one tag
     and parse them back out of QUERY_HISTORY.QUERY_TAG later with
     Snowflake's semi-structured functions. Not required for this
     sub-task, but worth knowing if you want richer attribution than a
     flat label provides.

  Q: Does unsetting QUERY_TAG in Step 1 affect queries that already ran
     with it set?
  A: No — QUERY_TAG is captured per query at the time it runs, not
     retroactively. Unsetting it only stops the tag from applying to
     queries you run AFTER the ALTER SESSION UNSET statement; everything
     tagged earlier in Step 1 keeps that tag permanently in QUERY_HISTORY.
*/
