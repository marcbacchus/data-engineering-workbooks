# Goal 8: Recover from Mistakes

**Workbook:** Snowflake Engineering
**Status:** ✅ Complete

Author: Marc Bacchus · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)

---

## What you are doing and why

Every prior goal in this workbook assumed the data was correct. Goal 8 is
about what happens when it isn't — a bad `UPDATE` with no `WHERE` clause,
an accidentally dropped table, a migration script with more than one bug
at once. This goal builds the full recovery toolkit Snowflake provides
for exactly those moments, then combines all of it in a single simulated
incident to show how the pieces fit together under real pressure rather
than in isolation.

By the end of this goal you will be able to:

- Query and restore historical data with Time Travel (`AT` / `BEFORE`,
  by `TIMESTAMP`, `OFFSET`, or `STATEMENT`)
- Recover dropped tables, schemas, and databases with `UNDROP`,
  including the realistic name-conflict case and targeting a specific
  non-latest dropped version
- Configure `DATA_RETENTION_TIME_IN_DAYS` at every level (account,
  database, schema, table), understand live vs. frozen inheritance, and
  know the hard caps for transient/temporary tables
- Explain what Fail-safe actually protects, monitor its storage cost,
  and know when (and who) to call when self-service recovery is
  exhausted
- Use zero-copy cloning for tables, schemas, and databases — including
  the storage/grants behavior differences between object types
- Combine cloning with Time Travel to build independent point-in-time
  snapshots, separate from in-place recovery
- Apply clone-and-swap (`ALTER TABLE ... SWAP WITH`) for zero-downtime
  changes to a live table
- Explain the distinction between database replication and failover,
  and what does/doesn't carry over to a replicated secondary

---

## Prerequisites

- Goals 1–7 complete
- ECOMMERCE database with all 10 tables loaded (10,370,254 rows)
- WORKBOOK_WH warehouse configured
- ACCOUNTADMIN access (required throughout — Fail-safe monitoring,
  `ACCOUNT_USAGE` views, replication commands)

---

## Sub-tasks

| # | Sub-task | File | COF-C03 Domain |
|---|---|---|---|
| 8.1 | Time Travel Fundamentals | `01_time_travel_basics.sql` | 1.0 |
| 8.2 | Recovering from Mistakes — UNDROP | `02_undrop_recovery.sql` | 1.0 |
| 8.3 | `DATA_RETENTION_TIME_IN_DAYS` — Configuring Retention | `03_data_retention_configuration.sql` | 1.0 |
| 8.4 | Fail-Safe — The Non-Configurable Last Resort | `04_failsafe.sql` | 1.0 |
| 8.5 | Zero-Copy Cloning Fundamentals | `05_cloning_fundamentals.sql` | 1.0 |
| 8.6 | Cloning + Time Travel Combined | `06_cloning_with_time_travel.sql` | 1.0 |
| 8.7 | Practical Clone Patterns — Dev/Test Refresh & Clone-and-Swap | `07_clone_patterns.sql` | 1.0 |
| 8.8 | Database Replication | `08_database_replication.sql` | 5.0 |
| 8.9 | Capstone — Simulated Incident Recovery | `09_capstone_incident_recovery.sql` | 1.0 |
| 8.10 | Exam Prep (18 questions) | `10_exam_prep.sql` | 1.0 (×14) / 5.0 (×4) |

No `00_reset_goal8.sql` — every sub-task's objects are disposable
sandbox tables/schemas cleaned up within their own file. 8.8's
would-be secondary database was never actually created (replication
stayed conceptual, no second account available), so there's no
cross-account object to tear down either.

---

## Important notes

- ⚠️ **8.8 is conceptual-only, by design** — real database replication
  needs a second Snowflake account to replicate to, which isn't
  available in this workbook's environment. Same treatment as 7.3's
  Data Clean Rooms. What's hands-on in 8.8: confirming this account has
  no replication configured, and the `ACCOUNT_USAGE` monitoring query
  pattern. Everything else is reference syntax, explicitly never
  executed.
- ⚠️ This account is **Enterprise Edition** — failover (promoting a
  secondary to primary) requires **Business Critical Edition** and
  genuinely cannot be run here, not just "not attempted."
- Several sub-tasks in this goal surfaced real live-tested corrections
  to what documentation/AI-assisted drafting initially suggested — see
  Key discoveries below. This goal had an unusually high rate of
  first-draft errors caught by live testing, more than most prior
  goals.

