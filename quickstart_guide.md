# Cortex AI for Customer Intelligence — Quickstart Guide

## Overview

This hands-on quickstart walks through Snowflake Cortex AI capabilities using sample hair color product data:

1. **Cortex Search** — Build a hybrid semantic + keyword search service for product discovery
2. **Sentiment at Scale** — Create an automated review classification pipeline with Dynamic Tables

**Estimated Time:** 30-45 minutes

---

## Prerequisites

- Snowflake account with `SYSADMIN` role (or equivalent)
- Cortex AI enabled on your account
- Cortex Code (optional, recommended for Exercise 1)
- Warehouse: `MEDIUM` or larger

---

## Setup

### Step 1: Create the Demo Environment

Open a SQL worksheet and run the setup script:

```sql
-- Run: scripts/00_setup.sql
-- This creates:
--   Database: CORTEX_AI_DEMO
--   Schemas: SEARCH, SENTIMENT
--   Warehouse: CORTEX_AI_DEMO_WH (Medium, auto-suspend 60s)
```

### Step 2: Load Sample Data

```sql
-- Run: scripts/load_sample_data.sql
-- This loads:
--   8 products with descriptions and ingredients
--   10 product reviews with ratings
--   10 hair profiles
--   20 multi-channel reviews (Salon, DTC, Ulta, Amazon, Sally Beauty, Target, Walmart)
```

### Step 3: Verify Row Counts

```sql
SELECT 'SEARCH.PRODUCT_CATALOG' AS TABLE_NAME, COUNT(*) AS ROWS FROM CORTEX_AI_DEMO.SEARCH.PRODUCT_CATALOG
UNION ALL
SELECT 'SEARCH.PRODUCT_REVIEWS', COUNT(*) FROM CORTEX_AI_DEMO.SEARCH.PRODUCT_REVIEWS
UNION ALL
SELECT 'SEARCH.HAIR_PROFILES', COUNT(*) FROM CORTEX_AI_DEMO.SEARCH.HAIR_PROFILES
UNION ALL
SELECT 'SENTIMENT.RAW_REVIEWS', COUNT(*) FROM CORTEX_AI_DEMO.SENTIMENT.RAW_REVIEWS;
```

Expected: 8, 10, 10, 20 rows respectively.

---

## Enable Cortex Code

1. Open Snowsight
2. Navigate to **Projects > Worksheets**
3. Click the **Cortex Code** icon in the left sidebar (or press `Cmd+Shift+P` and search "Cortex Code")
4. Cortex Code enables AI-assisted SQL development, debugging, and exploration

---

## Understand the Demo Data

### Search Schema
- `PRODUCT_CATALOG` — Hair color products with descriptions, ingredients, pricing, availability
- `PRODUCT_REVIEWS` — Customer reviews with ratings, verified purchase flags
- `HAIR_PROFILES` — Hair profiles with color preferences and shade recommendations

### Sentiment Schema
- `RAW_REVIEWS` — Multi-channel reviews from Salon locations, DTC, retail partners

### Quick Explore

```sql
-- Browse the product catalog
SELECT PRODUCT_NAME, SHADE_NAME, COVERAGE_LEVEL, PRICE, AVAILABLE_CHANNELS
FROM CORTEX_AI_DEMO.SEARCH.PRODUCT_CATALOG;

-- See reviews by channel
SELECT SOURCE_CHANNEL, COUNT(*) AS REVIEWS, ROUND(AVG(RATING), 1) AS AVG_RATING
FROM CORTEX_AI_DEMO.SENTIMENT.RAW_REVIEWS
GROUP BY SOURCE_CHANNEL ORDER BY REVIEWS DESC;
```

---

## Exercise 1: Fix Broken SQL (~5 minutes)

Open `scripts/broken_sentiment_query.sql` in Cortex Code. This query has **4 intentional bugs**. Ask Cortex Code to find and fix them:

**Prompt:** "Fix the bugs in this SQL query"

The query should classify reviews by sentiment and aggregate by Salon location to produce an NPS proxy score. See if Cortex Code can identify all 4 issues.

<details>
<summary>Hints (click to expand)</summary>

1. Look for a typo in `USE SCHEMA`
2. Check column name references carefully
3. The `DATEADD` function is missing something
4. String literals need quotes
5. Check the `ORDER BY` clause spelling

</details>

---

## Exercise 2: Build a Product Search Service (~15-20 minutes)

