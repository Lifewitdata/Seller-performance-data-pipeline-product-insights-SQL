-- ============================================================
--  SELLER PERFORMANCE DATA PIPELINE & PRODUCT INSIGHTS
--  Project: SQL Product Analytics
--  Platform: Mobile App · Marketplace Analytics
--  Database: MySQL
--  Tables: sellers, product_listings, sessions, transactions
-- ============================================================


-- ============================================================
-- STEP 1: DATABASE & TABLE SETUP
--         Create schema and import all four CSV tables
-- ============================================================

CREATE DATABASE IF NOT EXISTS kaufland_analytics;
USE kaufland_analytics;

-- ── Table 1: sellers ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sellers (
    seller_id      VARCHAR(10)   PRIMARY KEY,
    seller_name    VARCHAR(50)   NOT NULL,
    country        CHAR(2)       NOT NULL,           -- DE, PL, CZ, SK, RO
    category       VARCHAR(30)   NOT NULL,
    joined_date    DATE          NOT NULL,
    is_premium     TINYINT(1)    NOT NULL DEFAULT 0, -- 0 = standard, 1 = premium
    avg_rating     DECIMAL(3,1)  NOT NULL,
    total_products INT           NOT NULL
);

-- ── Table 2: product_listings ─────────────────────────────────
CREATE TABLE IF NOT EXISTS product_listings (
    listing_id   VARCHAR(10)   PRIMARY KEY,
    seller_id    VARCHAR(10)   NOT NULL,
    category     VARCHAR(30)   NOT NULL,
    product_name VARCHAR(50)   NOT NULL,
    price_eur    DECIMAL(10,2) NOT NULL,
    stock_qty    INT           NOT NULL,
    is_active    TINYINT(1)    NOT NULL DEFAULT 1,
    listed_date  DATE          NOT NULL,
    FOREIGN KEY (seller_id) REFERENCES sellers(seller_id)
);

-- ── Table 3: sessions ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sessions (
    session_id      VARCHAR(10)  PRIMARY KEY,
    user_id         VARCHAR(10)  NOT NULL,
    listing_id      VARCHAR(10),
    seller_id       VARCHAR(10),
    session_date    DATE         NOT NULL,
    device          VARCHAR(10)  NOT NULL,           -- Android, iOS
    country         CHAR(2)      NOT NULL,
    page_views      INT          NOT NULL,
    session_dur_sec INT          NOT NULL,
    bounced         TINYINT(1)   NOT NULL DEFAULT 0  -- 1 = bounced
);

-- ── Table 4: transactions ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id VARCHAR(10)   PRIMARY KEY,
    session_id     VARCHAR(10),
    seller_id      VARCHAR(10)   NOT NULL,
    listing_id     VARCHAR(10)   NOT NULL,
    user_id        VARCHAR(10)   NOT NULL,
    txn_date       DATE          NOT NULL,
    country        CHAR(2)       NOT NULL,
    device         VARCHAR(10)   NOT NULL,
    quantity       INT           NOT NULL,
    unit_price_eur DECIMAL(10,2) NOT NULL,
    gmv_eur        DECIMAL(12,2) NOT NULL,           -- quantity * unit_price
    is_returned    TINYINT(1)    NOT NULL DEFAULT 0,
    category       VARCHAR(30)   NOT NULL
);


-- ============================================================
-- STEP 2: DATA QUALITY CHECKS
--         Validate counts, nulls, and referential integrity
-- ============================================================

-- 2a. Row counts for all tables
SELECT 'sellers'          AS table_name, COUNT(*) AS row_count FROM sellers
UNION ALL
SELECT 'product_listings',               COUNT(*)               FROM product_listings
UNION ALL
SELECT 'sessions',                       COUNT(*)               FROM sessions
UNION ALL
SELECT 'transactions',                   COUNT(*)               FROM transactions;

-- 2b. Check for duplicate primary keys in transactions
SELECT transaction_id, COUNT(*) AS cnt
FROM   transactions
GROUP  BY transaction_id
HAVING cnt > 1;

-- 2c. Check for orphan listings (seller_id not in sellers)
SELECT pl.listing_id, pl.seller_id
FROM   product_listings pl
LEFT   JOIN sellers s ON pl.seller_id = s.seller_id
WHERE  s.seller_id IS NULL;

