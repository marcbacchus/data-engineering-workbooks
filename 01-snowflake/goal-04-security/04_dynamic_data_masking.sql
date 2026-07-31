-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Sub-task 4.4 : Dynamic data masking
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~40 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Sub-tasks 4.1-4.3 complete
--                    Enterprise Edition or higher (masking is not
--                    available on Standard Edition)
-- COF-C03 domain   : Domain 2.0 — Account Management and Data Governance (20%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   RBAC (Sub-tasks 4.1-4.3) controls whether a role can see a
--   TABLE. Dynamic Data Masking controls whether it can see the
--   real VALUE inside specific COLUMNS of that table — the same
--   query, run by two different roles, returns two different
--   results for the same row.
--
--   This sub-task masks CUSTOMERS.EMAIL (full mask) and
--   CUSTOMERS.PHONE (partial mask) — the two genuinely PII
--   columns in this dataset. The policies built here stay in
--   place for the rest of Goal 4; the capstone in Sub-task 4.9
--   combines them with row access policies and tags.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: DYNAMIC DATA MASKING
-- ══════════════════════════════════════════════════════════════
--
-- A masking policy is a SCHEMA-LEVEL object — like a table or a
-- view, it lives in a database and schema. It's written once as
-- a CASE expression, then attached to one or more columns with
-- ALTER TABLE/VIEW ... SET MASKING POLICY. The underlying data on
-- disk is never changed — masking happens at query time, evaluated
-- fresh for every query based on the CURRENT_ROLE() of whoever is
-- running it.
--
-- Two privileges govern who can do what, and they are
-- deliberately separate from ordinary table privileges:
--
--   CREATE MASKING POLICY   schema-level privilege — lets a role
--                            author policies in a given schema
--   APPLY MASKING POLICY    ACCOUNT-level (global) privilege —
--                            lets a role ATTACH a policy to a
--                            column. Held ONLY by ACCOUNTADMIN by
--                            default — not SECURITYADMIN, despite
--                            what some Snowflake examples show.
--                            Must be explicitly granted to any
--                            other role, same pattern as MANAGE
--                            GRANTS (Sub-task 4.3), which IS held
--                            by both ACCOUNTADMIN and SECURITYADMIN.
--                            The two privileges look similar but
--                            have different default holders — do
--                            not assume one implies the other.
--
-- This split exists on purpose: it lets a security/privacy
-- officer role decide what gets masked, independent of whoever
-- owns the table. Notably, table OWNERSHIP does not grant an
-- exemption from masking — an object owner sees masked data just
-- like anyone else unless their role is explicitly named inside
-- the policy's CASE logic. Step 5 below demonstrates this
-- directly.
--
-- ── Updating a policy that's already attached to a column ────
-- CREATE OR REPLACE MASKING POLICY works fine the FIRST time —
-- nothing is attached yet. Once a policy is attached to even one
-- column, CREATE OR REPLACE (and DROP) both fail with:
--
--   "Policy <name> cannot be dropped/replaced as it is associated
--   with one or more entities"
--
-- To change the logic of a policy that's already in use, use
-- ALTER MASKING POLICY ... SET BODY instead — it updates the
-- CASE expression in place, with no unset/reattach required, and
-- the new logic applies on the very next query. Step 7 below
-- demonstrates the failure and the fix side by side.
-- ─────────────────────────────────────────────────────────────
--
-- ── Oracle / SQL Server comparison ───────────────────────────
-- Oracle's closest equivalent is Data Redaction (part of the
-- Advanced Security option), managed through the DBMS_REDACT
-- package. The core idea is similar — transform the value at
-- query time, leave storage untouched — but Snowflake's masking
-- policy is a first-class, reusable schema object that can be
-- written once and attached to many columns across many tables,
-- whereas Oracle redaction policies are typically defined and
-- managed per column via package calls rather than as a single
-- named object you attach repeatedly.
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
-- STEP 1: Create a masking administrator role
-- ══════════════════════════════════════════════════════════════
-- Following Snowflake's documented pattern: a dedicated role for
-- defining and applying masking policies, separate from SYSADMIN
-- and separate from the DATA_ANALYST/DATA_ENGINEER roles built in
-- Sub-tasks 4.2-4.3.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS MASKING_ADMIN
    COMMENT = 'Manages and applies Dynamic Data Masking policies';

