# Goal 9: Monitor and Manage Costs

**Workbook:** Snowflake Engineering
**Status:** Complete ✅
**Estimated time:** ~2.5-3.5 hrs (placeholder — replace with actual time once you total your live sessions)
**Repo folder:** `goal-09-monitoring`

---

## What you are doing and why

Goals 1-8 built, secured, optimized, automated, shared, and made recoverable an entire data pipeline — but none of them asked "what did any of this actually cost, and how would you know if it got out of hand?" Goal 9 closes that gap: reading real credit and storage consumption straight from Snowflake's own system views, attributing cost down to the individual query, and building automated guardrails (resource monitors, alerts) that catch a runaway warehouse before it becomes a surprise on the bill.

By the end of this goal you can:

- Explain Snowflake's credit model precisely enough to predict what a given warehouse size and usage pattern will cost, and why per-second billing with a 60-second minimum makes AUTO_SUSPEND the single highest-leverage cost lever in the platform
- Query warehouse and account-wide credit usage from both INFORMATION_SCHEMA (fresh, narrow) and ACCOUNT_USAGE (complete, laggy) — and know precisely which one to reach for depending on the question
- Distinguish warehouse-backed compute from Snowflake-managed serverless compute (Snowpipe, Automatic Clustering, Search Optimization, and more) in real billing data via METERING_HISTORY's SERVICE_TYPE column
- Know which of Snowflake's three storage views is actually billing-accurate and which two are directional-only — and why treating them as interchangeable is a real mistake, not a pedantic distinction
- Tag and attribute cost to individual queries via QUERY_TAG and QUERY_ATTRIBUTION_HISTORY
- Build, verify, and correctly scope resource monitors — including the account-level vs. warehouse-level distinction, quota pooling across multiple warehouses, and the silent-replacement gotcha at the account level
- Automate cost monitoring with a scheduled Alert that queries real usage data and sends a custom notification, rather than relying solely on a resource monitor's fixed-format NOTIFY
- Run a full diagnose → attribute → contain incident investigation combining all of the above, rather than each technique in isolation

---

## Prerequisites

- Goals 1-8 complete
- ECOMMERCE database with all 10 tables loaded
- WORKBOOK_WH warehouse configured
- ACCOUNTADMIN access (required throughout — resource monitors, ACCOUNT_USAGE queries at scale, and account-level ALTER statements are all ACCOUNTADMIN-gated by default)
- Goal 6's NOTIFICATION INTEGRATION already built (reused in 9.9 rather than duplicated)

---

## Sub-tasks

