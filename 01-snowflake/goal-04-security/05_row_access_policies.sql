-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Sub-task 4.5 : Row access policies
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~40 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Sub-tasks 4.1-4.4 complete
--                    Enterprise Edition or higher (row access
--                    policies are not available on Standard
--                    Edition)
-- COF-C03 domain   : Domain 2.0 — Account Management and Data Governance (20%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Sub-task 4.4 controlled whether a role sees the real VALUE in
--   a column. Row access policies control whether a role sees a
--   ROW at all — the same query, run by two different roles,
--   returns a different SET OF ROWS, not just different values
--   within them.
--
--   This sub-task restricts CUSTOMERS and ORDERS to regional
--   analyst roles, using CUSTOMERS.REGION and
--   ORDERS.SHIPPING_REGION — North America, Europe, Asia Pacific,
--   South Asia, Latin America. A MANAGER role sees every region.
--   The capstone in Sub-task 4.9 combines this with Sub-task 4.4's
--   masking policies in one scenario.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: ROW ACCESS POLICIES
-- ══════════════════════════════════════════════════════════════
--
-- A row access policy is a SCHEMA-LEVEL object, same as a masking
-- policy — written once, attached to one or more tables/views.
-- Unlike a masking policy (one input column, one output value), a
-- row access policy takes one or more columns as input and RETURNS
-- BOOLEAN: TRUE means the row is visible, FALSE means it's
-- filtered out entirely, before the result set is even returned.
--
-- Two privileges govern this, mirroring Sub-task 4.4's pattern:
--
--   CREATE ROW ACCESS POLICY   schema-level — automatically
--                              granted to the schema OWNER
--                              (SYSADMIN, per Sub-task 4.1), which
--                              can then grant it onward
--   APPLY ROW ACCESS POLICY    ACCOUNT-level (global) — lets a
--                              role ATTACH a policy to a table or
--                              view. Held only by ACCOUNTADMIN by
--                              default, same restriction as APPLY
--                              MASKING POLICY in Sub-task 4.4 —
--                              grant it from ACCOUNTADMIN, not
--                              SECURITYADMIN.
--
-- This sub-task uses a MAPPING TABLE — a row-access-policy pattern
-- where the policy body looks up the querying role in a small
-- table rather than hardcoding role names in a CASE statement. The
-- mapping table scales to any number of regions without editing
-- the policy body itself.
--
-- ── The owner's-rights gotcha ─────────────────────────────────
-- When a row access policy's body queries a mapping table, that
-- lookup runs using the PRIVILEGES OF THE POLICY OWNER — not the
-- querying role. This means the querying role (e.g. ANALYST_EUROPE)
-- does NOT need SELECT on the mapping table itself; the POLICY's
-- owning role does. Forgetting this is a common setup mistake:
-- granting the mapping table's SELECT privilege to the analyst
-- roles instead of to the role that owns the policy accomplishes
-- nothing, since the analyst role never touches the mapping table
-- directly — the policy does, on their behalf.
-- ─────────────────────────────────────────────────────────────
--
-- ── Row access policies run before masking policies ──────────
-- When a table has both, Snowflake evaluates the row access policy
-- FIRST (deciding which rows exist at all), then applies any
-- masking policies to the columns of whatever rows survive. This
-- ordering matters for the Sub-task 4.9 capstone, which combines
-- both on the same table.
-- ─────────────────────────────────────────────────────────────
--
-- ── Updating a policy that's already attached ────────────────
-- Same restriction as masking policies (Sub-task 4.4): once a row
-- access policy is attached to a table, CREATE OR REPLACE cannot
-- change it. Use ALTER ROW ACCESS POLICY ... SET BODY instead —
-- it updates the logic in place, no need to detach and reattach,
-- and the table stays protected throughout the change.
-- ─────────────────────────────────────────────────────────────
--
-- ── Oracle / SQL Server comparison ───────────────────────────
-- Oracle's closest equivalent is Virtual Private Database (VPD),
-- managed through the DBMS_RLS package — a PL/SQL function
-- returns a WHERE-clause predicate that Oracle silently appends to
-- every query against the protected table. The core idea is the
-- same (invisible, automatic row filtering), but Snowflake's row
-- access policy is a named, reusable schema object attached via
-- GRANT-style privileges, whereas Oracle VPD policies are
-- registered procedurally via DBMS_RLS.ADD_POLICY calls rather
-- than created as a standalone SQL object.
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
-- STEP 1: Create a row access policy administrator role
-- ══════════════════════════════════════════════════════════════

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS ROW_ACCESS_ADMIN
    COMMENT = 'Manages and applies row access policies';

-- APPLY ROW ACCESS POLICY is account-level, held only by
-- ACCOUNTADMIN by default — same pattern as APPLY MASKING POLICY
USE ROLE ACCOUNTADMIN;

GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE ROW_ACCESS_ADMIN;

USE ROLE SECURITYADMIN;

GRANT ROLE ROW_ACCESS_ADMIN TO ROLE SYSADMIN;
GRANT ROLE ROW_ACCESS_ADMIN TO USER <your_username>;

-- CREATE ROW ACCESS POLICY is schema-level — SYSADMIN, as schema
-- owner, grants it directly
USE ROLE SYSADMIN;

GRANT USAGE ON DATABASE ECOMMERCE     TO ROLE ROW_ACCESS_ADMIN;
GRANT USAGE ON SCHEMA   ECOMMERCE.RAW TO ROLE ROW_ACCESS_ADMIN;
GRANT USAGE ON WAREHOUSE WORKBOOK_WH  TO ROLE ROW_ACCESS_ADMIN;
GRANT CREATE ROW ACCESS POLICY ON SCHEMA ECOMMERCE.RAW TO ROLE ROW_ACCESS_ADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Build the region mapping table
-- ══════════════════════════════════════════════════════════════
-- SYSADMIN owns this table, same as every other table in RAW.
-- ROW_ACCESS_ADMIN needs SELECT on it — per CONCEPT above, this is
-- because the POLICY (owned by ROW_ACCESS_ADMIN) looks it up, not
-- because any analyst role queries it directly.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.REGION_ACCESS_MAP (
    ROLE_NAME VARCHAR,
    REGION    VARCHAR
);

INSERT INTO ECOMMERCE.RAW.REGION_ACCESS_MAP (ROLE_NAME, REGION) VALUES
    ('ANALYST_NA',     'North America'),
    ('ANALYST_EUROPE', 'Europe'),
    ('ANALYST_APAC',   'Asia Pacific'),
    ('ANALYST_SASIA',  'South Asia'),
    ('ANALYST_LATAM',  'Latin America');

GRANT SELECT ON TABLE ECOMMERCE.RAW.REGION_ACCESS_MAP TO ROLE ROW_ACCESS_ADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Create the regional analyst roles and a MANAGER role
-- ══════════════════════════════════════════════════════════════
-- Each regional role holds ECOMMERCE_READ (Sub-task 4.2) for
-- baseline table/warehouse access. MANAGER also holds it, and is
-- named explicitly in the policy body to see every region.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS ANALYST_NA     COMMENT = 'Regional analyst: North America only';
CREATE ROLE IF NOT EXISTS ANALYST_EUROPE COMMENT = 'Regional analyst: Europe only';
CREATE ROLE IF NOT EXISTS ANALYST_APAC   COMMENT = 'Regional analyst: Asia Pacific only';
CREATE ROLE IF NOT EXISTS ANALYST_SASIA  COMMENT = 'Regional analyst: South Asia only';
CREATE ROLE IF NOT EXISTS ANALYST_LATAM  COMMENT = 'Regional analyst: Latin America only';
CREATE ROLE IF NOT EXISTS MANAGER        COMMENT = 'Sees all regions, every row';

GRANT ROLE ECOMMERCE_READ TO ROLE ANALYST_NA;
GRANT ROLE ECOMMERCE_READ TO ROLE ANALYST_EUROPE;
GRANT ROLE ECOMMERCE_READ TO ROLE ANALYST_APAC;
GRANT ROLE ECOMMERCE_READ TO ROLE ANALYST_SASIA;
GRANT ROLE ECOMMERCE_READ TO ROLE ANALYST_LATAM;
GRANT ROLE ECOMMERCE_READ TO ROLE MANAGER;

GRANT ROLE ANALYST_NA     TO ROLE SYSADMIN;
GRANT ROLE ANALYST_EUROPE TO ROLE SYSADMIN;
GRANT ROLE ANALYST_APAC   TO ROLE SYSADMIN;
GRANT ROLE ANALYST_SASIA  TO ROLE SYSADMIN;
GRANT ROLE ANALYST_LATAM  TO ROLE SYSADMIN;
GRANT ROLE MANAGER        TO ROLE SYSADMIN;

-- Granted to your user so you can switch between all of them for
-- testing in Step 5
GRANT ROLE ANALYST_NA     TO USER <your_username>;
GRANT ROLE ANALYST_EUROPE TO USER <your_username>;
GRANT ROLE ANALYST_APAC   TO USER <your_username>;
GRANT ROLE ANALYST_SASIA  TO USER <your_username>;
GRANT ROLE ANALYST_LATAM  TO USER <your_username>;
GRANT ROLE MANAGER        TO USER <your_username>;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Write and attach the row access policy
-- ══════════════════════════════════════════════════════════════

USE ROLE ROW_ACCESS_ADMIN;
USE SECONDARY ROLES NONE;

CREATE OR REPLACE ROW ACCESS POLICY ECOMMERCE.RAW.REGION_ACCESS_POLICY
    AS (region_col VARCHAR) RETURNS BOOLEAN ->
    CASE
        WHEN CURRENT_ROLE() IN ('MANAGER', 'SYSADMIN') THEN TRUE
        WHEN EXISTS (
            SELECT 1
            FROM ECOMMERCE.RAW.REGION_ACCESS_MAP m
            WHERE m.ROLE_NAME = CURRENT_ROLE()
              AND m.REGION = region_col
        ) THEN TRUE
        ELSE FALSE
    END
;

-- Attach to both tables that carry a region column — one policy,
-- reused across two tables, bound to a differently-named column
-- in each
ALTER TABLE ECOMMERCE.RAW.CUSTOMERS
    ADD ROW ACCESS POLICY ECOMMERCE.RAW.REGION_ACCESS_POLICY ON (REGION);

ALTER TABLE ECOMMERCE.RAW.ORDERS
    ADD ROW ACCESS POLICY ECOMMERCE.RAW.REGION_ACCESS_POLICY ON (SHIPPING_REGION);

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Prove the same query returns different ROWS by role
-- ══════════════════════════════════════════════════════════════

USE ROLE ANALYST_EUROPE;
USE SECONDARY ROLES NONE;

SELECT region, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.CUSTOMERS
GROUP BY region
;
-- Only Europe appears — every other region is filtered out
-- entirely, not just masked

USE ROLE ANALYST_NA;
USE SECONDARY ROLES NONE;

SELECT region, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.CUSTOMERS
GROUP BY region
;
-- Only North America appears

USE ROLE MANAGER;
USE SECONDARY ROLES NONE;

SELECT region, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.CUSTOMERS
GROUP BY region
;
-- All five regions appear — MANAGER is named explicitly in the
-- policy's CASE logic

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Confirm what's protected, account-wide
-- ══════════════════════════════════════════════════════════════

USE ROLE ROW_ACCESS_ADMIN;
USE SECONDARY ROLES NONE;

SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.POLICY_REFERENCES(
        POLICY_NAME => 'ECOMMERCE.RAW.REGION_ACCESS_POLICY'
    )
)
;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Updating a policy that's already attached
-- ══════════════════════════════════════════════════════════════
-- Same lesson as Sub-task 4.4 Step 7: CREATE OR REPLACE cannot
-- change a policy that's currently attached. Use ALTER ... SET
-- BODY instead — the table stays protected throughout.

