-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Sub-task 4.1 : RBAC fundamentals
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Goals 1-3 complete
--                    All 10 tables loaded in ECOMMERCE.RAW
--                    10,370,254 rows available
-- COF-C03 domain   : Domain 2.0 — Account Management and Data Governance (20%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Goals 1-3 got the environment built, data loaded, and queries
--   running. None of that matters if the wrong people can see the
--   wrong rows — Goal 4 is where you lock the environment down.
--
--   This sub-task covers Snowflake's Role-Based Access Control
--   (RBAC) model: how roles, users, and privileges relate to each
--   other, and how the built-in system roles are meant to be used.
--   Everything in Goals 4.2 through 4.9 — custom roles, masking,
--   row access policies, network policies — sits on top of the
--   model covered here, so get this one solid first.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: ROLE-BASED ACCESS CONTROL
-- ══════════════════════════════════════════════════════════════
--
-- Every action in Snowflake is evaluated against the ACTIVE ROLE
-- of the current session — not against the user account itself.
-- A user can be granted many roles, but only one is active as the
-- PRIMARY role at a time (set via USE ROLE, or a default at
-- login). Privileges are granted to roles. Roles are granted to
-- users, or to other roles (role hierarchy — covered in Sub-task
-- 4.2). When a role creates an object, that role becomes the
-- object's OWNER, with full control over it.
--
-- Snowflake ships with five system-defined roles:
--
--   ACCOUNTADMIN   top-level role. Combines SYSADMIN and
--                  SECURITYADMIN. Use sparingly — not a daily
--                  driver role.
--   SECURITYADMIN  manages users, roles, and grants account-wide.
--                  Also manages network policies (Sub-task 4.7).
--   USERADMIN      creates and manages users and roles, but
--                  cannot grant privileges on objects such as
--                  warehouses or databases.
--   SYSADMIN       creates warehouses, databases, and other
--                  objects. Typical parent role for the custom
--                  functional roles you build in Sub-task 4.2, and
--                  the role meant to own day-to-day working
--                  objects like ECOMMERCE.
--   PUBLIC         implicit role every user has. Anything granted
--                  to PUBLIC is visible account-wide — avoid
--                  granting anything sensitive here.
--
-- ── Oracle / SQL Server comparison ───────────────────────────
-- Oracle and SQL Server practitioners are used to granting
-- privileges straight to a user, or to a role that is a flat bag
-- of privileges (Oracle's CONNECT, RESOURCE, and DBA roles are a
-- good example). Snowflake's system roles are not a flat bag —
-- each one owns a distinct area of responsibility (security admin,
-- object admin, account admin), and granting object privileges
-- directly to a user is an anti-pattern here, not just a style
-- choice. A user with no granted role can log in but do almost
-- nothing.
--
-- The other shift: Oracle's DBA role can do everything, full
-- stop. Snowflake's ACCOUNTADMIN is powerful, but SYSADMIN cannot
-- manage users and SECURITYADMIN cannot create warehouses — the
-- split is intentional, so no single "do everything" role ends up
-- being anyone's everyday working role.
-- ─────────────────────────────────────────────────────────────
--
-- ── Every container needs USAGE, separately ──────────────────
-- Privileges cascade down an object's OWN hierarchy in some
-- cases, but never up. Querying a table requires USAGE on its
-- database AND USAGE on its schema, IN ADDITION TO the object-
-- level privilege (e.g. SELECT) on the table itself — three
-- separate grants, not one. The same is true of running a query
-- at all: a role also needs its own USAGE grant on a WAREHOUSE,
-- completely separate from database/schema/table access — Step 5
-- and Sub-task 4.2 both depend on this. Oracle practitioners often
-- expect schema and compute access to be implicit once object
-- grants exist; Snowflake does not work that way.
--
-- Ownership works the same way: granting OWNERSHIP on a database
-- transfers ownership of the database container ONLY. It does
-- NOT cascade to the schemas, tables, or warehouses inside or
-- alongside it — each keeps whatever role originally created it
-- until ownership is transferred separately, object by object.
-- SETUP below corrects this for ECOMMERCE and WORKBOOK_WH before
-- the lesson begins.
-- ─────────────────────────────────────────────────────────────
--
-- ── Secondary roles can hide the lesson — and WHY that happens ──
-- By default (DEFAULT_SECONDARY_ROLES = ALL, per Snowflake's
-- BCR-1692 change, rolled out 2024-2025), your session doesn't
-- just use the one role you're actively working as — it silently
-- stacks the privileges of EVERY role your user has ever been
-- granted, all at once. USE ROLE only changes which role owns
-- anything you CREATE; it does not, by itself, narrow which
-- privileges apply when you QUERY something.
--
-- This default exists because it's genuinely convenient for real
-- work — you don't want to be blocked from querying a table just
-- because you switched your "active" role for an unrelated task.
-- But it actively defeats the purpose the moment your goal is to
-- TEST a role in isolation, which is exactly what this workbook
-- keeps doing. If you switch to PUBLIC and ask "what can PUBLIC
-- do on its own?", but your session is still quietly applying
-- every privilege from ACCOUNTADMIN/SYSADMIN/whatever else you
-- hold, then a query succeeding tells you nothing about PUBLIC
-- specifically — it might be succeeding because of a completely
-- different role riding along in the background.
--
-- USE SECONDARY ROLES NONE is how you say "for this one test,
-- strip away every privilege I hold through any OTHER role, and
-- show me only what THIS role can do on its own." It's a testing
-- discipline, not a permanent setting — once you're back to real
-- work rather than testing a role's boundaries, you'd normally
-- leave secondary roles on ALL again.
--
-- Every "prove this role has/doesn't have access" step below runs:
--
--   USE SECONDARY ROLES NONE;
--
-- first. Skipping it is the most common reason an isolation test
-- quietly succeeds when it should fail — not because the role
-- actually has the privilege, but because something else you also
-- hold does.
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

-- Run this sub-task as ACCOUNTADMIN so every system role and
-- grant is visible while you're still learning the model.
-- Sub-task 4.2 moves the daily work under SYSADMIN.
USE ROLE ACCOUNTADMIN;

-- ── ENVIRONMENT FIX (one-time) ───────────────────────────────
-- If Goals 1-3 were built while ACCOUNTADMIN was the active
-- role, ACCOUNTADMIN — not SYSADMIN — owns ECOMMERCE.RAW, its
-- tables, and WORKBOOK_WH, even if SYSADMIN owns the ECOMMERCE
-- database shell. This is common on a fresh workbook environment
-- and is not an error — but Sub-tasks 4.2-4.4 all assume SYSADMIN
-- can work with this data and this warehouse, matching Snowflake's
-- own best practice (SYSADMIN should own working objects;
-- ACCOUNTADMIN is for account admin tasks only).
--
-- REVOKE CURRENT GRANTS is required here: SYSADMIN may already
-- hold an unrelated dependent grant on these objects (e.g. a
-- leftover CREATE FUNCTION grant on the schema) left over from
-- Goal 1/2 setup, and Snowflake blocks an ownership transfer
-- until that's cleared. This convenience clause clears it as
-- part of the same statement. Run this once per environment:

GRANT OWNERSHIP ON SCHEMA ECOMMERCE.RAW TO ROLE SYSADMIN
    REVOKE CURRENT GRANTS;
GRANT OWNERSHIP ON ALL TABLES IN SCHEMA ECOMMERCE.RAW TO ROLE SYSADMIN
    REVOKE CURRENT GRANTS;
GRANT OWNERSHIP ON WAREHOUSE WORKBOOK_WH TO ROLE SYSADMIN
    REVOKE CURRENT GRANTS;

-- Confirm the fix — should show SYSADMIN, not ACCOUNTADMIN
SHOW GRANTS ON TABLE ECOMMERCE.RAW.CUSTOMERS
;
SHOW GRANTS ON WAREHOUSE WORKBOOK_WH
;
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Check your active role
-- ══════════════════════════════════════════════════════════════
-- CURRENT_ROLE() reflects the ACTIVE role for this session only —
-- not every role you've been granted.

SELECT CURRENT_ROLE() AS active_role
;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Inventory the system roles
-- ══════════════════════════════════════════════════════════════
-- SHOW ROLES lists every role in the account. Note the OWNER
-- column — system roles are self-owned or owned by ACCOUNTADMIN,
-- unlike the custom roles built in Sub-task 4.2.

SHOW ROLES
;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: See what a role is actually allowed to do
-- ══════════════════════════════════════════════════════════════
-- SHOW GRANTS TO ROLE is the RBAC equivalent of asking
-- "what can this role actually do." Try it against SYSADMIN
-- first to see how broad the default privilege set is.

SHOW GRANTS TO ROLE SYSADMIN
;

SHOW GRANTS TO ROLE PUBLIC
;

-- ── PUBLIC's grant count is misleading — filter before judging ──
-- SHOW GRANTS TO ROLE PUBLIC can return 100+ rows even on a
-- clean account. Most are Snowflake's own baseline grants (the
-- SNOWFLAKE system database, sample data, etc.) and have nothing
-- to do with your workbook. What matters is whether any touch
-- ECOMMERCE specifically:
--
--   SHOW GRANTS TO ROLE PUBLIC;
--   SELECT *
--   FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
--   WHERE "name" ILIKE '%ECOMMERCE%'
--   ;
--
-- If that returns no rows, PUBLIC has no access to your data —
-- exactly what this sub-task assumes. If it does return rows,
-- someone (maybe you, in an earlier goal) granted access
-- broadly — worth reviewing before Goal 4 is done.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 4: See what roles your user actually holds
-- ══════════════════════════════════════════════════════════════
-- Replace <your_username> with your actual Snowflake username
-- (SnowSQL profile: workbook).

