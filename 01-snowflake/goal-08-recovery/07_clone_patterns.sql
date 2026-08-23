/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8       : Recover from Mistakes
  Sub-task 8.7 : Practical Clone Patterns — Dev/Test Refresh & Clone-and-Swap
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~30 minutes
  Warehouse size    : X-Small (WORKBOOK_WH)
  Database          : ECOMMERCE
  Run in            : Snowsight
  Prerequisites     : 8.1-8.6 complete
  COF-C03 domain    : 1.0 Snowflake AI Data Cloud Features & Architecture (31%)
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  8.5-8.6 covered the CLONE mechanics. This sub-task is where cloning
  becomes a repeatable operational pattern instead of a one-off exercise:
  refreshing a dev/test environment from production on a recurring basis
  without repeatedly breaking its grants, and using CLONE together with
  ALTER TABLE ... SWAP WITH to make risky changes to a large table with
  near-zero downtime and no maintenance window.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════
  PATTERN 1 — Repeatable dev/test refresh, and its real grants trap
  A one-time CLONE (8.5) is easy. A refresh you run every night surfaces
  a sharper problem: COPY GRANTS is a CREATE TABLE / CREATE VIEW keyword
  ONLY — CREATE SCHEMA and CREATE DATABASE don't accept it at all, and
  there's no syntax that copies a schema's or database's own grants to
  its clone (confirmed live — CREATE SCHEMA ... CLONE ... COPY GRANTS is
  a straight syntax error). What DOES carry over automatically on a
  schema/database clone is child objects' OWN grants, replicated fresh
  from whatever the SOURCE's child objects currently have — a separate
  mechanism from COPY GRANTS entirely (this is what 8.5 STEP 5 actually
  demonstrated). The trap: if a developer grants some DEV-ONLY access
  that doesn't exist on the equivalent PROD object, that access is
  SILENTLY WIPED on the next nightly refresh, because the refresh
  re-derives child grants from prod's CURRENT state each time — it
  doesn't preserve whatever dev had before. The realistic mitigation is
  capturing and reapplying dev-only grants around each refresh, not a
  clone-time parameter that doesn't exist for this object type.

  PATTERN 2 — Clone-and-swap for zero-downtime changes
  ALTER TABLE <name> SWAP WITH <target_table> atomically exchanges ALL
  content, metadata, constraints, AND grants between two tables in one
  transaction — readers never see a partial or half-swapped state. The
  practical pattern: clone a large table, apply risky changes (backfill,
  restructure, data fix) to the CLONE while the original stays fully live
  and queryable, validate the clone's correctness, then SWAP WITH to
  atomically promote it. The "old" version (now holding the pre-change
  data, just under the other name) can be dropped once you're confident,
  or kept briefly as a rollback option.

  Requirements and restrictions on SWAP WITH:
    - Requires OWNERSHIP privilege on BOTH tables
    - A temporary table can NEVER be swapped with a permanent or
      transient table — table type incompatibility, not a privilege issue
    - Grants transfer WITH the swap automatically — this is different
      from CLONE, where grants need the explicit COPY GRANTS parameter.
      SWAP WITH doesn't need it because it isn't creating a new object at
      all, it's exchanging the identity of two existing ones.

  ── Oracle / SQL Server comparison ─────────────────────────────────────
  Oracle's closest tool is partition exchange (ALTER TABLE ... EXCHANGE
  PARTITION), which atomically swaps a table partition's data with a
  standalone table — same atomic-swap idea, but scoped to a partition
  within a partitioned table, not a true whole-table identity swap. SQL
  Server has no atomic equivalent at all — the closest workaround is a
  three-step rename dance (rename A to a temp name, rename B to A, rename
  temp to B) using sp_rename, which is NOT atomic: there's a real window
  between those steps where neither name maps to the object you'd
  expect. Snowflake's SWAP WITH doing this as one atomic statement,
  including grants, is a meaningfully lower-risk operation for this
  audience to compare against what they're used to.
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
  STEP 1 — Repeatable dev/test schema refresh, and the grants trap
═══════════════════════════════════════════════════════════════════════════*/

