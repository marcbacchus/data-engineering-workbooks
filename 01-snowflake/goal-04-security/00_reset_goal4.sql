-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Utility : Reset script — undoes Goal 4's sub-tasks
-- ──────────────────────────────────────────────────────────────
-- Purpose : Returns the environment to its pre-Goal-4 state so any
--           or all of Goal 4's sub-task files can be retested from
--           a clean starting point. Does NOT touch Goals 1-3
--           objects (ECOMMERCE database, its 10 tables' DATA, or
--           WORKBOOK_WH itself) — only the roles, grants, and
--           policies Goal 4 added on top of them.
--
-- ⚠ DESTRUCTIVE — drops custom roles and unsets/drops policies.
--   Only run this if you intend to redo Goal 4 from scratch. Do
--   not run mid-goal, or you'll lose roles/policies later
--   sub-tasks depend on.
--
-- Run this ONCE, top to bottom, as ACCOUNTADMIN, before re-running
-- any Goal 4 sub-task files.
--
-- COVERAGE: Sub-tasks 4.1-4.9 (RBAC, role hierarchy, privilege
-- grants, masking, row access policies, tag-based governance,
-- network policies, secure views, capstone). As later material is
-- added, extend this script to match.
--
-- NOTE ON THE CAPSTONE (4.9): the capstone permanently upgrades
-- EMAIL_MASK, PHONE_MASK, NAME_MASK, and REGION_ACCESS_POLICY to
-- use IS_ROLE_IN_SESSION() instead of CURRENT_ROLE(). This script
-- DROPS those policy objects entirely (Steps 4-5 below) rather
-- than trying to revert their bodies — re-running Sub-tasks 4.4/
-- 4.5 fresh naturally recreates them with their original
-- CURRENT_ROLE()-based bodies, so no separate "undo the capstone"
-- step is needed.
--
-- ORDER MATTERS: objects are torn down in dependency order — a
-- policy/tag must be detached from columns and tables before it
-- can be dropped, a view must be dropped before the role that owns
-- it, and every object a role OWNS must be dropped or reassigned
-- before that role itself can be dropped. This script follows:
-- unset/detach -> drop views -> drop policies & tags -> drop
-- network objects -> drop helper tables -> revoke leftover grants
-- -> drop roles -> revert ownership -> confirm.
-- ══════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Detach row access policy from tables (Sub-task 4.5)
-- ══════════════════════════════════════════════════════════════
-- Must happen before the policy itself can be dropped.
-- DROP ALL ROW ACCESS POLICIES (not DROP ROW ACCESS POLICY
-- <name>) is used deliberately — Snowflake documents this form as
-- returning a successful status even when no policy is currently
-- attached, which is exactly the idempotent behavior a re-runnable
-- reset script needs. DROP ROW ACCESS POLICY <name> does not
-- support an IF EXISTS clause and errors if nothing is attached.

ALTER TABLE IF EXISTS ECOMMERCE.RAW.CUSTOMERS
    DROP ALL ROW ACCESS POLICIES;

ALTER TABLE IF EXISTS ECOMMERCE.RAW.ORDERS
    DROP ALL ROW ACCESS POLICIES;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Drop views (Sub-task 4.8)
-- ══════════════════════════════════════════════════════════════
-- Must happen before VIEW_ADMIN (the owning role) is dropped in
-- Step 11. Views don't need policy detachment themselves — the
-- policies live on the underlying tables (already handled above
-- and below) — they just need to be dropped as objects.

DROP VIEW IF EXISTS ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE;
DROP VIEW IF EXISTS ECOMMERCE.RAW.REGIONAL_ORDERS_VIEW;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Detach tags from columns (Sub-task 4.6)
-- ══════════════════════════════════════════════════════════════
-- Must happen before either tag can be dropped.

ALTER TABLE IF EXISTS ECOMMERCE.RAW.CUSTOMERS
    MODIFY COLUMN FIRST_NAME UNSET TAG ECOMMERCE.RAW.PII_TAG;
ALTER TABLE IF EXISTS ECOMMERCE.RAW.CUSTOMERS
    MODIFY COLUMN LAST_NAME UNSET TAG ECOMMERCE.RAW.PII_TAG;
ALTER TABLE IF EXISTS ECOMMERCE.RAW.CUSTOMERS
    MODIFY COLUMN SEGMENT UNSET TAG ECOMMERCE.RAW.SEGMENT_TAG;
