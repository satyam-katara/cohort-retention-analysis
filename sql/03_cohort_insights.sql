
/*
=========================================================
PROJECT: COHORT RETENTION ANALYSIS
FILE: 03_cohort_insights.sql
DATABASE: OperationalDashboard

PURPOSE:
Analyze cohort sizes and customer retention patterns.
=========================================================
*/

USE OperationalDashboard;
GO

-- 1. COHORT SIZE RANKING

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
    cohort_month,
    cohort_size,
    DENSE_RANK() OVER (
        ORDER BY cohort_size DESC
    ) AS cohort_size_rank
FROM CohortSizes
ORDER BY cohort_size_rank;




-- =============================================
-- 2. MONTH-WISE RETENTION PERFORMANCE
-- CORRECTED VERSION
-- =============================================

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

Cohorts AS
(
    SELECT
        customer_unique_id,
        DATEFROMPARTS(
            YEAR(first_purchase),
            MONTH(first_purchase),
            1
        ) AS cohort_month
    FROM CustomerFirstPurchase
),

CohortSizes AS
(
    SELECT
        cohort_month,
        COUNT(*) AS cohort_size
    FROM Cohorts
    GROUP BY cohort_month
),

CustomerActivity AS
(
    SELECT DISTINCT
        c.customer_unique_id,
        c.cohort_month,

        DATEDIFF(
            MONTH,
            c.cohort_month,
            DATEFROMPARTS(
                YEAR(o.order_purchase_timestamp),
                MONTH(o.order_purchase_timestamp),
                1
            )
        ) AS month_offset

    FROM Cohorts c
    INNER JOIN dbo.olist_customers_dataset cu
        ON c.customer_unique_id = cu.customer_unique_id
    INNER JOIN dbo.olist_orders_dataset o
        ON cu.customer_id = o.customer_id
),

LastObservedMonth AS
(
    SELECT
        DATEFROMPARTS(
            YEAR(MAX(order_purchase_timestamp)),
            MONTH(MAX(order_purchase_timestamp)),
            1
        ) AS last_month
    FROM dbo.olist_orders_dataset
),

MonthOffsets AS
(
    SELECT month_offset
    FROM (VALUES
        (0),(1),(2),(3),(4),(5),
        (6),(7),(8),(9),(10),(11)
    ) v(month_offset)
),

CohortRetention AS
(
    SELECT
        cs.cohort_month,
        cs.cohort_size,
        mo.month_offset,

        COUNT(DISTINCT ca.customer_unique_id)
            AS active_customers,

        CAST(
            COUNT(DISTINCT ca.customer_unique_id) * 100.0
            / NULLIF(cs.cohort_size, 0)
            AS DECIMAL(6,2)
        ) AS retention_percentage

    FROM CohortSizes cs
    CROSS JOIN MonthOffsets mo
    CROSS JOIN LastObservedMonth lom

    LEFT JOIN CustomerActivity ca
        ON ca.cohort_month = cs.cohort_month
        AND ca.month_offset = mo.month_offset

    WHERE DATEADD(
        MONTH,
        mo.month_offset,
        cs.cohort_month
    ) <= lom.last_month

    GROUP BY
        cs.cohort_month,
        cs.cohort_size,
        mo.month_offset
)

SELECT
    month_offset,
    COUNT(*) AS CohortsObserved,

    CAST(
        AVG(retention_percentage)
        AS DECIMAL(6,2)
    ) AS AverageRetentionPercentage

FROM CohortRetention
WHERE cohort_size >= 100
GROUP BY month_offset
ORDER BY month_offset;

