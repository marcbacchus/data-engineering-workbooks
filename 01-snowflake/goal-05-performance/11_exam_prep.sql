/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 5       : Optimize Performance
  Exam Prep    : COF-C03 practice questions
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 35-40 min
  Run in             : Read only — no SQL to execute
  Prerequisites      : Goal 5 sub-tasks 5.1-5.9 and Capstone complete
  COF-C03 domain     : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
──────────────────────────────────────────────────────────────────────────

HOW TO USE THIS FILE
  Read each question and choose your answer BEFORE reading the
  explanation. The learning happens in the moment of choosing, not in
  reading the answer passively.

  Each question references the sub-task where the concept was covered.
  If you get a question wrong, go back to that sub-task before continuing
  — several of these questions are built directly from real results this
  workbook produced during testing, not textbook abstractions.

  Questions are original, written for this workbook using the COF-C03
  exam objectives as a guide — not reproduced from any third-party
  question bank.
══════════════════════════════════════════════════════════════════════════
*/


-- ══════════════════════════════════════════════════════════════════════
--  Q1 — Query Profile fundamentals (Sub-task 5.1)
-- ══════════════════════════════════════════════════════════════════════
/*
You run a query joining two tables. In Query Profile, one table's scan
shows as a "DynamicSecureView" operator instead of "TableScan", with no
pruning statistics reported for it. What is the MOST likely explanation?

  A) The table is a materialized view
  B) The table has a row access policy attached
  C) The query hit the result cache
  D) The table has a masking policy on one of its columns
*/

-- ANSWER: B
-- A row access policy has to evaluate its filter logic in front of the
-- scan, so Snowflake represents that as a distinct wrapper operator
-- rather than exposing the underlying TableScan directly — confirmed on
-- this workbook's own ORDERS table (5.1), where EXPLAIN's OBJECTS column
-- literally labeled it "ORDERS (+ RowAccessPolicy)".
--
-- Why the others are tempting but wrong:
--   A) A materialized view queried directly would show its OWN operator
--      chain, not obscure the table it was built from — and a plain
--      SELECT against a base table wouldn't invoke an unrelated MV at
--      all unless query rewrite substituted it (which shows differently
--      — see Q9).
--   C) A cached result reuse shows as a "QUERY RESULT REUSE" operator
--      with NO other operators at all (5.1/5.4) — not a named table-scan
--      variant alongside normal join/sort operators.
--   D) A masking policy affects returned VALUES, not scan/pruning
--      visibility — a masked column's table still shows as a normal
--      TableScan.


-- ══════════════════════════════════════════════════════════════════════
--  Q2 — Micro-partition pruning math (Sub-task 5.2)
-- ══════════════════════════════════════════════════════════════════════
/*
SYSTEM$CLUSTERING_INFORMATION on an 8-partition table returns
average_depth = 8 and average_overlaps = 7 for a given column. What does
this tell you?

  A) There's a data error — these two numbers should always be equal
  B) The column has perfect clustering
  C) The column has the worst possible clustering — every partition's
     value range overlaps with every other partition
  D) 7 of the 8 partitions can be safely pruned for any filter
*/

-- ANSWER: C
-- average_depth's ceiling equals total_partition_count (8) — a value's
-- range spans every partition, including itself. average_overlaps' 
-- ceiling is total_partition_count - 1 (7) — a partition can't overlap
-- with itself. Both numbers hitting their respective maximums is the
-- SAME underlying fact (total overlap), not a contradiction — confirmed
-- directly on this workbook's PRODUCT_ID column (5.2).
--
-- Why the others are tempting but wrong:
--   A) The two numbers SHOULD differ by exactly 1 at the ceiling — this
--      is expected, not an error.
--   B) The opposite is true — depth near 1 (not 8) would indicate good
--      clustering.
--   D) Backwards — at this depth, essentially NO partition can be safely
--      pruned for an equality filter, since the value could be in any
--      of them.