SHOW GRANTS TO USER <your_username>
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Prove that privileges belong to the role, not the user
-- ══════════════════════════════════════════════════════════════
-- Switching to PUBLIC intentionally strips access down to
-- (almost) nothing, even though the user itself hasn't changed.
-- USE SECONDARY ROLES NONE is required here — see CONCEPT above.

USE ROLE PUBLIC;
USE SECONDARY ROLES NONE;

SELECT CURRENT_ROLE() AS active_role
;

-- Expected to fail — PUBLIC has no USAGE on the ECOMMERCE
-- database, so Snowflake can't get far enough to even check
-- table-level SELECT. Expect an error along the lines of:
-- "Database 'ECOMMERCE' does not exist or not authorized."
SELECT COUNT(*) AS customer_count
FROM ECOMMERCE.RAW.CUSTOMERS
;

-- Switch back to a role that can do the work
USE ROLE SYSADMIN;

SELECT CURRENT_ROLE() AS active_role
;

-- Succeeds — SYSADMIN now owns ECOMMERCE.RAW and its tables,
-- per the ENVIRONMENT FIX in SETUP
SELECT COUNT(*) AS customer_count
FROM ECOMMERCE.RAW.CUSTOMERS
;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Grant, test, and revoke — the full round trip
-- ══════════════════════════════════════════════════════════════
-- Using SELECT (non-destructive) so the round trip is safe to
-- run repeatedly. This is DDL, not DML — Snowflake DDL commits
-- immediately and is not covered by BEGIN/COMMIT the way
-- destructive DML is.
--
-- Per CONCEPT above, querying a table needs THREE grants, not
-- one: USAGE on the database, USAGE on the schema, and SELECT on
-- the table itself. All three are granted together below before
-- testing, so the round trip succeeds cleanly on the first try.

