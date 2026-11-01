#  Fake Review Detector on Snowflake

Flags fake, computer-generated product reviews using **Snowflake Cortex AI**, a model trained with **Snowpark**, auto-updating **dynamic tables**, and a **Streamlit** app where you can ask questions about the data in plain English (**Cortex Analyst**).

Everything runs inside Snowflake: no external APIs, and the data never leaves the platform.

---

##  Dataset

[Fake Reviews Dataset](https://www.kaggle.com/datasets/mexwell/fake-reviews-dataset) (Kaggle): **40,432 Amazon-style product reviews**, 50/50 split
- `OR`: original reviews written by real customers
- `CG`: computer-generated fake reviews

> Salminen, J., Kandpal, C., Kamel, A. M., Jung, S., & Jansen, B. J. (2022). *Creating and detecting fake reviews of online products.* Journal of Retailing and Consumer Services, 64, 102771.

The labels are only used at the end, to measure accuracy. The detector never sees them when scoring.

---

## Architecture

```
Kaggle CSV ──► RAW_REVIEWS (40,432 rows)
                    │  01  balanced 2,000-review sample
                    ▼
              REVIEWS_SAMPLE
        ┌───────────┼─────────────────┐
        ▼           ▼                 ▼
   01 AI_SENTIMENT  02 AI_EMBED +     03 AI_CLASSIFY
   (mood vs stars)  vector similarity (LLM judge)
        │           (copy-paste)      │
        └───────────┼─────────────────┘
                    ▼  04  combine into 0–100 suspicion score
              REVIEW_SCORES
        ┌───────────┼──────────────────────┐
        ▼           ▼                      ▼
  Snowpark ML    08 Semantic view ──►   Streamlit app
  (notebook)        Cortex Analyst      (chat · dashboard · checker)

New reviews ──► INCOMING_REVIEWS ──► 07 dynamic tables ──► auto-scored
```

---

##  How it works

| Signal | Snowflake feature | What it catches | Points |
|---|---|---|---|
| **AI judge** | `AI_CLASSIFY` (LLM) | Generic, machine-sounding text | 50 |
| **Near-duplicate** | `AI_EMBED` + `VECTOR_COSINE_SIMILARITY` | Reworded template reviews ("I *bought* this for my daughter" vs "I *purchased* this for my daughter") | up to 30 |
| **Sentiment red flag** | `AI_SENTIMENT` | Stars that contradict the text, or flat/neutral tone | 20 |

A review scoring **≥ 30** is flagged as likely fake.

---

##  Results (example run, 2,000-review sample)

| Approach | Accuracy | Notes |
|---|---|---|
| AI judge alone | ~71–73% | |
| Hand-weighted score (50/30/20) | ~70–74% | |
| **Snowpark-trained logistic regression** | **~72%** | Tested on 20% held-out reviews; beat the hand-picked weights on the same test set |

Other findings:
- **91%** of reviews whose star rating contradicted their text were fake (high precision, low recall)
- Fakes are far more often near-copies of another review than real ones
- Removing flagged reviews moves the average rating from **4.23★ → 4.13★** ("true rating")

Numbers shift slightly between runs because file 01 draws a random sample.

---

##  Files

| File | What it does |
|---|---|
| `01_setup_and_sentiment.sql` | Balanced sample + `AI_SENTIMENT` signal |
| `02_duplicates.sql` | Embeddings + similarity search for reworded copies |
| `03_ai_judge.sql` | LLM judge with `AI_CLASSIFY` + confusion matrix |
| `04_scoring_and_accuracy.sql` | Suspicion score, accuracy/precision/recall, "true rating" |
| `05_check_new_review.sql` | Score any single review you type in |
| `07_dynamic_tables.sql` | Auto-score new reviews (incremental refresh, so AI only runs on new rows) |
| `08_semantic_view.sql` | Business-friendly semantic view for Cortex Analyst |
| `fake_review_model.ipynb` | Snowpark feature engineering, model training/evaluation, ask-in-English with Cortex Analyst |
| `streamlit_app.py` | Streamlit in Snowflake app: 💬 chat with your data, 📊 dashboard, 🔍 live review checker |

---

##  How to run

1. Create a Snowflake account with Cortex AI enabled (Cortex AI functions are not available on card-free self-service trials)
2. Create a warehouse `REVIEWS_WH` and database `REVIEWS_DB`
3. Load the Kaggle CSV into `REVIEWS_DB.PUBLIC.RAW_REVIEWS` with columns `CATEGORY, RATING, LABEL, REVIEW_TEXT`
4. Run the SQL files in order: **01 → 02 → 03 → 04**, then **07** and **08**
5. Open `fake_review_model.ipynb` in a Snowflake Notebook and run all cells
6. Create a Streamlit app in Snowflake and paste in `streamlit_app.py`

---

##  Tech used

Snowflake SQL (CTEs, window functions, self-joins) · Cortex AI functions (`AI_SENTIMENT`, `AI_EMBED`, `AI_CLASSIFY`) · Vector similarity · Snowpark Python · scikit-learn · Dynamic tables · Semantic views · Cortex Analyst · Streamlit in Snowflake

##  Limitations

- Evaluated on one research dataset; real-world fake reviews may behave differently
- ~72% accuracy: some real reviews get flagged and some fakes slip through
- Signal weights and the 30-point cut-off were tuned on the same sample (the Snowpark model is evaluated on held-out data)


