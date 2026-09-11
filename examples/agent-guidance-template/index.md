---
title: Agent Guidance Template Repository
description: A starter design for packaging reviewed agent guidance for safe, versioned reuse across projects.
permalink: /examples/agent-guidance-template/
---

# Agent Guidance Template Repository

Use this design when several repositories need the same agent guidance but each team must retain control over its local rules.

**Outcome:** a private, versioned package that installs reviewed instructions and skills without inspecting application code or overwriting team-owned files.

## Do You Need This?

- **One project:** keep the guidance in that repository. A package adds work without improving reuse.
- **Several projects:** package the guidance when the same reviewed behaviour must stay consistent across them.

This repository distributes team-owned templates. It is not a repository-analysis service, agent runtime, knowledge base, memory system, or telemetry collector.

## Start Here

1. Choose one instruction that is already useful in more than one repository.
2. Package it for one supported host, such as GitHub Copilot.
3. Run `plan` and `install` against a temporary fixture before trying a team repository.

Add profiles, skills, and more adapters only after this smallest path works.

## Patterns Worth Studying

- [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) shows how one focused skill can make agent responses easier to act on.
- [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) demonstrates portable engineering behaviours that favour less code and less machinery.
- [affaan-m/ECC](https://github.com/affaan-m/ECC) demonstrates a broader harness with rules, skills, agents, hooks, memory, security, and installation tooling.

Borrow the scale that solves the problem. A focused internal package does not need to become a complete agent harness.

## Design Principles

### Reuse

1. Maintain each piece of guidance in one source location.
2. Package only the components a target project needs.
3. Treat generated project files as owned outputs, not independent copies.

### Safety

4. Preview every installation before writing files.
5. Keep executable hooks out of the first version.
6. Never collect or transmit information from consuming repositories.

## Proposed Structure

```text
agent-guidance-template/
    README.md
    bundle.yml
    package.json

    source/
        instructions/
            repository-roles.instructions.md
            validation.instructions.md
        skills/
            concise-output/
                SKILL.md

    adapters/
        github-copilot.yml

    bin/
        agent-guidance.mjs

    src/
        main.mjs
        plan.mjs
        install.mjs
        ownership.mjs
        paths.mjs

    tests/
        cli.test.mjs
        fixtures/
```

This is the internal-first version. `README.md` remains useful because colleagues still need setup, ownership, and release guidance. `package.json` points publishing at the organisation's private registry, and the package remains accessible only to the intended team or scope.

Add `LICENSE` only when organisational policy requires an explicit internal licence. Add `THIRD_PARTY_NOTICES.md` when dependencies or adapted material require attribution; private distribution does not remove those obligations.

Do not create empty `agents/`, `prompts/`, or additional adapter directories in advance. Add them when a reviewed component needs them. Generate `dist/` during packaging rather than committing it, and use npm scripts instead of separate PowerShell wrappers unless the team has a concrete PowerShell workflow to support. I use PowerShell wrappers because they fit my experience as a technical trainer and are comfortable for my individual workflow.

## Implementation

### CLI and ownership

- Keep the CLI entry point thin and delegate planning, installation, ownership, and path handling to separate modules.
- Resolve every destination path against the selected project root and reject absolute paths or traversal outside it.
- Track installed files in an ownership manifest and update or remove only those files.
- Build proposed output in a temporary directory before comparing or writing destination files.

### Packaging and tests

- Use an explicit npm `files` allowlist so private, development, and test files are not published accidentally.
- Test dry runs, collisions, repeat installation, updates, cleanup, and Windows and POSIX path separators in temporary fixtures.
- Require tests and `npm pack --dry-run` to pass before a tagged package release.
- Define measurable guarantees for deterministic output, ownership accuracy, and offline operation.

## Ownership Model

`source/` contains reviewed guidance. Files under `dist/` are generated during packaging, are not committed, and must not be edited directly.

Each adapter maps source components to paths understood by one coding-agent host. The internal first release supports GitHub Copilot through `.github/copilot-instructions.md`, `.github/instructions/`, `.github/skills/`, `.github/agents/`, and `.github/prompts/`.

A generic `AGENTS.md` adapter or another host should be added only when there is a real consumer and a validation method for it.

## How a Team Repository Fits

Your team's production repository is a consumer of the package, not part of the template source. It selects a reviewed package version and profile, then commits the generated guidance so changes remain visible in normal code review.

For a repository with no existing agent customization, the first installation would propose a small, isolated surface:

```text
team-repository/
    .agent-guidance.yml
    .agent-guidance/
        ownership.json
    .github/
        instructions/
            shared-agent-guidance/
                repository-roles.instructions.md
                validation.instructions.md
        skills/
            shared-agent-guidance/
                concise-output/
                    SKILL.md
    application-code/                   # Unread and unchanged
```

The repository declares what it consumes:

```yaml
schema_version: 1
package: "@your-scope/agent-guidance"
version: "1.0.0"
profile: core
target: github-copilot
```

The package owns only the generated files listed in `.agent-guidance/ownership.json`. Namespaced paths distinguish shared guidance from team-owned customization. Repository-specific architecture, commands, paths, and operational rules stay in separate files owned and reviewed by the team.

Before the first write, `plan` shows that `.github/` and the ownership manifest will be created. If a proposed path already exists but is not recorded as package-owned, installation stops and reports the collision. Updates and uninstall operations apply the same rule.

The installer does not inspect application code to decide what guidance a repository needs. A maintainer chooses the package version, profile, and adapter explicitly. CI can then verify that the committed generated files match that declaration without scanning unrelated repository content.

## Bundle Manifest

`bundle.yml` defines named profiles rather than installing every available component.

```yaml
schema_version: 1

profiles:
  core:
    instructions:
      - repository-roles
      - validation

  accessible-output:
    extends: core
    skills:
      - concise-output
```

Projects select a profile and target adapter. This keeps always-loaded context small and makes the installed behaviour reviewable.

## Packaging Flow

### Plan

1. Validate source metadata and referenced files.
2. Resolve the selected profile and adapter.
3. Build the target tree in a temporary directory.
4. Compare only managed destination paths with the proposed output.

### Apply

1. Show files that would be created, changed, preserved, or removed.
2. Write only after explicit confirmation or an automation-specific approval flag.
3. Record managed relative paths and file hashes in a local ownership manifest.

The installer must preserve destination files it does not own. Updating or uninstalling a bundle may change only files recorded in its ownership manifest unless the user explicitly approves a conflict resolution.

## NPM Distribution

An npm package provides a versioned, cross-platform delivery mechanism. It wraps the repository's packaging logic rather than becoming a second source for guidance.

Team-specific guidance should use a private package registry. Only generic content that has been reviewed for public release should be published to the public npm registry.

Installing the dependency must not modify a project. The package has no `postinstall` script. Consumers make changes only through explicit commands:

```powershell
npx @your-scope/agent-guidance@1.0.0 plan --profile core --target github-copilot
npx @your-scope/agent-guidance@1.0.0 install --profile core --target github-copilot
npx @your-scope/agent-guidance@1.1.0 update --dry-run
npx @your-scope/agent-guidance@1.1.0 uninstall
```

Use semantic versions and pin exact versions in automation. The published package contains only the CLI, manifests, schemas, source templates, adapters, and any required licence or notice files. Validate the package contents with `npm pack --dry-run` and publish from a protected release workflow.

## Privacy Contract

The tool installs static, reviewed template files. It may read only:

- Its packaged manifests and template assets.
- The explicitly provided `.agent-guidance.yml` project contract.
- The explicitly selected destination paths it plans to manage.
- Its own ownership manifest from a previous installation.

It must not inspect repository activity outside its managed paths:

- application source or tests;
- Git history, issues, or pull requests; or
- prompts, chat logs, or memories.

It must not inspect private machine state:

- editor state;
- environment variables or credentials;
- browser or clipboard data; or
- files elsewhere in the user's home directory.

The CLI performs no runtime network requests, telemetry, crash uploads, update checks, or background synchronization. A package manager may download the requested package before execution, but the CLI operates locally and offline.

The ownership manifest stores only the package version, selected profile, target adapter, managed relative paths, and content hashes. It must not store file contents, repository metadata, usernames, absolute paths, or machine identifiers.

Logs report planned actions and managed relative paths only. They must not print file contents or send output elsewhere. Temporary files remain local and are removed after packaging.

A separate privacy and security review is required before adding:

- hooks or background processing;
- memory or automatic learning;
- MCP integration;
- repository discovery; or
- global installation.

## Validation

### Package integrity

- Every manifest entry resolves to exactly one source component.
- Instruction and skill frontmatter is valid YAML.
- Generated output matches the selected profile deterministically.
- `npm pack --dry-run` contains only approved distribution files.
- Installing the npm dependency alone does not modify a project.

### Installation safety

- Dry runs do not change the destination.
- Installation preserves unowned files.
- Updates and uninstall operations modify only owned files.
- Repeat installation produces no further changes.

### Privacy

- Tests fail if the CLI attempts a network request.
- Tests prove the CLI does not recursively scan the destination repository.
- The ownership manifest contains no source content or identifying metadata.

## First Release

Build only:

- one profile;
- two repository-role instructions;
- one optional output-format skill;
- the GitHub Copilot adapter; and
- local packaging tests.

Do not build runtime features yet:

- repository inspection;
- runtime memory or automatic learning;
- MCP servers;
- background agents; or
- lifecycle hooks and telemetry.

Do not add more distribution paths until needed. Global installation and adapters without an active consumer remain out of scope.

## Acceptance Criteria

### Installation

- A new project can preview and install the `core` profile with one command.
- Running the installer twice produces no further changes.
- Existing unowned project instructions are preserved and reported.
- The generated customization files load without frontmatter diagnostics.
- A clean uninstall removes only files installed by the template.

### Privacy

- The complete lifecycle works with network access disabled.
- No restricted implementation or repository information is included in source, tests, fixtures, package output, or documentation.

Note: Most of this text was written by AI. Ask your AI to summarize the relevant sections. If you intend to build it, use existing packages where they fit.

The links at the top provide starting points. This resource is designed to help you begin, not to be cloned one-to-one. Your GitHub coding agent can adapt it to your existing infrastructure.

[Back to the article]({{ '/articles/designing-an-ai-friendly-ide-workspace/' | relative_url }})