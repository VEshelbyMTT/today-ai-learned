# Repository Role Instructions

Copy the content below into `.github/copilot-instructions.md` in the repository where the rules should apply. Replace each generic role with the relevant folder or repository name.

```markdown
## Source authority

Use the team codebase as evidence for current executable behaviour.

Use architecture and decision records for rationale and proposed direction.

Use the team knowledge base for reviewed guidance, concepts, and runbooks.

Treat external repositories as reference material only. Do not assume their patterns are approved for this project.

When sources disagree, report the conflict. Identify which claim describes current behaviour, proposed direction, external practice, or an uncertain conclusion.

## Write ownership

Put implementation changes in the team codebase.

Put architecture decisions and design rationale with the architecture records.

Put reusable guidance and operational learning in the team knowledge base.

Do not write private notes, transcripts, credentials, internal identifiers, or unpublished company information into public repositories.

## Validation

Test executable behaviour before describing it as current.

State assumptions and unresolved questions.

Require human review before treating generated guidance as team knowledge.
```

## Why use a file

A chat message provides context for that conversation. A checked in instruction file makes the repository rules visible, reviewable, and reusable in later work.
