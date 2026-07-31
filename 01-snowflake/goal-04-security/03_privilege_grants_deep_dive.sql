-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Sub-task 4.3 : Privilege grants deep dive
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~40 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Sub-tasks 4.1-4.2 complete
--                    ECOMMERCE_READ access role and DATA_ANALYST
--                    functional role exist (Sub-task 4.2)
-- COF-C03 domain   : Domain 2.0 — Account Management and Data Governance (20%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Sub-task 4.2 built the access-role/functional-role pattern
--   using a single privilege — SELECT. Real environments need
--   more than read access, and more than one way to hand it out:
--   multiple privileges at once, privileges that can themselves
--   be re-granted, and privileges that apply automatically to
--   objects that don't exist yet.
--
--   This sub-task covers all three, plus the precedence rules
--   that decide which grant wins when more than one could apply.
--   Sub-tasks 4.4 through 4.6 (masking, row access, tags) all
--   assume you're comfortable with future grants specifically —
--   policies need to attach to tables that get added later, not
--   just the ones that exist today.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: PRIVILEGE TYPES, GRANT OPTION, AND FUTURE GRANTS
-- ══════════════════════════════════════════════════════════════
--
-- Common privileges by object type:
--
--   TABLE      SELECT, INSERT, UPDATE, DELETE, TRUNCATE,
--              REFERENCES
--   SCHEMA     USAGE, CREATE TABLE, CREATE VIEW, MODIFY, MONITOR
--   DATABASE   USAGE, CREATE SCHEMA, MONITOR
--   WAREHOUSE  USAGE, OPERATE, MONITOR, MODIFY
--
-- ALL PRIVILEGES is a pseudo-privilege — shorthand that expands
-- to every applicable privilege for that object type EXCEPT
-- OWNERSHIP, which must always be transferred explicitly via
-- GRANT OWNERSHIP (Sub-task 4.1).
--
-- WITH GRANT OPTION lets the grantee re-grant the same privilege
-- to other roles — the grantee becomes a grantor. This is powerful
-- and easy to get wrong: if that re-granted ("dependent") privilege
-- still exists, Snowflake REFUSES to revoke the original grant
-- unless you explicitly add CASCADE. Without CASCADE, the revoke
-- fails outright — nothing is changed, not even partially. With
-- CASCADE, the original grant AND every dependent grant it enabled
-- are revoked together, in one statement. Step 3 below shows both
-- outcomes side by side.
--
-- FUTURE GRANTS apply a privilege automatically to objects of a
-- given type CREATED AFTER the future grant is issued, within a
-- database or schema. They do NOT apply retroactively to objects
-- that already exist — Sub-task 4.2 used ALL TABLES for exactly
-- this reason, since Goal 2's tables already existed.
--
-- PRECEDENCE: when future grants exist at both the database level
-- and the schema level for the same object type, the SCHEMA-level
-- future grant wins and the database-level one is ignored for that
-- schema. This is a real gotcha — a broad database-level future
-- grant can be silently overridden by a narrower schema-level one
-- nobody remembers setting.
--
-- ── MANAGE GRANTS: who can actually issue a future grant ──────
-- GRANT/REVOKE ... ON FUTURE ... requires the global MANAGE GRANTS
-- privilege, held only by ACCOUNTADMIN and SECURITYADMIN by
-- default — the same restriction pattern as APPLY MASKING POLICY
-- in Sub-task 4.4. SYSADMIN, even as the owner of ECOMMERCE, CANNOT
-- run a future grant statement directly. Every future-grant
-- statement in this sub-task switches to SECURITYADMIN first, then
-- switches back to SYSADMIN for everything else (creating objects,
-- non-future grants, testing) — that back-and-forth is a real
-- rhythm to get used to, not a one-off workaround.
-- ─────────────────────────────────────────────────────────────
--
-- ── Oracle / SQL Server comparison ───────────────────────────
-- Oracle's WITH ADMIN OPTION is the closest equivalent to
-- Snowflake's WITH GRANT OPTION — both let a grantee re-grant
-- what they hold. Oracle's ANY privileges (SELECT ANY TABLE,
-- CREATE ANY TABLE) are the nearest cousin to Snowflake's ALL
-- PRIVILEGES pseudo-grant, but ANY privileges in Oracle apply
-- account-wide across every schema, whereas Snowflake's ALL
-- PRIVILEGES is still scoped to the one object you named. Oracle
-- has no direct equivalent to Snowflake's future grants — the
-- closest analog is a trigger-based or IAM-policy workaround,
-- not a first-class grant feature.
-- ─────────────────────────────────────────────────────────────
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: See the full privilege list on a live object
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;