USE ROLE ACCOUNTADMIN;

GRANT USAGE ON DATABASE ECOMMERCE TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA ECOMMERCE.RAW TO ROLE PUBLIC;
GRANT SELECT ON TABLE ECOMMERCE.RAW.CUSTOMERS TO ROLE PUBLIC;

SHOW GRANTS ON TABLE ECOMMERCE.RAW.CUSTOMERS
;

-- Confirm the grants work
USE ROLE PUBLIC;
USE SECONDARY ROLES NONE;

SELECT COUNT(*) AS customer_count
FROM ECOMMERCE.RAW.CUSTOMERS
;
-- Succeeds — all three privileges are in place

-- Clean up — revoke everything just granted, in reverse order
USE ROLE ACCOUNTADMIN;

REVOKE SELECT ON TABLE ECOMMERCE.RAW.CUSTOMERS FROM ROLE PUBLIC;
REVOKE USAGE ON SCHEMA ECOMMERCE.RAW FROM ROLE PUBLIC;
REVOKE USAGE ON DATABASE ECOMMERCE FROM ROLE PUBLIC;

-- Confirm the revoke actually removed access
USE ROLE PUBLIC;
USE SECONDARY ROLES NONE;

SELECT COUNT(*) AS customer_count
FROM ECOMMERCE.RAW.CUSTOMERS
;
-- Fails again — same error as Step 5

