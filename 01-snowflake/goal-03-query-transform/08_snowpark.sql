-- ══════════════════════════════════════════════════════════════
-- SNOWFLAKE ENGINEERING WORKBOOK
-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks
-- Goal 3  : Query and Transform Data
-- Sub-task 3.8 : Snowpark Python intro
-- ──────────────────────────────────────────────────────────────
-- Time to complete : ~35 minutes
-- Warehouse size   : X-Small (WORKBOOK_WH)
-- Database         : ECOMMERCE
-- Run in           : Snowsight Notebook (Python cells)
--                    NOT a SQL worksheet
-- Prerequisites    : 07_udfs.sql completed
--                    Python familiarity helpful but not required
-- COF-C03 domain   : Domain 4.0 — Performance Optimization, Querying, and Transformation (21%)
-- ══════════════════════════════════════════════════════════════
--
-- WHAT YOU ARE DOING AND WHY
--   Everything in Goals 1, 2, and 3 so far has been SQL.
--   SQL is the right tool for 80% of data engineering work.
--   But sometimes you need Python — complex business logic,
--   ML preprocessing, API calls, file parsing, or simply
--   working with libraries that have no SQL equivalent.
--
--   Snowpark lets you write Python (and Java/Scala) that runs
--   INSIDE Snowflake — your code executes on warehouse compute,
--   your data never leaves the platform, and you get the full
--   Python ecosystem without managing servers or clusters.
--
--   This sub-task introduces Snowpark Python fundamentals:
--   connecting, reading data as DataFrames, transforming,
--   writing back to Snowflake, and building a simple pipeline.
--
-- ══════════════════════════════════════════════════════════════
-- HOW TO RUN THIS SUB-TASK
-- ══════════════════════════════════════════════════════════════
--
-- This sub-task uses Snowsight Notebooks — NOT SQL worksheets.
-- Notebooks support both SQL and Python cells in the same file.
--
-- CREATE A NOTEBOOK:
--   Snowsight → Projects → Workspaces → open your
--   'goal-3' folder → 'Goal 03 — Query and Transform'
--   folder → [+] → Notebook
--   Name it: 08_Snowpark Intro  (extendion: ipynb)
--   Click 'Connect'

 
--
-- HOW TO USE THIS NOTEBOOK:
--   Each step below is labelled [SQL CELL] or [PYTHON CELL]
--
--   To add a SQL cell:    click [+ SQL] in the notebook toolbar
--   To add a Python cell: click [+ Python] in the notebook toolbar
--
--   Paste the code block into the appropriate cell type.
--   Run each cell with Shift + Enter or the ▶ button.
--   Run All  → runs every cell top to bottom
--
--   CELL ORDER IN YOUR NOTEBOOK:
--   Cell 1: [SQL CELL]    — USE statements (CONTEXT setup)
--   Cell 2: [PYTHON CELL] — Step 1: session setup
--   Cell 3: [PYTHON CELL] — Step 2: read data
--   ... and so on
--
--   The /* */ wrappers in this file are just to keep the code
--   readable in a SQL file. Remove them when pasting into cells.
--
-- ══════════════════════════════════════════════════════════════
-- CONCEPT: WHAT IS SNOWPARK?
-- ══════════════════════════════════════════════════════════════
--
-- Snowpark is Snowflake's developer framework for Python, Java,
-- and Scala. It provides a DataFrame API — similar to pandas or
-- PySpark — but execution happens INSIDE Snowflake.
--
-- KEY DIFFERENCES FROM PANDAS:
--
--   pandas DataFrame:
--   · Data is pulled to your local machine
--   · Transformations run on your laptop CPU/RAM
--   · Limited by your machine's memory
--   · Must push results back to Snowflake separately
--
--   Snowpark DataFrame:
--   · Data stays in Snowflake
--   · Transformations run on warehouse compute (lazy evaluation)
--   · Scales to any data size your warehouse supports
--   · Results written directly to Snowflake tables
--   · No data movement — no security risk, no egress cost
--
-- LAZY EVALUATION:
--   Snowpark DataFrames are lazy — building a DataFrame does not
--   execute anything. SQL is only generated and executed when you
--   call an action: .collect(), .show(), .count(), .write.
--   This means you can chain many transformations cheaply.
--
-- WHEN TO USE SNOWPARK vs SQL:
--   Use SQL for:    standard transformations, aggregations, joins
--   Use Snowpark for: complex Python logic, ML preprocessing,
--                     iterative algorithms, custom libraries,
--                     operations that need Python control flow
--
-- Oracle equivalent:
--   No direct equivalent. The closest is Oracle's embedded Java
--   (OJVM) but it is far less accessible. Snowpark is significantly
--   easier to use and more powerful than anything Oracle offers
--   for embedded language processing.

