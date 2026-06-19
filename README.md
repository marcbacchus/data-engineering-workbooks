# Snowflake Engineering Workbook

A hands-on, goal-driven workbook for learning Snowflake from environment setup through production-grade automation. Part of a five-workbook series covering the modern data and cloud engineering stack.

**Workbook 1 of 5** — Snowflake · dbt · Terraform · Azure · Databricks

---

## Who this is for

This workbook is written for practitioners — people who learn by doing, not by reading feature lists. Whether you are new to Snowflake or coming from another data platform (Oracle, SQL Server, Redshift, BigQuery), the goal is the same: leave with working knowledge you can apply on Monday morning.

Each goal is structured around a real outcome, not a feature. You will not find a chapter called "Virtual Warehouses." You will find a goal called "Optimize Performance" that uses virtual warehouses as a tool to get there.

**Beginner to advanced.** Goals 1–3 assume only basic SQL familiarity. Goals 4–9 progressively assume the skills built in earlier goals. You can work through sequentially or jump to the goal most relevant to your current project.

---

## What you will build

By the end of this workbook you will have:

- A fully configured Snowflake environment with proper role hierarchy and security controls
- A working data pipeline from raw CSV files through to transformed, queryable tables
- Automated incremental loads using Streams and Tasks
- Performance-tuned queries with clustering and warehouse sizing dialed in
- A monitoring setup using ACCOUNT_USAGE and resource monitors
- Hands-on experience with Snowflake Cortex AI functions on real text data
- The practical knowledge to sit the SnowPro Core (COF-C03) certification with confidence

---

## Dataset

All exercises use a single consistent dataset throughout — a synthetic e-commerce platform covering customers, orders, products, suppliers, reviews, returns, and clickstream events.

| Table | Rows | Used for |
|---|---|---|
| customers | 100,000 | Joins, segmentation, cohort analysis |
| products | 10,000 | Catalog queries, category aggregations |
| suppliers | 1,000 | Multi-table joins |
| orders | 2,000,000 | Time-series, revenue analysis, pipelines |
| order_items | 4,659,254 | Performance exercises, large table operations |
| product_reviews | 500,000 | Cortex AI — sentiment, summarization |
| returns | 80,000 | Return rate analysis, DML exercises |
| clickstream_events | 3,000,000 | Streaming, event pipelines (later workbooks) |

Data spans 2019–2023 with realistic seasonality (Q4 peak), year-over-year growth, and deliberate nulls where real-world data would have them. See [`dataset/SCHEMA.md`](dataset/SCHEMA.md) for full column definitions, data distributions, and sample queries.

---

## Workbook structure

### Goals

| # | Goal | Key topics |
|---|---|---|
| 1 | [Set up your environment](goal-01-environment-setup/) | Architecture, object hierarchy, table types, warehouses, parameters |
| 2 | [Get data in](goal-02-get-data-in/) | COPY INTO, file formats, Snowpipe, semi-structured data, unloading, external tables, schema evolution |
| 3 | [Query and transform data](goal-03-query-transform/) | SQL, window functions, transactions, DML, Cortex AI, UDFs, Snowpark intro |
| 4 | [Secure your environment](goal-04-security/) | RBAC, masking policies, row access policies, network policies, tags |
| 5 | [Optimize performance](goal-05-performance/) | Query Profile, caching, clustering, warehouse sizing, Search Optimization |
| 6 | [Automate workflows](goal-06-automation/) | Tasks, Streams, CDC pipelines, stored procedures, Dynamic Tables |
| 7 | [Share and collaborate](goal-07-sharing/) | Secure data sharing, Marketplace, Data Clean Rooms |
| 8 | [Recover from mistakes](goal-08-recovery/) | Time Travel, Fail-Safe, zero-copy cloning, replication |
| 9 | [Monitor and manage costs](goal-09-monitoring/) | INFORMATION_SCHEMA, ACCOUNT_USAGE, SHOW commands, resource monitors |

### Sub-task structure

Each goal contains one SQL file per sub-task. Every file follows the same format:

```
-- ──────────────────────────────────────────────────────────
-- GOAL 3 · SUB-TASK 3.3: Manage transactions and concurrency
-- ──────────────────────────────────────────────────────────
-- WHAT YOU ARE DOING AND WHY
--   ...
--
-- CONCEPT
--   ...
-- ──────────────────────────────────────────────────────────

-- Step 1: ...
-- Step 2: ...

-- ── PRACTICE GAP ─────────────────────────────────────────
-- Your turn: ...

-- ── WHAT IF ──────────────────────────────────────────────
-- What if ...?
```

---

## Prerequisites

**Snowflake account**
A free 30-day trial account is sufficient for Goals 1–8. Goal 9 (monitoring and costs) benefits from having some query history to work with, which the earlier goals will generate naturally.

Sign up at [snowflake.com/try](https://www.snowflake.com/try-snowflake/) — no credit card required for trial.

**Snowflake edition**
Standard edition is sufficient for most goals. A few sub-tasks note where Enterprise features are required (materialized views, Fail-Safe, multi-cluster warehouses, extended Time Travel retention). These are clearly flagged.

**SQL client**
Snowsight (Snowflake's built-in web UI) works for everything in this workbook. If you prefer a dedicated client, VS Code with the Snowflake extension or DBeaver both work well.

**Python (optional)**
Only needed if you want to regenerate the dataset from scratch using the script in [`utils/`](utils/). Not required to complete any workbook exercises.

---

## Getting started

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/snowflake-workbook.git
cd snowflake-workbook
```

> **Note:** The three largest CSV files (`orders.csv`, `order_items.csv`, `clickstream_events.csv`) are stored with Git LFS. If you do not have Git LFS installed:
> ```bash
> git lfs install
> git lfs pull
> ```
> Or install Git LFS from [git-lfs.com](https://git-lfs.github.com/) before cloning.

### 2. Load the dataset

Goal 2 walks you through loading the dataset step by step — that is intentional. Loading data is the first real skill this workbook teaches. If you want to skip ahead to a later goal, run the setup script first:

```sql
-- Run this in Snowsight to create the database and load all tables
-- File: goal-02-get-data-in/00_quickload_for_later_goals.sql
```

### 3. Start at Goal 1

Open [`goal-01-environment-setup/`](goal-01-environment-setup/) and work through the sub-tasks in order. Each file is self-contained and runnable.

---

## SnowPro Core alignment

This workbook covers all six COF-C03 exam domains:

| Domain | Weight | Goals |
|---|---|---|
| Snowflake AI Data Cloud Features & Architecture | 25% | 1, 9 |
| Account Access and Security | 17% | 4, 9 |
| Performance Concepts | 15% | 5 |
| Data Loading and Unloading | 15% | 2 |
| Data Transformations | 17% | 3, 6 |
| Data Protection and Data Sharing | 11% | 7, 8 |

Sub-tasks that map directly to exam objectives are marked with `-- [COF-C03]` in the SQL file header.

---

## Workbook series

This is the first in a series of five workbooks using the same dataset and building on the same foundation:

| # | Workbook | Status |
|---|---|---|
| 1 | **Snowflake** (this workbook) | In progress |
| 2 | dbt | Planned |
| 3 | Terraform | Planned |
| 4 | Azure Data Engineering | Planned |
| 5 | Databricks | Planned |

Each workbook is self-contained but references the others where the platforms intersect — for example, the Terraform workbook provisions the Snowflake infrastructure built manually in this workbook, and the Databricks workbook uses the same `clickstream_events` table for streaming exercises.

---

## Contributing

Found an error? Have a better way to explain a concept? Pull requests are welcome.

Please open an issue before making large changes so we can discuss the approach. For typos, broken SQL, or missing explanations — just open a PR directly.

---

## License

MIT. Use this freely for learning, teaching, or building your own materials. Attribution appreciated but not required.

---

*Built for the data engineering community. No vendor sponsorship. No affiliate links. Just clean, honest technical content.*