-- =============================================
-- 3. BEST AND WORST PERFORMING COHORTS
-- =============================================

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
Cohorts AS
(
    SELECT
        customer_unique_id,
        DATEFROMPARTS(
            YEAR(first_purchase),
            MONTH(first_purchase),
            1
        ) AS cohort_month
    FROM CustomerFirstPurchase
),
CohortSizes AS
(
    SELECT
        cohort_month,
        COUNT(*) AS cohort_size
    FROM Cohorts
    GROUP BY cohort_month
),
Activity AS
(
    SELECT DISTINCT
        c.customer_unique_id,
        c.cohort_month,
        DATEDIFF(
            MONTH,
            c.cohort_month,
            DATEFROMPARTS(
                YEAR(o.order_purchase_timestamp),
                MONTH(o.order_purchase_timestamp),
                1
            )
        ) AS month_offset
    FROM dbo.olist_orders_dataset o
    INNER JOIN dbo.olist_customers_dataset cu
        ON o.customer_id = cu.customer_id
    INNER JOIN Cohorts c
        ON cu.customer_unique_id = c.customer_unique_id
),
LastObservedMonth AS
(
    SELECT
        DATEFROMPARTS(
            YEAR(MAX(order_purchase_timestamp)),
            MONTH(MAX(order_purchase_timestamp)),
            1
        ) AS last_month
    FROM dbo.olist_orders_dataset
),
CohortRetention AS
(
    SELECT
        cs.cohort_month,
        cs.cohort_size,

        CAST(
            COUNT(DISTINCT CASE
                WHEN a.month_offset = 1
                THEN a.customer_unique_id
            END) * 100.0 / cs.cohort_size
            AS DECIMAL(6,2)
        ) AS Month_1_Retention,

        CAST(
            COUNT(DISTINCT CASE
                WHEN a.month_offset = 3
                THEN a.customer_unique_id
            END) * 100.0 / cs.cohort_size
            AS DECIMAL(6,2)
        ) AS Month_3_Retention,

        CAST(
            COUNT(DISTINCT CASE
                WHEN a.month_offset = 6
                THEN a.customer_unique_id
            END) * 100.0 / cs.cohort_size
            AS DECIMAL(6,2)
        ) AS Month_6_Retention,

        lom.last_month

    FROM CohortSizes cs
    CROSS JOIN LastObservedMonth lom
    LEFT JOIN Activity a
        ON cs.cohort_month = a.cohort_month
    GROUP BY
        cs.cohort_month,
        cs.cohort_size,
        lom.last_month
),
RetentionComparison AS
(
    SELECT
        cr.cohort_month,
        cr.cohort_size,
        r.month_offset,
        r.retention_percentage
    FROM CohortRetention cr
    CROSS APPLY
    (
        VALUES
        (
            1,
            CASE WHEN DATEADD(MONTH, 1, cr.cohort_month)
                      <= cr.last_month
                 THEN cr.Month_1_Retention END
        ),
        (
            3,
            CASE WHEN DATEADD(MONTH, 3, cr.cohort_month)
                      <= cr.last_month
                 THEN cr.Month_3_Retention END
        ),
        (
            6,
            CASE WHEN DATEADD(MONTH, 6, cr.cohort_month)
                      <= cr.last_month
                 THEN cr.Month_6_Retention END
        )
    ) r(month_offset, retention_percentage)
    WHERE cr.cohort_size >= 100
)
SELECT
    month_offset,
    cohort_month,
    cohort_size,
    retention_percentage,
    DENSE_RANK() OVER (
        PARTITION BY month_offset
        ORDER BY retention_percentage DESC
    ) AS BestRank,
    DENSE_RANK() OVER (
        PARTITION BY month_offset
        ORDER BY retention_percentage ASC
    ) AS WorstRank
FROM RetentionComparison
WHERE retention_percentage IS NOT NULL
ORDER BY month_offset, BestRank;





-- =============================================
-- 4. OVERALL REPEAT PURCHASE ANALYSIS
-- =============================================

WITH CustomerOrderFrequency AS
(
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM dbo.olist_customers_dataset c
    INNER JOIN dbo.olist_orders_dataset o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)

-- 4.1 Overall repeat customer metrics

SELECT
    COUNT(*) AS TotalCustomers,

    SUM(CASE
        WHEN total_orders = 1 THEN 1
        ELSE 0
    END) AS OneTimeCustomers,

    SUM(CASE
        WHEN total_orders > 1 THEN 1
        ELSE 0
    END) AS RepeatCustomers,

    CAST(
        SUM(CASE
            WHEN total_orders > 1 THEN 1.0
            ELSE 0
        END) * 100.0 / COUNT(*)
        AS DECIMAL(6,2)
    ) AS RepeatCustomerPercentage

FROM CustomerOrderFrequency;


-- 4.2 Customer order frequency distribution

WITH CustomerOrderFrequency AS
(
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM dbo.olist_customers_dataset c
    INNER JOIN dbo.olist_orders_dataset o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)

SELECT
    total_orders,
    COUNT(*) AS NumberOfCustomers,
    CAST(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER ()
        AS DECIMAL(6,2)
    ) AS CustomerPercentage

FROM CustomerOrderFrequency
GROUP BY total_orders
ORDER BY total_orders;
