# Workbook 01: Snowflake Engineering

**Series:** [Data Engineering Workbooks](../README.md)  
**Dataset:** [E-Commerce dataset](../dataset/SCHEMA.md)  
**Estimated time:** 37–49 hours total (Goals 1–78 actual; Goal 9 estimated, will be refined when completed)
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
| [02](goal-02-get-data-in/) | Get data in | COPY INTO, file formats, Snowpipe, semi-structured data, unloading, external tables, schema evolution, error handling | ~4–5 hrs |
| [03](goal-03-query-transform/) | Query and transform data | SQL, window functions, transactions, DML, Cortex AI, UDFs, Snowpark intro | ~4–5 hrs |
| [04](goal-04-security/) | Secure your environment | RBAC, masking policies, row access policies, network policies, tags | ~5–6 hrs |
| [05](goal-05-performance/) | Optimize performance | Query Profile, caching, clustering, warehouse sizing, Search Optimization | ~6–7 hrs |
| [06](goal-06-automation/) | Automate workflows | Tasks, Streams, CDC pipelines, stored procedures, Dynamic Tables | ~7–8 hrs |
| [07](goal-07-sharing/) | Share and collaborate | Secure data sharing, Marketplace, Data Clean Rooms | ~2–3 hrs |
| [08](goal-08-recovery/) | Recover from mistakes | Time Travel, Fail-Safe, zero-copy cloning, replication | ~3–4 hrs |
| [09](goal-09-monitoring/) | Monitor and manage costs | INFORMATION_SCHEMA, ACCOUNT_USAGE, SHOW commands, resource monitors | ~1–2 hrs |

---

## Exam preparation

Each goal includes a dedicated exam preparation file as the final sub-task. These files contain 10-15 COF-C03 aligned practice questions with full explanations, wrong answer breakdowns, and direct references back to the sub-task where each concept was covered.

| Goal | Exam prep file | Questions |
|---|---|---|
| Goal 1 | [09_exam_prep.sql](goal-01-environment-setup/09_exam_prep.sql) | 12 |
| Goal 2 | [10_exam_prep.sql](goal-02-get-data-in/10_exam_prep.sql) | 14 |
| Goal 3 | [9_exam_prep.sql](goal-03-query-transform/09_exam_prep.sql) | 14 |
| Goal 4 | [10_exam_prep.sql](goal-04-security/10_exam_prep.sql) | 15 |
| Goal 5 | [11_exam_prep.sql](goal-05-performance/11_exam_prep.sql) | 13 |
| Goal 6 | [09_exam_prep.sql](goal-06-automation/09_exam_prep.sql) | 15 |
| Goal 7 | [04_exam_prep.sql](goal-07-sharing/04_exam_prep.sql) | 13 |
| Goal 8 | [10_exam_prep.sql](goal-08-recovery/10_exam_prep.sql) | 18 |
| Goal 9 | Coming as goal is published | — |

Questions are original — written specifically for this workbook using the COF-C03 exam objectives as a guide. They are not reproduced from any third-party source.

**How to use:** Complete all sub-tasks in a goal before attempting the exam prep. Read each question and choose your answer before reading the explanation. If you get a question wrong, go back to the referenced sub-task before continuing.

---

## Dataset

This workbook uses the shared e-commerce dataset located in [`../dataset/`](../dataset/).

Load instructions are in [Goal 02 — Get Data In](goal-02-get-data-in/). Work through Goal 02 sequentially — each sub-task builds on the previous one and by the end you will have all 10,370,254 rows loaded and ready for Goal 03.

---

## How to use this workbook

### 1. Open Snowsight

Log into your Snowflake account at [app.snowflake.com](https://app.snowflake.com).

### 2. Organize your worksheets

**Projects → Workspaces → [+ Add New] → Folder** — name it `Snowflake Workbook`.

1. Click the `Snowflake Workbook` folder → **[+]** → **Folder** — name it `Goal 01 — Environment Setup`
2. Click the `Goal 01 — Environment Setup` folder → **[+]** → **SQL File** — name it `01_architecture.sql`
   - Alternatively, use **[+] → Upload Files** to upload the `.sql` file directly from your cloned repo
3. Repeat for each sub-task file in the goal, keeping the same filename as the repo (e.g. `02_object_hierarchy.sql`)
4. Repeat steps 1–3 for each goal

This keeps your worksheets organized exactly like the repo structure — one folder per goal, one file per sub-task.
### 3. Run step by step


Copy a sub-task file into your worksheet. Run each step individually using **Cmd + Enter** (Mac) or **Ctrl + Enter** (Windows) — not the full file at once. Read the output before moving to the next step.

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
| Snowflake AI Data Cloud Features & Architecture | 31% | 01, 08 |
| Account Management and Data Governance | 20% | 04, 09 |
| Data Loading, Unloading, and Connectivity | 18% | 02 |
| Performance Optimization, Querying, and Transformation | 21% | 03, 05, 06 |
| Data Collaboration | 10% | 07, 08 |

Sub-tasks that map directly to exam objectives are marked with the COF-C03 domain in the file header.

---

## Oracle and SQL Server practitioners

Three things that will feel unfamiliar:

**Storage and compute are completely separate.** No single database server owns both. You pay for compute only when it is running.

**No tablespaces, extents, or data files to manage.** Snowflake handles all physical storage organisation internally. No REORG, VACUUM, or ANALYZE.

**AUTOCOMMIT is ON by default.** A DELETE without an explicit BEGIN runs and commits immediately. Covered in depth in Goal 01, Sub-task 1.8.

---

## What comes next

After completing this workbook:

- **[Workbook 02 — dbt](../02-dbt/)** transforms the data you loaded into Snowflake into business-ready models
- **[Workbook 03 — Terraform](../03-terraform/)** provisions the Snowflake infrastructure you built manually here, as code
- **[Workbook 04 — Azure](../04-azure/)** builds cloud pipelines that feed data into your Snowflake environment

---

*Data Engineering Workbooks · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
