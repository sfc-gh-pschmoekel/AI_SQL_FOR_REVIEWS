# Cortex AI for Customer Intelligence — Demo

Hands-on demo showcasing Snowflake Cortex AI capabilities for customer intelligence use cases in the retail industry.

## Use Cases

1. **Cortex Search for AI Agents** — Build hybrid semantic + keyword search services to power AI agent product knowledge
2. **Sentiment at Scale** — Automated review classification pipeline using Cortex AI functions and Dynamic Tables

## Getting Started

See [quickstart_guide.md](quickstart_guide.md) for a step-by-step walkthrough with exercises.

### Quick Setup

```sql
-- 1. Create demo environment
-- Run: scripts/00_setup.sql

-- 2. Load sample data
-- Run: scripts/load_sample_data.sql

-- 3. Pick a use case and follow along
-- scripts/02_cortex_search.sql
-- scripts/03_sentiment_at_scale.sql
```

## Repository Structure

```
scripts/
  00_setup.sql                  — Database, schema, warehouse setup
  load_sample_data.sql          — Sample product and review data
  02_cortex_search.sql          — Cortex Search service for product discovery
  03_sentiment_at_scale.sql     — Sentiment pipeline with Dynamic Tables
  customer_sentiment_demo.sql   — Full sentiment demo with AI functions
  04_cleanup.sql                — Remove all demo objects
  broken_sentiment_query.sql    — Exercise: fix 4 bugs with Cortex Code
quickstart_guide.md             — Self-paced guide with exercises
```

## Prerequisites

- Snowflake account with Cortex AI enabled
- `SYSADMIN` role (or equivalent for creating databases)
- Recommended: Medium warehouse or larger

## Cleanup

```sql
-- Run: scripts/04_cleanup.sql
```

## Learn More

- [Snowflake Cortex AI](https://docs.snowflake.com/en/user-guide/snowflake-cortex)
- [Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search)
- [Dynamic Tables](https://docs.snowflake.com/en/user-guide/dynamic-tables)
