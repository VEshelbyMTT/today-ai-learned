---
title: "Owner/developer theme synchronization: read-only teaching example"
description: A synthetic, read-only Node.js planner demonstrating owner and developer file boundaries for a Shopify theme.
permalink: /examples/owner-developer-sync/
---

# Owner/developer theme synchronization: read-only teaching example

This is newly written, generic code for the [TAIL article]({{ '/articles/becoming-the-webshop-front-end-developer/' | relative_url }}). It contains invented revision labels. [Browse or download the example files on GitHub](https://github.com/VEshelbyMTT/today-ai-learned/tree/main/examples/owner-developer-sync).

## Run locally

Use an existing Node.js 22 or newer installation. No package installation is needed.

```powershell
node --test .\sync-demo.test.cjs
node .\sync-demo.cjs forward
node .\sync-demo.cjs reverse
```

Run these from this example folder. The [planner]({{ '/examples/owner-developer-sync/sync-demo.cjs' | relative_url }}) only processes the invented data in the example; it does not read the current repository, fetch, stage, commit, push or contact a store. Invalid directions, missing baselines and conflicts fail with a nonzero exit status.

## Workflow routing

The [workflow]({{ '/examples/owner-developer-sync/theme-sync-demo.yml' | relative_url }}) is an inert download in this example folder. To try it, use a separate throwaway repository, put `sync-demo.cjs` and `sync-demo.test.cjs` at its root, and place the workflow at `.github/workflows/theme-sync-demo.yml`. Use generic `main` and `theme-editor` branches that are **not connected to a store**. Creating that repository or installing the workflow is a separate human action.

- A push to `main` chooses the forward example.
- A push to `theme-editor` chooses the reverse example.
- Manual dispatch accepts an explicit direction.
- Both directions share one concurrency group and run tests before printing their plan.
- The helper is checked out from `main`, not from the editor branch. Protect/review `main` in a real setup.
- The trigger workflow must exist on both pushed branches. GitHub discovers push workflows from the branch receiving the push; a `ref: main` checkout does not change discovery.
- Only tagged `github-actions[bot]` synchronization commits are skipped. A Shopify bot or a human owner is not excluded just for being an automated actor.

The demo requires only `contents: read`, disables persisted checkout credentials, and never calls Git write or Shopify operations. Do not increase its permissions just to experiment.

## Ownership contract

The maps use theme-root relative paths and **revision identifiers**, not file contents. A real adapter would map source `theme/` paths to the connected branch's root and obtain revisions from verified Git objects.

| File kind | Forward plan | Reverse plan |
|---|---|---|
| Liquid, CSS, JavaScript, assets and schema definitions | Follow developer source, including obsolete-code deletion | Never promote through the owner channel |
| Existing settings, templates, section-group JSON and non-schema locale JSON | Preserve owner state | Promote changed owner state only when source has not diverged from the baseline |
| A new owner-managed source file | Seed when it has never existed in the editor baseline | Do not delete merely because the editor has not received it yet |
| A baseline-known owner deletion | Do not resurrect old defaults | Propose deletion only without a conflicting source edit |

`baselineMain` and `baselineEditor` must be explicit. `{}` means a known empty baseline in this demonstration, not "we failed to load history". The demo refuses simultaneous, differing owner/developer edits rather than selecting a winner.

Plans contain `mode`, `direction`, `changes` (path and operation) and `preserved` paths. No revision values are printed. The tests cover both directions, new defaults, deletions, conflicts, invalid inputs, unchanged files and input preservation.

## What production still needs

Do not turn this into a live updater by appending a push command. A production implementation needs validated theme builds and schemas, Theme Check, trusted historical baselines, locale-key evolution, owner-comment preservation, remote-freshness checks, normal non-force updates, durable success/failure auditing, and reviewed branch permissions.

It worked for a small group that needed to work fast. I would not treat this teaching example as the way forward for big projects or companies. Think prototype or proof of concept, with a "YOU HAVE A WEEK - SHOW ME WHAT YOU'VE GOT!" kind of deadline.

Concurrency allows only one running and one pending run; newer pending runs may replace older ones, and execution order is not guaranteed. Real synchronization must inspect current branch tips and distinguish the triggering revision from the revision actually exported.

`GITHUB_TOKEN` writes normally do not trigger further push workflows. If a production workflow uses a different authorized identity, it must retain explicit loop prevention. Installing/updating workflow control files on another branch needs separately reviewed access; this demo does not attempt that.

A connected theme can remain connected after publication. A branch name does not enforce a development/live boundary. A production rollout needs an approved live-update policy, validation and rollback plan.

Local tests validate only this teaching planner. GitHub-hosted workflow execution, real Shopify synchronization, authenticated publication checks and commerce behavior are **NOT RUN**.
