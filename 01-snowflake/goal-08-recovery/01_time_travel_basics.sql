/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8       : Recover from Mistakes
  Sub-task 8.1 : Time Travel Fundamentals — Querying Historical Data
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~25 minutes
  Warehouse size    : X-Small (WORKBOOK_WH)
  Database          : ECOMMERCE
  Run in            : Snowsight
  Prerequisites     : Goals 1-2 complete (ECOMMERCE.RAW loaded, 10,370,254 rows)
  COF-C03 domain    : 1.0 Snowflake AI Data Cloud Features & Architecture (31%)
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  You will intentionally break a table with a bad UPDATE, then recover the
  original values three different ways — by OFFSET, by TIMESTAMP, and by
  STATEMENT (query ID) — using Snowflake's AT | BEFORE clause. This is the
  single most common "oh no" moment in production Snowflake work: someone
  runs an UPDATE or DELETE without a WHERE clause, and Time Travel is the
  first line of defense before anyone needs to escalate to support or
  restore from backups. Everything here works against a disposable sandbox
  table, not the live ORDERS table, so you can safely break it on purpose.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════
  Every DML statement in Snowflake (INSERT, UPDATE, DELETE, MERGE, TRUNCATE,
  and object DROP) preserves the prior state of the data for a configurable
  number of days — the data retention period (1 day by default on Standard
  Edition, up to 90 days on Enterprise). Within that window, the AT | BEFORE
  clause lets you query the table as it existed at a past point, specified
  three ways:

    TIMESTAMP  — an exact date/time
    OFFSET     — seconds relative to now (always negative, e.g. -300 = 5 min ago)
    STATEMENT  — the query ID of a specific statement, using its state
                 immediately before (BEFORE) or after (AT) that statement ran

  AT | BEFORE can be used in SELECT statements and in CREATE ... CLONE
  commands (CLONE is covered in 8.5-8.6). This sub-task covers SELECT only.

  ── Oracle / SQL Server comparison ─────────────────────────────────────
  Oracle has Flashback Query (AS OF TIMESTAMP / AS OF SCN) — conceptually
  the closest analog, also with a configurable retention window (UNDO
  retention). SQL Server's Temporal Tables (FOR SYSTEM_TIME AS OF) are
  similar but require the table to be explicitly declared SYSTEM_VERSIONED
  up front, with history rows maintained in a separate table you manage.
  Snowflake's Time Travel is automatic on every table with no setup step
  and no separate history table to manage — the tradeoff is the retention
  window is capped (90 days max) rather than indefinite.

  Watch out — TRUNCATE crosses the DDL/DML line differently here. In
  Oracle, SQL Server, and MySQL, TRUNCATE is DDL: it implicitly commits,
  cannot be rolled back, and resets identity/high-water-mark state. In
  Snowflake, TRUNCATE is officially classified as DML alongside INSERT,
  UPDATE, DELETE, and MERGE — it participates in explicit transactions
  and CAN be rolled back if the transaction fails or is explicitly rolled
  back, same as an UPDATE. Muscle memory from Oracle ("TRUNCATE = instant,
  no going back") does not hold in Snowflake.
  ────────────────────────────────────────────────────────────────────────
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════
  Create a disposable sandbox table so the "oops" DML below never touches
  the real ORDERS table.
───────────────────────────────────────────────────────────────────────────*/

USE DATABASE ECOMMERCE;
USE SCHEMA RAW;
USE WAREHOUSE WORKBOOK_WH;

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_TT_SANDBOX AS
SELECT *
FROM ECOMMERCE.RAW.ORDERS
LIMIT 1000
;

SELECT COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_TT_SANDBOX
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Establish a baseline and capture the "before" timestamp
═══════════════════════════════════════════════════════════════════════════*/

-- Note the current time before anything changes — you'll use this in
-- STEP 3's OFFSET/TIMESTAMP recovery queries below.
SELECT CURRENT_TIMESTAMP() AS baseline_timestamp
;

SELECT order_id, order_status
FROM ECOMMERCE.RAW.ORDERS_TT_SANDBOX
LIMIT 10
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Break it: an UPDATE with no WHERE clause
═══════════════════════════════════════════════════════════════════════════*/

-- Highlight from BEGIN through COMMIT and run together
BEGIN;

UPDATE ECOMMERCE.RAW.ORDERS_TT_SANDBOX
SET order_status = 'cancelled'
;

-- Used to replace <update_query_id> below — must run BEFORE COMMIT,
-- immediately after the UPDATE. LAST_QUERY_ID() returns whatever
-- statement most recently completed in the session, so capturing it
-- any later (after COMMIT, or after a confirmation SELECT) returns
-- that later statement's ID instead of the UPDATE's.
--
-- Alternative: if you didn't capture it live, or need a query ID from
-- an earlier session/statement entirely, Snowsight's own UI has it —
-- Monitoring > Query History, filter by SQL text or table name, and
-- copy the Query ID column directly. No ordering gotcha there since
-- you're reading it after the fact rather than relying on session state.
SELECT LAST_QUERY_ID() AS update_query_id
;

COMMIT;

-- Confirm the damage — every row now shows 'cancelled'
SELECT order_status, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_TT_SANDBOX
GROUP BY order_status
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Recover by OFFSET (seconds relative to now)
═══════════════════════════════════════════════════════════════════════════*/

-- Adjust -120 to roughly how many seconds ago STEP 1's baseline ran
SELECT order_id, order_status
FROM ECOMMERCE.RAW.ORDERS_TT_SANDBOX AT(OFFSET => -120)
LIMIT 10
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Recover by TIMESTAMP (exact point in time)
═══════════════════════════════════════════════════════════════════════════*/

-- <baseline_timestamp> — replace with the value STEP 1 returned
SELECT order_id, order_status
FROM ECOMMERCE.RAW.ORDERS_TT_SANDBOX AT(TIMESTAMP => '<baseline_timestamp>'::TIMESTAMP_LTZ)
LIMIT 10
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 5 — Recover by STATEMENT (query ID)
═══════════════════════════════════════════════════════════════════════════*/

-- BEFORE(STATEMENT => ...) returns the state immediately before that
-- statement ran — this is the most precise recovery method because it
-- doesn't depend on guessing a timestamp or offset at all.
-- <update_query_id> — replace with the value STEP 2 returned
SELECT order_id, order_status
FROM ECOMMERCE.RAW.ORDERS_TT_SANDBOX BEFORE(STATEMENT => '<update_query_id>')
LIMIT 10
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 6 — Actually restore the table using the STATEMENT method
═══════════════════════════════════════════════════════════════════════════*/

-- Highlight from BEGIN through COMMIT and run together
BEGIN;

UPDATE ECOMMERCE.RAW.ORDERS_TT_SANDBOX AS current_tbl
SET current_tbl.order_status = historical_tbl.order_status
FROM ECOMMERCE.RAW.ORDERS_TT_SANDBOX BEFORE(STATEMENT => '<update_query_id>') AS historical_tbl
WHERE current_tbl.order_id = historical_tbl.order_id
;

COMMIT;

-- Confirm the restore — order_status values should now be back to their
-- pre-STEP-2 mix instead of 100% 'cancelled'
SELECT order_status, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_TT_SANDBOX
GROUP BY order_status
;


/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════
  1. Run a DELETE against ORDERS_TT_SANDBOX that removes rows where
     order_status = 'cancelled' (there should be none left after STEP 6 — insert
     a couple of test rows first, or delete on a different column). Then
     recover the deleted rows using AT(STATEMENT => ...) instead of BEFORE.
     What's the practical difference between AT and BEFORE for the same
     query ID?

  2. Try an OFFSET value that goes back further than the table's retention
     period (e.g. -864000, ten days). What error do you get, and how does
     it differ from an OFFSET that's simply before the table existed?

  3. Find a completed query in Snowsight's Query History panel (any query,
     not necessarily one of yours from this file) and use its query ID in
     an AT(STATEMENT => ...) clause against ORDERS_TT_SANDBOX. Does it
     matter whether that query touched this table at all?
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════
  Q: What happens if I run a Time Travel query with a TIMESTAMP from
     before the table was created?
  A: Snowflake returns an error — the requested time is outside the range
     for which history exists, since a table has no historical state
     before its own creation.

  Q: Does Time Travel let me recover from a TRUNCATE?
  A: Yes — TRUNCATE is a DML operation like any other here, and the
     pre-truncate state is recoverable with AT | BEFORE within the
     retention period, same as an UPDATE or DELETE.

  Q: My OFFSET and TIMESTAMP recovery queries in STEP 3-4 returned slightly
     different-looking row counts or values than the STATEMENT-based one
     in STEP 5 — why?
  A: OFFSET and TIMESTAMP are approximate by nature — if any other session
     or process modified the table between your baseline capture and the
     UPDATE, an offset/timestamp a few seconds off from the exact moment
     can land you either just before or just after that other change.
     STATEMENT pins to an exact query ID with no ambiguity, which is why
     it's the more reliable method when precision matters.

  Q: Is there a performance cost to querying Time Travel data versus
     current data?
  A: Not meaningfully — Time Travel data lives in the same underlying
     immutable micro-partition storage as current data; Snowflake is just
     resolving which partitions were visible at the requested point in
     time. The query still benefits from normal pruning and caching.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CLEANUP (optional)
═══════════════════════════════════════════════════════════════════════════
  ORDERS_TT_SANDBOX is a 1,000-row disposable table — no ongoing credit
  cost worth flagging. Leave it in place; 8.2-8.7 reuse the same sandbox
  pattern, and it can be dropped at the end of the goal if desired.
───────────────────────────────────────────────────────────────────────────*/
