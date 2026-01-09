-- CLEANUP
DROP TABLE IF EXISTS sales_final;
DROP TABLE IF EXISTS rfm_scores;
DROP TABLE IF EXISTS rfm_final_segments;
DROP VIEW IF EXISTS rfm_metrics;

-- DATA TRANSFORMATION: Add 'state' to resolve Tableau mapping ambiguity
CREATE TABLE sales_final AS
SELECT 
    TRIM(`Order ID`) AS order_id,
    STR_TO_DATE(`Date`, '%d-%m-%y') AS order_date, 
    LOWER(TRIM(`Category`)) AS category,
    LOWER(TRIM(`Product`)) AS product_name,
    CAST(`Price` AS DECIMAL(10,2)) AS price,
    CAST(`Quantity` AS UNSIGNED) AS quantity,
    CAST(`Total Sales` AS DECIMAL(10,2)) AS total_revenue,
    `Customer Location` AS location,
    -- Mapping City to State for 100% accuracy in Tableau
    CASE 
        WHEN `Customer Location` = 'Miami' THEN 'Florida'
        WHEN `Customer Location` = 'Houston' THEN 'Texas'
        WHEN `Customer Location` = 'New York' THEN 'New York'
        WHEN `Customer Location` = 'Boston' THEN 'Massachusetts'
        WHEN `Customer Location` = 'Chicago' THEN 'Illinois'
        WHEN `Customer Location` = 'Seattle' THEN 'Washington'
        WHEN `Customer Location` = 'Dallas' THEN 'Texas'
        WHEN `Customer Location` = 'Denver' THEN 'Colorado'
        WHEN `Customer Location` = 'San Francisco' THEN 'California'
        WHEN `Customer Location` = 'Los Angeles' THEN 'California'
        ELSE 'United States'
    END AS state,
    `Payment Method` AS payment_method,
    `Status`
FROM amazon_sales25
WHERE `Order ID` IS NOT NULL 
  AND `Total Sales` IS NOT NULL
  AND `Date` IS NOT NULL
  AND `Total Sales` > 0;

-- EDA: Top 5 products by revenue
SELECT product_name, SUM(total_revenue) AS revenue
FROM sales_final
GROUP BY product_name
ORDER BY revenue DESC
LIMIT 5;

-- ANALYSIS: Month-over-Month (MoM) Growth
WITH monthly_sales AS (
    SELECT 
        DATE_FORMAT(order_date, '%Y-%m') AS sales_month,
        SUM(total_revenue) AS total_revenue
    FROM sales_final
    GROUP BY sales_month
)
SELECT 
    sales_month,
    total_revenue,
    LAG(total_revenue) OVER (ORDER BY sales_month) AS prev_month_revenue,
    ROUND((total_revenue - LAG(total_revenue) OVER (ORDER BY sales_month)) / 
          LAG(total_revenue) OVER (ORDER BY sales_month) * 100, 2) AS mom_growth_pct
FROM monthly_sales;

-- RFM PREPARATION
CREATE OR REPLACE VIEW rfm_metrics AS
SELECT 
    location,
    state,
    DATEDIFF((SELECT MAX(order_date) FROM sales_final), MAX(order_date)) AS recency,
    COUNT(order_id) AS frequency,
    SUM(total_revenue) AS monetary
FROM sales_final
GROUP BY location, state;

-- RFM SCORING: Value-based logic for Recency
CREATE TABLE rfm_scores AS
SELECT 
    *,
    CASE 
        WHEN recency = 0 THEN 5
        WHEN recency <= 2 THEN 4
        WHEN recency <= 5 THEN 3
        WHEN recency <= 10 THEN 2
        ELSE 1 
    END AS r_score,
    NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
    NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
FROM rfm_metrics;

-- SEGMENTATION
CREATE TABLE rfm_final_segments AS
SELECT 
    *,
    CONCAT(r_score, f_score, m_score) AS rfm_cell,
    ROUND((r_score + f_score + m_score) / 3, 1) AS rfm_avg_score,
    CASE 
        WHEN (r_score + f_score + m_score) / 3 >= 4.5 THEN 'Champion Region'
        WHEN (r_score + f_score + m_score) / 3 >= 3.5 THEN 'Loyal/Active Region'
        WHEN (r_score + f_score + m_score) / 3 >= 2.5 THEN 'Average Performance'
        WHEN (r_score + f_score + m_score) / 3 >= 1.5 THEN 'At Risk / Declining'
        ELSE 'Hibernating / Lost'
    END AS segment_label
FROM rfm_scores;

-- FINAL OUTPUT
SELECT * FROM rfm_final_segments ORDER BY rfm_avg_score DESC;
SELECT * FROM sales_final order by order_id;