SHOW GRANTS ON TABLE ECOMMERCE.RAW.CUSTOMERS
;
-- Compare the privilege column here against the TABLE list in
-- CONCEPT above — SELECT is the only one granted so far, from
-- Sub-task 4.2.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Grant multiple privileges at once, and ALL PRIVILEGES
-- ══════════════════════════════════════════════════════════════
-- Building a write-capable access role, parallel to Sub-task
-- 4.2's ECOMMERCE_READ. Multiple privileges can be comma-
-- separated in a single GRANT statement.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS ECOMMERCE_WRITE
    COMMENT = 'Access role: write privileges on ECOMMERCE.RAW';

CREATE ROLE IF NOT EXISTS DATA_ENGINEER
    COMMENT = 'Functional role: data engineer, granted to users';

USE ROLE SYSADMIN;

GRANT USAGE ON DATABASE ECOMMERCE     TO ROLE ECOMMERCE_WRITE;
GRANT USAGE ON SCHEMA   ECOMMERCE.RAW TO ROLE ECOMMERCE_WRITE;
GRANT USAGE ON WAREHOUSE WORKBOOK_WH  TO ROLE ECOMMERCE_WRITE;

-- Multiple privileges, one statement — deliberately omitting
-- DELETE and TRUNCATE for this access role
GRANT INSERT, UPDATE ON ALL TABLES IN SCHEMA ECOMMERCE.RAW
    TO ROLE ECOMMERCE_WRITE;

USE ROLE SECURITYADMIN;

GRANT ROLE ECOMMERCE_WRITE TO ROLE DATA_ENGINEER;
GRANT ROLE DATA_ENGINEER   TO ROLE SYSADMIN;

-- Confirm the exact privilege set — should show USAGE (warehouse),
-- INSERT, and UPDATE, never ALL PRIVILEGES unless you asked for it
SHOW GRANTS TO ROLE ECOMMERCE_WRITE
;

-- ── ALL PRIVILEGES, for comparison — not run against CUSTOMERS ──
-- GRANT ALL PRIVILEGES ON TABLE ECOMMERCE.RAW.CUSTOMERS
--     TO ROLE ECOMMERCE_WRITE;
-- This would add SELECT, INSERT, UPDATE, DELETE, TRUNCATE, and
-- REFERENCES in one statement — broader than intended here.
-- Left commented out deliberately: naming exact privileges is
-- the safer default, and ALL PRIVILEGES is easy to grant by
-- habit without meaning to include DELETE.
-- ─────────────────────────────────────────────────────────────

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: WITH GRANT OPTION, and why REVOKE needs CASCADE
-- ══════════════════════════════════════════════════════════════

-- Grant SELECT to ECOMMERCE_READ, allowing it to re-grant SELECT
-- to other roles itself
USE ROLE SYSADMIN;
GRANT SELECT ON TABLE ECOMMERCE.RAW.PRODUCTS TO ROLE ECOMMERCE_READ WITH GRANT OPTION;


-- Acting as a role that now HOLDS grant option, re-grant the
-- same privilege downstream to DATA_ENGINEER
USE ROLE ECOMMERCE_READ;
USE SECONDARY ROLES NONE;

GRANT SELECT ON TABLE ECOMMERCE.RAW.PRODUCTS TO ROLE DATA_ENGINEER;

-- Confirm DATA_ENGINEER now has SELECT on PRODUCTS, granted_by
-- ECOMMERCE_READ rather than SYSADMIN
USE ROLE SYSADMIN;

SHOW GRANTS ON TABLE ECOMMERCE.RAW.PRODUCTS
;

-- Attempt to revoke the ORIGINAL grant from ECOMMERCE_READ,
-- WITHOUT CASCADE. Expected to FAIL — DATA_ENGINEER's grant is
-- "dependent" on this one (it was re-granted using the grant
-- option ECOMMERCE_READ held), and Snowflake refuses to revoke a
-- grant that has dependents unless you explicitly say what to do
-- about them. This is a safety feature, not a bug: without it,
-- REVOKE could silently strand a downstream grant with no
-- remaining record of where it came from.
USE ROLE SYSADMIN;
REVOKE SELECT ON TABLE ECOMMERCE.RAW.PRODUCTS FROM ROLE ECOMMERCE_READ;
-- Error: "Revoke partially executed: 0 grant(s) revoked, 1
-- grant(s) skipped due to dependent grants and no CASCADE is
-- specified." Nothing changed — the revoke did not partially
-- apply, it did not apply at all.

