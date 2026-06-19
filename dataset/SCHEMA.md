# E-Commerce Dataset — Schema Reference
**Workbook Series:** Data & Cloud Engineering (Snowflake → dbt → Terraform → Azure → Databricks)  
**Dataset version:** 1.0  
**Generated:** 2024 (static, reproducible — seed: 42)  
**Date range:** 2019-01-01 to 2023-12-31  
**Total rows:** 10,350,254  

---

## Overview

A synthetic but realistic e-commerce dataset designed for use across all five workbooks in this series. The schema deliberately supports every major teaching scenario across platforms:

| Need | Table(s) |
|---|---|
| Relational joins (SQL fundamentals) | customers, orders, order_items, products, suppliers |
| Aggregations and window functions | orders, order_items, product_reviews |
| Text / NLP (Cortex, ML) | product_reviews.review_text |
| Time-series and seasonality | orders.created_at, clickstream_events.created_at |
| Streaming / event-driven pipelines | clickstream_events |
| Incremental loads (CDC, Streams) | orders, order_items (status changes) |
| Performance tuning (large table) | order_items (4.6M rows), clickstream_events (3M rows) |
| Delta Lake / Iceberg (Databricks) | orders, clickstream_events |
| Semi-structured / JSON | product_reviews (text), clickstream_events (device metadata) |

---

## Entity Relationship

```
suppliers (1) ──────────< products (M)
                               │
                               │ (M)
customers (1) ──────────< orders (M) >──────────< order_items (M) >──── products
                               │
                    ┌──────────┴──────────┐
                    │                     │
              product_reviews          returns
                    │                     │
               customers              customers
                    │
           clickstream_events ──── customers (optional, ~17% anonymous)
                             └──── products (for product-related events)
```

---

## Table Definitions

### suppliers
**Rows:** 1,000  
**Description:** Product suppliers / vendors. One supplier can supply many products.

| Column | Type | Description | Example |
|---|---|---|---|
| supplier_id | INTEGER | Primary key | 1 |
| supplier_name | VARCHAR | Company name | Rodriguez, Figueroa and Sanchez |
| contact_name | VARCHAR | Primary contact | Pamela Key |
| contact_email | VARCHAR | Contact email | afigueroa@roberts-shaffer.biz |
| phone | VARCHAR | Phone number | 310.221.3125x12931 |
| country | VARCHAR | Country of operation | United Kingdom |
| region | VARCHAR | Derived geographic region | Europe |
| is_active | BOOLEAN | Whether supplier is currently active | TRUE |
| created_at | TIMESTAMP | When supplier was onboarded | 2021-10-21 09:31:03 |

**Regions:** North America, Europe, Asia Pacific, Latin America, South Asia  
**Active split:** 92% active, 8% inactive  

---

### products
**Rows:** 10,000  
**Description:** Product catalog. Each product belongs to one category and is supplied by one supplier.

| Column | Type | Description | Example |
|---|---|---|---|
| product_id | INTEGER | Primary key | 42 |
| product_name | VARCHAR | Product name | Classic Books Collection 4151 |
| category | VARCHAR | Top-level category | Books |
| subcategory | VARCHAR | Sub-level category | Science and Tech |
| supplier_id | INTEGER | FK → suppliers | 880 |
| unit_price | FLOAT | Selling price (USD) | 25.11 |
| cost_price | FLOAT | Cost to company (USD) | 15.50 |
| weight_kg | FLOAT | Physical weight in kg | 24.58 |
| is_active | BOOLEAN | Whether product is listed | TRUE |
| created_at | TIMESTAMP | Product listing date | 2021-05-26 23:59:50 |

**Categories (10):** Electronics, Clothing, Home & Garden, Sports & Outdoors, Books,
Toys & Games, Beauty & Personal Care, Automotive, Food & Grocery, Office Supplies  
**Price range:** $1.99 – $4,999.99  
**Margin:** 35–65% gross margin (cost_price = 35–65% of unit_price)  
**Active split:** 88% active, 12% inactive  

