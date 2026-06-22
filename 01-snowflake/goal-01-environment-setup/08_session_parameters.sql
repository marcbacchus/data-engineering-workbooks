-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 1 : Set Up Your Environment
-- Sub-task 1.8 : Understand session and account parameters
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~20 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : 07_virtual_warehouses.sql completed
--                    WORKBOOK_WH exists
-- COF-C03 domain   : Domain 1 — Architecture & Features (25%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Snowflake has hundreds of parameters that control how your
--   session behaves — how dates are formatted, what timezone
--   is assumed, whether transactions auto-commit, how NULL
--   values sort, and much more.
--
--   Most practitioners never look at these until something
--   breaks. A query returns wrong dates. A timestamp is off
--   by hours. A DELETE commits when you thought it hadn't.
--   All of these trace back to parameter settings.
--
--   This sub-task covers the parameters that matter most
--   day-to-day — the ones that burn practitioners who do not
--   know they exist, especially those coming from Oracle,
--   SQL Server, or other platforms with different defaults.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THREE LEVELS OF PARAMETERS
-- ══════════════════════════════════════════════════════════════
--
-- Parameters in Snowflake operate at three levels.
-- Lower levels override higher levels:
--
--   ACCOUNT level   → applies to all users in the account
--       ↓ overrides
--   USER level      → applies to a specific user
--       ↓ overrides
--   SESSION level   → applies only to the current session
--
-- When you set a parameter at session level it overrides
-- whatever is set at account or user level — for this
-- session only. When the session ends the override is gone.
--
-- KEY PARAMETERS PRACTITIONERS NEED TO KNOW:
--
-- AUTOCOMMIT (default: TRUE)
--   Every DML statement (INSERT, UPDATE, DELETE, MERGE)
--   commits automatically when it completes.
--   Oracle default: FALSE — transactions are open until
--   you explicitly COMMIT or ROLLBACK.
--   This is the single most dangerous default for Oracle
--   practitioners moving to Snowflake.
--
-- TIMEZONE (default: UTC)
--   All TIMESTAMP_LTZ values are stored and displayed
--   relative to this timezone. If your users are in
--   New York but TIMEZONE = UTC, timestamps will display
--   5 hours ahead of local time.
--
-- TIMESTAMP_TYPE_MAPPING (default: TIMESTAMP_NTZ)
--   When you write TIMESTAMP without a suffix, Snowflake
--   maps it to this type. Options:
--   TIMESTAMP_NTZ — no timezone (stored as-is)
--   TIMESTAMP_LTZ — local timezone (converted to UTC on store)
--   TIMESTAMP_TZ  — with timezone offset
--
-- DATE_INPUT_FORMAT (default: AUTO)
--   How Snowflake interprets date strings on input.
--   AUTO detects common formats but can cause ambiguity
--   between MM/DD/YYYY and DD/MM/YYYY depending on locale.
--
-- DATE_OUTPUT_FORMAT (default: YYYY-MM-DD)
--   How dates display in query results.
--
-- QUERY_TAG
--   A string attached to every query in this session.
--   Appears in QUERY_HISTORY — invaluable for cost attribution
--   and workload monitoring. Set it to your team name,
--   pipeline name, or job ID.
--
-- TWO_DIGIT_CENTURY_START (default: 1970)
--   How two-digit years are interpreted.
--   Year 70 = 1970, year 69 = 2069.
--   Avoid two-digit years entirely — but know this exists.
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
-- STEP 1: Survey current parameter settings
-- ══════════════════════════════════════════════════════════════
-- SHOW PARAMETERS lists all parameters and their current values
-- along with where the value is set (default, account, session).

SHOW PARAMETERS;

-- Filter to the parameters that matter most
SELECT
    "key"           AS parameter_name,
    "value"         AS current_value,
    "default"       AS default_value,
    "level"         AS set_at_level,
    "description"   AS description
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "key" IN (
    'AUTOCOMMIT',
    'TIMEZONE',
    'TIMESTAMP_TYPE_MAPPING',
    'DATE_INPUT_FORMAT',
    'DATE_OUTPUT_FORMAT',
    'TIME_OUTPUT_FORMAT',
    'QUERY_TAG',
    'TWO_DIGIT_CENTURY_START'
)
ORDER BY "key"
;
-- level = SYSTEM means you are using the Snowflake default
-- level = ACCOUNT means your account admin has set this
-- level = SESSION means it is set only for this session

-- ══════════════════════════════════════════════════════════════
-- STEP 2: The AUTOCOMMIT trap — critical for Oracle practitioners
-- ══════════════════════════════════════════════════════════════
-- In Oracle, transactions are open until you COMMIT or ROLLBACK.
-- In Snowflake, AUTOCOMMIT = TRUE by default — every DML
-- statement commits the moment it completes.
--
-- This means: DELETE FROM table WHERE condition = TRUE
-- commits immediately. There is no "oops, let me rollback."
-- Time Travel is your safety net (Goal 8) — but knowing
-- AUTOCOMMIT exists prevents the mistake entirely.

-- Check current AUTOCOMMIT setting
SHOW PARAMETERS LIKE 'AUTOCOMMIT';

SELECT "key", "value", "default", "level"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- value = true = AUTOCOMMIT is ON (Snowflake default)

-- Demonstrate AUTOCOMMIT behaviour
CREATE TABLE IF NOT EXISTS ECOMMERCE.RAW.AUTOCOMMIT_TEST (
    id      INTEGER,
    val     VARCHAR(50)
)
;

INSERT INTO ECOMMERCE.RAW.AUTOCOMMIT_TEST VALUES (1, 'row one'), (2, 'row two');

-- With AUTOCOMMIT = TRUE this DELETE commits immediately
DELETE FROM ECOMMERCE.RAW.AUTOCOMMIT_TEST WHERE id = 1;

-- Try to rollback — it is too late, already committed
ROLLBACK;

-- Verify the row is gone — cannot be recovered by ROLLBACK
SELECT * FROM ECOMMERCE.RAW.AUTOCOMMIT_TEST;
-- Only row 2 remains. Row 1 is gone.
-- ROLLBACK had no effect because AUTOCOMMIT already committed.
-- Recovery requires Time Travel (Goal 8).

-- How to control this explicitly:
-- Option 1: Wrap DML in explicit transaction
BEGIN;
    DELETE FROM ECOMMERCE.RAW.AUTOCOMMIT_TEST WHERE id = 2;
    -- Changed your mind — rollback is possible here
ROLLBACK;

SELECT * FROM ECOMMERCE.RAW.AUTOCOMMIT_TEST;
-- Row 2 is back — ROLLBACK worked because BEGIN disabled AUTOCOMMIT
-- for this transaction block

-- Option 2: Turn AUTOCOMMIT off for the session
ALTER SESSION SET AUTOCOMMIT = FALSE;

DELETE FROM ECOMMERCE.RAW.AUTOCOMMIT_TEST WHERE id = 2;
--Notice Row 2 is gone
SELECT * FROM ECOMMERCE.RAW.AUTOCOMMIT_TEST;

ROLLBACK;
--Notice Row 2 is rollback
SELECT * FROM ECOMMERCE.RAW.AUTOCOMMIT_TEST;

-- Row 2 is back again — session-level AUTOCOMMIT = FALSE
-- means all DML is now in an implicit transaction

-- Reset AUTOCOMMIT to TRUE (Snowflake default)
ALTER SESSION SET AUTOCOMMIT = TRUE;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: TIMEZONE — understanding timestamp behaviour
-- ══════════════════════════════════════════════════════════════
-- The TIMEZONE parameter affects how TIMESTAMP_LTZ values
-- are stored and displayed. The Snowflake system default
-- is America/Los_Angeles. Best practice for data engineering
-- is to always set UTC explicitly — never assume the default.

-- Check account-level timezone default
SHOW PARAMETERS LIKE 'TIMEZONE' IN ACCOUNT;
-- Shows America/Los_Angeles — Snowflake system default

-- Check current session timezone
SHOW PARAMETERS LIKE 'TIMEZONE';

SELECT "key", "value", "default", "level"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- If level = SYSTEM  → using the Snowflake default
-- If level = SESSION → a previous ALTER SESSION SET TIMEZONE
--                      in this sub-task has overridden it

-- See the effect of timezone on timestamp display
SELECT
    CURRENT_TIMESTAMP()                                               AS current_ts_utc,
    CONVERT_TIMEZONE('UTC', 'America/New_York', CURRENT_TIMESTAMP()) AS current_ts_eastern,
    CONVERT_TIMEZONE('UTC', 'Europe/London',    CURRENT_TIMESTAMP()) AS current_ts_london
;

-- ── TIMESTAMP TYPES COMPARED ─────────────────────────────────
-- See all three timestamp types side by side using the
-- same underlying moment in time.

SELECT
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ  AS ts_ntz,
    CURRENT_TIMESTAMP()::TIMESTAMP_LTZ  AS ts_ltz,
    CURRENT_TIMESTAMP()::TIMESTAMP_TZ   AS ts_tz
;
-- ts_ntz : no timezone info — stored exactly as-is
--          session TIMEZONE setting has zero effect on NTZ
-- ts_ltz : converted to UTC on store, displayed in session timezone
-- ts_tz  : timezone offset travels with the value
--
-- Note: LTZ and TZ look identical when queried in the same
-- session they were written in. The difference appears when:
--   LTZ → always displays in the CURRENT session timezone
--   TZ  → always displays the timezone offset stored with the value
-- For global event logs where the original offset matters: use TZ
-- For everything else in data engineering: use NTZ

-- Now change session timezone and observe how each type responds
ALTER SESSION SET TIMEZONE = 'America/New_York';

SELECT
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ  AS ts_ntz,
    CURRENT_TIMESTAMP()::TIMESTAMP_LTZ  AS ts_ltz,
    CURRENT_TIMESTAMP()::TIMESTAMP_TZ   AS ts_tz
;
-- ts_ntz : UNCHANGED — timezone setting has no effect on NTZ
-- ts_ltz : shifts to reflect New York time
-- ts_tz  : shows New York offset (-0500 or -0400 depending on DST)

-- Verify active timezone
SHOW PARAMETERS LIKE 'TIMEZONE';

SELECT "key", "value", "level"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- value = America/New_York
-- level = SESSION

-- Reset to UTC for all remaining work
ALTER SESSION SET TIMEZONE = 'UTC';

-- Confirm reset
SHOW PARAMETERS LIKE 'TIMEZONE';

SELECT "key", "value", "level"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- value = UTC
-- level = SESSION

-- ── PRACTICAL GUIDANCE ────────────────────────────────────────
-- TIMESTAMP_NTZ — use for most data engineering work
--                 simple, no conversion surprises, consistent
-- TIMESTAMP_LTZ — use when timezone-aware storage is needed
--                 and users are in a single known timezone
-- TIMESTAMP_TZ  — use when source data carries timezone offsets
--                 that must be preserved (global event logs)
--
-- Always set TIMEZONE = 'UTC' explicitly at the start of
-- every pipeline session — never rely on the default.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: DATE formats — avoiding ambiguity
-- ══════════════════════════════════════════════════════════════
-- AUTO date format detection can cause silent errors when
-- source data mixes date formats. Explicit formats are safer.

-- Check current date format settings
SHOW PARAMETERS LIKE '%DATE%';

SELECT "key", "value", "default"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;

-- Demonstrate date format ambiguity
-- Is 01/02/2023 January 2nd or February 1st?
SELECT TO_DATE('01/02/2023')            AS auto_detected;
-- With AUTO format Snowflake interprets as MM/DD/YYYY = Jan 2

-- Set explicit input format
ALTER SESSION SET DATE_INPUT_FORMAT = 'DD/MM/YYYY';
SELECT TO_DATE('01/02/2023')            AS explicit_format;
-- Now interpreted as DD/MM/YYYY = Feb 1 — completely different date

-- Reset to AUTO
ALTER SESSION SET DATE_INPUT_FORMAT = 'AUTO';

-- Set output format for readability
ALTER SESSION SET DATE_OUTPUT_FORMAT = 'DD-MON-YYYY';
SELECT CURRENT_DATE() AS formatted_date;
-- Displays as 22-JUN-2025 style

-- Reset to ISO standard (recommended for data engineering)
ALTER SESSION SET DATE_OUTPUT_FORMAT = 'YYYY-MM-DD';
SELECT CURRENT_DATE() AS iso_date;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: QUERY_TAG — tagging queries for cost attribution
-- ══════════════════════════════════════════════════════════════
-- QUERY_TAG attaches a label to every query in your session.
-- Shows up in QUERY_HISTORY — essential for understanding
-- which pipeline, team, or process drove which cost.

-- Set a query tag for this session
ALTER SESSION SET QUERY_TAG = 'workbook:goal-01:sub-task-1.8';

-- Run a query — it will be tagged
SELECT COUNT(*), CURRENT_TIMESTAMP()
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- Find the tagged query in history
SELECT
    QUERY_ID,
    QUERY_TEXT,
    QUERY_TAG,
    WAREHOUSE_NAME,
    EXECUTION_TIME / 1000       AS execution_seconds,
    CREDITS_USED_CLOUD_SERVICES
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
    DATEADD('minute', -5, CURRENT_TIMESTAMP()),
    CURRENT_TIMESTAMP(),
    10
))
WHERE QUERY_TAG = 'workbook:goal-01:sub-task-1.8'
ORDER BY START_TIME DESC
;
-- Your tagged query appears with the label attached.
-- In production, set QUERY_TAG to your pipeline name,
-- dbt model name, or job ID at the start of every session.
-- This makes ACCOUNT_USAGE cost analysis far more actionable.