-- ── BEFORE YOU START: Connect the notebook kernel ────────────
-- In the notebook header click [Connect] → [Connect kernel]
-- Select: NOTEBOOK_SERVICE (Runtime v2.5 | CPU | Python 3.12)
-- Wait for the green dot confirming the kernel is connected.
-- Then run the first SQL cell (USE statements) before any Python.
-- ─────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- STEP 0: SETUP Context
-- ══════════════════════════════════════════════════════════════
-- ── First cell in the notebook — always SQL ───────────────────
-- Add this as the FIRST cell before any Python cells.
-- Sets the session context for the entire notebook.
--
-- [SQL CELL]
/*
   USE ROLE ACCOUNTADMIN;
   GRANT CREATE TABLE ON SCHEMA ECOMMERCE.RAW TO ROLE SYSADMIN; --Used in step 6
   GRANT CREATE STAGE ON SCHEMA ECOMMERCE.RAW TO ROLE SYSADMIN; --Used in step 6
   GRANT CREATE FUNCTION ON SCHEMA ECOMMERCE.RAW TO ROLE SYSADMIN; --Used in step 7
   USE ROLE SYSADMIN;
   USE WAREHOUSE WORKBOOK_WH;
   USE DATABASE ECOMMERCE;
   USE SCHEMA RAW;
*/
--
-- ══════════════════════════════════════════════════════════════
-- STEP 1: Set up the Snowpark session
-- ══════════════════════════════════════════════════════════════
-- [PYTHON CELL]
-- In a Snowsight Notebook the session is pre-created for you.
-- You just import the session object and you are connected.

/*
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark import functions as F
from snowflake.snowpark.types import *
import pandas as pd

# Get the active session — pre-configured in Snowsight Notebooks
session = get_active_session()

# Confirm connection
print(f"Connected to: {session.get_current_account()}")
print(f"Database:     {session.get_current_database()}")
print(f"Schema:       {session.get_current_schema()}")
print(f"Warehouse:    {session.get_current_warehouse()}")
print(f"Role:         {session.get_current_role()}")
*/

-- ══════════════════════════════════════════════════════════════
-- STEP 2: Read data as a Snowpark DataFrame
-- ══════════════════════════════════════════════════════════════
-- [PYTHON CELL]
-- session.table() creates a DataFrame from a Snowflake table.
-- No data is fetched yet — this is lazy.
 
/*
# Create a DataFrame — lazy, no data fetched yet
orders_df = session.table("ECOMMERCE.RAW.ORDERS")

# .show() fetches and displays the first N rows
# This IS an action — it executes SQL
orders_df.show(5)

# Check the schema
orders_df.schema
*/

-- [PYTHON CELL]
-- Reading with filters — still lazy until .show() or .collect()

/*
# Filter to delivered orders
delivered_df = session.table("ECOMMERCE.RAW.ORDERS").filter(
    F.col("ORDER_STATUS") == "delivered"
)

# Count — this is an action, triggers execution
print(f"Delivered orders: {delivered_df.count():,}")

# Column names in Snowpark are UPPERCASE by default
# Use F.col("COLUMN_NAME") or just "COLUMN_NAME" in many contexts
*/

