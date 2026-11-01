# =====================================================
# Fake Review Detector - Streamlit in Snowflake
# Tab 1: chat with your data in English (Cortex Analyst + semantic view)
# Tab 2: dashboard of the detector's results
# Tab 3: check any new review live
# =====================================================
import json

import pandas as pd
import requests
import streamlit as st

st.set_page_config(page_title="Fake Review Detector", page_icon="🕵️", layout="wide")

# Connect to Snowflake (the app runs inside Snowflake, so no password needed)
conn = st.connection("snowflake")
session = conn.session()
session.use_warehouse("REVIEWS_WH")
session.use_database("REVIEWS_DB")
session.use_schema("PUBLIC")

SEMANTIC_VIEW = "REVIEWS_DB.PUBLIC.REVIEWS_SEMANTIC"
JUDGE_LABELS = "['genuine customer review with specific personal experience', 'generic or computer-generated fake review']"
JUDGE_TASK = "{'task_description': 'Decide whether this product review was written by a real customer or is a fake, generic, machine-generated review'}"

st.title("🕵️ Fake Review Detector")
st.caption("Snowflake Cortex AI + Snowpark: sentiment, embeddings and an LLM judge combined into one suspicion score")

chat_tab, dash_tab, check_tab = st.tabs(["💬 Ask your data", "📊 Dashboard", "🔍 Check a review"])


# =====================================================
# TAB 1 - Cortex Analyst chat
# =====================================================
def call_analyst(messages):
    """Send the conversation to the Cortex Analyst REST API and return its reply."""
    body = {"messages": messages, "semantic_view": SEMANTIC_VIEW}
    r = requests.post(
        f"https://{session.connection.host}/api/v2/cortex/analyst/message",
        headers={
            "Authorization": f'Snowflake Token="{session.connection.rest.token}"',
            "Content-Type": "application/json",
        },
        json=body,
        timeout=60,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"Cortex Analyst error {r.status_code}: {r.text[:500]}")
    return r.json()["message"]


def show_message(content, key):
    """Draw one Cortex Analyst message: its explanation, the SQL, and the result."""
    for i, part in enumerate(content):
        if part["type"] == "text":
            st.markdown(part["text"])
        elif part["type"] == "suggestions":
            st.markdown("**Try asking:**")
            for j, s in enumerate(part["suggestions"]):
                if st.button(s, key=f"sugg_{key}_{i}_{j}"):
                    st.session_state.pending = s
        elif part["type"] == "sql":
            with st.expander("🧾 SQL it wrote"):
                st.code(part["statement"], language="sql")
            df = session.sql(part["statement"]).to_pandas()
            st.dataframe(df, use_container_width=True)
            # simple auto-chart: one text column + one number column -> bar chart
            if len(df.columns) == 2 and len(df) > 1 and pd.api.types.is_numeric_dtype(df.iloc[:, 1]):
                st.bar_chart(df.set_index(df.columns[0]))


with chat_tab:
    st.markdown("Ask questions about the scored reviews in plain English. "
                "Cortex Analyst turns them into SQL using the semantic view.")
    if "messages" not in st.session_state:
        st.session_state.messages = []

    if st.button("🔄 New chat"):
        st.session_state.messages = []

    # replay the conversation so far
    for n, msg in enumerate(st.session_state.messages):
        with st.chat_message("user" if msg["role"] == "user" else "assistant"):
            if msg["role"] == "user":
                st.markdown(msg["content"][0]["text"])
            else:
                show_message(msg["content"], key=n)

    question = st.chat_input("e.g. Which category has the most flagged reviews?")
    question = question or st.session_state.pop("pending", None)
    if question:
        st.session_state.messages.append(
            {"role": "user", "content": [{"type": "text", "text": question}]})
        with st.chat_message("user"):
            st.markdown(question)
        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                try:
                    reply = call_analyst(st.session_state.messages)
                    st.session_state.messages.append({"role": "analyst", "content": reply["content"]})
                    show_message(reply["content"], key=len(st.session_state.messages))
                except Exception as e:
                    st.session_state.messages.pop()  # drop the failed question
                    st.error(str(e))


