/*============================================================
  02_cortex_search.sql — Cortex Search Demo
  
  Demonstrates building a Cortex Search service over product
  catalog, reviews, and hair profiles to power an
  AI agent with real-time product knowledge.
  
  Prerequisites: Run 00_setup.sql and load sample data first.
============================================================*/

USE DATABASE CORTEX_AI_DEMO;
USE SCHEMA SEARCH;
USE WAREHOUSE CORTEX_AI_DEMO_WH;

/*------------------------------------------------------------
  Step 1: Explore the product catalog
------------------------------------------------------------*/

SELECT 
    PRODUCT_ID,
    PRODUCT_NAME,
    CATEGORY,
    SHADE_NAME,
    COVERAGE_LEVEL,
    PRICE,
    AVAILABLE_CHANNELS
FROM PRODUCT_CATALOG
ORDER BY PRODUCT_NAME
LIMIT 20;

/*------------------------------------------------------------
  Step 2: Build a unified search corpus
  
  Combine product descriptions, reviews, and hair profiles
  into a single searchable document per product.
------------------------------------------------------------*/

CREATE OR REPLACE VIEW SEARCH_CORPUS AS
SELECT
    pc.PRODUCT_ID,
    pc.PRODUCT_NAME,
    pc.CATEGORY,
    pc.SHADE_NAME,
    pc.SHADE_NUMBER,
    pc.COVERAGE_LEVEL,
    pc.PRICE,
    pc.AVAILABLE_CHANNELS,
    pc.DESCRIPTION || '\n\nIngredients: ' || pc.INGREDIENTS AS PRODUCT_DETAILS,
    
    -- Aggregate review text for this product
    agg.REVIEW_COUNT,
    agg.AVG_RATING,
    agg.SAMPLE_REVIEWS
FROM PRODUCT_CATALOG pc
LEFT JOIN (
    SELECT
        PRODUCT_ID,
        COUNT(*) AS REVIEW_COUNT,
        ROUND(AVG(RATING), 1) AS AVG_RATING,
        LISTAGG(
            'Rating: ' || RATING || '/5 - ' || REVIEW_TEXT, 
            '\n---\n'
        ) WITHIN GROUP (ORDER BY REVIEW_DATE DESC) AS SAMPLE_REVIEWS
    FROM PRODUCT_REVIEWS
    WHERE VERIFIED_PURCHASE = TRUE
    GROUP BY PRODUCT_ID
) agg ON pc.PRODUCT_ID = agg.PRODUCT_ID;

SELECT * FROM SEARCH_CORPUS LIMIT 5;

/*------------------------------------------------------------
  Step 3: Create a Cortex Search service
  
  This is the core of the demo — creating a hybrid search
  service that an AI agent can query via REST API.
------------------------------------------------------------*/

CREATE OR REPLACE CORTEX SEARCH SERVICE PRODUCT_SEARCH
  ON PRODUCT_DETAILS
  ATTRIBUTES PRODUCT_NAME, SHADE_NAME, CATEGORY, COVERAGE_LEVEL, PRICE, AVG_RATING
  WAREHOUSE = CORTEX_AI_DEMO_WH
  TARGET_LAG = '1 hour'
  AS (
    SELECT
        PRODUCT_ID,
        PRODUCT_NAME,
        CATEGORY,
        SHADE_NAME,
        SHADE_NUMBER,
        COVERAGE_LEVEL,
        PRICE,
        AVAILABLE_CHANNELS,
        PRODUCT_DETAILS,
        REVIEW_COUNT,
        AVG_RATING,
        SAMPLE_REVIEWS
    FROM SEARCH_CORPUS
  );

/*------------------------------------------------------------
  Step 4: Test search queries — these mimic what an AI agent would ask
------------------------------------------------------------*/

