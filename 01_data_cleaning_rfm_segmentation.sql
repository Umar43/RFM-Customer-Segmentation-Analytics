
-- Online Retail II — SQL Cleaning & Investigation
-- ============================================

-- Re-create the staging table to store raw transactional data cleanly
DROP TABLE IF EXISTS online_retail;
CREATE TABLE online_retail (
    invoice_no VARCHAR(20),
    stock_code VARCHAR(20),
    description TEXT,
    quantity INT,
    invoice_date TIMESTAMP,
    unit_price NUMERIC(10,2),
    customer_id INT,
    country VARCHAR(50),
    revenue NUMERIC(12,2)
);

-- Verify total imported row count (expect ~541,910)
SELECT COUNT(*) FROM online_retail;

-- Preview the first 10 records to inspect column formatting and structure
SELECT * FROM online_retail LIMIT 10;

-- Identify missing customer IDs
SELECT COUNT(*) AS Null_customer_id FROM online_retail WHERE customer_id IS NULL;

-- Count formal order cancellations, invoices starting with 'C'
SELECT COUNT(*) AS cancelled_order FROM online_retail WHERE invoice_no LIKE 'C%';

-- Count overall negative quantities — includes returns + inventory adjustments
SELECT COUNT(*) AS negative_quantity FROM online_retail WHERE quantity < 0;

-- Count negative quantities NOT starting with 'C' — unusual inventory records 
SELECT COUNT(*) AS negative_quantity FROM online_retail 
WHERE quantity < 0 AND invoice_no NOT LIKE 'C%';

-- Inspect a sample of non-'C' negative quantity transactions
SELECT * FROM online_retail 
WHERE quantity < 0 AND invoice_no NOT LIKE 'C%' LIMIT 20;

-- Validate if non-'C' negative records are zero-price internal stock write-offs
SELECT COUNT(*) AS zero_price_inventory_adjustments FROM online_retail 
WHERE quantity < 0 AND invoice_no NOT LIKE 'C%' AND unit_price = 0;


-- RFM: Frequency and Monetary per customer

SELECT customer_id, 
    COUNT(DISTINCT invoice_no) AS Frequency, 
    SUM(revenue) AS Monetary
FROM online_retail
WHERE customer_id IS NOT NULL 
  AND invoice_no NOT LIKE 'C%' 
  AND quantity > 0
GROUP BY customer_id
ORDER BY Monetary DESC;

-- Investigate customer 16446 
SELECT * FROM online_retail WHERE customer_id = 16446;
-- Finding: one 80,995-unit order (€168,469.60) placed, then fully cancelled 12 min later.
-- Check if this is a one-off or a pattern — find the largest single invoices dataset-wide
SELECT customer_id, invoice_no, SUM(revenue) AS invoice_total
FROM online_retail
WHERE customer_id IS NOT NULL AND invoice_no NOT LIKE 'C%' AND quantity > 0
GROUP BY customer_id, invoice_no
ORDER BY invoice_total DESC
LIMIT 20;

-- Investigate customer 12346 
SELECT * FROM online_retail WHERE customer_id = 12346;
-- Finding: same pattern — one 74,215-unit order, cancelled 16 min later.

-- Self-join to find ALL cancelled-then-rebought orders,
SELECT 
    o.customer_id, 
    o.invoice_no AS original_invoice, 
    c.invoice_no AS cancellation_invoice,
    o.stock_code, 
    o.quantity, 
    o.revenue
FROM online_retail o
JOIN online_retail c
  ON o.customer_id = c.customer_id
 AND o.stock_code = c.stock_code
 AND o.quantity = -c.quantity
WHERE o.quantity > 0
  AND o.invoice_no NOT LIKE 'C%'
  AND c.invoice_no LIKE 'C%'; 


SELECT DISTINCT o.customer_id, o.invoice_no
FROM online_retail o
JOIN online_retail c
  ON o.customer_id = c.customer_id
 AND o.stock_code = c.stock_code
 AND o.quantity = -c.quantity
WHERE o.quantity > 0
  AND o.invoice_no NOT LIKE 'C%'
  AND c.invoice_no LIKE 'C%';
  
--Find all original invoices that were genuinely cancelled
WITH cancelled_original_invoices AS (
    SELECT DISTINCT o.invoice_no
    FROM online_retail o
    JOIN online_retail c
      ON o.customer_id = c.customer_id
     AND o.stock_code = c.stock_code
     AND o.quantity = -c.quantity
     AND c.invoice_date > o.invoice_date
     AND c.invoice_date - o.invoice_date <= INTERVAL '1 day'
    WHERE o.quantity > 0
      AND o.invoice_no NOT LIKE 'C%'
      AND c.invoice_no LIKE 'C%'
)

-- Calculate RFM per customer
SELECT customer_id,
    '2011-12-09'::date - MAX(invoice_date)::date AS recency,
    COUNT(DISTINCT invoice_no) AS frequency,
    SUM(revenue) AS monetary
FROM online_retail
WHERE customer_id IS NOT NULL
  AND invoice_no NOT LIKE 'C%'
  AND quantity > 0
  AND invoice_no NOT IN (SELECT invoice_no FROM cancelled_original_invoices)
GROUP BY customer_id
ORDER BY monetary DESC;