-- Clear the query tag
ALTER SESSION UNSET QUERY_TAG;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Set parameters at account level
-- ══════════════════════════════════════════════════════════════
-- Account-level parameters apply to all users unless overridden
-- at user or session level. Requires ACCOUNTADMIN role.
-- Use carefully — account-level changes affect everyone.

USE ROLE ACCOUNTADMIN;

-- View current account-level parameter settings
SHOW PARAMETERS IN ACCOUNT;

SELECT
    "key"       AS parameter_name,
    "value"     AS current_value,
    "default"   AS default_value,
    "level"     AS set_at_level
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "level" = 'ACCOUNT'  -- only show parameters explicitly set at account level
ORDER BY "key"
;
-- Expected output varies by account.
-- You may see zero rows (all parameters at Snowflake defaults)
-- or one or more rows where your account admin has explicitly
-- set parameters.
--
-- Example of what you might see:
-- CORTEX_ENABLED_CROSS_REGION | ANY_REGION | DISABLED | ACCOUNT
-- This means Cortex AI functions are enabled to use cross-region
-- compute — relevant for Goal 3 Sub-task 3.7 (Cortex exercises).
--
-- Whatever appears here is your account's baseline configuration.
-- Note it down — it explains behaviour you may encounter later.

-- Return to SYSADMIN for remaining work
USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Best practice parameter configuration
-- ══════════════════════════════════════════════════════════════
-- These are the recommended session parameters to set at the
-- start of any production script or pipeline. Add this block
-- to your standard session setup.