-- Query 1: Customer asks about gray coverage
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'CORTEX_AI_DEMO.SEARCH.PRODUCT_SEARCH',
        '{
            "query": "What products are best for covering gray hair?",
            "columns": ["PRODUCT_NAME", "SHADE_NAME", "COVERAGE_LEVEL", "AVG_RATING", "PRICE"],
            "limit": 5
        }'
    )
);

-- Query 2: Customer asks about a specific shade
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'CORTEX_AI_DEMO.SEARCH.PRODUCT_SEARCH',
        '{
            "query": "Tell me about the Golden Brown shade for brown hair",
            "columns": ["PRODUCT_NAME", "SHADE_NAME", "PRODUCT_DETAILS", "AVG_RATING"],
            "limit": 3
        }'
    )
);

-- Query 3: Customer wants ingredient information
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'CORTEX_AI_DEMO.SEARCH.PRODUCT_SEARCH',
        '{
            "query": "Which hair colors are ammonia-free and safe for sensitive scalp?",
            "columns": ["PRODUCT_NAME", "PRODUCT_DETAILS", "PRICE"],
            "limit": 5
        }'
    )
);

/*------------------------------------------------------------
  Step 5: Cortex Search for hair profile matching
  
  Create a separate search service over hair profiles
  to help the agent recommend the right shade.
------------------------------------------------------------*/

CREATE OR REPLACE VIEW PROFILE_SEARCH_CORPUS AS
SELECT
    PROFILE_ID,
    NATURAL_COLOR,
    DESIRED_RESULT,
    GRAY_COVERAGE_NEEDED,
    GRAY_PERCENTAGE,
    HAIR_TEXTURE,
    HAIR_CONDITION,
    RECOMMENDED_SHADE,
    'Natural color: ' || NATURAL_COLOR || 
    '. Desired result: ' || DESIRED_RESULT ||
    '. Gray coverage: ' || IFF(GRAY_COVERAGE_NEEDED, GRAY_PERCENTAGE || ' gray', 'Not needed') ||
    '. Hair texture: ' || HAIR_TEXTURE ||
    '. Condition: ' || HAIR_CONDITION ||
    '. Recommended shade: ' || RECOMMENDED_SHADE AS PROFILE_DESCRIPTION
FROM HAIR_PROFILES;

CREATE OR REPLACE CORTEX SEARCH SERVICE PROFILE_SEARCH
  ON PROFILE_DESCRIPTION
  ATTRIBUTES NATURAL_COLOR, DESIRED_RESULT, GRAY_PERCENTAGE, RECOMMENDED_SHADE
  WAREHOUSE = CORTEX_AI_DEMO_WH
  TARGET_LAG = '1 hour'
  AS (
    SELECT * FROM PROFILE_SEARCH_CORPUS
  );

-- Test: Find similar profiles for shade recommendation
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'CORTEX_AI_DEMO.SEARCH.PROFILE_SEARCH',
        '{
            "query": "medium brown hair with 30% gray wanting natural coverage",
            "columns": ["NATURAL_COLOR", "DESIRED_RESULT", "GRAY_PERCENTAGE", "RECOMMENDED_SHADE"],
            "limit": 5
        }'
    )
);

/*------------------------------------------------------------
  Step 6: REST API integration pattern
  
  This shows how an AI agent would call Cortex Search via REST API.
------------------------------------------------------------*/

-- The REST API endpoint for PRODUCT_SEARCH would be:
-- POST https://<account>.snowflakecomputing.com/api/v2/cortex/search/CORTEX_AI_DEMO/SEARCH/PRODUCT_SEARCH
-- 
-- Request body:
-- {
--   "query": "What products are best for gray coverage?",
--   "columns": ["PRODUCT_NAME", "SHADE_NAME", "COVERAGE_LEVEL", "PRICE"],
--   "limit": 5
-- }
--
-- The AI agent calls this endpoint with the customer's natural language question.
-- Cortex Search returns semantically relevant products with metadata.
-- The agent uses these results to generate a grounded response.

SELECT 'Cortex Search services created! Test queries above to see results.' AS STATUS;
