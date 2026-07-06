-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 3  : Query and Transform Data
-- Sub-task 3.6 : Cortex AI functions
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~35 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight
-- Prerequisites    : 05_dml_transactions.sql completed
--                    CORTEX_USER database role granted (see Setup)
-- COF-C03 domain   : Domain 5 — Data Transformations (17%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   The PRODUCT_REVIEWS table has 500,000 rows of free-text
--   customer reviews. That text is unstructured — you cannot
--   GROUP BY it, filter it precisely, or aggregate it with SUM.
--
--   Snowflake Cortex AI changes that. With a single SQL function
--   call you can classify reviews by sentiment, summarise themes
--   across thousands of rows, translate text to other languages,
--   or filter rows using natural language conditions — all inside
--   SQL, all within Snowflake's security boundary, no external
--   API keys required.
--
--   This sub-task covers the Cortex AI functions that data
--   engineers use most frequently in analytical pipelines.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: CORTEX AI FUNCTIONS
-- ══════════════════════════════════════════════════════════════
--
-- Cortex AI functions run LLMs (large language models) directly
-- inside Snowflake SQL. Your data never leaves Snowflake's
-- security perimeter — no external API calls, no data movement.
--
-- CURRENT FUNCTIONS (as of mid-2026):
--
--   AI_COMPLETE(model, prompt)
--     General purpose LLM — generate text, answer questions,
--     extract structured data from unstructured text.
--     Most flexible, most powerful, most expensive.
--
--   AI_CLASSIFY(text, ['cat1', 'cat2', ...])
--     Classify text into one of your defined categories.
--     Returns a VARIANT with a label field.
--     Optimised and cheaper than AI_COMPLETE for classification.
--
--   AI_FILTER(text, condition)
--     Returns TRUE or FALSE for a natural language condition.
--     Use directly in WHERE, HAVING, or JOIN ... ON clauses.
--     Only rows passing the filter are processed — cost efficient.
--
--   AI_AGG(text_column, prompt)
--     Aggregate insights across multiple rows.
--     Not subject to LLM context window limits.
--     Use for: summarise 1,000 reviews, find common themes.
--
--   AI_SENTIMENT(text)
--     Task-specific sentiment analysis.
--     Returns a score from -1 (very negative) to 1 (very positive).
--     Cheaper and faster than AI_COMPLETE for sentiment.
--
--   AI_TRANSLATE(text, source_lang, target_lang)
--     Translate text between languages.
--     Returns translated text as VARCHAR.
--
-- AVAILABLE MODELS:
--   'snowflake-arctic'  — Snowflake's own model, cost-efficient
--   'llama3.1-70b'      — Strong general purpose (Meta)
--   'claude-sonnet-4-6' — Strong reasoning and analysis (Anthropic)
--   Choose smaller models for high-volume simple tasks (classification,
--   sentiment). Use larger models for complex reasoning tasks.
--
-- COST MODEL:
--   Cortex AI functions are billed per token processed.
--   Tokens ≈ 4 characters of text.
--   A 200-word review ≈ 250 tokens input + output tokens.
--   Running AI_COMPLETE on 500,000 reviews is expensive —
--   always filter to a subset first during development.
--   Use AI_FILTER to reduce rows before AI_COMPLETE or AI_AGG.
--
-- NOTE ON LEGACY FUNCTIONS:
--   SNOWFLAKE.CORTEX.COMPLETE(), SNOWFLAKE.CORTEX.SENTIMENT(),
--   and CLASSIFY_TEXT() are deprecated and will be removed
--   by end of 2026. Use the AI_ prefix functions shown here.
--
-- ══════════════════════════════════════════════════════════════
-- ⚠ IMPORTANT: ACCOUNT REQUIREMENT FOR THIS SUB-TASK
-- ══════════════════════════════════════════════════════════════
-- ALL Cortex AI functions (AI_SENTIMENT, AI_CLASSIFY, AI_FILTER,
-- AI_COMPLETE, AI_AGG, AI_TRANSLATE) require a PAID Snowflake
-- account. They are NOT available on the standard $400 trial.
--
-- OPTIONS TO ACCESS CORTEX AI:
--   1. Convert your trial to a paid account
--   2. Sign up for a separate Cortex Code CLI trial at:
--      signup.snowflake.com/cortex-code ($40 inference credits)
--   3. Read through this sub-task as a reference and return
--      to it when you have a paid account
--
-- This sub-task is written as a complete reference. The concepts,
-- syntax, and patterns are accurate and production-ready.
-- Every step is clearly labelled so you know exactly what to
-- run when Cortex AI becomes available on your account.
-- ══════════════════════════════════════════════════════════════
--
-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════


SET my_warehouse = 'WORKBOOK_WH';
ALTER WAREHOUSE IDENTIFIER($my_warehouse) RESUME IF SUSPENDED;
USE WAREHOUSE IDENTIFIER($my_warehouse);
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ── Grant CORTEX_USER role — required for all AI functions ────
-- Run as ACCOUNTADMIN or a role with MANAGE GRANTS privilege
USE ROLE ACCOUNTADMIN;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SYSADMIN;
USE ROLE SYSADMIN;

-- Verify the grant worked — if this runs without error you are ready
SELECT AI_COMPLETE('snowflake-arctic', 'Reply with: Cortex AI is ready') AS test;
-- Expected: "Cortex AI is ready" or similar confirmation

-- Return to SYSADMIN for all remaining steps
USE ROLE SYSADMIN;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- STEP 1: AI_SENTIMENT — score review sentiment
--         Requires: paid Snowflake account
-- ══════════════════════════════════════════════════════════════
-- AI_SENTIMENT returns a score from -1.0 (very negative)
-- to +1.0 (very positive). Fast and cheap — purpose-built
-- for sentiment analysis on large volumes of text.

-- Test on a few sample reviews first — always test before bulk runs
SELECT
    review_id,
    rating,
    LEFT(review_text, 100)              AS review_preview,
    AI_SENTIMENT(review_text)           AS sentiment_score
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
LIMIT 10
;
-- Compare the numeric rating (1-5) to the AI sentiment score (-1 to 1)
-- They should generally align — high ratings = positive sentiment
-- Misalignments are interesting: a 5-star review with negative sentiment
-- suggests the reviewer left a positive rating but wrote a mixed review

-- Sentiment distribution across all ratings
-- Limit rows to control cost during development
SELECT
    rating,
    COUNT(*)                            AS review_count,
    ROUND(AVG(AI_SENTIMENT(review_text)), 3) AS avg_sentiment,
    ROUND(MIN(AI_SENTIMENT(review_text)), 3) AS min_sentiment,
    ROUND(MAX(AI_SENTIMENT(review_text)), 3) AS max_sentiment
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
WHERE review_id <= 1000                 -- limit to 1,000 rows during development
GROUP BY rating
ORDER BY rating
;
-- Expected pattern:
-- Rating 1 → negative sentiment (avg close to -1)
-- Rating 5 → positive sentiment (avg close to +1)
-- Interesting: do any 1-star ratings have positive sentiment?
-- Those are likely sarcastic reviews — AI catches nuance stars do not

-- ══════════════════════════════════════════════════════════════
-- STEP 2: AI_CLASSIFY — classify reviews into categories
--         Requires: paid Snowflake account
-- ══════════════════════════════════════════════════════════════
-- AI_CLASSIFY assigns each row to one of your defined categories.
-- Returns a VARIANT — use :label::VARCHAR to extract the result.

-- Classify reviews by the type of feedback they contain
SELECT
    review_id,
    rating,
    LEFT(review_text, 80)               AS review_preview,
    AI_CLASSIFY(
        review_text,
        ['product_quality', 'shipping_delivery',
         'customer_service', 'value_for_money', 'general_positive']
    ):label::VARCHAR                    AS feedback_category
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
WHERE review_id <= 100                  -- small sample first
ORDER BY review_id
;
-- :label::VARCHAR extracts the category string from the VARIANT result
-- Each review is classified into exactly one category (single-label)
-- Results let you route reviews to the right team for action

-- Aggregate: what proportion of reviews are about each topic?
SELECT
    AI_CLASSIFY(
        review_text,
        ['product_quality', 'shipping_delivery',
         'customer_service', 'value_for_money', 'general_positive']
    ):label::VARCHAR                    AS feedback_category,
    COUNT(*)                            AS review_count,
    ROUND(AVG(rating), 2)               AS avg_rating
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
WHERE review_id <= 500                  -- 500 rows for development
GROUP BY feedback_category
ORDER BY review_count DESC
;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: AI_FILTER — filter rows using natural language
--         Requires: paid Snowflake account
-- ══════════════════════════════════════════════════════════════
-- AI_FILTER returns TRUE or FALSE for a natural language condition.
-- Use it directly in WHERE — only matching rows are returned.
-- More flexible than LIKE but more expensive — use on pre-filtered
-- subsets to control cost.

-- Find reviews that mention delivery problems
SELECT
    review_id,
    rating,
    review_text
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
WHERE review_id <= 200                  -- pre-filter by row number first
  AND AI_FILTER(
        review_text,
        'The review mentions a problem with shipping, delivery, or packaging'
    )
ORDER BY rating ASC                     -- lowest ratings first
LIMIT 10
;
-- AI_FILTER is applied AFTER the row number filter
-- Pre-filtering with cheap conditions (WHERE review_id <= 200)
-- before AI_FILTER reduces cost significantly

-- Find low-rated reviews that are actually positive (sarcastic or mislabeled)
SELECT
    review_id,
    rating,
    review_text,
    AI_SENTIMENT(review_text)           AS sentiment_score
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
WHERE rating = 1                        -- 1-star reviews only
  AND review_id <= 500
  AND AI_FILTER(
        review_text,
        'The review text is generally positive or complimentary'
    )
LIMIT 10
;
-- These are your data quality anomalies — 1-star ratings with
-- positive review text. Useful for cleaning training data or
-- flagging reviews for manual inspection.

-- ══════════════════════════════════════════════════════════════
-- STEP 4: AI_COMPLETE — extract structured data from text
--         Requires: paid Snowflake account
-- ══════════════════════════════════════════════════════════════
-- AI_COMPLETE is the most powerful and flexible function.
-- It takes a model name and a prompt — the prompt can include
-- column values from your table.
-- Best for: extraction, summarisation, complex reasoning.

-- Extract specific product issues from negative reviews
SELECT
    review_id,
    rating,
    review_text,
    AI_COMPLETE(
        'snowflake-arctic',
        'From this product review, extract the main issue in 10 words or fewer.
         If no specific issue is mentioned, respond with "no specific issue".
         Review: ' || review_text
    )                                   AS main_issue
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
WHERE rating <= 2                       -- negative reviews only
  AND review_id <= 50                   -- small sample — AI_COMPLETE is expensive
ORDER BY rating, review_id
;
-- snowflake-arctic is the most cost-efficient model for simple extraction
-- Use llama3.1-70b or claude-sonnet-4-6 for more nuanced tasks

-- Extract a structured summary from a review
SELECT
    review_id,
    rating,
    AI_COMPLETE(
        'llama3.1-70b',
        'Analyse this product review and return a JSON object with these fields:
         - sentiment: positive, neutral, or negative
         - main_topic: the primary subject of the review (one phrase)
         - would_recommend: true or false
         - key_phrase: the most memorable phrase from the review (quoted)

         Review: ' || review_text
    )                                   AS structured_analysis
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
WHERE review_id <= 10                   -- very small sample for complex prompts
ORDER BY review_id
;
-- Complex prompts asking for JSON output cost more tokens.
-- Use llama3.1-70b or larger models for structured extraction —
-- smaller models may not reliably produce valid JSON.
-- Parse the JSON result using PARSE_JSON() for downstream use.

-- ══════════════════════════════════════════════════════════════
-- STEP 5: AI_AGG — aggregate insights across many rows
--         Requires: paid Snowflake account
-- ══════════════════════════════════════════════════════════════
-- AI_AGG works like GROUP BY + AI — it summarises many rows
-- into one insight per group. Not subject to context window limits.
-- Use for: theme analysis, executive summaries, category insights.

-- Summarise the main themes in 1-star reviews per category
SELECT
    p.category,
    COUNT(r.review_id)                  AS review_count,
    AI_AGG(
        r.review_text,
        'What are the top 3 recurring complaints across these
         1-star product reviews? Be specific and concise.
         Format as a numbered list.'
    )                                   AS top_complaints
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS r
INNER JOIN ECOMMERCE.RAW.PRODUCTS p
    ON r.product_id = p.product_id
WHERE r.rating = 1
  AND r.review_id <= 200               -- limit during development
GROUP BY p.category
ORDER BY review_count DESC
LIMIT 5
;
-- AI_AGG reads ALL rows in the group and synthesises insights.
-- The result is one summary per category — powerful for reporting.
-- In production run this on full data (remove the review_id filter)
-- and schedule it weekly to track complaint trends over time.

-- ══════════════════════════════════════════════════════════════
-- STEP 6: AI_TRANSLATE — translate review text
--         Requires: paid Snowflake account
-- ══════════════════════════════════════════════════════════════
-- AI_TRANSLATE translates text between languages.
-- Useful when your customer base is multilingual and you want
-- to standardise reviews into a single language for analysis.

SELECT
    review_id,
    review_text                         AS original_english,
    AI_TRANSLATE(review_text, 'en', 'fr') AS french_translation,
    AI_TRANSLATE(review_text, 'en', 'es') AS spanish_translation
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS
WHERE review_id <= 5                    -- very small sample — translation is expensive
ORDER BY review_id
;
-- Language codes: 'en' English, 'fr' French, 'es' Spanish,
--                 'de' German, 'ja' Japanese, 'pt' Portuguese
-- In production: translate once, store the result, do not re-translate

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Persisting AI results — enrich your tables
--         Requires: paid Snowflake account
-- ══════════════════════════════════════════════════════════════
-- Running AI functions at query time is expensive and slow.
-- Best practice: run AI once, store results, query the stored results.
-- This is called "pre-computing" AI features.

-- Create an enriched reviews table with pre-computed AI features
CREATE OR REPLACE TABLE ECOMMERCE.RAW.PRODUCT_REVIEWS_ENRICHED AS
SELECT
    r.review_id,
    r.product_id,
    r.customer_id,
    r.rating,
    r.review_text,
    r.is_verified,
    r.helpful_votes,
    r.created_at,
    -- Pre-compute AI features once
    AI_SENTIMENT(r.review_text)         AS sentiment_score,
    AI_CLASSIFY(
        r.review_text,
        ['product_quality', 'shipping_delivery',
         'customer_service', 'value_for_money', 'general_positive']
    ):label::VARCHAR                    AS feedback_category
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS r
WHERE r.review_id <= 1000              -- limit during development
                                       -- remove limit for full production run
;

-- Now query the enriched table — fast, no AI compute cost
SELECT
    feedback_category,
    COUNT(*)                            AS review_count,
    ROUND(AVG(rating), 2)               AS avg_star_rating,
    ROUND(AVG(sentiment_score), 3)      AS avg_sentiment
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_ENRICHED
GROUP BY feedback_category
ORDER BY review_count DESC
;

-- Find the mismatch: high star rating but negative sentiment
SELECT
    review_id,
    rating,
    sentiment_score,
    feedback_category,
    review_text
FROM ECOMMERCE.RAW.PRODUCT_REVIEWS_ENRICHED
WHERE rating >= 4
  AND sentiment_score < -0.2           -- positive stars but negative text
ORDER BY sentiment_score ASC
LIMIT 10
;

-- ══════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════
-- Drop the enriched table created in Step 7
-- The original PRODUCT_REVIEWS table is unchanged
DROP TABLE IF EXISTS ECOMMERCE.RAW.PRODUCT_REVIEWS_ENRICHED;

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Using AI_SENTIMENT, find the product (by product_id) with
--    the highest average sentiment score despite having the
--    lowest average star rating. What does that tell you?
--    Limit to products with at least 10 reviews.
--
-- 2. Using AI_CLASSIFY, categorise all 1-star reviews into:
--    'defective_product', 'wrong_item', 'poor_quality',
--    'misleading_description', 'other'
--    Which category is most common for 1-star reviews?
--    Which category has the highest return rate when joined
--    to the RETURNS table?
--
-- 3. Create a PRODUCT_INSIGHTS table using AI_AGG that contains
--    for each product category:
--    · A one-paragraph summary of what customers love
--    · A one-paragraph summary of common complaints
--    · A recommended action for the product team
--    Schedule this as a weekly batch job using a Snowflake Task
--    (covered in Goal 6 — Automate Pipelines).

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if AI functions return inconsistent results?
-- A: LLMs are probabilistic — the same prompt can return slightly
--    different results each run. For classification tasks this
--    variability is usually small. For extraction tasks use
--    precise prompts with explicit format instructions.
--    Store results (Step 7 pattern) rather than re-running
--    so your downstream queries are deterministic.
--
-- Q: What if the AI function hits a context window limit?
-- A: Very long review texts may exceed the model's context window.
--    Truncate input text before passing to the function:
--    AI_COMPLETE(model, 'prompt: ' || LEFT(review_text, 2000))
--    LEFT(text, N) limits to N characters — use LEFT not SUBSTR
--    for context window management.
--    AI_AGG is NOT subject to context window limits — it handles
--    arbitrarily large row sets internally.
--
-- Q: What if I need to process all 500,000 reviews affordably?
-- A: Three cost control strategies:
--    1. Use AI_SENTIMENT and AI_CLASSIFY (task-specific, cheaper)
--       instead of AI_COMPLETE for volume processing.
--    2. Use snowflake-arctic model (cheapest) for simple tasks.
--    3. Pre-filter with cheap SQL conditions before AI functions —
--       AI_FILTER on 50,000 rows costs 10x less than on 500,000.
--    Check current token pricing at docs.snowflake.com before
--    running production bulk jobs.
--
-- Q: What if I need to run AI on data that cannot leave my region?
-- A: Snowflake Cortex runs entirely within Snowflake's infrastructure.
--    Your data never leaves the Snowflake service perimeter.
--    For Business Critical accounts with strict data residency
--    requirements, check CORTEX_ENABLED_CROSS_REGION in your
--    account parameters (covered in Goal 1 Sub-task 1.6).
--    Cross-region inference can be disabled if required.
--
-- Q: What models are available?
-- A: As of mid-2026: snowflake-arctic, llama3.1-70b,
--    claude-sonnet-4-6, and others. Model availability varies
--    by cloud provider and region. Check current availability:
--    SHOW MODELS IN SCHEMA SNOWFLAKE.CORTEX;
--    Or check: docs.snowflake.com/en/user-guide/snowflake-cortex