-- ══════════════════════════════════════════════════════════════
-- STEP 3: DataFrame transformations
-- ══════════════════════════════════════════════════════════════
-- [PYTHON CELL]
-- Chain transformations — all lazy until an action is called.
-- Snowpark translates your Python into SQL and runs it on Snowflake.

/*
from snowflake.snowpark import functions as F

# Read tables
orders_df   = session.table("ECOMMERCE.RAW.ORDERS")
customers_df = session.table("ECOMMERCE.RAW.CUSTOMERS")
items_df    = session.table("ECOMMERCE.RAW.ORDER_ITEMS")

# Chain transformations
result_df = (
    orders_df
    # Filter
    .filter(F.col("ORDER_STATUS") == "delivered")
    # Join with customers
    .join(
        customers_df.select("CUSTOMER_ID", "FIRST_NAME", "LAST_NAME", "COUNTRY"),
        on="CUSTOMER_ID",
        how="inner"
    )
    # Add derived column — full name
    .with_column(
        "CUSTOMER_NAME",
        F.concat(F.col("FIRST_NAME"), F.lit(" "), F.col("LAST_NAME"))
    )
    # Select only needed columns
    .select(
        "ORDER_ID",
        "CUSTOMER_NAME",
        "COUNTRY",
        "ORDER_TOTAL",
        "CREATED_AT"
    )
    # Sort by order total descending
    .sort(F.col("ORDER_TOTAL").desc())
)

# Show the result — this triggers execution
result_df.show(10)

# See what SQL Snowpark generated
print(result_df.queries["queries"][0])
# The .queries property shows the SQL Snowpark built
# Use this to understand and debug your DataFrame operations
*/

-- ══════════════════════════════════════════════════════════════
-- STEP 4: Aggregation with Snowpark
-- ══════════════════════════════════════════════════════════════
-- [PYTHON CELL]
-- .group_by() and .agg() map to GROUP BY and aggregates in SQL.

/*
from snowflake.snowpark import functions as F

orders_df = session.table("ECOMMERCE.RAW.ORDERS")
items_df  = session.table("ECOMMERCE.RAW.ORDER_ITEMS")
products_df = session.table("ECOMMERCE.RAW.PRODUCTS")

# Revenue by category — Snowpark equivalent of a GROUP BY query
category_revenue = (
    items_df
    .join(products_df.select("PRODUCT_ID", "CATEGORY"), on="PRODUCT_ID")
    .join(
        orders_df.select("ORDER_ID", "ORDER_STATUS").filter(
            F.col("ORDER_STATUS") == "delivered"
        ),
        on="ORDER_ID"
    )
    .group_by("CATEGORY")
    .agg(
        F.count(F.col("ORDER_ITEM_ID")).alias("ITEMS_SOLD"),
        F.sum(F.col("LINE_TOTAL")).alias("TOTAL_REVENUE"),
        F.avg(F.col("LINE_TOTAL")).alias("AVG_LINE_VALUE")
    )
    .sort(F.col("TOTAL_REVENUE").desc())
)

category_revenue.show(10)
*/

-- ══════════════════════════════════════════════════════════════
-- STEP 5: Convert between Snowpark and pandas
-- ══════════════════════════════════════════════════════════════
-- [PYTHON CELL]
-- Sometimes you need pandas for plotting, ML, or library compatibility.
-- Snowpark makes converting easy — but be careful with large datasets.

/*
# Snowpark DataFrame → pandas DataFrame
# WARNING: this pulls ALL data to the notebook's memory
# Only do this on small result sets

small_result = (
    session.table("ECOMMERCE.RAW.PRODUCTS")
    .filter(F.col("IS_ACTIVE") == True)
    .select("PRODUCT_NAME", "CATEGORY", "UNIT_PRICE", "COST_PRICE")
    .limit(1000)                # ALWAYS limit before converting to pandas
)

pandas_df = small_result.to_pandas()

print(f"Type: {type(pandas_df)}")
print(f"Shape: {pandas_df.shape}")
print(pandas_df.head())

# pandas → Snowpark DataFrame
# Useful for uploading a pandas result back to Snowflake
snowpark_df = session.create_dataframe(pandas_df)
snowpark_df.show(5)
*/

