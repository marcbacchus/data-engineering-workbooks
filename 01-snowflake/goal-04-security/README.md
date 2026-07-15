# Goal 4: Secure Your Environment

**Workbook:** Snowflake Engineering
**Status:** In Progress

---

## What this goal covers

RBAC · Role hierarchy · Dynamic data masking · Row access policies · Tag-based governance · Network policies · Data sharing

---

## Prerequisites

- Goals 1 and 2 complete
- ECOMMERCE database with all 10 tables loaded (10,350,254 rows)
- WORKBOOK_WH warehouse configured

---

## Recurring patterns across sub-tasks

A few gotchas showed up more than once while building this goal, worth knowing before you hit them yourself rather than after.

**CREATE OR REPLACE fails once a governance object is attached — use ALTER ... SET ... instead.**
Masking policies, row access policies, and network rules all share the same lifecycle restriction: `CREATE OR REPLACE` only works *before* the object is attached to anything (a column, a table, or — for network rules — a network policy's allow/block list). Once attached, `CREATE OR REPLACE` (and `DROP`) fail with an error naming the dependency, and you have to use the in-place update form instead:

| Object type | Update-in-place syntax |
|---|---|
| Masking policy | `ALTER MASKING POLICY <name> SET BODY -> ...` |
| Row access policy | `ALTER ROW ACCESS POLICY <name> SET BODY -> ...` |
| Network rule | `ALTER NETWORK RULE <name> SET VALUE_LIST = (...)` |

This surfaced independently in Sub-tasks 4.4, 4.5, and 4.7 — same underlying Snowflake design, three different object types. Assume it applies to any future governance object type too, and reach for `ALTER ... SET ...` first when editing something that's already in active use.

**APPLY-type privileges are ACCOUNTADMIN-only by default, not SECURITYADMIN — even though similarly-named "MANAGE"-type privileges often are both.**
`APPLY MASKING POLICY`, `APPLY ROW ACCESS POLICY`, and `APPLY TAG` are all global privileges held only by `ACCOUNTADMIN` by default. This is easy to get wrong because `MANAGE GRANTS` (needed for future grants, Sub-task 4.3) — a similarly-scoped global privilege — *is* held by both `ACCOUNTADMIN` and `SECURITYADMIN`. Don't assume one implies the pattern for the other; check each privilege's actual default holder rather than pattern-matching from a previous one.

**Ownership never cascades — transfer it at the exact level where the object lives.**
`GRANT OWNERSHIP ON DATABASE` does not cascade to schemas or tables inside it. `GRANT OWNERSHIP ON SCHEMA` does not extend to a warehouse that happens to live alongside it. Every object level needs its own explicit ownership transfer, and each transfer may need `REVOKE CURRENT GRANTS` if the new owner already holds some unrelated dependent grant on that object.

**Every container needs its own USAGE grant — including warehouses.**
Querying data needs `USAGE` on the database, `USAGE` on the schema, `SELECT` on the table, *and* `USAGE` on the warehouse — four independent grants, not one. A role that already has full data access can still fail every query with "warehouse does not exist or not authorized" if nobody granted it warehouse `USAGE` specifically.

**`USE SECONDARY ROLES NONE` is required for any real isolation test.** By default, a session aggregates privileges from every role a user holds, not just the active primary role. `USE ROLE <x>` alone does not narrow what a query can actually see — testing what a role can do *on its own* requires disabling secondary roles for that test.

---

*Data Engineering Workbooks · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
