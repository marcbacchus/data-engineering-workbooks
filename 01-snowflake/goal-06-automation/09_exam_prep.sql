/*
══════════════════════════════════════════════════════════════════════════
  SNOWFLAKE ENGINEERING WORKBOOK
  Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
  Goal 6       : Automate Workflows
  Exam Prep    : COF-C03 practice questions
══════════════════════════════════════════════════════════════════════════
  Time to complete   : 40-45 min
  Run in             : Read only — no SQL to execute
  Prerequisites      : Goal 6 sub-tasks 6.1-6.7 and Capstone complete
  COF-C03 domain     : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
──────────────────────────────────────────────────────────────────────────

HOW TO USE THIS FILE
  Read each question and choose your answer BEFORE reading the
  explanation. The learning happens in the moment of choosing, not in
  reading the answer passively.

  Each question references the sub-task where the concept was covered.
  If you get a question wrong, go back to that sub-task before continuing
  — several of these questions are built directly from real errors this
  workbook hit during testing (and had to correct live), not textbook
  abstractions. Goal 6 in particular involved more live trial-and-error
  than any prior goal — these questions lean heavily on what that process
  actually surfaced.

  Questions are original, written for this workbook using the COF-C03
  exam objectives as a guide — not reproduced from any third-party
  question bank.
══════════════════════════════════════════════════════════════════════════
*/


-- ══════════════════════════════════════════════════════════════════════
--  Q1 — Task privileges (Sub-task 6.1)
-- ══════════════════════════════════════════════════════════════════════
/*
SYSADMIN successfully runs CREATE TASK, and SHOW TASKS confirms SYSADMIN
as the owner. ALTER TASK ... RESUME then fails with error 091089. What's
the most likely cause?

  A) SYSADMIN needs USAGE on the warehouse first
  B) The task's SQL body has a syntax error
  C) EXECUTE TASK is not implicitly granted to SYSADMIN, even as owner
  D) Tasks can only be resumed by ACCOUNTADMIN
*/

-- ANSWER: C
-- Confirmed live in 6.1: owning a task and being able to CREATE one does
-- not include the EXECUTE TASK privilege needed to actually run it.
-- GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN (issued by ACCOUNTADMIN)
-- resolved it — the same "docs say one role, account requires
-- ACCOUNTADMIN for the grant" pattern seen repeatedly in Goals 4-5.
--
-- Why the others are tempting but wrong:
--   A) Warehouse USAGE would block CREATE TASK itself (and query
--      execution), not specifically RESUME — and CREATE TASK had already
--      succeeded.
--   B) A syntax error would fail at CREATE TASK compilation, not at
--      RESUME.
--   D) SYSADMIN CAN resume tasks — just not without the EXECUTE TASK
--      grant made explicitly first. ACCOUNTADMIN isn't a hard
--      requirement for day-to-day task operation.


-- ══════════════════════════════════════════════════════════════════════
--  Q2 — Serverless tasks (Sub-task 6.1)
-- ══════════════════════════════════════════════════════════════════════
/*
Which property correctly configures a serverless task's initial compute
size, and what state is a newly created task in before anyone touches it?

  A) USER_TASK_MANAGED_INITIAL_SIZE; started
  B) USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE; suspended
  C) SERVERLESS_INITIAL_SIZE; started
  D) USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE; started
*/

-- ANSWER: B
-- Confirmed live in 6.1 (twice — once via a wrong property name that
-- errored, once via the corrected version): the full property name
-- includes WAREHOUSE, and EVERY task — serverless or not — is created
-- SUSPENDED by default, consuming no credits until explicitly resumed.
--
-- Why the others are tempting but wrong:
--   A) This exact wrong name produced "invalid property 'USER_TASK_
--      MANAGED_INITIAL_SIZE' for 'TASK'" live in this workbook.
--   C) Not a real Snowflake property name.
--   D) Half right on the property name, but wrong on default state —
--      no task starts active regardless of compute model.


