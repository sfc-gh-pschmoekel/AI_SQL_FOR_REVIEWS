import streamlit as st
import pandas as pd
import altair as alt
import json
from datetime import timedelta

st.set_page_config(
    page_title="Sentiment Monitor",
    page_icon=":material/monitoring:",
    layout="wide",
)

conn = st.connection("snowflake")


@st.cache_data(ttl=timedelta(minutes=5))
def load_reviews():
    return conn.query("""
        SELECT
            REVIEW_ID, SOURCE_CHANNEL, LOCATION_NAME, REVIEW_DATE, RATING,
            REVIEW_TEXT, PRODUCT_NAME, REVIEWER_NAME, SENTIMENT_SCORE,
            SENTIMENT_LABEL, SENTIMENT_SCORE_1TO10, BRAND, COLOR_FAMILY,
            SHADE_MENTIONED, PRODUCT_TYPE, TOPICS, PRODUCT_ISSUE, SERVICE_ISSUE, AI_SUMMARY
        FROM CORTEX_AI_DEMO.SENTIMENT.REVIEW_DASHBOARD_V
        ORDER BY REVIEW_DATE DESC
    """)


df = load_reviews()

st.title(":material/monitoring: Sentiment Monitor")
st.caption("Real-time review intelligence across all channels, stores, and products")

with st.sidebar:
    st.header("Filters")
    channels = st.multiselect(
        "Channel",
        options=sorted(df["SOURCE_CHANNEL"].unique()),
        default=sorted(df["SOURCE_CHANNEL"].unique()),
    )
    sentiments = st.multiselect(
        "Sentiment",
        options=["Positive", "Neutral", "Negative"],
        default=["Positive", "Neutral", "Negative"],
    )
    product_types = st.multiselect(
        "Product type",
        options=sorted(df["PRODUCT_TYPE"].unique()),
        default=sorted(df["PRODUCT_TYPE"].unique()),
    )
    brands = st.multiselect(
        "Brand",
        options=sorted(df["BRAND"].dropna().unique()),
        default=sorted(df["BRAND"].dropna().unique()),
    )
    show_issues_only = st.toggle("Show issues only", value=False)

filtered = df[
    (df["SOURCE_CHANNEL"].isin(channels))
    & (df["SENTIMENT_LABEL"].isin(sentiments))
    & (df["PRODUCT_TYPE"].isin(product_types))
    & (df["BRAND"].isin(brands))
]
if show_issues_only:
    filtered = filtered[(filtered["PRODUCT_ISSUE"] == True) | (filtered["SERVICE_ISSUE"] == True)]

total = len(filtered)
avg_score = filtered["SENTIMENT_SCORE_1TO10"].mean() if total > 0 else 0
avg_rating = filtered["RATING"].mean() if total > 0 else 0
pos_pct = (filtered["SENTIMENT_LABEL"] == "Positive").sum() / max(total, 1) * 100
neg_count = (filtered["SENTIMENT_LABEL"] == "Negative").sum()
issue_count = ((filtered["PRODUCT_ISSUE"] == True) | (filtered["SERVICE_ISSUE"] == True)).sum()

with st.container(horizontal=True):
    st.metric("Total reviews", f"{total}", border=True)
    st.metric("Avg sentiment (1-10)", f"{avg_score:.1f}", border=True)
    st.metric("Avg star rating", f"{avg_rating:.1f}/5", border=True)
    st.metric("Positive %", f"{pos_pct:.0f}%", border=True)
    st.metric(":red[Negative reviews]", f"{neg_count}", border=True)
    st.metric(":orange[Flagged issues]", f"{issue_count}", border=True)


def explode_topics(dataframe):
    rows = []
    for _, row in dataframe.iterrows():
        raw = row["TOPICS"]
        if raw is None:
            continue
        if isinstance(raw, str):
            try:
                topics = json.loads(raw)
            except (json.JSONDecodeError, TypeError):
                continue
        elif isinstance(raw, list):
            topics = raw
        else:
            continue
        for t in topics:
            rows.append({"topic": t, "SENTIMENT_LABEL": row["SENTIMENT_LABEL"],
                         "SENTIMENT_SCORE_1TO10": row["SENTIMENT_SCORE_1TO10"],
                         "REVIEW_ID": row["REVIEW_ID"]})
    return pd.DataFrame(rows)