-- First run — creates DEV_ECOMMERCE as a clone of RAW. No COPY GRANTS
-- here — CREATE SCHEMA ... CLONE doesn't accept that keyword at all
-- (confirmed live: it's a straight syntax error, not just a no-op)
CREATE OR REPLACE SCHEMA ECOMMERCE.DEV_ECOMMERCE
CLONE ECOMMERCE.RAW
;

-- Child tables' grants replicated automatically from RAW's current
-- state — same mechanism 8.5 STEP 5 confirmed, nothing new here
SHOW GRANTS ON TABLE ECOMMERCE.DEV_ECOMMERCE.ORDERS
;

-- Simulate a developer adding DEV-ONLY access that doesn't exist on the
-- equivalent RAW table — this is the grant that's actually at risk
GRANT SELECT ON TABLE ECOMMERCE.DEV_ECOMMERCE.ORDERS TO ROLE SYSADMIN
;

SHOW GRANTS ON TABLE ECOMMERCE.DEV_ECOMMERCE.ORDERS
;

-- Second run — the actual "nightly refresh"
CREATE OR REPLACE SCHEMA ECOMMERCE.DEV_ECOMMERCE
CLONE ECOMMERCE.RAW
;

-- Expect the dev-only grant added above to be GONE — the refresh
-- re-derives child-table grants fresh from RAW's current state, it does
-- not preserve whatever DEV_ECOMMERCE itself had a moment ago
SHOW GRANTS ON TABLE ECOMMERCE.DEV_ECOMMERCE.ORDERS
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Clone-and-swap: apply a change offline, promote atomically
═══════════════════════════════════════════════════════════════════════════*/

CREATE OR REPLACE TABLE ECOMMERCE.RAW.SWAP_DEMO AS
SELECT *
FROM ECOMMERCE.RAW.ORDERS
LIMIT 500
;

-- Clone it — this is the "offline" copy changes will be applied to,
-- while SWAP_DEMO itself stays live and queryable for anyone else
CREATE OR REPLACE TABLE ECOMMERCE.RAW.SWAP_DEMO_STAGING
CLONE ECOMMERCE.RAW.SWAP_DEMO
;

-- A structural change applied to the STAGING copy only — SWAP_DEMO
-- (the "production" version, in this analogy) is completely unaffected
-- and remains queryable by anyone throughout
ALTER TABLE ECOMMERCE.RAW.SWAP_DEMO_STAGING ADD COLUMN reconciled_flag BOOLEAN DEFAULT FALSE
;

-- Confirm the live table doesn't have the new column yet
DESCRIBE TABLE ECOMMERCE.RAW.SWAP_DEMO
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Promote the change atomically
═══════════════════════════════════════════════════════════════════════════
  Requires OWNERSHIP on both tables. After this, SWAP_DEMO holds the
  NEW structure/data, and SWAP_DEMO_STAGING holds what SWAP_DEMO used to
  contain — the names swap identities, not the reverse.
───────────────────────────────────────────────────────────────────────────*/

ALTER TABLE ECOMMERCE.RAW.SWAP_DEMO SWAP WITH ECOMMERCE.RAW.SWAP_DEMO_STAGING
;

-- Now SWAP_DEMO has the new column — promoted atomically, no maintenance
-- window, and anyone who was querying SWAP_DEMO a moment ago either saw
-- the fully-old or fully-new version, never a half-changed state
DESCRIBE TABLE ECOMMERCE.RAW.SWAP_DEMO
;

-- SWAP_DEMO_STAGING now holds the pre-change data/structure — a
-- built-in rollback option for as long as you choose to keep it around
DESCRIBE TABLE ECOMMERCE.RAW.SWAP_DEMO_STAGING
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Confirm grants transferred automatically with the swap
═══════════════════════════════════════════════════════════════════════════
  Unlike CLONE, SWAP WITH needs no COPY GRANTS parameter — grants are
  part of what gets exchanged, not something left behind by default.
───────────────────────────────────────────────────────────────────────────*/

SHOW GRANTS ON TABLE ECOMMERCE.RAW.SWAP_DEMO
;


/*═══════════════════════════════════════════════════════════════════════════
  CLEANUP
═══════════════════════════════════════════════════════════════════════════*/

DROP SCHEMA IF EXISTS ECOMMERCE.DEV_ECOMMERCE;
DROP TABLE IF EXISTS ECOMMERCE.RAW.SWAP_DEMO;
DROP TABLE IF EXISTS ECOMMERCE.RAW.SWAP_DEMO_STAGING;


/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════
  1. Before dropping anything in CLEANUP, create a VIEW or a STREAM
     against SWAP_DEMO (before running STEP 3's swap). After the swap,
     check whether that view/stream still works correctly, still points
     at the data you expect, or breaks entirely. Downstream objects that
     reference a table by name can behave surprisingly around an
     identity swap — worth confirming directly rather than assuming.

  2. Try ALTER TABLE SWAP WITH using a role that has SELECT but NOT
     OWNERSHIP on one of the two tables. Confirm the specific error and
     compare it to what happens with a role that has OWNERSHIP on
     neither table.

  3. Create a TEMPORARY table and attempt to SWAP WITH a permanent table
     of a compatible structure. Confirm the specific error message this
     produces, and compare against what 8.2's WHAT IF said about
     CREATE OR REPLACE being an atomic drop-and-create — is a rejected
     SWAP attempt "safe" (no partial effect), the same way a failed
     transaction is?
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════
  Q: In STEP 1's refresh, the dev-only grant disappeared after the
     second CLONE. Is there any parameter that would have preserved it?
  A: Not at clone time — no such parameter exists for schemas or
     databases. COPY GRANTS is TABLE/VIEW-only syntax. The only real
     mitigations are procedural: capture SHOW GRANTS on the dev objects
     before each refresh and replay dev-only grants afterward (typically
     via a stored procedure generating dynamic GRANT statements), or
     avoid ad hoc grants on the dev clone altogether and rely on a
     standing ROLE with FUTURE GRANTS configured once against the dev
     schema, which re-applies to every newly (re)cloned object without
     needing to be reapplied per refresh.

  Q: Could I use SWAP WITH instead of CLONE-and-swap to just rename two
     tables around each other for some other reason unrelated to a
     staged change?
  A: Yes — SWAP WITH doesn't know or care that one side was built via
     CLONE. Any two same-database, same-type tables you own can be
     swapped, clone-derived or not.

  Q: Does SWAP WITH consume storage the way CLONE divergence does?
  A: No extra storage is created by the swap itself — it's purely a
     metadata operation exchanging which name points at which existing
     set of micro-partitions. Storage costs from this pattern all come
     from step 2's CLONE and whatever changes were applied to the
     staging copy, same copy-on-write model as 8.5, not from the SWAP
     step itself.

  Q: After SWAP WITH, does Time Travel on SWAP_DEMO show history from
     before the swap (the old SWAP_DEMO_STAGING's history) or history
     from what used to be under the SWAP_DEMO name?
  A: This is genuinely worth testing directly rather than assuming —
     see Practice Gap territory. Object identity and naming interact
     with Time Travel in ways worth confirming live rather than trusting
     intuition here, especially given how much of this goal has already
     turned up behavior that didn't match the reasonable-sounding guess.
───────────────────────────────────────────────────────────────────────────*/
