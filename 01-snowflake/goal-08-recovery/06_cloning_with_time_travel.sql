/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8       : Recover from Mistakes
  Sub-task 8.6 : Cloning + Time Travel Combined
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~25 minutes
  Warehouse size    : X-Small (WORKBOOK_WH)
  Database          : ECOMMERCE
  Run in            : Snowsight
  Prerequisites     : 8.1-8.5 complete
  COF-C03 domain    : 1.0 Snowflake AI Data Cloud Features & Architecture (31%)
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  8.5 cloned things as they exist RIGHT NOW. This sub-task combines that
  with 8.1's AT | BEFORE syntax to clone a table, schema, or database as
  it existed at a PAST point in time — a point-in-time snapshot you can
  keep and query independently, rather than a one-off Time Travel SELECT
  against the live object. This is the pattern for "take a safety
  snapshot before a risky migration" that 8.9's capstone will lean on.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════
  CLONE accepts the same AT | BEFORE clause as 8.1's SELECT queries, with
  the same three parameters — TIMESTAMP, OFFSET, STATEMENT — placed right
  after the CLONE keyword:

    CREATE TABLE t_clone CLONE t AT(TIMESTAMP => '...');
    CREATE TABLE t_clone CLONE t AT(OFFSET => -3600);
    CREATE TABLE t_clone CLONE t BEFORE(STATEMENT => '<query_id>');

  Why clone-at-a-point-in-time instead of just running a Time Travel
  SELECT? A clone is a real, independent, persistent object — you get to
  keep querying it, joining it, running reports against it, indefinitely,
  without depending on the source table's Time Travel window still
  reaching that far back. A Time Travel SELECT is a one-off read; a
  point-in-time clone is a snapshot you own.

  Restrictions specific to this combination:
    - Only DATABASES, SCHEMAS, and NON-TEMPORARY TABLES support AT |
      BEFORE with CLONE. Temporary tables cannot be cloned at all — with
      or without Time Travel — because there's no persistent history to
      clone from once the session that created them is gone.
    - If you don't specify AT | BEFORE, the clone still implicitly pins
      to a timestamp (the moment the CREATE...CLONE statement started) —
      this keeps a long-running clone of a busy table internally
      consistent, rather than picking up partial changes mid-operation.
    - Cloning a SCHEMA or DATABASE at a past point can hit a real
      obstacle: if a child table's OWN retention period is shorter than
      how far back you're reaching, that child's historical data may
      already be gone — even if the parent schema/database's retention
      covers it. The CLONE command fails outright unless you add
      IGNORE TABLES WITH INSUFFICIENT DATA RETENTION, which skips just
      that table rather than failing the whole clone.
    - Cloning a schema/database AT | BEFORE a timestamp does not clone
      TASKS inside it — tasks are only included in a schema/database
      clone that has no AT|BEFORE clause (i.e., a current-state clone).

  ── Oracle / SQL Server comparison ─────────────────────────────────────
  This combination — point-in-time state, made into an independent
  writable object, in one statement — has no real equivalent in either
  platform. Oracle's Flashback Table restores in place (overwrites
  current state, same object), it doesn't produce a second independent
  copy. To get a separate point-in-time snapshot in Oracle you're back to
  RMAN duplicate-database-with-until-time, a heavyweight backup-restore
  operation, not a single DDL statement. SQL Server has nothing
  comparable at all short of restoring a full/log backup chain to a new
  database. This is genuinely one of the more distinctive capabilities
  in Snowflake's recovery toolkit for this audience to walk away
  remembering.
  ────────────────────────────────────────────────────────────────────────
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════
  A disposable sandbox table, with a captured baseline timestamp, then a
  "migration gone wrong" DELETE — mirroring 8.1's pattern but this time
  recovering via a NEW independent clone rather than rewriting the
  original table in place.
───────────────────────────────────────────────────────────────────────────*/

USE DATABASE ECOMMERCE;
USE SCHEMA RAW;
USE WAREHOUSE WORKBOOK_WH;
USE ROLE SYSADMIN;

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_CLONE_TT_DEMO AS
SELECT *
FROM ECOMMERCE.RAW.ORDERS
LIMIT 1000
;

SELECT CURRENT_TIMESTAMP() AS baseline_timestamp
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS_CLONE_TT_DEMO
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — The "migration gone wrong" moment
═══════════════════════════════════════════════════════════════════════════*/

-- Highlight from BEGIN through COMMIT and run together
BEGIN;

DELETE FROM ECOMMERCE.RAW.ORDERS_CLONE_TT_DEMO
WHERE order_id > (
    SELECT MIN(order_id) + 500
    FROM ECOMMERCE.RAW.ORDERS_CLONE_TT_DEMO
)
;

-- Used to replace <delete_query_id> below — must run BEFORE COMMIT,
-- immediately after the DELETE (same LAST_QUERY_ID() ordering gotcha
-- from 8.1)
SELECT LAST_QUERY_ID() AS delete_query_id
;

COMMIT;

