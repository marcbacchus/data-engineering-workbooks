/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8       : Recover from Mistakes
  Sub-task 8.2 : Recovering from Mistakes — UNDROP
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~30 minutes
  Warehouse size    : X-Small (WORKBOOK_WH)
  Database          : ECOMMERCE
  Run in            : Snowsight
  Prerequisites     : 8.1 complete
  COF-C03 domain    : 1.0 Snowflake AI Data Cloud Features & Architecture (31%)
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  8.1 recovered from a bad UPDATE by querying and rewriting data. This
  sub-task covers the other half of "oops": accidentally dropping a table,
  schema, or database outright. You'll drop objects at all three levels
  and bring them back with UNDROP, then handle the messier real-world
  version of the problem — what happens when someone drops an object AND
  a new object with the same name gets created before anyone notices.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════
  DROP TABLE, DROP SCHEMA, and DROP DATABASE don't actually delete the
  object — they retain a version of it in Time Travel for the object's
  data retention period, exactly like an UPDATE or DELETE retains prior
  row versions. UNDROP TABLE / UNDROP SCHEMA / UNDROP DATABASE restores
  the most recently dropped version, as long as you're still inside the
  retention window.

  Two wrinkles that trip people up:
    1. If an object with the same name already exists, UNDROP fails
       outright — you must rename the current object out of the way
       first, UNDROP the old one, then rename as needed afterward.
    2. If the same name has been dropped more than once, UNDROP TABLE /
       SCHEMA / DATABASE with just a name restores the MOST RECENT drop
       only. To reach an older dropped version, you need its specific
       object ID from SNOWFLAKE.ACCOUNT_USAGE (TABLES / SCHEMATA /
       DATABASES) and pass it via UNDROP ... IDENTIFIER('<object_id>').

  ── Oracle / SQL Server comparison ─────────────────────────────────────
  Oracle's closest equivalent is Flashback Drop, which recovers a table
  from the recycle bin via FLASHBACK TABLE ... TO BEFORE DROP — the same
  "it's not really gone yet" model as UNDROP, and it has the same
  same-name gotcha (Oracle's recycle bin can hold multiple dropped
  versions of one name, resolved by specifying a system-generated
  recycle-bin name). SQL Server has no native equivalent at all — no
  recycle bin, no flashback. Recovering a dropped table in SQL Server
  means restoring from a full/differential/log backup to a point in
  time before the drop, a fundamentally heavier operation with no
  built-in self-service path. UNDROP's zero-setup, self-service recovery
  is a genuine Snowflake differentiator worth calling out to this
  audience.
  ────────────────────────────────────────────────────────────────────────
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════
  Disposable objects only — a demo table, a demo schema, and a demo
  database — so nothing here touches production ECOMMERCE.RAW objects.
───────────────────────────────────────────────────────────────────────────*/

USE DATABASE ECOMMERCE;
USE SCHEMA RAW;
USE WAREHOUSE WORKBOOK_WH;

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO AS
SELECT *
FROM ECOMMERCE.RAW.ORDERS
LIMIT 100
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Drop and restore a table (the basic case)
═══════════════════════════════════════════════════════════════════════════*/

DROP TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;

-- Confirm it's gone from normal view
SHOW TABLES LIKE 'ORDERS_UNDROP_DEMO' IN SCHEMA ECOMMERCE.RAW
;

UNDROP TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;

SELECT COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — The name-conflict scenario
═══════════════════════════════════════════════════════════════════════════
  This is the realistic version: the table gets dropped, then someone
  (or some pipeline) creates a new table with the same name before the
  mistake is caught. A plain UNDROP now fails because the name is taken.
───────────────────────────────────────────────────────────────────────────*/

DROP TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;

-- A different, unrelated table gets created with the same name —
-- simulating a pipeline re-creating it before anyone notices the drop
CREATE TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO (
    note VARCHAR
)
;

INSERT INTO ECOMMERCE.RAW.ORDERS_UNDROP_DEMO (note)
VALUES ('this is the new unrelated table, not the original')
;

-- This UNDROP fails — an object with this name already exists
UNDROP TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;

-- Fix: rename the current (new, unrelated) table out of the way first
ALTER TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO RENAME TO ECOMMERCE.RAW.ORDERS_UNDROP_DEMO_NEW
;

-- Now the name is free and the original can be restored
UNDROP TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;

SELECT COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Restoring a specific (non-latest) dropped version by ID
═══════════════════════════════════════════════════════════════════════════
  Drop the table a second time to create a second dropped version of the
  same name, then use SNOWFLAKE.ACCOUNT_USAGE.TABLES to target the OLDER
  of the two by its table_id rather than whichever UNDROP would pick by
  default (the most recent drop).
───────────────────────────────────────────────────────────────────────────*/

