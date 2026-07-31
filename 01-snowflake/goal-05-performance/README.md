# Goal 5: Optimize Performance

**Workbook:** Snowflake Engineering
**Dataset:** E-Commerce (loaded in Goal 2) — the Capstone additionally uses Snowflake's free, read-only `SNOWFLAKE_SAMPLE_DATA.TPCH_SF10` sample data
**Estimated time:** 6–7 hours total
**Warehouse size:** X-Small throughout (the Capstone copies real TPC-H benchmark data at ~60M rows, but still runs on X-Small)
**COF-C03 domains:** Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)

---

## What you are doing and why

Goals 1–4 built the environment, loaded the data, learned to query it, and locked it down. Goal 5 is where you learn to make it fast — and, just as importantly, learn when a given performance tool actually helps versus when it's the wrong fit for the problem in front of you.

This goal covers every layer of Snowflake's performance story: reading what actually happened in a query, understanding the storage layer underneath every table, the tools that reorganize or index that storage, the caching layers that can make a query nearly free, warehouse elasticity in both directions (bigger vs. more), and the governance tools that keep all of it under control. Several sub-tasks in this goal produced genuinely inconclusive or "no improvement" results on the workbook's own ECOMMERCE data — that's intentional and instructive, not a failure of the exercise; the Capstone exists specifically to prove out real, measurable wins once the dataset is large enough for them to matter.

By the end of this goal you will have:

- Read and interpreted Query Profile via `GET_QUERY_OPERATOR_STATS` and `EXPLAIN`, including a real row-access-policy blind spot this workbook discovered along the way
- Measured micro-partition pruning quality with `SYSTEM$CLUSTERING_INFORMATION` and connected it directly to real query behavior
- Added, measured, and removed a clustering key — including the real cost warnings and cardinality tradeoffs
- Distinguished result cache, warehouse (local disk) cache, and metadata cache — and hit a genuine self-referencing query gotcha while testing it
- Compared warehouse sizing (vertical) against multi-cluster warehouses (horizontal) for two different problems: single-query speed vs. concurrency
- Built a materialized view and discovered, empirically, that an eligible and current MV is not automatically used by the optimizer
- Applied and measured Search Optimization Service against the exact point-lookup scenario it's built for
- Set up a resource monitor and confirmed the hard limits of what resource monitors can and cannot govern
- Diagnosed and fixed three distinct real-scale performance problems in a single Capstone exercise on genuine TPC-H benchmark data, proving out every technique with real before/after numbers

---

## Prerequisites

- Goals 1–4 complete
- All 10 tables loaded in `ECOMMERCE.RAW` (10,370,254 rows)
- `WORKBOOK_WH` warehouse configured
- **Enterprise Edition** account — required for Sub-tasks 5.6 (multi-cluster), 5.7 (materialized views), and 5.8 (search optimization); confirmed available on this workbook's account
- `ACCOUNTADMIN` access — required for resource monitor creation (5.9) and every `ACCOUNT_USAGE` credit/cost check throughout this goal

---

## Sub-tasks

