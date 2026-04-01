/*============================================================
  03_sentiment_at_scale.sql — Sentiment at Scale with Dynamic Tables
  
  Demonstrates scaling Cortex sentiment analysis from a small
  experiment to an operational pipeline across all channels
  using Dynamic Tables for automated refresh.
  
  Prerequisites: Run 00_setup.sql and load sample data first.
============================================================*/

USE DATABASE CORTEX_AI_DEMO;
USE SCHEMA SENTIMENT;
USE WAREHOUSE CORTEX_AI_DEMO_WH;

/*------------------------------------------------------------
  Step 1: Explore raw reviews across channels
------------------------------------------------------------*/

SELECT 
    SOURCE_CHANNEL,
    COUNT(*) AS REVIEW_COUNT,
    ROUND(AVG(RATING), 1) AS AVG_RATING,
    MIN(REVIEW_DATE) AS EARLIEST,
    MAX(REVIEW_DATE) AS LATEST
FROM RAW_REVIEWS
GROUP BY SOURCE_CHANNEL
ORDER BY REVIEW_COUNT DESC;

/*------------------------------------------------------------
  Step 2: Apply Cortex SENTIMENT to reviews
  
  Now we run it across ALL reviews from ALL channels.
------------------------------------------------------------*/

SELECT
    REVIEW_ID,
    SOURCE_CHANNEL,
    LOCATION_NAME,
    RATING,
    LEFT(REVIEW_TEXT, 100) AS REVIEW_PREVIEW,
    SNOWFLAKE.CORTEX.SENTIMENT(REVIEW_TEXT) AS SENTIMENT_SCORE,
    CASE
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(REVIEW_TEXT) > 0.3 THEN 'Positive'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(REVIEW_TEXT) < -0.3 THEN 'Negative'
        ELSE 'Neutral'
    END AS SENTIMENT_LABEL
FROM RAW_REVIEWS
ORDER BY REVIEW_DATE DESC
LIMIT 20;

/*------------------------------------------------------------
  Step 3: Use Cortex COMPLETE for rich classification
  
  Go beyond sentiment — classify reviews by topic, detect
  product issues, and identify service quality signals.
------------------------------------------------------------*/

SELECT
    REVIEW_ID,
    SOURCE_CHANNEL,
    LOCATION_NAME,
    PRODUCT_NAME,
    RATING,
    SNOWFLAKE.CORTEX.COMPLETE(
        'mistral-large2',
        'Classify this hair color product review. Return a JSON object with these fields:
        - sentiment: "positive", "negative", or "neutral"
        - topics: array of topics from [color_accuracy, gray_coverage, hair_condition, ease_of_use, value_for_money, packaging, scent, longevity, salon_service, booking_experience]
        - product_issue: true/false (is there a product defect or quality complaint?)
        - service_issue: true/false (is there a salon service complaint?)
        - summary: one sentence summary of the review
        
        Review: ' || REVIEW_TEXT
    ) AS CLASSIFICATION
FROM RAW_REVIEWS
WHERE REVIEW_DATE >= DATEADD('day', -30, CURRENT_DATE())
LIMIT 10;

/*------------------------------------------------------------
  Step 4: Create a Dynamic Table pipeline
  
  This is the key architectural upgrade — replacing periodic
  batch processing with an always-on, auto-refreshing pipeline.
  New reviews get classified automatically.
------------------------------------------------------------*/

CREATE OR REPLACE DYNAMIC TABLE CLASSIFIED_REVIEWS
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
    SNOWFLAKE.CORTEX.SENTIMENT(r.REVIEW_TEXT) AS SENTIMENT_SCORE,
    CASE
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(r.REVIEW_TEXT) > 0.3 THEN 'Positive'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(r.REVIEW_TEXT) < -0.3 THEN 'Negative'
        ELSE 'Neutral'
    END AS SENTIMENT_LABEL,
    r.INGESTED_AT
FROM RAW_REVIEWS r;

