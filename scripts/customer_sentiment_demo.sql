/*============================================================
  customer_sentiment_demo.sql
  Customer Sentiment Intelligence 
  Prerequisites: Run 00_setup.sql and load_sample_data.sql first.
============================================================*/

USE DATABASE CORTEX_AI_DEMO;
USE SCHEMA SENTIMENT;
USE WAREHOUSE CORTEX_AI_DEMO_WH;

-- ============================================================
-- ACT 1: THE PROBLEM — Unstructured Reviews, No Visibility
-- ============================================================


SELECT
    SOURCE_CHANNEL,
    COUNT(*) AS REVIEW_COUNT,
    ROUND(AVG(RATING), 1) AS AVG_STAR_RATING,
    MIN(REVIEW_DATE) AS EARLIEST_REVIEW,
    MAX(REVIEW_DATE) AS LATEST_REVIEW
FROM RAW_REVIEWS
GROUP BY SOURCE_CHANNEL
ORDER BY REVIEW_COUNT DESC;


-- ============================================================
-- ACT 2: CORTEX SENTIMENT — Instant Scoring at Scale
-- ============================================================

-- One function call. Every review. Real-time.
-- AI_SENTIMENT returns a JSON object with overall sentiment (positive/negative/neutral/mixed).

WITH TOP_REVIEWS AS (
    SELECT *
    FROM RAW_REVIEWS
    ORDER BY REVIEW_DATE DESC
    LIMIT 20
)
SELECT
    REVIEW_ID,
    SOURCE_CHANNEL,
    LOCATION_NAME,
    PRODUCT_NAME,
    RATING AS STAR_RATING,
    REVIEW_TEXT,
    AI_SENTIMENT(REVIEW_TEXT):categories[0]:sentiment::VARCHAR AS SENTIMENT
FROM TOP_REVIEWS
ORDER BY REVIEW_DATE DESC;


-- 2C: Sentiment by Retail Channel — where is the brand strongest?

WITH SCORED_REVIEWS AS (
    SELECT
        SOURCE_CHANNEL,
        RATING,
        AI_SENTIMENT(REVIEW_TEXT):categories[0]:sentiment::VARCHAR AS SENTIMENT
    FROM RAW_REVIEWS
)
SELECT
    SOURCE_CHANNEL,
    COUNT(*) AS REVIEWS,
    ROUND(AVG(RATING), 1) AS AVG_STARS,
    SUM(CASE WHEN SENTIMENT = 'positive' THEN 1 ELSE 0 END) AS POSITIVE,
    SUM(CASE WHEN SENTIMENT = 'negative' THEN 1 ELSE 0 END) AS NEGATIVE,
    SUM(CASE WHEN SENTIMENT = 'mixed' THEN 1 ELSE 0 END) AS MIXED
FROM SCORED_REVIEWS
GROUP BY SOURCE_CHANNEL
ORDER BY NEGATIVE DESC;

-- 2D: Sentiment by Product / Hair Color Shade

WITH SCORED_REVIEWS AS (
    SELECT
        PRODUCT_NAME,
        RATING,
        AI_SENTIMENT(REVIEW_TEXT):categories[0]:sentiment::VARCHAR AS SENTIMENT
    FROM RAW_REVIEWS
)
SELECT
    PRODUCT_NAME,
    COUNT(*) AS REVIEWS,
    ROUND(AVG(RATING), 1) AS AVG_STARS,
    SUM(CASE WHEN SENTIMENT = 'positive' THEN 1 ELSE 0 END) AS POSITIVE,
    SUM(CASE WHEN SENTIMENT = 'negative' THEN 1 ELSE 0 END) AS NEGATIVE,
    SUM(CASE WHEN SENTIMENT = 'mixed' THEN 1 ELSE 0 END) AS MIXED
FROM SCORED_REVIEWS
GROUP BY PRODUCT_NAME
ORDER BY NEGATIVE DESC;

-- 2E: Sentiment by Salon Location

WITH SCORED_REVIEWS AS (
    SELECT
        LOCATION_NAME,
        RATING,
        AI_SENTIMENT(REVIEW_TEXT):categories[0]:sentiment::VARCHAR AS SENTIMENT
    FROM RAW_REVIEWS
    WHERE LOCATION_NAME IS NOT NULL
)
SELECT
    LOCATION_NAME,
    COUNT(*) AS REVIEWS,
    ROUND(AVG(RATING), 1) AS AVG_STARS,
    SUM(CASE WHEN SENTIMENT = 'positive' THEN 1 ELSE 0 END) AS PROMOTERS,
    SUM(CASE WHEN SENTIMENT = 'negative' THEN 1 ELSE 0 END) AS DETRACTORS,
    SUM(CASE WHEN SENTIMENT = 'mixed' THEN 1 ELSE 0 END) AS MIXED
FROM SCORED_REVIEWS
GROUP BY LOCATION_NAME
ORDER BY DETRACTORS DESC;

-- ============================================================
-- ACT 3: CORTEX COMPLETE — Review Intelligence
-- ============================================================

-- Sentiment + LLM analysis side by side.
-- See the score AND the structured "why" for every review.