---

## Key discoveries (carried forward — confirmed live)

- `LAST_QUERY_ID()` returns whatever statement most recently completed
  in the session — it must be captured as the very next statement after
  the one you're targeting, not after intervening statements like
  `COMMIT` or a confirmation `SELECT`
- `TRUNCATE` is classified as **DML** in Snowflake (unlike Oracle/SQL
  Server/MySQL, where it's DDL) — it participates in transactions and
  can be rolled back
- Out-of-range `DATA_RETENTION_TIME_IN_DAYS` on a transient object
  raises a **hard compilation error** at CREATE/ALTER time — it does
  NOT silently cap to the nearest valid value
- `DATA_RETENTION_TIME_IN_DAYS` inheritance is **live** for active
  objects (an object with no explicit value keeps following its
  parent's current setting indefinitely) but **freezes** at the value
  in effect when an object is dropped
- `SNOWFLAKE.ACCOUNT_USAGE.TABLES` and `TABLE_STORAGE_METRICS` are not
  interchangeable — only `TABLE_STORAGE_METRICS` breaks storage into
  `ACTIVE_BYTES`/`TIME_TRAVEL_BYTES`/`FAILSAFE_BYTES`; `TABLES` has a
  single undifferentiated `BYTES` column. `TABLE_STORAGE_METRICS` also
  retains historical/dropped object versions by default — filter with
  `TABLE_DROPPED IS NULL` to isolate the live object
- Table-level clones are near-instant; **schema/database clones are
  not** — they're N metadata operations (one per contained object), so
  duration scales with object count, not row count (confirmed: 22 sec
  for a 10-table schema clone, 26 sec for the same tables at database
  level)
- `SHOW GRANTS` on a cloned schema's **child objects** reflects grants
  automatically, independent of `COPY GRANTS` — but `COPY GRANTS`
  itself is a **`CREATE TABLE`/`CREATE VIEW`-only keyword**. `CREATE
  SCHEMA`/`CREATE DATABASE ... CLONE` don't accept it at all — there is
  no syntax that copies a schema's or database's own grants to its
  clone
- `SNOWFLAKE.ACCOUNT_USAGE.DATABASE_REPLICATION_USAGE_HISTORY` columns
  are `START_TIME`, `END_TIME`, `DATABASE_NAME`, `DATABASE_ID`,
  `CREDITS_USED`, `BYTES_TRANSFERRED` — no `PHASE_NAME` column
- When testing that something is preserved/transferred across an
  operation (e.g. grants surviving a clone or swap), confirm there's
  actually something present to test with first — an empty or trivial
  starting state makes a "confirmation" meaningless even if the query
  runs without error

---

## Key concepts

- **Time Travel** — query historical data via `AT`/`BEFORE` with
  `TIMESTAMP`, `OFFSET`, or `STATEMENT`; bounded by
  `DATA_RETENTION_TIME_IN_DAYS`
- **UNDROP** — restores dropped tables/schemas/databases at the object
  level; name conflicts require renaming the current object out of the
  way first
- **Fail-safe** — non-configurable 7-day period after Time Travel ends,
  permanent objects only, Snowflake Support-only recovery
- **Zero-copy cloning** — metadata-only object creation; storage cost
  follows a copy-on-write model, near-zero until either side diverges
- **Clone + Time Travel** — `CLONE ... AT | BEFORE` for independent
  point-in-time snapshots, separate from a one-off Time Travel query
- **Clone-and-swap** — `ALTER TABLE ... SWAP WITH` for atomic,
  zero-downtime promotion of a staged change
- **Database replication vs. failover** — replication (synced read-only
  copy) works on any edition; failover (promotion to writable primary)
  requires Business Critical Edition or higher

---

## COF-C03 exam coverage

| Domain | Weight | Goal 8 sub-tasks |
|---|---|---|
| 1.0 Snowflake AI Data Cloud Features & Architecture | 31% | 8.1–8.7, 8.9 |
| 5.0 Data Collaboration | 10% | 8.8 |

Exam prep: [`10_exam_prep.sql`](./10_exam_prep.sql) — 18 questions
(14 × Domain 1.0, 4 × Domain 5.0)

---

## When you are done

```bash
git add 01-snowflake/goal-08-recovery/
git commit -m "Goal 8: Recover from Mistakes — Time Travel, UNDROP, retention, Fail-safe, cloning, clone-and-swap, replication, capstone, exam prep"
git push
```