-- 2d. Null / missing value scan on transactions
SELECT
    SUM(transaction_id  IS NULL) AS null_txn_id,
    SUM(seller_id       IS NULL) AS null_seller_id,
    SUM(listing_id      IS NULL) AS null_listing_id,
    SUM(gmv_eur         IS NULL) AS null_gmv,
    SUM(txn_date        IS NULL) AS null_date
FROM transactions;

-- 2e. Verify GMV calculation integrity (gmv should equal qty * unit_price)
SELECT COUNT(*) AS mismatched_gmv_rows
FROM   transactions
WHERE  ABS(gmv_eur - (quantity * unit_price_eur)) > 0.01;


-- ============================================================
-- STEP 3: SELLER PERFORMANCE OVERVIEW
--         Core KPIs per seller aggregated from transactions
-- ============================================================

-- 3a. Top 10 sellers by total GMV
SELECT
    s.seller_id,
    s.seller_name,
    s.country,
    s.is_premium,
    s.avg_rating,
    COUNT(t.transaction_id)           AS total_orders,
    SUM(t.quantity)                   AS units_sold,
    ROUND(SUM(t.gmv_eur), 2)          AS total_gmv_eur,
    ROUND(AVG(t.gmv_eur), 2)          AS avg_order_value_eur,
    SUM(t.is_returned)                AS total_returns,
    ROUND(
        SUM(t.is_returned) * 100.0
        / NULLIF(COUNT(t.transaction_id), 0), 2
    )                                 AS return_rate_pct
FROM   sellers s
JOIN   transactions t ON s.seller_id = t.seller_id
GROUP  BY s.seller_id, s.seller_name, s.country, s.is_premium, s.avg_rating
ORDER  BY total_gmv_eur DESC
LIMIT  10;

-- 3b. Premium vs. standard seller comparison
SELECT
    CASE WHEN s.is_premium = 1 THEN 'Premium' ELSE 'Standard' END AS seller_tier,
    COUNT(DISTINCT s.seller_id)               AS seller_count,
    ROUND(AVG(s.avg_rating), 2)               AS avg_seller_rating,
    ROUND(SUM(t.gmv_eur), 2)                  AS total_gmv_eur,
    ROUND(AVG(t.gmv_eur), 2)                  AS avg_order_value_eur,
    ROUND(
        SUM(t.is_returned) * 100.0
        / NULLIF(COUNT(t.transaction_id), 0), 2
    )                                         AS return_rate_pct
FROM   sellers s
JOIN   transactions t ON s.seller_id = t.seller_id
GROUP  BY seller_tier;

-- 3c. Seller performance by country
SELECT
    s.country,
    COUNT(DISTINCT s.seller_id)   AS active_sellers,
    ROUND(SUM(t.gmv_eur), 2)      AS total_gmv_eur,
    ROUND(AVG(t.unit_price_eur), 2) AS avg_product_price_eur,
    ROUND(AVG(s.avg_rating), 2)   AS avg_seller_rating,
    ROUND(
        SUM(t.is_returned) * 100.0
        / NULLIF(COUNT(t.transaction_id), 0), 2
    )                             AS return_rate_pct
FROM   sellers s
JOIN   transactions t ON s.seller_id = t.seller_id
GROUP  BY s.country
ORDER  BY total_gmv_eur DESC;

-- 3d. Identify low-performing sellers (high return rate AND low rating)
SELECT
    s.seller_id,
    s.seller_name,
    s.avg_rating,
    COUNT(t.transaction_id)  AS total_orders,
    ROUND(SUM(t.gmv_eur), 2) AS total_gmv_eur,
    ROUND(
        SUM(t.is_returned) * 100.0
        / NULLIF(COUNT(t.transaction_id), 0), 2
    )                        AS return_rate_pct
FROM   sellers s
JOIN   transactions t ON s.seller_id = t.seller_id
GROUP  BY s.seller_id, s.seller_name, s.avg_rating
HAVING return_rate_pct > 30
   AND s.avg_rating < 3.5
ORDER  BY return_rate_pct DESC;


-- ============================================================
-- STEP 4: PRODUCT & LISTING INSIGHTS
--         Catalog health and best/worst performing products
-- ============================================================

-- 4a. Active vs. inactive listing breakdown per category
SELECT
    category,
    COUNT(*)                             AS total_listings,
    SUM(is_active)                       AS active_listings,
    COUNT(*) - SUM(is_active)            AS inactive_listings,
    ROUND(SUM(is_active) * 100.0 / COUNT(*), 1) AS active_rate_pct,
    ROUND(AVG(price_eur), 2)             AS avg_price_eur,
    ROUND(MIN(price_eur), 2)             AS min_price_eur,
    ROUND(MAX(price_eur), 2)             AS max_price_eur
