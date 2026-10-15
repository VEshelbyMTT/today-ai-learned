"""Generate the fictional player-path CSV used by the demo."""

from pathlib import Path

from synthetic_heatmap import generate_player_paths, save_player_paths


OUTPUT_PATH = Path(__file__).parent / "data" / "fake_player_paths.csv"


def main() -> None:
    data = generate_player_paths()
    output_path = save_player_paths(data, OUTPUT_PATH)
    print(f"Wrote {len(data):,} fictional positions to {output_path}")


if __name__ == "__main__":
    main()
