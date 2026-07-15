-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Sub-task 4.9 : Capstone — combining every security layer
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~50 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Sub-tasks 4.1-4.8 complete — this file
--                    assumes every role, policy, tag, and view
--                    from the rest of Goal 4 already exists
-- COF-C03 domain   : Domain 4 — Data Governance and Security (23%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Goal 4 built eight independent security mechanisms: system and
--   custom roles (4.1-4.3), masking policies (4.4), row access
--   policies (4.5), tag-driven masking (4.6), network policies
--   (4.7), and secure views (4.8). None of them know about each
--   other. They just all evaluate, every time, whenever a query
--   runs — which is exactly why they compose safely.
--
--   This capstone does two things: proves that composition really
--   holds (being cleared by one policy never clears you through
--   another), and then surfaces the one genuinely surprising gap
--   in how they compose — what CURRENT_ROLE()-based policies do
--   and don't know about role HIERARCHY (Sub-task 4.2). By the end,
--   you'll have upgraded every masking and row access policy built
--   in this goal to close that gap properly.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: CURRENT_ROLE() DOES NOT KNOW ABOUT ROLE HIERARCHY
-- ══════════════════════════════════════════════════════════════
--
-- Every masking and row access policy built in Sub-tasks 4.4-4.6
-- checks CURRENT_ROLE() — the literal name of whichever role is
-- currently ACTIVE as the primary role. Sub-task 4.2 taught that
-- roles can inherit other roles' PRIVILEGES through hierarchy
-- (GRANT ROLE x TO ROLE y). It is a very reasonable assumption that
-- inheriting a role's privileges would also mean "becoming" that
-- role for policy purposes. It does not.
--
-- If ANALYST_EUROPE is granted the PII_VIEWER role (GRANT ROLE
-- PII_VIEWER TO ROLE ANALYST_EUROPE), ANALYST_EUROPE now inherits
-- whatever PRIVILEGES PII_VIEWER holds (just ECOMMERCE_READ, in
-- this workbook). But if ANALYST_EUROPE is the ACTIVE primary role
-- when a query runs, CURRENT_ROLE() still returns 'ANALYST_EUROPE'
-- — never 'PII_VIEWER' — regardless of the hierarchy. A masking
-- policy checking CURRENT_ROLE() IN ('PII_VIEWER', 'SYSADMIN') will
-- NOT unmask data for ANALYST_EUROPE, even though it now inherits
-- PII_VIEWER's privileges in every other sense. Step 2 below proves
-- this directly, and it is a genuinely common, documented source
-- of confusion in real Snowflake environments.
--
-- The fix is a different context function: IS_ROLE_IN_SESSION(
-- '<role_name>'). Unlike CURRENT_ROLE(), it checks whether the
-- named role appears ANYWHERE in the current session's active
-- primary-or-secondary role hierarchy — not just whether it IS the
-- literal active role. Steps 4-6 below rewrite this goal's policies
-- to use it, then re-run the exact same hierarchy grant from Step 2
-- to confirm the behavior actually changes.
--
-- Neither function is universally "more correct" — CURRENT_ROLE()
-- is simpler to reason about and is what most Snowflake examples
-- default to; IS_ROLE_IN_SESSION() is for when you specifically
-- want hierarchy-based inheritance to extend to policy access too.
-- Which one you want is a design decision, not a bug fix, in most
-- cases — this capstone treats it as a deliberate upgrade, not a
-- correction of something "wrong" in Sub-tasks 4.4-4.6.
--
-- ── Oracle / SQL Server comparison ───────────────────────────
-- Oracle's VPD policies typically use SYS_CONTEXT to check the
-- current session's enabled role, with similar reasoning required
-- about whether a policy should check only the literal active role
-- or walk the broader role hierarchy — usually resolved with
-- custom PL/SQL querying DBA_ROLE_PRIVS rather than a single
-- built-in context function. IS_ROLE_IN_SESSION bundles that
-- hierarchy-walk into one function call; Oracle has no equally
-- direct equivalent.
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
-- STEP 1: Confirm the baseline — ANALYST_EUROPE, before any
--         hierarchy change
-- ══════════════════════════════════════════════════════════════

USE ROLE ANALYST_EUROPE;
USE SECONDARY ROLES NONE;

SELECT customer_id, first_name, last_name, email, phone, region
FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- Europe rows only, names/email/phone masked — the known-good
-- result from Sub-task 4.8 Step 8

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Grant PII_VIEWER into ANALYST_EUROPE's hierarchy — and
--         watch masking NOT change
-- ══════════════════════════════════════════════════════════════

USE ROLE SECURITYADMIN;

GRANT ROLE PII_VIEWER TO ROLE ANALYST_EUROPE;

-- ANALYST_EUROPE now inherits PII_VIEWER's privileges. Re-run the
-- exact same query as Step 1, with ANALYST_EUROPE still the active
-- primary role:
USE ROLE ANALYST_EUROPE;
USE SECONDARY ROLES NONE;

SELECT customer_id, first_name, last_name, email, phone, region
FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- STILL masked — nothing changed, despite ANALYST_EUROPE now
-- inheriting PII_VIEWER

-- ══════════════════════════════════════════════════════════════
-- STEP 3: See exactly why, directly
-- ══════════════════════════════════════════════════════════════

SELECT
    CURRENT_ROLE()                    AS current_role,
    IS_ROLE_IN_SESSION('PII_VIEWER')  AS pii_viewer_in_session
;
-- CURRENT_ROLE = 'ANALYST_EUROPE' — never changes just because a
-- role was granted into its hierarchy. IS_ROLE_IN_SESSION =
-- TRUE — PII_VIEWER genuinely IS in this session's active role
-- hierarchy. The masking policies check the first one, not the
-- second — that's the entire gap.

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Upgrade the masking policies to IS_ROLE_IN_SESSION
-- ══════════════════════════════════════════════════════════════
-- Using ALTER ... SET BODY (Sub-task 4.4 Step 7) — all three
-- policies are already attached, so CREATE OR REPLACE would fail.

USE ROLE MASKING_ADMIN;
USE SECONDARY ROLES NONE;

ALTER MASKING POLICY ECOMMERCE.RAW.EMAIL_MASK SET BODY ->
    CASE
        WHEN IS_ROLE_IN_SESSION('PII_VIEWER') OR IS_ROLE_IN_SESSION('SYSADMIN') THEN val
        ELSE '***MASKED***'
    END
;

ALTER MASKING POLICY ECOMMERCE.RAW.PHONE_MASK SET BODY ->
    CASE
        WHEN IS_ROLE_IN_SESSION('PII_VIEWER') OR IS_ROLE_IN_SESSION('SYSADMIN') THEN val
        ELSE CONCAT('***-***-', RIGHT(val, 4))
    END
;

ALTER MASKING POLICY ECOMMERCE.RAW.NAME_MASK SET BODY ->
    CASE
        WHEN IS_ROLE_IN_SESSION('PII_VIEWER') OR IS_ROLE_IN_SESSION('SYSADMIN') THEN val
        ELSE LEFT(val, 1) || REPEAT('*', GREATEST(LENGTH(val) - 1, 0))
    END
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Upgrade the row access policy the same way
-- ══════════════════════════════════════════════════════════════
-- IS_ROLE_IN_SESSION also accepts a COLUMN reference, not just a
-- literal string — evaluated per row against the mapping table.

USE ROLE ROW_ACCESS_ADMIN;
USE SECONDARY ROLES NONE;

ALTER ROW ACCESS POLICY ECOMMERCE.RAW.REGION_ACCESS_POLICY SET BODY ->
    CASE
        WHEN IS_ROLE_IN_SESSION('MANAGER') OR IS_ROLE_IN_SESSION('SYSADMIN') THEN TRUE
        WHEN EXISTS (
            SELECT 1
            FROM ECOMMERCE.RAW.REGION_ACCESS_MAP m
            WHERE IS_ROLE_IN_SESSION(m.ROLE_NAME)
              AND m.REGION = region_col
        ) THEN TRUE
        ELSE FALSE
    END
;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Re-run Step 1's exact query — same role, same hierarchy
--         grant, different result this time
-- ══════════════════════════════════════════════════════════════

USE ROLE ANALYST_EUROPE;
USE SECONDARY ROLES NONE;

SELECT customer_id, first_name, last_name, email, phone, region
FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- NOW unmasked — same active role (ANALYST_EUROPE), same hierarchy
-- grant from Step 2, only the POLICY LOGIC changed. Still Europe-
-- only rows, though — PII_VIEWER's hierarchy grant only reaches
-- the masking policies; MANAGER was never granted into
-- ANALYST_EUROPE's hierarchy, so row access is unaffected.

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Add MANAGER into the hierarchy too — full composition
-- ══════════════════════════════════════════════════════════════

USE ROLE SECURITYADMIN;

GRANT ROLE MANAGER TO ROLE ANALYST_EUROPE;

USE ROLE ANALYST_EUROPE;
USE SECONDARY ROLES NONE;

SELECT customer_id, first_name, last_name, email, phone, region
FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- Every region now visible, every name/email/phone unmasked — one
-- active role (ANALYST_EUROPE), two roles granted into its
-- hierarchy (PII_VIEWER, MANAGER), both now correctly recognized
-- by IS_ROLE_IN_SESSION-based policies across masking AND row
-- access at once

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Revert — this was a demonstration, not a permanent
--         change to ANALYST_EUROPE's scope
-- ══════════════════════════════════════════════════════════════

USE ROLE SECURITYADMIN;

REVOKE ROLE PII_VIEWER FROM ROLE ANALYST_EUROPE;
REVOKE ROLE MANAGER    FROM ROLE ANALYST_EUROPE;

USE ROLE ANALYST_EUROPE;
USE SECONDARY ROLES NONE;

SELECT customer_id, first_name, last_name, email, phone, region
FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- Back to Europe-only, masked — ANALYST_EUROPE restored to its
-- originally intended scope, policy logic upgrade notwithstanding

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 9: The full composition matrix
-- ══════════════════════════════════════════════════════════════
-- One query, six roles, showing every mechanism from Sub-tasks
-- 4.1-4.8 still working together correctly after the Step 4-5
-- upgrade. Run each block and compare against the expected
-- outcome in its comment.

USE ROLE ANALYST_EUROPE;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) AS visible_rows FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE;
-- Expected: Europe rows only, masked (no hierarchy grants remain)