topics_df = explode_topics(filtered)

col1, col2 = st.columns(2)

with col1:
    with st.container(border=True):
        st.subheader("Sentiment by channel")
        channel_agg = (
            filtered.groupby("SOURCE_CHANNEL")
            .agg(avg_score=("SENTIMENT_SCORE_1TO10", "mean"), count=("REVIEW_ID", "count"))
            .reset_index()
        )
        chart = (
            alt.Chart(channel_agg).mark_bar()
            .encode(
                x=alt.X("SOURCE_CHANNEL:N", title="Channel", sort="-y"),
                y=alt.Y("avg_score:Q", title="Avg sentiment (1-10)", scale=alt.Scale(domain=[0, 10])),
                color=alt.Color("avg_score:Q", scale=alt.Scale(scheme="redyellowgreen", domain=[1, 10]), legend=None),
                tooltip=["SOURCE_CHANNEL", "avg_score", "count"],
            )
        )
        st.altair_chart(chart, use_container_width=True)

with col2:
    with st.container(border=True):
        st.subheader("Sentiment by salon location")
        loc_data = filtered[filtered["LOCATION_NAME"].notna() & (filtered["LOCATION_NAME"] != "")]
        if len(loc_data) > 0:
            loc_agg = (
                loc_data.groupby("LOCATION_NAME")
                .agg(avg_score=("SENTIMENT_SCORE_1TO10", "mean"), count=("REVIEW_ID", "count"))
                .reset_index()
            )
            chart2 = (
                alt.Chart(loc_agg).mark_bar()
                .encode(
                    x=alt.X("LOCATION_NAME:N", title="Location", sort="-y"),
                    y=alt.Y("avg_score:Q", title="Avg sentiment (1-10)", scale=alt.Scale(domain=[0, 10])),
                    color=alt.Color("avg_score:Q", scale=alt.Scale(scheme="redyellowgreen", domain=[1, 10]), legend=None),
                    tooltip=["LOCATION_NAME", "avg_score", "count"],
                )
            )
            st.altair_chart(chart2, use_container_width=True)
        else:
            st.info("No salon location data in current filter")

col3, col4 = st.columns(2)

with col3:
    with st.container(border=True):
        st.subheader("Sentiment by product type")
        pt_agg = (
            filtered.groupby("PRODUCT_TYPE")
            .agg(avg_score=("SENTIMENT_SCORE_1TO10", "mean"), count=("REVIEW_ID", "count"))
            .reset_index()
        )
        chart3 = (
            alt.Chart(pt_agg).mark_bar()
            .encode(
                x=alt.X("PRODUCT_TYPE:N", title="Product type", sort="-y"),
                y=alt.Y("avg_score:Q", title="Avg sentiment (1-10)", scale=alt.Scale(domain=[0, 10])),
                color=alt.Color("avg_score:Q", scale=alt.Scale(scheme="redyellowgreen", domain=[1, 10]), legend=None),
                tooltip=["PRODUCT_TYPE", "avg_score", "count"],
            )
        )
        st.altair_chart(chart3, use_container_width=True)

with col4:
    with st.container(border=True):
        st.subheader("Sentiment by shade")
        shade_data = filtered[filtered["SHADE_MENTIONED"] != "N/A"]
        if len(shade_data) > 0:
            shade_agg = (
                shade_data.groupby("SHADE_MENTIONED")
                .agg(avg_score=("SENTIMENT_SCORE_1TO10", "mean"), count=("REVIEW_ID", "count"))
                .reset_index()
            )
            chart4 = (
                alt.Chart(shade_agg).mark_bar()
                .encode(
                    x=alt.X("SHADE_MENTIONED:N", title="Shade", sort="-y"),
                    y=alt.Y("avg_score:Q", title="Avg sentiment (1-10)", scale=alt.Scale(domain=[0, 10])),
                    color=alt.Color("avg_score:Q", scale=alt.Scale(scheme="redyellowgreen", domain=[1, 10]), legend=None),
                    tooltip=["SHADE_MENTIONED", "avg_score", "count"],
                )
            )
            st.altair_chart(chart4, use_container_width=True)
        else:
            st.info("No shade data in current filter")

col5, col6 = st.columns(2)