-- Confirm nothing changed — both grants are still present
SHOW GRANTS ON TABLE ECOMMERCE.RAW.PRODUCTS
;

-- Retry WITH CASCADE — this revokes the original grant AND
-- recursively revokes the dependent grant it enabled, in the
-- SAME statement. There is no separate cleanup step needed
-- afterward; CASCADE handles both in one shot.
REVOKE SELECT ON TABLE ECOMMERCE.RAW.PRODUCTS FROM ROLE ECOMMERCE_READ
    CASCADE;

-- Confirm BOTH grants are gone now — ECOMMERCE_READ's grant and
-- DATA_ENGINEER's downstream copy
SHOW GRANTS ON TABLE ECOMMERCE.RAW.PRODUCTS
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Future grants — privileges that apply automatically
-- ══════════════════════════════════════════════════════════════
-- A dedicated schema keeps this test isolated from the 10
-- production tables in ECOMMERCE.RAW.

CREATE SCHEMA IF NOT EXISTS ECOMMERCE.SANDBOX
    COMMENT = 'Sandbox schema for Sub-task 4.3 future grants testing';

GRANT USAGE ON SCHEMA ECOMMERCE.SANDBOX TO ROLE ECOMMERCE_READ;

-- Future grant: applies to tables created AFTER this statement,
-- not to anything that exists right now (SANDBOX is empty anyway)
-- Requires MANAGE GRANTS — switch to SECURITYADMIN for this one
-- statement, per CONCEPT above.
USE ROLE SECURITYADMIN;

GRANT SELECT ON FUTURE TABLES IN SCHEMA ECOMMERCE.SANDBOX
    TO ROLE ECOMMERCE_READ;

-- Switch back to SYSADMIN to actually create objects
USE ROLE SYSADMIN;

-- Create a brand-new table — no SELECT grant issued for it
-- individually, anywhere in this file
CREATE OR REPLACE TABLE ECOMMERCE.SANDBOX.FUTURE_GRANT_TEST (
    test_id INT,
    test_value VARCHAR
);

INSERT INTO ECOMMERCE.SANDBOX.FUTURE_GRANT_TEST VALUES (1, 'sample row');

-- Test as DATA_ANALYST (holds ECOMMERCE_READ via Sub-task 4.2)
USE ROLE DATA_ANALYST;
USE SECONDARY ROLES NONE;

-- Succeeds — the future grant applied automatically at creation
SELECT * FROM ECOMMERCE.SANDBOX.FUTURE_GRANT_TEST
;

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Precedence — schema-level future grants beat
--         database-level future grants
-- ══════════════════════════════════════════════════════════════
-- A broad database-level future grant can be silently overridden
-- for one schema by a narrower schema-level future grant, even if
-- the schema-level grant was added afterward. Both statements
-- below need MANAGE GRANTS — switch to SECURITYADMIN for both,
-- then switch back to SYSADMIN to create the test table.

USE ROLE SECURITYADMIN;

-- Broad, database-level future grant (deliberately not scoped)
GRANT SELECT ON FUTURE TABLES IN DATABASE ECOMMERCE
    TO ROLE ECOMMERCE_WRITE;

-- Narrower, schema-level future grant on SANDBOX specifically —
-- this one wins for any future table created in SANDBOX
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA ECOMMERCE.SANDBOX
    TO ROLE ECOMMERCE_WRITE;

-- Switch back to SYSADMIN to create the table
USE ROLE SYSADMIN;

CREATE OR REPLACE TABLE ECOMMERCE.SANDBOX.PRECEDENCE_TEST (
    test_id INT
);

-- Confirm which future grant actually applied to the new table —
-- expect SELECT and INSERT (the schema-level grant), not just
-- the SELECT from the database-level grant
SHOW GRANTS ON TABLE ECOMMERCE.SANDBOX.PRECEDENCE_TEST
;

-- Clean up the sandbox future grants so they don't affect later
-- sub-tasks — REVOKE ... ON FUTURE also requires MANAGE GRANTS
USE ROLE SECURITYADMIN;

REVOKE SELECT ON FUTURE TABLES IN DATABASE ECOMMERCE FROM ROLE ECOMMERCE_WRITE;
REVOKE SELECT, INSERT ON FUTURE TABLES IN SCHEMA ECOMMERCE.SANDBOX FROM ROLE ECOMMERCE_WRITE;