-- ══════════════════════════════════════════════════════════════════════
--  Q3 — Stream consumption mechanics (Sub-task 6.2)
-- ══════════════════════════════════════════════════════════════════════
/*
You run SELECT * FROM my_stream three times in a row, in three separate
worksheet tabs, with no other activity in between. What happens to the
stream's offset?

  A) It advances once, on the first SELECT
  B) It advances on each SELECT — three times total
  C) It never advances — a bare SELECT is a preview, not a consumption
  D) It advances only if run from the same session
*/

-- ANSWER: C
-- Confirmed live in 6.2, Step 3: the same SELECT was deliberately run
-- twice in a row and returned identical results both times. A stream's
-- offset only advances when it's read from INSIDE a DML statement (an
-- INSERT/MERGE/etc.) that actually commits — never from a plain SELECT,
-- regardless of session or how many times it's run.
--
-- Why the others are tempting but wrong:
--   A) There's no "first read consumes it" rule for plain SELECTs at
--      all — this describes DML consumption, applied to the wrong
--      statement type.
--   B) Same error, just applied three times instead of once.
--   D) Session identity is irrelevant — the distinguishing factor is
--      DML vs. plain SELECT, not which session issued it.


-- ══════════════════════════════════════════════════════════════════════
--  Q4 — Reading stream metadata (Sub-task 6.2)
-- ══════════════════════════════════════════════════════════════════════
/*
Within the SAME uncommitted transaction, a new row is INSERTed and then
immediately UPDATEd before the stream is consumed. How does a STANDARD
stream represent this when it's finally read?

  A) One DELETE row followed by one INSERT row (an update pair)
  B) One INSERT row reflecting only the FINAL values — the intermediate
     state is invisible
  C) Two INSERT rows, one for each statement
  D) An error — Snowflake disallows updating a row inserted earlier in
     the same uncommitted transaction
*/

-- ANSWER: B
-- Confirmed live in 6.2 (and re-confirmed as the root cause of a design
-- bug in Step 6): a stream reports the NET change since the last offset,
-- not a literal statement-by-statement log. A row inserted and updated
-- in the same unconsumed window collapses to a single INSERT with
-- METADATA$ISUPDATE = FALSE — there's no intermediate 'pending' state to
-- report, because nothing consumed the stream between the two statements.
--
-- Why the others are tempting but wrong:
--   A) That's what happens when an UPDATE targets a row that already
--      existed BEFORE the current offset — a genuinely different
--      scenario from this question's same-window insert+update.
--   C) Streams don't log statements individually at all — they report
--      row-level net effect.
--   D) This is completely legal SQL and a completely legal stream
--      scenario — it just collapses in the stream's output, it doesn't
--      error.


-- ══════════════════════════════════════════════════════════════════════
--  Q5 — Stream types (Sub-task 6.2)
-- ══════════════════════════════════════════════════════════════════════
/*
A table has an APPEND_ONLY stream. A row is inserted, then later updated,
then later deleted — all as three separate, individually committed
transactions, with nothing consuming the stream in between. What does the
stream show when finally queried?

  A) All three changes: the insert, the update pair, and the delete
  B) Nothing — APPEND_ONLY streams never show inserts that are later
     modified
  C) Only the original insert — the later update and delete are both
     invisible to an APPEND_ONLY stream
  D) Only the delete — APPEND_ONLY streams show the most recent state
*/

-- ANSWER: C
-- Confirmed live in 6.2, Step 6: APPEND_ONLY streams capture inserts
-- ONLY. Updates and deletes to previously-inserted rows are completely
-- invisible to this stream type, regardless of how much time or how many
-- separate transactions pass — this is what makes APPEND_ONLY suited to
-- pure log/append pipelines where history never needs correcting.
--
-- Why the others are tempting but wrong:
--   A) That's STANDARD stream behavior, the type this question is
--      explicitly NOT asking about.
--   B) The insert IS shown — APPEND_ONLY doesn't suppress inserts, only
--      subsequent updates/deletes to them.
--   D) APPEND_ONLY has no "most recent state" concept — it's a pure
--      append log, not a current-state view.


