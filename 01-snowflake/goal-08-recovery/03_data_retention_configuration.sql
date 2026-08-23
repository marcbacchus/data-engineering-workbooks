/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8       : Recover from Mistakes
  Sub-task 8.3 : DATA_RETENTION_TIME_IN_DAYS — Configuring Retention
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~25 minutes
  Warehouse size    : X-Small (WORKBOOK_WH)
  Database          : ECOMMERCE
  Run in            : Snowsight
  Prerequisites     : 8.1-8.2 complete
  COF-C03 domain    : 1.0 Snowflake AI Data Cloud Features & Architecture (31%)
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  8.1 and 8.2 both assumed a retention window existed and was long enough
  to recover from. This sub-task is about the parameter that actually
  controls that window — DATA_RETENTION_TIME_IN_DAYS — at every level it
  can be set (account, database, schema, table), how inheritance works
  between those levels, and the hard caps that apply regardless of what
  you try to set (transient/temporary tables never exceed 1 day, no
  matter what their parent database says).
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════
  DATA_RETENTION_TIME_IN_DAYS can be set at four levels:

    ACCOUNT   — the account-wide default (ACCOUNTADMIN only)
    DATABASE  — default for schemas/tables created in it
    SCHEMA    — default for tables created in it
    TABLE     — the object's own explicit value

  If a level doesn't set its own value explicitly, it INHERITS from its
  parent — and that inheritance is LIVE for active objects, not a
  snapshot taken at creation time. A table that never sets its own
  explicit value keeps following its parent schema/database's CURRENT
  setting indefinitely; only setting an explicit value directly on the
  object itself makes it stop following the parent. (Dropped objects
  behave differently — see the WHAT IF at the end of this file.)

  Hard caps, regardless of what any parent level says:
    - Permanent databases/schemas/tables: 0-90 days (Enterprise+); 0-1 on
      Standard Edition
    - Transient databases/schemas/tables: 0 or 1 day, period — attempting
      to set anything higher (confirmed live: 30 on a transient table)
      raises a hard compilation error, "invalid value [n] for parameter
      'DATA_RETENTION_TIME_IN_DAYS'" — it does NOT silently cap at 1
    - Temporary tables: same 0-or-1 cap as transient, and the table is
      purged at session end regardless, so the effective window is
      whichever is shorter

  Setting retention to 0 disables Time Travel for that object entirely —
  no AT | BEFORE queries, no UNDROP. For a PERMANENT object this still
  drops into the 7-day Fail-safe (Snowflake-support-only recovery,
  covered in 8.4). For a TRANSIENT or TEMPORARY object there is no
  Fail-safe at all — retention 0 on a transient table means zero
  recovery path the instant it's dropped or overwritten.

  ── Oracle / SQL Server comparison ─────────────────────────────────────
  Oracle's closest lever is UNDO_RETENTION, but it's an instance-level
  (or PDB-level) setting only — there's no per-table or per-schema
  override, and it's advisory: Oracle can shrink the effective flashback
  window under UNDO tablespace pressure even if UNDO_RETENTION is set
  high. Snowflake's per-object granularity with real per-object caps is
  more precise and more predictable. SQL Server has nothing comparable
  at all outside of Temporal Tables, where "retention" just means how
  long you choose to keep rows in the history table before your own
  cleanup job (or built-in retention policy, SQL Server 2017+) purges
  them — a self-managed table, not a platform guarantee.
  ────────────────────────────────────────────────────────────────────────
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE DATABASE ECOMMERCE;
USE SCHEMA RAW;
USE WAREHOUSE WORKBOOK_WH;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Check current retention settings at each level
═══════════════════════════════════════════════════════════════════════════*/

-- Account-level default
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN ACCOUNT
;

-- Database-level (ECOMMERCE)
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN DATABASE ECOMMERCE
;

-- Schema-level (ECOMMERCE.RAW)
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN SCHEMA ECOMMERCE.RAW
;

-- Table-level (an existing table, to see what it currently inherited)
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE ECOMMERCE.RAW.ORDERS
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Set an explicit table-level retention override
═══════════════════════════════════════════════════════════════════════════*/