-- ══════════════════════════════════════════════════════════════════════
--  Q3 — Clustering keys and reclustering (Sub-task 5.3)
-- ══════════════════════════════════════════════════════════════════════
/*
After adding a clustering key and waiting for reclustering to complete,
you notice a table's TOTAL micro-partition count changed from 8 to 3.
What's the best explanation?

  A) This indicates data was lost during reclustering
  B) Reclustering physically rewrites affected rows into a new set of
     micro-partitions, which can change the total count as a side effect
  C) SYSTEM$CLUSTERING_INFORMATION reported a stale number
  D) This only happens when SEARCH OPTIMIZATION is also enabled
*/

-- ANSWER: B
-- Confirmed directly on this workbook (5.3): reclustering isn't just
-- re-sorting values within a fixed set of partitions — it deletes and
-- re-inserts affected rows into NEW, more compact partitions. A shrinking
-- (or growing) total partition count is a normal side effect, not an
-- error. This is exactly why comparing pruning RESULTS before/after
-- clustering should use absolute partitions_scanned, not just
-- pct_scanned — the denominator itself can move.
--
-- Why the others are tempting but wrong:
--   A) Row count is unaffected — reclustering reorganizes layout, not
--      row content.
--   C) The function reflects current, real metadata — not stale data.
--   D) Search optimization is an unrelated feature (5.8) and has no
--      bearing on clustering's partition-count behavior.


-- ══════════════════════════════════════════════════════════════════════
--  Q4 — Result cache mechanics (Sub-task 5.4)
-- ══════════════════════════════════════════════════════════════════════
/*
You run the exact same SELECT statement twice in a row, with
USE_CACHED_RESULT left at its default. The second run shows bytes_scanned
= 0 and an operator type of "QUERY RESULT REUSE". Which of these would
NOT invalidate this cached result on a third identical run?

  A) Running the query from a different warehouse
  B) A different role querying it, with equivalent access privileges
  C) Modifying the underlying table's data between runs
  D) Adding a trailing space inside a string literal in the WHERE clause
*/

-- ANSWER: A
-- The result cache is a Cloud Services layer feature — account-wide, NOT
-- tied to any specific warehouse. Running the identical query text from
-- a DIFFERENT warehouse still hits the same cached result (this is
-- exactly why 5.5's warehouse-size comparison required
-- USE_CACHED_RESULT = FALSE on both runs — otherwise the second
-- warehouse's run would have just returned the first's cached result).
--
-- Why the others are tempting but wrong:
--   B) Different ROLE is fine as long as privileges are equivalent — the
--      requirement is access-equivalence, not identical role name.
--   C) Confirmed directly (5.4): an INSERT into the underlying table
--      invalidated the cache even with byte-for-byte identical query text.
--   D) The match requires syntactically IDENTICAL text — even
--      whitespace/formatting differences inside the query break the
--      match.


-- ══════════════════════════════════════════════════════════════════════
--  Q5 — Warehouse sizing (Sub-task 5.5)
-- ══════════════════════════════════════════════════════════════════════
/*
You resize a running X-Small warehouse to Small mid-session. What happens
to a query that was ALREADY EXECUTING at the moment of the resize?

  A) It's automatically restarted on the new, larger warehouse
  B) It continues running on the ORIGINAL size until it completes
  C) It's queued until the resize finishes, then resumes on the new size
  D) It fails and must be manually re-submitted
*/

-- ANSWER: B
-- Resizing takes effect for queries submitted AFTER the ALTER WAREHOUSE
-- statement — an in-flight query keeps running on whatever size it
-- started on. This is part of why resizing is described as having zero
-- downtime: nothing already running gets interrupted or restarted.
--
-- Why the others are tempting but wrong:
--   A), C), D) All imply some form of interruption or restart — none of
--   which occurs. This is a common misconception given how disruptive
--   resizing is on other platforms (Oracle/SQL Server typically require
--   an actual restart to change compute allocation).


