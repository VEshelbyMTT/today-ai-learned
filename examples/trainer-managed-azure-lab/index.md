---
title: Trainer managed Azure lab scripts
description: Privacy safe PowerShell examples for preparing, testing, timing, and cleaning up a trainer managed AI-901 workshop.
permalink: /examples/trainer-managed-azure-lab/
---

# Trainer managed Azure lab scripts

These privacy safe examples show the automation pattern Victoria Eshelby used for an AI-901 community workshop. They are supporting assets for the Today AI Learned case study, not a turnkey Microsoft product.

**Author:** Victoria Eshelby<br>
**Development:** Designed, tested, and reviewed by Victoria Eshelby with AI assistance<br>
**Source:** <https://github.com/VEshelbyMTT/today-ai-learned>

Please retain the author attribution when copying or adapting these scripts.

## What is included

| File | Purpose |
| --- | --- |
| [`Test-WorkshopReadiness.ps1`](Test-WorkshopReadiness.ps1) | Reports privacy safe Azure context and visibility counts without changing resources. |
| [`Deploy-WorkshopLab.ps1`](Deploy-WorkshopLab.ps1) | Creates learner identities, group membership, scoped roles, policies, shared AI services, schedules, learner VMs, and local handout files. |
| [`Cleanup-WorkshopLab.ps1`](Cleanup-WorkshopLab.ps1) | Previews cleanup by default and removes only the configured workshop assets when explicitly confirmed. |
| [`Enforce-SessionTimeout.ps1`](Enforce-SessionTimeout.ps1) | Azure Automation runbook that previews or enforces the session cutoff with a managed identity. |
| [`Load-Env.ps1`](Load-Env.ps1) | Loads local configuration without embedding tenant or subscription details in source. |
| [`workshop.env.example`](workshop.env.example) | Lists the settings a trainer must provide privately. |

[Read the sanitised prompt history.]({{ '/examples/trainer-managed-azure-lab/prompts/' | relative_url }})

The original environment values, learner accounts, credentials, TAP codes, resource names, endpoints, and deployment outputs are not included.

## Before deployment

You need:

1. A dedicated or strongly isolated Azure training subscription and resource group.
2. An existing Azure DevTest Lab with a usable virtual network, subnet, shared public IP or another approved connection path, and an allowed Windows image.
3. `Owner`, or both `Contributor` and `User Access Administrator`, at the workshop resource group scope.
4. Entra permissions to create users and groups. Temporary Access Pass also requires the authentication method policy and `UserAuthenticationMethod.ReadWrite.All`.
5. Azure PowerShell and Microsoft Graph PowerShell modules:

```powershell
Install-Module Az -Scope CurrentUser
Install-Module Microsoft.Graph -Scope CurrentUser
```

Confirm regional availability and quota for the selected VM size, Foundry model, and Azure AI Search tier. Set a budget and cost alerts before creating learner resources.

## Prompt to use after cloning

The first prompt should ask AI to review and prepare the deployment without authenticating or changing Azure. Replace the items in square brackets, but do not paste credentials, tokens, tenant IDs, subscription IDs, learner data, or generated output into chat.

> I cloned Victoria Eshelby's trainer managed Azure lab example. Act as a senior Azure solutions architect and PowerShell reviewer.
>
> My goal is to prepare an AI-901 workshop for [number] learners in [region], running from [start time and time zone] to [end time and time zone]. The DevTest Lab [already exists / still needs to be created separately]. My target budget is [amount and currency].
>
> Read this guide, `workshop.env.example`, and the five PowerShell scripts before recommending changes.
>
> Do not authenticate, run deployment or cleanup, change my Azure context, create resources, grant permissions, or request secrets. I will authenticate and select the subscription separately in my own terminal.
>
> First:
>
> 1. Identify missing prerequisites, assumptions, security risks, licensing needs, quota checks, and likely cost drivers.
> 2. Tell me which `.env` settings I must complete locally. Use placeholders in chat rather than my real values.
> 3. Check whether the proposed learner count, region, VM size, Foundry model, Search tier, identity model, network route, session cutoff, and cleanup plan fit together.
> 4. Explain each script and the resources or identities it can change.
> 5. Propose a staged validation plan that starts without VMs or shared AI resources, then tests one representative learner journey before scaling.
> 6. Include checks for least privilege, unrelated resource visibility, accessibility, generated credential handling, idempotent reruns, timeout report mode, and preview first cleanup.
> 7. Stop before every command that could create, modify, or delete Azure or Entra resources. Wait for my explicit approval and show me how I can verify the result myself.
>
> End with a go or no go checklist. Mark anything that cannot be verified from the repository as requiring human confirmation.