CREATE OR REPLACE TABLE ECOMMERCE.RAW.RETENTION_DEMO_PERMANENT (
    id INT
)
DATA_RETENTION_TIME_IN_DAYS = 10
;

SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE ECOMMERCE.RAW.RETENTION_DEMO_PERMANENT
;

-- Setting it after creation works the same way
ALTER TABLE ECOMMERCE.RAW.RETENTION_DEMO_PERMANENT SET DATA_RETENTION_TIME_IN_DAYS = 15
;

SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE ECOMMERCE.RAW.RETENTION_DEMO_PERMANENT
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Inheritance: schema default flows down to a table that
  doesn't set its own value — and keeps following it LIVE
═══════════════════════════════════════════════════════════════════════════*/

CREATE OR REPLACE SCHEMA ECOMMERCE.RETENTION_DEMO_SCHEMA
DATA_RETENTION_TIME_IN_DAYS = 20
;

-- No explicit retention set here — inherits the schema's 20
CREATE TABLE ECOMMERCE.RETENTION_DEMO_SCHEMA.INHERITS_FROM_SCHEMA (
    id INT
)
;

SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE ECOMMERCE.RETENTION_DEMO_SCHEMA.INHERITS_FROM_SCHEMA
;

-- Now change the schema's default. Inheritance in Snowflake is LIVE, not
-- a snapshot taken at table-creation time — INHERITS_FROM_SCHEMA never
-- set its own explicit value, so it keeps following whatever the schema
-- currently says. Expect BOTH tables below to show 5, not 20 and 5.
ALTER SCHEMA ECOMMERCE.RETENTION_DEMO_SCHEMA SET DATA_RETENTION_TIME_IN_DAYS = 5
;

CREATE TABLE ECOMMERCE.RETENTION_DEMO_SCHEMA.CREATED_AFTER_SCHEMA_CHANGE (
    id INT
)
;

-- Expect 5 — re-inherited live from the schema's new value
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE ECOMMERCE.RETENTION_DEMO_SCHEMA.INHERITS_FROM_SCHEMA
;

-- Also 5 — created after the change, so no surprise here
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE ECOMMERCE.RETENTION_DEMO_SCHEMA.CREATED_AFTER_SCHEMA_CHANGE
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — The transient/temporary hard cap
═══════════════════════════════════════════════════════════════════════════
  Requesting 30 days on a transient table doesn't silently cap at 1 —
  confirmed live: it's a hard compilation error at CREATE time. Worth
  seeing directly rather than taking on faith.
───────────────────────────────────────────────────────────────────────────*/

-- Expect: SQL compilation error: invalid value [30] for parameter
-- 'DATA_RETENTION_TIME_IN_DAYS' — this statement fails outright, the
-- table is not created at all
CREATE OR REPLACE TRANSIENT TABLE ECOMMERCE.RAW.RETENTION_DEMO_TRANSIENT (
    id INT
)
DATA_RETENTION_TIME_IN_DAYS = 30
;

-- The only values a transient table's own explicit setting will accept
-- are 0 or 1
CREATE OR REPLACE TRANSIENT TABLE ECOMMERCE.RAW.RETENTION_DEMO_TRANSIENT (
    id INT
)
DATA_RETENTION_TIME_IN_DAYS = 1
;

SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE ECOMMERCE.RAW.RETENTION_DEMO_TRANSIENT
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 5 — Setting retention to 0
═══════════════════════════════════════════════════════════════════════════*/

ALTER TABLE ECOMMERCE.RAW.RETENTION_DEMO_PERMANENT SET DATA_RETENTION_TIME_IN_DAYS = 0
;

SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE ECOMMERCE.RAW.RETENTION_DEMO_PERMANENT
;

-- With retention at 0, this table has no Time Travel window left —
-- AT/BEFORE and UNDROP no longer apply to it going forward. It's still
-- a PERMANENT table though, so a future drop still lands in Fail-safe
-- for 7 days (Snowflake-support-only recovery — see 8.4). Not
-- demonstrated live here since Fail-safe recovery isn't self-service
-- and there's nothing to show interactively.