FROM   product_listings
GROUP  BY category
ORDER  BY total_listings DESC;

-- 4b. Top 10 best-selling products by GMV
SELECT
    pl.listing_id,
    pl.product_name,
    pl.category,
    pl.price_eur                          AS listed_price_eur,
    COUNT(t.transaction_id)               AS total_orders,
    SUM(t.quantity)                       AS units_sold,
    ROUND(SUM(t.gmv_eur), 2)             AS total_gmv_eur,
    ROUND(
        SUM(t.is_returned) * 100.0
        / NULLIF(COUNT(t.transaction_id), 0), 2
    )                                     AS return_rate_pct
FROM   product_listings pl
JOIN   transactions t ON pl.listing_id = t.listing_id
GROUP  BY pl.listing_id, pl.product_name, pl.category, pl.price_eur
ORDER  BY total_gmv_eur DESC
LIMIT  10;

-- 4c. Listings with zero sales (dead inventory)
SELECT
    pl.listing_id,
    pl.seller_id,
    pl.product_name,
    pl.category,
    pl.price_eur,
    pl.stock_qty,
    pl.listed_date
FROM   product_listings pl
LEFT   JOIN transactions t ON pl.listing_id = t.listing_id
WHERE  t.listing_id IS NULL
  AND  pl.is_active = 1
ORDER  BY pl.stock_qty DESC;

-- 4d. Price distribution by category (quartile view)
SELECT
    category,
    ROUND(MIN(price_eur), 2)                            AS min_price,
    ROUND(AVG(price_eur), 2)                            AS avg_price,
    ROUND(MAX(price_eur), 2)                            AS max_price,
    -- MySQL does not have a built-in MEDIAN, so approximate with subquery
    ROUND(
        (SELECT price_eur
         FROM   product_listings p2
         WHERE  p2.category = p1.category
         ORDER  BY price_eur
         LIMIT  1
         OFFSET (SELECT COUNT(*) FROM product_listings p3
                 WHERE p3.category = p1.category) / 2)
    , 2)                                                AS approx_median_price
FROM   product_listings p1
GROUP  BY category
ORDER  BY avg_price DESC;

-- 4e. Category revenue share (% of total GMV)
SELECT
    category,
    ROUND(SUM(gmv_eur), 2)                                          AS category_gmv_eur,
    ROUND(SUM(gmv_eur) * 100.0 / SUM(SUM(gmv_eur)) OVER (), 2)     AS gmv_share_pct
FROM   transactions
GROUP  BY category
ORDER  BY category_gmv_eur DESC;


-- ============================================================
-- STEP 5: MONTHLY REVENUE & TREND ANALYSIS
--         Time-series GMV, order volume, and growth tracking
-- ============================================================

-- 5a. Monthly GMV and order volume
SELECT
    DATE_FORMAT(txn_date, '%Y-%m')         AS month,
    COUNT(transaction_id)                  AS total_orders,
    SUM(quantity)                          AS units_sold,
    ROUND(SUM(gmv_eur), 2)                 AS gmv_eur,
    ROUND(AVG(gmv_eur), 2)                 AS avg_order_value_eur,
    SUM(is_returned)                       AS total_returns,
    ROUND(
        SUM(is_returned) * 100.0
        / NULLIF(COUNT(transaction_id), 0), 2
    )                                      AS return_rate_pct
FROM   transactions
GROUP  BY month
ORDER  BY month;

-- 5b. Month-over-month GMV growth using LAG()
WITH monthly_gmv AS (
    SELECT
        DATE_FORMAT(txn_date, '%Y-%m') AS month,
        ROUND(SUM(gmv_eur), 2)         AS gmv_eur
    FROM   transactions
    GROUP  BY month
)
SELECT
    month,
    gmv_eur,
    LAG(gmv_eur) OVER (ORDER BY month)  AS prev_month_gmv,
    ROUND(
        (gmv_eur - LAG(gmv_eur) OVER (ORDER BY month))
        * 100.0
        / NULLIF(LAG(gmv_eur) OVER (ORDER BY month), 0), 2
    )                                   AS mom_growth_pct
FROM   monthly_gmv
ORDER  BY month;

