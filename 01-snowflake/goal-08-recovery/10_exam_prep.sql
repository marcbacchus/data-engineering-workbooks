/*═══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 8        : Recover from Mistakes
  Sub-task 8.10 : Exam Prep
═══════════════════════════════════════════════════════════════════════════
  Time to complete : ~25 minutes
  Warehouse size    : N/A — no SQL execution, review only
  Database          : N/A
  Run in            : N/A
  Prerequisites     : 8.1-8.9 complete
  COF-C03 domain    : 1.0 Snowflake AI Data Cloud Features & Architecture (31%)
                       — questions 1-14
                       5.0 Data Collaboration (10%) — questions 15-18
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  WHAT YOU ARE DOING AND WHY
═══════════════════════════════════════════════════════════════════════════
  18 questions covering Goal 8 end to end, weighted toward Domain 1.0 to
  match its 8-of-9 sub-task share of this goal. Several questions are
  built directly from behavior CONFIRMED LIVE while testing 8.1-8.8 —
  not just documented facts, but the specific gotchas that surfaced
  during actual testing (query ID ordering, the transient retention hard
  error, the schema-level COPY GRANTS syntax error, live vs. frozen
  retention inheritance). Real exam questions test exactly this kind of
  "looks right but isn't" detail, so these are worth taking seriously
  even though they came from this workbook's own mistakes.
───────────────────────────────────────────────────────────────────────────*/