/*------------------------------------------------------------
  Step 5: Build operational dashboards (queries for Looker/Hex)
------------------------------------------------------------*/

-- NPS by Salon location
SELECT
    LOCATION_NAME,
    COUNT(*) AS TOTAL_REVIEWS,
    ROUND(AVG(SENTIMENT_SCORE), 3) AS AVG_SENTIMENT,
    SUM(CASE WHEN SENTIMENT_LABEL = 'Positive' THEN 1 ELSE 0 END) AS POSITIVE,
    SUM(CASE WHEN SENTIMENT_LABEL = 'Negative' THEN 1 ELSE 0 END) AS NEGATIVE,
    ROUND(
        (SUM(CASE WHEN SENTIMENT_LABEL = 'Positive' THEN 1 ELSE 0 END)::FLOAT 
         - SUM(CASE WHEN SENTIMENT_LABEL = 'Negative' THEN 1 ELSE 0 END)::FLOAT) 
        / NULLIF(COUNT(*), 0) * 100, 1
    ) AS NPS_PROXY
FROM CLASSIFIED_REVIEWS
WHERE REVIEW_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY LOCATION_NAME
ORDER BY NPS_PROXY DESC;

-- Product defect early warning — sentiment drops by product
SELECT
    PRODUCT_NAME,
    DATE_TRUNC('week', REVIEW_DATE) AS REVIEW_WEEK,
    COUNT(*) AS REVIEWS,
    ROUND(AVG(SENTIMENT_SCORE), 3) AS AVG_SENTIMENT,
    SUM(CASE WHEN SENTIMENT_LABEL = 'Negative' THEN 1 ELSE 0 END) AS NEGATIVE_COUNT,
    ROUND(SUM(CASE WHEN SENTIMENT_LABEL = 'Negative' THEN 1 ELSE 0 END)::FLOAT 
          / NULLIF(COUNT(*), 0) * 100, 1) AS NEGATIVE_PCT
FROM CLASSIFIED_REVIEWS
GROUP BY PRODUCT_NAME, REVIEW_WEEK
HAVING REVIEWS >= 5
ORDER BY REVIEW_WEEK DESC, NEGATIVE_PCT DESC
LIMIT 30;

-- Channel comparison — sentiment by sales channel
SELECT
    SOURCE_CHANNEL,
    COUNT(*) AS TOTAL_REVIEWS,
    ROUND(AVG(RATING), 1) AS AVG_RATING,
    ROUND(AVG(SENTIMENT_SCORE), 3) AS AVG_SENTIMENT,
    ROUND(SUM(CASE WHEN SENTIMENT_LABEL = 'Positive' THEN 1 ELSE 0 END)::FLOAT 
          / NULLIF(COUNT(*), 0) * 100, 1) AS POSITIVE_PCT
FROM CLASSIFIED_REVIEWS
GROUP BY SOURCE_CHANNEL
ORDER BY AVG_SENTIMENT DESC;

/*------------------------------------------------------------
  Step 6: Alert pattern — detect sentiment anomalies
  
  This query could power an automated alerting system
  when a product or location drops below a threshold.
------------------------------------------------------------*/

SELECT
    'ALERT' AS SIGNAL,
    LOCATION_NAME,
    PRODUCT_NAME,
    COUNT(*) AS NEGATIVE_REVIEWS_7D,
    ROUND(AVG(SENTIMENT_SCORE), 3) AS AVG_SENTIMENT
FROM CLASSIFIED_REVIEWS
WHERE SENTIMENT_LABEL = 'Negative'
  AND REVIEW_DATE >= DATEADD('day', -7, CURRENT_DATE())
GROUP BY LOCATION_NAME, PRODUCT_NAME
HAVING NEGATIVE_REVIEWS_7D >= 3
ORDER BY NEGATIVE_REVIEWS_7D DESC;

SELECT 'Sentiment pipeline complete! Dynamic Table will auto-refresh as new reviews arrive.' AS STATUS;