ALTER TABLE IF EXISTS ECOMMERCE.RAW.SUPPLIERS
    MODIFY COLUMN CONTACT_NAME UNSET TAG ECOMMERCE.RAW.PII_TAG;

-- Unbind the masking policy from PII_TAG before dropping either
ALTER TAG IF EXISTS ECOMMERCE.RAW.PII_TAG UNSET MASKING POLICY ECOMMERCE.RAW.NAME_MASK;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Unset masking policies from columns (Sub-task 4.4)
-- ══════════════════════════════════════════════════════════════

ALTER TABLE IF EXISTS ECOMMERCE.RAW.CUSTOMERS
    MODIFY COLUMN EMAIL UNSET MASKING POLICY;

ALTER TABLE IF EXISTS ECOMMERCE.RAW.CUSTOMERS
    MODIFY COLUMN PHONE UNSET MASKING POLICY;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Drop masking policies (Sub-tasks 4.4 and 4.6)
-- ══════════════════════════════════════════════════════════════
-- Dropped entirely, not reverted — see the capstone note at the
-- top of this file for why that's sufficient.

DROP MASKING POLICY IF EXISTS ECOMMERCE.RAW.EMAIL_MASK;
DROP MASKING POLICY IF EXISTS ECOMMERCE.RAW.PHONE_MASK;
DROP MASKING POLICY IF EXISTS ECOMMERCE.RAW.NAME_MASK;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Drop the row access policy (Sub-task 4.5)
-- ══════════════════════════════════════════════════════════════

DROP ROW ACCESS POLICY IF EXISTS ECOMMERCE.RAW.REGION_ACCESS_POLICY;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Drop tags (Sub-task 4.6)
-- ══════════════════════════════════════════════════════════════

DROP TAG IF EXISTS ECOMMERCE.RAW.PII_TAG;
DROP TAG IF EXISTS ECOMMERCE.RAW.SEGMENT_TAG;

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Network policy cleanup (Sub-task 4.7)
-- ══════════════════════════════════════════════════════════════
-- Includes the disposable test user in case Step 6 of 4.7 was
-- interrupted before its own cleanup ran.

ALTER USER IF EXISTS NETWORK_POLICY_TEST_USER UNSET NETWORK_POLICY;
DROP USER IF EXISTS NETWORK_POLICY_TEST_USER;

DROP NETWORK POLICY IF EXISTS ECOMMERCE_WORKBOOK_POLICY;
DROP NETWORK RULE IF EXISTS ECOMMERCE.RAW.ALLOW_MY_IP;
DROP NETWORK RULE IF EXISTS ECOMMERCE.RAW.BLOCK_ALL_PUBLIC;

-- ══════════════════════════════════════════════════════════════
-- STEP 9: Drop the sandbox schema, if it still exists (Sub-task 4.3)
-- ══════════════════════════════════════════════════════════════

DROP SCHEMA IF EXISTS ECOMMERCE.SANDBOX;

-- ══════════════════════════════════════════════════════════════
-- STEP 10: Drop helper tables (Sub-task 4.5)
-- ══════════════════════════════════════════════════════════════

DROP TABLE IF EXISTS ECOMMERCE.RAW.REGION_ACCESS_MAP;

-- ══════════════════════════════════════════════════════════════
-- STEP 11: Revoke any leftover grants to PUBLIC (Sub-task 4.1)
-- ══════════════════════════════════════════════════════════════
-- Safety net in case a test round trip was interrupted before its
-- own cleanup ran.

REVOKE SELECT ON TABLE ECOMMERCE.RAW.CUSTOMERS FROM ROLE PUBLIC;
REVOKE USAGE ON SCHEMA ECOMMERCE.RAW FROM ROLE PUBLIC;
REVOKE USAGE ON DATABASE ECOMMERCE FROM ROLE PUBLIC;
REVOKE USAGE ON WAREHOUSE WORKBOOK_WH FROM ROLE PUBLIC;

-- ══════════════════════════════════════════════════════════════
-- STEP 12: Drop every custom role Goal 4 created
-- ══════════════════════════════════════════════════════════════
-- Dropping a role automatically removes it from any role
-- hierarchy it was part of — no need to REVOKE ROLE first. By this
-- point every object each role owned has already been dropped or
-- detached above, so these drops should not error.

-- Sub-task 4.2-4.3
DROP ROLE IF EXISTS DATA_ANALYST;
DROP ROLE IF EXISTS DATA_ENGINEER;
DROP ROLE IF EXISTS ECOMMERCE_READ;
DROP ROLE IF EXISTS ECOMMERCE_WRITE;

