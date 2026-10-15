"""Interactive Streamlit view of the fictional player movement dataset."""

from pathlib import Path

import pandas as pd
import streamlit as st

from synthetic_heatmap import (
    build_heatmap_figure,
    build_movement_animation,
    generate_player_paths,
    load_player_paths,
    save_player_paths,
)


APP_DIR = Path(__file__).parent
DATA_PATH = APP_DIR / "data" / "fake_player_paths.csv"


@st.cache_data
def get_data() -> pd.DataFrame:
    if not DATA_PATH.exists():
        save_player_paths(generate_player_paths(), DATA_PATH)
    return load_player_paths(DATA_PATH)


st.set_page_config(
    page_title="Synthetic player heatmap",
    page_icon="🗺️",
    layout="wide",
)

st.title("Synthetic player movement heatmap")
st.caption(
    "A fictional nine-player dataset on a map inspired by the iteration_3 "
    "diagram. No production telemetry is used."
)

data = get_data()
all_players = sorted(data["player_id"].unique().tolist())

with st.sidebar:
    st.header("Heatmap controls")
    selected_players = st.multiselect(
        "Players",
        options=all_players,
        default=all_players,
        format_func=lambda player_id: f"Player {player_id}",
    )
    minute_range = st.slider(
        "Elapsed minutes",
        min_value=0.0,
        max_value=10.0,
        value=(0.0, 10.0),
        step=0.5,
    )
    bins = st.slider(
        "Heatmap resolution",
        min_value=18,
        max_value=60,
        value=36,
        step=6,
    )
    show_paths = st.checkbox("Show individual paths", value=True)
    show_boxes = st.checkbox("Show area bounding boxes", value=True)
    trail_minutes = st.slider(
        "Animated trail length (minutes)",
        min_value=0.25,
        max_value=3.0,
        value=1.0,
        step=0.25,
    )

filtered = data[
    data["player_id"].isin(selected_players)
    & data["elapsed_minutes"].between(*minute_range)
]

player_count = int(filtered["player_id"].nunique())
non_spawn = filtered[filtered["name"] != "spawn"]
busiest_area = (
    non_spawn["name"].value_counts().index[0] if not non_spawn.empty else "None"
)
areas_visited = int(filtered.loc[filtered["name"] != "spawn", "name"].nunique())
window_label = f"{minute_range[0]:g}–{minute_range[1]:g} min"

metric_columns = st.columns(4)
metric_columns[0].metric("Players", player_count)
metric_columns[1].metric("Time window", window_label)
metric_columns[2].metric("Areas visited", areas_visited)
metric_columns[3].metric("Busiest non-spawn area", busiest_area)

view_mode = st.radio(
    "View",
    options=["Animated movement", "Position-density heatmap"],
    horizontal=True,
)
if view_mode == "Animated movement":
    figure = build_movement_animation(
        data,
        player_ids=selected_players,
        minute_range=minute_range,
        trail_minutes=trail_minutes,
        frame_interval_seconds=10,
        show_bounding_boxes=show_boxes,
    )
else:
    figure = build_heatmap_figure(
        data,
        player_ids=selected_players,
        minute_range=minute_range,
        bins=bins,
        show_paths=show_paths,
        show_bounding_boxes=show_boxes,
    )
st.plotly_chart(figure, width="stretch")

with st.expander("Inspect the fictional dataset"):
    st.dataframe(filtered, width="stretch", hide_index=True)
    st.download_button(
        "Download filtered CSV",
        data=filtered.to_csv(index=False).encode("utf-8"),
        file_name="filtered_fake_player_paths.csv",
        mime="text/csv",
    )

if view_mode == "Animated movement":
    st.info(
        "Interpretation: use Play or drag the elapsed-time slider. Bright "
        "outlined markers show current positions; coloured lines show each "
        "player's recent trail."
    )
else:
    st.info(
        "Interpretation: darker blue cells contain more sampled positions. "
        "This is a presence heatmap, not a measure of unique players, "
        "difficulty, or deaths."
    )
