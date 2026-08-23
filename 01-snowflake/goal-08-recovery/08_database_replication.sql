/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8       : Recover from Mistakes
  Sub-task 8.8 : Database Replication
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~20 minutes
  Warehouse size    : X-Small (WORKBOOK_WH)
  Database          : ECOMMERCE
  Run in            : Snowsight
  Prerequisites     : 8.1-8.7 complete
  COF-C03 domain    : 5.0 Data Collaboration (10%)
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  This is the one sub-task in Goal 8 that's conceptual-only rather than
  fully hands-on — same treatment as 7.3's Data Clean Rooms, and for the
  same underlying reason: real cross-account replication needs a SECOND
  Snowflake account to replicate TO, which isn't available in this
  workbook's environment. What IS hands-on: viewing this account's
  current replication configuration (there isn't any, which is itself
  worth confirming) and the monitoring views you'd use if there were.
  What's conceptual: actually enabling replication and failover, covered
  through documented syntax and behavior rather than live execution.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CONCEPT
═══════════════════════════════════════════════════════════════════════════
  Two separate mechanisms exist, and this account's EDITION determines
  which are available:

    DATABASE-LEVEL REPLICATION (ALTER DATABASE ... ENABLE REPLICATION
    TO ACCOUNTS) — keeps a read-only copy of a single database in sync
    with a source. Available on ALL editions, including this account's
    Enterprise. An account admin can force this even across a lower
    edition target using IGNORE EDITION CHECK.

    REPLICATION AND FAILOVER GROUPS (CREATE REPLICATION GROUP / CREATE
    FAILOVER GROUP) — the newer, broader mechanism. Replication groups
    can replicate databases, shares, and (Business Critical+) other
    account objects like roles, warehouses, and integrations. FAILOVER
    groups add one more capability on top: PROMOTING a secondary to
    become the new primary (writable) — this promotion capability
    specifically requires Business Critical Edition or higher,
    regardless of which mechanism replicates the underlying data.

  The distinction that actually matters for this account: REPLICATION
  (keeping a synced read-only copy) works fine on Enterprise. FAILOVER
  (promoting that copy to become writable/primary) does not — that's
  the wall this sub-task keeps bumping into, matching what was confirmed
  at Goal 8 planning time.

  What does and doesn't replicate with plain database-level replication —
  and this is worth pausing on, because it directly parallels 8.5/8.7's
  clone grants findings:
    - GRANTS on objects inside the replicated database are NOT
      replicated to the secondary — same story as CLONE, for a related
      reason: a secondary database's own access control is managed
      independently in its own account, not inherited from the primary.
    - Account-level PARAMETERS are not replicated via database-level
      replication (only via account-level replication, Business
      Critical+).
    - PIPES and STAGES are not replicated by plain database replication
      at all (stage/pipe replication is a replication/failover GROUP
      capability instead).
    - Security policies and tags replicate, but with real edition
      constraints of their own — a primary database with a masking
      policy or tag can fail to promote if any approved target account
      is on a lower edition than required for that policy type.

  ── Oracle / SQL Server comparison ─────────────────────────────────────
  Oracle's closest analog is Data Guard (physical or logical standby,
  with fast-start failover) — a mature, well-known capability, but one
  that requires separately licensed Enterprise Edition options and real
  infrastructure you provision and manage (standby servers, redo
  transport configuration, observer processes for automatic failover).
  SQL Server's equivalent — Always On Availability Groups, or the older
  Log Shipping — carries the same story: genuinely capable, but
  infrastructure YOU build and maintain. Snowflake's replication is
  built into the platform with no separate servers to provision, works
  natively across regions and even across cloud providers (AWS, Azure,
  GCP) in the same statement, and the only real gate is which Edition
  tier unlocks which capability — not a separate licensing negotiation
  or infrastructure project. This is a meaningful selling point to make
  concrete for this audience, even without a second account to prove it
  hands-on.
  ────────────────────────────────────────────────────────────────────────
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  SETUP
═══════════════════════════════════════════════════════════════════════════
  All replication commands and monitoring views require ACCOUNTADMIN.
───────────────────────────────────────────────────────────────────────────*/

USE ROLE ACCOUNTADMIN;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 1 — Confirm current replication configuration (expect: none)
═══════════════════════════════════════════════════════════════════════════
  Real, runnable, read-only. Expect zero rows from both — confirming
  there's genuinely no replication configured in this account yet,
  rather than assuming it based on the account setup alone.
───────────────────────────────────────────────────────────────────────────*/

-- Accounts in this organization where replication has been enabled
SHOW REPLICATION ACCOUNTS
;