/*═══════════════════════════════════════════════════════════════════════════
  ⚠️ Account-level default — read-only in this file
═══════════════════════════════════════════════════════════════════════════
  ALTER ACCOUNT SET DATA_RETENTION_TIME_IN_DAYS = <n> changes the default
  for every future object account-wide that doesn't set its own value —
  intentionally NOT executed here. That's a blast-radius change on a
  shared account, not something to leave altered as a side effect of a
  workbook exercise. Syntax, for reference only:

    ALTER ACCOUNT SET DATA_RETENTION_TIME_IN_DAYS = <n>;

  Same caution applies to MIN_DATA_RETENTION_TIME_IN_DAYS, which sets an
  account-wide FLOOR — the effective retention for any object becomes
  MAX(object's own setting, this account minimum), which can silently
  override an object-level 0 or 1 you set intentionally for cost reasons.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CLEANUP
═══════════════════════════════════════════════════════════════════════════*/

DROP TABLE IF EXISTS ECOMMERCE.RAW.RETENTION_DEMO_PERMANENT
;

DROP TABLE IF EXISTS ECOMMERCE.RAW.RETENTION_DEMO_TRANSIENT
;

DROP SCHEMA IF EXISTS ECOMMERCE.RETENTION_DEMO_SCHEMA
;


/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════
  1. Create a permanent table with DATA_RETENTION_TIME_IN_DAYS = 95. Does
     it error immediately the same way the transient case in STEP 4 does
     (confirmed: hard compilation error, not a silent cap), or does the
     90-day Enterprise cap get enforced some other way?

  2. Query SNOWFLAKE.ACCOUNT_USAGE.TABLES for RETENTION_TIME on a few
     tables in ECOMMERCE.RAW (remember the ACCOUNTADMIN + latency notes
     from 8.2 STEP 3). Does the value shown match what SHOW PARAMETERS
     reported live? If not, which one do you trust and why?

  3. Set a table's retention to 0, wait a minute, then try running an
     AT(OFFSET => -30) query against it (from before you set it to 0).
     Does the retention change apply retroactively to history that
     already existed, or only going forward from when you changed it?
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════
  Q: I set DATA_RETENTION_TIME_IN_DAYS = 0 on a table, then changed my
     mind and set it back to 7. Do I get back the history that was
     purged while it was at 0?
  A: No. Retention 0 doesn't just hide history, it stops retaining it —
     once a change's retention window has passed (immediately, at 0),
     that historical version is gone (or, for a permanent table, already
     moved into Fail-safe) and raising the setting again only protects
     changes made AFTER the increase.

  Q: Does a higher DATA_RETENTION_TIME_IN_DAYS cost more even if nothing
     ever gets updated or deleted?
  A: No — retention only matters for CHANGED or DELETED data. An
     unchanging table costs the same in storage regardless of its
     retention setting, because there's no prior version being kept
     around. The cost shows up when rows are updated/deleted/dropped and
     Snowflake has to retain the old micro-partitions for the retention
     window.

  Q: Can I set different retention for a table than its schema without
     ACCOUNTADMIN?
  A: Yes — object-level (table, schema, database) retention just needs
     OWNERSHIP or the appropriate ALTER privilege on that specific
     object. ACCOUNTADMIN is only required for the ACCOUNT-level default
     and for MIN_DATA_RETENTION_TIME_IN_DAYS.

  Q: STEP 3 showed live inheritance for an active table — does a table
     I already DROPPED also keep following its parent schema's retention
     changes?
  A: No — this is the one place inheritance stops being live. A dropped
     object's retention is fixed at the value it had at the moment it
     was dropped. If a table inherited 90 days from its schema, gets
     dropped, and the schema's retention is later changed to 1 day, that
     dropped table is still recoverable via UNDROP for the full 90 days
     it had when it was dropped — the schema's later change has no
     effect on it. To actually shorten a dropped object's own retention,
     you'd have to UNDROP it, explicitly set a shorter value, then drop
     it again.
───────────────────────────────────────────────────────────────────────────*/
