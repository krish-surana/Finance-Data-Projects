-- ============================================================
-- E-COMMERCE CUSTOMER ANALYSIS — SQL QUERIES
-- Krish Surana | Data Analysis Project
-- Database: ecommerce_db | Tables: orders, customers, products
-- ============================================================

-- ─────────────────────────────────────────────
-- STEP 1: DATA QUALITY CHECKS
-- ─────────────────────────────────────────────

-- Check for NULL values in key columns
SELECT 
    COUNT(*) AS total_records,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN order_date IS NULL THEN 1 ELSE 0 END) AS null_order_date,
    SUM(CASE WHEN revenue IS NULL THEN 1 ELSE 0 END) AS null_revenue,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS null_product_id
FROM orders;

-- Check for duplicate orders
SELECT order_id, COUNT(*) AS duplicate_count
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Check revenue outliers (flag orders > 3 std devs from mean)
SELECT order_id, customer_id, revenue,
    (revenue - AVG(revenue) OVER()) / STDDEV(revenue) OVER() AS z_score
FROM orders
HAVING ABS(z_score) > 3;

-- Validate date ranges
SELECT 
    MIN(order_date) AS earliest_order,
    MAX(order_date) AS latest_order,
    COUNT(DISTINCT YEAR(order_date)) AS years_covered
FROM orders;

-- ─────────────────────────────────────────────
-- STEP 2: REVENUE ANALYSIS
-- ─────────────────────────────────────────────