-- Customer Segmentation: RFM Scoring (1-4 scale, 4 = best)
-- CORRECTED: NTILE assigns group 1 to the FIRST rows in the sort order,
-- regardless of ASC/DESC. So to get the BEST customers into group 4:
-- Recency: DESC (lowest/best recency ends up LAST in DESC order = group 4)
-- Frequency: ASC (highest/best frequency ends up LAST in ASC order = group 4)
-- Monetary: ASC (highest/best monetary ends up LAST in ASC order = group 4)

WITH cancelled_original_invoices AS (
    SELECT DISTINCT o.invoice_no
    FROM online_retail o
    JOIN online_retail c
      ON o.customer_id = c.customer_id
     AND o.stock_code = c.stock_code
     AND o.quantity = -c.quantity
     AND c.invoice_date > o.invoice_date
     AND c.invoice_date - o.invoice_date <= INTERVAL '1 day'
    WHERE o.quantity > 0
      AND o.invoice_no NOT LIKE 'C%'
      AND c.invoice_no LIKE 'C%'
),
rfm AS (
    SELECT customer_id,
        '2011-12-09'::date - MAX(invoice_date)::date AS recency,
        COUNT(DISTINCT invoice_no) AS frequency,
        SUM(revenue) AS monetary
    FROM online_retail
    WHERE customer_id IS NOT NULL
      AND invoice_no NOT LIKE 'C%'
      AND quantity > 0
      AND invoice_no NOT IN (SELECT invoice_no FROM cancelled_original_invoices)
    GROUP BY customer_id
)
SELECT customer_id, recency, frequency, monetary,
    NTILE(4) OVER (ORDER BY recency DESC) AS r_score,
    NTILE(4) OVER (ORDER BY frequency ASC) AS f_score,
    NTILE(4) OVER (ORDER BY monetary ASC) AS m_score
FROM rfm
ORDER BY monetary DESC;


-- Segment Summary: how many customers per segment, and their averages

WITH cancelled_original_invoices AS (
    SELECT DISTINCT o.invoice_no
    FROM online_retail o
    JOIN online_retail c
      ON o.customer_id = c.customer_id
     AND o.stock_code = c.stock_code
     AND o.quantity = -c.quantity
     AND c.invoice_date > o.invoice_date
     AND c.invoice_date - o.invoice_date <= INTERVAL '1 day'
    WHERE o.quantity > 0
      AND o.invoice_no NOT LIKE 'C%'
      AND c.invoice_no LIKE 'C%'
),
rfm_base AS (
    SELECT 
        customer_id,
        '2011-12-09'::date - MAX(invoice_date)::date AS recency,
        COUNT(DISTINCT invoice_no) AS frequency,
        SUM(revenue) AS monetary
    FROM online_retail
    WHERE customer_id IS NOT NULL 
      AND invoice_no NOT LIKE 'C%' 
      AND quantity > 0
      AND invoice_no NOT IN (SELECT invoice_no FROM cancelled_original_invoices)
    GROUP BY customer_id
),
rfm_scores AS (
    SELECT 
        customer_id, recency, frequency, monetary,
        NTILE(4) OVER (ORDER BY recency DESC) AS r_score,
        NTILE(4) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),
rfm_segments AS (
    SELECT customer_id, recency, frequency, monetary,
        CASE 
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
            WHEN r_score <= 2 AND (f_score >= 3 OR m_score >= 3) THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Lost'
            ELSE 'New / Promising'
        END AS customer_segment
    FROM rfm_scores
)
SELECT 
    customer_segment,
    COUNT(*) AS num_customers,
    ROUND(AVG(recency), 1) AS avg_recency_days,
    ROUND(AVG(frequency), 1) AS avg_orders,
    ROUND(AVG(monetary), 2) AS avg_spend
FROM rfm_segments
GROUP BY customer_segment
ORDER BY avg_spend DESC;



-- Per-customer segment labels (for Python stats test — NOT grouped)
WITH cancelled_original_invoices AS (
    SELECT DISTINCT o.invoice_no
    FROM online_retail o
    JOIN online_retail c
      ON o.customer_id = c.customer_id
     AND o.stock_code = c.stock_code
     AND o.quantity = -c.quantity
     AND c.invoice_date > o.invoice_date
     AND c.invoice_date - o.invoice_date <= INTERVAL '1 day'
    WHERE o.quantity > 0
      AND o.invoice_no NOT LIKE 'C%'
      AND c.invoice_no LIKE 'C%'
),
rfm_base AS (
    SELECT 
        customer_id,
        '2011-12-09'::date - MAX(invoice_date)::date AS recency,
        COUNT(DISTINCT invoice_no) AS frequency,
        SUM(revenue) AS monetary
    FROM online_retail
    WHERE customer_id IS NOT NULL 
      AND invoice_no NOT LIKE 'C%' 
      AND quantity > 0
      AND invoice_no NOT IN (SELECT invoice_no FROM cancelled_original_invoices)
    GROUP BY customer_id
),
rfm_scores AS (
    SELECT 
        customer_id, recency, frequency, monetary,
        NTILE(4) OVER (ORDER BY recency DESC) AS r_score,
        NTILE(4) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
)
SELECT 
    customer_id, recency, frequency, monetary,
    CASE 
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
        WHEN r_score <= 2 AND (f_score >= 3 OR m_score >= 3) THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Lost'
        ELSE 'New / Promising'
    END AS customer_segment
FROM rfm_scores
ORDER BY monetary DESC;