with col5:
    with st.container(border=True):
        st.subheader("Sentiment by brand")
        brand_agg = (
            filtered.groupby("BRAND")
            .agg(avg_score=("SENTIMENT_SCORE_1TO10", "mean"), count=("REVIEW_ID", "count"))
            .reset_index()
        )
        chart5 = (
            alt.Chart(brand_agg).mark_bar()
            .encode(
                x=alt.X("BRAND:N", title="Brand", sort="-y"),
                y=alt.Y("avg_score:Q", title="Avg sentiment (1-10)", scale=alt.Scale(domain=[0, 10])),
                color=alt.Color("avg_score:Q", scale=alt.Scale(scheme="redyellowgreen", domain=[1, 10]), legend=None),
                tooltip=["BRAND", "avg_score", "count"],
            )
        )
        st.altair_chart(chart5, use_container_width=True)

with col6:
    with st.container(border=True):
        st.subheader("Sentiment by color family")
        cf_data = filtered[filtered["COLOR_FAMILY"].notna() & (filtered["COLOR_FAMILY"] != "N/A")]
        if len(cf_data) > 0:
            cf_agg = (
                cf_data.groupby("COLOR_FAMILY")
                .agg(avg_score=("SENTIMENT_SCORE_1TO10", "mean"), count=("REVIEW_ID", "count"))
                .reset_index()
            )
            chart6 = (
                alt.Chart(cf_agg).mark_bar()
                .encode(
                    x=alt.X("COLOR_FAMILY:N", title="Color family", sort="-y"),
                    y=alt.Y("avg_score:Q", title="Avg sentiment (1-10)", scale=alt.Scale(domain=[0, 10])),
                    color=alt.Color("avg_score:Q", scale=alt.Scale(scheme="redyellowgreen", domain=[1, 10]), legend=None),
                    tooltip=["COLOR_FAMILY", "avg_score", "count"],
                )
            )
            st.altair_chart(chart6, use_container_width=True)
        else:
            st.info("No color family data in current filter")

st.divider()
st.subheader(":material/topic: Topics mentioned across reviews")

if len(topics_df) > 0:
    col_t1, col_t2 = st.columns(2)

    with col_t1:
        with st.container(border=True):
            st.markdown("**Topic frequency**")
            topic_counts = topics_df.groupby("topic").agg(mentions=("REVIEW_ID", "count")).reset_index().sort_values("mentions", ascending=False)
            chart_t1 = (
                alt.Chart(topic_counts).mark_bar()
                .encode(
                    y=alt.Y("topic:N", sort="-x", title=None),
                    x=alt.X("mentions:Q", title="Mentions"),
                    color=alt.Color("mentions:Q", scale=alt.Scale(scheme="blues"), legend=None),
                    tooltip=["topic", "mentions"],
                )
            )
            st.altair_chart(chart_t1, use_container_width=True)

    with col_t2:
        with st.container(border=True):
            st.markdown("**Topic sentiment breakdown**")
            topic_sent = topics_df.groupby(["topic", "SENTIMENT_LABEL"]).size().reset_index(name="count")
            chart_t2 = (
                alt.Chart(topic_sent).mark_bar()
                .encode(
                    y=alt.Y("topic:N", sort="-x", title=None),
                    x=alt.X("count:Q", title="Reviews", stack="normalize"),
                    color=alt.Color("SENTIMENT_LABEL:N",
                                    scale=alt.Scale(domain=["Positive", "Neutral", "Negative"],
                                                    range=["#2ca02c", "#cccccc", "#d62728"]),
                                    title="Sentiment"),
                    tooltip=["topic", "SENTIMENT_LABEL", "count"],
                )
            )
            st.altair_chart(chart_t2, use_container_width=True)
else:
    st.info("No topic data available for current filters")

st.divider()
st.subheader(":material/build: Actionable improvements by topic")
st.caption("Negative reviews grouped by topic — what customers are telling you to fix")

neg_reviews = filtered[filtered["SENTIMENT_LABEL"].isin(["Negative"])]
neg_topics = explode_topics(neg_reviews)

