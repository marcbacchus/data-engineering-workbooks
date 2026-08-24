# Goal 6: Automate Workflows

**Workbook:** Snowflake Engineering
**Dataset:** E-Commerce (loaded in Goal 2), `ECOMMERCE.RAW`
**Estimated time:** 7–8 hours total
**Warehouse size:** X-Small throughout
**COF-C03 domains:** Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)

---

## What you are doing and why

Goals 1–5 built, secured, and tuned the environment. Goal 6 is where it stops being something you operate by hand and starts running itself: scheduled work, change detection, incremental pipelines, branching logic, procedural code, declarative freshness, and proactive alerting — the full automation toolkit Snowflake gives you natively, with no external orchestrator required.

This goal produced more live trial-and-error than any before it. Several sub-tasks — particularly DAGs (6.4) and stored procedures (6.5) — hit real syntax restrictions, privilege gaps, and behavioral surprises that aren't obvious from documentation alone. Every one of those was debugged live, corrected in place, and documented as a discovery rather than smoothed over — the exam prep file leans heavily on exactly these moments.

By the end of this goal you will have:

- Scheduled recurring work with Tasks, including the `EXECUTE TASK` privilege gap that isn't obvious from the docs
- Built and consumed Streams, including the exact mechanics of how updates are represented and when a stream's offset actually advances
- Combined Streams and Tasks into a real idempotent incremental pipeline using `MERGE`, proven safe against mid-run failure
- Orchestrated a multi-task DAG with parallel branches, a join point, and genuine conditional branching — including the narrow, documented rules `WHEN` clauses actually follow
- Written Snowflake Scripting stored procedures with variables, loops, and exception handling, and used one to solve a problem a single SQL statement structurally cannot
- Built the declarative alternative to Streams+Tasks with Dynamic Tables, including a real staleness trap around `TARGET_LAG = DOWNSTREAM`
- Implemented a dead-letter pattern and proactive Alerting, including a working end-to-end email notification test
- Built the same incremental pipeline three different ways in a single Capstone — raw `MERGE`, a stored-procedure wrapper, and a Dynamic Table — wired into one DAG with failure alerting, and compared the tradeoffs directly

---

## Prerequisites

- Goals 1–5 complete
- All 10 tables loaded in `ECOMMERCE.RAW` (10,370,254 rows)
- `WORKBOOK_WH` warehouse configured
- **`ACCOUNTADMIN` access** — required to grant `EXECUTE TASK` (6.1) and `EXECUTE ALERT` (6.7) to `SYSADMIN`; neither privilege is implicit even for the owning role. Also required for the optional email notification integration in 6.7.
- A verified email address on your Snowflake user, if you want to run 6.7's optional real-email test end-to-end

---

## Sub-tasks

Work through these in order — later sub-tasks directly reuse objects from earlier ones (6.3's `ORDERS_MART` and `SYNC_ORDERS_MART_TASK` are rebuilt into the Capstone's DAG; 6.7's `ALERT_LOG` table is reused by the Capstone's failure alert).

| # | Sub-task | File | Time | COF-C03 Domain | Key Concepts |
|---|---|---|---|---|---|
| 6.1 | Schedule Work with Tasks | [01_schedule_tasks.sql](01_schedule_tasks.sql) | ~30–40 min | 4.0 (21%) | `CREATE TASK`, CRON/interval scheduling, serverless vs. warehouse-assigned, `EXECUTE TASK` privilege gap |
| 6.2 | Capture Change Data with Streams | [02_capture_change_data_streams.sql](02_capture_change_data_streams.sql) | ~35–45 min | 4.0 (21%) | `CREATE STREAM`, offset consumption mechanics, update-pair representation, STANDARD vs. APPEND_ONLY |
| 6.3 | Build Incremental Pipelines with Streams + Tasks | [03_incremental_pipelines_streams_tasks.sql](03_incremental_pipelines_streams_tasks.sql) | ~40–50 min | 4.0 (21%) | `WHEN SYSTEM$STREAM_HAS_DATA`, idempotent `MERGE`, `SKIPPED` task state |
| 6.4 | Orchestrate with Task DAGs | [04_orchestrate_task_dags.sql](04_orchestrate_task_dags.sql) | ~45–55 min | 4.0 (21%) | `AFTER`, parallel branches, join points, `WHEN` clause restrictions, `SYSTEM$TASK_DEPENDENTS_ENABLE`, active-DAG modification rules |
| 6.5 | Write Stored Procedures | [05_stored_procedures.sql](05_stored_procedures.sql) | ~50–60 min | 4.0 (21%) | Snowflake Scripting, cursors, `EXCEPTION` handling, `SYSTEM$SET_RETURN_VALUE` restrictions |
| 6.6 | Work with Dynamic Tables | [06_dynamic_tables.sql](06_dynamic_tables.sql) | ~40–50 min | 4.0 (21%) | `TARGET_LAG`, `DOWNSTREAM` chaining, incremental vs. full refresh, contrast with Goal 5's materialized views |
| 6.7 | Handle Pipeline Errors and Observability | [07_pipeline_errors_observability.sql](07_pipeline_errors_observability.sql) | ~45–55 min | 4.0 (21%) | Dead-letter pattern, `CREATE ALERT`, `ALERT_HISTORY`, `SYSTEM$SEND_EMAIL`, notification integrations |
| Capstone | Three-Way Incremental Pipeline Comparison | [08_capstone.sql](08_capstone.sql) | ~60–75 min | 4.0 (21%) | Combines 6.1–6.7 into one DAG: raw `MERGE` vs. stored procedure vs. Dynamic Table, with failure alerting |
| Exam prep | COF-C03 exam preparation | [09_exam_prep.sql](09_exam_prep.sql) | ~40–45 min | 4.0 (21%) | 15 practice questions, most built directly from this goal's live debugging |