/*═══════════════════════════════════════════════════════════════════════════
  DOMAIN 1.0 — Time Travel, Fail-safe, Cloning (questions 1-14)
═══════════════════════════════════════════════════════════════════════════

Q1. [Domain 1.0]
In Snowflake, how is TRUNCATE TABLE classified?
  A. DDL — implicitly commits and cannot be rolled back
  B. DML — participates in transactions and can be rolled back
  C. Neither DDL nor DML — its own separate statement category
  D. DDL in Standard Edition, DML in Enterprise Edition and higher

Q2. [Domain 1.0]
A table's DATA_RETENTION_TIME_IN_DAYS is set to 0, then a row is
deleted. What happens to the deleted row's prior state?
  A. It is queryable via Time Travel for exactly 1 day regardless of
     the 0 setting
  B. For a PERMANENT table, it moves immediately into the 7-day
     Fail-safe period; for a TRANSIENT or TEMPORARY table, it is gone
     with no recovery path at all
  C. It is retained in Fail-safe for 7 days regardless of table type
  D. Setting retention to 0 has no effect on already-existing rows,
     only on rows changed after the setting is applied

Q3. [Domain 1.0]
Which role(s) can initiate a Fail-safe data recovery?
  A. ACCOUNTADMIN, via the FAILSAFE_RECOVERY system function
  B. Any role with OWNERSHIP on the affected object
  C. No role — Fail-safe recovery is Snowflake Support-only, via a
     support ticket
  D. SECURITYADMIN, but only within the same 7-day window as the
     original Time Travel retention

Q4. [Domain 1.0]
A table is dropped, and before anyone notices, a new unrelated table is
created with the exact same name. What is required to restore the
original dropped table?
  A. Nothing extra — UNDROP TABLE always restores the correct version
     by timestamp automatically
  B. The new table must be renamed out of the way first, then UNDROP
     TABLE can restore the original under its original name
  C. The original can never be restored once a same-named object exists
  D. UNDROP TABLE ... IDENTIFIER() must be used instead of plain
     UNDROP TABLE any time a name conflict exists

Q5. [Domain 1.0]
A table name has been dropped and recreated multiple times. What's
required to UNDROP a SPECIFIC older version rather than the most
recent drop?
  A. Multiple consecutive UNDROP TABLE statements, one per version, in
     order
  B. The object's specific ID from SNOWFLAKE.ACCOUNT_USAGE (e.g.
     TABLES), passed via UNDROP TABLE ... IDENTIFIER('<object_id>')
  C. This isn't possible — UNDROP can only ever reach the most recent
     drop of a given name
  D. Setting DATA_RETENTION_TIME_IN_DAYS to a higher value after the
     fact to "unlock" older versions

Q6. [Domain 1.0]
An attempt is made to set DATA_RETENTION_TIME_IN_DAYS = 30 on a
TRANSIENT table. What happens?
  A. The value silently caps at 1, the maximum for transient tables
  B. The statement succeeds, and 30 days of Time Travel is honored
     since Enterprise Edition allows up to 90
  C. A hard compilation error is raised — invalid value for the
     parameter — the statement fails outright
  D. The value silently caps at 90, matching the permanent-table
     Enterprise maximum

Q7. [Domain 1.0]
A table never sets its own explicit DATA_RETENTION_TIME_IN_DAYS and
instead inherits from its schema. The schema's retention is later
changed. What happens to the table's EFFECTIVE retention?
  A. Nothing — the table keeps whatever value it inherited at the
     moment it was created, permanently
  B. It immediately follows the schema's new value — inheritance for
     an ACTIVE object is live, not fixed at creation time
  C. It averages the old and new schema values
  D. It requires an explicit ALTER TABLE to pick up any change from the
     parent schema

Q8. [Domain 1.0]
A table is DROPPED while inheriting a 90-day retention from its schema.
Afterward, the schema's retention is changed to 1 day. What retention
period applies to the ALREADY-DROPPED table?
  A. 1 day — the dropped table immediately follows the new schema value
  B. 90 days — a dropped object's retention is fixed at whatever value
     was in effect at the moment it was dropped, not re-derived from
     the parent afterward
  C. 0 days — dropping the table reset its retention entirely
  D. Whichever is longer between the two values

Q9. [Domain 1.0]
What makes CREATE TABLE ... CLONE fast regardless of the source
table's row count?
  A. Snowflake compresses the data before copying it
  B. It's a metadata-only operation — the clone's metadata simply points
     at the same existing micro-partitions as the source; no data is
     physically copied
  C. Cloning runs on dedicated high-performance serverless compute
  D. Clone operations are capped at a maximum of 1GB regardless of
     source size, keeping them fast

Q10. [Domain 1.0]
Which CREATE ... CLONE statement correctly copies the source object's
explicit access grants to the new clone?
  A. CREATE SCHEMA new_schema CLONE source_schema COPY GRANTS;
  B. CREATE DATABASE new_db CLONE source_db COPY GRANTS;
  C. CREATE TABLE new_table CLONE source_table COPY GRANTS;
  D. All three — COPY GRANTS is supported identically across TABLE,
     SCHEMA, and DATABASE clone statements

Q11. [Domain 1.0]
A schema containing 10 tables is cloned. Compared to cloning a single
table, what should be expected?
  A. Identical near-instant timing — cloning is always a single metadata
     operation regardless of object count
  B. Noticeably longer — a schema/database clone is one metadata
     operation PER CONTAINED OBJECT, so duration scales with object
     count, not row count
  C. The schema clone will always be faster, since it batches all
     tables into one transaction
  D. Timing depends only on total row count across all 10 tables, not
     the number of tables itself

Q12. [Domain 1.0]
Which object type CANNOT be cloned using the AT | BEFORE (Time Travel)
clause under any circumstances?
  A. Permanent tables
  B. Schemas
  C. Temporary tables
  D. Databases

Q13. [Domain 1.0]
When cloning a DATABASE at a point in the past, a child table's own
retention period is shorter than how far back the clone reaches, and
its historical data has already aged out. What parameter allows the
clone to succeed anyway, skipping just that table?
  A. FORCE
  B. IGNORE TABLES WITH INSUFFICIENT DATA RETENTION
  C. COPY GRANTS
  D. ALLOW PARTIAL CLONE

Q14. [Domain 1.0]
What is required to run ALTER TABLE a SWAP WITH b successfully?
  A. SELECT privilege on both tables
  B. OWNERSHIP privilege on both tables, and neither table can be
     TEMPORARY if the other is PERMANENT or TRANSIENT
  C. ACCOUNTADMIN role, regardless of object ownership
  D. Both tables must already have identical column structures


═══════════════════════════════════════════════════════════════════════════
  DOMAIN 5.0 — Data Collaboration / Replication (questions 15-18)
═══════════════════════════════════════════════════════════════════════════

Q15. [Domain 5.0]
Which Snowflake Edition is the MINIMUM required to PROMOTE a secondary
(replicated) database to become the new primary — i.e., to actually
fail over?
  A. Standard Edition
  B. Enterprise Edition
  C. Business Critical Edition
  D. Any edition — promotion is included with basic database
     replication

Q16. [Domain 5.0]
An Enterprise Edition account enables plain database-level replication
(ALTER DATABASE ... ENABLE REPLICATION TO ACCOUNTS) to a target
account. What happens to GRANTS on objects inside the replicated
database?
  A. They replicate automatically, identically to the primary
  B. They do NOT replicate — the target account's own administrator
     must independently grant access on the secondary database
  C. Only OWNERSHIP grants replicate; all other privileges must be
     re-granted manually
  D. Grants replicate only if the COPY GRANTS parameter is included in
     the ENABLE REPLICATION statement

Q17. [Domain 5.0]
What does the IGNORE EDITION CHECK clause on ALTER DATABASE ... ENABLE
REPLICATION TO ACCOUNTS actually do?
  A. Skips validating that the replicated data doesn't contain
     restricted content
  B. Allows an account administrator to replicate a primary database to
     a target account even if that target account is on a lower
     Snowflake edition than would normally be required
  C. Bypasses the requirement for ACCOUNTADMIN to run the statement
  D. Disables Fail-safe on the replicated objects to reduce storage
     cost

Q18. [Domain 5.0]
What is the key distinction between "replication" and "failover" in
Snowflake?
  A. They are the same capability under two different marketing names
  B. Replication requires Business Critical Edition; failover is
     available on all editions
  C. Replication keeps a synced read-only copy of data in another
     account; failover is the additional capability of PROMOTING that
     copy to become the new writable primary, gated to Business
     Critical Edition or higher
  D. Failover only applies to individual tables; replication only
     applies to whole databases


═══════════════════════════════════════════════════════════════════════════
  ANSWER KEY
═══════════════════════════════════════════════════════════════════════════

Q1.  B — Confirmed against Snowflake's own docs (8.1): TRUNCATE is
     classified as DML, unlike Oracle/SQL Server/MySQL where it's DDL.

Q2.  B — 8.4's Fail-safe distinction: retention 0 still routes a
     PERMANENT table through Fail-safe on drop; TRANSIENT/TEMPORARY
     tables have no Fail-safe at all, so 0 there means genuinely gone.

Q3.  C — 8.4: no SQL command or role reaches Fail-safe recovery. It's
     support-ticket-only, full stop.

Q4.  B — 8.2 STEP 2, confirmed live: UNDROP fails outright against an
     existing same-named object; rename the new object out of the way
     first, then UNDROP restores the original under its original name.

Q5.  B — 8.2 STEP 3: SNOWFLAKE.ACCOUNT_USAGE.TABLES (or SCHEMATA /
     DATABASES) provides the object_id needed for
     UNDROP ... IDENTIFIER() to target a specific non-latest version.

Q6.  C — Confirmed LIVE during 8.3 testing: this raises a hard
     compilation error ("invalid value [30] for parameter
     'DATA_RETENTION_TIME_IN_DAYS'"), it does NOT silently cap.

Q7.  B — Confirmed live during 8.3 testing (after an initial file error
     was caught and corrected): inheritance for an ACTIVE object is
     live, following the parent's CURRENT value indefinitely, not fixed
     at creation time.

Q8.  B — The flip side of Q7: a DROPPED object's retention freezes at
     the value in effect at drop time and does not follow later parent
     changes.

Q9.  B — 8.5 CONCEPT: metadata-only, pointing at existing
     micro-partitions rather than physically copying data.

Q10. C — Confirmed live during 8.7 testing (a real file error caught
     and fixed): COPY GRANTS is a CREATE TABLE / CREATE VIEW keyword
     only. CREATE SCHEMA and CREATE DATABASE do not accept it — using
     it there is a straight syntax error.

Q11. B — Confirmed live during 8.5 testing (22 sec for a 10-table
     schema clone, 26 sec for the same tables at database level):
     schema/database clone time scales with object count, not row
     count or data volume.

Q12. C — 8.6 CONCEPT: only databases, schemas, and NON-temporary tables
     support the AT | BEFORE clause with CLONE.

Q13. B — 8.6 STEP 4: IGNORE TABLES WITH INSUFFICIENT DATA RETENTION
     skips child tables whose own retention doesn't reach the requested
     point in time, rather than failing the whole clone.

Q14. B — 8.7 CONCEPT: OWNERSHIP required on both tables; a TEMPORARY
     table can never be swapped with a PERMANENT or TRANSIENT table.

Q15. C — 8.8 CONCEPT: promotion (actual failover) requires Business
     Critical Edition or higher, regardless of which edition supports
     the underlying replication itself.

Q16. B — 8.8 CONCEPT, paralleling the CLONE grants findings from
     8.5/8.7: plain database-level replication does not carry grants to
     the secondary; the target account manages its own access control
     independently.

Q17. B — 8.8 STEP 2 reference syntax: IGNORE EDITION CHECK overrides
     the default edition-matching requirement between source and
     target accounts for database-level replication specifically.

Q18. C — 8.8 CONCEPT / WHAT IF: replication (sync) works on any
     edition; failover (promotion to writable primary) is the
     Business-Critical-gated capability layered on top of it — they are
     related but distinct capabilities, not synonyms.
───────────────────────────────────────────────────────────────────────────*/
