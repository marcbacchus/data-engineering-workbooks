-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author       : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 6       : Automate Workflows
-- Sub-task 6.5 : Write Stored Procedures
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~50-60 min
-- Warehouse size    : X-Small (WORKBOOK_WH)
-- Database          : ECOMMERCE.RAW
-- Run in            : Snowsight
-- Prerequisites     : Sub-tasks 6.1-6.4 complete — reuses the
--                      EXECUTE TASK grant to SYSADMIN made in 6.1
-- COF-C03 domain    : Domain 4.0 — Performance Optimization,
--                      Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- WHAT YOU ARE DOING AND WHY
-- ══════════════════════════════════════════════════════════════
--   Everything so far has been single SQL statements — a MERGE, a
--   CREATE TABLE AS, an INSERT. Real pipeline logic often needs
--   variables, loops, conditionals, and error handling that a
--   single statement can't express. Stored procedures give you
--   that, in a real procedural language, callable from a Task the
--   same way a plain SQL statement is.
--
--   This sub-task also closes a loop left open in 6.4: branching
--   a DAG on a genuinely COMPUTED value (not just "did the stream
--   have data") requires a procedure that explicitly sets a task's
--   return value — which needed Snowflake Scripting to do properly.
--   You'll build that here.
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- CONCEPT
-- ══════════════════════════════════════════════════════════════
--   Snowflake Scripting is the procedural language layered on top
--   of SQL: DECLARE for variables, BEGIN/END for the body, LET for
--   inline assignment, IF/CASE for branching, FOR/WHILE for loops,
--   and RETURN for the procedure's result. Any scripting variable
--   referenced INSIDE an embedded SQL statement needs a leading
--   colon (:variable_name). A cursor row-variable's individual
--   field (e.g. record.column_name) can NEVER be referenced
--   directly inside SQL, colon or not — it must first be assigned
--   to its own scalar variable (a plain scripting expression, no
--   colon), and THAT scalar variable is what gets the colon when
--   used inside SQL. Confirmed live, after two wrong attempts:
--   neither "record.column_name" nor ":record.column_name" work
--   inside embedded SQL — only ":plain_scalar_variable" does. A procedure's declared
--   RETURNS type is what CALL produces back to whoever invoked it
--   — this is completely separate from a TASK's return value
--   (SYSTEM$SET_RETURN_VALUE/SYSTEM$GET_PREDECESSOR_RETURN_VALUE
--   from 6.4), which is a DAG-level mechanism a procedure can
--   trigger as a side effect, not the same thing as its own RETURN.
--
--   Error handling uses an EXCEPTION block, not TRY/CATCH — that's
--   Snowflake Scripting's own vocabulary, borrowed conceptually
--   from PL/SQL's EXCEPTION section rather than T-SQL's TRY/CATCH.
--   You can define named exceptions with custom SQLSTATE-like codes
--   and messages, RAISE them deliberately, and catch them (or any
--   unanticipated error via WHEN OTHER) without the whole procedure
--   aborting uncontrolled.
--
--   JavaScript procedures (LANGUAGE JAVASCRIPT) predate Snowflake
--   Scripting and are still supported, but for most SQL-centric
--   logic they're now a legacy option rather than the default
--   choice — Snowflake Scripting covers the same ground with SQL-
--   native syntax and no context-switching between languages. JS
--   procedures remain useful for genuinely JavaScript-shaped logic
--   (complex string/regex manipulation, calling out to certain
--   APIs) but aren't the starting point for typical ELT logic.
--
--   Calling a procedure from a Task is just CALL <procedure_name>()
--   as the task's AS body — a Task doesn't know or care whether its
--   single statement is a MERGE or a CALL.
--
-- ── ORACLE / SQL SERVER COMPARISON ──────────────────────────────
--   Oracle       : PL/SQL stored procedures — DECLARE/BEGIN/END,
--                  EXCEPTION sections, cursors, all structurally
--                  very close to Snowflake Scripting. The closest
--                  analog of anything in this workbook so far.
--   SQL Server   : T-SQL stored procedures with TRY/CATCH blocks
--                  and @variables — conceptually equivalent, with
--                  T-SQL's THROW/CATCH replaced by Snowflake's
--                  RAISE/EXCEPTION vocabulary and : replacing @ for
--                  variable references inside SQL text.
--   Snowflake    : Procedures are schema-level objects like tables
--                  or views (CREATE PROCEDURE, fully qualified,
--                  overloadable by argument signature) rather than
--                  living in a separate "programmability" namespace
--                  the way SQL Server organizes them.
-- ──────────────────────────────────────────────────────────────
-- ══════════════════════════════════════════════════════════════

USE ROLE SYSADMIN;
USE WAREHOUSE WORKBOOK_WH;
USE DATABASE ECOMMERCE;
USE SCHEMA RAW;

-- ══════════════════════════════════════════════════════════════
-- SETUP
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE ECOMMERCE.RAW.STATUS_COUNT_LOG (
    order_status VARCHAR,
    order_count  NUMBER,
    logged_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE ECOMMERCE.RAW.PROCEDURE_ERROR_LOG (
    error_message VARCHAR,
    occurred_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ══════════════════════════════════════════════════════════════
-- STEP 1: A basic procedure — parameter, variable, RETURN
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE ECOMMERCE.RAW.GET_ORDER_STATUS_COUNT(status_filter VARCHAR)
RETURNS NUMBER
LANGUAGE SQL
AS
$$
DECLARE
    result_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO :result_count
    FROM ECOMMERCE.RAW.ORDERS
    WHERE order_status = :status_filter;

    RETURN result_count;
END;
$$;

CALL ECOMMERCE.RAW.GET_ORDER_STATUS_COUNT('pending');
CALL ECOMMERCE.RAW.GET_ORDER_STATUS_COUNT('shipped');

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Control flow — a cursor-driven FOR loop
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE ECOMMERCE.RAW.LOG_ALL_STATUS_COUNTS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    status_cursor CURSOR FOR SELECT DISTINCT order_status FROM ECOMMERCE.RAW.ORDERS;
    current_status VARCHAR;
    current_count   NUMBER;
    rows_logged     NUMBER DEFAULT 0;
BEGIN
    FOR record IN status_cursor DO
        -- Assign the cursor record's field to its own scalar
        -- variable FIRST (no colon here — this is a scripting
        -- expression, not embedded SQL). record.column_name can
        -- NEVER be referenced directly inside a SQL statement,
        -- even with a colon in front of it.
        current_status := record.order_status;

        -- NOW reference the scalar variable with a colon, since
        -- this IS embedded SQL.
        SELECT COUNT(*) INTO :current_count
        FROM ECOMMERCE.RAW.ORDERS
        WHERE order_status = :current_status;

        INSERT INTO ECOMMERCE.RAW.STATUS_COUNT_LOG (order_status, order_count)
        VALUES (:current_status, :current_count);

        rows_logged := rows_logged + 1;
    END FOR;

    RETURN 'Logged ' || rows_logged || ' status rows';
END;
$$;

CALL ECOMMERCE.RAW.LOG_ALL_STATUS_COUNTS();

SELECT * FROM ECOMMERCE.RAW.STATUS_COUNT_LOG ORDER BY logged_at DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 3: Error handling with an EXCEPTION block
-- ══════════════════════════════════════════════════════════════
-- Deliberately triggers a custom exception on divide-by-zero,
-- logs it, and returns a controlled message instead of aborting.

CREATE OR REPLACE PROCEDURE ECOMMERCE.RAW.SAFE_DIVIDE_DEMO(numerator NUMBER, denominator NUMBER)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    result_val FLOAT;
    division_by_zero EXCEPTION (-20001, 'Division by zero attempted');
BEGIN
    IF (denominator = 0) THEN
        RAISE division_by_zero;
    END IF;

    result_val := numerator / denominator;
    RETURN 'Result: ' || result_val;
EXCEPTION
    WHEN division_by_zero THEN
        INSERT INTO ECOMMERCE.RAW.PROCEDURE_ERROR_LOG (error_message)
        VALUES ('Division by zero attempted');
        RETURN 'Error handled: division by zero';
    WHEN OTHER THEN
        INSERT INTO ECOMMERCE.RAW.PROCEDURE_ERROR_LOG (error_message)
        VALUES (:SQLERRM);
        RETURN 'Unexpected error handled: ' || SQLERRM;
END;
$$;

CALL ECOMMERCE.RAW.SAFE_DIVIDE_DEMO(10, 2);
-- Expect: 'Result: 5'

CALL ECOMMERCE.RAW.SAFE_DIVIDE_DEMO(10, 0);
-- Expect: 'Error handled: division by zero' — NOT an unhandled error

SELECT * FROM ECOMMERCE.RAW.PROCEDURE_ERROR_LOG ORDER BY occurred_at DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Call a procedure from a Task
-- ══════════════════════════════════════════════════════════════
-- A Task's body doesn't care whether it's a MERGE or a CALL — this
-- is the same mechanism from 6.1, just pointed at a procedure.

CREATE OR REPLACE TASK ECOMMERCE.RAW.RUN_STATUS_LOG_TASK
    WAREHOUSE = WORKBOOK_WH
    SCHEDULE = '5 MINUTE'
    COMMENT = 'Goal 6.5 — calls LOG_ALL_STATUS_COUNTS on a schedule'
AS
    CALL ECOMMERCE.RAW.LOG_ALL_STATUS_COUNTS();

ALTER TASK ECOMMERCE.RAW.RUN_STATUS_LOG_TASK RESUME;

-- Wait a few minutes, then check
SELECT
    name, state, scheduled_time, completed_time, error_code
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'RUN_STATUS_LOG_TASK'))
ORDER BY scheduled_time DESC;

ALTER TASK ECOMMERCE.RAW.RUN_STATUS_LOG_TASK SUSPEND;
-- ⚠️ Background cost while resumed — suspend as soon as confirmed.

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Close the loop from 6.4 — set a Task's return value
-- from a genuinely computed business value
-- ══════════════════════════════════════════════════════════════
-- IMPORTANT CORRECTION, confirmed live (twice): SYSTEM$SET_RETURN_VALUE
-- CANNOT be called from inside a LANGUAGE SQL stored procedure at
-- all — not as a variable assignment, not even as a bare CALL
-- statement. Both fail with "Query called from a stored procedure
-- contains a function with side effects." This is Snowflake's own
-- documented restriction, confirmed against their SYSTEM$SET_RETURN_VALUE
-- reference page: the only supported patterns are (a) put the
-- scripting block directly in the TASK's own body — not wrapped in
-- a separate procedure at all — or (b) use a LANGUAGE JAVASCRIPT
-- procedure that executes the CALL as a dynamically constructed
-- separate statement via snowflake.createStatement(...).execute(),
-- rather than as a native Snowflake Scripting statement.
--
-- This sub-task uses option (a) — Snowflake's own simplest
-- documented approach (see SYSTEM$SET_RETURN_VALUE's reference page,
-- "Example 3: Use a variable to set the return value"). The
-- procedure-calling pattern from Steps 1-4 still fully applies to
-- everything else in real pipelines — this is a narrow, specific
-- exception for this one system function.

-- Standalone task graph, separate from 6.4's DAG, to demonstrate
-- this specific pattern in isolation. The ENTIRE body is a
-- Snowflake Scripting block — no separate CREATE PROCEDURE at all.

CREATE OR REPLACE TASK ECOMMERCE.RAW.CHECK_PENDING_COUNT_TASK
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6.5 — computes pending count and sets it as this task''s return value'
    SCHEDULE = '5 MINUTE'
AS
    DECLARE
        pending_count NUMBER;
        result_string VARCHAR;
    BEGIN
        pending_count := (SELECT COUNT(*) FROM ECOMMERCE.RAW.ORDERS WHERE order_status = 'pending');
        result_string := TO_VARCHAR(:pending_count);
        CALL SYSTEM$SET_RETURN_VALUE(:result_string);
    END;

CREATE OR REPLACE TASK ECOMMERCE.RAW.HIGH_PENDING_ALERT_TASK
    WAREHOUSE = WORKBOOK_WH
    COMMENT = 'Goal 6.5 — only fires if pending count exceeds a real threshold'
    AFTER ECOMMERCE.RAW.CHECK_PENDING_COUNT_TASK
    WHEN SYSTEM$GET_PREDECESSOR_RETURN_VALUE('CHECK_PENDING_COUNT_TASK')::NUMBER > 5
AS
    INSERT INTO ECOMMERCE.RAW.PENDING_ORDER_ALERTS (pending_count, note)
    SELECT
        SYSTEM$GET_PREDECESSOR_RETURN_VALUE('CHECK_PENDING_COUNT_TASK')::NUMBER,
        'threshold-based alert, computed return value (sub-task 6.5)';

SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ECOMMERCE.RAW.CHECK_PENDING_COUNT_TASK');

-- Wait a few minutes, then check both tasks
SELECT
    name, state, scheduled_time, completed_time, error_code
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('CHECK_PENDING_COUNT_TASK', 'HIGH_PENDING_ALERT_TASK')
ORDER BY scheduled_time DESC;

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Cleanup
-- ══════════════════════════════════════════════════════════════
-- Per the active-DAG rule confirmed in 6.4, suspend the root of
-- this small graph before it's considered fully wound down.

ALTER TASK ECOMMERCE.RAW.CHECK_PENDING_COUNT_TASK SUSPEND;

SHOW TASKS LIKE 'CHECK_PENDING_COUNT_TASK';
SHOW TASKS LIKE 'HIGH_PENDING_ALERT_TASK';
-- Root should show "suspended"; the child may still show "started"
-- — expected and harmless, same as confirmed in 6.4.

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
-- Your turn:
--   1. Write a procedure GET_RETURN_STATUS_COUNT(status_filter)
--      that mirrors Step 1 but queries RETURNS instead of ORDERS.
--   2. Add error handling: if status_filter doesn't match any row
--      at all, RAISE a custom exception and return a clear message
--      instead of silently returning 0.
--   3. Wire it into a scheduled Task, confirm it runs via
--      TASK_HISTORY(), then suspend the task.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
-- Q: Is a procedure's RETURN value the same thing as a Task's
--    return value from 6.4?
-- A: No — completely separate mechanisms. RETURN is what CALL
--    hands back to whoever invoked the procedure directly. A
--    Task's return value (read via SYSTEM$GET_PREDECESSOR_RETURN_VALUE)
--    only exists if something calls SYSTEM$SET_RETURN_VALUE
--    explicitly — and confirmed live, that call cannot happen
--    from inside a LANGUAGE SQL procedure at all (see Step 5).
--
-- Q: Why doesn't Step 5 use a stored procedure to set the task's
--    return value, when the rest of this sub-task is all about
--    procedures?
-- A: Confirmed live, twice: SYSTEM$SET_RETURN_VALUE cannot be
--    called from inside a LANGUAGE SQL stored procedure — neither
--    as a variable assignment nor as a bare CALL statement. Both
--    fail with "Query called from a stored procedure contains a
--    function with side effects." Snowflake's own documentation
--    confirms this: their reference example computes the value
--    and calls SYSTEM$SET_RETURN_VALUE directly inside the TASK's
--    own scripting block, with no procedure involved at all — the
--    exact pattern Step 5 follows.
--
-- Q: Why use a stored procedure instead of just writing the loop
--    logic directly as a Task's single statement?
-- A: A Task's AS body is exactly one SQL statement. Snowflake
--    Scripting's DECLARE/BEGIN/END syntax IS a single statement
--    from the parser's point of view, so a procedure (or an
--    anonymous scripting block, as Step 5 uses directly in the
--    task) is how you get loops, conditionals, or multi-step logic
--    with error handling into a Task at all.
--
-- Q: When would a JavaScript procedure actually be worth it?
-- A: Rarely for typical ELT logic — string/regex manipulation,
--    calling an external API/library not exposed as a SQL
--    function, or one specific case surfaced by Step 5's own
--    restriction: SYSTEM$SET_RETURN_VALUE CAN be called from a
--    LANGUAGE JAVASCRIPT procedure, because JavaScript executes it
--    as a separate dynamically-constructed statement
--    (snowflake.createStatement({sqlText: `CALL SYSTEM$SET_RETURN_VALUE(...)`}).execute())
--    rather than as a native scripting statement — sidestepping
--    the restriction that blocks LANGUAGE SQL procedures entirely.
--    For anything else expressible in SQL plus basic control flow,
--    Snowflake Scripting remains simpler.
--
-- Q: What happens if an exception is RAISEd but no matching WHEN
--    clause (and no WHEN OTHER) exists to catch it?
-- A: The procedure fails and the error propagates up exactly like
--    an unhandled SQL error would — to whatever called it (a Task
--    run shows FAILED with the error, a direct CALL surfaces it in
--    the worksheet). EXCEPTION handling is opt-in per procedure,
--    not automatic.
-- ══════════════════════════════════════════════════════════════
