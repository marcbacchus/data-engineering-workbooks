-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 4  : Secure Your Environment
-- Sub-task 4.6 : Tag-based governance
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~40 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : Sub-tasks 4.1-4.5 complete
--                    Enterprise Edition or higher
-- COF-C03 domain   : Domain 4 — Data Governance and Security (23%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Sub-task 4.4 attached masking policies one column at a time,
--   with ALTER TABLE ... SET MASKING POLICY. That works, but it
--   has a real limitation you already hit: there's no future-grant
--   equivalent for masking, so every new column needing the same
--   protection means writing another ALTER TABLE statement by
--   hand, forever.
--
--   Tags solve this differently: bind a masking policy to a TAG
--   instead of a column, then apply the tag to as many columns as
--   you want — including ones that don't exist yet. Tagging a new
--   column is a one-line statement; the masking logic itself never
--   has to be touched again. This sub-task rebuilds the FIRST_NAME/
--   LAST_NAME masking from Sub-task 4.4's Practice Gap using tags
--   instead of direct attachment, then shows the payoff: applying
--   protection to a brand-new column with zero new policy code.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: TAGS AND TAG-BASED MASKING
-- ══════════════════════════════════════════════════════════════
--
-- A TAG is a schema-level object, same family as tables, masking
-- policies, and row access policies. On its own, a tag is just a
-- label — a key with a controlled set of allowed values, applied
-- to a column, table, schema, or database for classification and
-- inventory purposes. That's tag use case #1: pure metadata, no
-- enforcement.
--
-- Tag use case #2 — the one this sub-task focuses on — binds a
-- MASKING POLICY to the tag itself, with ALTER TAG ... SET MASKING
-- POLICY. Once that binding exists, applying the tag to ANY column
-- of a matching data type automatically applies that masking
-- policy to it, with no separate ALTER TABLE ... SET MASKING
-- POLICY needed. The tag becomes the trigger; tagging a column IS
-- applying the protection.
--
-- Two privileges govern this, extending the same pattern from
-- Sub-tasks 4.4 and 4.5:
--
--   CREATE TAG     schema-level — automatically granted to the
--                  schema OWNER (SYSADMIN), same as CREATE MASKING
--                  POLICY and CREATE ROW ACCESS POLICY
--   APPLY TAG      ACCOUNT-level (global) — lets a role ATTACH a
--                  tag to an object. Held only by ACCOUNTADMIN by
--                  default, same restriction pattern as APPLY
--                  MASKING POLICY and APPLY ROW ACCESS POLICY.
--
-- Binding a masking policy TO a tag additionally requires APPLY
-- MASKING POLICY — the same privilege MASKING_ADMIN already holds
-- from Sub-task 4.4. This sub-task simply extends MASKING_ADMIN
-- with CREATE TAG and APPLY TAG rather than building a separate
-- role, since in a centralized governance model the same team
-- typically owns both mechanisms.
--
-- ── One masking policy per tag, per data type ─────────────────
-- A tag can carry at most one masking policy for a given data
-- type. Tagging a VARCHAR column and a NUMBER column with the same
-- tag requires two separate ALTER TAG ... SET MASKING POLICY
-- bindings — one per data type — even though it's a single tag.
-- ─────────────────────────────────────────────────────────────
--
-- ── Oracle / SQL Server comparison ───────────────────────────
-- Neither Oracle nor SQL Server has a native equivalent to tag-
-- driven masking as a core RDBMS feature. Oracle's nearest parallel
-- is typically a third-party or add-on data classification/catalog
-- layer (e.g. Oracle Data Safe's sensitive data discovery) sitting
-- on top of DBMS_REDACT policies that still have to be registered
-- per column. Snowflake's version — classification and enforcement
-- tied together in one schema-level object — is closer to what
-- data catalog tools bolt onto other platforms, built directly
-- into the database instead.
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
-- STEP 1: Extend MASKING_ADMIN with tag privileges
-- ══════════════════════════════════════════════════════════════

-- APPLY TAG is account-level, held only by ACCOUNTADMIN by
-- default — same pattern as APPLY MASKING POLICY (Sub-task 4.4)
-- and APPLY ROW ACCESS POLICY (Sub-task 4.5)
USE ROLE ACCOUNTADMIN;

GRANT APPLY TAG ON ACCOUNT TO ROLE MASKING_ADMIN;

-- CREATE TAG is schema-level — SYSADMIN, as schema owner, grants
-- it directly
USE ROLE SYSADMIN;

GRANT CREATE TAG ON SCHEMA ECOMMERCE.RAW TO ROLE MASKING_ADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Create the tags
-- ══════════════════════════════════════════════════════════════
-- PII_TAG will drive masking. SEGMENT_TAG is classification-only —
-- no masking policy will ever be bound to it, demonstrating tag
-- use case #1 (metadata/inventory) alongside use case #2 (masking
-- trigger) in the same sub-task.

USE ROLE MASKING_ADMIN;
USE SECONDARY ROLES NONE;

CREATE OR REPLACE TAG ECOMMERCE.RAW.PII_TAG
    COMMENT = 'Applied to columns containing personal name data — drives NAME_MASK';

-- ALLOWED_VALUES restricts this tag to a controlled vocabulary —
-- values placeholder-only (VIP/Standard/Enterprise); confirm the
-- real SEGMENT values in CUSTOMERS before treating this as final.
CREATE OR REPLACE TAG ECOMMERCE.RAW.SEGMENT_TAG
    ALLOWED_VALUES 'VIP', 'Standard', 'Enterprise'
    COMMENT = 'Classification only — no masking policy bound to this tag';

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Write the masking policy the tag will bind to
-- ══════════════════════════════════════════════════════════════
-- Same idea as Sub-task 4.4 Practice Gap exercise 1 — first
-- character visible, rest asterisked — but this time attached via
-- a tag instead of a direct ALTER TABLE statement.

CREATE OR REPLACE MASKING POLICY ECOMMERCE.RAW.NAME_MASK AS (val STRING)
    RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('PII_VIEWER', 'SYSADMIN') THEN val
        ELSE LEFT(val, 1) || REPEAT('*', GREATEST(LENGTH(val) - 1, 0))
    END
;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Bind the masking policy to the tag
-- ══════════════════════════════════════════════════════════════
-- This is the step that turns PII_TAG from a plain label into a
-- masking trigger. No column has been touched yet.

ALTER TAG ECOMMERCE.RAW.PII_TAG SET MASKING POLICY ECOMMERCE.RAW.NAME_MASK;

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Apply the tag to existing columns
-- ══════════════════════════════════════════════════════════════
-- Tagging IS applying the protection — no separate SET MASKING
-- POLICY statement needed on either column.

ALTER TABLE ECOMMERCE.RAW.CUSTOMERS MODIFY COLUMN FIRST_NAME
    SET TAG ECOMMERCE.RAW.PII_TAG = 'name';

ALTER TABLE ECOMMERCE.RAW.CUSTOMERS MODIFY COLUMN LAST_NAME
    SET TAG ECOMMERCE.RAW.PII_TAG = 'name';

-- Classification-only tag — SEGMENT_TAG has no masking policy
-- bound to it, so this has zero effect on query results. It exists
-- purely so SEGMENT shows up in a tag-based inventory (Step 8).
ALTER TABLE ECOMMERCE.RAW.CUSTOMERS MODIFY COLUMN SEGMENT
    SET TAG ECOMMERCE.RAW.SEGMENT_TAG = 'Standard';

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Prove tag-driven masking works
-- ══════════════════════════════════════════════════════════════
-- Using ANALYST_EUROPE here, not DATA_ANALYST — CUSTOMERS now has
-- a row access policy from Sub-task 4.5, and DATA_ANALYST isn't
-- mapped to any region in REGION_ACCESS_MAP, isn't MANAGER, and
-- isn't SYSADMIN. Querying as DATA_ANALYST here would return ZERO
-- rows before masking even has a chance to apply — the row access
-- policy runs first (Sub-task 4.5's CONCEPT) and filters everything
-- out. ANALYST_EUROPE holds ECOMMERCE_READ (masking-eligible) AND
-- is mapped to a real region (row-access-eligible), so it can
-- actually demonstrate masking here.

USE ROLE ANALYST_EUROPE;
USE SECONDARY ROLES NONE;

SELECT customer_id, first_name, last_name
FROM ECOMMERCE.RAW.CUSTOMERS
LIMIT 5
;
-- Europe rows only (row access), FIRST_NAME/LAST_NAME masked to
-- first-character-plus-asterisks (tag-driven masking) — both
-- policies applying together, same as Sub-task 4.5 Practice Gap
-- exercise 2 previewed

-- PII_VIEWER would hit the same problem as DATA_ANALYST above —
-- it's not in REGION_ACCESS_MAP, not MANAGER, not SYSADMIN, so row
-- access would filter it to zero rows too. Using SYSADMIN instead:
-- it's explicitly named in BOTH the row access policy (sees every
-- region) AND NAME_MASK's CASE logic (sees real names) — the only
-- role in this workbook currently exempt from both at once.
USE ROLE SYSADMIN;
USE SECONDARY ROLES NONE;

SELECT customer_id, first_name, last_name
FROM ECOMMERCE.RAW.CUSTOMERS
LIMIT 5
;
-- All regions visible, full names visible

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 7: The payoff — protect a new column with zero new policy
--         code
-- ══════════════════════════════════════════════════════════════
-- SUPPLIERS presumably has a contact name column from Goal 2.
-- Tagging it is the ENTIRE fix — compare this to Sub-task 4.4's
-- WHAT IF, which noted every new column needs its own ALTER TABLE
-- ... SET MASKING POLICY statement. Tags remove that requirement
-- for anything already tagged with PII_TAG.

USE ROLE MASKING_ADMIN;
USE SECONDARY ROLES NONE;

ALTER TABLE ECOMMERCE.RAW.SUPPLIERS MODIFY COLUMN CONTACT_NAME
    SET TAG ECOMMERCE.RAW.PII_TAG = 'name';

USE ROLE DATA_ANALYST;
USE SECONDARY ROLES NONE;

SELECT supplier_id, contact_name
FROM ECOMMERCE.RAW.SUPPLIERS
LIMIT 5
;
-- Masked immediately — NAME_MASK was never written or attached
-- specifically for SUPPLIERS; tagging the column was enough

USE ROLE SYSADMIN;

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Audit — find every column carrying a given tag
-- ══════════════════════════════════════════════════════════════
-- TAG_REFERENCES answers "what does this tag actually protect,
-- account-wide" — the tag equivalent of Sub-task 4.4's
-- POLICY_REFERENCES.

SELECT *
FROM TABLE(
    ECOMMERCE.INFORMATION_SCHEMA.TAG_REFERENCES(
        'ECOMMERCE.RAW.CUSTOMERS.FIRST_NAME', 'COLUMN'
    )
)
;

-- Confirm SEGMENT_TAG shows up too, even with no masking policy
-- bound to it — proving classification-only tags are equally
-- visible to this kind of audit
SELECT *
FROM TABLE(
    ECOMMERCE.INFORMATION_SCHEMA.TAG_REFERENCES(
        'ECOMMERCE.RAW.CUSTOMERS.SEGMENT', 'COLUMN'
    )
)
;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Tag ORDERS.SHIPPING_METHOD or another VARCHAR column of your
--    choosing with PII_TAG (it doesn't have to make real business
--    sense — this is purely to prove the mechanism). Confirm
--    NAME_MASK now applies to it as DATA_ANALYST, with no new
--    ALTER TABLE ... SET MASKING POLICY statement written.
--
-- 2. Run ALTER TAG ECOMMERCE.RAW.PII_TAG UNSET MASKING POLICY,
--    then re-run Step 6's DATA_ANALYST query. Confirm FIRST_NAME
--    and LAST_NAME are no longer masked — unbinding the policy
--    from the tag removes protection everywhere the tag is
--    applied, in one statement. Re-bind NAME_MASK afterward to
--    restore protection.
--
-- 3. Query TAG_REFERENCES_ALL_COLUMNS (the table-scoped, multi-
--    column version) against CUSTOMERS to see every tag applied
--    to every column in one result set, rather than checking one
--    column at a time as Step 8 does.
--
-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I need the same tag to mask both a VARCHAR column and
--    a NUMBER column?
-- A: One binding per data type — see CONCEPT above. Run a second
--    ALTER TAG ... SET MASKING POLICY with a policy whose signature
--    matches the other data type; the tag can hold both bindings
--    simultaneously, applied based on each tagged column's actual
--    type.
--
-- Q: What if I remove the tag from a column — does that delete the
--    masking policy?
-- A: No. Removing the tag from a column (UNSET TAG) only removes
--    that column's exposure to whatever policy the tag carries.
--    The masking policy object and the tag object both continue
--    to exist, and the tag can still be re-applied later or bound
--    to a different policy entirely.
--
-- Q: What if this seems like it solves Sub-task 4.4's "no future
--    grants for masking" problem?
-- A: It effectively does, for the common case. You still can't
--    make a BRAND NEW column arrive pre-tagged automatically (there
--    is no future-grant equivalent for tags either) — but tagging
--    an existing or newly created column is a single, short ALTER
--    statement, compared to writing out a full masking policy
--    attachment by hand each time. Step 7 above is this exact
--    scenario in practice.
--
-- Q: What if a role has APPLY TAG but not APPLY MASKING POLICY?
-- A: It can apply and remove tags freely, including PII_TAG — but
--    it cannot bind or change what masking policy (if any) that tag
--    carries. Applying a tag and controlling what the tag DOES are
--    two separate privileges, deliberately, so tagging/classification
--    work can be delegated without also delegating control over
--    the enforcement logic itself.
--
-- Q: What is different from Oracle I should watch for in this
--    sub-task specifically?
-- A: Key differences:
--    · Tag-based masking has no native Oracle equivalent — the
--      closest parallel is a bolted-on data catalog/classification
--      tool, not a core database feature
--    · CREATE TAG / APPLY TAG follow the same schema-level/
--      account-level privilege split established for masking and
--      row access policies — a pattern Oracle's privilege model
--      doesn't mirror
--    · A single Snowflake tag can simultaneously serve pure
--      classification (SEGMENT_TAG here) and active enforcement
--      (PII_TAG here) — Oracle draws a harder line between
--      metadata/classification tools and enforcement mechanisms
-- ══════════════════════════════════════════════════════════════
