
/*
=========================================================
PROJECT: COHORT RETENTION ANALYSIS
FILE: 02_data_validation.sql
DATABASE: OperationalDashboard

PURPOSE:
Validate customer and order data before cohort analysis.

=========================================================
*/

USE OperationalDashboard;
GO

-- 1. Check unmatched orders
SELECT
    COUNT(*) AS UnmatchedOrders
FROM dbo.olist_orders_dataset o
LEFT JOIN dbo.olist_customers_dataset c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;


-- 2. Check duplicate customer mappings
SELECT
    customer_id,
    COUNT(DISTINCT customer_unique_id) AS UniqueCustomerMappings
FROM dbo.olist_customers_dataset
GROUP BY customer_id
HAVING COUNT(DISTINCT customer_unique_id) > 1;


-- 3. Check null customer identifiers
SELECT
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END)
        AS NullCustomerIDs,
    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END)
        AS NullUniqueCustomerIDs
FROM dbo.olist_customers_dataset;


-- 4. Check null order identifiers and timestamps
SELECT
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END)
        AS NullOrderCustomerIDs,
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END)
        AS NullPurchaseTimestamps
FROM dbo.olist_orders_dataset;


-- 5. Order status distribution
SELECT
    order_status,
    COUNT(*) AS TotalOrders
FROM dbo.olist_orders_dataset
GROUP BY order_status
ORDER BY TotalOrders DESC;


-- 6. Customer count verification
SELECT
    COUNT(*) AS CustomerRecords,
    COUNT(DISTINCT customer_id) AS UniqueCustomerIDs,
    COUNT(DISTINCT customer_unique_id) AS UniqueRealCustomers
FROM dbo.olist_customers_dataset;


-- 7. Order date range
SELECT
    MIN(order_purchase_timestamp) AS FirstOrder,
    MAX(order_purchase_timestamp) AS LastOrder
FROM dbo.olist_orders_dataset;




-- =============================================
-- 8. COHORT RETENTION VALIDATION
-- =============================================

-- Check total customers against cohort sizes

WITH CustomerFirstPurchase AS
(
    SELECT
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_purchase
    FROM dbo.olist_customers_dataset c
    INNER JOIN dbo.olist_orders_dataset o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
),
CohortSizes AS
(
    SELECT
        DATEFROMPARTS(
            YEAR(first_purchase),
            MONTH(first_purchase),
            1
        ) AS cohort_month,
        COUNT(*) AS cohort_size
    FROM CustomerFirstPurchase
    GROUP BY
        YEAR(first_purchase),
        MONTH(first_purchase)
)
SELECT
    SUM(cohort_size) AS TotalCohortCustomers,
    COUNT(*) AS TotalCohorts
FROM CohortSizes;


-- 9. Independent Month 0 validation

WITH CustomerFirstPurchase AS
(
    SELECT
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_purchase
    FROM dbo.olist_customers_dataset c
    INNER JOIN dbo.olist_orders_dataset o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    DATEFROMPARTS(
        YEAR(first_purchase),
        MONTH(first_purchase),
        1
    ) AS cohort_month,
    COUNT(*) AS cohort_size
FROM CustomerFirstPurchase
GROUP BY
    YEAR(first_purchase),
    MONTH(first_purchase)
ORDER BY cohort_month;
