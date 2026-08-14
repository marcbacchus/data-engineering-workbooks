-- ══════════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 7       : Share and Collaborate
-- Sub-task 7.1 : Share data between Snowflake accounts
-- ══════════════════════════════════════════════════════════════════
-- ──────────────────────────────────────────────────────────────────
-- Time to complete : 30-40 min
-- Warehouse size    : WORKBOOK_WH (X-Small)
-- Database          : ECOMMERCE
-- Run in            : Snowsight
-- Prerequisites     : Goals 1-6 complete. ACCOUNTADMIN role available.
-- COF-C03 domain    : 5.0 Data Collaboration (10%)
-- ──────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════
-- You are going to give another Snowflake account live, read-only
-- access to a slice of ECOMMERCE data -- without copying a single
-- byte of it anywhere. You'll do this the way most real providers do
-- it when the consumer doesn't already have their own Snowflake
-- account: by spinning up a managed READER account, creating a
-- SHARE, granting the share access to a secure view, and adding the
-- reader account as a consumer of that share.
--
-- By the end you will have logged into the reader account from a
-- separate browser tab and queried live ECOMMERCE data through the
-- share -- then torn the whole thing down.

-- ══════════════════════════════════════════════════════════════════
-- CONCEPT
-- ══════════════════════════════════════════════════════════════════
-- A SHARE is a named Snowflake object that packages up privileges on
-- a database, schema, and specific objects (tables, secure views,
-- secure UDFs) and makes them visible to another Snowflake account.
-- Nothing is copied or moved. The consumer account queries the same
-- physical micro-partitions the provider owns, through Snowflake's
-- metadata layer -- this is why sharing has effectively zero storage
-- cost for the provider and zero load time for the consumer.
--
-- Two kinds of consumer:
--   FULL ACCOUNT   -- an existing Snowflake account (their own org)
--                      consumes your share alongside their own data.
--   READER ACCOUNT -- a lightweight account YOU create and manage,
--                      for a consumer who has no Snowflake account of
--                      their own. You pay for its compute; they get a
--                      login and nothing else to set up.
--
-- What CAN go into a share: tables, secure views, secure materialized
-- views, secure UDFs.
-- What CANNOT go into a share: regular (non-secure) views, stages,
-- file formats, tasks, streams, or anything with embedded business
-- logic you don't want the consumer to see the definition of.
--
-- That "secure" prefix matters: a secure view hides its own query
-- definition from anyone who doesn't own it -- including a share
-- consumer. This is the sharing analog of the row access policies
-- and masking policies you built in Goal 4: same instinct (don't
-- expose more than the consumer needs), different enforcement point.
--
-- ── Oracle / SQL Server comparison ──────────────────────────────
-- Neither Oracle nor SQL Server has a native equivalent to zero-copy
-- sharing. The closest analogs are physical: Oracle GoldenGate or
-- transactional replication in SQL Server, both of which physically
-- copy data to the consumer, cost storage on both sides, run on a
-- refresh/replication lag, and require the consumer to already have
-- a licensed database instance. Snowflake's share consumer sees data
-- that is live to the second, with no second copy anywhere.
-- ─────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════
-- ⚠️  COST WARNING
-- ══════════════════════════════════════════════════════════════════
-- A managed reader account has its own virtual warehouse and runs on
-- YOUR account's credits whenever it's queried. It is a real,
-- persistent, billable object -- not something per-task suspend
-- covers. This sub-task ends with an explicit teardown (STEP 6).
-- Do not skip it.