---

### customers
**Rows:** 100,000  
**Description:** Registered customer accounts. Spans 15 countries with US-heavy weighting.

| Column | Type | Description | Example |
|---|---|---|---|
| customer_id | INTEGER | Primary key | 1 |
| first_name | VARCHAR | First name | Katherine |
| last_name | VARCHAR | Last name | Christian |
| email | VARCHAR | Email address (unique) | user0@yahoo.com |
| phone | VARCHAR | Phone number | (441)618-6328x252 |
| country | VARCHAR | Country | Germany |
| region | VARCHAR | Geographic region | Europe |
| city | VARCHAR | City | Lake Hannahbury |
| postal_code | VARCHAR | Postal / ZIP code | 63298 |
| segment | VARCHAR | Customer segment | enterprise |
| is_active | BOOLEAN | Whether account is active | TRUE |
| created_at | TIMESTAMP | Account registration date | 2023-07-18 18:29:37 |

**Segments:** consumer (70%), business (22%), enterprise (8%)  
**Countries:** United States (35%), United Kingdom (10%), Canada (8%), Australia (7%), Germany (6%), others  
**Active split:** 85% active, 15% inactive  

---

### orders
**Rows:** 2,000,000  
**Description:** Customer orders. Core transaction table. Includes seasonal growth pattern across 2019–2023.

| Column | Type | Description | Example |
|---|---|---|---|
| order_id | INTEGER | Primary key | 1 |
| customer_id | INTEGER | FK → customers | 67633 |
| order_status | VARCHAR | Current order status | shipped |
| payment_method | VARCHAR | How the order was paid | credit_card |
| shipping_method | VARCHAR | Delivery method selected | express |
| shipping_country | VARCHAR | Destination country | Canada |
| shipping_region | VARCHAR | Destination region | North America |
| order_total | FLOAT | Total order value (USD) | 96.91 |
| shipping_date | DATE | Date item was shipped (NULL if not shipped) | 2022-07-19 |
| delivery_date | DATE | Date item was delivered (NULL if not delivered) | NULL |
| created_at | TIMESTAMP | Order placement timestamp | 2022-07-14 08:14:40 |

**Order statuses:** delivered (76%), shipped (10%), cancelled (5%), returned (4%), confirmed (3%), placed (2%)  
**Payment methods:** credit_card (40%), debit_card (20%), paypal (18%), apple_pay (10%), google_pay (8%), bank_transfer (4%)  
**Shipping methods:** standard (55%), express (28%), next_day (12%), pickup (5%)  
**Seasonality:** Q4 (Oct–Dec) accounts for ~35% of volume; year-over-year growth from 2019→2023  

**Good for:** time-series analysis, cohort analysis, revenue aggregation, order funnel analysis  
**Workbook use:** Cortex — order_notes column (15% of rows have free-text notes) for NLP exercises  

---

### order_items
**Rows:** 4,659,254  
**Description:** Line items within each order. Each order has 1–6 items. Largest table in the dataset — primary target for performance exercises.

| Column | Type | Description | Example |
|---|---|---|---|
| order_item_id | INTEGER | Primary key | 1 |
| order_id | INTEGER | FK → orders | 1 |
| product_id | INTEGER | FK → products | 4193 |
| quantity | INTEGER | Units ordered | 2 |
| unit_price | FLOAT | Price at time of order (may differ from current product price) | 39.48 |
| discount | FLOAT | Discount applied (0.0, 0.05, 0.10, 0.15, or 0.20) | 0.20 |
| line_total | FLOAT | quantity × unit_price × (1 − discount) | 63.17 |

**Items per order:** 1 (35%), 2 (28%), 3 (18%), 4 (10%), 5 (6%), 6 (3%)  
**Discount distribution:** no discount (60%), 5% (15%), 10% (12%), 15% (8%), 20% (5%)  

**Good for:** JOIN performance, aggregation at scale, clustering key exercises, warehouse sizing  

---

