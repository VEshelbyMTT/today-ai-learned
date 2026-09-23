<#
.SYNOPSIS
    Loads workshop configuration from a local .env file.

.NOTES
    Author: Victoria Eshelby
    Created with AI assistance and reviewed by Victoria Eshelby.
    Source: https://github.com/VEshelbyMTT/today-ai-learned/tree/main/examples/trainer-managed-azure-lab
#>

if ($MyInvocation.InvocationName -ne '.') {
    Write-Host 'This script was created by Victoria Eshelby.' -ForegroundColor DarkCyan
}

function Import-DotEnv {
    param([Parameter(Mandatory)][string]$Path)

    $settings = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file not found: $Path. Copy .env.example to .env and complete it first."
    }

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $trimmedLine = $line.Trim()
        if (-not $trimmedLine -or $trimmedLine.StartsWith('#')) { continue }

        $separatorIndex = $trimmedLine.IndexOf('=')
        if ($separatorIndex -lt 1) { continue }

        $key = $trimmedLine.Substring(0, $separatorIndex).Trim()
        $value = $trimmedLine.Substring($separatorIndex + 1).Trim()
        if ($value.Length -ge 2 -and
            (($value[0] -eq '"' -and $value[-1] -eq '"') -or
             ($value[0] -eq "'" -and $value[-1] -eq "'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $settings[$key] = $value
    }

    return $settings
}

function Get-WorkshopSetting {
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][string]$Key,
        $Default = $null,
        [switch]$Required
    )

    $value = if ($Settings.ContainsKey($Key)) { "$($Settings[$Key])".Trim() } else { '' }
    if (-not $value) { $value = $Default }

    if ($Required -and (-not $value -or $value -match '^<.+>$')) {
        throw "Set $Key in .env before running this script."
    }

    return $value
}

# Compatibility wrapper used by the original workshop scripts.
function Get-Conf {
    param(
        [Parameter(Mandatory)][hashtable]$DotEnv,
        [Parameter(Mandatory)][string]$Key,
        $Default = $null
    )

    return Get-WorkshopSetting -Settings $DotEnv -Key $Key -Default $Default
}