-- Standard session setup block for production scripts
ALTER SESSION SET TIMEZONE                = 'UTC';
ALTER SESSION SET DATE_INPUT_FORMAT       = 'YYYY-MM-DD';
ALTER SESSION SET DATE_OUTPUT_FORMAT      = 'YYYY-MM-DD';
ALTER SESSION SET TIME_OUTPUT_FORMAT      = 'HH24:MI:SS';
ALTER SESSION SET TIMESTAMP_TYPE_MAPPING  = 'TIMESTAMP_NTZ';
ALTER SESSION SET AUTOCOMMIT              = TRUE;
ALTER SESSION SET QUERY_TAG               = 'workbook:goal-01';

-- Verify all settings applied
SHOW PARAMETERS;

SELECT
    "key"           AS parameter_name,
    "value"         AS current_value,
    "level"         AS set_at_level
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "key" IN (
    'AUTOCOMMIT',
    'TIMEZONE',
    'TIMESTAMP_TYPE_MAPPING',
    'DATE_INPUT_FORMAT',
    'DATE_OUTPUT_FORMAT',
    'TIME_OUTPUT_FORMAT',
    'QUERY_TAG'
)
ORDER BY "key"
;
-- level = SESSION confirms these are session-level overrides
-- They reset to account/default values when session ends

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- Reset session parameters to defaults
ALTER SESSION UNSET TIMEZONE;
ALTER SESSION UNSET DATE_INPUT_FORMAT;
ALTER SESSION UNSET DATE_OUTPUT_FORMAT;
ALTER SESSION UNSET TIME_OUTPUT_FORMAT;
ALTER SESSION UNSET TIMESTAMP_TYPE_MAPPING;
ALTER SESSION UNSET AUTOCOMMIT;
ALTER SESSION UNSET QUERY_TAG;

