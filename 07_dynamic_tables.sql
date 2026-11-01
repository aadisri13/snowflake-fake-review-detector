-- =====================================================
-- 07: DYNAMIC TABLES - AUTO-SCORE NEW REVIEWS
-- New reviews land in INCOMING_REVIEWS.
-- Snowflake automatically keeps two dynamic tables up to date:
--   INCOMING_SIGNALS : runs the 3 AI signals on each new review (incremental = only new rows)
--   INCOMING_SCORED  : compares against the 2,000 known reviews + adds the points
-- =====================================================

USE WAREHOUSE REVIEWS_WH;
USE SCHEMA REVIEWS_DB.PUBLIC;

-- 1. The "inbox" where new reviews arrive
CREATE OR REPLACE TABLE INCOMING_REVIEWS (
    REVIEW_ID   NUMBER AUTOINCREMENT,
    CATEGORY    STRING,
    RATING      NUMBER,
    REVIEW_TEXT STRING,
    ARRIVED_AT  TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 2. Dynamic table #1: AI signals for every new review (refreshes within 1 minute)
CREATE OR REPLACE DYNAMIC TABLE INCOMING_SIGNALS
    TARGET_LAG = '1 minute'
    WAREHOUSE  = REVIEWS_WH
AS
SELECT REVIEW_ID, CATEGORY, RATING, REVIEW_TEXT, ARRIVED_AT,
       AI_SENTIMENT(REVIEW_TEXT):categories[0]:sentiment::STRING AS SENTIMENT,
       AI_CLASSIFY(
           REVIEW_TEXT,
           ['genuine customer review with specific personal experience',
            'generic or computer-generated fake review'],
           {'task_description': 'Decide whether this product review was written by a real customer or is a fake, generic, machine-generated review'}
       ):labels[0]::STRING AS AI_VERDICT,
       AI_EMBED('snowflake-arctic-embed-l-v2.0', REVIEW_TEXT) AS EMB
FROM INCOMING_REVIEWS;

-- 3. Dynamic table #2: duplicate check + final score (reads from dynamic table #1)
CREATE OR REPLACE DYNAMIC TABLE INCOMING_SCORED
    TARGET_LAG = '1 minute'
    WAREHOUSE  = REVIEWS_WH
AS
SELECT I.REVIEW_ID, I.CATEGORY, I.RATING, I.REVIEW_TEXT, I.ARRIVED_AT,
       I.SENTIMENT, I.AI_VERDICT,
       MAX(VECTOR_COSINE_SIMILARITY(I.EMB, R.EMB)) AS MAX_SIMILARITY,
       IFF(I.AI_VERDICT LIKE 'generic%', 50, 0) AS AI_POINTS,
       ROUND(30 * LEAST(1, GREATEST(0, (MAX_SIMILARITY - 0.6) / 0.3))) AS DUPLICATE_POINTS,
       IFF((I.RATING >= 4 AND I.SENTIMENT = 'negative')
        OR (I.RATING <= 2 AND I.SENTIMENT = 'positive')
        OR  I.SENTIMENT = 'neutral', 20, 0) AS SENTIMENT_POINTS,
       AI_POINTS + DUPLICATE_POINTS + SENTIMENT_POINTS AS SUSPICION_SCORE,
       IFF(SUSPICION_SCORE >= 30, 'LIKELY FAKE', 'LIKELY REAL') AS VERDICT
FROM INCOMING_SIGNALS I
CROSS JOIN REVIEW_EMBEDDINGS R
GROUP BY I.REVIEW_ID, I.CATEGORY, I.RATING, I.REVIEW_TEXT, I.ARRIVED_AT, I.SENTIMENT, I.AI_VERDICT;

-- 4. Simulate new reviews arriving
INSERT INTO INCOMING_REVIEWS (CATEGORY, RATING, REVIEW_TEXT) VALUES
 ('Books_5', 5, 'I enjoyed the people in this book and the writing. I will definitely read more by this author.'),
 ('Home_and_Kitchen_5', 2, 'Bought this kettle in March. The lid hinge cracked after six weeks and support never replied to my two emails, so I am returning it.');

-- 5. Don't want to wait a minute? Force a refresh now
ALTER DYNAMIC TABLE INCOMING_SCORED REFRESH;

-- 6. See the auto-scored reviews
SELECT VERDICT, SUSPICION_SCORE, AI_POINTS, DUPLICATE_POINTS, SENTIMENT_POINTS, REVIEW_TEXT
FROM INCOMING_SCORED
ORDER BY REVIEW_ID;

-- 7. Check how each dynamic table refreshes
--    (INCOMING_SIGNALS should say INCREMENTAL = AI only runs on NEW rows, which saves credits)
SHOW DYNAMIC TABLES LIKE 'INCOMING%';

-- =====================================================
-- AUTO-REFRESH DEMO (run these one at a time with Cmd+Enter)
-- a) insert one more review:
--    INSERT INTO INCOMING_REVIEWS (CATEGORY, RATING, REVIEW_TEXT) VALUES
--    ('Electronics_5', 5, 'Amazing product, totally worth it! Great quality and fast shipping. Highly recommend to everyone!');
-- b) wait ~2 minutes WITHOUT refreshing, then run step 6 again - it appears on its own.
-- =====================================================

-- 8. WHEN YOU'RE DONE: pause them so they don't use credits
-- ALTER DYNAMIC TABLE INCOMING_SCORED SUSPEND;
-- ALTER DYNAMIC TABLE INCOMING_SIGNALS SUSPEND;
-- (to start again: ALTER DYNAMIC TABLE ... RESUME;)