-- 5c. Weekly GMV trend
SELECT
    YEARWEEK(txn_date, 1)              AS year_week,
    MIN(txn_date)                      AS week_start,
    COUNT(transaction_id)              AS total_orders,
    ROUND(SUM(gmv_eur), 2)             AS weekly_gmv_eur
FROM   transactions
GROUP  BY year_week
ORDER  BY year_week;

-- 5d. Category-level monthly trend
SELECT
    DATE_FORMAT(txn_date, '%Y-%m') AS month,
    category,
    ROUND(SUM(gmv_eur), 2)          AS gmv_eur,
    COUNT(transaction_id)           AS orders
FROM   transactions
GROUP  BY month, category
ORDER  BY month, category;


-- ============================================================
-- STEP 6: MOBILE APP & SESSION ANALYTICS
--         Device split, bounce rates, and session engagement
-- ============================================================

-- 6a. Session metrics by device (Android vs iOS)
SELECT
    device,
    COUNT(session_id)                                      AS total_sessions,
    ROUND(AVG(page_views), 2)                             AS avg_page_views,
    ROUND(AVG(session_dur_sec), 2)                        AS avg_session_dur_sec,
    ROUND(AVG(session_dur_sec) / 60.0, 2)                 AS avg_session_dur_min,
    SUM(bounced)                                          AS bounced_sessions,
    ROUND(SUM(bounced) * 100.0 / COUNT(session_id), 2)   AS bounce_rate_pct
FROM   sessions
GROUP  BY device
ORDER  BY total_sessions DESC;

-- 6b. Session-to-transaction conversion rate by device
SELECT
    s.device,
    COUNT(DISTINCT s.session_id)                          AS total_sessions,
    COUNT(DISTINCT t.session_id)                          AS converting_sessions,
    ROUND(
        COUNT(DISTINCT t.session_id) * 100.0
        / NULLIF(COUNT(DISTINCT s.session_id), 0), 2
    )                                                     AS conversion_rate_pct,
    ROUND(SUM(t.gmv_eur), 2)                              AS total_gmv_eur
FROM   sessions s
LEFT   JOIN transactions t ON s.session_id = t.session_id
GROUP  BY s.device;

-- 6c. Bounce rate by country
SELECT
    country,
    COUNT(session_id)                                      AS total_sessions,
    ROUND(AVG(page_views), 2)                             AS avg_page_views,
    ROUND(AVG(session_dur_sec), 2)                        AS avg_dur_sec,
    ROUND(SUM(bounced) * 100.0 / COUNT(session_id), 2)   AS bounce_rate_pct
FROM   sessions
GROUP  BY country
ORDER  BY bounce_rate_pct ASC;

-- 6d. Sessions per listing — top browsed products
SELECT
    s.listing_id,
    pl.product_name,
    pl.category,
    COUNT(s.session_id)                AS total_sessions,
    ROUND(AVG(s.page_views), 2)        AS avg_page_views,
    ROUND(AVG(s.session_dur_sec), 2)   AS avg_session_dur_sec,
    ROUND(SUM(s.bounced) * 100.0
        / NULLIF(COUNT(s.session_id), 0), 2) AS bounce_rate_pct
FROM   sessions s
JOIN   product_listings pl ON s.listing_id = pl.listing_id
GROUP  BY s.listing_id, pl.product_name, pl.category
ORDER  BY total_sessions DESC
LIMIT  10;

-- 6e. Daily active sessions trend
SELECT
    session_date,
    COUNT(session_id)                     AS total_sessions,
    COUNT(DISTINCT user_id)               AS unique_users,
    ROUND(AVG(session_dur_sec) / 60, 2)  AS avg_dur_min
FROM   sessions
GROUP  BY session_date
ORDER  BY session_date;


-- ============================================================
-- STEP 7: RETURN & REFUND ANALYSIS
--         Identify high-return categories, products, sellers
-- ============================================================

-- 7a. Return rate by category
SELECT
    category,
    COUNT(transaction_id)         AS total_orders,
    SUM(is_returned)              AS returned_orders,
    ROUND(SUM(gmv_eur), 2)        AS total_gmv_eur,
    ROUND(
        SUM(CASE WHEN is_returned = 1 THEN gmv_eur ELSE 0 END), 2
    )                             AS returned_gmv_eur,
    ROUND(
        SUM(is_returned) * 100.0
        / NULLIF(COUNT(transaction_id), 0), 2
    )                             AS return_rate_pct