USE ROLE ROW_ACCESS_ADMIN;
USE SECONDARY ROLES NONE;

-- Add ANALYST_APAC temporarily, using the correct in-place method
ALTER ROW ACCESS POLICY ECOMMERCE.RAW.REGION_ACCESS_POLICY SET BODY ->
    CASE
        WHEN CURRENT_ROLE() IN ('MANAGER', 'SYSADMIN', 'ANALYST_APAC') THEN TRUE
        WHEN EXISTS (
            SELECT 1
            FROM ECOMMERCE.RAW.REGION_ACCESS_MAP m
            WHERE m.ROLE_NAME = CURRENT_ROLE()
              AND m.REGION = region_col
        ) THEN TRUE
        ELSE FALSE
    END
;

-- Confirm ANALYST_APAC now sees every region — its own AND
-- everyone else's, since it's temporarily named as an exception,
-- not looked up through the mapping table
USE ROLE ANALYST_APAC;
USE SECONDARY ROLES NONE;

SELECT region, COUNT(*) AS row_count
FROM ECOMMERCE.RAW.CUSTOMERS
GROUP BY region
;
-- All five regions appear — not just Asia Pacific

-- Revert back to the original mapping-table-only logic
USE ROLE ROW_ACCESS_ADMIN;
USE SECONDARY ROLES NONE;