| # | Sub-task | File | Time | COF-C03 Domain | Key Concepts |
|---|---|---|---|---|---|
| 9.1 | Credit Model Fundamentals | [01_credit_model_fundamentals.sql](01_credit_model_fundamentals.sql) | ~20 min | 2.0 (20%) | Credit model, per-second billing, 60s minimum, warehouse sizing scale |
| 9.2 | Warehouse Metering — INFORMATION_SCHEMA | [02_warehouse_metering_information_schema.sql](02_warehouse_metering_information_schema.sql) | ~20 min | 2.0 (20%) | INFORMATION_SCHEMA table functions, WAREHOUSE_METERING_HISTORY |
| 9.3 | Warehouse Metering — ACCOUNT_USAGE | [03_warehouse_metering_account_usage.sql](03_warehouse_metering_account_usage.sql) | ~20 min | 2.0 (20%) | ACCOUNT_USAGE views, retention vs. latency trade-off |
| 9.4 | Account-Level Serverless Metering | [04_account_level_serverless_metering.sql](04_account_level_serverless_metering.sql) | ~20 min | 2.0 (20%) | METERING_HISTORY, SERVICE_TYPE, serverless billing |
| 9.5 | Storage Cost Views | [05_storage_cost_views.sql](05_storage_cost_views.sql) | ~20 min | 2.0 (20%) | Storage views, billing-accurate vs. directional |
| 9.6 | Query-Level Cost Attribution | [06_query_level_cost_attribution.sql](06_query_level_cost_attribution.sql) | ~25 min | 2.0 (20%) | QUERY_TAG, QUERY_ATTRIBUTION_HISTORY |
| 9.7 | Resource Monitors — Create & Trigger | [07_resource_monitors_create_trigger.sql](07_resource_monitors_create_trigger.sql) | ~20 min | 2.0 (20%) | Resource monitors, CREDIT_QUOTA, TRIGGERS |
| 9.8 | Resource Monitors — Assignment & Scope | [08_resource_monitors_assignment_scope.sql](08_resource_monitors_assignment_scope.sql) | ~20 min | 2.0 (20%) | Account vs. warehouse scope, quota pooling |
| 9.9 | Automating Cost Alerts | [09_automating_cost_alerts.sql](09_automating_cost_alerts.sql) | ~25 min | 2.0 (20%) | Alerts, SNOWFLAKE.ALERT scheduling, SYSTEM$SEND_EMAIL |
| Capstone | Cost Incident — Diagnose, Attribute, Contain | [10_capstone_cost_incident.sql](10_capstone_cost_incident.sql) | ~30 min | 2.0 (20%) | Incident diagnosis workflow, combining 9.2/9.3/9.6/9.7/9.8 |
| Exam prep | 15-question practice set | [11_exam_prep.sql](11_exam_prep.sql) | — | 2.0 (20%) | — |

No `00_reset_goal9.sql` — every sub-task's objects are either read-only (9.1-9.6) or self-contained with their own cleanup/decision points built in (9.7's monitor persists intentionally, 9.8's throwaway pooling warehouse is dropped in-file, 9.9's alert is suspended in-file). Nothing in this goal creates disposable clutter that needs a batch reset.

---

## Important notes

- **This goal requires ACCOUNTADMIN more heavily than most prior goals.** Every ACCOUNT_USAGE query at 9.3 and beyond, every resource monitor operation, and every account-level ALTER statement is gated behind it. Unlike Goal 4's "SECURITYADMIN or higher consistently required ACCOUNTADMIN instead" discovery, this isn't a documented-minimum mismatch — resource monitors and account-level configuration are ACCOUNTADMIN-only by design.
- **Two real decision points were left open deliberately, not defaulted for you:** 9.8's account-level monitor (keep `GOAL9_ACCOUNT_MONITOR_V2` attached long-term, or unset it) and 9.9's alert (leave suspended, or resume for ongoing monitoring). Both are genuine "what do you want this account to do going forward" calls, not oversights.
- **9.7 deliberately did not force a live SUSPEND/SUSPEND_IMMEDIATE trigger.** `CREDIT_QUOTA` rounds decimals down to a whole credit, so the smallest meaningful non-zero quota is 1 credit — roughly an hour of X-Small runtime to actually cross. Step 4 of that file is an explicit, cost-flagged optional stretch exercise rather than something forced into the main path.
- **The capstone's "incident" is real but deliberately cheap** — a handful of tagged, redundant queries standing in for a bad ETL job, not a hypothetical walkthrough. The diagnostic method is real; only the dollar amount is kept trivial on purpose.

---

## Key discoveries to carry forward from Goal 9 (cost/monitoring layer)

