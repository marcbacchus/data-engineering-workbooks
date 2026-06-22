-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Goal 1 : Set Up Your Environment
-- Sub-task 1.5 : Know your stage types
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~20 minutes
-- Warehouse size   : X-Small (COMPUTE_WH)
-- Database         : ECOMMERCE
-- Prerequisites    : 04_view_types.sql completed
--                    ECOMMERCE database exists with RAW, STAGING,
--                    ANALYTICS schemas
-- COF-C03 domain   : Domain 1 — Architecture & Features (25%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Before you can load data into Snowflake you need somewhere
--   to land it first. That landing zone is called a stage.
--   A stage is a pointer to a location where files live —
--   either inside Snowflake or in cloud object storage.
--
--   Understanding stage types is essential for Goal 2 where
--   you will load the entire e-commerce dataset. Choosing the
--   wrong stage type creates unnecessary complexity, security
--   risk, or cost. This sub-task makes the choice deliberate.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: THE FOUR STAGE TYPES
-- ══════════════════════════════════════════════════════════════
--
--  ┌─────────────────┬──────────────┬───────────┬────────────┐
--  │ Stage type      │ Location     │ Shared?   │ Requires   │
--  │                 │              │           │ CREATE?    │
--  ├─────────────────┼──────────────┼───────────┼────────────┤
--  │ User stage      │ Snowflake    │ No        │ No         │
--  │ Table stage     │ Snowflake    │ No        │ No         │
--  │ Named internal  │ Snowflake    │ Yes       │ Yes        │
--  │ Named external  │ S3/Azure/GCS │ Yes       │ Yes        │
--  └─────────────────┴──────────────┴───────────┴────────────┘
--
-- USER STAGE (@~)
--   Every Snowflake user automatically has a personal stage.
--   Referenced with @~ shorthand. Private to you — no other
--   user can access it. Good for personal, ad-hoc file uploads.
--   Not suitable for team workflows or automation.
--
-- TABLE STAGE (@%tablename)
--   Every table automatically has a stage associated with it.
--   Referenced with @%tablename. Only files for loading into
--   that specific table should go here. Not shared across tables.
--   Useful for simple single-table loads but limited flexibility.
--
-- NAMED INTERNAL STAGE
--   A named object you create explicitly. Lives inside Snowflake
--   storage. Can be shared across users and roles (with grants).
--   The most flexible internal option — supports file format
--   objects, directory tables, and fine-grained access control.
--   Use for: team-based workflows, loading multiple tables,
--   anything that needs to be automated or shared.
--
-- NAMED EXTERNAL STAGE
--   Points to a location in cloud object storage you own —
--   S3 bucket, Azure Blob container, or GCS bucket. Files stay
--   in YOUR storage — Snowflake never copies them unless you
--   explicitly run COPY INTO. Requires storage integration or
--   credentials configuration.
--   Use for: large-scale data ingestion from cloud storage,
--   data lake integration, Snowpipe automation.
--   Covered in depth in Goal 2.
--
-- WHICH TO USE:
--   Personal ad-hoc upload      → user stage (@~)
--   Simple single-table load    → table stage (@%tablename)
--   Team workflow, automation   → named internal stage
--   Cloud storage integration   → named external stage
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

SET my_warehouse = 'COMPUTE_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);

-- Recreate ECOMMERCE if you ran the full cleanup in 1.4
CREATE DATABASE IF NOT EXISTS ECOMMERCE
    COMMENT = 'Workbook e-commerce dataset — Data Engineering Workbook Series'
;
CREATE SCHEMA IF NOT EXISTS ECOMMERCE.RAW
    COMMENT = 'Raw ingested data — source of truth, never modified'
;
CREATE TRANSIENT SCHEMA IF NOT EXISTS ECOMMERCE.STAGING
    COMMENT = 'Cleaned and typed data — transient, no Fail-Safe'
;
CREATE SCHEMA IF NOT EXISTS ECOMMERCE.ANALYTICS
    COMMENT = 'Business-ready tables and views for end-user querying'
;

USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- Create a simple table to demonstrate table stage
CREATE TABLE IF NOT EXISTS ECOMMERCE.RAW.STAGE_DEMO (
    id      INTEGER,
    name    VARCHAR(100),
    value   FLOAT
)
COMMENT = 'Demo table for stage type exercises — dropped in cleanup'
;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: User stage (@~)
-- ══════════════════════════════════════════════════════════════
-- Every user has a personal stage automatically.
-- No CREATE command needed — it always exists.
-- Reference it with @~ in any stage command.

-- List files in your user stage (empty until you PUT files here)
LIST @~;

-- The user stage is personal — only you can see and use it.
-- To upload files to your user stage from your local machine
-- you use the PUT command from SnowSQL (command line client)
-- or from a Snowflake connector. You cannot PUT from Snowsight UI.
--
-- PUT command syntax (run from SnowSQL, not Snowsight):
-- PUT file:///path/to/your/file.csv @~ AUTO_COMPRESS=FALSE;
--
-- We will use named internal stages in Goal 2 instead of user
-- stages — they are more suitable for team workflows and
-- can be used directly from Snowsight via the data loading UI.

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Table stage (@%tablename)
-- ══════════════════════════════════════════════════════════════
-- Every table has a stage automatically — no CREATE needed.
-- Reference it with @% followed by the table name.
-- Only accessible to roles with privileges on that table.

-- List files in the STAGE_DEMO table stage (empty initially)
LIST @%STAGE_DEMO;

-- The table stage is a convenient landing zone for files
-- destined for that specific table. It is automatically
-- scoped to the table — no accidental cross-table loading.
--
-- Limitation: table stages cannot have named file formats
-- applied to them and cannot be shared across tables.
-- For anything beyond a simple single-table load,
-- use a named internal stage instead.

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Named internal stage
-- ══════════════════════════════════════════════════════════════
-- This is what you will use throughout Goal 2 and beyond.
-- A named stage is a first-class Snowflake object —
-- you CREATE it, GRANT access to it, and reference it by name.

-- Create a named internal stage for the e-commerce raw data
CREATE STAGE IF NOT EXISTS ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE
    COMMENT = 'Named internal stage for e-commerce raw CSV files'
;

-- Verify it was created
SHOW STAGES IN SCHEMA ECOMMERCE.RAW;

SELECT
    "name"          AS stage_name,
    "database_name" AS database_name,
    "schema_name"   AS schema_name,
    "url"           AS stage_url,
    "type"          AS stage_type,
    "comment"       AS description
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- stage_type: INTERNAL — confirms this is internal Snowflake storage
-- stage_url:  shows the internal path Snowflake assigned

-- List files in the named stage (empty until files are uploaded)
LIST @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

-- Named stages support file format objects for cleaner COPY INTO
-- We will create file formats and use this stage in Goal 2.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Named external stage (structure only)
-- ══════════════════════════════════════════════════════════════
-- External stages point to cloud storage YOU own.
-- A full external stage requires a storage integration object
-- and credentials — covered in Goal 2 Sub-task 2.2.
--
-- Here we show the CREATE STAGE syntax for each cloud provider
-- so you understand the structure before Goal 2.
-- These are commented out — do not run them without valid
-- credentials and storage integration objects.

-- ── AWS S3 external stage ────────────────────────────────────
-- CREATE STAGE IF NOT EXISTS ECOMMERCE.RAW.S3_EXTERNAL_STAGE
--     URL            = 's3://your-bucket-name/your-prefix/'
--     STORAGE_INTEGRATION = your_s3_integration
--     FILE_FORMAT    = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"')
--     COMMENT        = 'External stage pointing to S3 bucket'
-- ;

-- ── Azure Blob Storage external stage ────────────────────────
-- CREATE STAGE IF NOT EXISTS ECOMMERCE.RAW.AZURE_EXTERNAL_STAGE
--     URL            = 'azure://youraccount.blob.core.windows.net/yourcontainer/'
--     STORAGE_INTEGRATION = your_azure_integration
--     FILE_FORMAT    = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"')
--     COMMENT        = 'External stage pointing to Azure Blob container'
-- ;

-- ── Google Cloud Storage external stage ──────────────────────
-- CREATE STAGE IF NOT EXISTS ECOMMERCE.RAW.GCS_EXTERNAL_STAGE
--     URL            = 'gcs://your-bucket-name/your-prefix/'
--     STORAGE_INTEGRATION = your_gcs_integration
--     FILE_FORMAT    = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"')
--     COMMENT        = 'External stage pointing to GCS bucket'
-- ;

-- KEY DIFFERENCE from internal stages:
-- · Files stay in YOUR cloud storage — Snowflake never copies them
--   unless you run COPY INTO
-- · You pay your cloud provider for storage, not Snowflake
-- · Requires a STORAGE INTEGRATION object for secure credential
--   management (no hardcoded keys in stage definitions)
-- · Enables Snowpipe for continuous automated ingestion

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Survey all stages in the account
-- ══════════════════════════════════════════════════════════════
-- User stages and table stages do not appear in SHOW STAGES —
-- only named stages (internal and external) are listed.
-- This is an important distinction for account administration.

SHOW STAGES IN DATABASE ECOMMERCE;

SELECT
    "name"          AS stage_name,
    "schema_name"   AS schema_name,
    "url"           AS location,
    "type"          AS stage_type,
    "comment"       AS description
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
;
-- Only ECOMMERCE_RAW_STAGE appears here.
-- @~ (user stage) and @%STAGE_DEMO (table stage) are invisible
-- to SHOW STAGES — they are implicit, not named objects.

-- Query INFORMATION_SCHEMA for named stages
SELECT
    STAGE_NAME,
    STAGE_SCHEMA,
    STAGE_TYPE,
    STAGE_URL,
    COMMENT
FROM ECOMMERCE.INFORMATION_SCHEMA.STAGES
ORDER BY STAGE_SCHEMA, STAGE_NAME
;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Grant access to a named stage
-- ══════════════════════════════════════════════════════════════
-- Named stages are securable objects — access is controlled
-- through role-based access control (RBAC).
-- This is a preview of Goal 4 — just enough to understand
-- that stages follow the same privilege model as tables and views.

-- Grant READ access on the stage to SYSADMIN
-- (SYSADMIN will need this to run COPY INTO in Goal 2)
GRANT READ ON STAGE ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE
    TO ROLE SYSADMIN
;

-- Grant WRITE access (ability to PUT files to the stage)
GRANT WRITE ON STAGE ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE
    TO ROLE SYSADMIN
;

-- Verify grants
SHOW GRANTS ON STAGE ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- Option 1 — Remove stage demo objects only
-- Use this if you are continuing to sub-task 1.6
-- ──────────────────────────────────────────────────────────────
-- NOTE: Do NOT drop ECOMMERCE_RAW_STAGE if you are continuing
-- to Goal 2 — you will use it to load the e-commerce dataset.
-- Only drop it here if you are resetting completely.

DROP TABLE IF EXISTS ECOMMERCE.RAW.STAGE_DEMO;
-- DROP STAGE IF EXISTS ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE;

-- Option 2 — Full reset, drop the entire ECOMMERCE database
-- NOTE: Sub-task 1.6 SETUP block will recreate everything needed
-- ──────────────────────────────────────────────────────────────
-- DROP DATABASE IF EXISTS ECOMMERCE;


-- ══════════════════════════════════════════════════════════════
-- WHAT'S NEXT
-- ══════════════════════════════════════════════════════════════
-- The ECOMMERCE_RAW_STAGE you created in Step 3 is ready.
-- In Goal 2 you will:
--   · Upload the e-commerce CSV files to this stage (PUT)
--   · Verify files arrived (LIST)
--   · Load them into tables (COPY INTO)
--   · Monitor load history (LOAD_HISTORY)
--   · Handle load errors (VALIDATE)
--
-- Everything in this sub-task was setup.
-- Goal 2 is where stages come alive.
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Create a second named internal stage called
--    ECOMMERCE_STAGING_STAGE in the ECOMMERCE.STAGING schema.
--    Add a comment describing its purpose.
--    Verify it appears in INFORMATION_SCHEMA.STAGES.
--
-- 2. Run LIST on your user stage (@~), the STAGE_DEMO table
--    stage (@%STAGE_DEMO), and the named stage
--    (@ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE).
--    All three should return zero files.
--    What is the difference in how you reference each one?
--
-- 3. Run SHOW STAGES IN DATABASE ECOMMERCE.
--    How many stages appear?
--    Now run LIST @~ and LIST @%STAGE_DEMO.
--    Why do the user and table stages not appear in SHOW STAGES?

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I PUT a file to the wrong stage in Goal 2?
-- A: Use REMOVE to delete it before running COPY INTO:
--    REMOVE @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE/wrong_file.csv;
--    Or remove all files: REMOVE @stage_name PATTERN='.*';
--    This is safe because files sitting in a stage have no
--    effect on any table until COPY INTO explicitly reads them.
--    Staging and loading are always two separate steps —
--    you can always clean up a stage without touching your tables.
--
-- Q: What if I want to keep files in my own S3 bucket but
--    load them into Snowflake automatically?
-- A: That is Snowpipe with an external stage. Snowpipe monitors
--    your S3 bucket for new files and triggers COPY INTO
--    automatically via cloud event notifications.
--    Covered in Goal 2 Sub-task 2.6.
--
-- Q: What if I drop a named stage — do the files inside get deleted?
-- A: For internal stages yes — the files are deleted along with
--    the stage object. For external stages no — the stage is just
--    a pointer. Dropping the stage removes the Snowflake metadata
--    but leaves your S3/Azure/GCS files completely untouched.
--
-- Q: What if I need to share a stage with another team?
-- A: Grant READ and/or WRITE on the named stage to their role.
--    User stages and table stages cannot be shared —
--    another reason to use named stages for team workflows.
--
-- Q: What is the difference between a stage and an external table?
-- A: A stage is a landing zone — files sit there waiting to be
--    loaded or queried. An external table is a metadata layer
--    that lets you query files in a stage directly using SQL
--    without loading them into Snowflake storage.
--    External tables are covered in Goal 2 Sub-task 2.8.