if len(neg_topics) > 0:
    topic_priority = (
        neg_topics.groupby("topic")
        .agg(neg_count=("REVIEW_ID", "count"), avg_score=("SENTIMENT_SCORE_1TO10", "mean"))
        .reset_index()
        .sort_values("neg_count", ascending=False)
    )

    for _, trow in topic_priority.iterrows():
        topic_name = trow["topic"].replace("_", " ").title()
        with st.expander(f":red[{topic_name}] — {int(trow['neg_count'])} negative review(s), avg score {trow['avg_score']:.1f}/10"):
            relevant = neg_reviews[neg_reviews["TOPICS"].apply(
                lambda x: trow["topic"] in (json.loads(x) if isinstance(x, str) else (x if isinstance(x, list) else []))
                if x is not None else False
            )]
            for _, rev in relevant.iterrows():
                st.markdown(
                    f"- **{rev['PRODUCT_NAME']}** ({rev['SOURCE_CHANNEL']}"
                    + (f" / {rev['LOCATION_NAME']}" if pd.notna(rev["LOCATION_NAME"]) and rev["LOCATION_NAME"] else "")
                    + f") — {rev['RATING']}/5 stars"
                )
                st.caption(f"  {rev['AI_SUMMARY']}")
else:
    st.success("No negative reviews to action — keep it up!")

st.divider()
st.subheader(":material/priority_high: Priority action queue")
st.caption("Reviews requiring attention, ranked by severity")

alerts = filtered[
    (filtered["SENTIMENT_LABEL"] == "Negative")
    | (filtered["PRODUCT_ISSUE"] == True)
    | (filtered["SERVICE_ISSUE"] == True)
].copy()

if len(alerts) > 0:
    alerts["priority_score"] = (
        (10 - alerts["SENTIMENT_SCORE_1TO10"])
        + alerts["PRODUCT_ISSUE"].astype(int) * 3
        + alerts["SERVICE_ISSUE"].astype(int) * 2
    )
    alerts = alerts.sort_values("priority_score", ascending=False)

    for _, row in alerts.iterrows():
        flags = []
        if row.get("PRODUCT_ISSUE"):
            flags.append(":red-badge[Product issue]")
        if row.get("SERVICE_ISSUE"):
            flags.append(":orange-badge[Service issue]")
        if row["SENTIMENT_SCORE_1TO10"] <= 3:
            flags.append(":red-badge[Critical]")
        flag_str = " ".join(flags)

        with st.container(border=True):
            c1, c2 = st.columns([3, 1])
            with c1:
                st.markdown(
                    f"**{row['PRODUCT_NAME']}** — {row['SOURCE_CHANNEL']}"
                    + (f" / {row['LOCATION_NAME']}" if pd.notna(row["LOCATION_NAME"]) and row["LOCATION_NAME"] else "")
                )
                st.caption(row["AI_SUMMARY"])
                if flag_str:
                    st.markdown(flag_str)
            with c2:
                st.metric("Score", f"{row['SENTIMENT_SCORE_1TO10']}/10")
                st.caption(f"{row['RATING']}/5 stars")
else:
    st.success("No active alerts — all reviews look healthy!")

st.divider()
st.subheader(":material/table: Review detail")

st.dataframe(
    filtered[
        [
            "REVIEW_DATE", "SOURCE_CHANNEL", "LOCATION_NAME", "PRODUCT_NAME", "BRAND",
            "COLOR_FAMILY", "SHADE_MENTIONED", "RATING", "SENTIMENT_SCORE_1TO10",
            "SENTIMENT_LABEL", "AI_SUMMARY", "PRODUCT_ISSUE", "SERVICE_ISSUE",
        ]
    ],
    column_config={
        "REVIEW_DATE": st.column_config.DateColumn("Date"),
        "SOURCE_CHANNEL": "Channel",
        "LOCATION_NAME": "Location",
        "PRODUCT_NAME": "Product",
        "BRAND": "Brand",
        "COLOR_FAMILY": "Color family",
        "SHADE_MENTIONED": "Shade",
        "RATING": st.column_config.NumberColumn("Stars", format="%d/5"),
        "SENTIMENT_SCORE_1TO10": st.column_config.ProgressColumn("Sentiment", min_value=0, max_value=10),
        "SENTIMENT_LABEL": "Label",
        "AI_SUMMARY": "AI summary",
        "PRODUCT_ISSUE": st.column_config.CheckboxColumn("Product issue"),
        "SERVICE_ISSUE": st.column_config.CheckboxColumn("Service issue"),
    },
    hide_index=True,
    use_container_width=True,
)
