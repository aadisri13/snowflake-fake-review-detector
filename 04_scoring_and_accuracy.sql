-- =====================================================
-- 04: FINAL SUSPICION SCORE (0-100) + ACCURACY
--   AI judge says fake          -> up to 50 points
--   Near-duplicate of another   -> up to 30 points
--   Sentiment red flag          -> 20 points
-- =====================================================

USE WAREHOUSE REVIEWS_WH;
USE SCHEMA REVIEWS_DB.PUBLIC;

-- 1. Combine all three signals into one table
CREATE OR REPLACE TABLE REVIEW_SCORES AS
SELECT S.REVIEW_ID, S.CATEGORY, S.RATING, S.LABEL, S.REVIEW_TEXT,
       S.SENTIMENT, M.MAX_SIMILARITY, J.AI_VERDICT,
       IFF(J.AI_VERDICT LIKE 'generic%', 50, 0) AS AI_POINTS,
       ROUND(30 * LEAST(1, GREATEST(0, (M.MAX_SIMILARITY - 0.6) / 0.3))) AS DUPLICATE_POINTS,
       IFF((S.RATING >= 4 AND S.SENTIMENT = 'negative')
        OR (S.RATING <= 2 AND S.SENTIMENT = 'positive')
        OR  S.SENTIMENT = 'neutral', 20, 0) AS SENTIMENT_POINTS,
       AI_POINTS + DUPLICATE_POINTS + SENTIMENT_POINTS AS SUSPICION_SCORE
FROM REVIEWS_SCORED S
JOIN REVIEW_SIMILARITY M USING (REVIEW_ID)
JOIN REVIEW_AI_JUDGE   J USING (REVIEW_ID);

-- 2. Accuracy / precision / recall at different cut-offs
SELECT T.THRESHOLD,
       ROUND(100 * AVG(IFF((R.SUSPICION_SCORE >= T.THRESHOLD) = (R.LABEL = 'CG'), 1, 0)), 1) AS ACCURACY_PCT,
       ROUND(100 * COUNT_IF(R.SUSPICION_SCORE >= T.THRESHOLD AND R.LABEL = 'CG')
                 / NULLIF(COUNT_IF(R.SUSPICION_SCORE >= T.THRESHOLD), 0), 1)              AS PRECISION_PCT,
       ROUND(100 * COUNT_IF(R.SUSPICION_SCORE >= T.THRESHOLD AND R.LABEL = 'CG')
                 / COUNT_IF(R.LABEL = 'CG'), 1)                                            AS RECALL_PCT
FROM REVIEW_SCORES R
CROSS JOIN (SELECT COLUMN1 AS THRESHOLD FROM VALUES (30), (40), (50), (60), (70)) T
GROUP BY T.THRESHOLD
ORDER BY T.THRESHOLD;

-- 3. Shown rating vs "true" rating after removing flagged reviews (cut-off 30)
SELECT CATEGORY,
       ROUND(AVG(RATING), 2)                                   AS SHOWN_RATING,
       ROUND(AVG(IFF(SUSPICION_SCORE < 30, RATING, NULL)), 2)  AS TRUE_RATING,
       COUNT_IF(SUSPICION_SCORE >= 30)                         AS FLAGGED_REVIEWS
FROM REVIEW_SCORES
GROUP BY CATEGORY
ORDER BY FLAGGED_REVIEWS DESC;

-- 4. Top 20 most suspicious reviews, with the reason
SELECT SUSPICION_SCORE, LABEL, RATING, SENTIMENT,
       ROUND(MAX_SIMILARITY, 2) AS MAX_SIMILARITY, AI_VERDICT, REVIEW_TEXT
FROM REVIEW_SCORES
ORDER BY SUSPICION_SCORE DESC
LIMIT 20;