---

## Important notes before starting

### Privilege grants aren't implicit — plan for two `ACCOUNTADMIN` interruptions
Both `EXECUTE TASK` (6.1) and `EXECUTE ALERT` (6.7) failed live on first use, with `SYSADMIN` as owner, because neither privilege is granted implicitly. Both are one-line `ACCOUNTADMIN` grants, made once, that persist for the rest of the goal — but budget for the interruption the first time you hit each one.

### Real, ongoing background credit cost — more sources of it than any prior goal
Scheduled Tasks (6.1, 6.3, 6.4, 6.8), Dynamic Table refreshes (6.6, 6.8), and Alerts (6.7, 6.8) all incur real cost while active. Every sub-task suspends what it created as soon as its teaching purpose is served — don't skip these steps, and double-check `SHOW TASKS` / `SHOW DYNAMIC TABLES` / `SHOW ALERTS` before moving on if you're ever unsure.

### `TARGET_LAG = DOWNSTREAM` needs an active consumer
Confirmed live in the Capstone: a Dynamic Table left in `DOWNSTREAM` mode with its only downstream consumer suspended does **not** reliably refresh, even when resumed itself. If you see stale data from a `DOWNSTREAM`-mode table, check whether its consumer is also suspended before assuming a bug.

### Modifying an active DAG requires suspending the root first — for every change
This tripped up testing repeatedly in 6.4: `CREATE OR REPLACE TASK`, `DROP TASK`, and even `ALTER TASK ... SUSPEND` on a single child all fail while the DAG's root is active. Suspend the root, make the change, then re-run `SYSTEM$TASK_DEPENDENTS_ENABLE` to bring the graph back up.

### Test-data footprint in `ORDERS`
Goal 6 sub-tasks wrote directly into the shared `ECOMMERCE.RAW.ORDERS` table rather than a throwaway clone (unlike Goal 5's approach) — a handful of synthetic rows (`900000001`–`900000010`) and a few status mutations from live testing remain in the dataset. Given the scale of the table (10.37M rows), this was a deliberate decision not to build a reset script for it — noise at this scale, not worth the added complexity.

---

## Key concepts introduced in this goal

**A Stream's offset only advances via DML consumption** — a plain `SELECT` is always a safe preview, never a consumption, regardless of session or how many times it's run.

**Streams report net change, not a statement log** — a row inserted and updated within the same unconsumed window collapses to a single `INSERT`, with no visible intermediate state.

**`MERGE` + Stream consumption is naturally idempotent** — because reading from a stream is part of the same transaction as applying the change, a failed `MERGE` never advances the offset, so a retry safely reprocesses the same pending data.

**`WHEN` clauses are far more restricted than they first appear** — only `SYSTEM$STREAM_HAS_DATA` and `SYSTEM$GET_PREDECESSOR_RETURN_VALUE` (plus basic type conversions) are permitted. No subqueries against tables, in any form.

**`SYSTEM$SET_RETURN_VALUE` cannot be called from inside a `LANGUAGE SQL` procedure** — confirmed against Snowflake's own documentation after two failed live attempts. The scripting block that calls it must live directly in a Task's own body (or inside a `LANGUAGE JAVASCRIPT` procedure, which executes it as a separate dynamic statement).

**Dynamic Tables and materialized views split two capabilities in opposite directions** — Dynamic Tables support joins and multi-table queries but never participate in automatic query rewrite; Goal 5's materialized views are the reverse (single table only, but silently substituted by the optimizer).

**Alerts and Tasks are structurally similar but distinct objects** — both need `WAREHOUSE`/`SCHEDULE`, both are created suspended, both need a separately-granted `EXECUTE` privilege — but an Alert's condition/action split is native to the object, not something built by hand with a `WHEN` clause.

---

## COF-C03 exam coverage

| Domain | Weight | Sub-tasks |
|---|---|---|
| Performance Optimization, Querying, and Transformation | 21% | 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, Capstone |

The exam prep file (`09_exam_prep.sql`) contains 15 questions covering all tested concepts from this goal — the majority built directly from real errors this workbook hit and corrected live, not textbook abstractions.

---

## When you are done

After completing all 8 sub-tasks (including the Capstone) and exam preparation:

1. Commit your progress:
```bash
git add 01-snowflake/goal-06-automation/
git commit -m "feat: complete goal-06 automate workflows"
git push
```

2. Move to [Goal 7: Share and Collaborate](../goal-07-sharing/)

---

*Data Engineering Workbooks · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
