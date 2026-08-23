/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8       : Recover from Mistakes
  Sub-task 8.5 : Zero-Copy Cloning Fundamentals
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~30 minutes
  Warehouse size    : X-Small (WORKBOOK_WH)
  Database          : ECOMMERCE
  Run in            : Snowsight
  Prerequisites     : 8.1-8.4 complete
  COF-C03 domain    : 1.0 Snowflake AI Data Cloud Features & Architecture (31%)
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  Cloning is where this goal shifts from "undo a mistake that already
  happened" to "make mistakes safe to make in the first place." A clone
  gives you a full, independent copy of a table, schema, or even an
  entire database in a fraction of the time a real data copy would take,
  and (initially) zero extra storage — the standard way to spin up a dev/test copy of production
  without waiting on a data load. This sub-task covers CURRENT-STATE
  cloning only (clone something as it exists right now); combining
  cloning with Time Travel to clone a PAST state is 8.6.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════
  CREATE <object> ... CLONE creates a new object whose metadata points at
  the SAME underlying micro-partitions as the source — no data is
  physically copied. A single TABLE clone is near-instant regardless of
  the source's row count, because it's one metadata operation cloning one
  set of pointers.

  SCHEMA and DATABASE clones are a different story — confirmed live: a
  10-table schema clone took ~22 seconds, not instant. That's expected
  and it's not about row count either. A schema/database clone isn't one
  bulk pointer-copy — it's one metadata operation PER CONTAINED OBJECT.
  Cloning a schema with 10 tables means individually cloning 10 tables'
  worth of metadata. Snowflake's own engineering team has documented
  multi-table schema/database clones taking well over 30 minutes on
  accounts with large numbers of objects, precisely because clone time
  scales with OBJECT COUNT, not data volume. For genuinely large numbers
  of tables, looping individual table clones can sometimes outperform a
  single schema/database CLONE statement.

  Storage cost follows a copy-on-write model:
    - At clone time: effectively zero extra storage — both objects point
      at identical micro-partitions
    - After a modification to EITHER side (source or clone): Snowflake
      writes NEW micro-partitions only for the changed data. Unchanged
      data keeps being shared between both objects.
    - Storage cost of a clone, going forward, is specifically the bytes
      that exist ONLY in the clone because of changes made after cloning

  What does and doesn't clone:
    - Tables, schemas, and databases clone directly with CREATE ... CLONE
    - Cloning a schema or database also clones (most of) its contained
      objects — but NOT external tables, stages, or pipes, which are
      silently skipped rather than erroring
    - Streams: any UNCONSUMED records on a cloned stream become
      inaccessible in the clone — this mirrors how Time Travel behaves
      for tables, since a stream's offset state doesn't clone cleanly
    - GRANTS are NOT copied by default. A cloned TABLE gets a fresh
      grant slate (just OWNERSHIP to whoever ran the clone) unless you
      add the COPY GRANTS parameter — but COPY GRANTS is a CREATE
      TABLE/CREATE VIEW keyword only. CREATE SCHEMA and CREATE DATABASE
      don't accept COPY GRANTS at all — there is no syntax that copies a
      schema's or database's OWN grants to its clone, full stop. The one
      thing that DOES carry over automatically for schema/database
      clones: privileges already granted on CHILD objects inside the
      source (e.g. a table's own grants) — a separate mechanism from
      COPY GRANTS entirely, confirmed live in STEP 5 below.

  ── Oracle / SQL Server comparison ─────────────────────────────────────
  Neither platform has a true equivalent built into the base product.
  Oracle's closest feature — cloning a Pluggable Database (PDB) via
  sparse/snapshot copy inside the multitenant architecture — requires the
  separately licensed Multitenant option and only operates at the
  whole-PDB level, not per-table or per-schema. SQL Server's Database
  Snapshots use a similar sparse-file, copy-on-write mechanism, but
  they're read-only, single-database-scoped, and mainly used for
  point-in-time reporting rather than as writable dev/test environments.
  Snowflake's version is writable immediately, works at table/schema/
  database granularity, needs no extra license, and takes one line of
  SQL — this is a genuine capability gap worth emphasizing to this
  audience, not just a syntax difference.
  ────────────────────────────────────────────────────────────────────────
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════*/

USE DATABASE ECOMMERCE;
USE SCHEMA RAW;
USE WAREHOUSE WORKBOOK_WH;
USE ROLE SYSADMIN;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Clone a table, current state
═══════════════════════════════════════════════════════════════════════════*/

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_CLONE_DEMO
CLONE ECOMMERCE.RAW.ORDERS
;

-- Row counts should match exactly
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS_CLONE_DEMO;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Verify zero-copy: both tables share the same CLONE_GROUP_ID
═══════════════════════════════════════════════════════════════════════════
  CLONE_GROUP_ID identifies the oldest common ancestor of a clone lineage
  — if the source and the clone share this ID, they're provably sharing
  the same underlying storage. Requires ACCOUNTADMIN. Also expect the
  clone's own ACTIVE_BYTES to be at or near zero at this point — it hasn't
  diverged from the source yet.
───────────────────────────────────────────────────────────────────────────*/

USE ROLE ACCOUNTADMIN;

SELECT
    table_name,
    clone_group_id,
    active_bytes / (1024*1024*1024) AS active_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE table_catalog = 'ECOMMERCE'
  AND table_schema = 'RAW'
  AND table_name IN ('ORDERS', 'ORDERS_CLONE_DEMO')
  AND table_dropped IS NULL
;

-- If ORDERS_CLONE_DEMO doesn't appear at all yet, that's ACCOUNT_USAGE
-- latency (up to ~90 min) — the clone hasn't propagated into this view
-- yet; wait and re-run. Also note: without the TABLE_DROPPED IS NULL
-- filter above, ORDERS can appear as MULTIPLE rows with different
-- CLONE_GROUP_IDs if it was ever dropped and recreated previously —
-- this view retains historical/dropped object versions by default, it
-- is not deduplicated to "current state only."

USE ROLE SYSADMIN;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Diverge the clone and watch storage split
═══════════════════════════════════════════════════════════════════════════*/

-- Highlight from BEGIN through COMMIT and run together
BEGIN;

UPDATE ECOMMERCE.RAW.ORDERS_CLONE_DEMO
SET order_status = 'test_divergence'
WHERE order_id = (SELECT MIN(order_id) FROM ECOMMERCE.RAW.ORDERS_CLONE_DEMO)
;

COMMIT;

-- Source is untouched — confirm no rows changed there
SELECT COUNT(*) AS affected_rows
FROM ECOMMERCE.RAW.ORDERS
WHERE order_status = 'test_divergence'
;

-- Re-check storage — expect the clone's ACTIVE_BYTES to now be
-- (slightly) nonzero, reflecting the one new micro-partition created
-- for the changed row, while ORDERS itself is unaffected. Latency
-- applies here — this may not show a change immediately.
USE ROLE ACCOUNTADMIN;

SELECT
    table_name,
    clone_group_id,
    active_bytes / (1024*1024*1024) AS active_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE table_catalog = 'ECOMMERCE'
  AND table_schema = 'RAW'
  AND table_name IN ('ORDERS', 'ORDERS_CLONE_DEMO')
  AND table_dropped IS NULL
;

USE ROLE SYSADMIN;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Grants do NOT clone by default
═══════════════════════════════════════════════════════════════════════════*/

-- Whatever roles currently have grants on ORDERS
SHOW GRANTS ON TABLE ECOMMERCE.RAW.ORDERS
;

-- The plain clone from STEP 1 — expect ONLY the OWNERSHIP grant to
-- SYSADMIN (whoever ran the clone), nothing carried over from ORDERS
SHOW GRANTS ON TABLE ECOMMERCE.RAW.ORDERS_CLONE_DEMO
;

-- Re-clone WITH COPY GRANTS this time
CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_CLONE_WITH_GRANTS
CLONE ECOMMERCE.RAW.ORDERS
COPY GRANTS
;

-- Now compare — this one should match ORDERS' explicit grants (minus
-- OWNERSHIP, which always goes to whoever ran the CREATE)
SHOW GRANTS ON TABLE ECOMMERCE.RAW.ORDERS_CLONE_WITH_GRANTS
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 5 — Clone a schema — child object grants replicate automatically
═══════════════════════════════════════════════════════════════════════════
  This is the separate mechanism noted in CONCEPT: schema/database clones
  carry over grants already set on objects INSIDE them, independent of
  whether COPY GRANTS was used for the schema itself.
