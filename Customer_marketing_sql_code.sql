CREATE DATABASE customer_marketing_analytics;
USE customer_marketing_analytics;
Select DATABASE();

SELECT COUNT(*) AS total_customers FROM customers;
SELECT * FROM customers LIMIT 10;
DESCRIBE customers;

SELECT COUNT(*) AS total_customers,
COUNT(gender) AS customers_with_gender,
COUNT(income) AS customers_with_income,
COUNT(*) - COUNT(gender) AS missing_gender,
COUNT(*) - COUNT(income) AS missing_income FROM customers;

SELECT MIN(age) AS minimum_age, MAX(age) AS maximum_age,
COUNT(*) AS age_118_count FROM customers WHERE age = 118;

SELECT COUNT(*) AS total_offers FROM offers;
SELECT * FROM offers;
select * from events;
SELECT COUNT(*) AS total_events FROM events;

SET GLOBAL local_infile = 1;
SHOW VARIABLES LIKE 'local_infile';

LOAD DATA LOCAL INFILE 'C:/Users/Nisha/Desktop/Nisha/Projects/Cafe+Rewards+Offers/events.csv'
INTO TABLE events
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(customer_id, event, value, time);

SELECT event, COUNT(*) AS event_count FROM events
GROUP BY event ORDER BY event_count DESC;

SELECT event, value FROM events LIMIT 20;
SELECT event, value FROM events
WHERE event IN ('transaction', 'offer viewed', 'offer completed') LIMIT 30;

SELECT event, value FROM events WHERE event = 'offer completed' LIMIT 10;

SELECT
    MIN(time) AS min_time,
    MAX(time) AS max_time,
    COUNT(DISTINCT time) AS unique_time_values
FROM events;

