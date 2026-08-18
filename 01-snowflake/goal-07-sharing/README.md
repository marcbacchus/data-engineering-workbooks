# Goal 7: Share and Collaborate

**Workbook:** Snowflake Engineering
**Time to complete:** ~2-3 hrs
**Warehouse:** WORKBOOK_WH (X-Small)
**Database:** ECOMMERCE
**Run in:** Snowsight

---

## What you are doing and why

Every goal up to this point assumed one account, one set of roles, one
team. Goal 7 breaks that assumption. You'll act as both a data
**provider** (handing another account live, governed access to your
data) and a data **consumer** (pulling in a live third-party dataset
and enriching your own data with it) — then look at the model
Snowflake offers for the case where neither side is willing to be
either.

By the end of this goal you will have:

- Created a real managed reader account and shared a secure view of
  ECOMMERCE data with it, live, across an actual account boundary
- Mounted a free Snowflake Marketplace listing and joined it against
  ORDERS/CUSTOMERS for genuine enrichment — not just a `SELECT *`
- Hit and resolved a real cross-goal interaction: a Goal 4 row access
  policy silently zeroing out a Goal 7 share, and understood *why*
  context functions behave differently across account boundaries
- Learned why Data Clean Rooms exist as a separate model from secure
  sharing, and why that sub-task stays conceptual in a solo workbook
  environment

---

## Prerequisites

- Goals 1-6 complete
- ECOMMERCE database with all 10 tables loaded (10,370,254 rows)
- WORKBOOK_WH warehouse configured
- ACCOUNTADMIN role available (required for managed accounts, share
  management, and Marketplace listing acquisition)
- Enterprise Edition account (confirmed relevant in 7.3 — required for
  a Data Provider role in a real Data Clean Room, though this goal's
  own account is Enterprise, a genuine clean room build-out still
  needs a second independent account, which is why 7.3 stays
  conceptual)

---

## Sub-tasks

| # | Sub-task | File | What you'll build |
|---|---|---|---|
| 7.1 | Share data between Snowflake accounts | [01_share_data.sql](01_share_data.sql) | Managed reader account, secure view, live cross-account share and query |
| 7.2 | Use the Snowflake Marketplace | [02_marketplace.sql](02_marketplace.sql) | Mounted free weather listing, joined against ORDERS/CUSTOMERS for enrichment |
| 7.3 | Understand Data Clean Rooms | [03_clean_rooms.sql](03_clean_rooms.sql) | Conceptual only — no hands-on component (requires a second independent account) |
| 7.4 | Exam prep | [04_exam_prep.sql](04_exam_prep.sql) | 13 COF-C03 practice questions, Domain 5.0 |

No capstone for this goal — three genuinely hands-on/conceptual
sub-tasks is a thin domain (10% exam weight, and one sub-task is
fully conceptual), so a capstone would be padding rather than real
synthesis.

---

## Important notes before starting

- **7.1 has a real, ongoing background cost.** A managed reader
  account runs its own warehouse, billed to *your* provider account
  for as long as it exists. The sub-task ends with an explicit
  teardown — don't skip it.
- **Reader-account login needs a separate browser session.** A second
  tab in the same browser will often silently reuse your provider
  account's Snowsight session instead of prompting a fresh login for
  the reader account. Use an incognito/private window.
- **`ALTER SHARE ... ADD ACCOUNTS` does not take the identifier you
  created the managed account with.** It needs the `locator` column
  from `SHOW MANAGED ACCOUNTS`, unquoted. This one cost real
  debugging time live — see 7.1 STEP 4.
- **Row access policies from Goal 4 can silently break a Goal 7
  share.** If a shared table has a policy using `CURRENT_ROLE()` or
  `IS_ROLE_IN_SESSION()`, a cross-account query returns zero rows
  with *no error* — not a bug, but a real interaction worth
  understanding before you hit it elsewhere. See 7.1 STEP 5.5.
- **Marketplace listing names and providers change.** The listing
  used in 7.2 was renamed from "Weather Source LLC: frostbyte" to
  "Pelmorex Weather Source: Frostbyte" between when this workbook was
  planned and when it was tested. Search by keyword, not exact title.
- **The free weather listing's coverage is limited**, not global —
  roughly 1,000 sampled US zip codes plus a handful of named
  international cities. A naive country-wide join returns almost
  nothing; 7.2 uses a small representative city mapping instead.

---

## Key concepts

**Secure Data Sharing is metadata-only, not a copy.** The consumer's
own warehouse reads the provider's underlying micro-partitions
directly — nothing is copied, provider storage is unaffected no
matter how many consumers query a share.

**Two consumer models exist for very different situations.** A
managed reader account is for a consumer with no Snowflake account of
their own, fully billed to the provider. A full account consumer pays
for their own compute and just needs `ALTER SHARE ... ADD ACCOUNTS`
with their org-qualified account name — no reader account, no
credentials to manage on your side.

**Row/masking policies don't automatically know about a cross-account
query.** Context functions like `CURRENT_ROLE()`, `CURRENT_USER()`,
and `IS_ROLE_IN_SESSION()` have nothing to resolve to when the query
originates from a different account's session — they silently fail
closed (zero rows), not open. A policy meant to protect shared data
across accounts needs to be written around `CURRENT_ACCOUNT()`
instead.

**The Marketplace is the same sharing mechanism with a storefront in
front of it.** A listing is a provider's packaged share plus metadata
(title, description, sample queries, pricing). Mounting one via "Get"
is functionally the same `CREATE DATABASE FROM SHARE` you ran by hand
in 7.1.

**Marketplace data is live, not a snapshot.** No refresh job exists
or is needed on the consumer side — the provider's updates are
visible immediately. What does behave like ordinary Snowflake query
performance is the *first* query against a newly mounted object:
confirmed live at 27 seconds cold vs. 878ms on immediate re-run,
purely a result-cache effect, not a sharing-mechanism cost.

**A Data Clean Room solves a different trust problem than sharing
does.** Secure sharing assumes the provider is willing to grant the
consumer direct query access to real rows. A clean room exists for
when *neither* side is willing to do that — collaborators pre-agree
on a fixed set of allowed analyses, and only aggregated/protected
output is ever visible to either party.

---

## COF-C03 exam coverage

| Domain | Weight | Sub-tasks |
|---|---|---|
| Data Collaboration | 10% | 7.1, 7.2, 7.3 |

The exam prep file (`04_exam_prep.sql`) contains 13 questions covering
all tested concepts from this goal — most built directly from real
errors this workbook hit and corrected live (locator vs. identifier,
`SHOW GRANTS OF SHARE` timing, the row access policy interaction, the
cold-cache performance finding), not textbook abstractions.

---

## When you are done

After completing all 4 sub-tasks including exam preparation:

1. Commit your progress:
```bash
git add 01-snowflake/goal-07-sharing/
git commit -m "feat: complete goal-07 share and collaborate"
git push
```

2. Move to [Goal 8: Recover from Mistakes](../goal-08-recovery/)

---

*Data Engineering Workbooks · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
