-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Sub-task 4.8 : Secure views
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~35 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Sub-tasks 4.1-4.7 complete
-- COF-C03 domain   : Domain 4 — Data Governance and Security (23%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Every mechanism so far in Goal 4 controls access to a TABLE
--   directly. A secure view is a different lever entirely: instead
--   of granting someone access to the table, you grant them access
--   to a VIEW that queries the table on their behalf — using the
--   VIEW OWNER's privileges, not theirs. This sub-task proves that
--   directly: a role with ZERO access to CUSTOMERS or ORDERS can
--   still query a secure view built on top of them.
--
--   It also answers a question the last four sub-tasks raise
--   naturally: does wrapping a table in a view let you bypass its
--   masking and row access policies? No — and proving that is the
--   other half of this sub-task.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: SECURE VIEWS AND OWNER'S RIGHTS
-- ══════════════════════════════════════════════════════════════
--
-- Any view — secure or not — runs with the OWNER'S privileges on
-- the underlying tables, not the querying role's. A role only
-- needs SELECT on the VIEW itself; it never needs SELECT on
-- CUSTOMERS or ORDERS directly. This is the single most useful
-- property of views as a security mechanism: you can hand someone
-- a narrow, purpose-built window into data they could never query
-- directly, without touching the base table's grants at all.
--
-- A SECURE view adds two protections a regular view does not have:
--
--   1. Its DEFINITION is hidden from anyone except the owner (or
--      an account-level auditor role). SHOW VIEWS and GET_DDL
--      return nothing useful to a non-owner — even the query
--      itself is redacted from things like Query Profile.
--   2. Snowflake DISABLES certain query-optimization shortcuts for
--      secure views specifically, because those shortcuts could
--      otherwise let a sufficiently clever query infer filtered-
--      out data through query plan or timing side channels. A
--      regular view does not get this protection.
--
-- A regular view is still a real access-control tool (owner's
-- rights alone is powerful) — SECURE is specifically for when the
-- view's own logic (a WHERE clause, a join condition) is itself
-- sensitive and shouldn't be visible to whoever you grant it to.
--
-- ── This does NOT bypass masking or row access policies ───────
-- Owner's rights only governs whether the QUERYING role needs
-- privileges on the base table. It has no effect on masking or row
-- access policies, because those evaluate CURRENT_ROLE() — the
-- actual querying role — not the view owner's role. Querying
-- CUSTOMERS through a view still applies every masking and row
-- access policy attached to CUSTOMERS, exactly as if the view
-- didn't exist. Step 7 below proves this directly: owner's rights
-- gets a role PAST the missing table grant, but row access still
-- filters the result down to nothing if that role isn't mapped to
-- any region.
-- ─────────────────────────────────────────────────────────────
--
-- ── No account-level privilege required — unlike every prior
--    sub-task in this goal ──────────────────────────────────────
-- CREATE VIEW (secure or not) is an ordinary schema-level
-- privilege, auto-granted to the schema owner like CREATE TABLE.
-- There is no APPLY-style global privilege gatekeeping secure
-- views the way APPLY MASKING POLICY, APPLY ROW ACCESS POLICY,
-- APPLY TAG, and CREATE NETWORK POLICY all required in Sub-tasks
-- 4.4-4.7. This sub-task never touches ACCOUNTADMIN at all —
-- worth noticing after four sub-tasks in a row that did.
-- ─────────────────────────────────────────────────────────────
--
-- ── CREATE OR REPLACE VIEW silently drops existing grants ─────
-- Unlike the "fails outright once attached" pattern from masking/
-- row access policies/network rules (Sub-tasks 4.4-4.7), replacing
-- a view does NOT fail — it succeeds, but SILENTLY drops every
-- privilege previously granted on it, unless you add COPY GRANTS
-- to the statement. This is a different failure mode entirely: no
-- error, just quietly broken access for everyone who had it,
-- discovered only when someone reports they can no longer query
-- something that worked yesterday. Step 8 demonstrates this.
-- ─────────────────────────────────────────────────────────────
--
-- ── Oracle / SQL Server comparison ───────────────────────────
-- Oracle views also execute with the view owner's (definer's)
-- privileges by default — this part is genuinely similar. Secure
-- views' hidden-definition behavior is closer to wrapping a view
-- in Oracle's DBMS_RLS-protected object or restricting DBA_VIEWS/
-- ALL_VIEWS visibility through careful grants — Snowflake's SECURE
-- keyword bundles that protection into the object itself, rather
-- than requiring separate configuration of catalog visibility.
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
-- STEP 1: Create a view administrator role
-- ══════════════════════════════════════════════════════════════
-- Notice this whole step runs under SYSADMIN alone — no
-- ACCOUNTADMIN switch anywhere, unlike Sub-tasks 4.4-4.7.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS VIEW_ADMIN
    COMMENT = 'Creates and maintains views over ECOMMERCE.RAW';