-- ══════════════════════════════════════════════════════════════════════
--  Q6 — Multi-cluster warehouses (Sub-task 5.6)
-- ══════════════════════════════════════════════════════════════════════
/*
A warehouse configured with MIN_CLUSTER_COUNT=1, MAX_CLUSTER_COUNT=3 is
handling 5 concurrent lightweight queries, none of which are queuing.
What would you expect started_clusters to show?

  A) 3, since MAX_CLUSTER_COUNT sets the number that always run
  B) Somewhere between 1 and 3, scaling with the number of concurrent
     sessions regardless of load
  C) 1, since no queries are actually queuing
  D) 5, one cluster per concurrent query
*/

-- ANSWER: C
-- Multi-cluster scaling triggers on QUEUING, not on concurrent session
-- COUNT alone. Confirmed directly on this workbook (5.6): 5 concurrent
-- SYSTEM$WAIT sessions, which consume very little real compute, ran
-- without triggering a second cluster at all — started_clusters stayed
-- at 1 because nothing was actually waiting for capacity.
--
-- Why the others are tempting but wrong:
--   A) MAX_CLUSTER_COUNT is a ceiling, not a fixed running count.
--   B) Session count alone is not the trigger — actual queuing is.
--   D) There's no 1:1 relationship between concurrent queries and
--      clusters; a single cluster can serve many concurrent lightweight
--      queries without any additional cluster starting.


-- ══════════════════════════════════════════════════════════════════════
--  Q7 — Materialized views: restrictions (Sub-task 5.7)
-- ══════════════════════════════════════════════════════════════════════
/*
Which of the following is a valid materialized view definition?

  A) A single-table aggregation with SUM and COUNT, no ORDER BY
  B) A join between two tables, each filtered independently
  C) A single-table aggregation with a window function for running totals
  D) A single-table query with a LIMIT clause
*/

-- ANSWER: A
-- Materialized views are restricted to a SINGLE table with a limited set
-- of supported aggregates (SUM, COUNT, MIN, MAX, AVG, and a few others) —
-- no joins, no window functions, no HAVING, no ORDER BY, no LIMIT.
--
-- Why the others are tempting but wrong:
--   B) Joins are not supported AT ALL in Snowflake materialized views —
--      this is one of the most significant restrictions compared to
--      Oracle (which does support MV joins).
--   C) Window functions are explicitly disallowed.
--   D) LIMIT is explicitly disallowed.


-- ══════════════════════════════════════════════════════════════════════
--  Q8 — Materialized views: query rewrite (Sub-task 5.7)
-- ══════════════════════════════════════════════════════════════════════
/*
You confirm a materialized view is fully populated (row counts match) and
current (behind_by = 0s). You then run a query against the BASE TABLE
that is logically identical to the MV's definition. Which statement is
TRUE?

  A) Snowflake is guaranteed to rewrite the query to use the MV, since it
     is eligible and current
  B) The optimizer may still choose to scan the base table directly, if
     it judges that cheaper than using the MV
  C) The query will fail, since an eligible MV already exists
  D) The MV will be dropped automatically, since it's redundant
*/

-- ANSWER: B
-- Confirmed directly on this workbook (5.7): a fully populated, fully
-- current MV was NOT used by the optimizer for a matching base-table
-- query — GET_QUERY_OPERATOR_STATS showed a plain TableScan + Aggregate,
-- not any MV-related operator. Query rewrite is COST-BASED: eligibility
-- alone doesn't guarantee the swap happens. This is a critical practical
-- takeaway — an MV existing and being current does NOT guarantee it's
-- providing any benefit.
--
-- Why the others are tempting but wrong:
--   A) This is the exact misconception this workbook's testing disproved.
--   C), D) Neither behavior occurs — an unused, eligible MV simply sits
--   idle (while still costing maintenance credits).


-- ══════════════════════════════════════════════════════════════════════
--  Q9 — Search optimization vs. clustering (Sub-tasks 5.3, 5.8)
-- ══════════════════════════════════════════════════════════════════════
/*
A table has two problem queries: one is a single-value equality lookup on
a high-cardinality column, returning very few rows. The other is a range
filter (BETWEEN two dates) that returns a large portion of the table.
Which pairing of fix-to-problem is correct?

  A) Clustering for the equality lookup, search optimization for the
     range filter
  B) Search optimization for the equality lookup, clustering for the
     range filter
  C) Search optimization for both
  D) Clustering for both
*/

