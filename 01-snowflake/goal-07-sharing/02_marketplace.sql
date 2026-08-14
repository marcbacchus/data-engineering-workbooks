-- ══════════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 7       : Share and Collaborate
-- Sub-task 7.2 : Use the Snowflake Marketplace
-- ══════════════════════════════════════════════════════════════════
-- ──────────────────────────────────────────────────────────────────
-- Time to complete : 30-40 min
-- Warehouse size    : WORKBOOK_WH (X-Small)
-- Database          : ECOMMERCE
-- Run in            : Snowsight
-- Prerequisites     : Goals 1-6 complete, Goal 7.1 complete.
--                      ACCOUNTADMIN role available.
-- COF-C03 domain    : 5.0 Data Collaboration (10%)
-- ──────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════════
-- 7.1 made YOU the data provider. This sub-task flips the role: you
-- become the consumer, mounting a free third-party dataset from the
-- Snowflake Marketplace and joining it against ECOMMERCE data for
-- enrichment. No file to download, no pipeline to build, no COPY
-- INTO -- the data just appears as a queryable database the moment
-- you click "Get."
--
-- You'll mount a public weather dataset and join it to ORDERS by
-- date and region to see whether weather is a plausible signal
-- behind order volume swings -- a realistic first move any data
-- team makes when asked "why did sales dip that week."

-- ══════════════════════════════════════════════════════════════════
-- CONCEPT
-- ══════════════════════════════════════════════════════════════════
-- The Marketplace is the discovery and provisioning layer built on
-- top of the same secure data sharing mechanism from 7.1. A listing
-- is a provider's packaged, publicly (or privately) discoverable
-- share. When you click "Get," Snowflake mounts that provider's
-- share as a new database in your account -- same zero-copy
-- mechanics you used yourself in 7.1, just with a storefront in
-- front of it.
--
-- Two listing types you'll encounter:
--   STANDARD  -- free or instantly-approved, data appears immediately.
--   PERSONALIZED -- requires the provider to approve your specific
--                    request first (common for paid/enterprise data).
--
-- The critical property for data engineering: a mounted listing is
-- LIVE. The provider updates their share, and your mounted database
-- reflects it immediately -- no refresh job, no re-ingestion, no
-- staleness to manage. This is the same "nothing is copied" property
-- from 7.1, just consumed instead of produced.
--
-- Provider side (conceptual, not hands-on here): publishing a
-- listing means wrapping a share (exactly like the one you built in
-- 7.1) with marketing metadata -- title, description, sample
-- queries, usage terms, pricing tier -- and submitting it either to
-- the public Marketplace or a private data exchange scoped to a
-- specific set of consumer accounts.
--
-- ── Oracle / SQL Server comparison ──────────────────────────────
-- Neither has an equivalent discovery layer. Getting third-party
-- data into an Oracle or SQL Server environment traditionally means
-- a vendor FTP/S3 drop, a licensing negotiation, a custom ETL job to
-- ingest and normalize their file format, and a scheduled refresh
-- job to keep it current -- all of which you own and maintain
-- forever. The Marketplace collapses all of that into "click Get."
-- ─────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKBOOK_WH;

-- ══════════════════════════════════════════════════════════════════
-- STEP 1: Browse and mount a free listing
-- ══════════════════════════════════════════════════════════════════
-- In Snowsight:
--   1. Left pane -> 'Marketplace' -> 'Snowflake Marketplace'
--   2. Search: 'weather frostbyte'
--   3. Select 'Pelmorex Weather Source: Frostbyte' (confirmed live --
--      this is the current name; it was 'Weather Source LLC:
--      frostbyte' previously, so search by keyword, not exact title,
--      since providers do rename listings)
--   4. Click 'Get' -> in the dialog, click 'Options' to expand
--   5. Change the database name from the default
--      (Pelmorex_Weather_Source_Frostbyte) to: WORKBOOK_WEATHER
--   6. Role dropdown: select PUBLIC
--   7. Click 'Get' -- confirmed free, no storage cost, instantly
--      accessible, hourly-updated data
--   8. In the confirmation dialog, click 'Done' (or 'Query Data' to
--      jump straight into a worksheet against it)

