---
title: Designing your IDE
description: How repository roles help AI agents distinguish current behaviour, proposed direction, shared guidance, and external examples.
permalink: /articles/designing-your-ide/
---

# Today AI Learned: Designing your IDE

**Published:** 11 September 2026

I have been reflecting on how the structure of my VS Code workspace affects the answers I get from AI agents.

My workspace brings several sources together, but I do not treat them as equally trustworthy:

```text
VS Code workspace

Personal
    Learning and feedback
    External projects
    Experiments

Repositories
    Team codebase
    Architecture and decisions
    Team knowledge base
    External reference repositories
```

The personal area is for notes and experiments. The repositories contain version controlled work that other people may depend on.

I give each repository a specific role. The team codebase provides evidence of current behaviour. Architecture records explain decisions and proposed direction. The knowledge base holds reviewed, reusable guidance. External repositories provide examples, but they do not govern my team's work.

My delivery loop is simple:

```text
Understand the problem and record decisions
    then implement the smallest useful change
    then test the behaviour and the data
    then update shared guidance with the evidence
```

It is not a rigid sequence. Testing can expose a design problem. Documentation can reveal unclear ownership. Either result sends the work back around the loop.

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

Giving an agent more repositories does not automatically produce better context. Without ownership rules, it can combine current behaviour, future plans, external patterns, and outdated guidance into one confident answer.

The workspace gives the agent access to evidence. The instructions explain how that evidence may be used. Tests and team review decide whether the result can be trusted.

## Try the approach

Start with the [repository role instructions](../../../examples/repository-roles/copilot-instructions.md), then replace the generic repository names with the roles in your own workspace.
