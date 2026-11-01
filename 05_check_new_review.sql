-- =====================================================
-- 05: CHECK ANY NEW REVIEW - REAL OR FAKE?
-- Runs the same 3 signals + the same points as file 04,
-- on ONE review that you type in.
-- =====================================================

USE WAREHOUSE REVIEWS_WH;
USE SCHEMA REVIEWS_DB.PUBLIC;

-- 1. Type your review between the $$ signs, and its star rating (1-5)
SET NEW_REVIEW = $$I enjoyed the people in this book and the writing. I will definitely read more by this author.$$;
SET NEW_RATING = 5;

-- 2. Score it
WITH NEW AS (
    SELECT $NEW_REVIEW AS REVIEW_TEXT, $NEW_RATING AS RATING
),
E AS (
    SELECT AI_EMBED('snowflake-arctic-embed-l-v2.0', REVIEW_TEXT) AS EMB FROM NEW
),
SIGNALS AS (
    SELECT REVIEW_TEXT, RATING,
           AI_SENTIMENT(REVIEW_TEXT):categories[0]:sentiment::STRING AS SENTIMENT,
           AI_CLASSIFY(
               REVIEW_TEXT,
               ['genuine customer review with specific personal experience',
                'generic or computer-generated fake review'],
               {'task_description': 'Decide whether this product review was written by a real customer or is a fake, generic, machine-generated review'}
           ):labels[0]::STRING AS AI_VERDICT,
           -- closest match among the 2,000 reviews already embedded in file 02
           (SELECT MAX(VECTOR_COSINE_SIMILARITY(E.EMB, R.EMB))
              FROM E, REVIEW_EMBEDDINGS R) AS MAX_SIMILARITY
    FROM NEW
)
SELECT
    IFF(AI_POINTS + DUPLICATE_POINTS + SENTIMENT_POINTS >= 30, 'LIKELY FAKE', 'LIKELY REAL') AS VERDICT,
    AI_POINTS + DUPLICATE_POINTS + SENTIMENT_POINTS AS SUSPICION_SCORE,
    *
FROM (
    SELECT *,
           IFF(AI_VERDICT LIKE 'generic%', 50, 0) AS AI_POINTS,
           ROUND(30 * LEAST(1, GREATEST(0, (MAX_SIMILARITY - 0.6) / 0.3))) AS DUPLICATE_POINTS,
           IFF((RATING >= 4 AND SENTIMENT = 'negative')
            OR (RATING <= 2 AND SENTIMENT = 'positive')
            OR  SENTIMENT = 'neutral', 20, 0) AS SENTIMENT_POINTS
    FROM SIGNALS
);
