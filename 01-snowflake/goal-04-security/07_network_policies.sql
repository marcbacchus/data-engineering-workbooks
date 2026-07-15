-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Sub-task 4.7 : Network policies
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~45 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Sub-tasks 4.1-4.6 complete
-- COF-C03 domain   : Domain 4 — Data Governance and Security (23%)
--
-- ⚠ THIS SUB-TASK IS DIFFERENT FROM EVERY OTHER ONE IN GOAL 4.
--   A masking policy or row access policy mistake shows you wrong
--   DATA. A network policy mistake activated at the wrong scope
--   can lock you — or every user in the account — out of
--   Snowflake entirely, sometimes requiring Snowflake Support to
--   resolve. This sub-task deliberately BUILDS and TESTS a network
--   policy without ever activating it at the account level or on
--   your own real user. Activation is demonstrated on a disposable
--   throwaway user instead. Read Step 5's warning before running
--   it.
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Every policy so far in Goal 4 controls access to DATA once
--   someone is already logged in. A network policy controls
--   whether someone can log in AT ALL, based on where their
--   connection is coming from — an IP address or CIDR range.
--
--   This sub-task builds an allow-list/block-list network policy
--   using network rules (the modern, reusable building block), then
--   tests it safely with Snowflake's non-disruptive simulation
--   tooling before ever activating anything for real.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: NETWORK RULES AND NETWORK POLICIES
-- ══════════════════════════════════════════════════════════════
--
-- A NETWORK RULE is a schema-level object — a named, reusable list
-- of IP addresses/CIDR ranges (or other identifier types). A
-- NETWORK POLICY is an ACCOUNT-level object that bundles network
-- rules (or raw IP lists, the older syntax) into an ALLOWED list
-- and a BLOCKED list. The policy itself does nothing until it's
-- ACTIVATED — associated with the account, a specific user, or a
-- security integration.
--
-- Privileges, and where they differ from every prior sub-task:
--
--   CREATE NETWORK RULE     schema-level — auto-granted to the
--                            schema owner (SYSADMIN), same pattern
--                            as CREATE MASKING/ROW ACCESS POLICY/
--                            TAG in Sub-tasks 4.4-4.6
--   CREATE NETWORK POLICY   GLOBAL — unlike those schema-level
--                            CREATE privileges, this one is NOT
--                            schema-owner-granted at all, because
--                            a network policy isn't a schema
--                            object. Only SECURITYADMIN (or
--                            higher) holds it by default, or a
--                            role explicitly granted the privilege.
--   ATTACH POLICY            GLOBAL — required to activate a
--                            network policy at the ACCOUNT level.
--                            Same ACCOUNTADMIN/SECURITYADMIN-only
--                            default as CREATE NETWORK POLICY.
--
-- Activating a network policy for an individual USER needs neither
-- of the above — it needs OWNERSHIP on both the target user and
-- the network policy (or a role higher than both owners).
--
-- ── Precedence: most specific wins, nothing merges ────────────
-- If a user-level network policy exists for a user, Snowflake uses
-- ONLY that policy for their login — it does not also consult the
-- account-level policy. If no user-level policy exists, Snowflake
-- falls back to any integration-level policy, then the account-
-- level policy. Only one policy applies at a time, at whichever
-- level is most specific.
--
-- Within a single policy, if an IP matches both the ALLOWED and
-- BLOCKED lists, BLOCKED wins.
-- ─────────────────────────────────────────────────────────────
--
-- ── Snowflake's built-in guardrail — and its limit ────────────
-- Snowflake blocks you from modifying a network policy in a way
-- that would remove YOUR OWN current session's IP from the allow
-- list — you'll get an explicit error rather than being silently
-- locked out mid-edit. This guardrail only protects the person
-- making the change, in that moment. It does not protect every
-- OTHER user the policy applies to, and it does not prevent a
-- badly-scoped BLOCKED list from locking out an entire office or
-- VPN range. Treat every network policy as something to simulate
-- before activating, not something to activate and iterate on live.
-- ─────────────────────────────────────────────────────────────
--
-- ── Oracle / SQL Server comparison ───────────────────────────
-- The nearest Oracle equivalent is Oracle Net's TCP.VALIDNODE_
-- CHECKING with TCP.INVITED_NODES/TCP.EXCLUDED_NODES, configured
-- in sqlnet.ora — a client-side/listener-side config file, not a
-- SQL-managed object. Snowflake's network policy is a first-class,
-- account-managed object with its own DDL, GRANT-based privileges,
-- and per-user override capability, rather than a file an admin
-- edits on a server.
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
-- STEP 1: Create a network administrator role
-- ══════════════════════════════════════════════════════════════
-- Separation of duties, following the documented Snowflake
-- pattern: NETWORK_ADMIN builds and maintains policies; account-
-- level activation stays a deliberate, separate action (Step 5's
-- warning explains why this sub-task doesn't automate it).

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS NETWORK_ADMIN
    COMMENT = 'Builds and maintains network rules and policies';

-- CREATE NETWORK POLICY and ATTACH POLICY are both global,
-- ACCOUNTADMIN-only by default — same restriction pattern as every
-- APPLY ... ON ACCOUNT privilege in Sub-tasks 4.4-4.6
GRANT CREATE NETWORK POLICY ON ACCOUNT TO ROLE NETWORK_ADMIN;
GRANT ATTACH POLICY ON ACCOUNT TO ROLE NETWORK_ADMIN;

USE ROLE SECURITYADMIN;

GRANT ROLE NETWORK_ADMIN TO ROLE SYSADMIN;
GRANT ROLE NETWORK_ADMIN TO USER <your_username>;

-- CREATE NETWORK RULE is schema-level — SYSADMIN, as schema
-- owner, grants it directly
USE ROLE SYSADMIN;

GRANT USAGE ON DATABASE ECOMMERCE     TO ROLE NETWORK_ADMIN;
GRANT USAGE ON SCHEMA   ECOMMERCE.RAW TO ROLE NETWORK_ADMIN;
GRANT USAGE ON WAREHOUSE WORKBOOK_WH  TO ROLE NETWORK_ADMIN;
GRANT CREATE NETWORK RULE ON SCHEMA ECOMMERCE.RAW TO ROLE NETWORK_ADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Find your own current IP address
-- ══════════════════════════════════════════════════════════════
-- Snowflake does not expose your client's public IP through a SQL
-- function — look it up externally (e.g. search "what is my IP")
-- before continuing. You'll use it in Step 3, and again to build a
-- CIDR range if you want more than a single address covered.
--
-- Replace <your_ip_address> below with the real value, in CIDR
-- notation (a single IP is <ip>/32, e.g. 203.0.113.10/32).

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Create the network rules
-- ══════════════════════════════════════════════════════════════

USE ROLE NETWORK_ADMIN;
USE SECONDARY ROLES NONE;

CREATE OR REPLACE NETWORK RULE ECOMMERCE.RAW.ALLOW_MY_IP
    MODE = INGRESS
    TYPE = IPV4
    VALUE_LIST = ('<your_ip_address>/32')
    COMMENT = 'Allow list: your own current IP, CIDR notation';

-- Built here but deliberately NOT wired into the main policy below
-- — see Step 4's comment for why, and Practice Gap exercise 4 for
-- how to actually observe this rule's effect.
CREATE OR REPLACE NETWORK RULE ECOMMERCE.RAW.BLOCK_ALL_PUBLIC
    MODE = INGRESS
    TYPE = IPV4
    VALUE_LIST = ('0.0.0.0/0')
    COMMENT = 'Block list: every IPv4 address — kept separate from the main policy on purpose, see Step 4';

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Create the network policy — allow-only, genuinely working
-- ══════════════════════════════════════════════════════════════
-- An ALLOWED_NETWORK_RULE_LIST on its own is a real, working allow
-- list: anything NOT in it is blocked implicitly — no separate
-- BLOCKED_NETWORK_RULE_LIST is needed to achieve that. This policy
-- intentionally does NOT reference BLOCK_ALL_PUBLIC.
--
-- Why not: BLOCK_ALL_PUBLIC covers 0.0.0.0/0 — every IPv4 address
-- that exists, including whatever's in the allow list. Per CONCEPT
-- above, when an IP matches both lists, BLOCKED always wins,
-- regardless of specificity — Snowflake does not do longest-
-- prefix-match the way a router would. Pairing ALLOW_MY_IP with
-- BLOCK_ALL_PUBLIC in the same policy would produce a policy that
-- blocks EVERYONE, including you — not "allow my IP, block
-- everything else" as the names might suggest. Practice Gap
-- exercise 4 has you prove this to yourself directly, temporarily,
-- without it being the policy this file leaves you with.

CREATE OR REPLACE NETWORK POLICY ECOMMERCE_WORKBOOK_POLICY
    ALLOWED_NETWORK_RULE_LIST = ('ECOMMERCE.RAW.ALLOW_MY_IP')
    COMMENT = 'Workbook Sub-task 4.7 — allow-only, built and simulated only, never activated at account level in this file';

SHOW NETWORK POLICIES LIKE 'ECOMMERCE_WORKBOOK_POLICY'
;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Simulate before activating — SAFE, non-disruptive
-- ══════════════════════════════════════════════════════════════
-- These stored procedures generate SQL and run what-if evaluations
-- against real historical login data. Neither one activates or
-- modifies anything — safe to run freely.
--
-- Snowflake's documentation states SECURITYADMIN (or higher) can
-- run these — in practice, this account requires ACCOUNTADMIN
-- specifically. Same "docs say SECURITYADMIN-capable, account
-- actually requires ACCOUNTADMIN" pattern already seen with APPLY
-- MASKING POLICY, APPLY ROW ACCESS POLICY, and APPLY TAG in
-- Sub-tasks 4.4-4.6 — worth checking directly rather than trusting
-- the documented minimum in any given account.

USE ROLE ACCOUNTADMIN;

-- Ask Snowflake what it would recommend, based on real recent
-- login history, as a sanity check against what you built by hand
CALL SNOWFLAKE.NETWORK_SECURITY.RECOMMEND_NETWORK_POLICY(
    LOOKBACK_DAYS => 30
);

-- Evaluate YOUR candidate policy against real login history —
-- shows what would have been allowed/blocked if this policy had
-- been active, without actually activating it
CALL SNOWFLAKE.NETWORK_SECURITY.EVALUATE_CANDIDATE_NETWORK_POLICY(
    POLICY_NAME => 'ECOMMERCE_WORKBOOK_POLICY'
);

-- ══════════════════════════════════════════════════════════════
-- ⚠ STEP 6: Activation — demonstrated on a DISPOSABLE test user
--   only. Never run ALTER ACCOUNT SET NETWORK_POLICY in this
--   sub-task, and never activate this policy on <your_username>
--   or any real user. Read this whole step before running any of
--   it.
-- ══════════════════════════════════════════════════════════════
-- A disposable user means: if ECOMMERCE_WORKBOOK_POLICY is wrong
-- in some way you didn't catch in Step 5, the ONLY account
-- affected is one you're about to delete anyway — never your own
-- login, never anyone else's.

USE ROLE USERADMIN;

CREATE OR REPLACE USER NETWORK_POLICY_TEST_USER
    PASSWORD = 'TempPassword_ReplaceMe123!'
    MUST_CHANGE_PASSWORD = TRUE
    COMMENT = 'Disposable — Sub-task 4.7 network policy activation test only. Drop after Step 6.';

-- Activating for a user needs OWNERSHIP on the user AND the
-- policy — USERADMIN owns the user it just created; NETWORK_ADMIN
-- owns the policy from Step 4. Documentation suggests SECURITYADMIN
-- (sitting above both in the default hierarchy) should be able to
-- act on both — in practice, SECURITYADMIN does not automatically
-- inherit OWNERSHIP on objects created by other custom roles just
-- by sitting above them; ACCOUNTADMIN is required here. Same
-- "docs say SECURITYADMIN-capable, account actually requires
-- ACCOUNTADMIN" pattern already seen with APPLY MASKING POLICY,
-- APPLY ROW ACCESS POLICY, APPLY TAG, and the network policy
-- advisor procedures earlier in this sub-task.
USE ROLE ACCOUNTADMIN;

ALTER USER NETWORK_POLICY_TEST_USER SET NETWORK_POLICY = 'ECOMMERCE_WORKBOOK_POLICY';

-- Confirm the policy is attached to the TEST USER specifically —
-- not to the account, not to your own user
SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN USER NETWORK_POLICY_TEST_USER
;

-- Clean up immediately — detach the policy, then drop the
-- disposable user entirely
ALTER USER NETWORK_POLICY_TEST_USER UNSET NETWORK_POLICY;

USE ROLE USERADMIN;

DROP USER IF EXISTS NETWORK_POLICY_TEST_USER;

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Query SNOWFLAKE.ACCOUNT_USAGE.INGRESS_NETWORK_ACCESS_HISTORY
--    (as ACCOUNTADMIN) to see real historical login IPs for this
--    account over the last 30 days. Compare it against what
--    RECOMMEND_NETWORK_POLICY suggested in Step 5.
--
-- 2. Add a second CIDR range to ALLOW_MY_IP (e.g. a wider range
--    covering your ISP, or a VPN range if you use one), using
--    ALTER NETWORK RULE ... SET VALUE_LIST — note this REPLACES
--    the entire list rather than adding to it, so include both
--    values in the same statement. Re-run Step 5's evaluation
--    afterward to confirm both are now treated as allowed.
--
-- 3. Repeat Step 6 with the roles reversed: try activating
--    ECOMMERCE_WORKBOOK_POLICY on NETWORK_POLICY_TEST_USER as
--    NETWORK_ADMIN alone (without switching to SECURITYADMIN).
--    Confirm it fails — NETWORK_ADMIN owns the policy but not the
--    user, and per CONCEPT above, user-level activation needs
--    OWNERSHIP on both.
--
-- 4. See the BLOCKED-always-wins precedence rule for yourself,
--    temporarily and safely — this is simulation only, nothing is
--    ever activated:
--
--    USE ROLE NETWORK_ADMIN;
--    USE SECONDARY ROLES NONE;
--    ALTER NETWORK POLICY ECOMMERCE_WORKBOOK_POLICY
--        SET BLOCKED_NETWORK_RULE_LIST = ('ECOMMERCE.RAW.BLOCK_ALL_PUBLIC');
--
--    USE ROLE ACCOUNTADMIN;
--    CALL SNOWFLAKE.NETWORK_SECURITY.EVALUATE_CANDIDATE_NETWORK_POLICY(
--        POLICY_NAME => 'ECOMMERCE_WORKBOOK_POLICY'
--    );
--    -- Your own IP now shows NO, despite still being in
--    -- ALLOW_MY_IP — proof that BLOCK_ALL_PUBLIC's 0.0.0.0/0
--    -- overrides it, exactly as Step 4's comment warned.
--
--    Revert immediately back to the working allow-only policy:
--
--    USE ROLE NETWORK_ADMIN;
--    ALTER NETWORK POLICY ECOMMERCE_WORKBOOK_POLICY
--        SET BLOCKED_NETWORK_RULE_LIST = ();
--    -- If an empty list is rejected, use UNSET instead:
--    -- ALTER NETWORK POLICY ECOMMERCE_WORKBOOK_POLICY
--    --     UNSET BLOCKED_NETWORK_RULE_LIST;
--
--    Re-run the evaluation once more to confirm your IP shows YES
--    again before moving on.
--
-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I try to remove my own current IP from an active
--    policy's allow list?
-- A: Snowflake blocks the change outright, with an explicit error
--    naming your current IP — see CONCEPT above. This only
--    protects the person making the edit, in that moment; it does
--    not protect other users or prevent a bad BLOCKED list from
--    affecting someone else entirely.
--
-- Q: What if I don't know which IPs to allow before writing a
--    restrictive policy?
-- A: Don't guess. Use RECOMMEND_NETWORK_POLICY (Step 5) or query
--    INGRESS_NETWORK_ACCESS_HISTORY (Practice Gap exercise 1)
--    first, so the policy is based on real login patterns rather
--    than an assumption about where people connect from.
--
-- Q: What if an IP matches both the allowed and blocked lists?
-- A: BLOCKED wins — even if the allowed entry is more specific (a
--    single IP) than the blocked entry (a broad range). Snowflake
--    does not do longest-prefix-match the way network routing
--    does. This is exactly why ECOMMERCE_WORKBOOK_POLICY in this
--    file is allow-only, with BLOCK_ALL_PUBLIC deliberately left
--    unattached — pairing a 0.0.0.0/0 block rule with any allow
--    rule produces a policy that blocks everyone, including
--    whoever's IP is in the allow list. Practice Gap exercise 4
--    lets you see this for yourself, temporarily and safely.
--
-- Q: What if I need this active on the real account, for real,
--    outside this workbook?
-- A: Simulate thoroughly first (Step 5, repeated as many times as
--    needed), confirm your OWN access is covered, activate at the
--    USER level for a small pilot group before ever touching the
--    ACCOUNT level, and know in advance that an account-level
--    lockout may require contacting Snowflake Support to resolve
--    — it is not something to activate-and-iterate on casually.
--
-- Q: What is different from Oracle I should watch for in this
--    sub-task specifically?
-- A: Key differences:
--    · sqlnet.ora is a client/listener config file edited outside
--      the database; a Snowflake network policy is a SQL object
--      with its own DDL, ownership, and GRANT-based privileges
--    · Per-user network policy override (this sub-task's Step 6)
--      has no close Oracle Net equivalent — TCP.INVITED_NODES/
--      TCP.EXCLUDED_NODES apply at the listener level, not per
--      database user
--    · CREATE NETWORK POLICY being a GLOBAL privilege rather than
--      schema-owner-granted is a direct consequence of network
--      policies being account-scoped objects, unlike every other
--      policy type covered so far in Goal 4
-- ══════════════════════════════════════════════════════════════