-- ══════════════════════════════════════════════════════════════
-- STEP 6: Write results back to Snowflake
-- ══════════════════════════════════════════════════════════════
-- [PYTHON CELL]
-- .write.save_as_table() writes a DataFrame to a Snowflake table.
-- This is how Snowpark pipelines persist their results.

/*
from snowflake.snowpark import functions as F

# Build a product margin summary
margin_summary = (
    session.table("ECOMMERCE.RAW.PRODUCTS")
    .filter(F.col("IS_ACTIVE") == True)
    .with_column(
        "MARGIN_PCT",
        F.round(
            (F.col("UNIT_PRICE") - F.col("COST_PRICE"))
            / F.col("UNIT_PRICE") * 100,
            2
        )
    )
    .with_column(
        "MARGIN_TIER",
        F.when(F.col("MARGIN_PCT") >= 50, F.lit("high"))
         .when(F.col("MARGIN_PCT") >= 30, F.lit("medium"))
         .otherwise(F.lit("low"))
    )
    .select(
        "PRODUCT_ID",
        "PRODUCT_NAME",
        "CATEGORY",
        "UNIT_PRICE",
        "COST_PRICE",
        "MARGIN_PCT",
        "MARGIN_TIER"
    )
)

# Write to a new table
# Requires CREATE TABLE privs (set in Step 0)
margin_summary.write.save_as_table(
    "ECOMMERCE.RAW.PRODUCT_MARGIN_SUMMARY",
    mode="overwrite"        # overwrite = CREATE OR REPLACE
                            # append    = INSERT INTO
                            # errorifexists = fail if table exists
)

print("Table written successfully")

# Verify with SQL
session.sql("SELECT COUNT(*) AS row_count FROM ECOMMERCE.RAW.PRODUCT_MARGIN_SUMMARY").show()
session.sql("SELECT * FROM ECOMMERCE.RAW.PRODUCT_MARGIN_SUMMARY LIMIT 5").show()
*/

-- ══════════════════════════════════════════════════════════════
-- STEP 7: Python UDF via Snowpark
-- ══════════════════════════════════════════════════════════════
-- [PYTHON CELL]
-- Register a Python function as a Snowflake UDF using @udf decorator.
-- The function runs inside Snowflake — not on your local machine.

/*
from snowflake.snowpark.functions import udf
from snowflake.snowpark.types import FloatType, IntegerType, StringType

# Define and register a Python UDF
@udf(
    name="calculate_discount_tier",
    is_permanent=True,
    stage_location="@ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE",
    replace=True,
    return_type=StringType(),
    input_types=[FloatType()]
)
def calculate_discount_tier(discount: float) -> str:
    """Classify a discount percentage into a tier."""
    if discount is None:
        return "no_discount"
    elif discount >= 0.3:
        return "heavy_discount"
    elif discount >= 0.15:
        return "moderate_discount"
    elif discount > 0:
        return "light_discount"
    else:
        return "no_discount"

# Test in SQL — the UDF is now a Snowflake object
session.sql("""
    SELECT
        order_item_id,
        discount,
        ECOMMERCE.RAW.calculate_discount_tier(discount) AS discount_tier
    FROM ECOMMERCE.RAW.ORDER_ITEMS
    LIMIT 10
""").show()
*/

-- ══════════════════════════════════════════════════════════════
-- STEP 8: Disconnect the notebook kernel when done
-- ══════════════════════════════════════════════════════════════
-- Always disconnect when you are finished to avoid idle
-- compute charges on the NOTEBOOK_SERVICE.
--
-- Click [Connect] dropdown in the notebook header
--     → [Restart kernel] to clear variables first (optional)
--     → then close the notebook
--
-- OR click [Connect] → the kernel will show as disconnected
-- after the idle timeout (24 hours by default).
-- Set a shorter idle timeout to avoid unexpected charges:
-- Snowsight → Admin → Notebooks → Idle timeout setting.
-- ══════════════════════════════════════════════════════════════
-- 
-- ══════════════════════════════════════════════════════════════
-- STEP 9: Cleanup
-- ══════════════════════════════════════════════════════════════
-- [SQL CELL] — run in a SQL cell in the notebook