-- ══════════════════════════════════════════════════════════════════════
--  Q6 — MERGE idempotency (Sub-task 6.3)
-- ══════════════════════════════════════════════════════════════════════
/*
A scheduled Task's body is a single MERGE statement consuming a Stream.
The warehouse fails mid-execution before the MERGE completes. What
happens to the stream's offset, and what happens on the next scheduled
run?

  A) The offset partially advances; the next run processes only the
     remaining rows
  B) The offset does not advance at all; the next run sees and reprocesses
     the exact same pending rows
  C) The stream becomes permanently stale and must be recreated
  D) The MERGE silently skips the rows it already partially processed
*/

-- ANSWER: B
-- This is the core idempotency guarantee established in 6.3: a MERGE is
-- atomic — it either fully commits or fully rolls back. Since reading
-- from the stream (which is what advances its offset) is part of that
-- same transaction, a failed MERGE means the offset-advancing read never
-- actually completed either. The next run sees identical pending data
-- and safely retries — nothing is silently lost or double-applied.
--
-- Why the others are tempting but wrong:
--   A) There's no partial-offset-advance mechanism — MERGE transactions
--      don't commit partially.
--   C) Staleness is governed by DATA_RETENTION_TIME_IN_DAYS elapsing
--      unconsumed, not by a single failed run.
--   D) There's nothing to "skip" — a rolled-back MERGE applied nothing
--      at all, so a retry reprocesses everything cleanly.


-- ══════════════════════════════════════════════════════════════════════
--  Q7 — Task history states (Sub-task 6.3)
-- ══════════════════════════════════════════════════════════════════════
/*
A Task's WHEN clause is SYSTEM$STREAM_HAS_DATA('my_stream'), and the
stream is currently empty. What does TASK_HISTORY() show for that
scheduled run?

  A) The run doesn't appear in TASK_HISTORY() at all — nothing happened
  B) STATE = 'SUCCEEDED', since the WHEN check itself completed without
     error
  C) STATE = 'SKIPPED', with error_code 0040003
  D) STATE = 'FAILED', since the task had nothing valid to do
*/

-- ANSWER: C
-- Confirmed live, identically, in both 6.3 and 6.4: a WHEN clause
-- evaluating FALSE produces STATE = 'SKIPPED' with error_code 0040003
-- ("Conditional expression for task evaluated to false") — recorded as
-- a real history entry, not silently omitted.
--
-- Why the others are tempting but wrong:
--   A) The whole point of recording SKIPPED runs is so you can CONFIRM
--      the guard is working — an absent row would give no such evidence.
--   B) SUCCEEDED specifically means the task's SQL BODY ran to
--      completion — a WHEN=FALSE run never executes the body at all.
--   D) FAILED implies an error occurred during execution — a skipped run
--      isn't an error condition, it's the guard working as designed.


-- ══════════════════════════════════════════════════════════════════════
--  Q8 — DAG join points (Sub-task 6.4)
-- ══════════════════════════════════════════════════════════════════════
/*
A task is defined with AFTER task_a, task_b. In a given scheduled run,
task_a succeeds but task_b fails. What happens to the AFTER task?

  A) It runs anyway, since at least one predecessor succeeded
  B) It does not run — AFTER requires ALL listed predecessors to succeed
  C) It runs, but only processes whatever task_a produced
  D) The entire DAG is automatically retried from the root
*/

-- ANSWER: B
-- A comma-separated AFTER list is an AND condition, not an OR — every
-- named predecessor must succeed in that run for the dependent task to
-- fire. task_a's successful work is still committed; only the join-point
-- task is blocked for that specific run of the graph.
--
-- Why the others are tempting but wrong:
--   A) This describes OR semantics, which AFTER does not have.
--   C) There's no partial/conditional execution based on which
--      predecessors succeeded — it's all-or-nothing for the dependent
--      task's own execution.
--   D) Snowflake has no automatic whole-graph retry mechanism — a failed
--      run just waits for the next scheduled cycle.