-- APPLY MASKING POLICY is account-level and held ONLY by
-- ACCOUNTADMIN by default (not SECURITYADMIN — see CONCEPT above)
-- — must be granted explicitly.
USE ROLE ACCOUNTADMIN;

GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE MASKING_ADMIN;

USE ROLE SECURITYADMIN;

GRANT ROLE MASKING_ADMIN TO ROLE SYSADMIN;
GRANT ROLE MASKING_ADMIN TO USER <your_username>;

-- CREATE MASKING POLICY is schema-level — the schema owner
-- (SYSADMIN, per Sub-task 4.1's environment fix) grants it
-- directly, the same as any other schema-level privilege.
-- Warehouse USAGE is granted defensively too, in case any future
-- masking-related work in this role needs to run a query.
USE ROLE SYSADMIN;

GRANT USAGE ON DATABASE ECOMMERCE     TO ROLE MASKING_ADMIN;
GRANT USAGE ON SCHEMA   ECOMMERCE.RAW TO ROLE MASKING_ADMIN;
GRANT USAGE ON WAREHOUSE WORKBOOK_WH  TO ROLE MASKING_ADMIN;
GRANT CREATE MASKING POLICY ON SCHEMA ECOMMERCE.RAW TO ROLE MASKING_ADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create a role allowed to see unmasked PII
-- ══════════════════════════════════════════════════════════════
-- Every masking policy below checks CURRENT_ROLE() against this
-- role (and SYSADMIN). Everyone else — including DATA_ANALYST —
-- sees masked values.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS PII_VIEWER
    COMMENT = 'Authorized to see unmasked PII columns';

GRANT ROLE ECOMMERCE_READ TO ROLE PII_VIEWER;
GRANT ROLE PII_VIEWER     TO ROLE SYSADMIN;
GRANT ROLE PII_VIEWER     TO USER <your_username>;

-- PII_VIEWER inherits warehouse USAGE through ECOMMERCE_READ
-- (granted in Sub-task 4.2 Step 3), so no separate warehouse
-- grant is needed here.

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Write the masking policies
-- ══════════════════════════════════════════════════════════════
-- CREATE OR REPLACE is safe here because nothing is attached to
-- either policy yet. Once Step 4 attaches these to columns,
-- CREATE OR REPLACE stops working on them — see Step 7.

USE ROLE MASKING_ADMIN;
USE SECONDARY ROLES NONE;

-- EMAIL: full mask for everyone except PII_VIEWER and SYSADMIN
CREATE OR REPLACE MASKING POLICY ECOMMERCE.RAW.EMAIL_MASK AS (val STRING)
    RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('PII_VIEWER', 'SYSADMIN') THEN val
        ELSE '***MASKED***'
    END
;

-- PHONE: partial mask — last 4 characters visible, rest redacted
CREATE OR REPLACE MASKING POLICY ECOMMERCE.RAW.PHONE_MASK AS (val STRING)
    RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('PII_VIEWER', 'SYSADMIN') THEN val
        ELSE CONCAT('***-***-', RIGHT(val, 4))
    END
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Attach the policies to columns
-- ══════════════════════════════════════════════════════════════
-- This is the step that actually requires APPLY MASKING POLICY —
-- writing the policy in Step 3 did not.

ALTER TABLE ECOMMERCE.RAW.CUSTOMERS MODIFY COLUMN EMAIL
    SET MASKING POLICY ECOMMERCE.RAW.EMAIL_MASK;

ALTER TABLE ECOMMERCE.RAW.CUSTOMERS MODIFY COLUMN PHONE
    SET MASKING POLICY ECOMMERCE.RAW.PHONE_MASK;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Prove the same query returns different results by role
-- ══════════════════════════════════════════════════════════════

-- As DATA_ANALYST — not named in either policy's CASE logic
USE ROLE DATA_ANALYST;
USE SECONDARY ROLES NONE;

SELECT customer_id, email, phone
FROM ECOMMERCE.RAW.CUSTOMERS
LIMIT 5
;
-- EMAIL fully masked, PHONE shows only the last 4 characters

-- As PII_VIEWER — explicitly named in both policies
USE ROLE PII_VIEWER;
USE SECONDARY ROLES NONE;

SELECT customer_id, email, phone
FROM ECOMMERCE.RAW.CUSTOMERS
LIMIT 5
;
-- Both columns show real values

-- As SYSADMIN — owns the table, but only sees real values because
-- SYSADMIN is explicitly named in the CASE logic, not because of
-- ownership. To confirm ownership alone is not enough: EMAIL_MASK
-- is already attached to a column at this point, so CREATE OR
-- REPLACE will fail (see Step 7) — use ALTER MASKING POLICY ...
-- SET BODY instead to temporarily drop SYSADMIN from the CASE
-- logic, re-run this query (expect a masked result), then use
-- ALTER ... SET BODY again to restore SYSADMIN before continuing.
USE ROLE SYSADMIN;
USE SECONDARY ROLES NONE;

SELECT customer_id, email, phone
FROM ECOMMERCE.RAW.CUSTOMERS
LIMIT 5
;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Confirm what's protected, account-wide
-- ══════════════════════════════════════════════════════════════
-- POLICY_REFERENCES lists every object a given policy is attached
-- to — useful for an audit, and for confirming a policy actually
-- landed where you expect.

SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.POLICY_REFERENCES(
        POLICY_NAME => 'ECOMMERCE.RAW.EMAIL_MASK'
    )
)
;

SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.POLICY_REFERENCES(
        REF_ENTITY_NAME   => 'ECOMMERCE.RAW.CUSTOMERS',
        REF_ENTITY_DOMAIN => 'TABLE'
    )
)
;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Updating a policy that's already attached
-- ══════════════════════════════════════════════════════════════
-- EMAIL_MASK is attached to CUSTOMERS.EMAIL as of Step 4. This
-- step proves CREATE OR REPLACE no longer works on it, then shows
-- the actual fix.

-- DATA_ENGINEER (built in Sub-task 4.3) holds only ECOMMERCE_WRITE
-- — INSERT/UPDATE, no SELECT. This step needs it to query
-- CUSTOMERS, so grant it ECOMMERCE_READ too. Without this, the
-- test below fails with "Insufficient privileges ... must have
-- SELECT granted on TABLE ECOMMERCE.RAW.CUSTOMERS" — a table-
-- privilege gap, unrelated to the masking policy this step is
-- actually testing.
USE ROLE SECURITYADMIN;

GRANT ROLE ECOMMERCE_READ TO ROLE DATA_ENGINEER;

USE ROLE MASKING_ADMIN;
USE SECONDARY ROLES NONE;

-- Expected to FAIL — EMAIL_MASK is associated with a column now
CREATE OR REPLACE MASKING POLICY ECOMMERCE.RAW.EMAIL_MASK AS (val STRING)
    RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('PII_VIEWER', 'SYSADMIN', 'DATA_ENGINEER') THEN val
        ELSE '***MASKED***'
    END
;
-- Error: "Policy EMAIL_MASK cannot be dropped/replaced as it is
-- associated with one or more entities"

-- Correct approach — ALTER MASKING POLICY ... SET BODY updates
-- the logic in place, no unset/reattach needed
ALTER MASKING POLICY ECOMMERCE.RAW.EMAIL_MASK SET BODY ->
    CASE
        WHEN CURRENT_ROLE() IN ('PII_VIEWER', 'SYSADMIN', 'DATA_ENGINEER') THEN val
        ELSE '***MASKED***'
    END
;

-- Confirm the new logic is live immediately — DATA_ENGINEER now
-- sees unmasked EMAIL without any ALTER TABLE statement at all
USE ROLE DATA_ENGINEER;
USE SECONDARY ROLES NONE;

SELECT customer_id, email
FROM ECOMMERCE.RAW.CUSTOMERS
LIMIT 5
;
-- Succeeds unmasked — the policy body changed, not the column
-- attachment

-- Revert EMAIL_MASK back to its original logic, so the rest of
-- Goal 4 (and the Sub-task 4.9 capstone) sees the state this
-- sub-task originally established
USE ROLE MASKING_ADMIN;
USE SECONDARY ROLES NONE;

ALTER MASKING POLICY ECOMMERCE.RAW.EMAIL_MASK SET BODY ->
    CASE
        WHEN CURRENT_ROLE() IN ('PII_VIEWER', 'SYSADMIN') THEN val
        ELSE '***MASKED***'
    END
