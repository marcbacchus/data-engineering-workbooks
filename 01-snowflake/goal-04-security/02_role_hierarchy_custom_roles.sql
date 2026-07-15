-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Sub-task 4.2 : Role hierarchy and custom roles
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~30 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Sub-task 4.1 complete
--                    SYSADMIN owns ECOMMERCE.RAW, its tables, and
--                    WORKBOOK_WH (fixed in Sub-task 4.1 SETUP)
-- COF-C03 domain   : Domain 4 — Data Governance and Security (23%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Sub-task 4.1 covered the system roles Snowflake ships with.
--   Real environments need more than that — you need roles that
--   map to actual jobs (analyst, engineer, auditor) without
--   handing anyone SYSADMIN just to let them query a table.
--
--   This sub-task builds your first custom roles and wires them
--   into a hierarchy under SYSADMIN. The pattern established here
--   — access roles separated from functional roles — is what
--   Sub-tasks 4.4 through 4.6 (masking, row access, tags) attach
--   their policies to, so the shape you build now matters later.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: ROLE HIERARCHY AND ROLE TYPES
-- ══════════════════════════════════════════════════════════════
--
-- A role can be granted to another role, not just to a user. This
-- creates a HIERARCHY: the parent role inherits every privilege
-- of every role beneath it. Snowflake's recommended pattern splits
-- custom roles into two types:
--
--   ACCESS ROLE      owns object privileges only (USAGE, SELECT,
--                     INSERT, etc. on specific databases, schemas,
--                     tables, warehouses). Never granted to a user
--                     directly. Named after WHAT it can touch.
--                     e.g. ECOMMERCE_READ
--
--   FUNCTIONAL ROLE   owns no object privileges of its own. Holds
--                     one or more access roles, and IS granted to
--                     users. Named after WHO holds it / what job
--                     it represents.
--                     e.g. DATA_ANALYST, DATA_ENGINEER
--
-- The hierarchy for this sub-task:
--
--   SYSADMIN
--     └── DATA_ANALYST        (functional role -> granted to users)
--           └── ECOMMERCE_READ   (access role -> holds privileges)
--
-- Granting the functional role up to SYSADMIN is deliberate: it
-- keeps every custom role visible to whoever administers the
-- account under SYSADMIN, rather than becoming an orphan branch
-- nobody with broad access can see or audit.
--
-- ── Oracle / SQL Server comparison ───────────────────────────
-- Oracle does support granting one role to another, so role
-- composition itself isn't new to Oracle practitioners. What's
-- different is that Snowflake treats the access-role/functional-
-- role split as the expected pattern, not an optional design
-- choice — Snowflake's own documentation and certification exam
-- assume you separate "what a role can touch" from "who holds
-- it." A flat role that mixes both (common in Oracle shops) works
-- technically but becomes hard to audit as it grows.
-- ─────────────────────────────────────────────────────────────
--
-- ── Who can create roles ──────────────────────────────────────
-- CREATE ROLE requires the USERADMIN privilege set (or higher).
-- SECURITYADMIN inherits USERADMIN, so either can create roles.
-- This sub-task uses SECURITYADMIN throughout, since it also
-- needs to grant roles to other roles and to users — USERADMIN
-- alone can create roles but has more limited grant authority.
-- ─────────────────────────────────────────────────────────────
--
-- ── Warehouse access is its own grant ────────────────────────
-- USAGE on a warehouse is a completely separate privilege from
-- USAGE on a database or schema — nothing about querying data
-- implies compute access. A functional role can inherit SELECT
-- on every table in ECOMMERCE and still fail every query with "no
-- warehouse" until its access role is also granted USAGE on
-- WORKBOOK_WH directly. Step 3 below grants this alongside the
-- data privileges, for exactly this reason.
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
USE ROLE SECURITYADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Create the access role
-- ══════════════════════════════════════════════════════════════
-- The access role holds privileges only. It is never granted
-- directly to a user.

CREATE ROLE IF NOT EXISTS ECOMMERCE_READ
    COMMENT = 'Access role: read-only privileges on ECOMMERCE.RAW';

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create the functional role
-- ══════════════════════════════════════════════════════════════
-- The functional role holds no privileges of its own yet — it
-- will hold the access role instead, and it IS what gets granted
-- to users.

CREATE ROLE IF NOT EXISTS DATA_ANALYST
    COMMENT = 'Functional role: general analyst, granted to users';

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Grant object and warehouse privileges to the access role
-- ══════════════════════════════════════════════════════════════
-- Per Sub-task 4.1's CONCEPT: querying a table needs USAGE on the
-- database, USAGE on the schema, and SELECT on the table itself
-- — all three, granted here to the access role, not to a user or
-- the functional role directly. Warehouse USAGE is a fourth,
-- separate grant — easy to forget since a warehouse was already
-- active in this session, but that has nothing to do with
-- whether DATA_ANALYST itself can use it.
--
-- SECURITYADMIN does not itself hold these privileges on
-- ECOMMERCE or WORKBOOK_WH, so switch to SYSADMIN (the owner) to
-- grant them.

USE ROLE SYSADMIN;

GRANT USAGE  ON DATABASE ECOMMERCE            TO ROLE ECOMMERCE_READ;
GRANT USAGE  ON SCHEMA   ECOMMERCE.RAW        TO ROLE ECOMMERCE_READ;
GRANT SELECT ON ALL TABLES IN SCHEMA ECOMMERCE.RAW TO ROLE ECOMMERCE_READ;
GRANT USAGE  ON WAREHOUSE WORKBOOK_WH         TO ROLE ECOMMERCE_READ;

-- ── ALL TABLES vs. FUTURE TABLES ─────────────────────────────
-- GRANT ... ON ALL TABLES IN SCHEMA only covers tables that exist
-- right now. A table added next week would NOT be covered. Future
-- grants (ON FUTURE TABLES) are covered in Sub-task 4.3 — for
-- this sub-task, ALL TABLES is sufficient since Goal 2 already
-- loaded all 10 tables.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Build the hierarchy — grant role to role
-- ══════════════════════════════════════════════════════════════
-- Role-to-role grants are managed by SECURITYADMIN, not SYSADMIN.

USE ROLE SECURITYADMIN;

-- Access role becomes a child of the functional role
GRANT ROLE ECOMMERCE_READ TO ROLE DATA_ANALYST;

-- Functional role becomes a child of SYSADMIN, for visibility
GRANT ROLE DATA_ANALYST TO ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Grant the functional role to your user and test it
-- ══════════════════════════════════════════════════════════════
-- Replace <your_username> with your actual Snowflake username.

GRANT ROLE DATA_ANALYST TO USER <your_username>;

-- Switch to the new role and confirm isolation, per Sub-task
-- 4.1's secondary-roles lesson.
USE ROLE DATA_ANALYST;
USE SECONDARY ROLES NONE;

SELECT CURRENT_ROLE() AS active_role
;

-- Succeeds — DATA_ANALYST inherits both the data privileges AND
-- the warehouse USAGE from ECOMMERCE_READ through the hierarchy,
-- even though DATA_ANALYST itself holds no direct grants
SELECT COUNT(*) AS customer_count
FROM ECOMMERCE.RAW.CUSTOMERS
;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Inspect the hierarchy two different ways
-- ══════════════════════════════════════════════════════════════
-- SHOW GRANTS TO ROLE and SHOW GRANTS OF ROLE answer different
-- questions — easy to mix up, and both are exam-relevant. Both
-- commands return columns with the SAME names (granted_to,
-- grantee_name, granted_by) — the column names don't tell them
-- apart. What differs is what grantee_name MEANS in each.

USE ROLE SECURITYADMIN;

--TO -> "What does DATA_ANALYST hold?" (its own privileges/roles)
-- grantee_name is always DATA_ANALYST; rows show what it holds
-- (e.g. ECOMMERCE_READ as a granted role).
SHOW GRANTS TO ROLE DATA_ANALYST
;

--OF -> "Who holds DATA_ANALYST?" (users/roles above it)
-- grantee_name is whoever HOLDS DATA_ANALYST — your user, and
-- SYSADMIN as the parent role.
SHOW GRANTS OF ROLE DATA_ANALYST
;

-- ── TO vs OF — same-looking columns, opposite direction ──────
-- Both commands return columns named granted_to, grantee_name,
-- and granted_by — the column names alone don't distinguish them.
--   SHOW GRANTS TO ROLE X  -> grantee_name is always X itself;
--                             rows show what X holds
--   SHOW GRANTS OF ROLE X  -> grantee_name is whoever HOLDS X
--                             (a user, or a parent role)
-- ─────────────────────────────────────────────────────────────

-- Return to a sane working role before moving on
USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a second access role, ECOMMERCE_WRITE, with INSERT
--    and UPDATE (not DELETE) on all tables in ECOMMERCE.RAW, plus
--    USAGE on WORKBOOK_WH. Create a second functional role,
--    DATA_ENGINEER, that holds BOTH ECOMMERCE_READ and
--    ECOMMERCE_WRITE. Grant DATA_ENGINEER to SYSADMIN for
--    visibility, same as DATA_ANALYST.
--
-- 2. With DATA_ANALYST active and USE SECONDARY ROLES NONE set,
--    attempt an INSERT into ECOMMERCE.RAW.CUSTOMERS. Confirm it
--    fails — DATA_ANALYST only inherited ECOMMERCE_READ, not
--    ECOMMERCE_WRITE, even though both roles ultimately roll up
--    to SYSADMIN.
--
-- 3. Run SHOW GRANTS OF ROLE ECOMMERCE_READ. Notice it now shows
--    TWO parent roles if you completed exercise 1 (DATA_ANALYST
--    from this sub-task, plus anything else you granted it to).
--    This is the practical reason access roles are named after
--    what they touch — a single access role is meant to be reused
--    across multiple functional roles.
--
-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I grant the access role directly to a user instead
--    of routing it through a functional role?
-- A: It works technically, but defeats the point of the split.
--    The functional role is what should appear in SHOW GRANTS TO
--    USER — a clean, job-shaped list ("this person is a
--    DATA_ANALYST"), not a pile of access-role plumbing details
--    every admin has to decode later.
--
-- Q: What if I don't grant the functional role up to SYSADMIN?
-- A: The role still works for the user it's granted to, but
--    becomes invisible to anyone auditing from SYSADMIN down —
--    SHOW GRANTS OF ROLE from SYSADMIN's perspective won't surface
--    it. Orphaned custom roles like this are a common audit
--    finding in real Snowflake accounts.
--
-- Q: What if a functional role has SELECT on every table it needs
--    but every query still fails?
-- A: Check warehouse USAGE specifically. It's easy to assume a
--    role that "has data access" can run queries, but warehouse
--    access is a fourth, independent grant — see CONCEPT and
--    Step 3 above.
--
-- Q: What if I try to grant a role to itself, or create a
--    circular hierarchy (A granted to B, B granted to A)?
-- A: Snowflake rejects this with a compilation error — role
--    hierarchies must be a directed acyclic graph (DAG), same
--    constraint as most permission-inheritance systems.
--
-- Q: What if DATA_ANALYST is active but I actually need
--    DATA_ENGINEER's privileges too?
-- A: Either switch primary role with USE ROLE DATA_ENGINEER, or
--    leave secondary roles enabled (the account default, per
--    Sub-task 4.1) so both apply at once. Which is correct
--    depends on whether you want isolation (testing, least
--    privilege) or convenience (daily work) — this workbook uses
--    USE SECONDARY ROLES NONE specifically to force isolation
--    during testing.
--
-- Q: What is different from Oracle I should watch for in this
--    sub-task specifically?
-- A: Key differences:
--    · The access-role/functional-role split is the documented,
--      exam-tested convention here — not just a nice-to-have
--    · GRANT ROLE ... TO ROLE requires SECURITYADMIN (or USERADMIN
--      for role creation), a different role than the one that
--      grants object privileges (SYSADMIN, or the object owner)
--    · SHOW GRANTS TO ROLE vs SHOW GRANTS OF ROLE is a distinction
--      Oracle's role/privilege views don't split the same way
-- ══════════════════════════════════════════════════════════════
