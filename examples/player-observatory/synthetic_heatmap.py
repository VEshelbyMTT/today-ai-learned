"""Generate and visualize fictional player paths on a diagram-inspired map."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd
import plotly.graph_objects as go


@dataclass(frozen=True, slots=True)
class Area:
    """Define an immutable fictional map area in X/Y map units.

    Attributes:
        name: Identifier used by player samples and route connections.
        x_min: Lower X bound of the area's bounding box.
        x_max: Upper X bound of the area's bounding box.
        y_min: Lower Y bound of the area's bounding box.
        y_max: Upper Y bound of the area's bounding box.
        shape: Plotly shape type used to draw the area, such as rect or circle.
    """

    name: str
    x_min: float
    x_max: float
    y_min: float
    y_max: float
    shape: str = "rect"

    @property
    def center(self) -> tuple[float, float]:
        """Return the bounding-box midpoint as an (x, y) coordinate pair."""
        return (
            (self.x_min + self.x_max) / 2,
            (self.y_min + self.y_max) / 2,
        )


AREAS = (
    Area("spawn", 46, 54, 26, 34, "circle"),
    Area("area1", 34, 46, 39, 46),
    Area("area2", 24, 34, 50, 56),
    Area("area3", 44, 56, 50, 56),
    Area("area4", 14, 25, 38, 44),
    Area("area5", 64, 79, 33, 40),
    Area("area6", 66, 76, 47, 53),
    Area("area7", 82, 92, 43, 49),
    Area("area8", 88, 99, 28, 35),
    Area("area9", 28, 41, 27, 34),
    Area("area10", 9, 24, 17, 27),
    Area("area11", 1, 20, 6, 12),
    Area("area12", 42, 62, 14, 21),
    Area("area13", 30, 37, 14, 20),
    Area("area14", 38, 47, 4, 10),
    Area("area15", 51, 58, 3, 9),
    Area("area16", 64, 72, 6, 12),
    Area("area17", 70, 83, 18, 24),
)

CONNECTIONS = (
    ("spawn", "area1"),
    ("spawn", "area5"),
    ("spawn", "area9"),
    ("spawn", "area12"),
    ("area1", "area2"),
    ("area1", "area3"),
    ("area1", "area4"),
    ("area5", "area6"),
    ("area5", "area7"),
    ("area5", "area8"),
    ("area9", "area10"),
    ("area10", "area11"),
    ("area12", "area13"),
    ("area12", "area14"),
    ("area12", "area15"),
    ("area12", "area16"),
    ("area12", "area17"),
)

REQUIRED_COLUMNS = (
    "player_id",
    "timestamp",
    "elapsed_minutes",
    "x",
    "y",
    "bbox_x_min",
    "bbox_x_max",
    "bbox_y_min",
    "bbox_y_max",
    "name",
    "movement_state",
    "target_name",
)

PLAYER_COLORS = (
    "#332288",
    "#88CCEE",
    "#44AA99",
    "#117733",
    "#999933",
    "#DDCC77",
    "#CC6677",
    "#882255",
    "#AA4499",
)

HEATMAP_SCALE = (
    (0.00, "rgba(247,251,255,0.00)"),
    (0.20, "rgba(198,219,239,0.35)"),
    (0.45, "rgba(107,174,214,0.60)"),
    (0.70, "rgba(33,113,181,0.80)"),
    (1.00, "rgba(8,48,107,0.96)"),
)


def area_frame() -> pd.DataFrame:
    """Return the fictional map layout as a pandas DataFrame."""
    return pd.DataFrame(asdict(area) for area in AREAS)


def _adjacency() -> dict[str, list[str]]:
    graph = {area.name: [] for area in AREAS}
    for source, target in CONNECTIONS:
        graph[source].append(target)
        graph[target].append(source)
    return graph


def _movement_bounds(source: Area, target: Area) -> tuple[float, float, float, float]:
    padding = 1.0
    return (
        min(source.x_min, target.x_min) - padding,
        max(source.x_max, target.x_max) + padding,
        min(source.y_min, target.y_min) - padding,
        max(source.y_max, target.y_max) + padding,
    )


def generate_player_paths(
    *,
    player_count: int = 9,
    duration_minutes: int = 10,
    sample_interval_seconds: int = 5,
    seed: int = 20261002,
) -> pd.DataFrame:
    """Generate deterministic fictional player positions for a small demo."""
    if not 1 <= player_count <= 9:
        raise ValueError("player_count must be between 1 and 9")
    if not 1 <= duration_minutes <= 10:
        raise ValueError("duration_minutes must be between 1 and 10")
    if sample_interval_seconds <= 0:
        raise ValueError("sample_interval_seconds must be positive")

    area_by_name = {area.name: area for area in AREAS}
    graph = _adjacency()
    start_time = datetime(2026, 10, 2, 12, 0, tzinfo=timezone.utc)
    total_seconds = duration_minutes * 60
    sample_seconds = range(0, total_seconds + 1, sample_interval_seconds)
    records: list[dict[str, object]] = []

    for player_id in range(1, player_count + 1):
        rng = np.random.default_rng(seed + player_id)
        route_affinity = {
            area.name: float(rng.lognormal(mean=0.0, sigma=0.4))
            for area in AREAS
        }
        current_name = "spawn"
        previous_name: str | None = None
        target_name: str | None = None
        x, y = area_by_name[current_name].center
        dwell_seconds = int(rng.integers(15, 46))
        walking_speed = float(rng.uniform(0.12, 0.20))

        for step, elapsed_seconds in enumerate(sample_seconds):
            if step > 0:
                if target_name is None and dwell_seconds <= 0:
                    candidates = graph[current_name]
                    alternatives = [
                        name for name in candidates if name != previous_name
                    ]
                    choices = alternatives or candidates
                    weights = np.array(
                        [route_affinity[name] for name in choices],
                        dtype=float,
                    )
                    target_name = str(
                        rng.choice(choices, p=weights / weights.sum())
                    )
                    walking_speed = float(rng.uniform(0.12, 0.20))

                if target_name is None:
                    area = area_by_name[current_name]
                    center_x, center_y = area.center
                    x += (center_x - x) * 0.18 + float(rng.normal(0, 0.10))
                    y += (center_y - y) * 0.18 + float(rng.normal(0, 0.10))
                    x = float(np.clip(x, area.x_min + 0.25, area.x_max - 0.25))
                    y = float(np.clip(y, area.y_min + 0.25, area.y_max - 0.25))
                    dwell_seconds -= sample_interval_seconds
                else:
                    destination = area_by_name[target_name]
                    destination_x, destination_y = destination.center
                    delta_x = destination_x - x
                    delta_y = destination_y - y
                    remaining_distance = float(np.hypot(delta_x, delta_y))
                    step_distance = walking_speed * sample_interval_seconds

                    if remaining_distance <= step_distance:
                        x, y = destination.center
                        previous_name, current_name = current_name, target_name
                        target_name = None
                        dwell_seconds = int(rng.integers(15, 46))
                    else:
                        x += delta_x / remaining_distance * step_distance
                        y += delta_y / remaining_distance * step_distance

            area = area_by_name[current_name]
            if target_name is None:
                bounds = (
                    area.x_min,
                    area.x_max,
                    area.y_min,
                    area.y_max,
                )
                movement_state = "dwelling"
                target_value = current_name
            else:
                bounds = _movement_bounds(area, area_by_name[target_name])
                movement_state = "walking"
                target_value = target_name

            records.append(
                {
                    "player_id": player_id,
                    "timestamp": start_time + timedelta(seconds=elapsed_seconds),
                    "elapsed_minutes": elapsed_seconds / 60,
                    "x": round(x, 3),
                    "y": round(y, 3),
                    "bbox_x_min": bounds[0],
                    "bbox_x_max": bounds[1],
                    "bbox_y_min": bounds[2],
                    "bbox_y_max": bounds[3],
                    "name": current_name,
                    "movement_state": movement_state,
                    "target_name": target_value,
                }
            )

    result = pd.DataFrame.from_records(records, columns=REQUIRED_COLUMNS)
    result["timestamp"] = pd.to_datetime(result["timestamp"], utc=True)
    return result


def validate_player_paths(data: pd.DataFrame) -> None:
    """Raise ValueError when the generated data violates the demo contract."""
    missing = set(REQUIRED_COLUMNS).difference(data.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")
    if data.empty:
        raise ValueError("The player path dataset is empty")
    if not data["player_id"].between(1, 9).all():
        raise ValueError("player_id values must be between 1 and 9")

    starts = (
        data.sort_values(["player_id", "timestamp"])
        .groupby("player_id", as_index=False)
        .first()
    )
    if not starts["name"].eq("spawn").all():
        raise ValueError("Every player path must start at spawn")

    within_x = data["x"].between(data["bbox_x_min"], data["bbox_x_max"])
    within_y = data["y"].between(data["bbox_y_min"], data["bbox_y_max"])
    if not (within_x & within_y).all():
        raise ValueError("Every x/y position must be inside its bounding box")

    ordered = data.sort_values(["player_id", "timestamp"]).copy()
    ordered["step_distance"] = np.hypot(
        ordered.groupby("player_id")["x"].diff(),
        ordered.groupby("player_id")["y"].diff(),
    )
    if ordered["step_distance"].dropna().gt(1.05).any():
        raise ValueError("A player path contains an unrealistic movement jump")


def save_player_paths(data: pd.DataFrame, output_path: str | Path) -> Path:
    """Validate and write the synthetic dataset to CSV."""
    validate_player_paths(data)
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data.to_csv(path, index=False, date_format="%Y-%m-%dT%H:%M:%SZ")
    return path


def load_player_paths(path: str | Path) -> pd.DataFrame:
    """Load and validate the synthetic CSV."""
    data = pd.read_csv(path, parse_dates=["timestamp"])
    validate_player_paths(data)
    return data


def _add_map_design(
    figure: go.Figure,
    *,
    show_bounding_boxes: bool,
) -> None:
    area_by_name = {area.name: area for area in AREAS}
    for source_name, target_name in CONNECTIONS:
        source_x, source_y = area_by_name[source_name].center
        target_x, target_y = area_by_name[target_name].center
        figure.add_shape(
            type="line",
            x0=source_x,
            y0=source_y,
            x1=target_x,
            y1=target_y,
            line={"color": "#AAB4BE", "width": 2},
            layer="below",
        )

    if not show_bounding_boxes:
        return

    for area in AREAS:
        figure.add_shape(
            type=area.shape,
            x0=area.x_min,
            x1=area.x_max,
            y0=area.y_min,
            y1=area.y_max,
            line={"color": "#354A5F", "width": 1.5},
            fillcolor="rgba(231,234,237,0.22)",
            layer="above",
        )
        center_x, center_y = area.center
        figure.add_annotation(
            x=center_x,
            y=center_y,
            text=f"<b>{area.name}</b>",
            showarrow=False,
            font={"color": "#1F2933", "size": 11},
            bgcolor="rgba(255,255,255,0.72)",
            borderpad=2,
        )


def build_heatmap_figure(
    data: pd.DataFrame,
    *,
    player_ids: Iterable[int] | None = None,
    minute_range: tuple[float, float] = (0.0, 10.0),
    bins: int = 36,
    show_paths: bool = True,
    show_bounding_boxes: bool = True,
) -> go.Figure:
    """Build a density heatmap over the diagram-inspired fictional map."""
    validate_player_paths(data)
    selected_ids = (
        sorted(data["player_id"].unique().tolist())
        if player_ids is None
        else sorted(set(player_ids))
    )
    start_minute, end_minute = minute_range
    filtered = data[
        data["player_id"].isin(selected_ids)
        & data["elapsed_minutes"].between(start_minute, end_minute)
    ].sort_values(["player_id", "timestamp"])

    figure = go.Figure()
    _add_map_design(figure, show_bounding_boxes=show_bounding_boxes)

    if not filtered.empty:
        figure.add_trace(
            go.Histogram2d(
                x=filtered["x"],
                y=filtered["y"],
                nbinsx=bins,
                nbinsy=max(12, int(bins * 0.6)),
                colorscale=HEATMAP_SCALE,
                colorbar={
                    "title": {"text": "Position<br>samples"},
                    "thickness": 14,
                },
                hovertemplate=(
                    "x=%{x}<br>y=%{y}<br>samples=%{z}<extra></extra>"
                ),
                name="Position density",
                showscale=True,
            )
        )

        if show_paths:
            for color_index, (player_id, player_data) in enumerate(
                filtered.groupby("player_id", sort=True)
            ):
                figure.add_trace(
                    go.Scatter(
                        x=player_data["x"],
                        y=player_data["y"],
                        mode="lines",
                        line={
                            "color": PLAYER_COLORS[color_index % len(PLAYER_COLORS)],
                            "width": 1.4,
                        },
                        opacity=0.6,
                        name=f"Player {player_id}",
                        customdata=np.column_stack(
                            (
                                player_data["name"],
                                player_data["elapsed_minutes"],
                                player_data["movement_state"],
                                player_data["target_name"],
                            )
                        ),
                        hovertemplate=(
                            f"Player {player_id}<br>"
                            "area=%{customdata[0]}<br>"
                            "state=%{customdata[2]}<br>"
                            "target=%{customdata[3]}<br>"
                            "elapsed=%{customdata[1]:.2f} min"
                            "<extra></extra>"
                        ),
                    )
                )
    else:
        figure.add_annotation(
            x=50,
            y=30,
            text="No positions match the selected filters",
            showarrow=False,
            bgcolor="#FFFFFF",
            bordercolor="#687580",
        )

    figure.update_layout(
        title={
            "text": "Synthetic player movement heatmap",
            "x": 0.02,
            "xanchor": "left",
        },
        template="plotly_white",
        height=720,
        margin={"l": 30, "r": 30, "t": 70, "b": 105},
        legend={
            "orientation": "h",
            "yanchor": "top",
            "y": -0.10,
            "xanchor": "center",
            "x": 0.5,
        },
        xaxis={
            "title": "Fictional map X",
            "range": [0, 100],
            "showgrid": False,
            "zeroline": False,
        },
        yaxis={
            "title": "Fictional map Y",
            "range": [0, 60],
            "showgrid": False,
            "zeroline": False,
        },
        plot_bgcolor="#F7F8FA",
        paper_bgcolor="#FFFFFF",
        hovermode="closest",
    )
    return figure


def _format_elapsed(elapsed_seconds: float) -> str:
    minutes, seconds = divmod(int(round(elapsed_seconds)), 60)
    return f"{minutes:02d}:{seconds:02d}"


def _movement_traces(
    data: pd.DataFrame,
    *,
    player_ids: list[int],
    elapsed_seconds: float,
    trail_seconds: float,
    window_start_seconds: float,
) -> list[go.Scatter]:
    traces: list[go.Scatter] = []
    for color_index, player_id in enumerate(player_ids):
        player_data = data[
            (data["player_id"] == player_id)
            & (data["elapsed_minutes"] * 60 <= elapsed_seconds)
        ].sort_values("timestamp")
        trail_start = max(window_start_seconds, elapsed_seconds - trail_seconds)
        trail_data = player_data[
            player_data["elapsed_minutes"] * 60 >= trail_start
        ]
        color = PLAYER_COLORS[color_index % len(PLAYER_COLORS)]

        traces.append(
            go.Scatter(
                x=trail_data["x"],
                y=trail_data["y"],
                mode="lines",
                line={"color": color, "width": 3},
                opacity=0.72,
                hoverinfo="skip",
                showlegend=False,
                name=f"Player {player_id} trail",
            )
        )

        if player_data.empty:
            traces.append(
                go.Scatter(
                    x=[],
                    y=[],
                    mode="markers",
                    name=f"Player {player_id}",
                    marker={"color": color, "size": 12},
                )
            )
            continue

        current = player_data.iloc[-1]
        traces.append(
            go.Scatter(
                x=[current["x"]],
                y=[current["y"]],
                mode="markers",
                marker={
                    "color": color,
                    "size": 14,
                    "line": {"color": "#FFFFFF", "width": 2},
                },
                name=f"Player {player_id}",
                customdata=[
                    [
                        current["name"],
                        current["movement_state"],
                        current["target_name"],
                        _format_elapsed(float(current["elapsed_minutes"]) * 60),
                    ]
                ],
                hovertemplate=(
                    f"<b>Player {player_id}</b><br>"
                    "area=%{customdata[0]}<br>"
                    "state=%{customdata[1]}<br>"
                    "target=%{customdata[2]}<br>"
                    "elapsed=%{customdata[3]}<extra></extra>"
                ),
            )
        )
    return traces


def build_movement_animation(
    data: pd.DataFrame,
    *,
    player_ids: Iterable[int] | None = None,
    minute_range: tuple[float, float] = (0.0, 10.0),
    trail_minutes: float = 1.0,
    frame_interval_seconds: int = 10,
    show_bounding_boxes: bool = True,
) -> go.Figure:
    """Animate player positions over elapsed time with short fading trails."""
    validate_player_paths(data)
    selected_ids = (
        sorted(data["player_id"].unique().tolist())
        if player_ids is None
        else sorted(set(player_ids))
    )
    selected_data = data[data["player_id"].isin(selected_ids)]
    requested_start, requested_end = minute_range
    if selected_data.empty:
        start_minute, end_minute = requested_start, requested_end
    else:
        start_minute = max(
            requested_start,
            float(selected_data["elapsed_minutes"].min()),
        )
        end_minute = min(
            requested_end,
            float(selected_data["elapsed_minutes"].max()),
        )
    filtered = selected_data[
        selected_data["elapsed_minutes"].between(start_minute, end_minute)
    ].copy()

    figure = go.Figure()
    _add_map_design(figure, show_bounding_boxes=show_bounding_boxes)

    start_seconds = start_minute * 60
    end_seconds = end_minute * 60
    frame_seconds = np.arange(
        start_seconds,
        end_seconds + frame_interval_seconds,
        frame_interval_seconds,
        dtype=float,
    )
    frame_seconds = frame_seconds[frame_seconds <= end_seconds]
    if len(frame_seconds) == 0 or frame_seconds[-1] != end_seconds:
        frame_seconds = np.append(frame_seconds, end_seconds)

    if selected_ids and not filtered.empty:
        initial_traces = _movement_traces(
            filtered,
            player_ids=selected_ids,
            elapsed_seconds=float(frame_seconds[0]),
            trail_seconds=trail_minutes * 60,
            window_start_seconds=start_seconds,
        )
        figure.add_traces(initial_traces)
        trace_indexes = list(range(len(initial_traces)))

        frames = []
        for elapsed_seconds in frame_seconds:
            elapsed_label = _format_elapsed(float(elapsed_seconds))
            frames.append(
                go.Frame(
                    name=str(int(elapsed_seconds)),
                    data=_movement_traces(
                        filtered,
                        player_ids=selected_ids,
                        elapsed_seconds=float(elapsed_seconds),
                        trail_seconds=trail_minutes * 60,
                        window_start_seconds=start_seconds,
                    ),
                    traces=trace_indexes,
                    layout=go.Layout(
                        title={
                            "text": (
                                "Synthetic player movement "
                                f"- elapsed {elapsed_label}"
                            ),
                            "x": 0.02,
                            "xanchor": "left",
                        }
                    ),
                )
            )
        figure.frames = frames

        slider_steps = [
            {
                "args": [
                    [frame.name],
                    {
                        "frame": {"duration": 250, "redraw": False},
                        "mode": "immediate",
                        "transition": {"duration": 150},
                    },
                ],
                "label": _format_elapsed(float(frame.name)),
                "method": "animate",
            }
            for frame in frames
        ]
        playback_controls = [
            {
                "buttons": [
                    {
                        "args": [
                            None,
                            {
                                "frame": {"duration": 350, "redraw": False},
                                "fromcurrent": True,
                                "transition": {"duration": 150},
                            },
                        ],
                        "label": "Play",
                        "method": "animate",
                    },
                    {
                        "args": [
                            [None],
                            {
                                "frame": {"duration": 0, "redraw": False},
                                "mode": "immediate",
                                "transition": {"duration": 0},
                            },
                        ],
                        "label": "Pause",
                        "method": "animate",
                    },
                ],
                "direction": "left",
                "pad": {"r": 10, "t": 70},
                "showactive": False,
                "type": "buttons",
                "x": 0.0,
                "xanchor": "left",
                "y": 0,
                "yanchor": "top",
            }
        ]
    else:
        slider_steps = []
        playback_controls = []
        figure.add_annotation(
            x=50,
            y=30,
            text="Select at least one player",
            showarrow=False,
            bgcolor="#FFFFFF",
            bordercolor="#687580",
        )

    figure.update_layout(
        title={
            "text": (
                "Synthetic player movement "
                f"- elapsed {_format_elapsed(start_seconds)}"
            ),
            "x": 0.02,
            "xanchor": "left",
        },
        template="plotly_white",
        height=760,
        margin={"l": 30, "r": 30, "t": 70, "b": 155},
        legend={
            "orientation": "h",
            "yanchor": "top",
            "y": -0.20,
            "xanchor": "center",
            "x": 0.5,
        },
        sliders=[
            {
                "active": 0,
                "currentvalue": {
                    "prefix": "Elapsed time: ",
                    "font": {"color": "#1F2933", "size": 14},
                },
                "len": 0.82,
                "pad": {"b": 10, "t": 55},
                "steps": slider_steps,
                "x": 0.16,
                "xanchor": "left",
                "y": 0,
                "yanchor": "top",
            }
        ]
        if slider_steps
        else [],
        updatemenus=playback_controls,
        xaxis={
            "title": "Fictional map X",
            "range": [0, 100],
            "showgrid": False,
            "zeroline": False,
        },
        yaxis={
            "title": "Fictional map Y",
            "range": [0, 60],
            "showgrid": False,
            "zeroline": False,
        },
        plot_bgcolor="#F7F8FA",
        paper_bgcolor="#FFFFFF",
        hovermode="closest",
    )
    return figure
