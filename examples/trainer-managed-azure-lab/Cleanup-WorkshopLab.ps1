<#
.SYNOPSIS
    Tears down an AI-901 training environment after the course:
    deletes the 29 learner VMs plus the demo VM, removes the learner accounts and security group,
    and cleans up RBAC assignments. Does NOT delete the lab or resource group.

.DESCRIPTION
    Safe by default: runs in preview (-WhatIf-style) mode unless -Confirm2 is supplied.
    Idempotent: missing objects are skipped without error.

.NOTES
    Author: Victoria Eshelby
    Created with AI assistance and reviewed by Victoria Eshelby.
    Source: https://github.com/VEshelbyMTT/today-ai-learned/tree/main/examples/trainer-managed-azure-lab

.EXAMPLE
    # Preview what would be removed:
    .\Cleanup-AI901-Lab.ps1

    # Actually delete VMs, users, and the group:
    .\Cleanup-AI901-Lab.ps1 -Confirm2
#>

[CmdletBinding()]
param(
    [switch]$Confirm2,          # Must be set to perform real deletions.
    [switch]$KeepUsers,         # Delete VMs only; keep learner accounts + group.
    [switch]$KeepVMs,           # Delete users/group only; keep VMs.
    [switch]$KeepSharedAi       # Keep the shared Foundry account + Azure AI Search.
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host 'This script was created by Victoria Eshelby.' -ForegroundColor DarkCyan

# --- Central config from .env (falls back to the in-script defaults below if a key is absent) ---
. (Join-Path $PSScriptRoot 'Load-Env.ps1')
$DotEnv = Import-DotEnv (Join-Path $PSScriptRoot '..\.env')

#region CONFIG
$Config = [ordered]@{
    TenantId       = Get-Conf $DotEnv 'TENANT_ID'       '<your-tenant-guid>'
    SubscriptionId = Get-Conf $DotEnv 'SUBSCRIPTION_ID' '<your-subscription-guid>'
    ResourceGroup  = Get-Conf $DotEnv 'RESOURCE_GROUP'  '<workshop-resource-group>'
    LabName        = Get-Conf $DotEnv 'LAB_NAME'        '<existing-devtest-lab>'
    Domain         = Get-Conf $DotEnv 'DOMAIN'          '<your-tenant-domain>'
    LearnerCount   = [int](Get-Conf $DotEnv 'LEARNER_COUNT' 29)
    VmNamePrefix   = Get-Conf $DotEnv 'VM_NAME_PREFIX'  'ai901-student'
    LearnerPrefix  = Get-Conf $DotEnv 'LEARNER_PREFIX'  'learner'
    GroupName      = Get-Conf $DotEnv 'GROUP_NAME'      'Workshop-Learners'
    FoundryName    = Get-Conf $DotEnv 'FOUNDRY_NAME'    '<globally-unique-foundry-name>'
    SearchName     = Get-Conf $DotEnv 'SEARCH_NAME'     '<globally-unique-search-name>'
    DemoVmName     = Get-Conf $DotEnv 'DEMO_VM_NAME'    'workshop-demo'
    ApiVersion     = Get-Conf $DotEnv 'DTL_API_VERSION' '2018-09-15'
}
$requiredSettings = 'TenantId','SubscriptionId','ResourceGroup','LabName','Domain'
foreach ($settingName in $requiredSettings) {
    $settingValue = "$($Config[$settingName])"
    if (-not $settingValue -or $settingValue -match '^<.+>$') {
        throw "Complete $settingName in .env before running cleanup."
    }
}
if (-not $KeepSharedAi -and
    ($Config.FoundryName -match '^<.+>$' -or $Config.SearchName -match '^<.+>$')) {
    throw 'Set FOUNDRY_NAME and SEARCH_NAME in .env or run with -KeepSharedAi.'
}
$LabResourceId = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroup)/providers/Microsoft.DevTestLab/labs/$($Config.LabName)"
#endregion

function Write-Step { param($m) Write-Host "`n[STEP] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    [DONE] $m" -ForegroundColor Green }
function Write-Info { param($m) Write-Host "    [INFO] $m" -ForegroundColor Gray }
function Write-Prev { param($m) Write-Host "    [PREVIEW] would $m" -ForegroundColor Yellow }

if (-not $Confirm2) {
    Write-Host "`nPREVIEW MODE: no resources will be changed.`n" -ForegroundColor Yellow
}

#region LOGIN
Write-Step 'Checking existing Azure and Microsoft Graph contexts'
$azContext = Get-AzContext -ErrorAction SilentlyContinue
if (-not $azContext -or -not $azContext.Account -or -not $azContext.Subscription) {
    throw 'No Azure context is selected. Authenticate interactively in your terminal first.'
}
if ($azContext.Tenant.Id -ne $Config.TenantId -or $azContext.Subscription.Id -ne $Config.SubscriptionId) {
    throw 'The selected Azure context does not match TENANT_ID and SUBSCRIPTION_ID in .env.'
}
if (-not $KeepUsers) {
    $graphContext = Get-MgContext
    $requiredScopes = 'User.ReadWrite.All','Group.ReadWrite.All','GroupMember.ReadWrite.All'
    $hasRequiredGraphContext = $graphContext -and
        $graphContext.TenantId -eq $Config.TenantId -and
        -not ($requiredScopes | Where-Object { $_ -notin $graphContext.Scopes })
    if (-not $hasRequiredGraphContext) {
        throw "No suitable Microsoft Graph context exists. Authenticate separately with Connect-MgGraph for the configured tenant and scopes: $($requiredScopes -join ', ')."
    }
}
#endregion

