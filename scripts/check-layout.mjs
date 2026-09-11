import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const baseUrl = (process.env.SITE_PREVIEW_URL ?? "http://127.0.0.1:4000").replace(/\/$/, "");
const articlePath = "/articles/designing-an-ai-friendly-ide-workspace/";
const viewports = [
  { name: "desktop", width: 1440, height: 900, maxTitleSize: 76 },
  { name: "mobile", width: 390, height: 844, maxTitleSize: 48 }
];

await mkdir("test-results", { recursive: true });

const browser = await chromium.launch();

try {
  for (const viewport of viewports) {
    const page = await browser.newPage({ viewport });
    const response = await page.goto(`${baseUrl}${articlePath}`, { waitUntil: "networkidle" });

    assert(response?.ok(), `${viewport.name}: article returned HTTP ${response?.status() ?? "unknown"}`);
    await page.screenshot({
      path: `test-results/article-${viewport.name}.png`,
      fullPage: true
    });

    const metrics = await page.evaluate(() => {
      const main = document.querySelector("main.prose");
      const header = document.querySelector(".article-header");
      const title = document.querySelector(".article-header h1");
      const deck = document.querySelector(".article-deck");
      const paragraph = document.querySelector("main.prose > p:not(.article-summary)");
      const stylesheet = document.querySelector('link[rel="stylesheet"][href*="/assets/css/style.css"]');
      const codeBlocks = [...document.querySelectorAll("main.prose pre")];

      if (!main || !header || !title || !deck || !paragraph || !stylesheet) {
        throw new Error("Article layout contract elements are missing");
      }

      const headerBounds = header.getBoundingClientRect();
      const titleBounds = title.getBoundingClientRect();
      const deckBounds = deck.getBoundingClientRect();

      return {
        bodyClientWidth: document.documentElement.clientWidth,
        bodyScrollWidth: document.documentElement.scrollWidth,
        bodyFontFamily: getComputedStyle(document.body).fontFamily,
        stylesheetVersioned: new URL(stylesheet.href).searchParams.has("v"),
        mainWidth: main.getBoundingClientRect().width,
        headerLeft: headerBounds.left,
        headerWidth: headerBounds.width,
        titleFontSize: Number.parseFloat(getComputedStyle(title).fontSize),
        titleWithinHeader:
          titleBounds.left >= headerBounds.left &&
          titleBounds.right <= headerBounds.right &&
          titleBounds.top >= headerBounds.top &&
          titleBounds.bottom <= headerBounds.bottom,
        titleDeckOverlap: !(
          titleBounds.right <= deckBounds.left ||
          titleBounds.left >= deckBounds.right ||
          titleBounds.bottom <= deckBounds.top ||
          titleBounds.top >= deckBounds.bottom
        ),
        paragraphWidth: paragraph.getBoundingClientRect().width,
        overflowingCodeBlocks: codeBlocks.filter(
          (block) => block.scrollWidth > block.clientWidth + 1
        ).length
      };
    });

    console.log(`${viewport.name}: layout metrics`, metrics);
    assert(
      metrics.bodyFontFamily.includes("IBM Plex Mono"),
      `${viewport.name}: site stylesheet did not load`
    );
    assert.equal(
      metrics.stylesheetVersioned,
      true,
      `${viewport.name}: stylesheet URL is not cache-versioned`
    );
    assert(
      metrics.bodyScrollWidth <= metrics.bodyClientWidth + 1,
      `${viewport.name}: page overflows horizontally (${metrics.bodyScrollWidth}px > ${metrics.bodyClientWidth}px)`
    );
    assert(
      metrics.mainWidth >= metrics.bodyClientWidth - 1,
      `${viewport.name}: article canvas leaves an unintended side column`
    );
    assert(
      Math.abs(metrics.headerLeft) <= 1 && metrics.headerWidth >= metrics.bodyClientWidth - 1,
      `${viewport.name}: masthead has unintended outer gutters`
    );
    assert(
      metrics.titleFontSize <= viewport.maxTitleSize,
      `${viewport.name}: title is oversized at ${metrics.titleFontSize}px`
    );
    assert.equal(
      metrics.titleWithinHeader,
      true,
      `${viewport.name}: article title escapes the masthead`
    );
    assert.equal(
      metrics.titleDeckOverlap,
      false,
      `${viewport.name}: article title overlaps its supporting text`
    );
    assert(
      metrics.paragraphWidth <= 800,
      `${viewport.name}: paragraph measure is too wide at ${metrics.paragraphWidth}px`
    );
    assert.equal(
      metrics.overflowingCodeBlocks,
      0,
      `${viewport.name}: one or more code blocks overflow their container`
    );

    console.log(`${viewport.name}: layout contract passed`);
    await page.close();
  }
} finally {
  await browser.close();
}