-- Drop the test table
DROP TABLE IF EXISTS ECOMMERCE.RAW.AUTOCOMMIT_TEST;

-- Verify parameters reset to defaults
SHOW PARAMETERS LIKE 'AUTOCOMMIT';

SELECT "key", "value", "level"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- level should show SYSTEM (back to Snowflake default)

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Set your session timezone to your local timezone.
--    Run SELECT CURRENT_TIMESTAMP() and compare it to UTC.
--    How many hours difference do you see?
--    Reset to UTC when done.
--
-- 2. Recreate the AUTOCOMMIT trap deliberately:
--    a. Create a table with 5 rows
--    b. Run DELETE without BEGIN
--    c. Try ROLLBACK
--    d. Confirm the rows are gone
--    e. Now repeat with BEGIN ... ROLLBACK
--    f. Confirm the rows are still there
--    This exercise will make AUTOCOMMIT unforgettable.
--
-- 3. Set QUERY_TAG to your name and run 3 different queries.
--    Then query INFORMATION_SCHEMA.QUERY_HISTORY to find all
--    three tagged queries. What information does each row show?
--
-- 4. What happens if you set DATE_INPUT_FORMAT = 'DD/MM/YYYY'
--    and then try to load a CSV where dates are in MM/DD/YYYY
--    format? What error would you expect in Goal 2?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I want a parameter to apply permanently for
--    my user without setting it every session?
-- A: Set it at user level:
--    ALTER USER your_username SET TIMEZONE = 'America/New_York';
--    This applies every time you log in without needing to
--    set it in each session. Session-level settings still
--    override it when explicitly set.
--
-- Q: What if I forget to set QUERY_TAG and cannot identify
--    which pipeline ran an expensive query?
-- A: Check ACCOUNT_USAGE.QUERY_HISTORY for the session details —
--    the USER_NAME, WAREHOUSE_NAME, and SESSION_ID can help
--    identify the source even without a tag. Going forward,
--    make QUERY_TAG part of your standard pipeline template.
--    Covered in Goal 9.
--
-- Q: What if AUTOCOMMIT = FALSE causes a session to hold
--    an open transaction for a long time?
-- A: Long-running open transactions can cause table lock
--    contention in Snowflake. Always COMMIT or ROLLBACK
--    explicitly when using AUTOCOMMIT = FALSE. Use
--    SHOW TRANSACTIONS to see open transactions in your
--    session. Covered in Goal 3 Sub-task 3.3.
--
-- Q: What if different team members have different timezone
--    settings and timestamps look different to each person?
-- A: Set TIMEZONE at account level so everyone sees the same
--    timestamps. UTC is the standard recommendation for data
--    engineering — convert to local time only in BI tools
--    at the presentation layer, never in the warehouse itself.
--
-- Q: What if I need different date formats for different
--    pipelines loading from different source systems?
-- A: Set DATE_INPUT_FORMAT at session level at the start of
--    each pipeline script. Each pipeline session can have its
--    own format without affecting other sessions or users.
--    This is one of the most common real-world uses of
--    session-level parameter overrides.