WITH TOP_REVIEWS AS (
    SELECT *
    FROM RAW_REVIEWS
    ORDER BY REVIEW_DATE DESC
    LIMIT 10
),
ANALYZED AS (
    SELECT
        REVIEW_ID,
        SOURCE_CHANNEL,
        PRODUCT_NAME,
        RATING AS STAR_RATING,
        AI_SENTIMENT(REVIEW_TEXT):categories[0]:sentiment::VARCHAR AS SENTIMENT,
        TRY_PARSE_JSON(REGEXP_REPLACE(SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large2',
            CONCAT(
                'You are a customer experience analyst for a premium hair color brand. ',
                'Analyze this review and return ONLY a JSON object with: ',
                '"topics" (array from: color_quality, gray_coverage, application_ease, packaging, value_for_money, salon_service, longevity, hair_health, shade_accuracy), ',
                '"key_phrase" (most important phrase, max 10 words), ',
                '"action_needed" (none, monitor, or urgent).\n\n',
                'Review (', SOURCE_CHANNEL, ', ', RATING::VARCHAR, ' stars): ', REVIEW_TEXT
            )
        ), '```json?\\n?|```', '')) AS AI_JSON
    FROM TOP_REVIEWS
)
SELECT
    REVIEW_ID,
    SOURCE_CHANNEL,
    PRODUCT_NAME,
    STAR_RATING,
    SENTIMENT,
    AI_JSON:"topics"::VARCHAR AS TOPICS,
    AI_JSON:"key_phrase"::VARCHAR AS KEY_PHRASE,
    AI_JSON:"action_needed"::VARCHAR AS ACTION_NEEDED
FROM ANALYZED
ORDER BY ACTION_NEEDED DESC;

-- ============================================================
-- ACT 4: DYNAMIC TABLE — Always-On Sentiment Pipeline
-- ============================================================

-- Replace batch ETL with a self-maintaining pipeline.
-- New reviews are scored and classified automatically.

CREATE OR REPLACE DYNAMIC TABLE SENTIMENT_INTELLIGENCE
  TARGET_LAG = '1 hour'
  WAREHOUSE = CORTEX_AI_DEMO_WH
  AS
SELECT
    r.REVIEW_ID,
    r.SOURCE_CHANNEL,
    r.LOCATION_NAME,
    r.REVIEW_DATE,
    r.RATING,
    r.REVIEW_TEXT,
    r.PRODUCT_NAME,
    r.REVIEWER_NAME,
    AI_SENTIMENT(r.REVIEW_TEXT):categories[0]:sentiment::VARCHAR AS SENTIMENT,
    SNOWFLAKE.CORTEX.COMPLETE(
        'mistral-large2',
        CONCAT(
            'Analyze this review. Return ONLY valid JSON: ',
            '{"topics":["<from: color_quality,gray_coverage,application_ease,packaging,value_for_money,salon_service,booking,longevity,hair_health,shade_accuracy,shipping,subscription>"],',
            '"product_issue":<bool>,"service_issue":<bool>,"action":"<none|monitor|urgent>","summary":"<1 sentence>"}\n\n',
            'Review (', r.SOURCE_CHANNEL, ', ', r.RATING::VARCHAR, ' stars): ', r.REVIEW_TEXT
        )
    ) AS AI_CLASSIFICATION,
    r.INGESTED_AT
FROM RAW_REVIEWS r;




-- ============================================================
-- TRY IT YOURSELF — Starter Template
-- ============================================================
-- Swap in your own table and text column.

WITH MY_SAMPLE AS (
    SELECT *
    FROM <YOUR_DATABASE>.<YOUR_SCHEMA>.<YOUR_TABLE>
    -- Add any filters here (e.g. WHERE created_date >= '2025-01-01')
    ORDER BY <DATE_COLUMN> DESC
    LIMIT 10
)
SELECT
    <ID_COLUMN>,
    <GROUP_BY_COLUMN>,                -- e.g. region, department, product, rep
    AI_SENTIMENT(<TEXT_COLUMN>):categories[0]:sentiment::VARCHAR AS SENTIMENT,
    TRY_PARSE_JSON(REGEXP_REPLACE(SNOWFLAKE.CORTEX.COMPLETE(
        'mistral-large2',
        CONCAT(
            'Analyze this text and return ONLY a JSON object with: ',
            '"topics" (array of relevant themes), ',
            '"key_phrase" (most important phrase, max 10 words), ',
            '"action_needed" (none, monitor, or urgent).\n\n',
            'Text: ', <TEXT_COLUMN>
        )
    ), '```json?\\n?|```', '')) AS AI_JSON,
    AI_JSON:"topics"::VARCHAR AS TOPICS,
    AI_JSON:"key_phrase"::VARCHAR AS KEY_PHRASE,
    AI_JSON:"action_needed"::VARCHAR AS ACTION_NEEDED
FROM MY_SAMPLE;




/*
  KEY DEMO TALKING POINTS:
  
  1. BEFORE: Reviews scattered across 7 channels, manually read, no real-time signals
  2. AFTER:  Unified sentiment pipeline — every review scored, classified, and actionable
  3. SPEED:  From raw review to insight in seconds, not days
  4. SCALE:  Same SQL works for 20 reviews or 20 million
  5. ALWAYS ON: Dynamic Table auto-refreshes — no batch jobs, no ETL maintenance
  6. NO ML EXPERTISE NEEDED: SQL analysts can run the entire pipeline
  7. DATA NEVER LEAVES SNOWFLAKE: No API calls to external LLMs
*/