-- Databases in this account currently configured as primary or
-- secondary for replication
SHOW REPLICATION DATABASES
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 2 — Enabling database replication (reference only — NOT executed)
═══════════════════════════════════════════════════════════════════════════
  ⚠️ Not run here — this needs a real target account in the organization,
  which this workbook's environment doesn't have. Syntax for reference:

    ALTER DATABASE ECOMMERCE
    ENABLE REPLICATION TO ACCOUNTS <org_name>.<target_account_name>;

  To force this across a lower-edition target account:

    ALTER DATABASE ECOMMERCE
    ENABLE REPLICATION TO ACCOUNTS <org_name>.<target_account_name>
    IGNORE EDITION CHECK;

  In the TARGET account, an ACCOUNTADMIN would then run:

    CREATE DATABASE ECOMMERCE_REPLICA
    AS REPLICA OF <org_name>.<source_account_name>.ECOMMERCE;

  ...followed by a manual or scheduled ALTER DATABASE ... REFRESH to
  sync it, typically via a Task on a short interval (Snowflake recommends
  10 minutes or less for predictable refresh behavior).
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  STEP 3 — Monitoring replication (real query pattern, expect 0 rows)
═══════════════════════════════════════════════════════════════════════════
  If replication WERE configured, this is how you'd track refresh
  history, data transferred, and credits consumed by the (serverless)
  replication service — same idea as 8.4's FAILSAFE_RECOVERY check
  against METERING_HISTORY, just a different service type.
───────────────────────────────────────────────────────────────────────────*/

SELECT
    database_name,
    database_id,
    start_time,
    end_time,
    credits_used,
    bytes_transferred
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_REPLICATION_USAGE_HISTORY
ORDER BY start_time DESC
;


/*═══════════════════════════════════════════════════════════════════════════
  STEP 4 — Failover groups and the Business Critical wall
  (reference only — NOT executed)
═══════════════════════════════════════════════════════════════════════════
  ⚠️ Requires Business Critical Edition or higher — this account is
  Enterprise, so this genuinely cannot be run here, not just "not
  attempted." Syntax for reference:

    CREATE FAILOVER GROUP ecommerce_fg
    OBJECT_TYPES = DATABASES
    ALLOWED_DATABASES = ECOMMERCE
    ALLOWED_ACCOUNTS = <org_name>.<target_account_name>
    REPLICATION_SCHEDULE = '10 MINUTE';

  Promoting a secondary to primary (the actual "failover" event) is a
  separate statement, run FROM the target account holding the secondary:

    ALTER FAILOVER GROUP ecommerce_fg PRIMARY;

  Attempting either of these against this Enterprise account returns an
  edition-restriction error rather than executing — Business Critical
  specifically, not just "a higher tier," is the requirement for BOTH
  creating a failover group and promoting one.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  CLEANUP
═══════════════════════════════════════════════════════════════════════════
  Nothing was created in this sub-task — STEP 2 and STEP 4 are reference
  syntax only, never executed.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  PRACTICE GAP
═══════════════════════════════════════════════════════════════════════════
  1. Read through SHOW REPLICATION DATABASES' documented output columns
     (even with zero rows returned here). What column would tell you
     whether a given database is currently serving as PRIMARY or
     SECONDARY? What would you expect to see change in that column
     immediately after a failover promotion?

  2. This account's ECOMMERCE database has row access policies from
     Goal 4 and (potentially) tags from earlier goals. Per the CONCEPT
     section's note on policy/tag edition constraints, what specifically
     would need to be true about a target account's edition for
     ECOMMERCE to replicate there successfully with its policies intact?

  3. Compare the REFRESH mechanism for plain database-level replication
     (a manually-scheduled Task running ALTER DATABASE ... REFRESH)
     against a failover group's built-in REPLICATION_SCHEDULE parameter.
     What operational burden does the failover-group approach remove
     that the plain database-replication approach leaves entirely to
     you?
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT IF
═══════════════════════════════════════════════════════════════════════════
  Q: If I "failover" to a secondary database, does the OLD primary
     automatically become a secondary of the new primary, or does it
     just stop being anything?
  A: It automatically becomes a read-only secondary of the newly
     promoted primary — failover isn't a one-way cutover that orphans
     the old primary, it flips the roles between the two databases while
     keeping the replication relationship intact.

  Q: Is "replication" the same thing as "failover," just under a
     different name?
  A: No, and this is worth being precise about for exam purposes:
     REPLICATION is keeping a synced read-only copy somewhere else —
     available on every edition. FAILOVER is specifically the ability to
     PROMOTE that copy to become the new writable primary — a Business
     Critical+ capability layered on top of replication, not a
     rebranding of it. You can have replication without any failover
     capability at all (this account's actual situation, if it ever
     enabled replication).

  Q: Given GRANTS don't replicate with plain database-level replication,
     how would a target account actually give anyone access to the
     replicated secondary database once it exists?
  A: The target account's own ACCOUNTADMIN (or a role with sufficient
     privilege there) has to independently GRANT access on the secondary
     database after it's created — same manual step as re-granting
     access after a CLONE without COPY GRANTS in 8.5/8.7. Replication
     copies the DATA; it deliberately does not copy who's allowed to see
     it, since access control is meant to stay under each account's own
     administration.
───────────────────────────────────────────────────────────────────────────*/