DROP TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;

-- Requires ACCOUNTADMIN — ACCOUNT_USAGE views need it in this account
-- (confirmed repeatedly across Goals 4-7). Also carries ACCOUNT_USAGE's
-- normal latency (up to ~3 hrs) — if the drop above doesn't show up yet,
-- that's the latency, not a failure.
USE ROLE ACCOUNTADMIN;

SELECT table_id, table_name, created, deleted
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES
WHERE table_name = 'ORDERS_UNDROP_DEMO'
  AND table_schema = 'RAW'
  AND deleted IS NOT NULL
ORDER BY deleted DESC
;

-- Used to replace <older_table_id> below — take the table_id from the
-- SECOND row (older DELETED timestamp), not the most recent drop
UNDROP TABLE ECOMMERCE.RAW.ORDERS_UNDROP_DEMO IDENTIFIER('<older_table_id>')
;

SELECT COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — UNDROP SCHEMA
═══════════════════════════════════════════════════════════════════════════*/

CREATE OR REPLACE SCHEMA ECOMMERCE.UNDROP_DEMO_SCHEMA
;

CREATE TABLE ECOMMERCE.UNDROP_DEMO_SCHEMA.PLACEHOLDER (id INT)
;

DROP SCHEMA ECOMMERCE.UNDROP_DEMO_SCHEMA
;

UNDROP SCHEMA ECOMMERCE.UNDROP_DEMO_SCHEMA
;

SHOW TABLES IN SCHEMA ECOMMERCE.UNDROP_DEMO_SCHEMA
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 5 — UNDROP DATABASE
═══════════════════════════════════════════════════════════════════════════*/

CREATE OR REPLACE DATABASE UNDROP_DEMO_DB
;

CREATE TABLE UNDROP_DEMO_DB.PUBLIC.PLACEHOLDER (id INT)
;

DROP DATABASE UNDROP_DEMO_DB
;

UNDROP DATABASE UNDROP_DEMO_DB
;

SHOW TABLES IN SCHEMA UNDROP_DEMO_DB.PUBLIC
;


/*═══════════════════════════════════════════════════════════════════════════
  CLEANUP
═══════════════════════════════════════════════════════════════════════════*/

USE ROLE SYSADMIN;

DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_UNDROP_DEMO
;

DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_UNDROP_DEMO_NEW
;

DROP SCHEMA IF EXISTS ECOMMERCE.UNDROP_DEMO_SCHEMA
;

DROP DATABASE IF EXISTS UNDROP_DEMO_DB
;


/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════
  1. Drop ORDERS_UNDROP_DEMO_NEW (the renamed-out-of-the-way table from
     STEP 2) and restore it. Does it come back under its renamed name, or
     does UNDROP restore the name it had at the moment it was dropped?

  2. Drop a table, wait a few minutes, then try UNDROP TABLE with a
     table name that never existed. What does the error message tell you
     versus the error from trying to restore something past its
     retention period?

  3. In STEP 5, the restored UNDROP_DEMO_DB contains PLACEHOLDER — but
     what happens to grants that existed on the database or its objects
     before the drop? Check SHOW GRANTS ON DATABASE UNDROP_DEMO_DB before
     and after the drop/undrop cycle to find out.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════
  Q: I ran CREATE OR REPLACE TABLE instead of DROP + CREATE — does UNDROP
     still work?
  A: Yes. CREATE OR REPLACE is implemented as an atomic drop-and-create,
     so the prior version is dropped (and retained in Time Travel) exactly
     as if you'd run DROP TABLE yourself. The same UNDROP TABLE command
     recovers it.

  Q: What if I need to recover a dropped COLUMN, not a whole table?
  A: You can't — UNDROP only works at the table/schema/database object
     level. A dropped column (via ALTER TABLE ... DROP COLUMN) is not
     recoverable via UNDROP. Your only path back is Time Travel: query
     the table AT/BEFORE a point before the column was dropped and
     rebuild it from there.

  Q: Someone dropped a database that contained schemas and tables with
     their own explicit DATA_RETENTION_TIME_IN_DAYS settings, shorter
     than the database's. Does UNDROP DATABASE bring everything back?
  A: Only what's still within ITS OWN retention window. Each object's
     retention clock runs independently from when IT was dropped, not
     from the parent's setting — so a table with a 1-day retention
     nested inside a database with a 30-day retention can still be lost
     even though the database-level UNDROP itself succeeds.

  Q: Can I UNDROP something dropped by another user, or do I need to be
     the one who dropped it?
  A: Ownership/privilege on the object is what matters, not who ran the
     DROP. Any role with the right privilege on the dropped object (or
     its parent schema/database, depending on object type) can UNDROP it
     regardless of who deleted it.
───────────────────────────────────────────────────────────────────────────*/