-- Switch back to SYSADMIN before continuing
USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Clean up the sandbox schema
-- ══════════════════════════════════════════════════════════════
-- Drop the whole schema rather than dropping tables one at a
-- time — this also removes the schema-level grants issued to it.

DROP SCHEMA IF EXISTS ECOMMERCE.SANDBOX;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Grant SELECT WITH GRANT OPTION on ORDERS to DATA_ANALYST
--    directly (not the access role). Re-grant it from DATA_ANALYST
--    to a brand-new role of your own naming. Try to revoke the
--    original grant from DATA_ANALYST WITHOUT CASCADE and confirm
--    — as in Step 3 — that it fails outright. Then retry WITH
--    CASCADE and confirm both grants are gone in one statement.
--
-- 2. Recreate the sandbox schema, then (as SECURITYADMIN) set up a
--    database-level future grant and a schema-level future grant
--    for FUTURE VIEWS (not tables) with different privilege sets.
--    Switch back to SYSADMIN, create a view, and confirm which
--    future grant's privileges actually landed on it.
--
-- 3. Run GRANT ALL PRIVILEGES ON TABLE ECOMMERCE.RAW.PRODUCT_REVIEWS
--    TO ROLE ECOMMERCE_READ, then SHOW GRANTS ON TABLE for it.
--    Confirm OWNERSHIP is NOT among the privileges granted, even
--    though ALL PRIVILEGES was used — matching CONCEPT above.
--    Revoke ALL PRIVILEGES afterward to leave ECOMMERCE_READ as a
--    read-only role.
--
-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I revoke a privilege from a role that re-granted it
--    downstream with WITH GRANT OPTION?
-- A: The plain REVOKE fails outright — see Step 3. Snowflake
--    returns "Revoke partially executed: 0 grant(s) revoked ...
--    due to dependent grants and no CASCADE is specified" and
--    changes nothing. Add CASCADE to the REVOKE statement to
--    remove the original grant AND every dependent grant it
--    enabled, all in the same statement — there is no separate
--    cleanup step needed once CASCADE is used.
--
-- Q: What if GRANT/REVOKE ... ON FUTURE fails with something like
--    "Your primary role SYSADMIN must have MANAGE GRANTS"?
-- A: Expected — future grants require the global MANAGE GRANTS
--    privilege, which only ACCOUNTADMIN and SECURITYADMIN hold by
--    default, regardless of what SYSADMIN owns. Switch to
--    SECURITYADMIN for that one statement, then switch back to
--    SYSADMIN — Steps 4 and 5 above do this every time a future
--    grant is issued or revoked.
--
-- Q: What if I grant a future privilege at the database level and
--    it doesn't seem to apply to a new table in a specific schema?
-- A: Check for a schema-level future grant on the same object
--    type in that schema — it silently wins over the database-
--    level grant, per CONCEPT and Step 5 above.
--
-- Q: What if I need a future grant to apply to objects that
--    already exist too?
-- A: It won't, retroactively. Combine a future grant (for new
--    objects going forward) with an ALL TABLES / ALL VIEWS style
--    grant (for what exists right now) — Sub-task 4.2 used this
--    exact combination.
--
-- Q: What if ALL PRIVILEGES doesn't give a role everything I
--    expected?
-- A: ALL PRIVILEGES excludes OWNERSHIP by design — Practice Gap
--    exercise 3 confirms this directly. OWNERSHIP must always be
--    transferred with GRANT OWNERSHIP, never bundled into a
--    broader grant.
--
-- Q: What is different from Oracle I should watch for in this
--    sub-task specifically?
-- A: Key differences:
--    · WITH GRANT OPTION (Snowflake) vs WITH ADMIN OPTION
--      (Oracle) — same idea, different keyword
--    · Oracle's ANY privileges are account-wide; Snowflake's ALL
--      PRIVILEGES stays scoped to the object you named
--    · Future grants have no first-class Oracle equivalent —
--      Oracle privilege management is inherently retroactive-only
--      without custom tooling
--    · MANAGE GRANTS as a gatekeeper for future grants has no
--      direct Oracle parallel — Oracle privilege administration
--      doesn't split "grant this privilege" from "grant this
--      privilege on objects that don't exist yet" the way
--      Snowflake does
-- ══════════════════════════════════════════════════════════════