### product_reviews
**Rows:** 500,000  
**Description:** Customer reviews on delivered orders. Each review is tied to a specific product, customer, and order. The review_text column is the primary target for Cortex AI exercises.

| Column | Type | Description | Example |
|---|---|---|---|
| review_id | INTEGER | Primary key | 1 |
| product_id | INTEGER | FK → products | 1533 |
| customer_id | INTEGER | FK → customers | 44 |
| order_id | INTEGER | FK → orders (delivered only) | 622976 |
| rating | INTEGER | Star rating 1–5 | 2 |
| review_text | VARCHAR | Written review content | Packaging was damaged and product had defects on arrival. |
| is_verified | BOOLEAN | Whether purchase is verified | TRUE |
| helpful_votes | INTEGER | Community helpful votes (Poisson distributed) | 4 |
| created_at | TIMESTAMP | Review submission timestamp | 2021-04-02 21:26:12 |

**Rating distribution:** 5★ (40%), 4★ (32%), 3★ (15%), 2★ (8%), 1★ (5%)  
**Verified split:** 88% verified, 12% unverified  
**Only from delivered orders** — enforced during generation  

**Good for:** Cortex SENTIMENT(), SUMMARIZE(), COMPLETE(); average rating aggregations; NLP pipelines  

---

### returns
**Rows:** 80,000  
**Description:** Return requests on delivered or returned orders. Each return ties back to a specific order line item.

| Column | Type | Description | Example |
|---|---|---|---|
| return_id | INTEGER | Primary key | 1 |
| order_id | INTEGER | FK → orders | 1154525 |
| order_item_id | INTEGER | FK → order_items | 2689100 |
| product_id | INTEGER | FK → products | 5455 |
| customer_id | INTEGER | FK → customers | 79866 |
| return_reason | VARCHAR | Reason for return | Arrived too late |
| return_status | VARCHAR | Processing status | refunded |
| refund_amount | FLOAT | Amount refunded (USD) | 138.51 |
| created_at | TIMESTAMP | Return request timestamp | 2021-07-14 11:36:53 |

**Return reasons:** Defective or damaged (22%), Not as described (18%), Changed my mind (18%), Wrong item received (12%), Item no longer needed (10%), Better price found elsewhere (8%), Arrived too late (7%), Quality not as expected (5%)  
**Return statuses:** refunded (65%), received (15%), approved (10%), requested (5%), rejected (5%)  
**Refund amount:** 85–100% of original line_total  

**Good for:** return rate analysis, reason categorisation, join exercises across 4 tables  

---

### clickstream_events
**Rows:** 3,000,000  
**Description:** Web/app behavioural events. ~17% of events are anonymous (no customer_id). Primary table for streaming, event-driven pipeline, and Databricks exercises.

| Column | Type | Description | Example |
|---|---|---|---|
| event_id | INTEGER | Primary key | 1 |
| session_id | VARCHAR | Browser/app session identifier | s000244726 |
| customer_id | INTEGER | FK → customers (NULL if anonymous) | NULL |
| event_type | VARCHAR | Type of event | add_to_cart |
| product_id | INTEGER | FK → products (NULL for non-product events) | 9220 |
| device_type | VARCHAR | Device category | mobile |
| browser | VARCHAR | Browser name | Chrome |
| operating_system | VARCHAR | OS name | iOS |
| session_duration_seconds | INTEGER | Seconds in session (1–3600, exponential dist.) | 376 |
| created_at | TIMESTAMP | Event timestamp | 2021-05-21 02:38:04 |

**Event types:** page_view (35%), product_view (25%), add_to_cart (15%), search (8%), checkout_start (6%), remove_from_cart (5%), purchase (4%), wishlist_add (2%)  
**Devices:** desktop (45%), mobile (42%), tablet (13%)  
**Browsers:** Chrome (52%), Safari (28%), Firefox (8%), Edge (7%), Samsung Internet (5%)  
**Anonymous sessions:** ~17% of events have NULL customer_id  