#region DELETE VMs
if (-not $KeepVMs) {
    Write-Step "Deleting lab VMs ($($Config.LearnerCount) learners + demo)"
    $vmNames = @(1..$Config.LearnerCount | ForEach-Object { "$($Config.VmNamePrefix)$('{0:D2}' -f $_)" }) + $Config.DemoVmName
    foreach ($vmName in $vmNames) {
        $vmResId = "$LabResourceId/virtualmachines/$vmName"
        $vm = Get-AzResource -ResourceId $vmResId -ErrorAction SilentlyContinue
        if (-not $vm) { Write-Info "$vmName not found - skip."; continue }
        if ($Confirm2) {
            Remove-AzResource -ResourceId $vmResId -ApiVersion $Config.ApiVersion -Force | Out-Null
            Write-Ok "$vmName deleted."
        } else {
            Write-Prev "delete $vmName"
        }
    }
}
#endregion

#region DELETE USERS + GROUP
if (-not $KeepUsers) {
    Write-Step 'Removing learner accounts and security group'

    for ($i = 1; $i -le $Config.LearnerCount; $i++) {
        $nn  = '{0:D2}' -f $i
        $upn = "$($Config.LearnerPrefix)$nn@$($Config.Domain)"
        $u = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $u) { Write-Info "$upn not found - skip."; continue }
        if ($Confirm2) {
            Remove-MgUser -UserId $u.Id
            Write-Ok "$upn deleted."
        } else {
            Write-Prev "delete user $upn"
        }
    }

    $group = Get-MgGroup -Filter "displayName eq '$($Config.GroupName)'" -ConsistencyLevel eventual -CountVariable c -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($group) {
        # Remove only assignments created for this workshop. Never remove unrelated group access.
        $resourceGroupId = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroup)"
        $workshopScopes = @(
            $LabResourceId
            "$resourceGroupId/providers/Microsoft.CognitiveServices/accounts/$($Config.FoundryName)"
            "$resourceGroupId/providers/Microsoft.Search/searchServices/$($Config.SearchName)"
        )
        foreach ($scope in $workshopScopes) {
            $roleAssignments = Get-AzRoleAssignment -ObjectId $group.Id -Scope $scope -ErrorAction SilentlyContinue |
                Where-Object { $_.Scope -eq $scope }
            foreach ($roleAssignment in $roleAssignments) {
                if ($Confirm2) {
                    Remove-AzRoleAssignment -ObjectId $group.Id -RoleDefinitionName $roleAssignment.RoleDefinitionName -Scope $scope -ErrorAction SilentlyContinue
                    Write-Ok "Removed role '$($roleAssignment.RoleDefinitionName)' at $scope."
                } else {
                    Write-Prev "remove role '$($roleAssignment.RoleDefinitionName)' at $scope"
                }
            }
        }
        if ($Confirm2) {
            Remove-MgGroup -GroupId $group.Id
            Write-Ok "Group '$($Config.GroupName)' deleted."
        } else {
            Write-Prev "delete group '$($Config.GroupName)'"
        }
    } else {
        Write-Info "Group '$($Config.GroupName)' not found - skip."
    }
}
#endregion

#region DELETE SHARED AI
if (-not $KeepSharedAi) {
    Write-Step 'Deleting shared Foundry account and Azure AI Search'
    $rgId      = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroup)"
    $foundryId = "$rgId/providers/Microsoft.CognitiveServices/accounts/$($Config.FoundryName)"
    $searchId  = "$rgId/providers/Microsoft.Search/searchServices/$($Config.SearchName)"
    foreach ($res in @(
        @{ Id = $foundryId; Api = '2025-06-01'; Name = $Config.FoundryName },
        @{ Id = $searchId;  Api = '2023-11-01'; Name = $Config.SearchName })) {
        if (-not (Get-AzResource -ResourceId $res.Id -ErrorAction SilentlyContinue)) { Write-Info "$($res.Name) not found - skip."; continue }
        if ($Confirm2) {
            Remove-AzResource -ResourceId $res.Id -ApiVersion $res.Api -Force | Out-Null
            Write-Ok "$($res.Name) deleted."
        } else {
            Write-Prev "delete $($res.Name)"
        }
    }
}
#endregion

if ($Confirm2) {
    Write-Host "`nCLEANUP COMPLETE" -ForegroundColor Green
    Write-Host "Lab '$($Config.LabName)' and resource group '$($Config.ResourceGroup)' were retained." -ForegroundColor Cyan
    Write-Host 'NEXT ACTION: verify the retained lab and resource group in the Azure portal.' -ForegroundColor Cyan
} else {
    Write-Host "`nPREVIEW COMPLETE: no resources were changed." -ForegroundColor Yellow
    Write-Host 'NEXT ACTION: review the preview above. Re-run with -Confirm2 only when the deletion list is correct.' -ForegroundColor Cyan
}