───────────────────────────────────────────────────────────────────────────*/

CREATE OR REPLACE SCHEMA ECOMMERCE.RAW_CLONE_DEMO
CLONE ECOMMERCE.RAW
;

SHOW TABLES IN SCHEMA ECOMMERCE.RAW_CLONE_DEMO
;

-- Compare grants on one specific cloned table inside the schema against
-- the equivalent table in the original RAW schema
SHOW GRANTS ON TABLE ECOMMERCE.RAW_CLONE_DEMO.ORDERS
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 6 — Clone the entire database
═══════════════════════════════════════════════════════════════════════════
  ⚠️ This clones all 10 ECOMMERCE tables (10.37M rows). Expect this to
  take at least as long as STEP 5's schema clone (~22 sec for the same
  10 tables) — database/schema clones scale with object count, not row
  count, so this isn't instant despite still being metadata-only. Don't
  leave this lying around though — see CLEANUP below.
───────────────────────────────────────────────────────────────────────────*/

CREATE OR REPLACE DATABASE ECOMMERCE_CLONE_DEMO
CLONE ECOMMERCE
;

SHOW SCHEMAS IN DATABASE ECOMMERCE_CLONE_DEMO
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE_CLONE_DEMO.RAW.ORDERS
;


/*═══════════════════════════════════════════════════════════════════════════
  CLEANUP
═══════════════════════════════════════════════════════════════════════════
  ⚠️ ECOMMERCE_CLONE_DEMO in particular — a full database clone sitting
  around and then diverging (any DML against it) starts accumulating real
  storage cost with nothing gained after this exercise. Drop everything
  created in this file.
───────────────────────────────────────────────────────────────────────────*/

DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_CLONE_DEMO;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_CLONE_WITH_GRANTS;
DROP SCHEMA IF EXISTS ECOMMERCE.RAW_CLONE_DEMO;
DROP DATABASE IF EXISTS ECOMMERCE_CLONE_DEMO;


/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════
  1. Try CREATE TABLE ... CLONE against ECOMMERCE.RAW.ORDERS specifying a
     target schema that doesn't exist yet. Does the clone command create
     the schema for you, or does it require the destination to already
     exist?

  2. Attempt to clone a STAGE (internal or external, whichever you have
     available) directly with CREATE STAGE ... CLONE. Compare that
     against what happened silently in STEP 6 when the whole database
     (which may contain stages) was cloned. Consistent behavior, or not?

  3. Grant a new privilege on ECOMMERCE.RAW.ORDERS to some role AFTER
     already having created ORDERS_CLONE_WITH_GRANTS in STEP 4. Does the
     new grant retroactively show up on the clone? What does that confirm
     about "grants diverge immediately after clone time"?
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════
  Q: 8.5's intro called cloning "a fraction of the time" but the schema
     clone in STEP 5 took 22 seconds — is that a problem?
  A: No, that's expected and confirmed live. A single table clone is
     effectively one metadata operation and is near-instant. A schema or
     database clone is N metadata operations, one PER CONTAINED OBJECT —
     cloning a 10-table schema means 10 individual table-clone operations
     behind the scenes, not one bulk copy. Time scales with OBJECT COUNT,
     not row count or data volume. Snowflake's own engineering team has
     documented schema/database clones taking 30+ minutes on accounts
     with large numbers of tables for exactly this reason. Still vastly
     faster than a real data copy, just not literally instant once
     multiple objects are involved.

  Q: If I clone a table and then drop the ORIGINAL, what happens to the
     clone?
  A: The clone is unaffected — it has its own independent metadata entry
     and keeps working normally, still referencing whichever
     micro-partitions it needs (shared ones that haven't been purged, and
     any of its own from post-clone changes). This is exactly why
     CLONE_GROUP_ID exists — to track shared-storage lineage even after
     an ancestor in that lineage is gone.

  Q: Does cloning a TRANSIENT table produce a transient clone, or does
     table type reset to permanent?
  A: The clone keeps the source's table type — cloning a transient table
     produces a transient clone, a permanent table produces a permanent
     clone. Table type is one of the properties that carries over, unlike
     grants.

  Q: I need a clone of just PART of a table (some rows, not all). Does
     CLONE support a WHERE clause?
  A: No — CLONE always copies the entire object as it exists (or existed,
     with Time Travel in 8.6). For a filtered subset, you'd use
     CREATE TABLE ... AS SELECT ... WHERE instead — which is NOT
     zero-copy, since it's genuinely writing new data for whatever rows
     match the filter.

  Q: Does the clone's DATA_RETENTION_TIME_IN_DAYS setting come from the
     source table or reset to a default?
  A: Object parameters explicitly set on the source (including
     DATA_RETENTION_TIME_IN_DAYS) carry over to the clone at clone time.
     If the source was relying on inheritance from its schema/database
     rather than an explicit value, the clone inherits from ITS OWN
     parent container instead — same live-inheritance behavior covered
     in 8.3, just starting fresh at the clone's new location.
───────────────────────────────────────────────────────────────────────────*/