-- ══════════════════════════════════════════════════════════════════
-- STEP 2: Confirm the mount and inspect what you got
-- ══════════════════════════════════════════════════════════════════
-- A mounted listing behaves exactly like the database you created
-- FROM SHARE in 7.1 -- because that's what it is.

SHOW DATABASES LIKE 'WORKBOOK_WEATHER';

-- Used to identify the actual schema/table names before writing the
-- join in STEP 3 -- Marketplace providers name things inconsistently,
-- don't assume a schema/table name from documentation matches what
-- you actually got:
SHOW SCHEMAS IN DATABASE WORKBOOK_WEATHER;
SHOW TABLES IN DATABASE WORKBOOK_WEATHER;

-- If SHOW TABLES returns nothing, the listing exposes its data as
-- secure views instead of base tables -- confirmed live for this
-- listing. Same "don't expose the underlying object" pattern from
-- 7.1, just on the provider's side instead of yours:
SHOW VIEWS IN DATABASE WORKBOOK_WEATHER;

-- ══════════════════════════════════════════════════════════════════
-- STEP 3: Join the mounted data against ECOMMERCE for enrichment
-- ══════════════════════════════════════════════════════════════════
-- Confirmed live from the listing's own sample queries: schema is
-- onpoint_id, table is history_day (daily) / forecast_day (forward-
-- looking), keyed on postal_code + country + date_valid_std -- not
-- a generic region/date pair.
--
-- IMPORTANT COVERAGE LIMITATION: this free tier only covers ~1,000
-- sampled US zip codes plus a small set of named international city
-- centers (the listing's own sample queries confirm Boston, Paris,
-- London, Tokyo, and Sydney specifically). It is NOT full global
-- postal coverage. A naive join on ECOMMERCE.RAW.CUSTOMERS.COUNTRY
-- will mostly return nothing, since most postal codes in synthetic
-- ecommerce data won't exist in this sample. The honest join uses a
-- small representative mapping instead -- one covered postal code
-- per country, using the same five cities the provider's own sample
-- queries demonstrate coverage for.
--
-- ALSO CONFIRMED LIVE: ECOMMERCE.RAW.CUSTOMERS.country stores full
-- country names ('United States'), while the weather listing keys
-- on ISO country codes ('US') -- these don't match directly, so the
-- mapping table below carries both forms rather than a single
-- shared country column.

CREATE OR REPLACE TABLE ECOMMERCE.RAW.WEATHER_MARKET_MAP (
    customer_country  VARCHAR,  -- matches ECOMMERCE.RAW.CUSTOMERS.country (full name)
    iso_country       VARCHAR,  -- matches WORKBOOK_WEATHER's country column (ISO code)
    postal_code       VARCHAR,
    market_city       VARCHAR
);

-- Confirmed live: ECOMMERCE.RAW.CUSTOMERS.country stores full names
-- (e.g. 'United States'), while the weather listing keys on ISO
-- country codes (e.g. 'US') -- these do not match directly, hence
-- the two separate country columns above instead of one.
INSERT INTO ECOMMERCE.RAW.WEATHER_MARKET_MAP VALUES
    ('United States',  'US', '02201',    'Boston'),
    ('France',         'FR', '75008',    'Paris'),
    ('United Kingdom', 'GB', 'SW1A 0AA', 'London'),
    ('Japan',          'JP', '102-0082', 'Tokyo'),
    ('Australia',      'AU', '2000',     'Sydney');

CREATE OR REPLACE VIEW ECOMMERCE.RAW.DAILY_ORDERS_WEATHER AS
SELECT
    o.created_at,
    m.market_city,
    m.customer_country,
    COUNT(DISTINCT o.order_id)         AS order_count,
    SUM(o.order_total)                 AS daily_revenue,
    w.avg_temperature_air_2m_f,
    w.tot_precipitation_in
FROM ECOMMERCE.RAW.ORDERS o
JOIN ECOMMERCE.RAW.CUSTOMERS c
    ON c.customer_id = o.customer_id
JOIN ECOMMERCE.RAW.WEATHER_MARKET_MAP m
    ON m.customer_country = c.country
JOIN WORKBOOK_WEATHER.onpoint_id.history_day w
    ON w.postal_code = m.postal_code
   AND w.country = m.iso_country
   AND w.date_valid_std = o.created_at
