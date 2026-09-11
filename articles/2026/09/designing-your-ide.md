---
title: Designing an AI friendly IDE workspace
description: How repository roles help AI agents distinguish current behaviour, proposed direction, shared guidance, and external examples.
permalink: /articles/designing-your-ide/
---

**TL;DR:** Give each repository a role. Tell the AI where to read, where to write, and which source wins when they disagree.

# Today AI Learned: Designing an AI friendly IDE workspace

**Published:** 11 September 2026

I have been reflecting on how the structure of my VS Code workspace affects the answers I get from AI agents.

## Give each repository a role

My workspace brings several sources together, but I do not treat them as equally trustworthy:

```text
VS Code workspace

Git worktrees
    Isolated working directories for feature branches
Personal
    Learning and feedback
    External projects
    Experiments

Repositories
    Team codebase
    Architecture and decisions
    Team knowledge base
    Agent guidance
    External reference repositories
```

The personal area is for notes and experiments. The repositories contain version-controlled work that other people may depend on.

Each repository has a specific role:

- **Team codebase:** evidence of current behaviour.
- **Architecture records:** decisions and proposed direction.
- **Knowledge base:** reviewed, reusable guidance.
- **Agent guidance repository:** instructions, skills, prompts, and agents packaged for use in other projects.
- **External repositories:** examples that do not govern my team's work.

The knowledge base explains how the team works. The agent guidance repository turns selected working practices into files that AI tools can load. Team codebases consume those files while retaining their own repository-specific instructions.

## Use the roles during delivery

My delivery loop is simple:

```text
    Understand the problem and record decisions
    then implement the smallest useful change
    then test the behaviour and the data
    then update shared guidance with the evidence
```

It is not a rigid sequence. Testing can expose a design problem. Documentation can reveal unclear ownership. Either result sends the work back around the loop.

## Tell the agent which source wins

I record the repository boundaries in project instructions rather than relying on one chat to remember them:

> Use the team codebase as evidence for current behaviour.
>
> Use architecture records for decisions and proposed direction.
>
> Treat external repositories as reference material only.
>
> Put reusable guidance in the team knowledge base.
>
> If sources disagree, show the conflict and identify each source.

More repositories do not automatically provide better context. Without ownership rules, an agent can combine current behaviour, future plans, external patterns, and outdated guidance into one confident answer.

I saw this in a pull request for a button feature I am currently designing:

- My architecture records described both the current and future vision.
- The pull request was scoped to the current button work.
- The implementation jumped ahead to button 2.0, which belonged in a separate pull request.

The future design was valid context. It was not part of the approved scope.

I now use two controls:

1. A separate Git worktree isolates the changes for each pull request.
2. Repository instructions distinguish current behaviour, approved scope, and future direction.

Before merging, I compare the worktree with the main working tree and run the relevant tests. The workspace provides the evidence; the instructions control how the agent uses it; review decides whether the result can be trusted.

## Bonus: package shared guidance

Repository-level instructions in VS Code are enough to use this approach. Packaging becomes useful only when several projects need the same reviewed instructions, skills, prompts, or agents.

If that sounds familiar, the [agent guidance template starter](../../../examples/agent-guidance-template/index.md) shows where to begin. It includes a small internal repository structure, public projects worth studying, ownership and privacy rules, and checks for safe installation and updates.

## Try it

1. Copy the [repository role instructions](../../../examples/repository-roles/copilot-instructions.md).
2. Replace the generic roles with repositories from your workspace.
3. Ask about a topic where two sources disagree. Check whether the agent reports the conflict instead of blending them.

Note: Most of this text was designed + written by a human, and then waffled and edited by AI.

#TodayAILearned #VSCode #ArtificialIntelligence #KnowledgeManagement #DataEngineering
