---
title: Sanitised AI-901 prompt history
description: The prompts and corrections that shaped a trainer managed Azure workshop environment.
permalink: /examples/trainer-managed-azure-lab/prompts/
---

# Recovered prompt history

This publication safe record was recovered from two local GitHub Copilot sessions from July 2026.

It is **not a verbatim transcript**. Real tenant, subscription, account, resource, path, and learner details have been removed. Typographical errors have been lightly corrected where they do not change the meaning. The context was creating an AI-901 lab environment where learners could use the Foundry playground and managed identity through Python exercises.

The raw turns are not published because several contain private identifiers and generated learner account output.

The recovered history spans 67 user turns covering architecture, access windows, shared services, security review, accessibility, authentication, deployment, troubleshooting, idempotency, configuration, scaling, and Temporary Access Pass recovery.

## 1. Initial architecture prompt

The first prompt established a role, existing state, and strict scope:

> Act as a senior Azure Solutions Architect and PowerShell automation engineer.


> I have already created the Azure DevTest Lab. Do not recreate the lab. Build only the remaining components: policies, users, groups, RBAC, and the student VMs.

The original prompt included the real cloud placement, tenant, subscription, resource group, lab, learner accounts, VM requirements, budget, and output expectations. Those values are intentionally omitted here.

The initial VM count was lower and later changed to 30 but I made it so I could deploy n-number of labs. This is useful evidence that the design evolved through the conversation rather than arriving as one complete prompt.

## 2. Access window and shared services

> I also want to time restrict the labs to a maximum of two hours. Once that ends, learners lose access to everything.
>
> Can we create one Foundry account and one Search resource for the group so only one shared environment is deployed? I also want to hide all my other resource groups.

This led to questions about time bound RBAC, a fallback enforcement runbook, shared services, resource scope, and automatic shutdown.

## 3. Session timing and trainer test account

> I want the labs to be time bound for the workshop window.
>
> I also want a test user for myself so I can see how the labs work. Add a demo account and VM.

The raw prompt contains exact dates, times, and a real guest account. Those details are omitted from this archive.

## 4. Learner guidance

> It will be an online virtual session, so the README needs to be easy to read and step by step for Turkish, Arabic, and refugee learners.

Later prompts sharpened that requirement:

> Make it as easy as possible for the learner.

> From the perspective of a refugee whose English may be limited, what other considerations should I put in place?

> Add a reassurance box explaining that we do not ask for personal information, they cannot break anything, they can copy and paste, and they can ask for help. Add a word help glossary with sign in, username, password or code, browser, computer, connect, start, help, and useful Azure words.

These prompts led to multilingual steps, translation and read aloud guidance, keyboard help, a glossary, reassurance, and a simplified sign in path.

## 5. Managed identity and shared project

> Let us use managed identity because it is better practice. I will demonstrate what keys are, but I want learners to use one shared project and Search index.

This changed the design from learner held keys to Entra authentication, managed identity, scoped data roles, and shared resources.

## 6. Security and infrastructure review

> Evaluate the design from a security and infrastructure perspective. What considerations or policies are missing? Make changes where necessary.

Follow up prompts included:

> Should I enable network isolation?

> Anything else that may be problematic?

> Am I ready to deploy? Are there any other considerations I should be aware of?

These prompts were more valuable than asking only for code. They led to checks for network access, remote desktop, role scope, quota, licensing, regional support, credential storage, and cleanup.

## 7. Start and shutdown behaviour

> Let us have the VMs start automatically at the teaching time if learners are not already online.

This was paired with automatic shutdown and access expiry so the learner experience and cost controls used the same session window.

## 8. Temporary Access Pass

> Can we use Temporary Access Pass?

> How do I enable the TAP policy?

The final deployment prompt added an important recovery requirement:

> Can you generate TAP codes without overwriting the existing learner state?

The raw deployment turn includes learner usernames and generated output. It must remain private.

## 9. Explain before execution

> Walk me through the deployment script.

This prompt matters because the workflow was not simply “generate and run”. The script was reviewed region by region before deployment.

## 10. Match the learning material

> Let us follow the Microsoft AI fundamentals labs for the model choice.

This grounded the environment in the exercises learners would actually complete rather than choosing a model only because it was available.

## 11. Safe reruns

> Can we change the code so that if an identity or resource already exists, we do not recreate or overwrite it?

This produced idempotent checks for groups, users, role assignments, policies, shared services, and virtual machines.

## 12. Separate configuration

> Where possible, can I have a `.env` file for the configuration settings?

This separated local environment values from reusable code. The public version must contain placeholders only.

## 13. Final scale change

> I want to create 30 VMs.

The final design became 29 learner workspaces plus one trainer demo workspace.

## Prompt pattern worth sharing

The strongest prompts did one of four things:

1. Set a role, existing state, scope, and constraints.
2. Added a learner or operational requirement that the first design had missed.
3. Asked for challenge and review before execution.
4. Reported real output and asked for the smallest safe correction.

The useful story is not that one perfect prompt generated the environment. The environment emerged through requirements, challenge, deployment evidence, and correction across many turns.