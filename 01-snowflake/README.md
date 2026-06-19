# Workbook 01: Snowflake Engineering

**Series:** [Data Engineering Workbooks](../README.md)  
**Dataset:** [E-Commerce dataset](../dataset/SCHEMA.md)  
**Estimated time:** 15–20 hours total  
**Certification alignment:** SnowPro Core COF-C03  

---

## What you will build

By the end of this workbook you will have:

- A fully configured Snowflake environment with proper role hierarchy and security controls
- A working data pipeline from raw CSV files through to transformed, queryable tables
- Automated incremental loads using Streams, Tasks, and Dynamic Tables
- Performance-tuned queries with clustering and warehouse sizing dialled in
- A monitoring setup using ACCOUNT_USAGE and resource monitors
- Hands-on experience with Snowflake Cortex AI functions on real text data
- The practical knowledge to sit the SnowPro Core COF-C03 certification with confidence

---

## Prerequisites

- A Snowflake account — [free 30-day trial here](https://www.snowflake.com/try-snowflake/), no credit card required
- Access to Snowsight (Snowflake's web UI)
- SYSADMIN or ACCOUNTADMIN role on your account
- Basic SQL familiarity (SELECT, FROM, WHERE, GROUP BY)
- Git installed and configured — see [Workbook 00: Git for Data Engineers](../00-git/) if needed

**Snowflake edition:** Standard is sufficient for most goals. Enterprise features are clearly flagged where required (materialized views, extended Time Travel, multi-cluster warehouses). This workbook was validated on Enterprise edition.

---

## Goals

| # | Goal | Key topics | Time |
|---|---|---|---|
| [01](goal-01-environment-setup/) | Set up your environment | Architecture, object hierarchy, table types, view types, stage types, editions, warehouses, parameters | ~2–3 hrs |
| [02](goal-02-get-data-in/) | Get data in | COPY INTO, file formats, Snowpipe, semi-structured data, unloading, external tables, schema evolution, error handling | ~3–4 hrs |
| [03](goal-03-query-transform/) | Query and transform data | SQL, window functions, transactions, DML, Cortex AI, UDFs, Snowpark intro | ~3–4 hrs |
| [04](goal-04-security/) | Secure your environment | RBAC, masking policies, row access policies, network policies, tags | ~2 hrs |
| [05](goal-05-performance/) | Optimize performance | Query Profile, caching, clustering, warehouse sizing, Search Optimization | ~2 hrs |
| [06](goal-06-automation/) | Automate workflows | Tasks, Streams, CDC pipelines, stored procedures, Dynamic Tables | ~2–3 hrs |
| [07](goal-07-sharing/) | Share and collaborate | Secure data sharing, Marketplace, Data Clean Rooms | ~1 hr |
| [08](goal-08-recovery/) | Recover from mistakes | Time Travel, Fail-Safe, zero-copy cloning, replication | ~1–2 hrs |
| [09](goal-09-monitoring/) | Monitor and manage costs | INFORMATION_SCHEMA, ACCOUNT_USAGE, SHOW commands, resource monitors | ~1–2 hrs |

---

## Dataset

This workbook uses the shared e-commerce dataset located in [`../dataset/`](../dataset/).

Load instructions are in [Goal 02 — Get Data In](goal-02-get-data-in/). If you want to skip ahead to a later goal, run the quickload script first:

```sql
-- goal-02-get-data-in/00_quickload.sql
```

---

## How to use this workbook

### 1. Open Snowsight

Log into your Snowflake account at [app.snowflake.com](https://app.snowflake.com).

### 2. Create a worksheet per goal

**Projects → Worksheets → +** — name it `Goal 01 — Environment Setup`. Create a new worksheet for each goal to keep your query history clean and organised.

### 3. Run step by step

Copy a sub-task file into your worksheet. Run each step individually using **Cmd + Enter** — not the full file at once. Read the output before moving to the next step.

### 4. Do the practice gaps

Every sub-task ends with a Practice Gap — exercises where you extend or adapt the code yourself. These are not optional. They are where the learning actually happens.

### 5. Commit your progress after each goal

```bash
git add 01-snowflake/goal-01-environment-setup/
git commit -m "feat: complete goal-01 environment setup"
git push
```

---

## COF-C03 exam coverage

| Domain | Weight | Goals |
|---|---|---|
| Snowflake AI Data Cloud Features & Architecture | 25% | 01, 09 |
| Account Access and Security | 17% | 04, 09 |
| Performance Concepts | 15% | 05 |
| Data Loading and Unloading | 15% | 02 |
| Data Transformations | 17% | 03, 06 |
| Data Protection and Data Sharing | 11% | 07, 08 |

Sub-tasks that map directly to exam objectives are marked with `-- [COF-C03]` in the file header.

---

## Oracle and SQL Server practitioners

Three things that will feel unfamiliar:

**Storage and compute are completely separate.** No single database server owns both. You pay for compute only when it is running.

**No tablespaces, extents, or data files to manage.** Snowflake handles all physical storage organisation internally. No REORG, VACUUM, or ANALYZE.

**AUTOCOMMIT is ON by default.** A DELETE without an explicit BEGIN runs and commits immediately. Covered in depth in Goal 03, Sub-task 3.3.

---

## What comes next

After completing this workbook:

- **[Workbook 02 — dbt](../02-dbt/)** transforms the data you loaded into Snowflake into business-ready models
- **[Workbook 03 — Terraform](../03-terraform/)** provisions the Snowflake infrastructure you built manually here, as code
- **[Workbook 04 — Azure](../04-azure/)** builds cloud pipelines that feed data into your Snowflake environment

---

*Data Engineering Workbooks · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