**Good for:** streaming ingestion (Azure Event Hubs, Databricks Auto Loader), funnel analysis, session analysis, device/browser reporting, Delta Lake exercises  

---

## Key Relationships for Workbook Exercises

```sql
-- Core revenue query (works in all workbooks)
SELECT
    c.country,
    p.category,
    DATE_TRUNC('month', o.created_at) AS order_month,
    SUM(oi.line_total)                AS revenue,
    COUNT(DISTINCT o.order_id)        AS orders,
    COUNT(DISTINCT o.customer_id)     AS customers
FROM orders o
JOIN customers   c  ON o.customer_id  = c.customer_id
JOIN order_items oi ON o.order_id     = oi.order_id
JOIN products    p  ON oi.product_id  = p.product_id
WHERE o.order_status = 'delivered'
GROUP BY 1, 2, 3
ORDER BY 1, 3;

-- Return rate by category
SELECT
    p.category,
    COUNT(DISTINCT oi.order_item_id)  AS total_items_sold,
    COUNT(DISTINCT r.return_id)       AS total_returns,
    ROUND(COUNT(DISTINCT r.return_id) * 100.0 /
          COUNT(DISTINCT oi.order_item_id), 2) AS return_rate_pct
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN returns r ON oi.order_item_id = r.order_item_id
GROUP BY 1
ORDER BY 4 DESC;

-- Cortex sentiment on reviews (Snowflake Goal 3)
SELECT
    p.category,
    AVG(pr.rating)                                          AS avg_rating,
    AVG(SNOWFLAKE.CORTEX.SENTIMENT(pr.review_text))        AS avg_sentiment_score,
    COUNT(*)                                                AS review_count
FROM product_reviews pr
JOIN products p ON pr.product_id = p.product_id
GROUP BY 1
ORDER BY 3 DESC;

-- Clickstream funnel (Databricks / Azure workbooks)
SELECT
    event_type,
    COUNT(*)                                    AS events,
    COUNT(DISTINCT session_id)                  AS sessions,
    COUNT(DISTINCT customer_id)                 AS unique_customers
FROM clickstream_events
WHERE created_at >= '2023-01-01'
GROUP BY 1
ORDER BY 2 DESC;
```

---

## Data Quality Notes

- **Referential integrity:** All foreign keys are valid within their respective tables
- **NULLs by design:**
  - `orders.shipping_date` — NULL for placed/confirmed/cancelled orders
  - `orders.delivery_date` — NULL for non-delivered orders
  - `clickstream_events.customer_id` — NULL for ~17% anonymous sessions
  - `clickstream_events.product_id` — NULL for non-product events (page_view, search, checkout_start, purchase)
- **Price consistency:** `order_items.unit_price` reflects price at time of order and may differ from current `products.unit_price` — intentional, mirrors real-world behavior
- **Temporal consistency:** review and return timestamps are always after their related order's delivery_date
- **Reproducibility:** All data generated with seed=42 — regenerating produces identical output

---

## File Information

| File | Rows | Size |
|---|---|---|
| suppliers.csv | 1,000 | 0.1 MB |
| products.csv | 10,000 | 1.0 MB |
| customers.csv | 100,000 | 12.7 MB |
| orders.csv | 2,000,000 | 210.8 MB |
| order_items.csv | 4,659,254 | 171.8 MB |
| product_reviews.csv | 500,000 | 53.2 MB |
| returns.csv | 80,000 | 6.6 MB |
| clickstream_events.csv | 3,000,000 | 237.7 MB |
| **TOTAL** | **10,350,254** | **693.9 MB** |

**GitHub hosting note:** Files over 100MB cannot be committed directly to GitHub.
Recommended approach:
- `suppliers.csv`, `products.csv`, `customers.csv`, `returns.csv` → commit directly (all under 100MB)
- `product_reviews.csv` → commit directly (53MB)
- `orders.csv`, `order_items.csv`, `clickstream_events.csv` → use Git LFS or host in a public S3 bucket
- Alternative: provide a generation script so readers can produce the data themselves (reproducible via seed=42)