- A missing privilege on ACCOUNT_USAGE or MONITOR USAGE-gated INFORMATION_SCHEMA functions returns **zero rows, not an error** — indistinguishable from "genuinely no activity" unless you specifically check role/grants first
- `INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY` is documented as **generally deprecated** in favor of the ACCOUNT_USAGE view, and does **not** include Adaptive Warehouse usage
- `METERING_HISTORY`'s `NAME` column has **context-dependent meaning per SERVICE_TYPE** — warehouse name for WAREHOUSE_METERING, a target table or composite client string for SNOWPIPE_STREAMING, etc. — never assume a universal meaning
- Of the three storage views, only `TABLE_STORAGE_METRICS` is documented as billing-accurate at table grain; `STORAGE_USAGE` and `DATABASE_STORAGE_USAGE_HISTORY` are both explicitly documented as **directional-only**, not designed to reconcile with an invoice
- `QUERY_TAG` precedence is **session > user > account**
- `QUERY_ATTRIBUTION_HISTORY` excludes warehouse idle time by design and carries **up to 8-hour latency** — the longest latency figure anywhere in this goal
- `CREDIT_QUOTA` **silently rounds decimals down** to the nearest whole credit — confirmed live, not just documented
- **`DESCRIBE RESOURCE MONITOR` does not exist** (`Unsupported feature 'TOK_RESOURCE_MONITOR'`) — `SHOW RESOURCE MONITORS` (optionally with `RESULT_SCAN(LAST_QUERY_ID())` for column-level inspection) is the only live way to inspect one
- `TRIGGERS` on `ALTER RESOURCE MONITOR` is **not additive** — it wipes and fully replaces the existing trigger set every time
- Assigning a new account-level resource monitor via `ALTER ACCOUNT SET RESOURCE_MONITOR` **silently replaces** the previous one — no error; the old monitor persists as an object but its `level` reverts to `NULL`
- Warehouses pooled on the same resource monitor **share one quota**, and a SUSPEND/SUSPEND_IMMEDIATE trigger suspends **every** warehouse on that monitor, not just whichever one crossed the line
- Account-level and warehouse-level resource monitors are **both enforced independently** on the same warehouse — whichever fires first wins; neither overrides the other
- An account-level resource monitor does **not** govern Snowflake-provided serverless compute (reconfirms the Goal 5 discovery: "Resource monitors cannot govern Snowflake's own serverless warehouses")
- Alerts are **suspended by default**, same as Tasks (Goal 6) — `ALTER ALERT ... RESUME` required
- Alert condition/action SQL is **not validated at CREATE/ALTER time** — only at execution; check `ALERT_HISTORY`, don't assume success
- `ALTER RESOURCE MONITOR ... SET` requires **at least one `property = value` pair before `TRIGGERS`** — a bare `SET TRIGGERS ...` with no property first is a syntax error, even though it reads as logically equivalent
- `RESULT_SCAN(LAST_QUERY_ID())` — the default offset (`-1`) points to the **immediately preceding** statement; an explicit `LAST_QUERY_ID(-2)` skips one further back than intended if run right after a single SHOW command

---

## Key concepts

Credit model · Per-second billing / 60s minimum · Warehouse vs. serverless compute · INFORMATION_SCHEMA vs. ACCOUNT_USAGE trade-offs · SERVICE_TYPE-based cost attribution · Storage billing accuracy tiers · QUERY_TAG · Per-query cost attribution · Resource monitors (CREDIT_QUOTA, FREQUENCY, TRIGGERS, NOTIFY/SUSPEND/SUSPEND_IMMEDIATE) · Account-level vs. warehouse-level monitor scope · Quota pooling · Alerts (condition/schedule/action) · SNOWFLAKE.ALERT scheduling functions

---

## COF-C03 exam coverage

All 9 sub-tasks, the capstone, and the exam prep set map entirely to:

| Domain | Weight | Goal 9 sub-tasks |
|---|---|---|
| 2.0 Account Management and Data Governance | 20% | 9.1-9.9, capstone (same domain as Goal 4) |

Unlike Goal 8, which genuinely spanned two domains at the sub-task level, Goal 9 doesn't split — every sub-task is Domain 2.0 material (credit/cost views, resource monitors, ACCOUNT_USAGE governance).

---

## When you are done

```bash
git add goal-09-monitoring/
git commit -m "Goal 9: Monitor and Manage Costs — complete (9 sub-tasks + capstone + exam prep)"
git push
```
