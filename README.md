# Seller-performance-data-pipeline-product-insights-SQL
![SQL](https://img.shields.io/badge/Database-MySQL-blue?logo=mysql&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Mobile%20App-lightgrey)
![Analytics](https://img.shields.io/badge/Domain-Marketplace%20Analytics-orange)
![Status](https://img.shields.io/badge/Status-Complete-brightgreen)

A end-to-end SQL analytics project that models a marketplace data pipeline covering **seller performance**, **product insights**, **mobile session behaviour**, and **return analysis** — built entirely in MySQL across 4 relational tables.

---

## 📁 Project Structure

```
├── kaufland_sql_analytics.sql   # Main SQL script (all 10 steps)
├── data/
│   ├── sellers.csv              # 500 sellers across 5 countries
│   ├── product_listings.csv     # 3,000 product listings
│   ├── sessions.csv             # 20,000 mobile app sessions
│   └── transactions.csv         # 8,000 purchase transactions
└── README.md
```

---

## 🗂️ Database Schema

Four tables with primary keys, foreign keys, and correct data types.

### `sellers`
| Column | Type | Description |
|---|---|---|
| seller_id | VARCHAR(10) | Primary key |
| seller_name | VARCHAR(50) | Seller display name |
| country | CHAR(2) | DE, PL, CZ, SK, RO |
| category | VARCHAR(30) | Primary selling category |
| joined_date | DATE | Registration date |
| is_premium | TINYINT(1) | 0 = Standard, 1 = Premium |
| avg_rating | DECIMAL(3,1) | Seller rating (0–5) |
| total_products | INT | Total catalog size |

### `product_listings`
| Column | Type | Description |
|---|---|---|
| listing_id | VARCHAR(10) | Primary key |
| seller_id | VARCHAR(10) | FK → sellers |
| category | VARCHAR(30) | Beauty, Electronics, Fashion, Sports, Home & Garden |
| product_name | VARCHAR(50) | Product display name |
| price_eur | DECIMAL(10,2) | Listed price in EUR |
| stock_qty | INT | Available stock units |
| is_active | TINYINT(1) | 1 = active listing |
| listed_date | DATE | Date product was listed |

### `sessions`
| Column | Type | Description |
|---|---|---|
| session_id | VARCHAR(10) | Primary key |
| user_id | VARCHAR(10) | App user identifier |
| listing_id | VARCHAR(10) | Listing viewed |
| seller_id | VARCHAR(10) | Seller page visited |
| session_date | DATE | Session date |
| device | VARCHAR(10) | Android or iOS |
| country | CHAR(2) | User's country |
| page_views | INT | Pages viewed per session |
| session_dur_sec | INT | Session duration in seconds |
| bounced | TINYINT(1) | 1 = bounced session |

### `transactions`
| Column | Type | Description |
|---|---|---|
| transaction_id | VARCHAR(10) | Primary key |
| session_id | VARCHAR(10) | FK → sessions |
| seller_id | VARCHAR(10) | FK → sellers |
| listing_id | VARCHAR(10) | FK → product_listings |
| user_id | VARCHAR(10) | Buyer identifier |
| txn_date | DATE | Transaction date |
| country | CHAR(2) | Buyer's country |
| device | VARCHAR(10) | Android or iOS |
| quantity | INT | Units purchased |
| unit_price_eur | DECIMAL(10,2) | Price per unit |
| gmv_eur | DECIMAL(12,2) | Gross Merchandise Value |
| is_returned | TINYINT(1) | 1 = returned order |
| category | VARCHAR(30) | Product category |

---

## 🔍 Analysis Steps

### Step 1 — Database & Table Setup
DDL to create the `kaufland_analytics` database and all 4 tables with constraints and foreign keys.

### Step 2 — Data Quality Checks
Row counts, null scans, duplicate primary key detection, orphan listing detection, and GMV formula validation.

### Step 3 — Seller Performance Overview
Top 10 sellers by GMV, premium vs standard comparison, country-level KPIs, and low-performer flagging (high return rate + low rating).

### Step 4 — Product & Listing Insights
Active vs inactive listing health by category, best-selling products, dead inventory detection (zero-sale active listings), price distribution, and category GMV share.

### Step 5 — Monthly Revenue & Trend Analysis
Monthly and weekly GMV trends, month-over-month growth using `LAG()`, and category-level monthly breakdown.

### Step 6 — Mobile App & Session Analytics
Android vs iOS engagement metrics, session-to-purchase conversion rate by device, bounce rate by country, and top browsed product listings.

### Step 7 — Return & Refund Analysis
Return rates by category, monthly return trend, and sellers with the highest returned GMV impact.

### Step 8 — Seller Ranking with Window Functions
`RANK()` and `DENSE_RANK()` within country, cumulative GMV using `SUM() OVER()`, and percentile tier segmentation (Top 10% / 25% / 50%).

### Step 9 — Full Seller Scorecard
A single dashboard query joining all 4 tables to produce per-seller KPIs: listings, GMV, session engagement, bounce rate, and conversion rate in one view.

### Step 10 — Cohort & User Behaviour Analysis
Repeat buyer identification, device preferences of buyers, and cross-category purchasing behaviour.

---

## 🛠️ SQL Concepts Used

- `JOIN` (INNER, LEFT) across multiple tables
- Aggregate functions — `SUM()`, `AVG()`, `COUNT()`, `MIN()`, `MAX()`
- Window functions — `RANK()`, `DENSE_RANK()`, `LAG()`, `PERCENT_RANK()`, `SUM() OVER()`
- CTEs (`WITH` clause) for readable multi-step logic
- Conditional aggregation with `CASE WHEN`
- `NULLIF()` to safely handle division by zero
- `DATE_FORMAT()` and `YEARWEEK()` for time-series grouping
- `GROUP_CONCAT()` for multi-value string aggregation
- `HAVING` for post-aggregation filtering
- Subqueries for median approximation

---

## ▶️ How to Run

**Requirements:** MySQL 8.0+

```sql
-- 1. Run the full script
SOURCE kaufland_sql_analytics.sql;

-- 2. Or import CSVs manually after creating tables (Step 1)
LOAD DATA INFILE '/path/to/sellers.csv'
INTO TABLE sellers
FIELDS TERMINATED BY ','
IGNORE 1 ROWS;
```

> You can also use **MySQL Workbench** → Table Data Import Wizard to load the CSVs into each table after running Step 1.

---

## 📊 Key Metrics Produced

| Metric | Description |
|---|---|
| **GMV** | Gross Merchandise Value per seller / category / month |
| **Return Rate %** | Returned orders / total orders |
| **Conversion Rate %** | Sessions that resulted in a purchase |
| **Bounce Rate %** | Sessions with no further action |
| **Avg Order Value** | GMV / number of orders |
| **MoM Growth %** | Month-over-month GMV change |
| **Seller Percentile** | Top 10% / 25% / 50% tier by GMV |

---

## 🗺️ Countries Covered

| Code | Country |
|---|---|
| DE | Germany |
| PL | Poland |
| CZ | Czech Republic |
| SK | Slovakia |
| RO | Romania |

---

## 📦 Dataset Summary

| Table | Rows |
|---|---|
| sellers | 500 |
| product_listings | 3,000 |
| sessions | 20,000 |
| transactions | 8,000 |