USE ROLE MANAGER;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) AS visible_rows FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE;
-- Expected: every region, still masked — MANAGER was never in
-- either masking policy's allow list, hierarchy or otherwise

USE ROLE PII_VIEWER;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) AS visible_rows FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE;
-- Expected: ZERO rows — PII_VIEWER is not MANAGER, not SYSADMIN,
-- and not mapped to any region; unmasked columns would show real
-- values, but there is nothing to show

USE ROLE SYSADMIN;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) AS visible_rows FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE;
-- Expected: every region, fully unmasked — SYSADMIN is explicitly
-- named in every policy in this goal

USE ROLE VIEW_ONLY_ANALYST;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) AS visible_rows FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE;
-- Expected: ZERO rows, but the query SUCCEEDS — owner's rights
-- (Sub-task 4.8) gets this role past having no direct grant on
-- CUSTOMERS/ORDERS at all; row access still filters it to nothing

USE ROLE DATA_ANALYST;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) AS visible_rows FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE;
-- Expected: ZERO rows — same reasoning as PII_VIEWER above;
-- DATA_ANALYST was never mapped to a region either

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 10: Where network policies fit in this picture
-- ══════════════════════════════════════════════════════════════
-- Sub-task 4.7's network policy is separate from everything above
-- — it governs whether a connection is allowed AT ALL, evaluated
-- before authentication completes. None of Steps 1-9 would run if
-- the connecting IP were blocked, regardless of which role, which
-- masking logic, or which row access policy applies afterward.
-- There is no live "combine" demonstration for this the way there
-- is for the other mechanisms, since ECOMMERCE_WORKBOOK_POLICY was
-- deliberately never activated at the account level (Sub-task
-- 4.7's safety framing) — its composition with everything else in
-- this goal is: it either lets the connection happen, or none of
-- the rest of this matters at all.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Build a real, permanent composite functional role —
--    EU_REGIONAL_MANAGER — that holds ANALYST_EUROPE, MANAGER, and
--    PII_VIEWER all at once via role hierarchy, rather than
--    temporarily hacking ANALYST_EUROPE's hierarchy the way Steps
--    2-8 did. Grant it to SYSADMIN for visibility and to your user
--    for testing. Confirm it produces the same "every region,
--    fully unmasked" result as Step 7, without ever touching
--    ANALYST_EUROPE itself.
--
-- 2. Re-run Sub-task 4.5's Practice Gap exercise 2 (querying
--    CUSTOMERS directly as ANALYST_EUROPE with EMAIL/PHONE
--    selected) now that the policies use IS_ROLE_IN_SESSION.
--    Confirm the result is identical to before the upgrade —
--    the upgrade changes HOW hierarchy is evaluated, not the
--    outcome for roles that were already working correctly.
--
-- 3. Look up IS_GRANTED_TO_INVOKER_ROLE in Snowflake's docs and
--    compare it to IS_ROLE_IN_SESSION. Write down, in your own
--    words, when INVOKER_ROLE (the view owner, in some execution
--    contexts) would differ from CURRENT_ROLE (the querying role)
--    — this matters specifically for policies attached to views
--    rather than base tables, which Sub-task 4.8 touched on but
--    didn't fully explore.
--
-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I want a hierarchy grant to work with a policy that
--    still uses CURRENT_ROLE(), without rewriting the policy?
-- A: You can't — CURRENT_ROLE() has no hierarchy-awareness option
--    short of changing the function used in the policy body
--    itself. Steps 4-5 above are the only real fix once a policy
--    is written this way.
--
-- Q: What if a role has multiple SECONDARY roles active (not the
--    USE SECONDARY ROLES NONE isolation this workbook has used
--    throughout) — does IS_ROLE_IN_SESSION check those too?
-- A: Yes — IS_ROLE_IN_SESSION checks the full active role
--    hierarchy, primary AND secondary. This is actually a second,
--    separate reason CURRENT_ROLE()-based policies can look
--    "wrong" in normal use: a session with secondary roles enabled
--    (the account default, per Sub-task 4.1) might have real
--    access to something through a secondary role that
--    CURRENT_ROLE() never reveals, while IS_ROLE_IN_SESSION would
--    have caught it correctly either way.
--
-- Q: What if every policy in this goal should have used
--    IS_ROLE_IN_SESSION from the start?
-- A: Not necessarily — see CONCEPT above. CURRENT_ROLE() is
--    simpler, more predictable, and is what most Snowflake
--    documentation defaults to. The right choice depends on
--    whether you WANT hierarchy to extend policy access
--    automatically. This capstone upgraded Goal 4's policies
--    because the workbook's own role hierarchy (Sub-task 4.2)
--    makes that the more coherent choice going forward — not
--    because CURRENT_ROLE() was ever a mistake.
--
-- Q: What if a role's hierarchy grant needs to be revoked, like
--    Step 8 does — does that immediately affect an already-active
--    session?
-- A: The effect is checked per-query, not cached for the session's
--    lifetime — Step 8's revoke takes effect immediately on the
--    very next query run as ANALYST_EUROPE, with no need to log
--    out or start a new session.
--
-- Q: What is different from Oracle I should watch for in this
--    sub-task specifically?
-- A: Key differences:
--    · IS_ROLE_IN_SESSION bundles a full role-hierarchy walk into
--      one context function; Oracle's SYS_CONTEXT-based VPD
--      policies typically require custom PL/SQL against
--      DBA_ROLE_PRIVS to achieve the same hierarchy-awareness
--    · Every mechanism in this goal (RBAC, masking, row access,
--      tags, network policies, secure views) is a genuinely
--      separate, independently-evaluated Snowflake object type —
--      Oracle's closest equivalents (roles, Data Redaction, VPD,
--      no close tag equivalent, sqlnet.ora, definer's rights
--      views) are spread across the database engine, a security
--      option package, and OS-level config files, rather than
--      being one coherent, SQL-native governance layer
-- ══════════════════════════════════════════════════════════════