FROM   transactions
GROUP  BY category
ORDER  BY return_rate_pct DESC;

-- 7b. Monthly return rate trend
SELECT
    DATE_FORMAT(txn_date, '%Y-%m')   AS month,
    COUNT(transaction_id)            AS total_orders,
    SUM(is_returned)                 AS returns,
    ROUND(
        SUM(is_returned) * 100.0
        / NULLIF(COUNT(transaction_id), 0), 2
    )                                AS return_rate_pct
FROM   transactions
GROUP  BY month
ORDER  BY month;

-- 7c. Sellers with highest return GMV impact
SELECT
    t.seller_id,
    s.seller_name,
    COUNT(t.transaction_id)       AS total_orders,
    ROUND(SUM(t.gmv_eur), 2)      AS total_gmv_eur,
    ROUND(
        SUM(CASE WHEN t.is_returned = 1 THEN t.gmv_eur ELSE 0 END), 2
    )                             AS returned_gmv_eur,
    ROUND(
        SUM(t.is_returned) * 100.0
        / NULLIF(COUNT(t.transaction_id), 0), 2
    )                             AS return_rate_pct
FROM   transactions t
JOIN   sellers s ON t.seller_id = s.seller_id
GROUP  BY t.seller_id, s.seller_name
HAVING total_orders >= 10
ORDER  BY returned_gmv_eur DESC
LIMIT  10;


-- ============================================================
-- STEP 8: SELLER RANKING WITH WINDOW FUNCTIONS
--         Relative performance within country and category
-- ============================================================

-- 8a. Seller GMV rank within each country using RANK()
WITH seller_gmv AS (
    SELECT
        t.seller_id,
        s.seller_name,
        s.country,
        s.avg_rating,
        ROUND(SUM(t.gmv_eur), 2)  AS total_gmv_eur,
        COUNT(t.transaction_id)   AS total_orders
    FROM   transactions t
    JOIN   sellers s ON t.seller_id = s.seller_id
    GROUP  BY t.seller_id, s.seller_name, s.country, s.avg_rating
)
SELECT
    seller_id,
    seller_name,
    country,
    avg_rating,
    total_gmv_eur,
    total_orders,
    RANK()       OVER (PARTITION BY country ORDER BY total_gmv_eur DESC) AS gmv_rank_in_country,
    DENSE_RANK() OVER (ORDER BY total_gmv_eur DESC)                      AS global_gmv_rank,
    ROUND(
        total_gmv_eur * 100.0
        / SUM(total_gmv_eur) OVER (PARTITION BY country), 2
    )                                                                    AS country_gmv_share_pct
FROM   seller_gmv
ORDER  BY country, gmv_rank_in_country;

-- 8b. Running cumulative GMV per seller (monthly)
SELECT
    s.seller_id,
    s.seller_name,
    DATE_FORMAT(t.txn_date, '%Y-%m')       AS month,
    ROUND(SUM(t.gmv_eur), 2)              AS monthly_gmv,
    ROUND(
        SUM(SUM(t.gmv_eur))
        OVER (PARTITION BY s.seller_id ORDER BY DATE_FORMAT(t.txn_date, '%Y-%m')), 2
    )                                     AS cumulative_gmv
FROM   transactions t
JOIN   sellers s ON t.seller_id = s.seller_id
GROUP  BY s.seller_id, s.seller_name, month
ORDER  BY s.seller_id, month;

-- 8c. Seller percentile tiers (TOP 10% / 25% / bottom)
WITH seller_gmv AS (
    SELECT
        seller_id,
        ROUND(SUM(gmv_eur), 2) AS total_gmv_eur
    FROM   transactions
    GROUP  BY seller_id
),
ranked AS (
    SELECT
        seller_id,
        total_gmv_eur,
        PERCENT_RANK() OVER (ORDER BY total_gmv_eur)       AS pct_rank
    FROM   seller_gmv
)
SELECT
    seller_id,
    total_gmv_eur,
    ROUND(pct_rank * 100, 1) AS percentile,
    CASE
        WHEN pct_rank >= 0.90 THEN 'Top 10%'
        WHEN pct_rank >= 0.75 THEN 'Top 25%'
        WHEN pct_rank >= 0.50 THEN 'Top 50%'
        ELSE 'Bottom 50%'
    END                      AS seller_tier
FROM   ranked
ORDER  BY total_gmv_eur DESC;


