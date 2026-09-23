<#
.SYNOPSIS
    Hard cutoff enforcer for the AI-901 training session.
    Stops all lab VMs AND revokes all learner RBAC so the cohort loses access to
    everything (lab, VMs, Foundry, Search) when the session window ends.

.DESCRIPTION
    Designed to run inside AZURE AUTOMATION using the Automation account's
    SYSTEM-ASSIGNED MANAGED IDENTITY (no stored credentials). This is the recommended
    "lose access after 2 hours" mechanism when Microsoft Entra ID P2 / PIM is NOT available.

.NOTES
    Author: Victoria Eshelby
    Created with AI assistance and reviewed by Victoria Eshelby.
    Source: https://github.com/VEshelbyMTT/today-ai-learned/tree/main/examples/trainer-managed-azure-lab

    Schedule options:
      - A one-time schedule created 2 hours after the class start, OR
      - A recurring daily schedule at the fixed class end time (e.g., 15:00).

    The companion action (RE-GRANT access for the next session) is simply re-running
    Deploy-AI901-Lab.ps1 (its RBAC steps are idempotent), or a mirror "grant" runbook.

.REQUIRED MANAGED IDENTITY ROLES (assign to the Automation account MI, least privilege)
      - 'DevTest Labs User' (or Contributor) on the lab  -> to stop VMs
      - 'User Access Administrator' on the Refugee RG     -> to remove role assignments
        (scope it to the RG only; do NOT grant at subscription scope)

.PARAMETER Mode
    'Revoke' (default) removes access + stops VMs. 'Report' only logs what it would do.
#>

param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$LabName,
    [Parameter(Mandatory)][string]$FoundryName,
    [Parameter(Mandatory)][string]$SearchName,
    [string]$GroupName = 'Workshop-Learners',
    [int]$LearnerCount = 29,
    [string]$VmNamePrefix = 'workshop-student',
    [string]$DemoVmName = 'workshop-demo',
    [string]$ApiVersion = '2018-09-15',
    [ValidateSet('Revoke','Report')][string]$Mode = 'Revoke'
)

$ErrorActionPreference = 'Stop'

Write-Output '[AUTHOR] This script was created by Victoria Eshelby.'

$Config = @{
    SubscriptionId = $SubscriptionId
    ResourceGroup  = $ResourceGroup
    LabName        = $LabName
    GroupName      = $GroupName
    LearnerCount   = $LearnerCount
    VmNamePrefix   = $VmNamePrefix
    DemoVmName     = $DemoVmName
    FoundryName    = $FoundryName
    SearchName     = $SearchName
    ApiVersion     = $ApiVersion
}

Write-Output "[START] AI-901 session cutoff | Mode=$Mode | $(Get-Date -Format o)"

# --- Authenticate with the Automation account's managed identity (keyless) ---
Connect-AzAccount -Identity | Out-Null
Set-AzContext -SubscriptionId $Config.SubscriptionId | Out-Null

$rgId      = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroup)"
$labId     = "$rgId/providers/Microsoft.DevTestLab/labs/$($Config.LabName)"
$foundryId = "$rgId/providers/Microsoft.CognitiveServices/accounts/$($Config.FoundryName)"
$searchId  = "$rgId/providers/Microsoft.Search/searchServices/$($Config.SearchName)"

# --- 1. Stop all learner VMs plus the demo VM ---
$vmNames = @(1..$Config.LearnerCount | ForEach-Object { "$($Config.VmNamePrefix)$('{0:D2}' -f $_)" }) + $Config.DemoVmName
foreach ($vmName in $vmNames) {
    $vmResId = "$labId/virtualmachines/$vmName"
    if (-not (Get-AzResource -ResourceId $vmResId -ErrorAction SilentlyContinue)) { continue }
    if ($Mode -eq 'Report') { Write-Output "[PREVIEW] Stop VM: $vmName"; continue }
    try {
        $path = "$vmResId/stop?api-version=$($Config.ApiVersion)"
        Invoke-AzRestMethod -Method POST -Path $path | Out-Null
        Write-Output "[DONE] Stopped VM: $vmName"
    } catch {
        Write-Warning "Could not stop $vmName : $($_.Exception.Message)"
    }
}

# --- 2. Revoke ALL learner group RBAC (lab + Foundry + Search) => lose access to everything ---
$group = Get-AzADGroup -DisplayName $Config.GroupName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $group) {
    Write-Warning "Group '$($Config.GroupName)' not found; nothing to revoke."
} else {
    foreach ($scope in @($labId, $foundryId, $searchId)) {
        $assignments = Get-AzRoleAssignment -ObjectId $group.Id -Scope $scope -ErrorAction SilentlyContinue |
                       Where-Object { $_.Scope -eq $scope }
        foreach ($ra in $assignments) {
            if ($Mode -eq 'Report') {
                Write-Output "[PREVIEW] Remove role '$($ra.RoleDefinitionName)' at $scope"
                continue
            }
            Remove-AzRoleAssignment -ObjectId $group.Id -RoleDefinitionName $ra.RoleDefinitionName -Scope $scope -ErrorAction SilentlyContinue
            Write-Output "[DONE] Removed role '$($ra.RoleDefinitionName)' at $scope"
        }
    }
}

if ($Mode -eq 'Report') {
    Write-Output "[PREVIEW COMPLETE] No resources were changed."
    Write-Output "NEXT ACTION: review the preview, then run again with -Mode Revoke at the session end."
} else {
    Write-Output "[CUTOFF COMPLETE] Learner VMs were stopped and learner access was removed @ $(Get-Date -Format o)."
    Write-Output "NEXT ACTION: verify that all learner VMs show Stopped in the Azure portal."
}