-- ══════════════════════════════════════════════════════════════════════
--  Q9 — WHEN clause restrictions (Sub-task 6.4)
-- ══════════════════════════════════════════════════════════════════════
/*
Which WHEN clause is valid on a Task?

  A) WHEN (SELECT COUNT(*) FROM my_table) > 0
  B) WHEN EXISTS (SELECT 1 FROM my_table WHERE status = 'pending')
  C) WHEN SYSTEM$GET_PREDECESSOR_RETURN_VALUE('my_task')::NUMBER > 5
  D) WHEN my_table.row_count > 5
*/

-- ANSWER: C
-- Confirmed live in 6.4, after two failed attempts at options resembling
-- A and B: a WHEN clause permits ONLY SYSTEM$STREAM_HAS_DATA and
-- SYSTEM$GET_PREDECESSOR_RETURN_VALUE (plus basic type conversions like
-- the ::NUMBER cast shown here) — no subqueries against tables, in any
-- form, are allowed.
--
-- Why the others are tempting but wrong:
--   A) This exact pattern failed live with "Invalid expression for task
--      condition... only SYSTEM$GET_PREDECESSOR_RETURN_VALUE,
--      SYSTEM$STREAM_HAS_DATA are allowed."
--   B) Still a table subquery under the hood, regardless of EXISTS vs.
--      scalar syntax — same restriction applies.
--   D) Direct column references have no meaning in a WHEN clause at all
--      — it isn't evaluated in a row context.


-- ══════════════════════════════════════════════════════════════════════
--  Q10 — Modifying an active DAG (Sub-task 6.4)
-- ══════════════════════════════════════════════════════════════════════
/*
A DAG's root task is currently resumed and running on schedule. You need
to change one child task's SQL body. What must you do first?

  A) Nothing — CREATE OR REPLACE TASK works on any task regardless of the
     graph's state
  B) Suspend just that one child task
  C) Suspend the ROOT task of the graph, even if you're only touching a
     child
  D) Drop and recreate the entire DAG from scratch
*/

-- ANSWER: C
-- Confirmed live in 6.4, repeatedly: Snowflake refuses to modify (via
-- CREATE OR REPLACE) OR drop ANY task inside an active graph until the
-- ROOT is suspended — "Unable to update graph with root task ... since
-- that root task is not suspended." This held true even when suspending
-- an individual child directly, not just when replacing it.
--
-- Why the others are tempting but wrong:
--   A) This is exactly what failed live — an active root blocks changes
--      to any task in its graph.
--   B) Suspending only the child, with the root still active, ALSO
--      failed live with the same error — the root specifically must go
--      down first.
--   D) Unnecessarily destructive — suspending the root and making the
--      targeted change is sufficient; nothing needs to be rebuilt from
--      scratch.


-- ══════════════════════════════════════════════════════════════════════
--  Q11 — Scripting variable scope (Sub-task 6.5)
-- ══════════════════════════════════════════════════════════════════════
/*
Inside a Snowflake Scripting FOR loop over a cursor, you need to use the
current row's column value inside an embedded SQL statement. Which
approach works?

  A) Reference it directly: WHERE col = record.column_name
  B) Reference it with a colon directly: WHERE col = :record.column_name
  C) Assign it to its own scalar variable first (no colon), then
     reference THAT variable with a colon inside the SQL statement
  D) Use record.column_name in a LET statement, then never reference it
     in SQL at all
*/

-- ANSWER: C
-- Confirmed live in 6.5, after TWO wrong attempts matching options A and
-- B respectively (both produced "unexpected '.'" or "invalid identifier"
-- errors) and finally verified against Snowflake's own documented cursor
-- example: record.column_name can NEVER appear inside embedded SQL, with
-- or without a colon. It must first be assigned to a plain scalar
-- variable (a scripting expression, no colon needed there), and THAT
-- variable — not the cursor field directly — gets the colon when used in
-- SQL.
--
-- Why the others are tempting but wrong:
--   A) Failed live with "invalid identifier 'RECORD.ORDER_STATUS'" —
--      Snowflake tries to resolve it as a table column, not a scripting
--      reference.
--   B) Also failed live — "unexpected '.'" — a colon doesn't make a
--      dotted cursor-field reference valid inside SQL.
--   D) Defeats the purpose — the whole point is usually to USE the value
--      in a query (a lookup, an insert, a filter), not just hold it.