-- ══════════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════════
-- STEP 1: Build a secure view to expose (don't share raw tables directly)
-- ══════════════════════════════════════════════════════════════════
-- Sharing the whole CUSTOMERS table would hand the consumer PII you
-- likely don't want to expose. A secure view narrows and hides.

CREATE OR REPLACE SECURE VIEW ECOMMERCE.RAW.SHARED_CUSTOMER_SUMMARY AS
SELECT
    c.customer_id,
    c.created_at,
    c.country,
    COUNT(o.order_id)          AS total_orders,
    SUM(o.order_total)         AS lifetime_value
FROM ECOMMERCE.RAW.CUSTOMERS c
LEFT JOIN ECOMMERCE.RAW.ORDERS o
    ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.created_at, c.country;

-- ══════════════════════════════════════════════════════════════════
-- STEP 2: Create the share and grant it access
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE SHARE ECOMMERCE_CUSTOMER_SHARE
    COMMENT = 'Read-only customer summary for workbook Goal 7.1';

-- A share needs USAGE on every container level, same rule as any
-- other principal (see Goal 4 discovery: database, schema, AND
-- warehouse are three independent grants -- warehouses are never
-- granted to shares since compute always runs on the consumer side).
GRANT USAGE ON DATABASE ECOMMERCE TO SHARE ECOMMERCE_CUSTOMER_SHARE;
GRANT USAGE ON SCHEMA ECOMMERCE.RAW TO SHARE ECOMMERCE_CUSTOMER_SHARE;
GRANT SELECT ON VIEW ECOMMERCE.RAW.SHARED_CUSTOMER_SUMMARY
    TO SHARE ECOMMERCE_CUSTOMER_SHARE;

-- Confirm what the share currently exposes
SHOW GRANTS TO SHARE ECOMMERCE_CUSTOMER_SHARE;

-- ══════════════════════════════════════════════════════════════════
-- STEP 3: Create a managed reader account as the consumer
-- ══════════════════════════════════════════════════════════════════
-- <placeholder_reader_account> -- pick a short, lowercase, unique
-- account name (letters/numbers/underscores only).
-- <placeholder_admin_user> / <placeholder_admin_password> -- the
-- login you will use to sign into the reader account in STEP 5.
--
-- Password policy: even with no custom PASSWORD POLICY object set,
-- Snowflake's account-default policy still applies and WILL reject
-- ADMIN_PASSWORD if it doesn't meet these minimums:
--   MIN_LENGTH            8
--   MIN_UPPER_CASE_CHARS   1
--   MIN_LOWER_CASE_CHARS   1
--   MIN_NUMERIC_CHARS      1
--   MIN_SPECIAL_CHARS      0  (not required by default, but allowed)
-- Confirmed live: MIN_LENGTH and MIN_LOWERCASE errors both hit on a
-- first attempt with a short/all-caps placeholder. Something like
-- <placeholder_admin_password> -> Workbook7Share should clear all of
-- the above. Check your account's actual policy first if unsure:
--   DESCRIBE PASSWORD POLICY SNOWFLAKE.ACCOUNT_DEFAULT_PASSWORD_POLICY;

CREATE MANAGED ACCOUNT <placeholder_reader_account>
    ADMIN_NAME     = '<placeholder_admin_user>'
    ADMIN_PASSWORD = '<placeholder_admin_password>'
    TYPE           = READER
    COMMENT        = 'Workbook Goal 7.1 -- reader account for share demo';

-- Get the reader account's login URL and locator
SHOW MANAGED ACCOUNTS LIKE '<placeholder_reader_account>';

-- ══════════════════════════════════════════════════════════════════
-- STEP 4: Add the reader account as a consumer of the share
-- ══════════════════════════════════════════════════════════════════
-- IMPORTANT: the name you gave CREATE MANAGED ACCOUNT in STEP 3 is
-- only an identifier -- it is NOT the value ADD ACCOUNTS needs.
-- Snowflake assigns the reader account its own separate account
-- name/locator. Pull the real value from SHOW MANAGED ACCOUNTS
-- first, or ADD ACCOUNTS will fail with:
--   "Following accounts cannot be added to this share: <name>."

SHOW MANAGED ACCOUNTS LIKE '<placeholder_reader_account>';
-- Look for the "locator" column in the output above (a short
-- alphanumeric string like RE47190) -- that is the value ADD
-- ACCOUNTS needs. It is NOT the "name" column, which just echoes
-- back the identifier you chose in STEP 3 (SHARED_TEST_ACCOUNT) --
-- that identifier is never accepted by ADD ACCOUNTS and will fail
-- with "Following accounts cannot be added to this share."

-- ACCOUNTS takes an identifier, not a string literal -- do not quote
-- it. Since the reader account lives in the same organization as
-- this provider account, the bare locator is enough (no orgname.
-- prefix needed). A cross-org share would need orgname.accountname
-- instead, still unquoted.
ALTER SHARE ECOMMERCE_CUSTOMER_SHARE
    ADD ACCOUNTS = <placeholder_reader_account_locator>;

-- NOTE: SHOW GRANTS OF SHARE lists accounts that have already run
-- CREATE DATABASE FROM SHARE -- i.e. accounts actively consuming the
-- share. It will correctly return ZERO rows at this point, since
-- STEP 5 (where the reader account consumes it) hasn't happened yet.
-- This is expected, not a latency issue.
--
-- To confirm ADD ACCOUNTS itself worked, use SHOW SHARES instead --
-- it lists accounts a share is available TO, whether or not they've
-- consumed it yet. Check the "to" column for the reader locator:
SHOW SHARES LIKE 'ECOMMERCE_CUSTOMER_SHARE';

-- ══════════════════════════════════════════════════════════════════
-- STEP 5: Consume the share from the reader account (live -- separate tab)
-- ══════════════════════════════════════════════════════════════════
-- Open the login URL from STEP 3's SHOW output, and sign in with the
-- admin user/password you set above.
--
-- NOTE: a plain second tab in the same browser will often silently
-- reuse your provider account's Snowsight session instead of
-- prompting a fresh login for the reader account. Use an incognito/
-- private window (or a separate browser entirely) for the reader
-- account login to avoid this -- confirmed live.
--
-- Run the following FROM INSIDE THE READER ACCOUNT:

-- Run in reader account:
-- SHOW SHARES;
-- Look at the "owner" column in the results -- it shows the exact
-- org_name.account_name of the provider (e.g. WKLFKIU.APB83925),
-- already in the correct format for the FROM SHARE clause below.
-- Do NOT use CURRENT_ACCOUNT() from the provider side for this --
-- it returns only the bare account locator, not the org-qualified
-- name, and will fail with "Share does not exist or not authorized."
--
-- CREATE DATABASE SHARED_ECOMMERCE FROM SHARE
--     <placeholder_provider_org>.<placeholder_provider_account>.ECOMMERCE_CUSTOMER_SHARE;
--
-- A brand-new reader account has NO default warehouse -- it's an
-- empty account with its own compute, billed to your provider
-- account. Create one before querying, or you'll hit:
--   "No active warehouse selected in the current session."
--
-- CREATE WAREHOUSE READER_WH WITH WAREHOUSE_SIZE = 'XSMALL'
--     AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
-- USE WAREHOUSE READER_WH;
--
-- SELECT * FROM SHARED_ECOMMERCE.RAW.SHARED_CUSTOMER_SUMMARY
-- LIMIT 10;
--
-- ⚠️ READER_WH is a real, separate billable object in the reader
-- account -- add it to the STEP 6 teardown below (DROP WAREHOUSE),
-- same cost discipline as the managed account itself.

-- ══════════════════════════════════════════════════════════════════
-- STEP 5.5: If STEP 5 returned zero rows -- check for a row access policy
-- ══════════════════════════════════════════════════════════════════
-- SHARED_CUSTOMER_SUMMARY is built on ECOMMERCE.RAW.CUSTOMERS, which
-- (from Goal 4) may carry REGION_ACCESS_POLICY. That policy's
-- condition uses IS_ROLE_IN_SESSION() to decide access -- and in a
-- cross-account share query, the reader account has no session role
-- matching anything the policy checks for. Every branch falls
-- through to ELSE FALSE. Result: zero rows, no error. This is a real
-- interaction between Goal 4 and Goal 7, not a bug in the steps
-- above -- confirmed live.
--
-- Check first (provider account):
SELECT *
FROM TABLE(
  ECOMMERCE.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME   => 'ECOMMERCE.RAW.CUSTOMERS',
    REF_ENTITY_DOMAIN => 'TABLE'
  )
);

