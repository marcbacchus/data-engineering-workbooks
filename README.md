# Data Engineering Workbooks

Learn modern data engineering by building production-ready solutions—one task at a time.

**One consistent dataset. One GitHub repository. Nine workbooks.**
Free, open source, and built for practitioners.

---

## Who is this for

This series is written for practitioners — people who learn by doing, not by reading feature lists. Each workbook is structured around real outcomes, not feature tours.

**Beginners** — no prior experience with a tool is assumed within each workbook. Basic SQL familiarity is helpful for the data platform workbooks.

**Experienced engineers** — the goal-driven structure lets you jump directly to what is relevant. Every workbook covers topics that trip up even seasoned practitioners.

**Career changers and students** — the series builds a complete, demonstrable portfolio of data engineering skills backed by a public GitHub repository.

---

## The series

| # | Workbook | Focus | Status |
|---|---|---|---|
| 00 | [Git for Data Engineers](00-git/) | Version control fundamentals in a data engineering context | Complete ✅ |
| 01 | [Snowflake](01-snowflake/) | Data warehousing, pipelines, security, performance, Cortex AI | In Progress |
| 02 | [dbt](02-dbt/) | Data transformation, modelling, testing, documentation | Planned |
| 03 | [Terraform](03-terraform/) | Infrastructure as code for data platforms | Planned |
| 04 | [Azure Data Engineering](04-azure/) | Azure data services, pipelines, and cloud integration | Planned |
| 05 | [Databricks](05-databricks/) | Spark, Delta Lake, streaming, and ML pipelines | Planned |
| 06 | [AWS Data Engineering](06-aws/) | S3, Glue, Redshift, Lambda, Kinesis, and Step Functions | Planned |
| 07 | [Python for Data Engineers](07-python/) | Python applied to data engineering — not generic tutorials | Planned |
| 08 | [AI for Data Engineers](08-ai/) | LLMs in pipelines, Cortex, prompt engineering, model evaluation | Planned |

---

## The dataset

All nine workbooks use the same synthetic e-commerce dataset — customers, orders, products, suppliers, reviews, returns, and clickstream events spanning 2019–2023.

| Table | Rows | Primary use |
|---|---|---|
| customers | 100,000 | Joins, segmentation, cohort analysis |
| products | 10,000 | Catalog queries, category aggregations |
| suppliers | 1,000 | Multi-table joins, supplier analysis |
| orders | 2,000,000 | Time-series, revenue analysis, pipelines |
| order_items | 4,659,254 | Performance exercises, large table operations |
| product_reviews | 500,000 | NLP, sentiment analysis, AI functions |
| returns | 80,000 | Return rate analysis, DML exercises |
| clickstream_events | 3,000,000 | Streaming, event pipelines, ML features |

Using one dataset across all workbooks means you focus entirely on the technology — you already know the data by workbook two.

See [`dataset/SCHEMA.md`](dataset/SCHEMA.md) for full column definitions, data distributions, and sample queries.

---

## How to get started

### 1. Clone the repository

```bash
git clone git@github.com:marcbacchus/data-engineering-workbooks.git
cd data-engineering-workbooks
```

> **Git LFS required** for the three large dataset files. Install from [git-lfs.com](https://git-lfs.github.com/) then run `git lfs pull`.

### 2. Choose your starting point

**New to data engineering?** Start with [00 — Git for Data Engineers](00-git/). Every other workbook assumes basic Git knowledge.

**Already know Git?** Start with [01 — Snowflake](01-snowflake/). It is the foundation that dbt, Terraform, and the cloud workbooks build on.

**Already know Snowflake?** Jump to whichever workbook covers your next learning goal.

### 3. Follow the workbook structure

Each workbook follows the same format:

```
Goal → Sub-tasks → Step-by-step code → Practice gap → What if variations
```

Every sub-task is a single SQL, Python, or HCL file. Run it step by step. Read the output. Do the practice gap. Then commit your progress.

---

## How the workbooks connect

The series is designed so each workbook builds on the previous ones — but each is also self-contained enough to stand alone.

```
00-git          ← foundation for all version control in the series
    ↓
01-snowflake    ← data platform foundation
    ↓
02-dbt          ← transforms the data loaded in Snowflake
    ↓
03-terraform    ← provisions the Snowflake infrastructure as code
    ↓
04-azure        ← cloud pipelines feeding into Snowflake
05-databricks   ← Spark and Delta Lake alongside Snowflake
06-aws          ← AWS data services alongside Snowflake
    ↓
07-python       ← glue language across all platforms (Snowpark, PySpark, boto3)
    ↓
08-ai           ← AI applied across the full stack
```

---

## Workbook structure

Every workbook follows the same internal structure:

```
XX-workbook/
├── README.md                    ← workbook overview and goal index
├── goal-01-<name>/
│   ├── README.md                ← goal overview and sub-task index
│   ├── 01_subtask_name.sql      ← one file per sub-task
│   ├── 02_subtask_name.sql
│   └── ...
├── goal-02-<name>/
└── ...
```

Each sub-task file follows a consistent format:

```
Header block    — what, why, time, warehouse size, COF-C03 alignment
Concept         — explanation before any code
Steps           — numbered, one concept per step, explained inline
Practice gap    — your turn to extend or adapt
What if         — open questions and edge cases
```

---

## Certification alignment

| Workbook | Certification |
|---|---|
| 01 Snowflake | SnowPro Core COF-C03 |
| 02 dbt | dbt Analytics Engineering Certification |
| 03 Terraform | HashiCorp Terraform Associate |
| 04 Azure | Microsoft Azure Data Engineer Associate (DP-203) |
| 05 Databricks | Databricks Certified Data Engineer Associate |
| 06 AWS | AWS Certified Data Engineer Associate (DEA-C01) |

Each workbook includes exam preparation questions at the end of every goal — written specifically to reinforce what was just built, not generic question banks.

---

## Contributing

Found an error? Have a better explanation? Pull requests are welcome.

Please open an issue before making large changes. For typos, broken code, or missing explanations — open a PR directly.

---

## License

MIT. Use freely for learning, teaching, or building your own materials. Attribution appreciated but not required.

---

*Built for the data engineering community. No vendor sponsorship. No affiliate links. Just clean, honest technical content.*

*[github.com/marcbacchus/data-engineering-workbooks](https://github.com/marcbacchus/data-engineering-workbooks)*
