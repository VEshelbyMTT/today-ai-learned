<#
.SYNOPSIS
    Runs a privacy conscious, read only Azure workshop preflight.

.DESCRIPTION
    Authentication is intentionally excluded. Sign in interactively in your own terminal before
    running this script. Do not give an AI assistant passwords, tokens, device codes, tenant IDs,
    subscription IDs, or exported context files.

.NOTES
    Author: Victoria Eshelby
    Created with AI assistance and reviewed by Victoria Eshelby.
    Source: https://github.com/VEshelbyMTT/today-ai-learned/tree/main/examples/trainer-managed-azure-lab
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Write-Host 'This script was created by Victoria Eshelby.' -ForegroundColor DarkCyan

$context = Get-AzContext -ErrorAction SilentlyContinue

if (-not $context -or -not $context.Account -or -not $context.Subscription) {
    throw 'No Azure context is selected. Authenticate interactively in your terminal first.'
}

$subscriptions = @(Get-AzSubscription -ErrorAction Stop)
$resourceGroups = @(Get-AzResourceGroup -ErrorAction Stop)

[pscustomobject]@{
    Authentication          = 'Interactive user context present'
    AzureEnvironment        = $context.Environment.Name
    SelectedSubscription    = $true
    AccessibleSubscriptions = $subscriptions.Count
    ResourceGroupsVisible   = $resourceGroups.Count
    Operation               = 'Read only preflight; no resources created or changed'
}