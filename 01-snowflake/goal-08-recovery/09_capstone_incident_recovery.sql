/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8       : Recover from Mistakes
  Sub-task 8.9 : CAPSTONE — Simulated Incident Recovery
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~50 minutes
  Warehouse size    : X-Small (WORKBOOK_WH)
  Database          : ECOMMERCE
  Run in            : Snowsight
  Prerequisites     : 8.1-8.8 complete
  COF-C03 domain    : 1.0 Snowflake AI Data Cloud Features & Architecture (31%)
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  A single simulated incident, deliberately built to need every technique
  from 8.1-8.7 at once rather than one at a time: a migration script with
  multiple bugs hits two tables in the same run — a bad UPDATE on one, an
  accidental DROP on the other — while the team ALSO wants an independent
  safety snapshot preserved before touching anything further, in case the
  recovery attempt itself goes wrong. Real incidents rarely have exactly
  one thing wrong; this one doesn't either.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT — Recovery technique decision tree
═══════════════════════════════════════════════════════════════════════════
  Before touching the incident itself, the actual decision this capstone
  is teaching: which Goal 8 technique fits which failure mode.

    Data corrupted in place (bad UPDATE/DELETE/MERGE), table stays live
      → Time Travel query + in-place fix (8.1's pattern) if a brief
        window of visibly-wrong data is acceptable
      → Clone-and-swap (8.6 point-in-time clone + 8.7 SWAP WITH) if
        ZERO visible downtime/wrong-data-window matters — this capstone
        uses this path for exactly that reason

    Object gone entirely (DROP, accidental CREATE OR REPLACE)
      → UNDROP (8.2) — restores the object itself, not just its data

    Need an independent, durable reference point BEFORE attempting
    risky remediation (in case the fix itself goes wrong)
      → Point-in-time CLONE (8.6) — creates a real standalone object you
        can fall back to, independent of whether the SOURCE's Time
        Travel window survives whatever happens next

  This capstone hits all three in one incident, in the order a real
  responder would actually encounter them: assess damage, secure a
  reference point, THEN start fixing things — not fix-first-assess-later.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  SETUP — Stand up the two "production" tables the incident will hit
═══════════════════════════════════════════════════════════════════════════
  <table_name> — this capstone assumes a CUSTOMERS table exists in
  ECOMMERCE.RAW alongside ORDERS. Adjust the source table name below if
  the actual table is named differently in this account.
───────────────────────────────────────────────────────────────────────────*/

USE DATABASE ECOMMERCE;
USE SCHEMA RAW;
USE WAREHOUSE WORKBOOK_WH;
USE ROLE SYSADMIN;

CREATE OR REPLACE TABLE ECOMMERCE.RAW.ORDERS_INCIDENT AS
SELECT * FROM ECOMMERCE.RAW.ORDERS LIMIT 1000
;

CREATE OR REPLACE TABLE ECOMMERCE.RAW.CUSTOMERS_INCIDENT AS
SELECT * FROM ECOMMERCE.RAW.CUSTOMERS LIMIT 500
;

-- A grant on ORDERS_INCIDENT, so the clone-and-swap recovery later has
-- something real to confirm survived the swap (same reasoning as 8.7's
-- STEP 4 fix)
GRANT SELECT ON TABLE ECOMMERCE.RAW.ORDERS_INCIDENT TO ROLE PUBLIC
;

-- Baseline, captured before the incident — this is the "last known good"
-- point every recovery step below reaches back to
SELECT CURRENT_TIMESTAMP() AS baseline_timestamp
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS_INCIDENT;
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.CUSTOMERS_INCIDENT;


/*═══════════════════════════════════════════════════════════════════════════
  INCIDENT — The migration script's two bugs
═══════════════════════════════════════════════════════════════════════════
  Bug 1: an UPDATE with a scoping bug corrupts ORDERS_INCIDENT.
  Bug 2: the same script's cleanup step accidentally drops
  CUSTOMERS_INCIDENT instead of a genuinely disposable staging table.
───────────────────────────────────────────────────────────────────────────*/

-- Highlight from BEGIN through COMMIT and run together
BEGIN;

UPDATE ECOMMERCE.RAW.ORDERS_INCIDENT
SET order_status = 'migration_error'
;

-- Used to replace <update_query_id> below — must run BEFORE COMMIT,
-- immediately after the UPDATE (LAST_QUERY_ID ordering, per 8.1/8.6)
SELECT LAST_QUERY_ID() AS update_query_id
;

COMMIT;

-- Bug 2 — the wrong table gets dropped
DROP TABLE ECOMMERCE.RAW.CUSTOMERS_INCIDENT
;

-- Confirm the damage
SELECT order_status, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_INCIDENT
GROUP BY order_status
;

SHOW TABLES LIKE 'CUSTOMERS_INCIDENT' IN SCHEMA ECOMMERCE.RAW
;


/*═══════════════════════════════════════════════════════════════════════════
  RESPONSE STEP 1 — Secure an independent reference point FIRST
═══════════════════════════════════════════════════════════════════════════
  Before attempting any fix, preserve a standalone point-in-time clone of
  ORDERS_INCIDENT as it existed at baseline — a durable fallback that
  survives even if the remediation steps below go wrong, independent of
  ORDERS_INCIDENT's own Time Travel window.
───────────────────────────────────────────────────────────────────────────*/

-- <baseline_timestamp> — replace with the value SETUP returned
CREATE TABLE ECOMMERCE.RAW.ORDERS_INCIDENT_SAFETY_SNAPSHOT
CLONE ECOMMERCE.RAW.ORDERS_INCIDENT
AT(TIMESTAMP => '<baseline_timestamp>'::TIMESTAMP_LTZ)
;

SELECT order_status, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_INCIDENT_SAFETY_SNAPSHOT
GROUP BY order_status
;


/*═══════════════════════════════════════════════════════════════════════════
  RESPONSE STEP 2 — UNDROP the wrongly-dropped table
═══════════════════════════════════════════════════════════════════════════*/

UNDROP TABLE ECOMMERCE.RAW.CUSTOMERS_INCIDENT
;

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.CUSTOMERS_INCIDENT
;


/*═══════════════════════════════════════════════════════════════════════════
  RESPONSE STEP 3 — Clone-and-swap recovery for the corrupted table
═══════════════════════════════════════════════════════════════════════════
  Rather than 8.1's in-place UPDATE-back-to-original approach, this uses
  8.6 + 8.7 combined: build a corrected table via a point-in-time clone,
  validate it independently while ORDERS_INCIDENT stays live and
  queryable throughout, then promote atomically. Zero window where
  anyone querying ORDERS_INCIDENT sees a half-fixed state.
───────────────────────────────────────────────────────────────────────────*/

-- <update_query_id> — replace with the value captured during the INCIDENT
CREATE TABLE ECOMMERCE.RAW.ORDERS_INCIDENT_FIXED
CLONE ECOMMERCE.RAW.ORDERS_INCIDENT
BEFORE(STATEMENT => '<update_query_id>')
;

-- Validate BEFORE promoting — this is the whole point of fixing offline
SELECT order_status, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_INCIDENT_FIXED
GROUP BY order_status
;

-- Promote atomically
ALTER TABLE ECOMMERCE.RAW.ORDERS_INCIDENT SWAP WITH ECOMMERCE.RAW.ORDERS_INCIDENT_FIXED
;

-- Confirm ORDERS_INCIDENT (the name that matters) now holds the
-- corrected data
SELECT order_status, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_INCIDENT
GROUP BY order_status
;

-- Confirm the PUBLIC grant from SETUP survived the swap (8.7's finding
-- holds here too)
SHOW GRANTS ON TABLE ECOMMERCE.RAW.ORDERS_INCIDENT
;


/*═══════════════════════════════════════════════════════════════════════════
  POST-INCIDENT VALIDATION
═══════════════════════════════════════════════════════════════════════════*/

SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS_INCIDENT;
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.CUSTOMERS_INCIDENT;
SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.ORDERS_INCIDENT_SAFETY_SNAPSHOT;

-- ORDERS_INCIDENT_FIXED no longer exists under that name — it IS
-- ORDERS_INCIDENT now, post-swap. What used to be ORDERS_INCIDENT (the
-- corrupted version) is sitting under ORDERS_INCIDENT_FIXED's old name
-- instead. Confirm that's really the corrupted copy before dropping it.
SELECT order_status, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.ORDERS_INCIDENT_FIXED
GROUP BY order_status
;


/*═══════════════════════════════════════════════════════════════════════════
  RETROSPECTIVE
═══════════════════════════════════════════════════════════════════════════
  Technique-to-failure mapping actually used above:
    - ORDERS_INCIDENT (data corruption)  → clone-and-swap (8.6 + 8.7)
    - CUSTOMERS_INCIDENT (wrong DROP)    → UNDROP (8.2)
    - Safety net before touching anything → point-in-time CLONE (8.6)

  What clone-and-swap bought here that 8.1's in-place UPDATE approach
  wouldn't have: ORDERS_INCIDENT was queryable and correct-looking (or
  fully wrong-looking) at every moment — never a state where some rows
  were fixed and others weren't mid-UPDATE. For a small 1,000-row
  sandbox table this barely matters; for a real production table with
  concurrent readers during a live incident, it's the difference between
  a clean recovery and a support ticket about "why did my query return
  inconsistent results for thirty seconds."

  What the safety snapshot bought: if RESPONSE STEP 3's clone-and-swap
  had gone wrong somehow — wrong query ID, corrupted the fix itself —
  ORDERS_INCIDENT_SAFETY_SNAPSHOT was there as a second independent
  fallback that never depended on ORDERS_INCIDENT's own history
  surviving. Belt and suspenders, deliberately.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CLEANUP
═══════════════════════════════════════════════════════════════════════════*/

DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_INCIDENT;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_INCIDENT_FIXED;
DROP TABLE IF EXISTS ECOMMERCE.RAW.ORDERS_INCIDENT_SAFETY_SNAPSHOT;
DROP TABLE IF EXISTS ECOMMERCE.RAW.CUSTOMERS_INCIDENT;


/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════
  1. Rebuild this same incident, but with CUSTOMERS_INCIDENT dropped
     TWICE (drop, undrop, then drop again) before running RESPONSE
     STEP 2. Apply 8.2 STEP 3's technique (SNOWFLAKE.ACCOUNT_USAGE.TABLES
     + IDENTIFIER()) to make sure you're restoring the RIGHT dropped
     version, not just whichever UNDROP would pick by default.

  2. In RESPONSE STEP 3, what would have happened if ORDERS_INCIDENT_FIXED
     had been created with COPY GRANTS instead of relying on SWAP WITH's
     automatic grant transfer? Would the end result actually differ, and
     if not, which approach better fits a scenario where the fix might
     get rejected and never actually promoted?

  3. This capstone's incident hit two SEPARATE tables. Redesign the
     SETUP so both tables live in one SCHEMA that itself gets dropped by
     mistake, then recover using a single schema-level UNDROP (8.2 STEP
     4) instead of two separate table-level recoveries. Under what
     circumstances is the schema-level approach clearly better, and when
     would it be worse (think about what happens if only ONE of the two
     tables actually needed recovery)?
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════
  Q: Why capture the safety snapshot (RESPONSE STEP 1) BEFORE fixing
     anything, instead of just fixing first and taking a snapshot after
     if needed?
  A: Because by the time you'd realize you need it, the moment it needed
     to capture (baseline, pre-incident) may already be harder to reach —
     every additional operation against ORDERS_INCIDENT is another
     query competing for the same Time Travel window, and if something
     unexpected happens during RESPONSE STEP 3, having already secured
     an independent copy means the recovery attempt's own mistakes don't
     threaten your only path back. This mirrors real incident response
     practice broadly: stabilize/preserve evidence before you start
     changing things, not after.

  Q: This whole capstone assumed the DATA_RETENTION_TIME_IN_DAYS window
     was long enough to reach back to baseline_timestamp for every
     recovery step. What if the incident had been discovered days later,
     past a short retention window?
  A: Then RESPONSE STEP 1 and RESPONSE STEP 3 both fail outright — Time
     Travel (and clone-AT/BEFORE, which depends on it) simply can't
     reach data that's already aged out of the retention period. This is
     exactly why 8.3's retention configuration and 8.4's Fail-safe
     matter as prerequisites to this capstone, not unrelated earlier
     sub-tasks: the recovery techniques in this file only work within
     whatever window those settings actually provide, and past that,
     you're into Fail-safe-and-a-support-ticket territory, not
     self-service recovery at all.

  Q: Could this whole incident have been prevented, rather than just
     recovered from well?
  A: Recovery capability and prevention are separate concerns. Goal 4
     (row access policies, RBAC) and disciplined use of BEGIN/COMMIT
     transaction blocks reduce the CHANCE of a scoping bug like the
     UPDATE above reaching production, and requiring peer review on
     migration scripts reduces human error generally. But Goal 8 exists
     precisely because prevention is never 100% — the discipline this
     goal teaches is what happens once prevention has already failed.
───────────────────────────────────────────────────────────────────────────*/
