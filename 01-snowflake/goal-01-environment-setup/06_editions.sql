-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 1 : Set Up Your Environment
-- Sub-task 1.6 : Understand Snowflake editions
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~15 minutes
-- Warehouse size   : X-Small (COMPUTE_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : 05_stage_types.sql completed
-- COF-C03 domain   : Domain 1 — Architecture & Features (25%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Snowflake is sold in four editions. The edition your account
--   runs on determines which features are available to you —
--   and several features covered in this workbook are gated
--   behind Enterprise edition or higher.
--
--   Understanding editions matters for three reasons:
--   1. You need to know what your account can and cannot do
--   2. The COF-C03 exam tests edition-specific feature knowledge
--   3. When advising clients or employers on Snowflake adoption
--      you need to know what tier justifies what cost
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE FOUR SNOWFLAKE EDITIONS
-- ══════════════════════════════════════════════════════════════
--
-- STANDARD
--   The entry-level edition. Suitable for development,
--   non-critical workloads, and getting started.
--   Key limitations:
--   · Time Travel: 0–1 day only (not 90 days)
--   · No multi-cluster warehouses
--   · No materialized views
--   · No column-level security (dynamic data masking)
--   · No row access policies
--   · No database replication
--
-- ENTERPRISE (most common in production)
--   The most widely deployed edition for production workloads.
--   Adds everything practitioners actually need at scale:
--   · Time Travel: 0–90 days
--   · Multi-cluster warehouses (auto-scaling for concurrency)
--   · Materialized views
--   · Dynamic data masking (column-level security)
--   · Row access policies
--   · Database replication across regions
--   · Periodic data rekeying
--   This workbook is validated on Enterprise edition.
--
-- BUSINESS CRITICAL
--   Enterprise plus enhanced security and compliance features:
--   · Customer-managed encryption keys (Tri-Secret Secure)
--   · AWS PrivateLink / Azure Private Link support
--   · HIPAA, PCI-DSS, SOC 2 Type II compliance
--   · External tokenisation support
--   · Database failover and fallback
--   Required for regulated industries (healthcare, finance,
--   government) where data cannot leave a private network.
--
-- VIRTUAL PRIVATE SNOWFLAKE (VPS)
--   The highest tier. A completely dedicated Snowflake
--   environment — no shared infrastructure with other customers.
--   For organisations with the most stringent security and
--   isolation requirements. Rare in practice.
--
-- EDITION FEATURE MATRIX (features tested on COF-C03)
-- ┌─────────────────────────────────┬──────┬────────┬────────┬─────┐
-- │ Feature                         │ STD  │ ENT    │ BC     │ VPS │
-- ├─────────────────────────────────┼──────┼────────┼────────┼─────┤
-- │ Time Travel (max days)          │  1   │  90    │  90    │ 90  │
-- │ Fail-Safe                       │  ✓   │  ✓     │  ✓     │  ✓  │
-- │ Multi-cluster warehouses        │  ✗   │  ✓     │  ✓     │  ✓  │
-- │ Materialized views              │  ✗   │  ✓     │  ✓     │  ✓  │
-- │ Dynamic data masking            │  ✗   │  ✓     │  ✓     │  ✓  │
-- │ Row access policies             │  ✗   │  ✓     │  ✓     │  ✓  │
-- │ Database replication            │  ✗   │  ✓     │  ✓     │  ✓  │
-- │ Customer-managed keys           │  ✗   │  ✗     │  ✓     │  ✓  │
-- │ Private Link support            │  ✗   │  ✗     │  ✓     │  ✓  │
-- │ Dedicated infrastructure        │  ✗   │  ✗     │  ✗     │  ✓  │
-- └─────────────────────────────────┴──────┴────────┴────────┴─────┘
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'COMPUTE_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: Identify your current edition
-- ══════════════════════════════════════════════════════════════
-- Check your account identifier and region
SELECT
    CURRENT_ACCOUNT()               AS account_identifier,
    CURRENT_REGION()                AS cloud_region,
    CURRENT_ORGANIZATION_NAME()     AS organization_name
;

-- To find your edition:
-- Click your account name (bottom-left) → Account → View Account Details
-- Your edition is displayed in the account details panel
--
-- Note: SNOWFLAKE.ACCOUNT_USAGE.ACCOUNTS and SHOW ORGANIZATIONS
-- both require ORGADMIN role which most practitioners do not have.
-- The Snowsight UI is the most reliable way to check your edition.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Verify Enterprise features are available
-- ══════════════════════════════════════════════════════════════
-- Since this workbook is validated on Enterprise edition,
-- we verify the key Enterprise features are accessible
-- on your account before building on them in later goals.

-- Test 1: Time Travel retention — Enterprise supports up to 90 days
-- Create a test table and set retention to 30 days
-- (This fails on Standard edition — max is 1 day)
CREATE TABLE IF NOT EXISTS ECOMMERCE.RAW.EDITION_TEST (
    id      INTEGER,
    val     VARCHAR(100)
)
DATA_RETENTION_TIME_IN_DAYS = 30
COMMENT = 'Edition feature test table — dropped in cleanup'
;

-- Verify retention was set to 30 days
SHOW TABLES LIKE 'EDITION_TEST' IN SCHEMA ECOMMERCE.RAW;

SELECT
    "name"              AS table_name,
    "retention_time"    AS time_travel_days
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- retention_time = 30 confirms Enterprise edition
-- If you see retention_time = 1, your account is Standard edition
-- and the DATA_RETENTION_TIME_IN_DAYS = 30 was silently capped

-- Test 2: Materialized views — Enterprise only
-- We already created one in sub-task 1.4 successfully.
-- If that worked, materialized views are available on your account.

-- Test 3: Dynamic data masking — covered in Goal 4
-- Test 4: Row access policies — covered in Goal 4
-- Test 5: Multi-cluster warehouses — covered in sub-task 1.7

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Edition-aware feature flags in your scripts
-- ══════════════════════════════════════════════════════════════
-- When writing scripts that may run on different editions,
-- it is good practice to check the edition first and branch
-- your logic accordingly. This pattern is useful when writing
-- Terraform or dbt code that deploys to multiple environments.

-- Edition check via Snowsight UI:
-- Click your account name (bottom-left) → Account → View Account Details
-- Use the edition shown there to interpret the feature availability
-- table in the CONCEPT section above.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Edition-gated features in this workbook
-- ══════════════════════════════════════════════════════════════
-- For reference, here are the sub-tasks in this workbook
-- that require Enterprise edition or higher.
-- Each is flagged in its own file — this is the master list.

-- [ENTERPRISE REQUIRED]
-- Sub-task 1.3 : DATA_RETENTION_TIME_IN_DAYS > 1 day
-- Sub-task 1.4 : Materialized views (CREATE MATERIALIZED VIEW)
-- Sub-task 1.7 : Multi-cluster warehouse configuration
-- Sub-task 4.3 : Dynamic data masking policies
-- Sub-task 4.4 : Row access policies
-- Sub-task 8.1 : Time Travel retention beyond 1 day
-- Sub-task 8.4 : Database replication and failover

-- [STANDARD EDITION — works on all editions]
-- Everything else in this workbook runs on Standard edition.
-- Standard edition is available on the free trial account.

-- If you are on Standard edition:
-- · Goals 1–3 work completely
-- · Goal 4 (security): masking and row access policies unavailable
-- · Goal 5 (performance): multi-cluster warehouses unavailable
-- · Goal 8 (recovery): Time Travel capped at 1 day
-- · All other sub-tasks work as written

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Where to find edition information in Snowsight
-- ══════════════════════════════════════════════════════════════
-- Your edition is visible in three places in the Snowsight UI:
--
-- 1. Bottom-left corner of Snowsight
--    Click your account name → account details panel
--    Shows: account identifier, edition, cloud, region
--
-- 2. Admin → Accounts (ACCOUNTADMIN role required)
--    Shows all accounts in your organisation with editions
--
-- 3. SNOWFLAKE.ACCOUNT_USAGE.ACCOUNTS view (used in Step 1)
--    Programmatic access — useful for automation and reporting
--
-- For the COF-C03 exam: know which features are Standard vs
-- Enterprise vs Business Critical. The feature matrix in the
-- CONCEPT section above covers the most commonly tested items.

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- Option 1 — Remove edition test table only
-- Use this if you are continuing to sub-task 1.7
-- ──────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS ECOMMERCE.RAW.EDITION_TEST;

-- Verify
SHOW TABLES IN SCHEMA ECOMMERCE.RAW;
-- Should return only ECOMMERCE_RAW_STAGE (named stage)
-- and any tables you chose to keep from earlier sub-tasks

-- Option 2 — Full reset, drop the entire ECOMMERCE database
-- NOTE: Sub-task 1.7 SETUP block will recreate everything needed
-- ──────────────────────────────────────────────────────────────
-- DROP DATABASE IF EXISTS ECOMMERCE;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Run the edition check query in Step 3.
--    Based on the output, list which features in this workbook
--    are available on your account and which are not.
--
-- 2. A client asks you to recommend a Snowflake edition for
--    a healthcare company that needs:
--    · HIPAA compliance
--    · Column-level data masking for PII
--    · 30-day Time Travel for audit purposes
--    · Private network connectivity (no public internet)
--    Which edition do you recommend and why?
--    What is the minimum edition that meets ALL requirements?
--
-- 3. Try to create a table with DATA_RETENTION_TIME_IN_DAYS = 90.
--    What value does SHOW TABLES report for retention_time?
--    Does it match what you set?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I need a feature that is not available on my
--    current edition?
-- A: Contact your Snowflake account team to upgrade. Edition
--    upgrades are non-disruptive — your data, users, and
--    configurations are preserved. Downgrades are more complex
--    and may require feature cleanup first.
--
-- Q: What if I am on a trial account — what edition is it?
-- A: Snowflake trial accounts are Enterprise edition for the
--    30-day trial period. This is why the free trial is a good
--    learning environment — all Enterprise features are available.
--    After the trial if you convert to a paid account, confirm
--    your contracted edition before building on Enterprise features.
--
-- Q: What if I want to test Business Critical features?
-- A: You need a Business Critical account. There is no way to
--    trial BC features on an Enterprise account. If you are
--    evaluating BC for a client, Snowflake can provision a
--    temporary BC evaluation environment.
--
-- Q: Does the edition affect query performance?
-- A: Not directly. Query performance is driven by warehouse
--    size, clustering, and query design — not edition.
--    Edition gates features, not compute speed.
--    The exception: multi-cluster warehouses (Enterprise+)
--    allow horizontal scaling for high-concurrency workloads
--    which can significantly improve throughput under load.
--
-- Q: What edition do most enterprise production accounts use?
-- A: Enterprise is by far the most common production edition.
--    It covers the vast majority of real-world requirements
--    at a reasonable cost premium over Standard.
--    Business Critical is used where compliance mandates it —
--    healthcare (HIPAA), financial services (PCI-DSS), and
--    government workloads primarily.