# =====================================================
# TAB 2 - Dashboard
# =====================================================
@st.cache_data(ttl=600)
def load_scores():
    return session.table("REVIEW_SCORES").to_pandas()


with dash_tab:
    df = load_scores()
    c_left, c_right = st.columns(2)
    threshold = c_left.slider("Flag as fake if score ≥", 0, 100, 30, 10)
    category = c_right.selectbox("Category", ["All"] + sorted(df["CATEGORY"].unique().tolist()))

    view = df if category == "All" else df[df["CATEGORY"] == category]
    flagged = view["SUSPICION_SCORE"] >= threshold
    is_fake = view["LABEL"] == "CG"

    accuracy = (flagged == is_fake).mean() * 100
    precision = (flagged & is_fake).sum() / max(flagged.sum(), 1) * 100
    shown = view["RATING"].mean()
    true = view.loc[~flagged, "RATING"].mean()

    m1, m2, m3, m4, m5 = st.columns(5)
    m1.metric("Reviews", len(view))
    m2.metric("Flagged", int(flagged.sum()))
    m3.metric("Accuracy", f"{accuracy:.1f}%")
    m4.metric("Precision", f"{precision:.1f}%")
    m5.metric("True rating", f"{true:.2f} ★", f"{true - shown:+.2f} vs shown {shown:.2f}")

    st.subheader("Suspicion score: fake vs real")
    dist = (view.assign(TYPE=view["LABEL"].map({"CG": "Fake", "OR": "Real"}))
                .groupby(["SUSPICION_SCORE", "TYPE"]).size().unstack(fill_value=0))
    st.bar_chart(dist)

    st.subheader("Most suspicious reviews")
    cols = ["SUSPICION_SCORE", "AI_POINTS", "DUPLICATE_POINTS", "SENTIMENT_POINTS",
            "RATING", "SENTIMENT", "LABEL", "REVIEW_TEXT"]
    st.dataframe(view.sort_values("SUSPICION_SCORE", ascending=False)[cols].head(50),
                 use_container_width=True)


# =====================================================
# TAB 3 - Check a new review live
# =====================================================
with check_tab:
    text = st.text_area("Paste any product review")
    rating = st.slider("Its star rating", 1, 5, 5)

    if st.button("Analyze", type="primary") and text.strip():
        with st.spinner("Asking Cortex..."):
            row = session.sql(f"""
                WITH NEW AS (SELECT ? AS T),
                     E   AS (SELECT AI_EMBED('snowflake-arctic-embed-l-v2.0', T) AS EMB FROM NEW)
                SELECT
                  AI_SENTIMENT(T):categories[0]:sentiment::STRING AS SENTIMENT,
                  AI_CLASSIFY(T, {JUDGE_LABELS}, {JUDGE_TASK}):labels[0]::STRING AS AI_VERDICT,
                  (SELECT MAX(VECTOR_COSINE_SIMILARITY(E.EMB, R.EMB))
                     FROM E, REVIEW_EMBEDDINGS R) AS MAX_SIMILARITY
                FROM NEW
            """, params=[text]).collect()[0]

        # same points system as file 04
        ai_pts = 50 if row["AI_VERDICT"].startswith("generic") else 0
        dup_pts = round(30 * min(1, max(0, (row["MAX_SIMILARITY"] - 0.6) / 0.3)))
        s = row["SENTIMENT"]
        sent_pts = 20 if ((rating >= 4 and s == "negative") or
                          (rating <= 2 and s == "positive") or s == "neutral") else 0
        score = ai_pts + dup_pts + sent_pts

        if score >= 30:
            st.error(f"🚩 Likely FAKE: suspicion score {score}/100")
        else:
            st.success(f"✅ Likely REAL: suspicion score {score}/100")
        st.write(f"- **AI judge:** {row['AI_VERDICT']} → {ai_pts} pts")
        st.write(f"- **Closest match among known reviews:** {row['MAX_SIMILARITY']:.2f} similarity → {dup_pts} pts")
        st.write(f"- **Sentiment:** {s} with {rating}★ → {sent_pts} pts")
