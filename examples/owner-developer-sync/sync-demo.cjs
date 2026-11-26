"use strict";

const assert = require("node:assert/strict");

function isOwnerFile(path) {
  return (
    (/^config\/.+\.json$/.test(path) && path !== "config/settings_schema.json") ||
    /^templates\/.+\.json$/.test(path) ||
    /^sections\/[^/]+\.json$/.test(path) ||
    (/^locales\/.+\.json$/.test(path) && !/\.schema\.json$/.test(path))
  );
}

function validateRevisions(files, name) {
  assert(files && typeof files === "object" && !Array.isArray(files), `${name} must be a revision map`);
  for (const [path, revision] of Object.entries(files)) {
    assert(
      /^(assets|blocks|config|layout|locales|sections|snippets|templates)\/[A-Za-z0-9_./-]+$/.test(path) &&
        path.split("/").every(part => part && part !== "." && part !== ".."),
      `${name} contains an unsupported theme path`
    );
    assert(typeof revision === "string" && revision.length > 0, `${name} contains an invalid revision`);
  }
}

function planSync(direction, { main, editor, baselineMain, baselineEditor }) {
  assert(["forward", "reverse"].includes(direction), "Direction must be forward or reverse");
  for (const [name, files] of Object.entries({ main, editor, baselineMain, baselineEditor })) {
    validateRevisions(files, name);
  }

  const changes = [];
  const preserved = [];
  const addChange = (path, current, proposed) => {
    if (current === proposed) return;
    changes.push({
      path,
      operation: proposed === undefined ? "delete" : current === undefined ? "create" : "update"
    });
  };

  if (direction === "forward") {
    const paths = new Set([...Object.keys(main), ...Object.keys(editor), ...Object.keys(baselineEditor)]);
    for (const path of [...paths].sort()) {
      if (isOwnerFile(path) && (Object.hasOwn(editor, path) || Object.hasOwn(baselineEditor, path))) {
        preserved.push(path);
        continue;
      }
      addChange(path, editor[path], main[path]);
    }
  } else {
    const paths = new Set([...Object.keys(editor), ...Object.keys(baselineEditor)]);
    for (const path of [...paths].sort()) {
      if (!isOwnerFile(path) || editor[path] === baselineEditor[path] || main[path] === editor[path]) {
        continue;
      }
      assert(
        main[path] === baselineMain[path],
        `Owner/developer conflict at ${path}; preserve both versions and resolve it`
      );
      addChange(path, main[path], editor[path]);
    }
  }

  return { mode: "plan-only", direction, changes, preserved };
}

function demoPlan(direction) {
  const baseline = {
    "assets/site.css": "code-before",
    "config/settings_data.json": "owner-before",
    "config/settings_schema.json": "schema-before",
    "locales/en.default.json": "translation-before",
    "sections/header-group.json": "layout-before",
    "sections/header.liquid": "header-before",
    "templates/index.json": "home-before"
  };
  return planSync(direction, {
    baselineMain: baseline,
    baselineEditor: baseline,
    main: {
      ...baseline,
      "assets/site.css": "developer-code-after",
      "config/settings_schema.json": "developer-schema-after",
      "templates/page.new.json": "new-page-default"
    },
    editor: {
      ...baseline,
      "config/settings_data.json": "owner-settings-after",
      "locales/en.default.json": "owner-wording-after",
      "templates/index.json": "owner-home-after"
    }
  });
}

module.exports = { isOwnerFile, planSync, demoPlan };

if (require.main === module) {
  console.log(JSON.stringify(demoPlan(process.argv[2]), null, 2));
}
