"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { demoPlan, isOwnerFile, planSync } = require("./sync-demo.cjs");

test("saved settings, layouts and wording are owner-managed; definitions are not", () => {
  for (const path of ["config/settings_data.json", "templates/index.json", "sections/header-group.json", "locales/nl.json"]) {
    assert.equal(isOwnerFile(path), true, path);
  }
  for (const path of ["config/settings_schema.json", "locales/en.default.schema.json", "sections/header.liquid", "assets/site.css"]) {
    assert.equal(isOwnerFile(path), false, path);
  }
});

test("forward updates code and schemas, seeds new JSON, and preserves saved owner files", () => {
  const plan = demoPlan("forward");
  assert.deepEqual(plan.changes, [
    { path: "assets/site.css", operation: "update" },
    { path: "config/settings_schema.json", operation: "update" },
    { path: "templates/page.new.json", operation: "create" }
  ]);
  assert(plan.preserved.includes("config/settings_data.json"));
  assert(plan.preserved.includes("locales/en.default.json"));
  assert(plan.preserved.includes("templates/index.json"));
});

test("reverse proposes only changed owner-managed files", () => {
  assert.deepEqual(demoPlan("reverse").changes, [
    { path: "config/settings_data.json", operation: "update" },
    { path: "locales/en.default.json", operation: "update" },
    { path: "templates/index.json", operation: "update" }
  ]);
});

test("simultaneous owner/developer JSON edits stop without exposing values", () => {
  assert.throws(() => planSync("reverse", {
    main: { "templates/index.json": "developer-private-value" },
    editor: { "templates/index.json": "owner-private-value" },
    baselineMain: { "templates/index.json": "before" },
    baselineEditor: { "templates/index.json": "before" }
  }), /Owner\/developer conflict at templates\/index\.json/);
});

test("a baseline-known owner deletion is proposed without deleting new source defaults", () => {
  assert.deepEqual(planSync("reverse", {
    main: { "templates/old.json": "before", "templates/new.json": "new" },
    editor: {},
    baselineMain: { "templates/old.json": "before" },
    baselineEditor: { "templates/old.json": "before" }
  }).changes, [{ path: "templates/old.json", operation: "delete" }]);
});

test("a conflicting owner deletion stops", () => {
  assert.throws(() => planSync("reverse", {
    main: { "templates/old.json": "developer-after" },
    editor: {},
    baselineMain: { "templates/old.json": "before" },
    baselineEditor: { "templates/old.json": "before" }
  }), /Owner\/developer conflict/);
});

test("unchanged editor files do not overwrite developer changes", () => {
  assert.deepEqual(planSync("reverse", {
    main: { "templates/index.json": "developer-after" },
    editor: { "templates/index.json": "before" },
    baselineMain: { "templates/index.json": "before" },
    baselineEditor: { "templates/index.json": "before" }
  }).changes, []);
});

test("forward does not resurrect a baseline-known owner deletion", () => {
  const plan = planSync("forward", {
    main: { "templates/old.json": "before" },
    editor: {},
    baselineMain: { "templates/old.json": "before" },
    baselineEditor: { "templates/old.json": "before" }
  });
  assert.deepEqual(plan.changes, []);
  assert.deepEqual(plan.preserved, ["templates/old.json"]);
});

test("code deletions go forward but never come back through the owner channel", () => {
  const state = {
    main: {},
    editor: { "assets/old.css": "old" },
    baselineMain: { "assets/old.css": "old" },
    baselineEditor: { "assets/old.css": "old" }
  };
  assert.deepEqual(planSync("forward", state).changes, [{ path: "assets/old.css", operation: "delete" }]);
  assert.deepEqual(planSync("reverse", state).changes, []);
});

test("directions, baselines and paths must be explicit and valid", () => {
  const state = { main: {}, editor: {}, baselineMain: {}, baselineEditor: {} };
  assert.throws(() => planSync("sideways", state), /Direction/);
  assert.throws(() => planSync("reverse", { ...state, baselineMain: undefined }), /revision map/);
  for (const path of ["assets/../private.txt", "assets//site.css", ".github/workflows/other.yml", "assets/a\nb.css"]) {
    assert.throws(() => planSync("forward", { ...state, main: { [path]: "revision" } }), /unsupported theme path/);
  }
});

test("the plan never returns content and does not mutate its inputs", () => {
  const main = Object.freeze({ "assets/site.css": "never-print-this" });
  const plan = planSync("forward", {
    main,
    editor: Object.freeze({}),
    baselineMain: Object.freeze({}),
    baselineEditor: Object.freeze({})
  });
  assert.equal(plan.mode, "plan-only");
  assert(!JSON.stringify(plan).includes("never-print-this"));
  assert.deepEqual(main, { "assets/site.css": "never-print-this" });
});