ALTER ROW ACCESS POLICY ECOMMERCE.RAW.REGION_ACCESS_POLICY SET BODY ->
    CASE
        WHEN CURRENT_ROLE() IN ('MANAGER', 'SYSADMIN') THEN TRUE
        WHEN EXISTS (
            SELECT 1
            FROM ECOMMERCE.RAW.REGION_ACCESS_MAP m
            WHERE m.ROLE_NAME = CURRENT_ROLE()
              AND m.REGION = region_col
        ) THEN TRUE
        ELSE FALSE
    END
;

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Add a sixth row to REGION_ACCESS_MAP mapping a brand-new role
--    name (that you haven't created) to a region. Confirm nothing
--    breaks — the policy's EXISTS subquery simply never matches
--    for a role nobody holds. Then create that role for real,
--    grant yourself it, and confirm it now sees that region.
--
-- 2. As ANALYST_EUROPE, query CUSTOMERS selecting EMAIL and PHONE
--    alongside REGION. Confirm you see ONLY Europe rows AND masked
--    EMAIL/PHONE values at the same time — row access and masking
--    both apply together, which is exactly what Sub-task 4.9's
--    capstone will formalize.
--
-- 3. Try adding a SECOND row access policy to CUSTOMERS.REGION
--    (any body will do). Confirm it fails — a column can only be
--    protected by one row access policy at a time.
--
-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if the analyst role needs SELECT on the mapping table
--    to make the policy work?
-- A: It doesn't, and granting it accomplishes nothing. The policy
--    body executes with the PRIVILEGES OF ITS OWNER (ROW_ACCESS_
--    ADMIN here), not the querying role — see CONCEPT above. The
--    analyst role never touches REGION_ACCESS_MAP directly.
--
-- Q: What if a table has both a row access policy and a masking
--    policy — which applies first?
-- A: The row access policy always evaluates first, deciding which
--    rows exist in the result at all. Masking is then applied to
--    whichever rows survive. You cannot put the same column in
--    both a row access policy signature and a masking policy
--    signature at the same time, though — Sub-task 4.4's EMAIL/
--    PHONE masking and this sub-task's REGION row access policy
--    are on different columns for exactly this reason.
--
-- Q: What if I try to CREATE OR REPLACE a row access policy that's
--    already attached to a table?
-- A: Same restriction as masking policies (Sub-task 4.4) — it's
--    blocked once attached. Use ALTER ROW ACCESS POLICY ... SET
--    BODY instead, as Step 7 demonstrates; the table stays
--    protected throughout the update, with no gap where it's
--    unprotected.
--
-- Q: What if a role has INSERT privilege on a table protected by
--    a row access policy — can it insert a row for a region it
--    can't see?
-- A: Yes. Row access policies filter what SELECT (and the SELECT
--    portion of UPDATE/DELETE/MERGE) returns — they do not block
--    INSERT of new rows outside what the role could normally see.
--    None of the analyst roles in this sub-task hold INSERT (only
--    ECOMMERCE_READ), so this doesn't apply yet, but it matters
--    once a role holds both regional row access and write access.
--
-- Q: What is different from Oracle I should watch for in this
--    sub-task specifically?
-- A: Key differences:
--    · VPD policies are registered procedurally via
--      DBMS_RLS.ADD_POLICY; a Snowflake row access policy is a
--      standalone, named schema object created with ordinary SQL
--    · APPLY ROW ACCESS POLICY as a distinct account-level
--      privilege has no direct Oracle parallel — Oracle VPD
--      policy application is bundled into the DBMS_RLS package
--      call itself, not a separately grantable privilege
--    · The owner's-rights execution model for mapping table
--      lookups (this sub-task's CONCEPT) has a rough parallel in
--      Oracle's DBMS_RLS policy function running with the
--      privileges of whoever owns the underlying PL/SQL function
-- ══════════════════════════════════════════════════════════════
