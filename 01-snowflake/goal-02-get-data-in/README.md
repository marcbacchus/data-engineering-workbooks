# Goal 2: Get Data In

**Workbook:** Snowflake Engineering
**Dataset:** E-Commerce (loaded in this goal)
**Estimated time:** 4–5 hours total
**Warehouse size:** X-Small throughout
**COF-C03 domains:** Domain 3.0 — Data Loading, Unloading, and Connectivity (18%)

---

## What you are doing and why

Data does not load itself. Before you can query, transform, or analyse anything in Snowflake, you need to get data in — and out. This goal covers the complete data ingestion surface: batch loading, continuous ingestion, semi-structured formats, error handling, unloading, and schema evolution.

By the end of this goal you will have:

- Loaded 10,370,254 rows across 10 tables into `ECOMMERCE.RAW`
- Loaded semi-structured data in both JSON and Parquet format
- Handled real load errors and diagnosed them using Snowflake's tools
- Automated ingestion using Snowpipe
- Exported data in CSV, JSON, and partitioned formats
- Queried staged files without loading them
- Evolved a table schema safely without downtime

---

## Prerequisites

- Goal 1 complete — `ECOMMERCE` database with `RAW`, `STAGING`, `ANALYTICS` schemas
- `WORKBOOK_WH` warehouse created
- `ECOMMERCE_RAW_STAGE` named internal stage created
- SnowSQL installed and configured (`snowsql -c workbook` works)
- Dataset files downloaded to `~/projects/data-engineering-workbooks/dataset/`

---

## Dataset files used in this goal

| File | Rows | Format | Used in |
|---|---|---|---|
| suppliers.csv | 1,000 | CSV | 2.2, 2.3 |
| products.csv | 10,000 | CSV | 2.2, 2.3 |
| customers.csv | 100,000 | CSV | 2.2, 2.3 |
| orders.csv | 2,000,000 | CSV | 2.2, 2.3 |
| order_items.csv | 4,659,254 | CSV | 2.2, 2.3 |
| product_reviews.csv | 500,000 | CSV | 2.2, 2.3 |
| returns.csv | 80,000 | CSV | 2.2, 2.3 |
| clickstream_events.csv | 3,000,000 | CSV | 2.2, 2.3 |
| product_reviews.json | 10,000 | JSON (nested) | 2.2, 2.5 |
| product_reviews.parquet | 10,000 | Parquet/Snappy | 2.2, 2.5 |

All files are in the `dataset/` folder at the root of this repository.

---

## Sub-tasks

Work through these in order. Each file builds on the previous one.

| File | Sub-task | Time | Key concepts |
|---|---|---|---|
| [00_cleanup.sql](00_cleanup.sql) | Reset Goal 2 work | 2 min | Drop tables, formats, stage files — safe to re-run |
| [01_file_formats.sql](01_file_formats.sql) | Create file format objects | ~20 min | CSV_FORMAT, JSON_FORMAT, PARQUET_FORMAT, named vs inline |
| [02_staging_files.sql](02_staging_files.sql) | Stage files for loading | ~25 min | PUT via SnowSQL, LIST, stage preview, Mac/Windows variants |
| [03_copy_into.sql](03_copy_into.sql) | Load data with COPY INTO | ~30 min | COPY INTO, load deduplication, LOAD_HISTORY, first queries |
| [04_error_handling.sql](04_error_handling.sql) | Handle load errors | ~25 min | VALIDATION_MODE, ON_ERROR options, VALIDATE(), error diagnosis |
| [05_semi_structured.sql](05_semi_structured.sql) | Semi-structured data | ~40 min | VARIANT, dot-notation, FLATTEN, JSON load, Parquet load, TO_TIMESTAMP |
| [06_snowpipe.sql](06_snowpipe.sql) | Automate with Snowpipe | ~25 min | CREATE PIPE, AUTO_INGEST, REST API, pipe monitoring, pause/resume |
| [07_unload_data.sql](07_unload_data.sql) | Unload data from Snowflake | ~20 min | COPY INTO stage, HEADER, SINGLE, partitioned exports, GET |
| [08_external_tables.sql](08_external_tables.sql) | Work with external tables | ~20 min | External table concepts, direct stage queries, METADATA$FILENAME |
| [09_schema_evolution.sql](09_schema_evolution.sql) | Manage schema evolution | ~25 min | ALTER TABLE, ADD/DROP/RENAME COLUMN, SWAP, sequences, safe DDL |
| [10_exam_prep.sql](10_exam_prep.sql) | COF-C03 exam preparation | ~35 min | 14 practice questions covering all Goal 2 topics |

---

## How to run these files

### Tools needed
- **Snowsight** — for all SQL files (Steps marked "Run in: Snowsight")
- **SnowSQL** — for PUT and GET commands (Steps marked "Run in: SnowSQL")