Useful follow up prompts include:

> Here is the redacted error from the last stage. Explain the likely cause, propose the smallest safe correction, and tell me how to test only that correction. Do not rerun completed stages or ask for private identifiers.

> Review this redacted deployment summary from the perspective of a learner, not an owner. What must I test before inviting participants?

> Prepare a cleanup preview checklist. Do not execute cleanup. Include Azure resources, Entra identities, role assignments, generated credentials, local connection files, retained evidence, and cost verification.

## Configure privately

Copy `workshop.env.example` to `.env`, then replace every value in angle brackets and review every default:

```powershell
Copy-Item workshop.env.example .env
```

Do not commit `.env`. Choose a new globally unique Foundry account name and Search service name. Replace the example session date, times, time zone, cohort size, region, model, and tags.

## Authenticate separately

The local deployment and cleanup scripts do not sign you in or change subscription. Authenticate in your own terminal and select the intended subscription before running them:

```powershell
Connect-AzAccount
Set-AzContext -Subscription '<select privately>'

Connect-MgGraph -TenantId '<select privately>' -Scopes @(
    'Group.ReadWrite.All'
    'GroupMember.ReadWrite.All'
    'User.ReadWrite.All'
    'UserAuthenticationMethod.ReadWrite.All'
)
```

The scripts compare those existing contexts with `.env` and stop on a mismatch.

Run the read only preflight first. Its output contains state and counts rather than tenant, subscription, account, or resource names:

```powershell
.\Test-WorkshopReadiness.ps1
```

## Recommended deployment sequence

1. Run the identity and policy path without creating VMs:

   ```powershell
   .\Deploy-WorkshopLab.ps1 -SkipVmCreation -SkipSharedAiResources
   ```

2. Review created identities, group membership, role scopes, policies, and local output. Correct any licensing, quota, role, or region issue before adding compute.
3. Run the complete deployment. The script is designed to reuse existing workshop resources where practical:

   ```powershell
   .\Deploy-WorkshopLab.ps1
   ```

4. Use a representative demo account to test the learner journey. Do not rely on an owner account.
5. Upload `Enforce-SessionTimeout.ps1` to Azure Automation if PIM based expiry is unavailable. Assign its managed identity only the roles described in the script, schedule it with explicit parameter values, and run `-Mode Report` first.

## Test before learners arrive

Verify all of the following with the demo account:

* only the intended workshop resources are visible
* the assigned VM starts and its connection route works
* the local VM account works without exposing its password in logs
* Foundry and Search data plane access work through Entra roles
* the actual learning exercises run from beginning to end
* browser translation, read aloud, keyboard navigation, and support instructions work
* rerunning deployment skips or reuses existing resources instead of duplicating them
* the session timeout runbook reports the expected VMs and role assignments
* automatic startup and shutdown use the intended time zone

Store generated credentials and TAP codes only in an approved secure channel. Delete local handout files after distribution and never commit `output/`.

## Cleanup

Preview first. This makes no changes:

```powershell
.\Cleanup-WorkshopLab.ps1
```

Read every proposed deletion. When the list is correct, apply it explicitly:

```powershell
.\Cleanup-WorkshopLab.ps1 -Confirm2
```

Then verify in Azure and Entra that learner access is gone, chargeable resources were removed, costs have stopped increasing, and local credentials and connection files were deleted.

## Important limitations

These scripts cannot decide whether your tenant is suitable for external learners or whether your organisation has approved the workshop. Review security, privacy, safeguarding, procurement, accessibility, licensing, quota, cost, and data retention requirements for your environment.

The scripts intentionally do not create the DevTest Lab, approve Entra policies, create budgets, configure organisational networking, or grant their own operator permissions. Those controls remain with the trainer and the tenant administrators.