-- Return to a sane working role before moving on
USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Run SHOW GRANTS TO ROLE for each of ACCOUNTADMIN,
--    SECURITYADMIN, USERADMIN, and SYSADMIN. Write down, in your
--    own words, one thing each role can do that the others
--    cannot.
--
-- 2. As ACCOUNTADMIN, grant USAGE on WORKBOOK_WH to PUBLIC, then
--    (with USE SECONDARY ROLES NONE active) prove as PUBLIC that
--    you can USE WAREHOUSE WORKBOOK_WH but still cannot query
--    CUSTOMERS. This shows that warehouse access and data access
--    are two entirely separate grants — a common trip-up for
--    practitioners used to compute and data privileges being
--    less sharply separated. Revoke it again afterward.
--
-- 3. Grant yourself a second role (or ask whoever administers
--    your account to grant one), then run SHOW GRANTS TO USER
--    again without logging out. Confirm the new role appears
--    immediately.
--
-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I grant a privilege straight to a user instead of
--    to a role?
-- A: Snowflake technically allows GRANT <privilege> ... TO USER,
--    but it's a strong anti-pattern. Direct-to-user grants don't
--    show up cleanly in role-based grant reviews and don't
--    compose with the role hierarchy built in Sub-task 4.2.
--    Grant to role, then grant role to user — always.
--
-- Q: What if my active role has SELECT on a table but the query
--    still fails?
-- A: Check USAGE on the database and schema — see CONCEPT and
--    Step 6 above. Missing either one fails with a container-
--    level error ("Database does not exist or not authorized")
--    even though the real problem is one level up from the table.
--
-- Q: What if a role I switch to still seems to have more access
--    than it should?
-- A: Check secondary roles — see CONCEPT above. Run
--    USE SECONDARY ROLES NONE to test a role in true isolation.
--
-- Q: What if GRANT OWNERSHIP ON DATABASE (or SCHEMA) doesn't fix
--    a "not authorized" error on an object inside it?
-- A: Ownership does not cascade from database to schema to table,
--    or from a database to warehouses that live alongside it.
--    Transfer ownership at the level where the object actually
--    lives — SETUP above does this explicitly for the schema, its
--    tables, and the warehouse, as three separate statements.
--
-- Q: What if a GRANT OWNERSHIP statement fails with something
--    like "Dependent grant of privilege ... exists. It must be
--    revoked first"?
-- A: The new owning role already holds some other privilege on
--    that object (e.g. CREATE FUNCTION on a schema) that conflicts
--    with taking ownership. Add REVOKE CURRENT GRANTS to the same
--    GRANT OWNERSHIP statement — SETUP above uses this by default
--    for exactly this reason, since it's common on environments
--    that were built up over several earlier goals.
--
-- Q: What if I'm logged in as ACCOUNTADMIN and something goes
--    wrong?
-- A: ACCOUNTADMIN combines SYSADMIN and SECURITYADMIN, so
--    mistakes here have the largest blast radius in the account.
--    Use it only for the specific admin actions that require it
--    (Step 6 above), then switch back to a narrower role
--    immediately — exactly what Step 6 does at the end.
--
-- Q: What is different from Oracle I should watch for in this
--    sub-task specifically?
-- A: Key differences:
--    · No single "DBA does everything" role — responsibilities
--      are split across ACCOUNTADMIN / SECURITYADMIN / SYSADMIN
--    · Privileges never attach to a user directly in practice
--    · USAGE is a distinct, required privilege on databases,
--      schemas, AND warehouses — not implied by object-level
--      grants or by having used the object once already
--    · Ownership does not cascade down a container hierarchy the
--      way some Oracle privilege inheritance might suggest
--    · Secondary roles have no direct Oracle/SQL Server
--      equivalent — nearest comparison is granting a user
--      multiple roles all active at once, rather than requiring
--      an explicit role switch
-- ══════════════════════════════════════════════════════════════