### Quick rule
```
PUT and GET commands  → SnowSQL
Everything else       → Snowsight
```

### Step by step
1. Open Snowsight → **Projects → Worksheets → +**
2. Name it `Goal 02 — Get Data In`
3. Copy a sub-task file into your worksheet
4. Run each step individually using **Cmd+Enter** (Mac) or **Ctrl+Enter** (Windows)
5. Read the output and comments before moving to the next step

> **Important:** Run the cleanup script (`00_cleanup.sql`) before starting if you want a fresh environment, or after completing a sub-task if you want to reset and re-run.

---

## Key objects created in this goal

```
ECOMMERCE.RAW
├── Tables (8 CSV tables)
│   ├── SUPPLIERS           (1,000 rows)
│   ├── PRODUCTS            (10,000 rows)
│   ├── CUSTOMERS           (100,000 rows)
│   ├── ORDERS              (2,000,000 rows)
│   ├── ORDER_ITEMS         (4,659,254 rows)
│   ├── PRODUCT_REVIEWS     (500,000 rows)
│   ├── RETURNS             (80,000 rows)
│   └── CLICKSTREAM_EVENTS  (3,000,000 rows)
│
├── Tables (semi-structured)
│   ├── PRODUCT_REVIEWS_JSON     (10,000 records — VARIANT column)
│   └── PRODUCT_REVIEWS_PARQUET  (10,000 rows — typed columns)
│
├── File format objects
│   ├── CSV_FORMAT
│   ├── JSON_FORMAT
│   └── PARQUET_FORMAT
│
└── Stage
    └── ECOMMERCE_RAW_STAGE  (all source files — persists for Goal 3+)
```

**Total rows loaded: 10,350,254**

---

## Scripts folder

The `scripts/` folder contains shell scripts for terminal commands that cannot run in Snowsight:

| Script | Purpose | Platform |
|---|---|---|
| `scripts/create_error_test_mac.sh` | Creates broken CSV and stages it | Mac / Linux |
| `scripts/create_error_test_windows.ps1` | Creates broken CSV and stages it | Windows |

---

## SnowSQL quick reference

SnowSQL is required for PUT (upload) and GET (download) commands.

**Connect:**
```bash
snowsql -c workbook
```

**Your prompt:**
```
MBACCHUS#WORKBOOK_WH@ECOMMERCE.RAW>
```
Pattern: `<username>#<warehouse>@<database>.<schema>`

**Upload a file (PUT):**
```sql
-- Mac / Linux
PUT file:///Users/marc/projects/data-engineering-workbooks/dataset/suppliers.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Windows
PUT file://C:/Users/YourName/projects/data-engineering-workbooks/dataset/suppliers.csv @ECOMMERCE.RAW.ECOMMERCE_RAW_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
```

**Download a file (GET):**
```sql
-- Mac / Linux
GET @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_export.csv file:///Users/marc/Downloads/;

-- Windows
GET @ECOMMERCE.RAW.ECOMMERCE_EXPORT_STAGE/orders_export.csv file://C:/Users/YourName/Downloads/;
```

---

## Real-world discoveries made during testing

These are behaviours we discovered by actually running every step — not from documentation alone:

- **PUT stores files without .gz extension** when `AUTO_COMPRESS=FALSE` — file references in COPY INTO must not include `.gz`
- **Parquet timestamps from pandas/PyArrow** are stored as microseconds since epoch — use `TO_TIMESTAMP(col::INTEGER, 6)` to convert
- **PIPE_EXECUTION_PAUSED** is the correct syntax for pausing a pipe — `ALTER PIPE ... PAUSE` does not exist
- **PARTITION BY** in COPY INTO has limited support — use subfolder paths in the stage reference instead
- **GET does not support PATTERN** — download by specific file name or stage prefix only
- **JSON unload requires OBJECT_CONSTRUCT()** — you cannot select multiple typed columns into a JSON FILE_FORMAT directly
- **Inline FILE_FORMAT syntax** in stage SELECT queries is unreliable — always use named format objects
- **Snowflake AUTOINCREMENT sequences use caching** — gaps between sessions are expected and normal

---

## COF-C03 exam coverage

| Domain | Weight | Sub-tasks |
|---|---|---|
| Data Loading, Unloading, and Connectivity | 18% | 2.1, 2.2, 2.3, 2.4, 2.6, 2.7, 2.8 |
| Performance Optimization, Querying, and Transformation | 21% | 2.5, 2.9 |

The exam prep file (`10_exam_prep.sql`) contains 14 questions covering all tested concepts from this goal.

---

## When you are done

After completing all 10 sub-tasks including exam preparation:

1. Commit your progress:
```bash
git add 01-snowflake/goal-02-get-data-in/
git commit -m "feat: complete goal-02 get data in"
git push
```

2. Move to [Goal 3: Query and Transform Data](../goal-03-query-transform/)

---

*Data Engineering Workbooks · [github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