This exercise demonstrates Cortex Search — a hybrid semantic + keyword search service that could power an AI agent's product knowledge.

### Step 1: Run the Cortex Search script

```sql
-- Run: scripts/02_cortex_search.sql
-- Follow the step-by-step SQL comments
```

### Step 2: Try your own search queries

After creating the `PRODUCT_SEARCH` service, try these searches:

```sql
-- "What's good for sensitive scalp?"
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'CORTEX_AI_DEMO.SEARCH.PRODUCT_SEARCH',
        '{"query": "gentle color for sensitive scalp", "columns": ["PRODUCT_NAME", "PRODUCT_DETAILS", "PRICE"], "limit": 3}'
    )
);

-- "Which products last the longest?"
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'CORTEX_AI_DEMO.SEARCH.PRODUCT_SEARCH',
        '{"query": "long lasting fade resistant color", "columns": ["PRODUCT_NAME", "SHADE_NAME", "PRODUCT_DETAILS"], "limit": 3}'
    )
);
```

### Step 3: Ask Cortex Code to help

**Prompt:** "Write a query that searches for products suitable for curly hair with gray coverage, and include customer review ratings"

---

## Exercise 3: Sentiment Pipeline with Dynamic Tables (~10 minutes)

This exercise demonstrates scaling Cortex sentiment analysis into an automated pipeline.

### Step 1: Run the Sentiment at Scale script

```sql
-- Run: scripts/03_sentiment_at_scale.sql
-- This creates a Dynamic Table that auto-classifies reviews
```

### Step 2: Explore the results

```sql
-- Which Salon locations have the best sentiment?
SELECT LOCATION_NAME, COUNT(*) AS REVIEWS, ROUND(AVG(SENTIMENT_SCORE), 3) AS AVG_SENTIMENT
FROM CORTEX_AI_DEMO.SENTIMENT.CLASSIFIED_REVIEWS
WHERE LOCATION_NAME IS NOT NULL
GROUP BY LOCATION_NAME
ORDER BY AVG_SENTIMENT DESC;

-- Which channels have the most negative reviews?
SELECT SOURCE_CHANNEL, 
    SUM(CASE WHEN SENTIMENT_LABEL = 'Negative' THEN 1 ELSE 0 END) AS NEGATIVE,
    COUNT(*) AS TOTAL,
    ROUND(SUM(CASE WHEN SENTIMENT_LABEL = 'Negative' THEN 1 ELSE 0 END)::FLOAT / COUNT(*) * 100, 1) AS NEG_PCT
FROM CORTEX_AI_DEMO.SENTIMENT.CLASSIFIED_REVIEWS
GROUP BY SOURCE_CHANNEL
ORDER BY NEG_PCT DESC;
```

### Step 3: Ask Cortex Code for deeper analysis

**Prompt:** "Analyze the negative reviews and categorize them by issue type — is it product quality, service, shipping, or pricing?"

---

## Bonus Exercises

### For Data Engineers
- "Build a data quality check that flags reviews with missing product names or channels"
- "Write a Snowpark Python UDF that calculates review text complexity scores"

### For Data Analysts
- "Compare DTC subscription customers vs. retail-only customers — who leaves better reviews?"
- "Build a weekly executive summary view that combines sentiment trends with channel performance"

### For Data Scientists
- "Using Cortex COMPLETE, classify each review into a persona based on their language and concerns"
- "Create a churn risk score using order frequency and sentiment signals"

---

## Tips and Troubleshooting

| Issue | Solution |
|-------|----------|
| "Cortex functions not available" | Ensure Cortex AI is enabled on your account. Check with your admin. |
| "Dynamic Table not refreshing" | Verify the warehouse is running: `ALTER WAREHOUSE CORTEX_AI_DEMO_WH RESUME` |
| "Cortex Search service not found" | Search services take 1-2 minutes to initialize after creation. Wait and retry. |
| "Insufficient privileges" | You need `SYSADMIN` or a role with `CREATE DATABASE` privileges |
| "Query timeout" | For Cortex COMPLETE on large datasets, use a `LARGE` warehouse or process in batches |

---

## Cleanup

When done, run the cleanup script to remove all demo objects:

```sql
-- Run: scripts/04_cleanup.sql
-- This drops the CORTEX_AI_DEMO database and warehouse
```

---

## Learn More

- [Cortex AI Documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex)
- [Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search)
- [Dynamic Tables](https://docs.snowflake.com/en/user-guide/dynamic-tables)