-- Sub-task 4.4 and 4.6 (MASKING_ADMIN was extended with tag
-- privileges in 4.6, but it's the same role — one drop covers both)
DROP ROLE IF EXISTS MASKING_ADMIN;
DROP ROLE IF EXISTS PII_VIEWER;

-- Sub-task 4.5
DROP ROLE IF EXISTS ROW_ACCESS_ADMIN;
DROP ROLE IF EXISTS MANAGER;
DROP ROLE IF EXISTS ANALYST_NA;
DROP ROLE IF EXISTS ANALYST_EUROPE;
DROP ROLE IF EXISTS ANALYST_APAC;
DROP ROLE IF EXISTS ANALYST_SASIA;
DROP ROLE IF EXISTS ANALYST_LATAM;

-- Sub-task 4.7
DROP ROLE IF EXISTS NETWORK_ADMIN;

-- Sub-task 4.8
DROP ROLE IF EXISTS VIEW_ADMIN;
DROP ROLE IF EXISTS VIEW_ONLY_ANALYST;

-- ══════════════════════════════════════════════════════════════
-- STEP 13: Revert ownership back to ACCOUNTADMIN
-- ══════════════════════════════════════════════════════════════
-- Puts the environment back in the state Sub-task 4.1 assumes on
-- a fresh run: ACCOUNTADMIN owns the schema, tables, and
-- warehouse, and the ENVIRONMENT FIX block has real work to do
-- when you re-run 01_rbac_fundamentals.sql. Network rules/policy,
-- REGION_ACCESS_MAP, and the Sub-task 4.8 views no longer exist as
-- of the steps above, so there is nothing left to revert ownership
-- on for those.

GRANT OWNERSHIP ON SCHEMA ECOMMERCE.RAW TO ROLE ACCOUNTADMIN
    REVOKE CURRENT GRANTS;
GRANT OWNERSHIP ON ALL TABLES IN SCHEMA ECOMMERCE.RAW TO ROLE ACCOUNTADMIN
    REVOKE CURRENT GRANTS;
GRANT OWNERSHIP ON WAREHOUSE WORKBOOK_WH TO ROLE ACCOUNTADMIN
    REVOKE CURRENT GRANTS;

-- ══════════════════════════════════════════════════════════════
-- STEP 14: Confirm the reset
-- ══════════════════════════════════════════════════════════════

-- Should return zero rows — no Goal 4 custom roles remain
SHOW ROLES LIKE '%ECOMMERCE_%';
SHOW ROLES LIKE '%DATA_%';
SHOW ROLES LIKE '%MASKING%';
SHOW ROLES LIKE '%PII%';
SHOW ROLES LIKE '%ANALYST%';
SHOW ROLES LIKE '%MANAGER%';
SHOW ROLES LIKE '%ROW_ACCESS%';
SHOW ROLES LIKE '%NETWORK%';
SHOW ROLES LIKE '%VIEW%';

-- Should show OWNERSHIP granted to ACCOUNTADMIN, not SYSADMIN
SHOW GRANTS ON TABLE ECOMMERCE.RAW.CUSTOMERS;
SHOW GRANTS ON WAREHOUSE WORKBOOK_WH;

-- Should return zero rows — no masking or row access policies
-- remain on CUSTOMERS
SELECT *
FROM TABLE(
    ECOMMERCE.INFORMATION_SCHEMA.POLICY_REFERENCES(
        REF_ENTITY_NAME   => 'ECOMMERCE.RAW.CUSTOMERS',
        REF_ENTITY_DOMAIN => 'TABLE'
    )
)
;

-- Should return zero rows — no tags remain
SHOW TAGS IN SCHEMA ECOMMERCE.RAW;

-- Should return zero rows — no network policies/rules remain
SHOW NETWORK POLICIES LIKE 'ECOMMERCE_WORKBOOK_POLICY';
SHOW NETWORK RULES IN SCHEMA ECOMMERCE.RAW;

-- Should return zero rows — no Sub-task 4.8 views remain
SHOW VIEWS LIKE '%ORDERS%' IN SCHEMA ECOMMERCE.RAW;

-- ══════════════════════════════════════════════════════════════
-- Environment is now back to its pre-Goal-4 state.
-- Re-run 01_rbac_fundamentals.sql through 09_capstone.sql from the
-- top (10_exam_prep.sql creates no objects, so it doesn't need a
-- fresh environment — safe to run any time).
-- ══════════════════════════════════════════════════════════════