GRANT ROLE VIEW_ADMIN TO ROLE SYSADMIN;
GRANT ROLE VIEW_ADMIN TO USER <your_username>;

-- VIEW_ADMIN needs real SELECT access on the tables it will build
-- views over — Snowflake validates a view's definition against the
-- CREATING role's privileges at creation time. This is different
-- from who gets to USE the finished view (owner's rights, per
-- CONCEPT above) — the creator still needs ordinary table access
-- to write and validate the view in the first place.
GRANT ROLE ECOMMERCE_READ TO ROLE VIEW_ADMIN;

USE ROLE SYSADMIN;

GRANT USAGE ON DATABASE ECOMMERCE     TO ROLE VIEW_ADMIN;
GRANT USAGE ON SCHEMA   ECOMMERCE.RAW TO ROLE VIEW_ADMIN;
GRANT USAGE ON WAREHOUSE WORKBOOK_WH  TO ROLE VIEW_ADMIN;
GRANT CREATE VIEW ON SCHEMA ECOMMERCE.RAW TO ROLE VIEW_ADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create a role with ZERO base table access
-- ══════════════════════════════════════════════════════════════
-- Deliberately does NOT hold ECOMMERCE_READ. This is what proves
-- owner's rights in Step 7 — if this role can query a view built
-- on CUSTOMERS/ORDERS despite this, it's the view's ownership
-- doing the work, not any grant this role holds itself.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS VIEW_ONLY_ANALYST
    COMMENT = 'Holds no base table access — sees data only through granted views';

GRANT ROLE VIEW_ONLY_ANALYST TO ROLE SYSADMIN;
GRANT ROLE VIEW_ONLY_ANALYST TO USER <your_username>;

USE ROLE SYSADMIN;

GRANT USAGE ON DATABASE ECOMMERCE     TO ROLE VIEW_ONLY_ANALYST;
GRANT USAGE ON SCHEMA   ECOMMERCE.RAW TO ROLE VIEW_ONLY_ANALYST;
GRANT USAGE ON WAREHOUSE WORKBOOK_WH  TO ROLE VIEW_ONLY_ANALYST;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Create a baseline — a REGULAR (non-secure) view
-- ══════════════════════════════════════════════════════════════

USE ROLE VIEW_ADMIN;
USE SECONDARY ROLES NONE;

CREATE OR REPLACE VIEW ECOMMERCE.RAW.REGIONAL_ORDERS_VIEW AS
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email,
        c.phone,
        c.region,
        o.order_id,
        o.order_total
    FROM ECOMMERCE.RAW.CUSTOMERS c
    JOIN ECOMMERCE.RAW.ORDERS o
        ON c.customer_id = o.customer_id
;

USE ROLE SYSADMIN;

GRANT SELECT ON VIEW ECOMMERCE.RAW.REGIONAL_ORDERS_VIEW TO ROLE VIEW_ONLY_ANALYST;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: See a regular view's definition as a non-owner
-- ══════════════════════════════════════════════════════════════

USE ROLE VIEW_ONLY_ANALYST;
USE SECONDARY ROLES NONE;

-- Succeeds — the definition is fully visible to anyone with USAGE
-- on the schema, regardless of whether they own it
SELECT GET_DDL('VIEW', 'ECOMMERCE.RAW.REGIONAL_ORDERS_VIEW')
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Create the SECURE equivalent
-- ══════════════════════════════════════════════════════════════

USE ROLE VIEW_ADMIN;
USE SECONDARY ROLES NONE;

CREATE OR REPLACE SECURE VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE AS
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email,
        c.phone,
        c.region,
        o.order_id,
        o.order_total
    FROM ECOMMERCE.RAW.CUSTOMERS c
    JOIN ECOMMERCE.RAW.ORDERS o
        ON c.customer_id = o.customer_id
;

USE ROLE SYSADMIN;

GRANT SELECT ON VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE TO ROLE VIEW_ONLY_ANALYST;

-- Also granted to ECOMMERCE_READ, not just VIEW_ONLY_ANALYST — this
-- means every role that already holds ECOMMERCE_READ (all five
-- regional analysts, MANAGER, DATA_ANALYST) automatically inherits
-- access to this view too, consistent with the access-role pattern
-- from Sub-task 4.2. Needed for Step 8 below.
GRANT SELECT ON VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE TO ROLE ECOMMERCE_READ;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Same GET_DDL attempt — now blocked
-- ══════════════════════════════════════════════════════════════