-- ANSWER: B
-- Search optimization is purpose-built for point lookups returning FEW
-- rows; clustering is the better fit for range queries or lookups
-- returning MANY rows. This workbook's Capstone tested this exact pairing
-- empirically on real TPC-H data: search optimization took a l_partkey
-- equality lookup from 48/48 to 17/48 partitions scanned; a clustering
-- key took an l_shipdate range query from 48/48 to 3/49 — clustering's
-- improvement was actually LARGER, consistent with it being the better
-- tool for the range-query shape specifically.
--
-- Why the others are tempting but wrong:
--   A) Backwards — this pairs each tool with the shape it's weaker at.
--   C), D) Both tools CAN sometimes work on either shape, but using the
--   wrong one for a given query pattern leaves real performance on the
--   table, as this workbook's own side-by-side test demonstrated.


-- ══════════════════════════════════════════════════════════════════════
--  Q10 — Search optimization: when it can't help (Sub-task 5.8)
-- ══════════════════════════════════════════════════════════════════════
/*
You add search optimization to a column, wait for it to fully build
(progress = 100%), then re-run a point-lookup query on that column.
partitions_scanned is unchanged from before. SYSTEM$CLUSTERING_INFORMATION
on this column shows average_depth equal to total_partition_count. What
is the most likely explanation?

  A) Search optimization failed to build correctly
  B) The specific value being filtered on genuinely exists in every
     partition already, so there's nothing to skip
  C) The warehouse needs to be resized larger for search optimization to
     take effect
  D) Search optimization only works on VARCHAR columns
*/

-- ANSWER: B
-- Confirmed directly on this workbook (5.8): search optimization skips
-- partitions that DON'T contain a filtered value. If average_depth is
-- already at the maximum (matching total_partition_count), the column's
-- values are scattered across every partition — meaning a given value is
-- very likely present in ALL of them already. No indexing technique can
-- skip a partition that legitimately contains matching rows.
--
-- Why the others are tempting but wrong:
--   A) search_optimization_progress = 100 confirms it built successfully.
--   C) Search optimization maintenance runs on Snowflake's own serverless
--   compute, entirely independent of your warehouse's size.
--   D) Search optimization supports equality/IN on most data types, plus
--   substring search — it's not VARCHAR-only.


-- ══════════════════════════════════════════════════════════════════════
--  Q11 — Resource monitors (Sub-task 5.9)
-- ══════════════════════════════════════════════════════════════════════
/*
A resource monitor's TRIGGERS include "ON 100 PERCENT DO SUSPEND". Once
this fires and suspends the warehouse, which of these correctly describes
what's needed to resume normal operation?

  A) It automatically resumes at the start of the next query
  B) It resumes automatically once the FREQUENCY interval resets, or an
     ACCOUNTADMIN intervenes manually before then
  C) Any role can immediately override the suspension
  D) SUSPEND (unlike SUSPEND_IMMEDIATE) never actually stops the
     warehouse — it only sends a notification
*/

-- ANSWER: B
-- A resource-monitor-suspended warehouse stays suspended until either the
-- quota resets on its configured FREQUENCY, or an ACCOUNTADMIN manually
-- raises the quota or adjusts the monitor. This is an important practical
-- risk to understand BEFORE it happens for real — an accidental trip can
-- temporarily block all work on that warehouse.
--
-- Why the others are tempting but wrong:
--   A) There's no automatic resume tied to query submission — a
--      suspended warehouse just stays suspended.
--   C) Only ACCOUNTADMIN (or an explicitly delegated role) can intervene.
--   D) SUSPEND (as opposed to SUSPEND_IMMEDIATE) DOES stop the warehouse
--      — it just waits for currently-running queries to finish first,
--      rather than cancelling them immediately.


-- ══════════════════════════════════════════════════════════════════════
--  Q12 — Resource monitors: scope limitation (Sub-task 5.9)
-- ══════════════════════════════════════════════════════════════════════
/*
Which of the following credit-consuming activities is a resource monitor
attached to your warehouse UNABLE to govern?

  A) A query running on that warehouse for several minutes
  B) A second cluster spinning up on that warehouse under
     multi-cluster load
  C) Background reclustering triggered by a clustering key on a table
  D) An oversized warehouse left running idle before auto-suspend kicks in
*/

