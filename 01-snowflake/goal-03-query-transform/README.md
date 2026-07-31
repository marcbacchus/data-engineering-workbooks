# Goal 3: Query and Transform Data

**Workbook:** Snowflake Engineering  
**Dataset:** E-Commerce (loaded in Goal 2)  
**Estimated time:** 4–5 hours total  
**Warehouse size:** X-Small throughout  
**COF-C03 domains:** Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)

---

## What you are doing and why

Goals 1 and 2 built the environment and loaded the data. Goal 3 is where you actually use it.

This goal covers the SQL patterns, transformation techniques, and developer tools practitioners use every day on large datasets — not toy examples, but real queries on 10 million rows where choices about filtering, joining, and structuring logic have measurable impact on performance and maintainability.

By the end of this goal you will have:

- Written production-grade SQL across all 10 e-commerce tables
- Used window functions to build running totals, rankings, and period-over-period comparisons
- Structured complex queries with CTEs that read like documentation
- Safely executed DML inside transactions with proper AUTOCOMMIT awareness
- Explored Cortex AI functions on 500,000 product reviews
- Built reusable SQL, JavaScript, and Python UDFs
- Written your first Snowpark Python pipeline in a Snowsight Notebook

---

## Prerequisites

- Goal 1 and Goal 2 complete
- All 10 tables loaded in `ECOMMERCE.RAW` (10,370,254 rows)
- `WORKBOOK_WH` warehouse configured
- SnowSQL installed and configured (`snowsql -c workbook` works)

---

## Sub-tasks

Work through these in order. Each file builds on the previous one.

| File | Sub-task | Time | Key concepts |
|---|---|---|---|
| [01_sql_fundamentals.sql](01_sql_fundamentals.sql) | SQL fundamentals and query patterns | ~30 min | WHERE, NULL handling, CASE/IFF, TRY_CAST, date functions, TABLESAMPLE, ILIKE |
| [02_joins_aggregations.sql](02_joins_aggregations.sql) | Joins and aggregations at scale | ~35 min | INNER/LEFT/FULL OUTER joins, GROUP BY rules, HAVING, correlated subqueries, fan-out |
| [03_window_functions.sql](03_window_functions.sql) | Window functions | ~35 min | ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG/LEAD, running totals, moving averages, QUALIFY |
| [04_ctes.sql](04_ctes.sql) | CTEs and query organisation | ~30 min | WITH clause, chained CTEs, recursive CTEs, CTE vs subquery vs view, data quality checks |
| [05_dml_transactions.sql](05_dml_transactions.sql) | DML and transactions | ~30 min | INSERT, UPDATE, DELETE, TRUNCATE, MERGE, AUTOCOMMIT trap, BEGIN/COMMIT/ROLLBACK |
| [06_cortex_ai.sql](06_cortex_ai.sql) | Cortex AI functions | ~35 min | AI_SENTIMENT, AI_CLASSIFY, AI_FILTER, AI_COMPLETE, AI_AGG, AI_TRANSLATE — paid account required |
| [07_udfs.sql](07_udfs.sql) | User-defined functions | ~30 min | SQL UDFs, JavaScript UDFs, UDTFs, overloading, secure UDFs, date series generator |
| [08_snowpark.sql](08_snowpark.sql) | Snowpark Python intro | ~35 min | Snowsight Notebooks, session setup, DataFrames, lazy evaluation, write back, Python UDFs |
| [09_exam_prep.sql](09_exam_prep.sql) | COF-C03 exam preparation | ~35 min | 14 practice questions covering all Goal 3 topics |

---

## Important notes before starting

### Sub-task 3.6 — Cortex AI
All Cortex AI functions (`AI_SENTIMENT`, `AI_CLASSIFY`, `AI_FILTER`, `AI_COMPLETE`, `AI_AGG`, `AI_TRANSLATE`) require a **paid Snowflake account**. They are not available on the standard $400 trial. Read through Sub-task 3.6 as a reference and return to it when you have a paid account.

### Sub-task 3.8 — Snowpark Notebook
Sub-task 3.8 runs in a **Snowsight Notebook**, not a SQL worksheet.

Create the notebook:
- Snowsight → Projects → Workspaces → open your `Snowflake Workbook` folder → `Goal 03 — Query and Transform` folder → **[+] → Notebook**
- Name it: `Goal 03 — Snowpark Intro`
- Select warehouse: `WORKBOOK_WH`

First cell in the notebook must be a SQL cell with:
```sql
USE ROLE ACCOUNTADMIN;
GRANT CREATE TABLE ON SCHEMA ECOMMERCE.RAW TO ROLE SYSADMIN; --Used in step 6
GRANT CREATE STAGE ON SCHEMA ECOMMERCE.RAW TO ROLE SYSADMIN; --Used in step 6
GRANT CREATE FUNCTION ON SCHEMA ECOMMERCE.RAW TO ROLE SYSADMIN; --Used in step 7
USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;
```

Always disconnect the kernel when done to avoid idle compute charges.

---

## Key concepts introduced in this goal

**QUALIFY** — Snowflake-specific keyword that filters on window function results without a subquery wrapper. No Oracle equivalent.

**AUTOCOMMIT = TRUE** — every DML statement commits immediately in Snowflake. A DELETE without BEGIN cannot be rolled back. Always use BEGIN/COMMIT for destructive DML.

**Correlated vs non-correlated subqueries** — a correlated subquery runs once per outer row. On 2 million orders this means 2 million executions. Replace with a CTE that aggregates once and joins.

**Window function fan-out** — PARTITION BY keeps all rows unlike GROUP BY which collapses them. One row in, one row out — with partition-level calculations attached.

**Snowpark lazy evaluation** — a Snowpark DataFrame is a query plan, not data. Nothing executes until an action (.show(), .collect(), .write) is called.

---

## COF-C03 exam coverage

| Domain | Weight | Sub-tasks |
|---|---|---|
| Data Transformations | 17% | 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8 |

The exam prep file (`09_exam_prep.sql`) contains 14 questions covering all tested concepts from this goal.

---

## When you are done

After completing all 9 sub-tasks including exam preparation:

1. Commit your progress:
```bash
git add 01-snowflake/goal-03-query-transform/
git commit -m "feat: complete goal-03 query and transform data"
git push
```

2. Move to [Goal 4: Secure Your Environment](../goal-04-secure-environment/)

---

*Data Engineering Workbooks · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