USE ROLE VIEW_ONLY_ANALYST;
USE SECONDARY ROLES NONE;

-- Errors outright — "Object does not exist, or operation cannot
-- be performed" — rather than returning NULL or a redacted
-- result. Secure view definitions are restricted to the OWNER
-- only (or an account-level auditor via ACCOUNTADMIN or the
-- SNOWFLAKE.OBJECT_VIEWER database role) — a non-owner's GET_DDL
-- call is treated as if the object doesn't exist at all, not as
-- a partial/empty answer. Same role, same command as Step 4,
-- opposite result, purely because SECURE is set.
SELECT GET_DDL('VIEW', 'ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE')
;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Prove owner's rights — AND its limit
-- ══════════════════════════════════════════════════════════════

-- Expected to FAIL — VIEW_ONLY_ANALYST has no grant on CUSTOMERS
-- at all, direct or inherited
SELECT COUNT(*) FROM ECOMMERCE.RAW.CUSTOMERS
;

-- Succeeds — owner's rights means SELECT on the VIEW is enough,
-- even with zero access to the underlying tables
SELECT customer_id, first_name, last_name, region
FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- But returns ZERO ROWS — the row access policy on CUSTOMERS.REGION
-- still evaluates CURRENT_ROLE(), which is VIEW_ONLY_ANALYST here,
-- not the view's owner. VIEW_ONLY_ANALYST isn't in
-- REGION_ACCESS_MAP, isn't MANAGER, isn't SYSADMIN — so it sees
-- nothing, exactly as it would querying CUSTOMERS directly if it
-- had been granted access. Owner's rights got this role PAST the
-- missing table grant; it did not get it past the row access
-- policy.

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Confirm policies still apply for a role that CAN see
--         rows
-- ══════════════════════════════════════════════════════════════

USE ROLE ANALYST_EUROPE;
USE SECONDARY ROLES NONE;

SELECT customer_id, first_name, last_name, email, phone, region
FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- Europe rows only (row access policy), names masked to first-
-- character-plus-asterisks (tag-driven masking), email fully
-- masked, phone partially masked — every policy from Sub-tasks
-- 4.4-4.6 still applies, unchanged, through the secure view

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 9: CREATE OR REPLACE silently drops grants — see it happen
-- ══════════════════════════════════════════════════════════════

SHOW GRANTS ON VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- VIEW_ONLY_ANALYST's SELECT grant is here — note it before the
-- replace below

USE ROLE VIEW_ADMIN;
USE SECONDARY ROLES NONE;

-- Replacing WITHOUT copy grants — no error, but watch what happens
-- to the grant above
CREATE OR REPLACE SECURE VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE AS
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email,
        c.phone,
        c.region,
        o.order_id,
        o.order_total,
        o.order_status
    FROM ECOMMERCE.RAW.CUSTOMERS c
    JOIN ECOMMERCE.RAW.ORDERS o
        ON c.customer_id = o.customer_id
;

USE ROLE SYSADMIN;

SHOW GRANTS ON VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- VIEW_ONLY_ANALYST's grant is GONE — no error was ever raised.
-- Confirm the impact directly:

USE ROLE VIEW_ONLY_ANALYST;
USE SECONDARY ROLES NONE;

-- Fails now — the grant this role depended on silently vanished
-- when the view was replaced
SELECT customer_id FROM ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;

-- In a real incident, this is the point where someone notices and
-- re-grants access — but doing so manually every time a view gets
-- replaced is exactly the problem COPY GRANTS solves. Re-grant now
-- so the COPY GRANTS replace below has something real to preserve:
USE ROLE SYSADMIN;

GRANT SELECT ON VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE TO ROLE VIEW_ONLY_ANALYST;
GRANT SELECT ON VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE TO ROLE ECOMMERCE_READ;

-- Fix: redo the replace WITH COPY GRANTS, which restores this
USE ROLE VIEW_ADMIN;
USE SECONDARY ROLES NONE;

CREATE OR REPLACE SECURE VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
    COPY GRANTS AS
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email,
        c.phone,
        c.region,
        o.order_id,
        o.order_total,
        o.order_status
    FROM ECOMMERCE.RAW.CUSTOMERS c
    JOIN ECOMMERCE.RAW.ORDERS o
        ON c.customer_id = o.customer_id
;

USE ROLE SYSADMIN;

