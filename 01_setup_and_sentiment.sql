-- =====================================================
-- 01: SETUP + SENTIMENT
-- Fake Review Detector on Snowflake
-- =====================================================

USE WAREHOUSE REVIEWS_WH;
USE SCHEMA REVIEWS_DB.PUBLIC;

-- 1. Check the raw data (expect 20,216 CG + 20,216 OR)
SELECT LABEL, COUNT(*) AS TOTAL
FROM RAW_REVIEWS
GROUP BY LABEL;

-- 2. Balanced 2,000-row sample (1000 fake + 1000 real), each with an ID
CREATE OR REPLACE TABLE REVIEWS_SAMPLE AS
SELECT ROW_NUMBER() OVER (ORDER BY RANDOM()) AS REVIEW_ID, *
FROM (
    (SELECT * FROM RAW_REVIEWS WHERE LABEL = 'CG' ORDER BY RANDOM() LIMIT 1000)
    UNION ALL
    (SELECT * FROM RAW_REVIEWS WHERE LABEL = 'OR' ORDER BY RANDOM() LIMIT 1000)
);

-- 3. SIGNAL 1: AI sentiment (positive / negative / neutral / mixed)
CREATE OR REPLACE TABLE REVIEWS_SCORED AS
SELECT *,
       AI_SENTIMENT(REVIEW_TEXT):categories[0]:sentiment::STRING AS SENTIMENT
FROM REVIEWS_SAMPLE;

-- 4. How does sentiment differ between fake (CG) and real (OR)?
SELECT SENTIMENT, LABEL, COUNT(*) AS N
FROM REVIEWS_SCORED
GROUP BY ALL
ORDER BY 1, 2;

-- 5. Rating vs text mismatch (5 stars but negative text, or the opposite)
SELECT RATING, LABEL, SENTIMENT, REVIEW_TEXT
FROM REVIEWS_SCORED
WHERE (RATING >= 4 AND SENTIMENT = 'negative')
   OR (RATING <= 2 AND SENTIMENT = 'positive');