-- ══════════════════════════════════════════════════════════════════════
--  Q12 — SYSTEM$SET_RETURN_VALUE (Sub-task 6.5)
-- ══════════════════════════════════════════════════════════════════════
/*
You want a Task's return value (readable by a successor via
SYSTEM$GET_PREDECESSOR_RETURN_VALUE) to reflect a value computed inside a
LANGUAGE SQL stored procedure that the task CALLs. Where should
SYSTEM$SET_RETURN_VALUE actually be called from?

  A) Inside the LANGUAGE SQL procedure, as a bare CALL statement
  B) Inside the LANGUAGE SQL procedure, assigned to a variable
  C) It cannot be called from inside a LANGUAGE SQL procedure at all —
     the scripting block must live directly in the Task's own body
     instead
  D) Inside the procedure's RETURN statement
*/

-- ANSWER: C
-- Confirmed live in 6.5, after two separate failed attempts matching A
-- and B, and verified directly against Snowflake's own reference example
-- for this function: SYSTEM$SET_RETURN_VALUE cannot be invoked from
-- inside a LANGUAGE SQL procedure in ANY form — both fail with "Query
-- called from a stored procedure contains a function with side effects."
-- Snowflake's documented pattern puts the entire DECLARE/BEGIN/END
-- scripting block directly in the Task's AS body, with no separate
-- procedure involved for this specific mechanism. (A LANGUAGE JAVASCRIPT
-- procedure CAN call it, since JavaScript executes it as a separate
-- dynamically-constructed statement rather than a native scripting call.)
--
-- Why the others are tempting but wrong:
--   A) Failed live with the side-effects error — being a bare statement
--      instead of an assignment didn't matter.
--   B) Also failed live with the identical error — assignment vs. bare
--      CALL made no difference; the restriction is on being inside a
--      LANGUAGE SQL procedure's query context at all.
--   D) RETURN sets the PROCEDURE's own return value (what CALL hands
--      back to its caller) — a completely separate mechanism from a
--      TASK's return value, which only SYSTEM$SET_RETURN_VALUE controls.


-- ══════════════════════════════════════════════════════════════════════
--  Q13 — Dynamic Tables vs. materialized views (Sub-task 6.6)
-- ══════════════════════════════════════════════════════════════════════
/*
Which statement correctly distinguishes a Snowflake Dynamic Table from
Snowflake's OTHER materialized view feature?

  A) Dynamic Tables support joins across multiple tables; the other
     materialized view feature is restricted to a single source table —
     but Dynamic Tables never participate in automatic query rewrite,
     while the single-table materialized view does
  B) They are the exact same feature under two different names
  C) Dynamic Tables get automatic query rewrite; the single-table
     materialized view does not
  D) The single-table materialized view supports joins; Dynamic Tables do
     not
*/

-- ANSWER: A
-- This is the key distinction worth not mixing up: query COMPLEXITY
-- support and query REWRITE behavior are split across Snowflake's two
-- different materialized-result features, in opposite directions.
-- Dynamic Tables are the closer analog to Oracle's join-capable
-- materialized views on complexity, but you must always query a Dynamic
-- Table BY NAME — it's never silently substituted the way Oracle's
-- fast-refresh MV (or Snowflake's own single-table MV) can be via
-- optimizer rewrite.
--
-- Why the others are tempting but wrong:
--   B) They're genuinely different objects with different capabilities
--      and different creation syntax (Goal 5's MATERIALIZED VIEW vs.
--      Goal 6's DYNAMIC TABLE).
--   C) Backwards — it's the single-table materialized view that
--      participates in query rewrite, not the Dynamic Table.
--   D) Backwards on both counts — swaps which feature supports joins and
--      which doesn't.


