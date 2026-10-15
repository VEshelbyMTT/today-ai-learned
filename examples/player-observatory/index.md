---
title: "Player Observatory: fictional movement example"
description: Explore nine fictional players, replay their journeys, or adapt the Python and browser examples.
permalink: /examples/player-observatory/
---

# Player Observatory

Nine fictional players, ten minutes of movement, and a little world to explore.

[Open the interactive Player Observatory]({{ '/examples/player-observatory/observatory/' | relative_url }}) or [read the article]({{ '/articles/using-ai-for-visuals-dashboards-and-complex-visualisations/' | relative_url }}).

All players, coordinates, timestamps, areas, and routes are fictional. The example contains no production telemetry or real game map.

## Explore in your browser

Press Play or scrub the timeline, filter players, select an area, and switch between movement and density. Statistics accumulate from the start through the replay cursor. Density counts recorded positions; area visitors use dwelling samples. The definitions and CSV download are under **Behind the visual**.

The same panel includes **About this experiment** and **Download map SVG**. Export pauses playback and saves the current map as a self-contained vector image with the view, replay time, selected-player count, Victoria Eshelby's creator credit, and original dashboard URL. The SVG description records the selected player IDs. Open the downloaded image in a browser; it needs no dashboard stylesheet or data connection.

The browser experience uses HTML, CSS, JavaScript, and a static CSV. It needs no Python service, credentials, or Databricks connection.

## Adapt the Python example

[Browse or download the source folder on GitHub](https://github.com/VEshelbyMTT/today-ai-learned/tree/main/examples/player-observatory).

The folder includes the [Streamlit app](https://github.com/VEshelbyMTT/today-ai-learned/blob/main/examples/player-observatory/streamlit_app.py), [executed notebook](https://github.com/VEshelbyMTT/today-ai-learned/blob/main/examples/player-observatory/synthetic_player_heatmap.ipynb), shared generator and Plotly functions, tests, and [fictional CSV]({{ '/examples/player-observatory/data/fake_player_paths.csv' | relative_url }}).

Run these commands from the downloaded `examples/player-observatory` folder, preferably in a virtual environment:

```powershell
python -m pip install -r requirements.txt
streamlit run streamlit_app.py
```

The generator uses seeded route preferences, variable pauses, and bounded walking speeds along connected areas. To regenerate the fictional CSV, run `python generate_dataset.py`. This overwrites the example's CSV with repeatable generated data.

## Run the browser example locally

From the same folder:

```powershell
python -m http.server 8766 --bind 127.0.0.1
```

Open `http://127.0.0.1:8766/observatory/`. Serve the files over HTTP; opening the HTML directly does not support fetching the CSV.

## Validate changes

Run the Python tests from the example folder:

```powershell
python -m pytest tests
```

For the focused Chromium tests, install the optional browser-test dependency and browser, then run the suite:

```powershell
python -m pip install playwright
python -m playwright install chromium
python -m unittest discover -s observatory -p test_preview.py -v
```

The browser tests cover selection, independently calculated totals, replay, density counts, CSV download, keyboard controls, reduced motion, loading errors, and embedded layouts.
