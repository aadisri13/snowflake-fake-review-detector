-- =====================================================
-- 03: AI JUDGE
-- An LLM reads each review and decides: genuine or fake/generic?
-- =====================================================

USE WAREHOUSE REVIEWS_WH;
USE SCHEMA REVIEWS_DB.PUBLIC;

-- 1. SIGNAL 3: let AI_CLASSIFY label every review
CREATE OR REPLACE TABLE REVIEW_AI_JUDGE AS
SELECT REVIEW_ID,
       AI_CLASSIFY(
           REVIEW_TEXT,
           ['genuine customer review with specific personal experience',
            'generic or computer-generated fake review'],
           {'task_description': 'Decide whether this product review was written by a real customer or is a fake, generic, machine-generated review'}
       ):labels[0]::STRING AS AI_VERDICT
FROM REVIEWS_SAMPLE;

-- 2. Confusion matrix: AI verdict vs the real answer
SELECT J.AI_VERDICT, S.LABEL, COUNT(*) AS N
FROM REVIEW_AI_JUDGE J
JOIN REVIEWS_SAMPLE S USING (REVIEW_ID)
GROUP BY ALL
ORDER BY 1, 2;

-- 3. Accuracy of the AI judge on its own
SELECT ROUND(100 * AVG(IFF((J.AI_VERDICT LIKE 'generic%') = (S.LABEL = 'CG'), 1, 0)), 1) AS AI_JUDGE_ACCURACY_PCT
FROM REVIEW_AI_JUDGE J
JOIN REVIEWS_SAMPLE S USING (REVIEW_ID);