Work through these in order. Each file builds on the previous one, and several later sub-tasks directly reuse findings from earlier ones (5.8 reuses 5.2's exact column; 5.3 and 5.8 get compared head-to-head in the Capstone).

| File | Sub-task | Time | Key concepts |
|---|---|---|---|
| [01_reading_query_profile.sql](01_reading_query_profile.sql) | Reading Query Profile | ~25–30 min | Query Profile, `GET_QUERY_OPERATOR_STATS`, `EXPLAIN`, row access policy blind spot |
| [02_micro_partitions_and_pruning.sql](02_micro_partitions_and_pruning.sql) | Micro-partitions & Pruning | ~25–30 min | `SYSTEM$CLUSTERING_INFORMATION`, average_depth/overlaps, partition pruning in practice |
| [03_clustering_keys.sql](03_clustering_keys.sql) | Clustering Keys | ~30–35 min | `CLUSTER BY`, automatic reclustering, cardinality cost warnings |
| [04_result_and_warehouse_caching.sql](04_result_and_warehouse_caching.sql) | Result & Warehouse Caching | ~30–35 min | Result cache, warehouse (local disk) cache, metadata cache, `USE_CACHED_RESULT` |
| [05_warehouse_sizing_and_scaling_policies.sql](05_warehouse_sizing_and_scaling_policies.sql) | Warehouse Sizing & Scaling Policies | ~25–30 min | T-shirt sizing, credit doubling per size, live resize, scaling policy concept |
| [06_multi_cluster_warehouses_and_concurrency.sql](06_multi_cluster_warehouses_and_concurrency.sql) | Multi-Cluster Warehouses & Concurrency | ~30–40 min | `MIN/MAX_CLUSTER_COUNT`, scaling policy, concurrency vs. single-query speed |
| [07_materialized_views.sql](07_materialized_views.sql) | Materialized Views | ~30–35 min | Single-table restriction, cost-based query rewrite, refresh maintenance |
| [08_search_optimization_service.sql](08_search_optimization_service.sql) | Search Optimization Service | ~30–40 min | Search access path, point lookups vs. range queries, cardinality warnings |
| [09_resource_monitors_and_query_acceleration_service.sql](09_resource_monitors_and_query_acceleration_service.sql) | Resource Monitors & Query Acceleration Service | ~25–30 min | `CREDIT_QUOTA`, `TRIGGERS`, QAS eligibility, serverless-warehouse blind spot |
| [10_capstone.sql](10_capstone.sql) | Capstone — Diagnose and Fix a Slow Analytics Workload | ~60–75 min | Applies 5.1–5.9 together on real TPC-H benchmark data |
| [11_exam_prep.sql](11_exam_prep.sql) | COF-C03 exam preparation | ~35–40 min | 13 practice questions covering all Goal 5 topics |

---

## Important notes before starting

### Trial-account credit discipline
This goal touches several features with real, ongoing background credit cost (automatic clustering in 5.3, materialized view maintenance in 5.7, search optimization maintenance in 5.8). Every sub-task follows the same discipline: estimate cost first where a function exists to do so, apply narrowly on a throwaway clone rather than a production table, measure, then disable/drop in the same session. Don't skip the cleanup steps.

### Sub-task 5.6 — Multi-Cluster Warehouses
This is the one sub-task in Goal 5 that cannot be scripted sequentially — Step 3 requires multiple Snowsight worksheet tabs open and run simultaneously to generate genuine concurrent load. Read the sub-task fully before starting so you have your tabs ready.

### Sub-task 5.9 — Resource Monitor
The resource monitor created in this sub-task is the one object in this entire goal that is **not** dropped at the end — it's meant to persist as an ongoing safety net for the rest of this workbook series. If you already have your own account-level resource monitor, check `SHOW RESOURCE MONITORS` first; a redundant monitor adds confusion without adding protection.

### Capstone — real cost, real scale
Every prior sub-task in this goal used the workbook's own `ORDER_ITEMS` table (~8 micro-partitions) and repeatedly found it too small for clustering, search optimization, materialized views, or QAS to show a measurable improvement. The Capstone deliberately switches to real TPC-H benchmark data (`SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM`, ~60M rows / 48 micro-partitions) via a genuine `CREATE TABLE ... AS SELECT` copy — not a zero-copy clone, since shared databases can't be cloned. This is the single priciest step in Goal 5; budget real minutes, not seconds, for it. (`TPCH_SF1` was tried first and confirmed insufficient — 6M rows still compressed down to just 8 partitions.)

---

## Key concepts introduced in this goal

**Micro-partition pruning** — Snowflake skips partitions using stored min/max metadata before scanning any real data. Clustering quality (measured via `average_depth`/`average_overlaps`) predicts how well this works for a given column.

**Clustering vs. Search Optimization** — two different fixes for two different query shapes. Clustering favors range queries and lookups returning many rows; search optimization favors point lookups returning few rows. Confirmed head-to-head in this goal's Capstone on identical real data.

**Cost-based materialized view rewrite** — Snowflake's optimizer will only substitute a materialized view for a base-table query if it judges the MV cheaper than a direct scan. An MV being fully populated and current does not guarantee it's actually being used.

**Three distinct caching layers** — result cache (account-wide, Cloud Services layer, 24hr+ retention), warehouse cache (per-warehouse, local SSD, lost on suspend), and metadata cache (always-on, can answer some queries without a running warehouse at all).

**Multi-cluster scaling triggers on queuing, not session count** — several concurrent lightweight sessions may never trigger a second cluster if none of them are actually waiting for capacity.

**Resource monitors cannot govern Snowflake's own serverless warehouses** — automatic clustering, materialized view maintenance, and search optimization maintenance all run on separate, Snowflake-managed compute that no resource monitor (account-level or warehouse-level) can see or control.

---

## COF-C03 exam coverage

| Domain | Weight | Sub-tasks |
|---|---|---|
| Performance & Query Optimization | ~10–15% | 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, Capstone |

The exam prep file (`11_exam_prep.sql`) contains 13 questions covering all tested concepts from this goal, including one capstone-synthesis question built directly from this workbook's own real testing results.

---

## When you are done

After completing all 9 sub-tasks, the Capstone, and exam preparation:

1. Commit your progress:
```bash
git add 01-snowflake/goal-05-performance/
git commit -m "feat: complete goal-05 optimize performance"
git push
```

2. Move to [Goal 6: Automate Workflows](../goal-06-automation/)

---

*Data Engineering Workbooks · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