CREATE TABLE events_clean AS
SELECT
    customer_id,
    event,
    
    CASE
        WHEN event IN ('offer received', 'offer viewed')
        THEN TRIM(
            SUBSTRING_INDEX(
                SUBSTRING_INDEX(value, '''offer id'': ''', -1),
                '''',
                1
            )
        )
        
        WHEN event = 'offer completed'
        THEN TRIM(
            SUBSTRING_INDEX(
                SUBSTRING_INDEX(value, '''offer_id'': ''', -1),
                '''',
                1
            )
        )
        
        ELSE NULL
    END AS offer_id,

    CASE
        WHEN event = 'offer completed'
        THEN CAST(
            SUBSTRING_INDEX(
                SUBSTRING_INDEX(value, '''reward'': ', -1),
                '}',
                1
            ) AS DECIMAL(10,2)
        )
        ELSE NULL
    END AS reward,

    CASE
        WHEN event = 'transaction'
        THEN CAST(
            SUBSTRING_INDEX(
                SUBSTRING_INDEX(value, '''amount'': ', -1),
                '}',
                1
            ) AS DECIMAL(10,2)
        )
        ELSE NULL
    END AS amount,

    time AS time_days

FROM events;

SELECT * FROM events_clean LIMIT 20;
SELECT COUNT(*) AS total_clean_events FROM events_clean;
DESCRIBE events_clean;

SELECT * FROM customers LIMIT 10;
DESCRIBE customers;

SELECT COUNT(*) AS invalid_age FROM customers
WHERE age >= 100 OR age IS NULL;

SELECT COUNT(*) AS missing_gender
FROM customers
WHERE gender IS NULL OR TRIM(gender) = '';

SELECT COUNT(*) AS total_customers, COUNT(NULLIF(TRIM(income), '')) AS customers_with_income
FROM customers;

SELECT gender, COUNT(*) AS customer_count FROM customers
GROUP BY gender ORDER BY customer_count DESC;

CREATE TABLE customers_clean AS
SELECT
    customer_id,

    STR_TO_DATE(
        CAST(became_member_on AS CHAR),
        '%Y%m%d'
    ) AS member_since,

    CASE
        WHEN TRIM(gender) = '' OR gender IS NULL THEN 'Unknown'
        ELSE gender
    END AS gender,

    CASE
        WHEN age >= 100 OR age IS NULL THEN NULL
        ELSE age
    END AS age,

    CASE
        WHEN TRIM(income) = '' OR income IS NULL THEN NULL
        ELSE CAST(income AS DECIMAL(12,2))
    END AS income

FROM customers;

SELECT * FROM customers_clean LIMIT 10;
DESCRIBE customers_clean;
SELECT * FROM offers;
DESCRIBE offers;

CREATE TABLE offers_clean AS
SELECT
    offer_id,
    LOWER(TRIM(offer_type)) AS offer_type,
    difficulty,
    reward,
    duration,
    TRIM(channels) AS channels
FROM offers;
SELECT * FROM offers_clean;

SELECT
    COUNT(DISTINCT customer_id) AS total_customers,
    
    SUM(event = 'transaction') AS total_transactions,
    
    ROUND(
        SUM(CASE WHEN event = 'transaction' THEN amount ELSE 0 END),
        2
    ) AS total_spend,
    
    SUM(event = 'offer received') AS offers_received,
    
    SUM(event = 'offer viewed') AS offers_viewed,
    
    SUM(event = 'offer completed') AS offers_completed,
    
    ROUND(
        SUM(CASE WHEN event = 'offer completed' THEN reward ELSE 0 END),
        2
    ) AS total_rewards

FROM events_clean;

CREATE TABLE customer_360 AS
SELECT
    c.customer_id,
    c.member_since,
    c.gender,
    c.age,
    c.income,

    -- Sales
    COALESCE(SUM(
        CASE
            WHEN e.event = 'transaction' THEN e.amount
            ELSE 0
        END
    ), 0) AS total_spend,

    COALESCE(SUM(
        CASE
            WHEN e.event = 'transaction' THEN 1
            ELSE 0
        END
    ), 0) AS total_transactions,

    -- Marketing engagement
    COALESCE(SUM(
        CASE
            WHEN e.event = 'offer received' THEN 1
            ELSE 0
        END
    ), 0) AS offers_received,

    COALESCE(SUM(
        CASE
            WHEN e.event = 'offer viewed' THEN 1
            ELSE 0
        END
    ), 0) AS offers_viewed,

    COALESCE(SUM(
        CASE
            WHEN e.event = 'offer completed' THEN 1
            ELSE 0
        END
    ), 0) AS offers_completed,

    COALESCE(SUM(
        CASE
            WHEN e.event = 'offer completed' THEN e.reward
            ELSE 0
        END
    ), 0) AS total_rewards,

    -- Activity
    MAX(e.time_days) AS last_activity_day

FROM customers_clean c
LEFT JOIN events_clean e
    ON c.customer_id = e.customer_id

GROUP BY
    c.customer_id,
    c.member_since,
    c.gender,
    c.age,
    c.income;
    
    SELECT COUNT(*) AS total_customers
FROM customer_360;
SELECT * FROM customer_360 LIMIT 10;

-- =====================================================
-- CUSTOMER 360 DERIVED KPIs
-- =====================================================
ALTER TABLE customer_360
ADD COLUMN avg_transaction_value DECIMAL(12,2),
ADD COLUMN offer_view_rate DECIMAL(6,2),
ADD COLUMN offer_completion_rate DECIMAL(6,2);

ALTER TABLE customer_360
MODIFY customer_id VARCHAR(50) NOT NULL;
ALTER TABLE customer_360
ADD PRIMARY KEY (customer_id);

UPDATE customer_360
SET
    avg_transaction_value =
        CASE
            WHEN total_transactions > 0
            THEN ROUND(total_spend / total_transactions, 2)
            ELSE 0
        END,
    offer_view_rate =
        CASE
            WHEN offers_received > 0
            THEN ROUND((offers_viewed / offers_received) * 100, 2)
            ELSE 0
        END,
    offer_completion_rate =
        CASE
            WHEN offers_viewed > 0
            THEN ROUND((offers_completed / offers_viewed) * 100, 2)
            ELSE 0
        END;
        
       SELECT
    customer_id,
    total_spend,
    total_transactions,
    avg_transaction_value,
    offers_received,
    offers_viewed,
    offer_view_rate,
    offers_completed,
    offer_completion_rate
FROM customer_360
LIMIT 10;
SELECT
    MIN(total_spend) AS min_spend,
    MAX(total_spend) AS max_spend,
    AVG(total_spend) AS avg_spend,
    MIN(total_transactions) AS min_transactions,
    MAX(total_transactions) AS max_transactions,
    AVG(total_transactions) AS avg_transactions,
    MIN(offer_view_rate) AS min_view_rate,
    MAX(offer_view_rate) AS max_view_rate,
    AVG(offer_view_rate) AS avg_view_rate
FROM customer_360;

SELECT
    spend_quartile,
    COUNT(*) AS customers,
    MIN(total_spend) AS minimum_spend,
    MAX(total_spend) AS maximum_spend
FROM (
    SELECT
        customer_id,
        total_spend,
        NTILE(4) OVER (ORDER BY total_spend) AS spend_quartile
    FROM customer_360
) AS ranked_customers
GROUP BY spend_quartile
ORDER BY spend_quartile;

SELECT
    transaction_quartile,
    COUNT(*) AS customers,
    MIN(total_transactions) AS minimum_transactions,
    MAX(total_transactions) AS maximum_transactions
FROM (
    SELECT
        customer_id,
        total_transactions,
        NTILE(4) OVER (ORDER BY total_transactions) AS transaction_quartile
    FROM customer_360
) AS ranked_customers
GROUP BY transaction_quartile
ORDER BY transaction_quartile;

SELECT
    MIN(last_activity_day) AS earliest_activity,
    MAX(last_activity_day) AS latest_activity,
    AVG(last_activity_day) AS avg_activity_day
FROM customer_360;

SELECT
    activity_quartile,
    COUNT(*) AS customers,
    MIN(last_activity_day) AS earliest_activity,
    MAX(last_activity_day) AS latest_activity
FROM (
    SELECT
        customer_id,
        last_activity_day,
        NTILE(4) OVER (ORDER BY last_activity_day) AS activity_quartile
    FROM customer_360
) AS ranked_customers
GROUP BY activity_quartile
ORDER BY activity_quartile;

ALTER TABLE customer_360
ADD COLUMN customer_segment VARCHAR(30);

UPDATE customer_360
SET customer_segment =
    CASE

        -- High Value: top spend + top transaction frequency
        WHEN total_spend >= 148.79
             AND total_transactions >= 11
        THEN 'High Value'

        -- Loyal: strong transaction frequency + meaningful spending
        WHEN total_transactions >= 7
             AND total_spend >= 69.41
        THEN 'Loyal'

        -- At Risk: previously active/value-generating customers
        -- but currently in the lowest activity quartile
        WHEN last_activity_day < 606
             AND (total_spend >= 69.41 OR total_transactions >= 7)
        THEN 'At Risk'

        -- Engaged: strong offer interaction
        WHEN offer_view_rate >= 76
             AND offer_completion_rate >= 50
        THEN 'Engaged'

        -- Low Engagement: low value + low transaction activity
        WHEN total_spend < 21.82
             AND total_transactions <= 4
             AND offer_view_rate < 76
        THEN 'Low Engagement'

        -- Remaining customers with some activity/value
        ELSE 'Emerging'

    END;
    
    SELECT
    customer_segment,
    COUNT(*) AS customer_count
FROM customer_360
GROUP BY customer_segment
ORDER BY customer_count DESC;

-- =====================================================
-- MARKETING OFFER PERFORMANCE
-- =====================================================

SELECT o.offer_id,o.offer_type,o.difficulty,o.reward,o.duration,o.channels,
COUNT(CASE
        WHEN e.event = 'offer received' THEN 1
    END) AS offers_received,
    COUNT(CASE
        WHEN e.event = 'offer viewed' THEN 1
    END) AS offers_viewed,

    COUNT(CASE
        WHEN e.event = 'offer completed' THEN 1
    END) AS offers_completed,
ROUND(
        COUNT(CASE
            WHEN e.event = 'offer viewed' THEN 1
        END)
        /
        NULLIF(
            COUNT(CASE
                WHEN e.event = 'offer received' THEN 1
            END), 0
        ) * 100,
        2
    ) AS view_rate,

    ROUND(
        COUNT(CASE
            WHEN e.event = 'offer completed' THEN 1
        END)
        /
        NULLIF(
            COUNT(CASE
                WHEN e.event = 'offer viewed' THEN 1
            END), 0
        ) * 100,
        2
    ) AS completion_rate

FROM offers_clean o

LEFT JOIN events_clean e ON o.offer_id = e.offer_id
GROUP BY o.offer_id,o.offer_type,o.difficulty,o.reward,o.duration,o.channels
ORDER BY completion_rate DESC;

-- =====================================================
-- FINAL TABLEAU DATASET: OFFER PERFORMANCE
-- =====================================================

CREATE TABLE offer_performance AS
SELECT
    o.offer_id,
    o.offer_type,
    o.difficulty,
    o.reward,
    o.duration,
    o.channels,

    COUNT(CASE WHEN e.event = 'offer received' THEN 1 END) AS offers_received,

    COUNT(CASE WHEN e.event = 'offer viewed' THEN 1 END) AS offers_viewed,

    COUNT(CASE WHEN e.event = 'offer completed' THEN 1 END) AS offers_completed,

    ROUND(
        COUNT(CASE WHEN e.event = 'offer viewed' THEN 1 END)
        / NULLIF(
            COUNT(CASE WHEN e.event = 'offer received' THEN 1 END), 0
        ) * 100,
        2
    ) AS view_rate,

    ROUND(
        COUNT(CASE WHEN e.event = 'offer completed' THEN 1 END)
        / NULLIF(
            COUNT(CASE WHEN e.event = 'offer viewed' THEN 1 END), 0
        ) * 100,
        2
    ) AS completion_rate

FROM offers_clean o

LEFT JOIN events_clean e ON o.offer_id = e.offer_id
GROUP BY o.offer_id,o.offer_type,o.difficulty,o.reward,o.duration,o.channels;
