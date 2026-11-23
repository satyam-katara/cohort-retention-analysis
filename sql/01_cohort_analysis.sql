
/*
=========================================================
PROJECT: COHORT RETENTION ANALYSIS
DATASET: OLIST BRAZILIAN E-COMMERCE
DATABASE: OperationalDashboard
TOOL: MICROSOFT SQL SERVER

BUSINESS QUESTION:
Do customers acquired in different months retain differently?

OBJECTIVE:
Analyze monthly customer retention by grouping customers
into cohorts based on their first purchase month.

CUSTOMER KEY:
customer_unique_id

ORDER KEY:
order_id

=========================================================
*/
USE OperationalDashboard;
GO


/*
=========================================================
SECTION 1: CUSTOMER-ORDER DATA PREPARATION
=========================================================

Purpose:
Join customer and order tables using customer_id.

Important:
customer_id is order-specific.
customer_unique_id identifies the actual customer.

Only valid customer identifiers and purchase timestamps
will be considered in the cohort analysis.
=========================================================
*/

-- Section 1 queries will be added here.

-- 1.1 CUSTOMER-ORDER DATA PREPARATION

IF OBJECT_ID('tempdb..#CustomerOrders') IS NOT NULL
    DROP TABLE #CustomerOrders;

SELECT
    c.customer_unique_id,
    o.customer_id,
    o.order_id,
    o.order_purchase_timestamp,
    CAST(
        DATEFROMPARTS(
            YEAR(o.order_purchase_timestamp),
            MONTH(o.order_purchase_timestamp),
            1
        ) AS DATE
    ) AS purchase_month,
    o.order_status
INTO #CustomerOrders
FROM dbo.olist_orders_dataset o
INNER JOIN dbo.olist_customers_dataset c
    ON o.customer_id = c.customer_id
WHERE
    c.customer_unique_id IS NOT NULL
    AND o.order_purchase_timestamp IS NOT NULL;


-- 1.2 VERIFY PREPARED DATA

SELECT
    COUNT(*) AS TotalOrderRecords,
    COUNT(DISTINCT order_id) AS UniqueOrders,
    COUNT(DISTINCT customer_unique_id) AS UniqueCustomers,
    MIN(order_purchase_timestamp) AS FirstPurchase,
    MAX(order_purchase_timestamp) AS LastPurchase
FROM #CustomerOrders;


-- 1.3 SAMPLE RECORDS

SELECT TOP 10 *
FROM #CustomerOrders
ORDER BY order_purchase_timestamp;




/*
=========================================================
SECTION 2: FIRST PURCHASE MONTH & COHORT ASSIGNMENT
=========================================================

Business Logic:
Each customer is assigned to the month of their
first-ever recorded purchase.

Customer identifier: customer_unique_id
=========================================================
*/

-- 2.1 Find each customer's first purchase date

IF OBJECT_ID('tempdb..#CustomerCohorts') IS NOT NULL
    DROP TABLE #CustomerCohorts;

SELECT
    customer_unique_id,
    MIN(order_purchase_timestamp) AS first_purchase_date,
    CAST(
        DATEFROMPARTS(
            YEAR(MIN(order_purchase_timestamp)),
            MONTH(MIN(order_purchase_timestamp)),
            1
        ) AS DATE
    ) AS cohort_month
INTO #CustomerCohorts
FROM #CustomerOrders
GROUP BY customer_unique_id;


-- 2.2 Inspect customer cohort assignments

SELECT TOP 20
    customer_unique_id,
    first_purchase_date,
    cohort_month
FROM #CustomerCohorts
ORDER BY first_purchase_date;


-- 2.3 Calculate cohort sizes

SELECT
    cohort_month,
    COUNT(*) AS cohort_size
FROM #CustomerCohorts
GROUP BY cohort_month
ORDER BY cohort_month;


-- 2.4 Validate total cohort customers

SELECT
    COUNT(*) AS TotalCohortCustomers,
    COUNT(DISTINCT customer_unique_id) AS UniqueCustomers
FROM #CustomerCohorts;


-- 2.5 Verify cohort sizes against total customers

