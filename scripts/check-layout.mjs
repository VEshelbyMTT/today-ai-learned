import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const baseUrl = (process.env.SITE_PREVIEW_URL ?? "http://127.0.0.1:4000").replace(/\/$/, "");
const articles = [
  { slug: "designing-an-ai-friendly-ide-workspace", image: "2026-09-11" },
  { slug: "making-ai-my-implementation-minion", image: "2026-09-25" },
  { slug: "using-ai-for-visuals-design-and-explanation", image: "2026-10-09" },
  { slug: "using-ai-for-visuals-dashboards-and-complex-visualisations", image: "2026-10-16" }
];
const viewports = [
  { name: "desktop", width: 1440, height: 900, maxTitleSize: 76 },
  { name: "mobile", width: 390, height: 844, maxTitleSize: 48 }
];

await mkdir("test-results", { recursive: true });

const browser = await chromium.launch();

try {
  for (const { article, viewport } of articles.flatMap(article => viewports.map(viewport => ({ article, viewport })))) {
    const articlePath = `/articles/${article.slug}/`;
    const page = await browser.newPage({ viewport });
    const response = await page.goto(`${baseUrl}${articlePath}`, { waitUntil: "networkidle" });

    assert(response?.ok(), `${viewport.name}: article returned HTTP ${response?.status() ?? "unknown"}`);
    await page.screenshot({
      path: `test-results/${article.slug}-${viewport.name}.png`,
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

    const metadata = await page.evaluate(() => ({
      author: document.querySelector('meta[name="author"]')?.content,
      canonical: document.querySelector('link[rel="canonical"]')?.href,
      url: document.querySelector('meta[property="og:url"]')?.content,
      title: document.querySelector('meta[property="og:title"]')?.content,
      image: document.querySelector('meta[property="og:image"]')?.content,
      twitterImage: document.querySelector('meta[name="twitter:image"]')?.content
    }));
    const publishedUrl = `https://veshelbymtt.github.io/today-ai-learned${articlePath}`;
    assert.equal(metadata.author, "Victoria Eshelby");
    assert.equal(metadata.canonical, publishedUrl);
    assert.equal(metadata.url, publishedUrl);
    assert(metadata.title?.length > 0, "Sharing title is missing");
    const imagePath = `/assets/today-ai-learned-subject-${article.image}.png`;
    assert.equal(metadata.image, `https://veshelbymtt.github.io/today-ai-learned${imagePath}`);
    assert.equal(metadata.twitterImage, metadata.image);
    const imageResponse = await page.request.get(`${baseUrl}${imagePath}`);
    assert(imageResponse.ok(), `Missing sharing artwork: ${imagePath}`);
    assert(imageResponse.headers()["content-type"]?.includes("image/png"), "Sharing artwork must be PNG");

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
  for (const viewport of viewports) {
    const page = await browser.newPage({ viewport });
    const response = await page.goto(`${baseUrl}/`, { waitUntil: "networkidle" });
    assert(response?.ok(), "Homepage did not load");
    assert.equal(await page.locator(".article-card").count(), articles.length);
    for (const article of articles) {
      const card = page.locator(`.article-card[href$="/articles/${article.slug}/"]`);
      assert.equal(await card.count(), 1, `Missing article card: ${article.slug}`);
      const image = card.locator("img");
      assert.equal(await image.count(), 1, `Missing card artwork: ${article.slug}`);
      await image.evaluate(img => img.decode());
      assert(await image.evaluate(img => {
        const bounds = img.getBoundingClientRect();
        return img.naturalWidth > 0 && bounds.width > 0 && bounds.left >= 0 && bounds.right <= innerWidth;
      }), `Card artwork does not fit: ${article.slug}`);
    }
    await page.screenshot({ path: `test-results/home-${viewport.name}.png`, fullPage: true });
    await page.close();
  }
} finally {
  await browser.close();
}