-- If REGION_ACCESS_POLICY shows up, drop it temporarily to let this
-- demo run, then re-attach immediately after (provider account).
-- Note: row access policies use DROP/ADD, not SET/UNSET -- UNSET is
-- for masking policies only, confirmed via live syntax error.
-- Fully qualify the policy name -- an unqualified name resolves
-- against your session's CURRENT SCHEMA, which may not be RAW,
-- and fails with "does not exist or not authorized" even though
-- the policy exists and you're on the right role.
ALTER TABLE ECOMMERCE.RAW.CUSTOMERS
    DROP ROW ACCESS POLICY ECOMMERCE.RAW.REGION_ACCESS_POLICY;

-- Re-run the SELECT from the reader account (STEP 5) -- it should
-- now return rows.

-- Put the policy back once you've confirmed the share works --
-- do not skip this, per the "flag it, test it, put it back" rule
-- from Goal 4/6:
ALTER TABLE ECOMMERCE.RAW.CUSTOMERS
    ADD ROW ACCESS POLICY ECOMMERCE.RAW.REGION_ACCESS_POLICY ON (REGION);

-- ══════════════════════════════════════════════════════════════════
-- STEP 6: Tear down -- required, see cost warning above
-- ══════════════════════════════════════════════════════════════════

-- From the reader account first (optional but tidy):
-- DROP DATABASE IF EXISTS SHARED_ECOMMERCE;
-- DROP WAREHOUSE IF EXISTS READER_WH;