DROP TABLE IF EXISTS ECOMMERCE.RAW.PRODUCT_MARGIN_SUMMARY;
DROP FUNCTION IF EXISTS ECOMMERCE.RAW.calculate_discount_tier(FLOAT);

-- Verify
SHOW TABLES IN SCHEMA ECOMMERCE.RAW; --10 tables
SHOW USER FUNCTIONS IN SCHEMA ECOMMERCE.RAW; --No results

-- ══════════════════════════════════════════════════════════════
-- PRACTICE GAP
-- ══════════════════════════════════════════════════════════════
--
-- 1. Using Snowpark DataFrames, build a customer RFM summary table:
--    · Recency: days since last order
--    · Frequency: total number of orders
--    · Monetary: total spend
--    Write the result to ECOMMERCE.RAW.CUSTOMER_RFM
--    Then query it with SQL to find your top 10 customers
--    by all three dimensions combined.
--
-- 2. Convert the category revenue DataFrame from Step 4
--    to a pandas DataFrame and calculate the coefficient
--    of variation (std/mean) for TOTAL_REVENUE.
--    Which category has the most consistent revenue?
--    Which has the most variable?
--
-- 3. Register a Python UDF called sentiment_score_simple
--    that takes a review_text string and returns:
--    · 1.0 if the text contains any positive words
--      (great, excellent, love, perfect, amazing)
--    · -1.0 if it contains any negative words
--      (terrible, awful, broken, waste, disappointed)
--    · 0.0 otherwise
--    Apply it to PRODUCT_REVIEWS and compare results
--    to the numeric rating column.

-- ══════════════════════════════════════════════════════════════
-- WHAT IF
-- ══════════════════════════════════════════════════════════════
--
-- Q: What if I need to use a Python library that is not
--    pre-installed in Snowflake?
-- A: Snowflake has a large set of pre-installed packages
--    (numpy, pandas, scikit-learn, etc.). For custom packages
--    use the Anaconda channel in Snowsight Notebooks:
--    Packages → search for the package → Add.
--    For packages not in Anaconda, upload them as a stage file
--    and reference them in your UDF definition.
--
-- Q: What is the difference between Snowpark DataFrames
--    and pandas DataFrames in terms of memory?
-- A: Snowpark DataFrames are pointers to data in Snowflake —
--    they use almost no local memory regardless of table size.
--    pandas DataFrames pull data to your notebook's RAM.
--    A 1 billion row Snowpark DataFrame is just a query plan.
--    A 1 billion row pandas DataFrame crashes your notebook.
--    Always filter and limit before .to_pandas().
--
-- Q: What if .queries shows unexpected SQL?
-- A: This is a great debugging tool. If Snowpark generates
--    inefficient SQL, you can see exactly what it produced.
--    Common issues: extra joins from column name ambiguity,
--    unnecessary subqueries, missing filter pushdown.
--    Sometimes it is faster to write the SQL directly and
--    use session.sql() instead of the DataFrame API.
--
-- Q: Can Snowpark replace dbt for transformations?
-- A: They serve different purposes. dbt excels at SQL
--    transformations with lineage, testing, and documentation.
--    Snowpark excels at Python-native logic that SQL cannot
--    express. In practice: use dbt for SQL transformations,
--    use Snowpark when you genuinely need Python.
--    Workbook 02 (dbt) covers this in depth.
--
-- Q: What is the Oracle equivalent of Snowpark?
-- A: No direct equivalent. Oracle embedded Java (OJVM) is
--    conceptually similar — running JVM code inside the database.
--    But Snowpark is dramatically simpler to use, supports
--    modern Python, and has a full DataFrame API.
--    Most Oracle shops call external Python scripts separately —
--    Snowpark eliminates that architecture complexity entirely.