-- ANSWER: C
-- Confirmed directly (5.9, citing Snowflake's own documentation):
-- resource monitors govern YOUR warehouse's compute, but CANNOT govern
-- Snowflake's own serverless warehouses — automatic clustering
-- maintenance, materialized view refresh, and search optimization
-- maintenance all run on separate, Snowflake-managed serverless compute
-- that resource monitors have no visibility into or control over.
--
-- Why the others are tempting but wrong:
--   A), B), D) All represent compute running ON your own warehouse
--   (including any additional clusters it spins up) — squarely within
--   what a resource monitor attached to that warehouse governs.


-- ══════════════════════════════════════════════════════════════════════
--  Q13 — CAPSTONE SYNTHESIS (combines 5.1, 5.2, 5.7)
-- ══════════════════════════════════════════════════════════════════════
/*
This workbook's own Goal 5 Capstone found that a materialized view's
byte-scanned reduction (~31x, on an 8-partition test table in Sub-task
5.7) did NOT translate into a visible elapsed_seconds improvement — but a
LATER test on a 48-partition table (in the Capstone) with a similar-shaped
MV DID show elapsed_seconds drop by roughly 65%. What is the best
explanation for why the SAME underlying mechanism produced a visible
time difference in one case but not the other?

  A) The 8-partition table's materialized view wasn't actually working
  B) At very small scale, fixed per-query overhead (compilation, network
     round-trip) dominates total elapsed time, so even a large PROPORTIONAL
     reduction in work done doesn't move wall-clock time meaningfully;
     at larger scale, actual scan time is large enough that reducing it
     produces a visible difference
  C) Materialized views only provide a real benefit above exactly 40
     partitions
  D) The larger table's result was due to warehouse caching, not the
     materialized view
*/

-- ANSWER: B
-- This is the core lesson connecting Sub-task 5.7 and the Capstone:
-- bytes_scanned and elapsed_seconds don't always move together. On a
-- tiny table, the real scan work is already sub-second regardless of
-- whether an MV is used — a 31x reduction in NEGLIGIBLE work is still
-- negligible in absolute terms. On a table large enough that the base
-- scan is a meaningful fraction of total query time, the same
-- proportional reduction becomes visible in wall-clock time too. Neither
-- result was wrong — they were consistent with the same mechanism at two
-- different scales.
--
-- Why the others are tempting but wrong:
--   A) The 5.7 test confirmed the MV WAS being read directly (explicit
--   reference) and DID reduce bytes_scanned ~31x — it worked; the
--   ELAPSED time metric just wasn't sensitive enough at that scale to
--   show it.
--   C) There's no such fixed partition threshold in Snowflake's actual
--   behavior — this is a fabricated, oversimplified rule.
--   D) The Capstone's comparison used USE_CACHED_RESULT = FALSE on both
--   runs specifically to rule out caching as an explanation.


-- ══════════════════════════════════════════════════════════════════════
--  SCORE GUIDE
-- ══════════════════════════════════════════════════════════════════════
/*
  12-13 correct : Strong grasp of Goal 5. Move on to Goal 6 with confidence.
  9-11 correct  : Solid overall, but revisit the specific sub-tasks tied
                  to any question you missed before moving on — several
                  of these test genuine "gotcha" behaviors this workbook
                  discovered empirically, not just textbook definitions.
  6-8 correct   : Re-read the CONCEPT sections of 5.2, 5.3, 5.7, and 5.8
                  specifically — these four sub-tasks account for the
                  majority of this exam prep's questions and are also the
                  most conceptually dense in Goal 5.
  Below 6       : Work back through Goal 5's sub-tasks in order before
                  attempting this file again — the questions build on
                  each other (e.g. Q9 and Q13 assume Q2/Q3's clustering
                  math and Q7/Q8's MV restrictions are already solid).
*/
