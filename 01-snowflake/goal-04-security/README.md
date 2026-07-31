# Goal 4: Secure Your Environment

**Workbook:** Snowflake Engineering
**Dataset:** E-Commerce (loaded in Goal 2)
**Estimated time:** 5–6 hours total
**Warehouse size:** X-Small throughout
**COF-C03 domains:** Domain 4 — Data Governance and Security (23%)

---

## What you are doing and why

Goal 3 taught you to query the data. Goal 4 teaches you to control who can see it — and how much of it they can see.

This goal covers every layer of Snowflake's security model, built up one mechanism at a time: role-based access control and its hierarchy, the privilege system underneath it, column-level masking, row-level filtering, tag-driven governance, network-level restrictions, and secure views. Each mechanism is independent and evaluates on every query regardless of the others — which is exactly why they compose safely, and exactly what the Capstone sets out to prove.

By the end of this goal you will have:

- Built a real role hierarchy using the access-role/functional-role pattern, not just system roles
- Understood the full privilege grant model, including future grants and why `ALL PRIVILEGES` deliberately excludes `OWNERSHIP`
- Applied dynamic data masking so the same query returns different results depending on who's asking
- Built row access policies using the mapping-table pattern to restrict order visibility by region
- Used tags to bind masking policies to a classification, so new columns inherit protection automatically
- Configured and tested network policies, including the "blocked always wins" precedence rule
- Built secure views and discovered the real difference between "fails outright" and "silently drops grants" as two distinct failure modes across this goal's features
- Proven, in the Capstone, exactly where `CURRENT_ROLE()`-based policies do and don't understand role hierarchy — and fixed every policy in the goal to close that gap

---

## Prerequisites

- Goals 1–3 complete
- All 10 tables loaded in `ECOMMERCE.RAW` (10,370,254 rows)
- `WORKBOOK_WH` warehouse configured
- **Enterprise Edition** account — dynamic data masking and row access policies require it; confirmed available on this workbook's account
- Access to `ACCOUNTADMIN` — required repeatedly throughout this goal (see Important Notes below)

---

## Sub-tasks

Work through these in order. Each file builds on the previous one — the Capstone specifically assumes every role, policy, tag, and view from 4.1–4.8 already exists.

| File | Sub-task | Time | Key concepts |
|---|---|---|---|
| [01_rbac_fundamentals.sql](01_rbac_fundamentals.sql) | RBAC fundamentals | ~30 min | System roles, `ACCOUNTADMIN`/`SYSADMIN`/`SECURITYADMIN`/`USERADMIN`/`PUBLIC`, ownership doesn't cascade, `USAGE` on every container |
| [02_role_hierarchy_custom_roles.sql](02_role_hierarchy_custom_roles.sql) | Role hierarchy and custom roles | ~30 min | Access-role/functional-role pattern, `SHOW GRANTS TO` vs `OF ROLE`, secondary roles |
| [03_privilege_grants_deep_dive.sql](03_privilege_grants_deep_dive.sql) | Privilege grants deep dive | ~35 min | Multiple privileges, `WITH GRANT OPTION`, future grants, `ALL PRIVILEGES` excludes `OWNERSHIP` |
| [04_dynamic_data_masking.sql](04_dynamic_data_masking.sql) | Dynamic data masking | ~40 min | Masking policies, role-based unmasking, `APPLY MASKING POLICY` privilege reality |
| [05_row_access_policies.sql](05_row_access_policies.sql) | Row access policies | ~35 min | Mapping-table pattern, policy runs as its OWNER not the querying role, `CREATE OR REPLACE` fails once attached |
| [06_tag_based_governance.sql](06_tag_based_governance.sql) | Tag-based governance | ~30 min | `CREATE TAG`, binding a masking policy to a tag, new columns inherit protection automatically |
| [07_network_policies.sql](07_network_policies.sql) | Network policies | ~30 min | IP allow/blocklists, "blocked always wins" precedence, no longest-prefix-match |
| [08_secure_views.sql](08_secure_views.sql) | Secure views | ~35 min | Owner's-rights execution, no `APPLY`-style privilege gate, `CREATE OR REPLACE VIEW` silently drops grants without `COPY GRANTS` |
| [09_capstone.sql](09_capstone.sql) | Capstone — combining every security layer | ~50 min | Proves policy composition; `CURRENT_ROLE()` vs `IS_ROLE_IN_SESSION()` and role hierarchy |
| [10_exam_prep.sql](10_exam_prep.sql) | COF-C03 exam preparation | ~35 min | 15 practice questions covering all Goal 4 topics |