;

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Write a third masking policy, NAME_MASK, that shows only the
--    first character of CUSTOMERS.FIRST_NAME followed by asterisks
--    (e.g. "Jordan" -> "J*****") for everyone except PII_VIEWER and
--    SYSADMIN. Attach it to both FIRST_NAME and LAST_NAME.
--
-- 2. As DATA_ANALYST, attempt to run the ALTER TABLE ... SET
--    MASKING POLICY statement from Step 4 against a different
--    column. Confirm it fails — DATA_ANALYST was never granted
--    APPLY MASKING POLICY, only SELECT.
--
-- 3. Run the second POLICY_REFERENCES query from Step 6 again
--    after completing exercise 1. Confirm it now lists three
--    columns (EMAIL, PHONE, and whichever name column you picked)
--    instead of two.
--
-- 4. Try ALTER MASKING POLICY ... SET BODY on PHONE_MASK to add a
--    THIRD tier: DATA_ENGINEER sees the last 4 digits (as today),
--    PII_VIEWER/SYSADMIN see the full number, and everyone else
--    sees a full mask instead of a partial one. Confirm the
--    change applies without touching CUSTOMERS.PHONE's attachment
--    at all.
--
-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I own the table — don't I automatically see unmasked
--    data?
-- A: No. Ownership controls who can alter or drop the object, not
--    who sees through its masking policies. Step 5 demonstrates
--    this directly with SYSADMIN, which owns CUSTOMERS but is only
--    unmasked because it's explicitly listed in the CASE logic.
--
-- Q: What if GRANT APPLY MASKING POLICY fails when run as
--    SECURITYADMIN?
-- A: Expected in most accounts — APPLY MASKING POLICY is held only
--    by ACCOUNTADMIN by default, unlike MANAGE GRANTS (Sub-task
--    4.3), which both ACCOUNTADMIN and SECURITYADMIN hold. Run
--    that one GRANT statement as ACCOUNTADMIN specifically — see
--    Step 1 above.
--
-- Q: What if I want a masking policy to apply automatically to
--    columns in tables that don't exist yet?
-- A: It won't. Masking policies cannot be attached via future
--    grants — there is no ON FUTURE TABLES equivalent for SET
--    MASKING POLICY. Each column needs its own explicit ALTER
--    TABLE/VIEW statement, every time a new table needs the same
--    protection. Plan for this in any pipeline that creates tables
--    programmatically.
--
-- Q: What if a role has SELECT on a column but not APPLY MASKING
--    POLICY?
-- A: It can query the column fine — it just always sees the
--    masked result, and cannot itself attach, replace, or remove
--    the policy. SELECT and APPLY MASKING POLICY are governing two
--    completely different actions.
--
-- Q: What if I try to CREATE OR REPLACE (or DROP) a masking policy
--    that's already attached to a column?
-- A: It fails with "Policy <name> cannot be dropped/replaced as it
--    is associated with one or more entities" — see Step 7. Use
--    ALTER MASKING POLICY ... SET BODY to change the logic in
--    place instead. CREATE OR REPLACE only works before a policy
--    has been attached to anything, or after every attachment has
--    been explicitly UNSET first.
--
-- Q: What if I need to temporarily see unmasked data as an
--    ordinary analyst, just once?
-- A: Don't add every analyst to the policy's CASE logic just to
--    debug something. Either switch to a role authorized in the
--    policy (like PII_VIEWER here) for that session, or have
--    someone with that role run the query for you. Loosening a
--    masking policy's CASE logic to solve a one-off problem is a
--    common way protections quietly erode over time.
--
-- Q: What is different from Oracle I should watch for in this
--    sub-task specifically?
-- A: Key differences:
--    · Masking requires Enterprise Edition — Oracle Data Redaction
--      requires the separately licensed Advanced Security option
--    · APPLY MASKING POLICY is a distinct account-level privilege
--      with no direct Oracle parallel — Oracle redaction access is
--      typically controlled through EXEMPT REDACTION POLICY grants
--      per user instead
--    · A Snowflake masking policy is one reusable object attached
--      to many columns; Oracle redaction is usually configured per
--      column through repeated DBMS_REDACT.ADD_POLICY calls
-- ══════════════════════════════════════════════════════════════