-- ══════════════════════════════════════════════════════════════════════
--  Q14 — TARGET_LAG = DOWNSTREAM (Sub-task 6.6)
-- ══════════════════════════════════════════════════════════════════════
/*
A Dynamic Table's TARGET_LAG is set to DOWNSTREAM, and the only Dynamic
Table built on top of it is currently SUSPENDED. What happens to the
upstream table's freshness?

  A) It refreshes on a sensible default schedule regardless
  B) It refreshes as often as its own last known fixed lag before
     switching to DOWNSTREAM
  C) It may not refresh at all — DOWNSTREAM means "refresh only as needed
     to satisfy consumers," and a suspended consumer demands nothing
  D) DOWNSTREAM is rejected at creation time if no active consumer exists
*/

-- ANSWER: C
-- Confirmed live in the Capstone: a Dynamic Table left in DOWNSTREAM mode
-- with its only downstream consumer suspended showed a stale row count
-- even several minutes after being resumed itself — resuming the
-- upstream table alone wasn't suffient. Nothing was actively demanding
-- freshness from it. Switching it to a fixed literal TARGET_LAG resolved
-- it immediately.
--
-- Why the others are tempting but wrong:
--   A) There's no fallback default schedule — DOWNSTREAM genuinely means
--      no independent schedule of its own.
--   B) DOWNSTREAM doesn't preserve or fall back to a prior fixed-lag
--      value — it's a distinct mode, not a temporary override.
--   D) CREATE/ALTER succeeds regardless of whether a downstream consumer
--      currently exists or is active — Snowflake doesn't validate that
--      at creation time.


-- ══════════════════════════════════════════════════════════════════════
--  Q15 — Alerts (Sub-task 6.7 / Capstone)
-- ══════════════════════════════════════════════════════════════════════
/*
Which statement correctly compares a Snowflake ALERT to a Snowflake TASK?

  A) An Alert's action always runs on schedule, same as a Task's body —
     there's no built-in condition check
  B) Both need EXECUTE TASK granted before they can be resumed
  C) An Alert has a required condition/action split built into the
     object itself; both object types are created SUSPENDED and need
     EXECUTE {ALERT|TASK} granted separately before resuming, even for
     the owning role
  D) Alerts cannot write to tables — only send emails
*/

-- ANSWER: C
-- Confirmed live in 6.7: resuming a newly created Alert failed with
-- error 392000 ("EXECUTE ALERT privilege must be granted to owner
-- role") — the exact same pattern as EXECUTE TASK in 6.1, just a
-- distinct privilege for the distinct object type. Structurally, Alerts
-- and Tasks share WAREHOUSE + SCHEDULE + created-suspended-by-default,
-- but an Alert's IF(EXISTS(...))/THEN condition-action split is native
-- to the object, unlike a Task's optional WHEN clause bolted onto an
-- otherwise unconditional body.
--
-- Why the others are tempting but wrong:
--   A) This describes a Task's default behavior, not an Alert's — an
--      Alert's action is conditional by design.
--   B) Close, but imprecise — Alerts need EXECUTE ALERT specifically,
--      not EXECUTE TASK; they're separate privileges for separate object
--      types.
--   D) The dead-letter/logging pattern in 6.7 used a plain INSERT as the
--      alert's action, proven working before email was ever set up —
--      SYSTEM$SEND_EMAIL is one possible action, not a requirement.


-- ══════════════════════════════════════════════════════════════════════
--  SCORE GUIDE
-- ══════════════════════════════════════════════════════════════════════
/*
  13-15 correct : Strong grasp of Goal 6. Move on to Goal 7 with confidence.
  10-12 correct : Solid overall, but revisit the specific sub-tasks tied
                  to any question you missed before moving on — several
                  of these test genuine live failures this workbook hit
                  and had to debug, not just textbook definitions.
  7-9 correct   : Re-read the CONCEPT sections of 6.4 and 6.5 specifically
                  — these two sub-tasks produced the most live errors
                  during testing and account for the densest cluster of
                  questions here (Q8-Q12).
  Below 7       : Work back through Goal 6's sub-tasks in order before
                  attempting this file again — the questions build on
                  each other (e.g. Q9 and Q12 both assume Q7's WHEN/
                  SKIPPED mechanics are already solid).
*/