A destructive reset script, [`00_reset_goal4.sql`](00_reset_goal4.sql), is also included — it undoes every role, policy, and tag this goal creates so any sub-task can be retested from a clean starting point. Do not run it mid-goal.

---

## Important notes before starting

### `ACCOUNTADMIN` vs. documented minimums
This account consistently required `ACCOUNTADMIN` for operations Snowflake's own documentation suggests `SECURITYADMIN` (or a lesser role) should be able to perform — confirmed across five separate cases in this goal: `APPLY MASKING POLICY`, `APPLY ROW ACCESS POLICY`, `APPLY TAG`, `RECOMMEND_NETWORK_POLICY`/`EVALUATE_CANDIDATE_NETWORK_POLICY`, and network policy user activation. Don't trust documented privilege minimums at face value — test directly.

### Two distinct failure modes, easy to confuse
Sub-tasks 4.4–4.7 (masking, row access, tags, network policies) all **fail outright** if you try `CREATE OR REPLACE` on an object already attached elsewhere — you must use `ALTER ... SET BODY` (or `SET VALUE_LIST`) instead. Sub-task 4.8 (secure views) behaves the opposite way: `CREATE OR REPLACE VIEW` **succeeds silently** but drops every existing grant unless you add `COPY GRANTS` — no error, just quietly broken access discovered later. Know which failure mode applies to which object type.

### Sub-task 4.9 — Capstone
Assumes every object from 4.1–4.8 still exists and is correctly configured. If you've re-run the reset script or skipped a sub-task, the Capstone will not behave as written.

---

## Key concepts introduced in this goal

**Ownership never cascades** — `GRANT OWNERSHIP ON DATABASE` does not extend to its schemas or tables; `GRANT OWNERSHIP ON SCHEMA` does not extend to a warehouse alongside it. Each object level needs its own explicit transfer.

**Every container needs its own `USAGE` grant** — database, schema, and warehouse are three independent grants. A role with full data access can still fail every query on missing warehouse `USAGE` alone.

**`USE SECONDARY ROLES NONE`** — required for any real role-isolation test. The account default (`DEFAULT_SECONDARY_ROLES = ALL`) means a session aggregates every held role's privileges, not just the active primary role.

**`CURRENT_ROLE()` vs. `IS_ROLE_IN_SESSION()`** — `CURRENT_ROLE()` only reflects the literal active primary role, never a role inherited through hierarchy. Any masking or row access policy written against `CURRENT_ROLE()` alone will not recognize a parent role's implicit access — `IS_ROLE_IN_SESSION()` is needed for hierarchy-aware policy logic. This is the Capstone's central lesson.

**Policies run with their OWNER's privileges, not the querying role's** — a row access policy's mapping-table lookup, and a secure view's underlying table access, both execute as whoever owns the policy/view. The querying role never needs direct access to what's underneath.

**"Blocked always wins"** — network policy precedence has no longest-prefix-match the way network routing does; a blocklist entry always overrides a more specific allowlist entry.

---

## COF-C03 exam coverage

| Domain | Weight | Sub-tasks |
|---|---|---|
| Data Governance and Security | 23% | 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9 |

The exam prep file (`10_exam_prep.sql`) contains 15 questions covering all tested concepts from this goal.

---

## When you are done

After completing all 9 sub-tasks, the Capstone, and exam preparation:

1. Commit your progress:
```bash
git add 01-snowflake/goal-04-security/
git commit -m "feat: complete goal-04 secure your environment"
git push
```

2. Move to [Goal 5: Optimize Performance](../goal-05-performance/)

---

*Data Engineering Workbooks · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