-- Back in the provider account (use the same account_name/locator
-- from STEP 4, not the STEP 3 identifier):
ALTER SHARE ECOMMERCE_CUSTOMER_SHARE
    REMOVE ACCOUNTS = <placeholder_reader_account_locator>;

DROP SHARE IF EXISTS ECOMMERCE_CUSTOMER_SHARE;

DROP MANAGED ACCOUNT IF EXISTS <placeholder_reader_account>;

-- Confirm both are gone
SHOW SHARES LIKE 'ECOMMERCE_CUSTOMER_SHARE';
SHOW MANAGED ACCOUNTS LIKE '<placeholder_reader_account>';

-- ══════════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════
-- 1. Create a second secure view -- ORDER_ITEMS aggregated by product
--    category -- and add it to the same share without recreating the
--    share from scratch.
-- 2. Try granting SELECT on the raw ORDERS table directly to the
--    share instead of a secure view. Query it from the reader
--    account and note exactly which columns are now exposed that
--    weren't in SHARED_CUSTOMER_SUMMARY.
-- 3. Run DESCRIBE SHARE ECOMMERCE_CUSTOMER_SHARE before tearing
--    down, and compare its output to SHOW GRANTS TO SHARE.

-- ══════════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════════
-- Q: What if the consumer already has their own Snowflake account?
-- A: Skip the managed account entirely. ALTER SHARE ... ADD ACCOUNTS
--    takes their account identifier directly, and they run
--    CREATE DATABASE FROM SHARE against your share the same way
--    STEP 5 does -- no reader account, no admin credentials to
--    manage, and they pay for their own compute.
--
-- Q: What if I update SHARED_CUSTOMER_SUMMARY's definition after the
--    consumer has already mounted it?
-- A: They see the change immediately, no re-grant needed. The
--    consumer's CREATE DATABASE FROM SHARE just points at your
--    share's current object set -- there's nothing to refresh
--    because nothing was ever copied.
--
-- Q: What if I DROP the secure view without removing it from the
--    share first?
-- A: The share silently loses that object. The consumer's queries
--    against it start failing with an object-not-found error --
--    Snowflake does not warn you or block the DROP. Always check
--    SHOW GRANTS TO SHARE before dropping anything a share depends on.
--
-- Q: What if I need to share with someone in a different cloud
--    region or a different cloud provider entirely (AWS -> Azure)?
-- A: Direct sharing only works within the same region and cloud
--    platform. Cross-region or cross-cloud sharing requires database
--    replication first (a Goal 8 topic) to get a copy of the data
--    into a matching region, and you share the replica from there.
--
-- Q: What if a shared table/view has a row access policy that uses
--    CURRENT_ROLE(), CURRENT_USER(), or IS_ROLE_IN_SESSION()?
-- A: Those functions evaluate to NULL (or effectively "no match") in
--    a cross-account query -- the reader account has no session role
--    that exists in your account's role hierarchy. If the policy's
--    condition doesn't have an explicit branch for that case, every
--    row is filtered and the consumer gets zero rows with no error.
--    Confirmed live in this sub-task against Goal 4's
--    REGION_ACCESS_POLICY. The durable fix (not just for this demo)
--    is to write policy conditions for shared objects around
--    CURRENT_ACCOUNT() instead, which stays populated across
--    accounts -- see "Dynamic Row-Level Security Across Snowflake
--    Accounts" pattern for the general approach if you need row
--    filtering that actually works for share consumers.
