# Goal 1: Set Up Your Environment

**Workbook:** Snowflake Engineering  
**Dataset:** E-Commerce (loaded in Goal 2)  
**Estimated time:** 2–3 hours  
**Warehouse size:** X-Small throughout  
**COF-C03 domain:** Domain 1.0 — Snowflake AI Data Cloud Features & Architecture (31%)

---

## What you are doing and why

Before writing a single query or loading a single row of data, you need a clear mental model of what Snowflake is, how it is structured, and how to navigate it deliberately.

Most Snowflake problems practitioners hit day-to-day — unexpected costs, slow queries, objects that seem to disappear, permissions that do not work as expected — trace back to a gap in this foundation. Goal 1 closes those gaps before they become habits.

By the end of this goal you will have:

- A clear mental model of Snowflake's three-layer architecture
- Confident navigation of the object hierarchy (account → database → schema → table)
- The ability to choose the right table type, view type, and stage type for any situation
- A properly configured virtual warehouse
- An understanding of Snowflake editions and what features they gate
- Session and account parameters set correctly for your working environment

You will also have created the `ECOMMERCE` database and its three-schema structure (`RAW`, `STAGING`, `ANALYTICS`) that carries through the entire workbook series.

---

## Prerequisites

- **Assumed knowledge:** You know what a database is, what a table is, 
- and have written at least a basic SELECT statement. If not, complete 
- a free SQL fundamentals course first — 
- [Mode SQL Tutorial](https://mode.com/sql-tutorial/) or 
- [SQLZoo](https://sqlzoo.net/) are both excellent starting points.

- A Snowflake account (trial is fine — [sign up here](https://www.snowflake.com/try-snowflake/))
- Access to Snowsight (Snowflake's web UI)
- SYSADMIN or ACCOUNTADMIN role access
- No prior Snowflake experience required

---

## Sub-tasks

Work through these in order. Each file is self-contained and runnable step by step in Snowsight.

| # | Sub-task | File | Time | COF-C03 Domain | Key Concepts |
|---|---|---|---|---|---|
| 1.1 | Understand the Snowflake architecture | [01_architecture.sql](01_architecture.sql) | ~20 min | 1.0 (31%) | Three-layer model, storage/compute separation, cloud services layer, credit consumption |
| 1.2 | Navigate the object hierarchy | [02_object_hierarchy.sql](02_object_hierarchy.sql) | ~25 min | 1.0 (31%) | Account → database → schema → table, SHOW commands, INFORMATION_SCHEMA, ECOMMERCE database setup |
| 1.3 | Know your table types | [03_table_types.sql](03_table_types.sql) | ~25 min | 1.0 (31%) | Permanent, transient, temporary, external tables — when to use each and cost implications |
| 1.4 | Know your view types | [04_view_types.sql](04_view_types.sql) | ~20 min | 1.0 (31%) | Standard, secure, and materialized views — use cases and trade-offs |
| 1.5 | Know your stage types | [05_stage_types.sql](05_stage_types.sql) | ~20 min | 1.0 (31%) | User, table, named internal, named external stages — when to use each |
| 1.6 | Understand Snowflake editions | [06_editions.sql](06_editions.sql) | ~15 min | 1.0 (31%) | Standard vs Enterprise vs Business Critical — feature gates and cost implications |
| 1.7 | Configure virtual warehouses | [07_virtual_warehouses.sql](07_virtual_warehouses.sql) | ~30 min | 1.0 (31%) | Sizing, auto-suspend, auto-resume, multi-cluster, credit consumption |
| 1.8 | Understand session and account parameters | [08_session_parameters.sql](08_session_parameters.sql) | ~20 min | 1.0 (31%) | ALTER SESSION, ALTER ACCOUNT, SHOW PARAMETERS, timezone and date format traps |
| Exam prep | COF-C03 exam preparation | [09_exam_prep.sql](09_exam_prep.sql) | ~30 min | 1.0 (31%) | 12 practice questions with full explanations tied to sub-tasks |
---

## How to run these files

1. Open [Snowsight](https://app.snowflake.com)
2. Create a new worksheet: **Projects → Worksheets → +**
3. Name it `Goal 1 — Environment Setup`
4. Open the sub-task file from this folder
5. Copy the contents into your worksheet
6. Run each step individually using **Cmd + Enter** (not the full file at once)
7. Read the output before moving to the next step

> **Important:** Run one step at a time. Each step builds on the previous one and the comments explain what you should see. If something does not match, stop and investigate before continuing.

---

## Key objects created in this goal

By the end of Goal 1 you will have created the following objects in your Snowflake account. These persist and are used in every subsequent goal.

```
ECOMMERCE                        ← database
├── RAW                          ← schema: raw ingested data
├── STAGING                      ← schema: cleaned and typed data  
├── ANALYTICS                    ← schema: business-ready tables and views
└── INFORMATION_SCHEMA           ← built-in, read-only metadata views
```

---

## Oracle and SQL Server practitioners — read this first

If you are coming from Oracle or SQL Server, three things in this goal will feel unfamiliar:

**Storage and compute are completely separate.** There is no single database server that owns both. Your data lives in cloud object storage (S3, Azure Blob, or GCS). Your queries run on virtual warehouses that you spin up and down independently. You pay for compute only when it is running.

**There are no tablespaces, extents, or data files to manage.** Snowflake handles all physical storage organisation internally through micro-partitioning. You never run REORG, VACUUM, or ANALYZE.

**AUTOCOMMIT is ON by default.** This is covered in detail in Goal 3 (Sub-task 3.3). For now, just know it — a DELETE without an explicit BEGIN runs and commits immediately. There is no implicit transaction wrapping your statements.

---

## COF-C03 exam coverage

Sub-tasks in this goal map to the following COF-C03 exam objectives:

- Snowflake architecture (three-layer model, virtual warehouses, cloud services)
- Snowflake object model (databases, schemas, tables, views, stages)
- Table types and their use cases
- View types and their use cases
- Snowflake editions and feature availability
- Virtual warehouse configuration and credit consumption
- Session and account parameter management

Domain 1.0 represents **31% of the COF-C03 exam** — the single largest domain. This goal covers it comprehensively.

---

## When you are done

After completing all 9 sub-tasks including the exam preparation:

1. Commit your progress:
```bash
git add 01-snowflake/goal-01-environment-setup/
git commit -m "feat: complete goal-01 environment setup"
git push
```

2. Move to [Goal 2: Get Data In](../goal-02-get-data-in/)

---

*Snowflake Engineering Workbook · [github.com/marcbacchus/snowflake-workbook](https://github.com/marcbacchus/snowflake-workbook)*
