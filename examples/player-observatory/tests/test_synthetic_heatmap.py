from synthetic_heatmap import (
    build_heatmap_figure,
    build_movement_animation,
    generate_player_paths,
    validate_player_paths,
)


def test_default_dataset_shape_and_players() -> None:
    data = generate_player_paths()

    assert len(data) == 9 * 121
    assert data["player_id"].nunique() == 9
    assert data["elapsed_minutes"].min() == 0
    assert data["elapsed_minutes"].max() == 10


def test_every_player_starts_at_spawn() -> None:
    data = generate_player_paths()
    starts = (
        data.sort_values(["player_id", "timestamp"])
        .groupby("player_id", as_index=False)
        .first()
    )

    assert starts["name"].eq("spawn").all()
    assert starts["x"].eq(50).all()
    assert starts["y"].eq(30).all()


def test_positions_remain_inside_their_bounding_boxes() -> None:
    data = generate_player_paths()

    validate_player_paths(data)
    assert data["x"].between(data["bbox_x_min"], data["bbox_x_max"]).all()
    assert data["y"].between(data["bbox_y_min"], data["bbox_y_max"]).all()


def test_paths_walk_continuously_without_teleporting() -> None:
    data = generate_player_paths()
    ordered = data.sort_values(["player_id", "timestamp"]).copy()
    ordered["distance"] = (
        ordered.groupby("player_id")[["x", "y"]]
        .diff()
        .pow(2)
        .sum(axis=1)
        .pow(0.5)
    )

    assert ordered["movement_state"].eq("walking").any()
    assert ordered["distance"].dropna().le(1.05).all()


def test_generation_is_reproducible() -> None:
    first = generate_player_paths(seed=42)
    second = generate_player_paths(seed=42)

    assert first.equals(second)


def test_heatmap_contains_density_and_player_paths() -> None:
    data = generate_player_paths(player_count=2, duration_minutes=1)
    figure = build_heatmap_figure(data, player_ids=[1, 2])

    assert figure.data[0].type == "histogram2d"
    assert [trace.name for trace in figure.data[1:]] == [
        "Player 1",
        "Player 2",
    ]


def test_animation_uses_elapsed_time_and_player_markers() -> None:
    data = generate_player_paths(player_count=2, duration_minutes=1)
    figure = build_movement_animation(
        data,
        player_ids=[1, 2],
        frame_interval_seconds=10,
    )

    assert len(figure.frames) == 7
    assert len(figure.data) == 4
    assert figure.layout.sliders[0].currentvalue.prefix == "Elapsed time: "
    assert figure.frames[-1].name == "60"
