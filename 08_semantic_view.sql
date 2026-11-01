-- =====================================================
-- 08: SEMANTIC VIEW - describe the data in business language
-- This is what lets Cortex Analyst understand English questions.
-- FACTS = raw numbers, DIMENSIONS = things you group/filter by,
-- METRICS = calculations, SYNONYMS = other words people might use.
-- =====================================================

USE WAREHOUSE REVIEWS_WH;
USE SCHEMA REVIEWS_DB.PUBLIC;

CREATE OR REPLACE SEMANTIC VIEW REVIEWS_SEMANTIC
  TABLES (
    reviews AS REVIEWS_DB.PUBLIC.REVIEW_SCORES
      PRIMARY KEY (REVIEW_ID)
      WITH SYNONYMS = ('product reviews', 'reviews')
      COMMENT = 'One row per product review scored by the fake review detector'
  )
  FACTS (
    reviews.star_rating AS reviews.RATING          COMMENT = 'Star rating 1 to 5',
    reviews.suspicion   AS reviews.SUSPICION_SCORE COMMENT = 'Fake suspicion score 0 to 100'
  )
  DIMENSIONS (
    reviews.category AS reviews.CATEGORY
      WITH SYNONYMS = ('product category', 'product type')
      COMMENT = 'Product category such as Books_5 or Electronics_5',
    reviews.true_label AS IFF(reviews.LABEL = 'CG', 'fake', 'real')
      WITH SYNONYMS = ('ground truth', 'actual label')
      COMMENT = 'Whether the review is actually fake or real',
    reviews.sentiment AS reviews.SENTIMENT
      COMMENT = 'positive, negative, neutral or mixed',
    reviews.flag_status AS IFF(reviews.SUSPICION_SCORE >= 30, 'flagged', 'not flagged')
      WITH SYNONYMS = ('flagged', 'suspicious')
      COMMENT = 'flagged means the detector thinks the review is fake'
  )
  METRICS (
    reviews.review_count  AS COUNT(reviews.REVIEW_ID)                 COMMENT = 'Number of reviews',
    reviews.avg_rating    AS AVG(reviews.RATING)                      COMMENT = 'Average star rating',
    reviews.avg_suspicion AS AVG(reviews.SUSPICION_SCORE)             COMMENT = 'Average suspicion score',
    reviews.flagged_count AS COUNT_IF(reviews.SUSPICION_SCORE >= 30)  COMMENT = 'Number of reviews flagged as fake'
  )
  COMMENT = 'Fake review detector results';

-- Query it yourself: pick dimensions + metrics, no joins or GROUP BY needed
SELECT *
FROM SEMANTIC_VIEW(
    REVIEWS_SEMANTIC
    DIMENSIONS reviews.category
    METRICS reviews.review_count, reviews.flagged_count, reviews.avg_rating
)
ORDER BY FLAGGED_COUNT DESC;