-- Confirm the damage — roughly half the rows are gone
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS_CLONE_TT_DEMO
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Recover via a point-in-time TABLE clone, by TIMESTAMP
═══════════════════════════════════════════════════════════════════════════
  Unlike 8.1, this doesn't touch ORDERS_CLONE_TT_DEMO itself — it creates
  a brand new, fully independent table holding the pre-delete state.
───────────────────────────────────────────────────────────────────────────*/

-- <baseline_timestamp> — replace with the value SETUP returned
CREATE TABLE ECOMMERCE.RAW.ORDERS_RECOVERED_BY_TIMESTAMP
CLONE ECOMMERCE.RAW.ORDERS_CLONE_TT_DEMO
AT(TIMESTAMP => '<baseline_timestamp>'::TIMESTAMP_LTZ)
;

-- Expect the full pre-delete count — this table was never touched by
-- the DELETE in STEP 1
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS_RECOVERED_BY_TIMESTAMP
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Recover via a point-in-time TABLE clone, by STATEMENT
═══════════════════════════════════════════════════════════════════════════
  BEFORE(STATEMENT => ...) is the precise version, same reasoning as 8.1
  STEP 5 — no timestamp guessing required.
───────────────────────────────────────────────────────────────────────────*/

-- <delete_query_id> — replace with the value STEP 1 returned
CREATE TABLE ECOMMERCE.RAW.ORDERS_RECOVERED_BY_STATEMENT
CLONE ECOMMERCE.RAW.ORDERS_CLONE_TT_DEMO
BEFORE(STATEMENT => '<delete_query_id>')
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS_RECOVERED_BY_STATEMENT
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Point-in-time SCHEMA clone with IGNORE TABLES WITH
  INSUFFICIENT DATA RETENTION
═══════════════════════════════════════════════════════════════════════════
  Cloning ECOMMERCE.RAW as it existed a short time ago. Any sandbox table
  left over from 8.1-8.5 with a short (e.g. transient 1-day) retention
  that's already aged past this point would normally fail the WHOLE
  clone — this parameter skips just that table instead.
───────────────────────────────────────────────────────────────────────────*/

CREATE OR REPLACE SCHEMA ECOMMERCE.RAW_POINT_IN_TIME_DEMO
CLONE ECOMMERCE.RAW
AT(OFFSET => -300)
IGNORE TABLES WITH INSUFFICIENT DATA RETENTION
;

SHOW TABLES IN SCHEMA ECOMMERCE.RAW_POINT_IN_TIME_DEMO
;


/*═══════════════════════════════════════════════════════════════════════════
  CLEANUP
═══════════════════════════════════════════════════════════════════════════*/

DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_CLONE_TT_DEMO;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_RECOVERED_BY_TIMESTAMP;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_RECOVERED_BY_STATEMENT;
DROP SCHEMA IF EXISTS ECOMMERCE.RAW_POINT_IN_TIME_DEMO;


/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════
  1. Try CREATE TEMPORARY TABLE t_clone CLONE <any table> AT(OFFSET =>
     -60). Does it fail outright, or does it succeed but silently ignore
     the AT clause? Confirm which, since the docs state non-temporary
     tables only support the AT|BEFORE combination but don't specify the
     failure mode.

  2. STEP 4 used AT(OFFSET => -300) — a point recent enough that
     IGNORE TABLES WITH INSUFFICIENT DATA RETENTION likely had nothing
     to actually skip. Find (or create) a transient table with a 1-day
     retention in ECOMMERCE.RAW, wait past that window conceptually (or
     reason through it), and predict whether a schema clone reaching
     back 2+ days would skip it or fail the whole operation without the
     IGNORE parameter.

  3. Clone ECOMMERCE.RAW at a point in time using AT(TIMESTAMP => ...)
     and check whether any Tasks that exist in that schema show up in
     the clone, per the CONCEPT note that AT|BEFORE schema clones skip
     Tasks entirely. Then clone it again with no AT|BEFORE clause at all
     and compare.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════
  Q: Why would I ever use a point-in-time CLONE instead of just running
     the recovery pattern from 8.1 (query historical data, then UPDATE
     the live table back)?
  A: 8.1's approach is right when you want to fix the SAME table in
     place and keep using it. A point-in-time clone is right when you
     want to KEEP the pre-mistake version around independently — to
     compare old vs. new, to hand the snapshot to someone else for
     verification before deciding whether to actually roll back, or to
     preserve evidence of what changed without touching the live object
     at all.

  Q: Does the new clone from STEP 2/3 have its OWN Time Travel history
     going back further, since it was cloned from a point in the past?
  A: No — a clone's Time Travel history starts fresh at the moment the
     clone itself is created, regardless of what point in the source's
     history it was cloned FROM. ORDERS_RECOVERED_BY_TIMESTAMP has no
     Time Travel access to anything before ITS OWN creation, even though
     it visually represents an earlier state of ORDERS_CLONE_TT_DEMO.

  Q: If the source table gets DROPPED and PURGED (past Fail-safe, fully
     gone) after I already created a point-in-time clone from it, is the
     clone affected?
  A: No — once the clone exists, it's a fully independent object with
     its own metadata and its own claim on whichever micro-partitions it
     needs. It has no ongoing dependency on the source object continuing
     to exist.
───────────────────────────────────────────────────────────────────────────*/