SHOW GRANTS ON VIEW ECOMMERCE.RAW.CUSTOMER_ORDERS_SECURE
;
-- Both grants are back — this time COPY GRANTS had something real
-- to copy from, since they were re-granted just above. Compare
-- this to the first replace in this step: without a re-grant in
-- between, COPY GRANTS would have had nothing to preserve either —
-- it only protects grants that exist AT THE MOMENT of the replace,
-- not any historical state from before the previous replace.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Query INFORMATION_SCHEMA.VIEWS for ECOMMERCE.RAW and check
--    the IS_SECURE column. Confirm REGIONAL_ORDERS_VIEW shows
--    FALSE and CUSTOMER_ORDERS_SECURE shows TRUE — this is the
--    audit-friendly way to inventory which views in a schema are
--    secure without checking each one's DDL by hand.
--
-- 2. As SYSADMIN (which IS explicitly named in both the row access
--    policy and the relevant masking policies), query
--    CUSTOMER_ORDERS_SECURE and confirm you see every region,
--    fully unmasked — the same "explicitly named, not exempt via
--    ownership" principle from Sub-task 4.4, now demonstrated
--    through a view instead of a raw table query.
--
-- 3. Grant VIEW_ONLY_ANALYST role ECOMMERCE_READ (Sub-task 4.2)
--    directly, then re-run Step 7's CUSTOMERS query as
--    VIEW_ONLY_ANALYST. Confirm it now succeeds directly against
--    the table — then revoke ECOMMERCE_READ again afterward to
--    leave VIEW_ONLY_ANALYST in its original zero-base-access
--    state for anyone re-running this file later.
--
-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if a role has SELECT on a secure view but not on the
--    tables it queries?
-- A: That's the entire point — see Step 7. A view runs with the
--    OWNER's privileges on the base tables, not the querying
--    role's. This is true of any view, not just secure ones.
--
-- Q: What if I need to see a secure view's definition and I'm not
--    the owner?
-- A: You need either the OWNERSHIP privilege on the view itself,
--    or (for auditing across an account) the ACCOUNTADMIN role or
--    the SNOWFLAKE.OBJECT_VIEWER database role, which exists
--    specifically so an auditor doesn't need full ACCOUNTADMIN
--    just to review view definitions.
--
-- Q: What if I replace a secure view and existing grantees suddenly
--    can't query it anymore, with no error anywhere?
-- A: CREATE OR REPLACE VIEW silently drops existing grants unless
--    COPY GRANTS is included — see Step 9. This has no error
--    message at replace time; it just quietly breaks downstream
--    access. Make COPY GRANTS a habit on every CREATE OR REPLACE
--    VIEW against an object that already has grantees.
--
-- Q: What if grants were ALREADY dropped by an earlier replace —
--    will COPY GRANTS on a LATER replace bring them back?
-- A: No. COPY GRANTS only preserves whatever grants exist on the
--    object AT THE MOMENT that specific replace statement runs —
--    it has no memory of grants from before a previous replace
--    already wiped them out. If access was already lost, someone
--    has to re-grant it explicitly first; COPY GRANTS on the next
--    replace will then correctly preserve THAT re-grant going
--    forward, but it cannot resurrect something already gone.
--    Step 9 demonstrates this explicitly with a re-grant in
--    between the two replace statements, for exactly this reason.
--
-- Q: What if I want to use a secure view to grant NARROWER access
--    than the base table's masking/row access policies already
--    provide?
-- A: That works — a secure view's own WHERE clause or column list
--    can restrict further (e.g. exclude ORDER_TOTAL entirely, or
--    add an additional WHERE region = 'Europe' hardcoded). It
--    cannot, however, grant BROADER access than the base table's
--    policies allow for that querying role — masking and row
--    access still evaluate CURRENT_ROLE() underneath, regardless
--    of what the view's own SQL says.
--
-- Q: What is different from Oracle I should watch for in this
--    sub-task specifically?
-- A: Key differences:
--    · Definer's rights views are similar in both, but Snowflake's
--      SECURE keyword bundles hidden-definition protection into
--      the object itself, rather than relying on separately
--      restricting catalog view (DBA_VIEWS/ALL_VIEWS) access
--    · No account-level APPLY-style privilege gates view creation
--      in Snowflake — a genuine contrast with masking/row access/
--      tag/network policies (Sub-tasks 4.4-4.7), all of which
--      required an ACCOUNTADMIN-held global privilege
--    · Oracle's CREATE OR REPLACE VIEW keeps existing grants by
--      default — the opposite of Snowflake's default behavior.
--      Oracle only loses grants if you explicitly DROP the view
--      and then CREATE it fresh, which is a deliberate two-step
--      action, not a side effect of the normal replace path.
--      Snowflake inverts this: CREATE OR REPLACE VIEW drops grants
--      unless you remember to add COPY GRANTS — the safer default
--      is the one you have to opt into, not the one you get for
--      free. Worth being extra careful here specifically if you're
--      coming from Oracle and assuming the familiar command name
--      behaves the same way underneath.
-- ══════════════════════════════════════════════════════════════