-- Total revenue by month
SELECT 
    DATE_FORMAT(order_date, '%Y-%m') AS month,
    COUNT(order_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS unique_customers,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(AVG(revenue), 2) AS avg_order_value,
    ROUND(SUM(revenue) / LAG(SUM(revenue)) OVER(ORDER BY DATE_FORMAT(order_date,'%Y-%m')) - 1, 4) AS mom_growth
FROM orders
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month;

-- Revenue by product category
SELECT 
    p.category,
    COUNT(o.order_id) AS total_orders,
    ROUND(SUM(o.revenue), 2) AS total_revenue,
    ROUND(SUM(o.revenue) / SUM(SUM(o.revenue)) OVER() * 100, 2) AS revenue_share_pct,
    ROUND(AVG(o.revenue), 2) AS avg_order_value
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY p.category
ORDER BY total_revenue DESC;

-- Revenue by region
SELECT 
    c.region,
    COUNT(DISTINCT c.customer_id) AS customers,
    COUNT(o.order_id) AS orders,
    ROUND(SUM(o.revenue), 2) AS revenue,
    ROUND(AVG(o.revenue), 2) AS avg_order_value,
    ROUND(SUM(o.revenue) / SUM(SUM(o.revenue)) OVER() * 100, 2) AS revenue_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.region
ORDER BY revenue DESC;

-- ─────────────────────────────────────────────
-- STEP 3: CUSTOMER SEGMENTATION (RFM ANALYSIS)
-- ─────────────────────────────────────────────

-- Calculate RFM scores
WITH rfm_base AS (
    SELECT 
        customer_id,
        DATEDIFF(CURDATE(), MAX(order_date)) AS recency_days,
        COUNT(order_id) AS frequency,
        ROUND(SUM(revenue), 2) AS monetary
    FROM orders
    GROUP BY customer_id
),
rfm_scores AS (
    SELECT *,
        NTILE(5) OVER(ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER(ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER(ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),
rfm_segments AS (
    SELECT *,
        r_score + f_score + m_score AS rfm_total,
        CASE 
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
            WHEN r_score >= 3 AND f_score <= 2 AND m_score >= 3 THEN 'Potential Loyalists'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk'
            WHEN r_score <= 2 AND f_score >= 4 THEN 'Cant Lose Them'
            WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost Customers'
            ELSE 'Average Customers'
        END AS segment
    FROM rfm_scores
)
SELECT * FROM rfm_segments ORDER BY rfm_total DESC;

-- Segment summary
WITH rfm_base AS (
    SELECT customer_id,
        DATEDIFF(CURDATE(), MAX(order_date)) AS recency_days,
        COUNT(order_id) AS frequency,
        ROUND(SUM(revenue), 2) AS monetary
    FROM orders GROUP BY customer_id
),
rfm_scores AS (
    SELECT *,
        NTILE(5) OVER(ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER(ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER(ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),
rfm_segments AS (
    SELECT *,
        CASE 
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
            WHEN r_score >= 3 AND f_score <= 2 AND m_score >= 3 THEN 'Potential Loyalists'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk'
            ELSE 'Others'
        END AS segment
    FROM rfm_scores
)
SELECT 
    segment,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_customers,
    ROUND(AVG(monetary), 2) AS avg_revenue,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER(), 2) AS pct_of_revenue,
    ROUND(AVG(frequency), 1) AS avg_orders,
    ROUND(AVG(recency_days), 0) AS avg_recency_days
FROM rfm_segments
GROUP BY segment
ORDER BY total_revenue DESC;

-- ─────────────────────────────────────────────
-- STEP 4: PARETO ANALYSIS (TOP 20% CUSTOMERS)
-- ─────────────────────────────────────────────

WITH customer_revenue AS (
    SELECT 
        customer_id,
        ROUND(SUM(revenue), 2) AS total_revenue,
        COUNT(order_id) AS total_orders
    FROM orders
    GROUP BY customer_id
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER(ORDER BY total_revenue DESC) AS revenue_rank,
        COUNT(*) OVER() AS total_customers,
        SUM(total_revenue) OVER() AS grand_total_revenue,
        SUM(total_revenue) OVER(ORDER BY total_revenue DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_revenue
    FROM customer_revenue
)
SELECT 
    customer_id,
    total_revenue,
    total_orders,
    revenue_rank,
    ROUND(revenue_rank * 100.0 / total_customers, 1) AS pct_of_customers,
    ROUND(cumulative_revenue * 100.0 / grand_total_revenue, 1) AS cumulative_revenue_pct,
    CASE WHEN revenue_rank * 100.0 / total_customers <= 20 
         THEN 'Top 20% — High Value' ELSE 'Bottom 80%' END AS customer_tier
FROM ranked
ORDER BY revenue_rank;

-- Summary: What % of revenue comes from top 20%?
WITH customer_revenue AS (
    SELECT customer_id, SUM(revenue) AS total_revenue
    FROM orders GROUP BY customer_id
),
ranked AS (
    SELECT *,
        NTILE(5) OVER(ORDER BY total_revenue DESC) AS quintile
    FROM customer_revenue
)
SELECT 
    CASE WHEN quintile = 1 THEN 'Top 20%' ELSE 'Bottom 80%' END AS customer_group,
    COUNT(*) AS customers,
    ROUND(SUM(total_revenue), 0) AS revenue,
    ROUND(SUM(total_revenue) * 100.0 / SUM(SUM(total_revenue)) OVER(), 1) AS revenue_share_pct
FROM ranked
GROUP BY CASE WHEN quintile = 1 THEN 'Top 20%' ELSE 'Bottom 80%' END;

-- ─────────────────────────────────────────────
-- STEP 5: PRODUCT PERFORMANCE
-- ─────────────────────────────────────────────

-- Top 10 products by revenue
SELECT 
    p.product_id, p.product_name, p.category,
    COUNT(o.order_id) AS units_sold,
    ROUND(SUM(o.revenue), 2) AS total_revenue,
    ROUND(AVG(o.revenue), 2) AS avg_price,
    ROUND(SUM(o.revenue) * 100.0 / SUM(SUM(o.revenue)) OVER(), 2) AS revenue_share_pct
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC
LIMIT 10;

-- ─────────────────────────────────────────────
-- STEP 6: COHORT RETENTION ANALYSIS
-- ─────────────────────────────────────────────

WITH first_orders AS (
    SELECT customer_id, MIN(DATE_FORMAT(order_date, '%Y-%m')) AS cohort_month
    FROM orders GROUP BY customer_id
),
order_activity AS (
    SELECT o.customer_id,
        f.cohort_month,
        DATE_FORMAT(o.order_date, '%Y-%m') AS order_month,
        PERIOD_DIFF(
            EXTRACT(YEAR_MONTH FROM o.order_date),
            EXTRACT(YEAR_MONTH FROM STR_TO_DATE(CONCAT(f.cohort_month,'-01'),'%Y-%m-%d'))
        ) AS months_since_first
    FROM orders o JOIN first_orders f ON o.customer_id = f.customer_id
)
SELECT 
    cohort_month,
    months_since_first,
    COUNT(DISTINCT customer_id) AS active_customers
FROM order_activity
GROUP BY cohort_month, months_since_first
ORDER BY cohort_month, months_since_first;

-- ============================================================
-- END OF SQL ANALYSIS
-- ============================================================