SELECT
    SUM(cohort_size) AS SumOfCohortSizes,
    (SELECT COUNT(DISTINCT customer_unique_id)
     FROM #CustomerOrders) AS TotalUniqueCustomers
FROM (
    SELECT
        cohort_month,
        COUNT(*) AS cohort_size
    FROM #CustomerCohorts
    GROUP BY cohort_month
) AS CohortSummary;




/*
=========================================================
SECTION 3: MONTHS SINCE FIRST PURCHASE
=========================================================

Purpose:
Calculate the number of months elapsed between a
customer's cohort month and each order's purchase month.

Example:
Cohort: January 2017
Purchase: March 2017
Months Since First Purchase: 2
=========================================================
*/

-- 3.1 Calculate customer activity by cohort month

IF OBJECT_ID('tempdb..#CustomerActivity') IS NOT NULL
    DROP TABLE #CustomerActivity;

SELECT
    co.customer_unique_id,
    cc.cohort_month,
    co.purchase_month,

    DATEDIFF(
        MONTH,
        cc.cohort_month,
        co.purchase_month
    ) AS months_since_first_purchase,

    co.order_id

INTO #CustomerActivity

FROM #CustomerOrders co
INNER JOIN #CustomerCohorts cc
    ON co.customer_unique_id = cc.customer_unique_id;


-- 3.2 Inspect customer activity

SELECT TOP 20 *
FROM #CustomerActivity
ORDER BY
    cohort_month,
    customer_unique_id,
    purchase_month;


-- 3.3 Check month offsets

SELECT
    MIN(months_since_first_purchase) AS MinimumMonthOffset,
    MAX(months_since_first_purchase) AS MaximumMonthOffset,
    COUNT(*) AS TotalActivityRecords
FROM #CustomerActivity;


-- 3.4 Check for invalid negative offsets

SELECT COUNT(*) AS NegativeMonthOffsets
FROM #CustomerActivity
WHERE months_since_first_purchase < 0;




/*
=========================================================
SECTION 4: COHORT RETENTION COUNT MATRIX
=========================================================

Purpose:
Calculate distinct active customers for each cohort
across months 0 to 11.

Rows: Cohort Month
Columns: Month 0 to Month 11
Values: Distinct Active Customers

Important:
Future unobserved months are represented as NULL,
not zero.
=========================================================
*/

-- 4.1 Generate month offsets

IF OBJECT_ID('tempdb..#CohortGrid') IS NOT NULL
    DROP TABLE #CohortGrid;

DECLARE @LastObservedMonth DATE;

SELECT
    @LastObservedMonth =
        DATEFROMPARTS(
            YEAR(MAX(order_purchase_timestamp)),
            MONTH(MAX(order_purchase_timestamp)),
            1
        )
FROM #CustomerOrders;


SELECT
    cc.cohort_month,
    cc.cohort_size,
    m.month_offset,

    CASE
        WHEN DATEADD(MONTH, m.month_offset, cc.cohort_month)
             <= @LastObservedMonth
        THEN COUNT(DISTINCT ca.customer_unique_id)
        ELSE NULL
    END AS active_customers

INTO #CohortGrid

FROM (
    SELECT
        cohort_month,
        COUNT(*) AS cohort_size
    FROM #CustomerCohorts
    GROUP BY cohort_month
) cc

CROSS JOIN (
    SELECT month_offset
    FROM (VALUES
        (0), (1), (2), (3), (4), (5),
        (6), (7), (8), (9), (10), (11)
    ) AS MonthOffsets(month_offset)
) m

LEFT JOIN #CustomerActivity ca
    ON ca.cohort_month = cc.cohort_month
    AND ca.months_since_first_purchase = m.month_offset

GROUP BY
    cc.cohort_month,
    cc.cohort_size,
    m.month_offset;


-- 4.2 Generate retention count matrix

IF OBJECT_ID('tempdb..#CohortCounts') IS NOT NULL
    DROP TABLE #CohortCounts;

SELECT
    cohort_month,
    MAX(cohort_size) AS cohort_size,

    MAX(CASE WHEN month_offset = 0
        THEN active_customers END) AS Month_0,

    MAX(CASE WHEN month_offset = 1
        THEN active_customers END) AS Month_1,

    MAX(CASE WHEN month_offset = 2
        THEN active_customers END) AS Month_2,

    MAX(CASE WHEN month_offset = 3
        THEN active_customers END) AS Month_3,

    MAX(CASE WHEN month_offset = 4
        THEN active_customers END) AS Month_4,

    MAX(CASE WHEN month_offset = 5
        THEN active_customers END) AS Month_5,

    MAX(CASE WHEN month_offset = 6
        THEN active_customers END) AS Month_6,

    MAX(CASE WHEN month_offset = 7
        THEN active_customers END) AS Month_7,

    MAX(CASE WHEN month_offset = 8
        THEN active_customers END) AS Month_8,

    MAX(CASE WHEN month_offset = 9
        THEN active_customers END) AS Month_9,

    MAX(CASE WHEN month_offset = 10
        THEN active_customers END) AS Month_10,

    MAX(CASE WHEN month_offset = 11
        THEN active_customers END) AS Month_11

INTO #CohortCounts

FROM #CohortGrid
GROUP BY cohort_month;


-- 4.3 Display cohort retention count matrix

SELECT *
FROM #CohortCounts
ORDER BY cohort_month;



/*
=========================================================
SECTION 5: COHORT RETENTION PERCENTAGE MATRIX
=========================================================

Formula:
Retention Rate = (Active Customers / Cohort Size) * 100

Month 0 retention should equal 100% for every cohort.
Unobserved months remain NULL.
=========================================================
*/

-- 5.1 Calculate retention percentages

IF OBJECT_ID('tempdb..#CohortRetention') IS NOT NULL
    DROP TABLE #CohortRetention;

SELECT
    cohort_month,
    cohort_size,

    CAST(Month_0 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_0,

    CAST(Month_1 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_1,

    CAST(Month_2 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_2,

    CAST(Month_3 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_3,

    CAST(Month_4 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_4,

    CAST(Month_5 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_5,

    CAST(Month_6 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_6,

    CAST(Month_7 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_7,

    CAST(Month_8 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_8,

    CAST(Month_9 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_9,

    CAST(Month_10 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_10,

    CAST(Month_11 * 100.0 / NULLIF(cohort_size, 0)
        AS DECIMAL(6,2)) AS Month_11

INTO #CohortRetention

FROM #CohortCounts;


-- 5.2 Display final retention matrix

SELECT *
FROM #CohortRetention
ORDER BY cohort_month;


-- 5.3 Verify Month 0 retention

SELECT
    cohort_month,
    cohort_size,
    Month_0,
    CASE
        WHEN Month_0 = 100.00 THEN 'PASS'
        ELSE 'FAIL'
    END AS Month0Validation
FROM #CohortRetention
ORDER BY cohort_month;



-- =============================================
-- FINAL OUTPUT: RETENTION MATRIX EXPORT
-- =============================================

SELECT
    cohort_month,
    cohort_size,
    Month_0,
    Month_1,
    Month_2,
    Month_3,
    Month_4,
    Month_5,
    Month_6,
    Month_7,
    Month_8,
    Month_9,
    Month_10,
    Month_11
FROM #CohortRetention
ORDER BY cohort_month;