-- ============================================================
-- STEP 9: FULL SELLER SCORECARD (COMBINED PIPELINE VIEW)
--         Single dashboard query joining all four tables
-- ============================================================

SELECT
    s.seller_id,
    s.seller_name,
    s.country,
    s.category                                         AS seller_category,
    s.is_premium,
    s.avg_rating,
    s.total_products                                   AS catalog_size,

    -- Listing metrics
    COUNT(DISTINCT pl.listing_id)                      AS active_listings,
    ROUND(AVG(pl.price_eur), 2)                        AS avg_listing_price_eur,
    SUM(pl.stock_qty)                                  AS total_stock_units,

    -- Transaction metrics
    COUNT(DISTINCT t.transaction_id)                   AS total_orders,
    SUM(t.quantity)                                    AS units_sold,
    ROUND(SUM(t.gmv_eur), 2)                           AS total_gmv_eur,
    ROUND(AVG(t.gmv_eur), 2)                           AS avg_order_value_eur,
    ROUND(
        SUM(t.is_returned) * 100.0
        / NULLIF(COUNT(t.transaction_id), 0), 2
    )                                                  AS return_rate_pct,

    -- Session metrics
    COUNT(DISTINCT ss.session_id)                      AS total_sessions,
    ROUND(AVG(ss.page_views), 2)                       AS avg_page_views,
    ROUND(AVG(ss.session_dur_sec), 2)                  AS avg_session_dur_sec,
    ROUND(SUM(ss.bounced) * 100.0
        / NULLIF(COUNT(ss.session_id), 0), 2)          AS session_bounce_rate_pct,

    -- Conversion: sessions that resulted in a purchase
    ROUND(
        COUNT(DISTINCT t.session_id) * 100.0
        / NULLIF(COUNT(DISTINCT ss.session_id), 0), 2
    )                                                  AS session_conversion_rate_pct,

    -- GMV rank (global)
    DENSE_RANK() OVER (ORDER BY SUM(t.gmv_eur) DESC)  AS global_gmv_rank

FROM       sellers s
LEFT JOIN  product_listings pl ON s.seller_id = pl.seller_id AND pl.is_active = 1
LEFT JOIN  transactions t      ON s.seller_id = t.seller_id
LEFT JOIN  sessions ss         ON s.seller_id = ss.seller_id
GROUP BY
    s.seller_id, s.seller_name, s.country,
    s.category, s.is_premium, s.avg_rating, s.total_products
ORDER BY total_gmv_eur DESC;


-- ============================================================
-- STEP 10: COHORT & USER BEHAVIOUR ANALYSIS
--          Repeat buyers, multi-device usage, top users
-- ============================================================

-- 10a. Repeat buyer analysis (users with 2+ purchases)
SELECT
    user_id,
    COUNT(DISTINCT transaction_id)         AS total_purchases,
    COUNT(DISTINCT txn_date)               AS purchase_days,
    MIN(txn_date)                          AS first_purchase_date,
    MAX(txn_date)                          AS last_purchase_date,
    DATEDIFF(MAX(txn_date), MIN(txn_date)) AS days_active_span,
    ROUND(SUM(gmv_eur), 2)                 AS lifetime_gmv_eur,
    ROUND(AVG(gmv_eur), 2)                 AS avg_order_value_eur
FROM   transactions
GROUP  BY user_id
HAVING total_purchases > 1
ORDER  BY lifetime_gmv_eur DESC
LIMIT  20;

-- 10b. Device preference of buyers
SELECT
    device,
    COUNT(DISTINCT user_id)               AS unique_buyers,
    COUNT(transaction_id)                 AS total_orders,
    ROUND(SUM(gmv_eur), 2)               AS total_gmv_eur,
    ROUND(AVG(gmv_eur), 2)               AS avg_order_value_eur
FROM   transactions
GROUP  BY device
ORDER  BY total_gmv_eur DESC;

-- 10c. Cross-category buyers (users who bought from 2+ categories)
SELECT
    user_id,
    COUNT(DISTINCT category)               AS categories_purchased,
    GROUP_CONCAT(DISTINCT category ORDER BY category SEPARATOR ', ')
                                           AS categories_list,
    ROUND(SUM(gmv_eur), 2)                AS total_gmv_eur
FROM   transactions
GROUP  BY user_id
HAVING categories_purchased >= 2
ORDER  BY categories_purchased DESC, total_gmv_eur DESC
LIMIT  20;


-- ============================================================
-- END OF SCRIPT
-- ============================================================