GROUP BY o.created_at, m.market_city, m.customer_country,
         w.avg_temperature_air_2m_f, w.tot_precipitation_in;

SELECT *
FROM ECOMMERCE.RAW.DAILY_ORDERS_WEATHER
ORDER BY created_at DESC
LIMIT 20;

-- ══════════════════════════════════════════════════════════════════
-- STEP 4: No teardown needed for the mounted database itself
-- ══════════════════════════════════════════════════════════════════
-- Unlike 7.1's reader account, a mounted Marketplace database is
-- metadata-only on your side -- no warehouse, no managed account, no
-- ongoing background cost beyond the compute YOU spend querying it
-- with your own warehouse (already covered by WORKBOOK_WH's existing
-- auto-suspend). Nothing here needs the ⚠️ cost-warning treatment
-- from 7.1.
--
-- If you want to remove it when you're done with the workbook:
-- DROP DATABASE IF EXISTS WORKBOOK_WEATHER;
-- DROP VIEW IF EXISTS ECOMMERCE.RAW.DAILY_ORDERS_WEATHER;

-- ══════════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════════
-- 1. Add a sixth market to WEATHER_MARKET_MAP for a country in your
--    CUSTOMERS data that isn't already covered, using one of the
--    listing's other confirmed-working sample postal codes, or your
--    own zip if you're US-based (the sample covers ~1,000 US codes).
-- 2. Run DESCRIBE SHARE against the underlying share for your
--    mounted listing (find its name via SHOW SHARES -- Marketplace
--    mounts are backed by real INBOUND shares) and compare its
--    structure to the share you built by hand in 7.1.
-- 3. Check whether your mounted listing auto-refreshes: note today's
--    row count in onpoint_id.history_day for one postal code, come
--    back in a day or two, and compare. No action on your part
--    should be required for the count to change -- it's a live,
--    hourly-updated share, not a static extract.

-- ══════════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════════
-- Q: What if the free listing I want requires approval instead of
--    instant access?
-- A: That's a PERSONALIZED listing. Clicking "Request" instead of
--    "Get" sends the provider a request; you get notified once
--    they approve it, then the database mounts the same way a
--    STANDARD listing does. There's no separate consumption
--    mechanism to learn -- only the approval gate differs.
--
-- Q: What if I need to combine data from two different Marketplace
--    providers in a single query?
-- A: You can -- each mounted listing is just another database, and
--    ordinary cross-database joins work. The one restriction to
--    know: a row access policy that references a mapping table from
--    a DIFFERENT provider's share than the table it's protecting
--    will fail for a consumer, per Snowflake's cross-provider policy
--    restriction (a variant of the same policy/sharing interaction
--    from 7.1's WHAT IF).
--
-- Q: What if the provider stops maintaining the listing or pulls it
--    from the Marketplace?
-- A: Your mounted database stops receiving updates and queries
--    against it will eventually fail once the provider's share is
--    revoked. Nothing is copied to your account, so there's no local
--    fallback -- this is the tradeoff for zero-copy, always-live
--    access: you depend on the provider continuing to publish.
--
-- Q: What if the first query against a mounted listing is slow, then
--    a re-run is nearly instant?
-- A: Confirmed live: 27 seconds cold, 878ms on immediate re-run.
--    Result caching works normally against shared objects -- the
--    provider's underlying micro-partitions aren't copied anywhere,
--    but Snowflake still caches YOUR query result the same as it
--    would for any table you own. The first run pays full scan cost
--    (no clustering visibility into a table you don't own, per
--    Goal 5's discovery that MV/clustering internals aren't
--    inspectable on objects you don't have OWNERSHIP on); the second
--    run just serves the cached result. Don't mistake first-query
--    latency on a share for a sharing-mechanism problem -- rerun
--    before concluding anything's wrong.
--
-- A: You'd wrap a share you already know how to build (7.1) with a
--    listing definition in Snowsight's Provider Studio -- title,
--    description, sample queries, and either PUBLIC (open
--    Marketplace) or PRIVATE (specific consumer accounts only,
--    functionally a data exchange) visibility. The share mechanics
--    underneath are identical to what you built in 7.1.
