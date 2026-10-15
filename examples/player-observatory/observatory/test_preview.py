"""Run with Python and Playwright installed: python -m unittest discover -s <observatory>."""

import csv
import base64
import math
import threading
import unittest
import xml.etree.ElementTree as ET
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parent.parent


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


class PreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(
            ("127.0.0.1", 0), partial(QuietHandler, directory=str(ROOT))
        )
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}/observatory/"
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()
        with (ROOT / "data" / "fake_player_paths.csv").open(newline="") as source:
            cls.records = list(csv.DictReader(source))

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.context = self.browser.new_context(viewport={"width": 1440, "height": 1080})
        self.page = self.context.new_page()
        self.errors = []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))
        self.page.goto(self.url + "index.html")
        self.page.wait_for_function(
            "document.querySelector('#metric-players').textContent === '9'"
        )

    def tearDown(self):
        self.context.close()
        self.assertEqual(self.errors, [])

    def scrub(self, seconds):
        self.page.locator("#time").fill(str(seconds))

    def test_initial_state_and_no_autoplay(self):
        self.assertEqual(self.page.locator("#clock").inner_text(), "00:00")
        self.assertEqual(self.page.locator("#metric-distance").inner_text(), "0.0")
        self.assertEqual(self.page.locator("#area-visitors").inner_text(), "9")
        self.assertEqual(self.page.locator(".marker").count(), 9)
        self.assertEqual(self.page.locator(".region").count(), 18)
        self.assertEqual(self.page.get_by_role("button", name="Play replay").count(), 1)

    def test_full_session_statistics_match_independent_csv_calculation(self):
        self.scrub(600)
        previous = {}
        distance = 0
        visited = set()
        counts = {}
        for row in self.records:
            player = row["player_id"]
            x, y = float(row["x"]), float(row["y"])
            if player in previous:
                px, py = previous[player]
                distance += math.hypot(x - px, y - py)
            previous[player] = (x, y)
            if row["name"] != "spawn" and row["movement_state"] == "dwelling":
                visited.add(row["name"])
                counts[row["name"]] = counts.get(row["name"], 0) + 1
        self.assertAlmostEqual(
            float(self.page.locator("#metric-distance").inner_text()), distance, delta=0.051
        )
        self.assertEqual(self.page.locator("#metric-areas").inner_text(), f"{len(visited)} / 17")
        busiest = max(counts, key=counts.get)
        self.assertEqual(
            self.page.locator("#metric-busiest").inner_text(), f"Area {int(busiest[4:]):02}"
        )
        self.assertIn("1,089 of 1,089", self.page.locator("#sample-count").text_content())

    def test_selection_empty_state_and_single_player(self):
        self.page.locator("#select-all").click()
        self.assertIn("No players selected", self.page.locator("#status").inner_text())
        self.assertEqual(self.page.locator("#metric-players").inner_text(), "0")
        self.assertEqual(self.page.locator(".marker").count(), 0)
        self.assertTrue(self.page.locator("#download").is_disabled())
        self.page.get_by_role("checkbox", name="Player 01", exact=True).check()
        self.scrub(300)
        self.assertEqual(self.page.locator("#metric-players").inner_text(), "1")
        self.assertEqual(self.page.locator(".marker").count(), 1)
        self.assertIn("61 of 1,089", self.page.locator("#sample-count").text_content())
        self.page.locator("#select-all").click()
        self.assertEqual(self.page.locator(".marker").count(), 9)

    def test_replay_pause_reset_and_keyboard_scrub(self):
        self.page.locator("#speed").select_option("10")
        self.page.get_by_role("button", name="Play replay").click()
        self.page.wait_for_function("Number(document.querySelector('#time').value) >= 1")
        self.page.get_by_role("button", name="Pause replay").click()
        stopped = self.page.locator("#time").input_value()
        self.page.locator("#time").focus()
        self.page.keyboard.press("ArrowRight")
        self.assertEqual(int(self.page.locator("#time").input_value()), int(stopped) + 1)
        self.page.locator("#reset").click()
        self.assertEqual(self.page.locator("#clock").inner_text(), "00:00")
        self.scrub(599)
        self.page.get_by_role("button", name="Play replay").click()
        self.page.wait_for_function("document.querySelector('#clock').textContent === '10:00'")
        self.assertEqual(self.page.get_by_role("button", name="Play replay").count(), 1)

    def test_area_keyboard_inspection(self):
        self.scrub(600)
        region = self.page.get_by_role("button", name="Inspect Area 01", exact=True)
        region.focus()
        self.page.keyboard.press("Enter")
        self.assertEqual(self.page.locator("#area-title").inner_text(), "Area 01")
        expected = [
            row for row in self.records
            if row["name"] == "area1" and row["movement_state"] == "dwelling"
        ]
        self.assertEqual(int(self.page.locator("#area-samples").inner_text()), len(expected))
        self.assertEqual(
            int(self.page.locator("#area-visitors").inner_text()),
            len({row["player_id"] for row in expected}),
        )

    def test_density_and_download_match_selection(self):
        self.scrub(300)
        self.page.locator("#density").click()
        self.assertEqual(self.page.locator("#density").get_attribute("aria-pressed"), "true")
        self.assertEqual(self.page.locator(".marker").count(), 0)
        total = self.page.locator("#world rect title").all_text_contents()
        self.assertEqual(sum(int(title.split()[0]) for title in total), 9 * 61)
        self.page.locator("summary").click()
        with self.page.expect_download() as download_info:
            self.page.locator("#download").click()
        download = download_info.value
        with Path(download.path()).open(newline="") as source:
            records = list(csv.DictReader(source))
        self.assertEqual(len(records), 9 * 61)
        self.assertLessEqual(max(float(row["elapsed_minutes"]) for row in records), 5)
        self.page.locator("#movement").click()
        self.assertEqual(self.page.locator(".marker").count(), 9)
        self.assertEqual(self.page.locator("#world rect title").count(), 0)

    def test_mobile_and_embed_have_no_horizontal_overflow(self):
        for width in [375, 768, 1024, 1440]:
            self.page.set_viewport_size({"width": width, "height": 900})
            self.assertTrue(self.page.evaluate(
                "document.documentElement.scrollWidth <= innerWidth"
            ), f"Standalone overflow at {width}")
            self.page.goto(self.url + "embed.html")
            frame = self.page.frame_locator("iframe")
            frame.locator("#play:not(:disabled)").wait_for()
            self.page.wait_for_function(
                """() => {
                    const frame = document.querySelector('iframe');
                    return frame.clientHeight >= frame.contentDocument.documentElement.scrollHeight;
                }"""
            )
            self.assertTrue(self.page.evaluate(
                "document.documentElement.scrollWidth <= innerWidth"
            ), f"Embed parent overflow at {width}")
            self.assertTrue(frame.locator("html").evaluate(
                "node => node.scrollWidth <= window.innerWidth"
            ), f"Embed child overflow at {width}")
            frame.locator("#time").fill("300")
            self.assertEqual(frame.locator("#clock").inner_text(), "05:00")
            self.page.goto(self.url + "index.html")
            self.page.locator("#play:not(:disabled)").wait_for()

    def test_author_credit_survives_layout_and_view_changes(self):
        original = "https://veshelbymtt.github.io/today-ai-learned/"
        for width in [375, 1440]:
            self.page.set_viewport_size({"width": width, "height": 900})
            for suffix in ["index.html", "index.html?embedded"]:
                self.page.goto(self.url + suffix)
                self.page.locator("#play:not(:disabled)").wait_for()
                self.assertEqual(
                    self.page.locator('meta[name="author"]').get_attribute("content"),
                    "Victoria Eshelby",
                )
                self.assertTrue(
                    self.page.locator('link[rel="canonical"]').get_attribute("href").startswith(original)
                )
                byline = self.page.get_by_role("link", name="Created by Victoria Eshelby")
                self.assertTrue(byline.is_visible())
                self.assertTrue(byline.get_attribute("href").startswith(original))
                self.assertIn("Victoria Eshelby", self.page.locator("#world-description").text_content())
                for mode in ["density", "movement"]:
                    self.page.locator(f"#{mode}").click()
                    self.scrub(300)
                    credit = self.page.locator("#world .map-attribution")
                    self.assertTrue(credit.is_visible())
                    self.assertIn("Created by Victoria Eshelby", credit.text_content())
                    self.assertTrue(credit.evaluate(
                        """node => {
                            const box = node.getBBox();
                            const bounds = node.ownerSVGElement.viewBox.baseVal;
                            return box.x >= bounds.x && box.y >= bounds.y &&
                                box.x + box.width <= bounds.x + bounds.width &&
                                box.y + box.height <= bounds.y + bounds.height;
                        }"""
                    ))

    def test_sharing_metadata_and_about_links(self):
        expected = "https://veshelbymtt.github.io/today-ai-learned/"
        for selector in ['meta[property="og:image"]', 'meta[name="twitter:image"]']:
            self.assertEqual(
                self.page.locator(selector).get_attribute("content"),
                expected + "assets/today-ai-learned-subject-2026-10-16.png",
            )
        self.assertIn("Victoria Eshelby", self.page.locator(
            'meta[property="og:title"]'
        ).get_attribute("content"))
        self.assertEqual(
            self.page.locator('meta[property="og:url"]').get_attribute("content"),
            self.page.locator('link[rel="canonical"]').get_attribute("href"),
        )
        self.page.locator("summary").click()
        self.assertTrue(self.page.get_by_role("heading", name="About this experiment").is_visible())
        self.assertTrue(self.page.get_by_role("link", name="Read the story").get_attribute("href").startswith(expected))
        self.assertEqual(
            self.page.get_by_role("link", name="explore the source").get_attribute("href"),
            "https://github.com/VEshelbyMTT/today-ai-learned/tree/main/examples/player-observatory",
        )

    def test_map_svg_export_is_self_contained_and_attributed(self):
        self.page.locator("#select-all").click()
        self.page.get_by_role("checkbox", name="Player 01", exact=True).check()
        self.scrub(300)
        self.page.locator("summary").click()
        for mode in ["movement", "density"]:
            self.page.locator(f"#{mode}").click()
            with self.page.expect_download() as download_info:
                self.page.locator("#download-map").click()
            download = download_info.value
            self.assertEqual(download.suggested_filename, f"player-observatory-{mode}-300s.svg")
            content = Path(download.path()).read_text(encoding="utf-8")
            root = ET.fromstring(content)
            ns = {"s": "http://www.w3.org/2000/svg"}
            self.assertEqual(root.tag, "{http://www.w3.org/2000/svg}svg")
            self.assertIn("Created by Victoria Eshelby", content)
            self.assertIn("https://veshelbymtt.github.io/today-ai-learned/examples/player-observatory/observatory/", content)
            self.assertIn("05:00", content)
            self.assertIn("Players selected: 1", content)
            self.assertIn("Selected player IDs: 1.", content)
            self.assertEqual(root[0].get("fill"), "#0b151b")
            markers = root.findall('.//s:circle[@class="marker"]', ns)
            self.assertEqual(len(markers), 1 if mode == "movement" else 0)
            self.assertEqual(root.findall(".//s:script", ns), [])
            self.assertEqual(root.findall(".//s:image", ns), [])
            tile = root.find('.//*[@class="tile"]')
            self.assertIn("fill:", tile.get("style"))
            encoded = base64.b64encode(content.encode()).decode()
            exported = self.context.new_page()
            exported.goto("data:image/svg+xml;base64," + encoded)
            self.assertTrue(exported.evaluate(
                """() => {
                    const bounds = document.documentElement.viewBox.baseVal;
                    return Array.from(document.querySelectorAll('text')).every(node => {
                        const box = node.getBBox();
                        return box.width > 0 && box.x >= bounds.x && box.y >= bounds.y &&
                            box.x + box.width <= bounds.x + bounds.width &&
                            box.y + box.height <= bounds.y + bounds.height;
                    });
                }"""
            ))
            exported.close()

    def test_reduced_motion_and_theme(self):
        self.page.emulate_media(reduced_motion="reduce")
        self.page.reload()
        self.page.locator("#play:not(:disabled)").wait_for()
        self.assertEqual(self.page.get_by_role("button", name="Play replay").count(), 1)
        self.assertEqual(self.page.locator(".tile").first.evaluate(
            "node => getComputedStyle(node).transitionDuration"
        ), "0s")

    def test_embed_resizes_in_both_directions_and_when_evidence_opens(self):
        self.page.goto(self.url + "embed.html")
        frame = self.page.frame_locator("iframe")
        frame.locator("#play:not(:disabled)").wait_for()
        for width in [390, 1440, 375, 1024]:
            self.page.set_viewport_size({"width": width, "height": 900})
            self.page.wait_for_function(
                """() => {
                    const frame = document.querySelector('iframe');
                    const content = frame.contentDocument.body.getBoundingClientRect().height;
                    return frame.clientHeight >= content && frame.clientHeight - content < 4;
                }"""
            )
        frame.locator("summary").click()
        self.page.wait_for_function(
            """() => {
                const frame = document.querySelector('iframe');
                const content = frame.contentDocument.body.getBoundingClientRect().height;
                return frame.clientHeight >= content && frame.clientHeight - content < 4;
            }"""
        )

    def test_dataset_failure_is_visible(self):
        self.page.route("**/data/fake_player_paths.csv", lambda route: route.fulfill(status=503))
        self.page.reload()
        self.page.locator("#status.error").wait_for()
        self.assertIn("503", self.page.locator("#status").inner_text())
        self.assertTrue(self.page.locator("#play").is_disabled())
        self.assertTrue(self.page.locator("#density").is_disabled())

    def test_model_edge_cases_and_geometry_match_source(self):
        results = self.page.evaluate("""async () => {
            const m = await import('./model.js');
            const source = await (await fetch('../data/fake_player_paths.csv')).text();
            const rows = m.parseCSV(source);
            let rejected = false;
            try { m.parseCSV('player_id,x\\n1,nope'); } catch { rejected = true; }
            const path = rows.filter(r => r.player_id === 1);
            const a = path[1], b = path[2], point = m.positionAt(path,7.5);
            return {
                rejected, count:rows.length,
                midpoint:point.x === (a.x+b.x)/2 && point.y === (a.y+b.y)/2,
                empty:m.statistics([]), cells:m.densityCells([]).length,
                areas:m.areas
            };
        }""")
        self.assertTrue(results["rejected"])
        self.assertEqual(results["count"], 1089)
        self.assertTrue(results["midpoint"])
        self.assertEqual(results["empty"], {"players": 0, "areas": 0, "distance": 0, "busiest": None})
        self.assertEqual(results["cells"], 0)
        for area in results["areas"]:
            samples = [
                row for row in self.records
                if row["name"] == area["name"] and row["movement_state"] == "dwelling"
            ]
            for row in samples:
                for field, source in [("x0", "bbox_x_min"), ("x1", "bbox_x_max"),
                                      ("y0", "bbox_y_min"), ("y1", "bbox_y_max")]:
                    self.assertEqual(area[field], float(row[source]))


if __name__ == "__main__":
    unittest.main()
