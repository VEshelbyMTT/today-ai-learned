<#
.SYNOPSIS
    Deploys the remaining AI-901 DevTest Lab components for a training cohort:
    lab policies, Entra security group + learner accounts, RBAC, tags, auto-shutdown,
    and 29 Windows 10 Enterprise Standard_B2ms lab VMs.

.DESCRIPTION
    The DevTest Lab and resource group configured in .env are assumed to ALREADY EXIST.
    This script does NOT create the lab. It is idempotent where practical: re-running it
    will not duplicate the group, users, role assignments, policies, or VMs.

    Modules required:
        Az.Accounts, Az.Resources          (Install-Module Az -Scope CurrentUser)
        Microsoft.Graph.Authentication
        Microsoft.Graph.Groups
        Microsoft.Graph.Users
        Microsoft.Graph.Identity.DirectoryManagement

.NOTES
    Author: Victoria Eshelby
    Created with AI assistance and reviewed by Victoria Eshelby.
    Source: https://github.com/VEshelbyMTT/today-ai-learned/tree/main/examples/trainer-managed-azure-lab
    Course: AI-901
    Passwords are NEVER hard-coded. VM local admin password is prompted securely or read
    from Key Vault. Learner temp passwords are randomly generated and written to a local,
    access-controlled credentials CSV that must be deleted after distribution.
#>

[CmdletBinding()]
param(
    # --- Optional: retrieve VM local admin password from Key Vault instead of prompting ---
    [string]$KeyVaultName,
    [string]$VMAdminPasswordSecretName,

    # --- Assign each learner ownership of ONLY their own VM (strict least privilege). ---
    [switch]$AssignPerVmOwnership,

    # --- Skip user creation (use if tenant policy/licensing blocks account creation). ---
    [switch]$SkipUserCreation,

    # --- Skip generating Temporary Access Pass (TAP) codes (learners then use temp passwords). ---
    [switch]$SkipTapGeneration,

    # --- Create/recover TAP codes, write their CSV, then stop before Azure resource deployment. ---
    [switch]$GenerateTapOnly,

    # --- Do everything except actually create the learner VMs (dry run for identity/policy). ---
    [switch]$SkipVmCreation,

    # --- Do not create the separate demo/test VM. ---
    [switch]$SkipDemoVm,

    # --- Skip creating the shared Foundry account + Azure AI Search resources. ---
    [switch]$SkipSharedAiResources,

    # --- Fixed lab window (CEST = UTC+2). Access is granted from start and auto-revoked at end.
    #     Access OPENS 15:00 (setup: sign-in, password, MFA); teaching starts 16:00; ENDS 18:30 CEST.
    #     Time-bound RBAC needs Entra P2/PIM. ---
    [datetimeoffset]$SessionStart,
    [datetimeoffset]$SessionEnd,

    # --- Grant PERMANENT access instead of the time-bound window (disables auto-revoke). ---
    [switch]$PermanentAccess
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host 'This script was created by Victoria Eshelby.' -ForegroundColor DarkCyan

# --- Central config from .env (falls back to the in-script defaults below if a key is absent) ---
. (Join-Path $PSScriptRoot 'Load-Env.ps1')
$DotEnv = Import-DotEnv (Join-Path $PSScriptRoot '..\.env')

# .env can also set the session window; an explicit -SessionStart/-SessionEnd on the CLI wins.
if (-not $PSBoundParameters.ContainsKey('SessionStart')) {
    $sessionStartSetting = Get-Conf $DotEnv 'SESSION_START'
    if (-not $sessionStartSetting -or $sessionStartSetting -match '^<.+>$') {
        throw 'Set SESSION_START in .env or pass -SessionStart explicitly.'
    }
    $SessionStart = [datetimeoffset]$sessionStartSetting
}
if (-not $PSBoundParameters.ContainsKey('SessionEnd')) {
    $sessionEndSetting = Get-Conf $DotEnv 'SESSION_END'
    if (-not $sessionEndSetting -or $sessionEndSetting -match '^<.+>$') {
        throw 'Set SESSION_END in .env or pass -SessionEnd explicitly.'
    }
    $SessionEnd = [datetimeoffset]$sessionEndSetting
}

#region ============================ CONFIGURATION ============================
# Values come from ..\.env when present; the second argument to Get-Conf is the fallback default.
$Config = [ordered]@{
    TenantId        = Get-Conf $DotEnv 'TENANT_ID'        '<your-tenant-guid>'
    SubscriptionId  = Get-Conf $DotEnv 'SUBSCRIPTION_ID'  '<your-subscription-guid>'
    ResourceGroup   = Get-Conf $DotEnv 'RESOURCE_GROUP'   '<workshop-resource-group>'
    LabName         = Get-Conf $DotEnv 'LAB_NAME'         '<existing-devtest-lab>'
    # Sweden Central: supports ALL five AI-901 labs INCLUDING Content Understanding (06a),
    # which is NOT offered in West Europe. Lab + VMs + Foundry + Search all live here.
    Location        = Get-Conf $DotEnv 'LOCATION'         'swedencentral'
    Domain          = Get-Conf $DotEnv 'DOMAIN'           '<your-tenant-domain>'

    VMSize          = Get-Conf $DotEnv 'VM_SIZE'          'Standard_B2ms'
    # DevTest Labs storageType: 'Standard' (HDD) | 'StandardSSD' | 'Premium'
    StorageType     = Get-Conf $DotEnv 'STORAGE_TYPE'     'StandardSSD'
    LocalAdminUser  = Get-Conf $DotEnv 'LOCAL_ADMIN_USER' 'student'

    LearnerCount    = [int](Get-Conf $DotEnv 'LEARNER_COUNT' 29)
    VmNamePrefix    = Get-Conf $DotEnv 'VM_NAME_PREFIX'   'ai901-student'   # -> ai901-student01 .. 29
    LearnerPrefix   = Get-Conf $DotEnv 'LEARNER_PREFIX'   'learner'         # -> learner01 .. learner29

    GroupName       = Get-Conf $DotEnv 'GROUP_NAME'       'Workshop-Learners'
    GroupNickname   = Get-Conf $DotEnv 'GROUP_NICKNAME'   'workshop-learners'

    # Demo/test participant: an EXISTING guest user (not created), gets its own VM + full access.
    DemoUserUpn     = Get-Conf $DotEnv 'DEMO_USER_UPN'    '<existing-demo-user-upn>'
    DemoVmName      = Get-Conf $DotEnv 'DEMO_VM_NAME'     'workshop-demo'

    # Auto-shutdown aligned to the session END (18:30 CEST). Windows TZ id = 'W. Europe Standard Time'.
    ShutdownTime    = Get-Conf $DotEnv 'SHUTDOWN_TIME'     '1830'
    ShutdownTimeZone= Get-Conf $DotEnv 'SHUTDOWN_TIMEZONE' 'W. Europe Standard Time'

    # Auto-START safety net: bring every (opted-in) VM online at teaching start if it's not already
    # running. Same Windows TZ as shutdown; day-of-week is derived from SessionStart.
    StartupTime     = Get-Conf $DotEnv 'STARTUP_TIME'     '1600'

    # --- Temporary Access Pass (TAP): a short code each learner types to sign in (no phone/app).
    #     Needs the tenant TAP policy enabled + Graph scope UserAuthenticationMethod.ReadWrite.All. ---
    TapLifetimeMinutes = [int](Get-Conf $DotEnv 'TAP_LIFETIME_MINUTES' 300)          # ~5h covers the window + buffer
    TapUsableOnce      = [bool]::Parse((Get-Conf $DotEnv 'TAP_USABLE_ONCE' 'false')) # reusable through the session

    ApiVersion      = Get-Conf $DotEnv 'DTL_API_VERSION'  '2018-09-15'

    # --- Shared AI resources: ONE Foundry account + ONE Search for the whole class ---
    # NOTE: FoundryName must be globally unique + lowercase alphanumeric. Change if taken.
    FoundryName     = Get-Conf $DotEnv 'FOUNDRY_NAME'     '<globally-unique-foundry-name>'
    FoundryProject  = Get-Conf $DotEnv 'FOUNDRY_PROJECT'  'workshop-project'
    # Aligned with the official AI-901 lab 02a-generative-ai (gpt-5-mini; fallbacks gpt-5 / gpt-5.1).
    ModelName       = Get-Conf $DotEnv 'MODEL_NAME'       'gpt-5-mini'
    ModelVersion    = Get-Conf $DotEnv 'MODEL_VERSION'    ''                # empty -> Azure deploys the current DEFAULT version
    ModelSku        = Get-Conf $DotEnv 'MODEL_SKU'        'GlobalStandard'
    ModelCapacity   = [int](Get-Conf $DotEnv 'MODEL_CAPACITY' 10)
    SearchName      = Get-Conf $DotEnv 'SEARCH_NAME'      '<globally-unique-search-name>'
    SearchSku       = Get-Conf $DotEnv 'SEARCH_SKU'       'basic'           # 'free' | 'basic'
    EntraOnlyAuth   = [bool]::Parse((Get-Conf $DotEnv 'ENTRA_ONLY_AUTH' 'true'))  # disable API keys -> keyless

    Tags = @{
        Course      = Get-Conf $DotEnv 'TAG_COURSE'       'AI-901'
        Cohort      = Get-Conf $DotEnv 'TAG_COHORT'       'CommunityWorkshop'
        Environment = Get-Conf $DotEnv 'TAG_ENVIRONMENT'  'Training'
        Owner       = Get-Conf $DotEnv 'TAG_OWNER'        'WorkshopTrainer'
        CostControl = Get-Conf $DotEnv 'TAG_COST_CONTROL' 'Required'
    }
}

$requiredSettings = 'TenantId','SubscriptionId','ResourceGroup','LabName','Domain'
foreach ($settingName in $requiredSettings) {
    $settingValue = "$($Config[$settingName])"
    if (-not $settingValue -or $settingValue -match '^<.+>$') {
        throw "Complete $settingName in .env before running the deployment."
    }
}
if (-not $SkipDemoVm -and $Config.DemoUserUpn -match '^<.+>$') {
    throw 'Set DEMO_USER_UPN in .env or run with -SkipDemoVm.'
}
if (-not $SkipSharedAiResources -and
    ($Config.FoundryName -match '^<.+>$' -or $Config.SearchName -match '^<.+>$')) {
    throw 'Set FOUNDRY_NAME and SEARCH_NAME in .env or run with -SkipSharedAiResources.'
}
if ($SessionStart.Year -lt 2000 -or $SessionEnd.Year -lt 2000 -or $SessionEnd -le $SessionStart) {
    throw 'Set a valid SESSION_START and SESSION_END in .env or pass both parameters explicitly.'
}

$LabResourceId = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroup)/providers/Microsoft.DevTestLab/labs/$($Config.LabName)"
$OutputDir     = Join-Path $PSScriptRoot '..\output'
$null = New-Item -ItemType Directory -Path $OutputDir -Force
#endregion

#region ============================ HELPERS ================================
function Write-Step { param([string]$Message) Write-Host "`n[STEP] $Message" -ForegroundColor Cyan }
function Write-Info { param([string]$Message) Write-Host "    [INFO] $Message" -ForegroundColor Gray }
function Write-Ok   { param([string]$Message) Write-Host "    [DONE] $Message" -ForegroundColor Green }
function Write-Warn2{ param([string]$Message) Write-Host "    [WARNING] $Message" -ForegroundColor Yellow }

# Cryptographically secure random integer in [0, MaxExclusive). Uses a CSPRNG (NOT Get-Random /
# System.Random, which is predictable and unsuitable for credentials).
function Get-CryptoRandomInt {
    param([Parameter(Mandatory)][int]$MaxExclusive)
    if ($MaxExclusive -le 0) { throw 'MaxExclusive must be greater than 0.' }
    $bytes = New-Object 'System.Byte[]' 4
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $val = [System.BitConverter]::ToUInt32($bytes, 0)
    return [int]($val % [uint32]$MaxExclusive)
}

function New-RandomPassword {
    param([int]$Length = 16)
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = 'abcdefghijkmnpqrstuvwxyz'
    $digit   = '23456789'
    $special = '!@#$%^&*-_'
    $all     = "$upper$lower$digit$special"
    $chars = @(
        $upper[(Get-CryptoRandomInt -MaxExclusive $upper.Length)]
        $lower[(Get-CryptoRandomInt -MaxExclusive $lower.Length)]
        $digit[(Get-CryptoRandomInt -MaxExclusive $digit.Length)]
        $special[(Get-CryptoRandomInt -MaxExclusive $special.Length)]
    )
    for ($i = 0; $i -lt ($Length - 4); $i++) { $chars += $all[(Get-CryptoRandomInt -MaxExclusive $all.Length)] }
    -join ($chars | Sort-Object { Get-CryptoRandomInt -MaxExclusive 2147483647 })
}

function Invoke-DtlRest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET','PUT','DELETE')] [string]$Method,
        [Parameter(Mandatory)][string]$RelativePath,   # relative to the lab resource id
        [object]$Body
    )
    $path = "$LabResourceId$RelativePath" + "?api-version=$($Config.ApiVersion)"
    $params = @{ Method = $Method; Path = $path }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $params.Payload = ($Body | ConvertTo-Json -Depth 20)
    }
    $resp = Invoke-AzRestMethod @params
    if ($resp.StatusCode -ge 400) {
        throw "DevTest Labs REST $Method $RelativePath failed ($($resp.StatusCode)): $($resp.Content)"
    }
    if ($resp.Content) { return ($resp.Content | ConvertFrom-Json) }
}

# Resolve the RDP connection endpoint for a DTL VM that uses the lab SHARED public IP:
# returns '<sharedIpFqdn>:<natFrontendPort>' (what learners type into the RDP client), or a
# placeholder if the shared-IP NAT mapping is not yet assigned. StrictMode-safe property access.
function Get-DtlVmRdpEndpoint {
    param([Parameter(Mandatory)][string]$VmName)
    try { $vm = Invoke-DtlRest -Method GET -RelativePath "/virtualmachines/$VmName" }
    catch { return '(unavailable)' }
    if (-not $vm) { return '(pending)' }
    $props = $vm.properties
    $fqdn = $null
    if ($props.PSObject.Properties.Name -contains 'fqdn') { $fqdn = $props.fqdn }
    $port = $null
    if (($props.PSObject.Properties.Name -contains 'sharedPublicIpAddressConfiguration') -and
        $props.sharedPublicIpAddressConfiguration -and
        ($props.sharedPublicIpAddressConfiguration.PSObject.Properties.Name -contains 'inboundNatRules')) {
        $rule = $props.sharedPublicIpAddressConfiguration.inboundNatRules | Select-Object -First 1
        if ($rule -and ($rule.PSObject.Properties.Name -contains 'frontendPort')) { $port = $rule.frontendPort }
    }
    if ($fqdn -and $port) { return "$fqdn`:$port" }
    if ($fqdn) { return $fqdn }
    return '(pending)'
}

# Write a ready-to-use Remote Desktop file so a learner can just DOUBLE-CLICK it and type the
# password - no host, port, or user name to type. Skips placeholder endpoints like '(pending)'.
function New-RdpFile {
    param(
        [Parameter(Mandatory)][string]$Endpoint,   # '<host>:<port>' or '<host>'
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Endpoint) -or $Endpoint.StartsWith('(')) { return $false }
    $lines = @(
        "full address:s:$Endpoint"
        "username:s:$UserName"
        'prompt for credentials:i:1'   # ask only for the password
        'screen mode id:i:2'           # full screen
        'use multimon:i:0'
        'authentication level:i:2'
        'redirectclipboard:i:1'        # copy/paste between local + lab PC
    )
    Set-Content -Path $Path -Value ($lines -join "`r`n") -Encoding ASCII
    return $true
}

# Opt a single VM into auto-start (schedule 'LabVmsStartupTask') so it powers on at the scheduled
# time if it is not already running. Non-fatal: warns and continues if the schedule can't be applied
# (e.g. the VM does not exist yet). DTL requires this per-VM opt-in; the lab policy alone won't start VMs.
function Enable-DtlVmAutoStart {
    param(
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Time,        # 'HHmm', e.g. '1600'
        [Parameter(Mandatory)][string]$Weekday,     # e.g. 'Friday'
        [Parameter(Mandatory)][string]$TimeZoneId
    )
    $body = @{
        properties = @{
            status           = 'Enabled'
            taskType         = 'LabVmsStartupTask'
            weeklyRecurrence = @{ weekdays = @($Weekday); time = $Time }
            timeZoneId       = $TimeZoneId
        }
    }
    try {
        Invoke-DtlRest -Method PUT -RelativePath "/virtualmachines/$VmName/schedules/LabVmsStartupTask" -Body $body | Out-Null
        return $true
    } catch {
        Write-Warn2 "Auto-start opt-in failed for $VmName : $($_.Exception.Message)"
        return $false
    }
}

function Invoke-ArmRest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET','PUT','DELETE')] [string]$Method,
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][string]$ApiVersion,
        [object]$Body
    )
    $path = "$ResourceId`?api-version=$ApiVersion"
    $params = @{ Method = $Method; Path = $path }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $params.Payload = ($Body | ConvertTo-Json -Depth 30)
    }
    $resp = Invoke-AzRestMethod @params
    if ($resp.StatusCode -ge 400) {
        throw "ARM $Method $ResourceId failed ($($resp.StatusCode)): $($resp.Content)"
    }
    if ($resp.Content) { return ($resp.Content | ConvertFrom-Json) }
}
#endregion

#region ============================ 1. LOGIN ================================
Write-Step '1. Connecting to Azure and Microsoft Graph'

if (-not $SkipUserCreation) {
    $graphScopes = @(
        'Group.ReadWrite.All',
        'GroupMember.ReadWrite.All',
        'User.ReadWrite.All'
    )
    if (-not $SkipTapGeneration) {
        $graphScopes += 'UserAuthenticationMethod.ReadWrite.All'
    }
    $graphContext = Get-MgContext
    $hasRequiredGraphContext = $graphContext -and
        $graphContext.TenantId -eq $Config.TenantId -and
        -not ($graphScopes | Where-Object { $_ -notin $graphContext.Scopes })
    if (-not $hasRequiredGraphContext) {
        throw "No suitable Microsoft Graph context exists. Authenticate separately with Connect-MgGraph for tenant $($Config.TenantId) and scopes: $($graphScopes -join ', ')."
    }
    Write-Ok "Using the existing Microsoft Graph context for $($graphContext.Account)."
}

$azContext = Get-AzContext -ErrorAction SilentlyContinue
if (-not $azContext -or -not $azContext.Account -or -not $azContext.Subscription) {
    throw 'No Azure context is selected. Authenticate interactively in your terminal first.'
}
if ($azContext.Tenant.Id -ne $Config.TenantId -or $azContext.Subscription.Id -ne $Config.SubscriptionId) {
    throw 'The selected Azure context does not match TENANT_ID and SUBSCRIPTION_ID in .env.'
}
Write-Ok 'Using the existing Azure context selected by the trainer.'
#endregion

#region ============================ 2. VALIDATION ==========================
Write-Step '2. Validating resource group and lab exist (will NOT create the lab)'

$rg = Get-AzResourceGroup -Name $Config.ResourceGroup -ErrorAction SilentlyContinue
if (-not $rg) { throw "Resource group '$($Config.ResourceGroup)' not found. Aborting." }
Write-Ok "Resource group '$($Config.ResourceGroup)' found in $($rg.Location)"

$lab = Get-AzResource -ResourceId $LabResourceId -ErrorAction SilentlyContinue
if (-not $lab) { throw "DevTest Lab '$($Config.LabName)' not found at $LabResourceId. Aborting." }
Write-Ok "DevTest Lab '$($Config.LabName)' found."
if ($lab.Location -and $lab.Location -ne $Config.Location) {
    Write-Warn2 "Lab region '$($lab.Location)' != configured Location '$($Config.Location)'. DevTest Lab VMs"
    Write-Warn2 "inherit the LAB's region, and Foundry/Search deploy to Config.Location - a mismatch will fail"
    Write-Warn2 "or split regions. Recreate the lab in '$($Config.Location)', or align Config.Location to the lab."
}
#endregion

#region ============================ 3. TAGS ================================
Write-Step '3. Applying cost-control tags to the lab'
Update-AzTag -ResourceId $LabResourceId -Tag $Config.Tags -Operation Merge | Out-Null
Write-Ok "Tags applied: $(($Config.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
#endregion

#region ============================ 4. ENTRA GROUP =========================
Write-Step "4. Creating Entra security group '$($Config.GroupName)'"

$group = $null
if (-not $SkipUserCreation) {
    $group = Get-MgGroup -Filter "displayName eq '$($Config.GroupName)'" -ConsistencyLevel eventual -CountVariable c -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($group) {
        Write-Ok "Group already exists (id: $($group.Id)) - reusing."
    } else {
        $group = New-MgGroup -DisplayName $Config.GroupName `
            -MailEnabled:$false -MailNickname $Config.GroupNickname `
            -SecurityEnabled:$true `
            -Description 'AI-901 refugee training cohort learners.'
        Write-Ok "Created group (id: $($group.Id))."
    }
} else {
    Write-Warn2 'SkipUserCreation set - group/user/membership steps skipped.'
}
#endregion

#region ============================ 5. LEARNER ACCOUNTS ====================
Write-Step "5. Creating $($Config.LearnerCount) learner accounts and adding them to the group"

$credentialRows = @()
$learnerMap     = @{}   # index -> UPN
$demoUser       = $null

if (-not $SkipUserCreation) {
    for ($i = 1; $i -le $Config.LearnerCount; $i++) {
        $nn   = '{0:D2}' -f $i
        $upn  = "$($Config.LearnerPrefix)$nn@$($Config.Domain)"
        $disp = "AI-901 Learner $nn"
        $learnerMap[$i] = $upn

        $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existing) {
            Write-Info "$upn already exists - reusing (no password reset)."
            $user = $existing
            $tempPw = $null
        } else {
            $tempPw = New-RandomPassword -Length 16
            $pwProfile = @{
                # Learners sign in with a TAP code (no password change). Keep this $false so the
                # rare password FALLBACK path doesn't force a change screen and contradict the guide.
                ForceChangePasswordNextSignIn = $false
            }
            $pwProfile['Password'] = $tempPw
            $user = New-MgUser -DisplayName $disp `
                -UserPrincipalName $upn `
                -MailNickname "$($Config.LearnerPrefix)$nn" `
                -AccountEnabled:$true `
                -PasswordProfile $pwProfile `
                -UsageLocation 'NL'
            Write-Ok "Created $upn"
        }

        # Idempotent group membership
        if ($group) {
            $isMember = Get-MgGroupMember -GroupId $group.Id -All |
                        Where-Object { $_.Id -eq $user.Id }
            if (-not $isMember) {
                New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
                Write-Info "Added $upn to $($Config.GroupName)."
            }
        }

        if ($tempPw) {
            $credentialRows += [pscustomobject]@{
                LearnerNumber = $nn
                Username      = $upn
                TempPassword  = $tempPw
                MustChange    = 'No (TAP sign-in; password is fallback only)'
            }
        }
    }

    # Write credentials to a file in the workspace output folder (DELETE after handout).
    $credPath = Join-Path $OutputDir 'learner-credentials.csv'
    if ($credentialRows.Count -gt 0) {
        $credentialRows | Export-Csv -Path $credPath -NoTypeInformation -Encoding UTF8
        Write-Warn2 "New temp passwords written to: $credPath  --> distribute securely, then DELETE."
    } else {
        Write-Info 'No learner accounts were created; the credentials CSV was not changed.'
    }

    # --- Demo/test participant: EXISTING guest user (not created), just add to the group ---
    $demoUser = Get-MgUser -Filter "userPrincipalName eq '$($Config.DemoUserUpn)'" `
        -ConsistencyLevel eventual -CountVariable dc -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($demoUser) {
        if ($group) {
            $isMember = Get-MgGroupMember -GroupId $group.Id -All | Where-Object { $_.Id -eq $demoUser.Id }
            if (-not $isMember) {
                New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $demoUser.Id
                Write-Info "Added demo user to $($Config.GroupName)."
            }
        }
        Write-Ok "Demo user found: $($Config.DemoUserUpn)"
    } else {
        Write-Warn2 "Demo user '$($Config.DemoUserUpn)' NOT found - check the configured guest UPN format."
    }
}
#endregion

#region ===================== 5b. TEMPORARY ACCESS PASS (TAP) ===============
if (-not $SkipUserCreation -and -not $SkipTapGeneration) {
    Write-Step '5b. Generating Temporary Access Pass (TAP) codes for phone-free sign-in'

    # Requires: (1) the tenant TAP policy enabled for these users
    #   (Entra admin center > Protection > Authentication methods > Temporary Access Pass), and
    #   (2) the Graph scope UserAuthenticationMethod.ReadWrite.All (requested at login).
    $tapPath      = Join-Path $OutputDir 'learner-tap-codes.csv'
    $savedTapRows = @{}
    if (Test-Path $tapPath) {
        foreach ($savedRow in (Import-Csv -Path $tapPath)) {
            if ($savedRow.Username -and $savedRow.TAP) { $savedTapRows[$savedRow.Username] = $savedRow }
        }
    }
    $tapRows   = @()
    $tapFailed = $false

    # Start the pass at session open if that's still in the future; otherwise let it start now.
    $nowUtc   = (Get-Date).ToUniversalTime()
    $tapStart = if ($SessionStart.UtcDateTime -gt $nowUtc) { $SessionStart.UtcDateTime } else { $null }

    foreach ($i in ($learnerMap.Keys | Sort-Object)) {
        $upn  = $learnerMap[$i]

        try { $existingTap = Get-MgUserAuthenticationTemporaryAccessPassMethod -UserId $upn -ErrorAction Stop }
        catch { $existingTap = $null }

        # Graph never returns an existing TAP's secret again. Keep it only when its code is still
        # available locally; otherwise replace it so the resulting CSV always contains a usable code.
        if ($existingTap -and $savedTapRows.ContainsKey($upn)) {
            $tapRows += $savedTapRows[$upn]
            Write-Info "TAP already exists for $upn - keeping code from the existing CSV."
            continue
        }
        if ($existingTap) {
            try {
                foreach ($method in @($existingTap)) {
                    Remove-MgUserAuthenticationTemporaryAccessPassMethod `
                        -UserId $upn `
                        -TemporaryAccessPassAuthenticationMethodId $method.Id `
                        -Confirm:$false `
                        -ErrorAction Stop
                }
                Write-Info "Replaced unrecoverable TAP for $upn because its code was not in the CSV."
            } catch {
                Write-Warn2 "Existing TAP removal failed for $upn : $($_.Exception.Message)"
                $tapFailed = $true
                break
            }
        }

        $body = @{
            isUsableOnce      = [bool]$Config.TapUsableOnce
            lifetimeInMinutes = [int]$Config.TapLifetimeMinutes
        }
        if ($tapStart) { $body.startDateTime = $tapStart.ToString('o') }
        try {
            $tap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $upn -BodyParameter $body -ErrorAction Stop
            $tapRows += [pscustomobject]@{
                LearnerNumber = '{0:D2}' -f $i
                Username      = $upn
                TAP           = $tap.TemporaryAccessPass
                StartsUtc     = $tap.StartDateTime
                Minutes       = $tap.LifetimeInMinutes
                UsableOnce    = $tap.IsUsableOnce
            }
            Write-Ok "TAP created for $upn"
        } catch {
            Write-Warn2 "TAP creation failed for $upn : $($_.Exception.Message)"
            $tapFailed = $true
            break   # stop after the first failure - it's almost always a policy/scope issue for all
        }
    }

    if (-not $tapFailed -and $tapRows.Count -eq $learnerMap.Count) {
        $tapRows | Export-Csv -Path $tapPath -NoTypeInformation -Encoding UTF8
        Write-Warn2 "TAP codes written to: $tapPath  --> distribute securely, then DELETE."
    } elseif ($tapRows.Count -gt 0) {
        Write-Warn2 'The TAP CSV was not changed because generation did not complete for every learner.'
    }
    if ($tapFailed) {
        Write-Warn2 'TAP generation stopped after a failure. Common causes:'
        Write-Warn2 '  - the Temporary Access Pass policy is not enabled for these users, or'
        Write-Warn2 '  - the sign-in lacks UserAuthenticationMethod.ReadWrite.All.'
        Write-Warn2 'Enable it: Entra admin center > Protection > Authentication methods > Temporary Access Pass.'
        Write-Warn2 'Fallback: learners can sign in with the temp password in learner-credentials.csv.'
    }
} elseif ($SkipTapGeneration) {
    Write-Info 'SkipTapGeneration set - no TAP codes generated (learners use temp passwords).'
}
#endregion

if ($GenerateTapOnly) {
    if ($SkipTapGeneration) { throw 'GenerateTapOnly cannot be combined with SkipTapGeneration.' }
    if ($SkipUserCreation) { throw 'GenerateTapOnly cannot be combined with SkipUserCreation.' }
    Write-Ok 'GenerateTapOnly completed; Azure resource deployment was skipped.'
    return
}

#region ============================ 6. RBAC ================================
Write-Step '6. Assigning least-privilege RBAC'

function Set-RoleAssignmentIdempotent {
    param(
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)][string]$RoleDefinitionName,
        [Parameter(Mandatory)][string]$Scope
    )
    # Skip (don't abort) if the role doesn't exist in this tenant/subscription - some newer
    # built-ins (e.g. 'Azure AI User') may not be registered yet. Assign manually if needed.
    if (-not (Get-AzRoleDefinition -Name $RoleDefinitionName -ErrorAction SilentlyContinue)) {
        Write-Warn2 "Role '$RoleDefinitionName' not found in this subscription - skipping (assign manually if required)."
        return $false
    }
    $existing = Get-AzRoleAssignment -ObjectId $ObjectId -Scope $Scope -RoleDefinitionName $RoleDefinitionName -ErrorAction SilentlyContinue |
                Where-Object { $_.Scope -eq $Scope }
    if ($existing) { return $false }
    New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope | Out-Null
    return $true
}

# Resolves the object id of the principal running this deployment (used to grant the deployer
# temporary data-plane rights so it can build the KEYLESS Search index).
function Get-CurrentPrincipalObjectId {
    try { $u = Get-AzADUser -SignedIn -ErrorAction Stop; if ($u) { return $u.Id } } catch {}
    try {
        $acct = (Get-AzContext).Account.Id
        $u = Get-AzADUser -UserPrincipalName $acct -ErrorAction Stop
        if ($u) { return $u.Id }
    } catch {}
    return $null
}

# Builds + populates the 'hr-index' that Foundry IQ (lab 07) searches, using the SAME index
# schema + HR documents as the official lab setup (setup/index-schema.json + setup/hr-data.json),
# but KEYLESS: every data-plane call uses an Entra bearer token instead of the Search admin key.
function Initialize-HrSearchIndex {
    param(
        [Parameter(Mandatory)][string]$SearchName,
        [Parameter(Mandatory)][string]$SearchResourceId
    )
    $endpoint = "https://$SearchName.search.windows.net"
    $indexApi = '2023-11-01'
    $repoBase = 'https://raw.githubusercontent.com/MicrosoftLearning/mslearn-ai-fundamentals/main/setup'

    # Give the deploying principal data-plane rights so it can create the index + upload docs.
    $me = Get-CurrentPrincipalObjectId
    if ($me) {
        foreach ($r in @('Search Service Contributor','Search Index Data Contributor')) {
            Set-RoleAssignmentIdempotent -ObjectId $me -RoleDefinitionName $r -Scope $SearchResourceId | Out-Null
        }
    } else {
        Write-Warn2 'Could not resolve the deploying principal - you may need Search Index Data Contributor to build hr-index.'
    }

    # Pull the official index schema + HR data verbatim (no re-serialization).
    try {
        $schemaJson = (Invoke-WebRequest -Uri "$repoBase/index-schema.json" -UseBasicParsing).Content
        $dataJson   = (Invoke-WebRequest -Uri "$repoBase/hr-data.json"     -UseBasicParsing).Content
    } catch {
        Write-Warn2 "Could not download hr-index schema/data from the lab repo: $($_.Exception.Message)"
        return
    }

    # Data-plane auth: Entra bearer token for the Azure AI Search audience (handles Az v12 SecureString).
    $tok   = Get-AzAccessToken -ResourceUrl 'https://search.azure.com'
    $token = if ($tok.Token -is [System.Security.SecureString]) {
                 (New-Object System.Net.NetworkCredential('', $tok.Token)).Password
             } else { $tok.Token }
    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

    # Create the index (idempotent PUT). Retry: data-plane RBAC can take ~1 min to propagate.
    $created = $false
    for ($i = 1; $i -le 10; $i++) {
        try {
            Invoke-RestMethod -Method PUT -Uri "$endpoint/indexes/hr-index?api-version=$indexApi" `
                -Headers $headers -Body $schemaJson | Out-Null
            $created = $true; break
        } catch { Start-Sleep -Seconds 15 }
    }
    if (-not $created) {
        Write-Warn2 "Failed to create 'hr-index' (RBAC propagation/quota?). Build it with setup/deploy-search.sh."
        return
    }
    Write-Ok "Search index 'hr-index' created."

    # Upload the HR policy documents.
    for ($i = 1; $i -le 6; $i++) {
        try {
            Invoke-RestMethod -Method POST -Uri "$endpoint/indexes/hr-index/docs/index?api-version=$indexApi" `
                -Headers $headers -Body $dataJson | Out-Null
            Write-Ok "HR policy documents uploaded to 'hr-index'."
            return
        } catch { Start-Sleep -Seconds 10 }
    }
    Write-Warn2 "hr-index created but document upload failed - re-run, or upload hr-data.json manually."
}

# Grants a role either PERMANENTLY (-PermanentAccess), or TIME-BOUND to the fixed session
# window (default): access starts at $SessionStart and auto-revokes at $SessionEnd. Time-bound
# assignments require Entra ID P2 / PIM for Azure resources; if unavailable we fall back to
# permanent and rely on Enforce-SessionTimeout.ps1 to cut access at the window end.
function Grant-GroupAccess {
    param(
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)][string]$RoleDefinitionName,
        [Parameter(Mandatory)][string]$Scope
    )
    # Don't abort the whole deployment if a role isn't available in this tenant/subscription
    # (e.g. 'Azure AI User' when the AIServices RP roles haven't propagated). Warn and move on.
    if (-not (Get-AzRoleDefinition -Name $RoleDefinitionName -ErrorAction SilentlyContinue)) {
        Write-Warn2 "Role '$RoleDefinitionName' not available in this tenant/subscription - skipping this grant (assign manually if learners need it)."
        return
    }
    if (-not $PermanentAccess) {
        try {
            $roleDef   = Get-AzRoleDefinition -Name $RoleDefinitionName
            $roleDefId = "/subscriptions/$($Config.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$($roleDef.Id)"
            New-AzRoleAssignmentScheduleRequest -Name (New-Guid).Guid -Scope $Scope `
                -PrincipalId $ObjectId -RoleDefinitionId $roleDefId -RequestType 'AdminAssign' `
                -ScheduleInfoStartDateTime $SessionStart.UtcDateTime.ToString('o') `
                -ExpirationType 'AfterDateTime' -ExpirationEndDateTime $SessionEnd.UtcDateTime.ToString('o') `
                -ErrorAction Stop | Out-Null
            Write-Ok "Time-bound '$RoleDefinitionName' granted ($($SessionStart.ToString('u')) -> $($SessionEnd.ToString('u')), auto-revoke)."
            return
        } catch {
            Write-Warn2 "Time-bound grant failed (needs Entra P2/PIM): $($_.Exception.Message)"
            Write-Warn2 "Falling back to PERMANENT; enforce the cutoff with Enforce-SessionTimeout.ps1."
        }
    }
    if (Set-RoleAssignmentIdempotent -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope) {
        Write-Ok "'$RoleDefinitionName' assigned at scope."
    } else {
        Write-Info "'$RoleDefinitionName' already present at scope."
    }
}

# Primary (requested): group gets "DevTest Labs User" at LAB scope.
# Everything is scoped to the Refugee RG's resources ONLY (lab, Foundry, Search) and never
# to the subscription, so learners cannot see any other resource group in the portal.
if ($group) {
    Grant-GroupAccess -ObjectId $group.Id -RoleDefinitionName 'DevTest Labs User' -Scope $LabResourceId
}
#endregion

#region ==================== 6b. SHARED AI RESOURCES (Foundry + Search) ======
Write-Step '6b. Creating the ONE shared Foundry account + Azure AI Search (Entra-only / keyless)'

if ($SkipSharedAiResources) {
    Write-Warn2 'SkipSharedAiResources set - Foundry/Search not created.'
} else {
    $rgId      = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroup)"
    $foundryId = "$rgId/providers/Microsoft.CognitiveServices/accounts/$($Config.FoundryName)"
    $projectId = "$foundryId/projects/$($Config.FoundryProject)"
    $deployId  = "$foundryId/deployments/$($Config.ModelName)"
    $searchId  = "$rgId/providers/Microsoft.Search/searchServices/$($Config.SearchName)"
    $csApi     = '2025-06-01'
    $searchApi = '2023-11-01'

    # --- ONE Foundry account: system-assigned MI, keyless (Entra-only) ---
    $foundryBody = @{
        location   = $Config.Location
        kind       = 'AIServices'
        sku        = @{ name = 'S0' }
        identity   = @{ type = 'SystemAssigned' }
        properties = @{
            allowProjectManagement = $true
            customSubDomainName    = $Config.FoundryName
            disableLocalAuth       = [bool]$Config.EntraOnlyAuth
            publicNetworkAccess    = 'Enabled'
        }
        tags = $Config.Tags
    }
    $foundry = Invoke-ArmRest -Method PUT -ResourceId $foundryId -ApiVersion $csApi -Body $foundryBody
    $foundryMiPrincipalId = $foundry.identity.principalId
    Write-Ok "Foundry account '$($Config.FoundryName)' accepted (keyless=$($Config.EntraOnlyAuth))."

    # --- Wait for the account to finish provisioning before creating child resources ---
    # The PUT above returns while the account is still 'Creating'/'Accepted'. Creating the
    # project too early fails with 400 "Parent account does not provision correctly".
    $provState = $foundry.properties.provisioningState
    $deadline  = (Get-Date).AddMinutes(10)
    while ($provState -notin @('Succeeded','Failed','Canceled') -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
        $foundry   = Invoke-ArmRest -Method GET -ResourceId $foundryId -ApiVersion $csApi
        $provState = $foundry.properties.provisioningState
        Write-Host "    ...Foundry provisioningState = $provState" -ForegroundColor DarkGray
    }
    if ($provState -ne 'Succeeded') {
        throw "Foundry account '$($Config.FoundryName)' did not provision (state=$provState). Re-run to retry."
    }
    if (-not $foundryMiPrincipalId) { $foundryMiPrincipalId = $foundry.identity.principalId }
    Write-Ok "Foundry account '$($Config.FoundryName)' provisioned (state=Succeeded)."

    # --- Foundry project (what learners open in the portal) ---
    $projectBody = @{
        location   = $Config.Location
        identity   = @{ type = 'SystemAssigned' }
        properties = @{ displayName = 'AI-901 Project'; description = 'Shared AI-901 training project.' }
    }
    Invoke-ArmRest -Method PUT -ResourceId $projectId -ApiVersion $csApi -Body $projectBody | Out-Null
    Write-Ok "Foundry project '$($Config.FoundryProject)' ready."

    # --- Model deployment for the playground labs ---
    $modelSpec = @{ format = 'OpenAI'; name = $Config.ModelName }
    if ($Config.ModelVersion) { $modelSpec.version = $Config.ModelVersion }  # omit -> use default version
    $deployBody = @{
        sku        = @{ name = $Config.ModelSku; capacity = $Config.ModelCapacity }
        properties = @{ model = $modelSpec }
    }
    try {
        Invoke-ArmRest -Method PUT -ResourceId $deployId -ApiVersion $csApi -Body $deployBody | Out-Null
        Write-Ok "Model '$($Config.ModelName)' deployed ($($Config.ModelSku), cap $($Config.ModelCapacity))."
    } catch {
        Write-Warn2 "Model deployment failed (region/quota?). Deploy manually in Foundry. $($_.Exception.Message)"
    }

    # --- ONE Azure AI Search: keyless (Entra-only) ---
    $searchBody = @{
        location   = $Config.Location
        sku        = @{ name = $Config.SearchSku }
        identity   = @{ type = 'SystemAssigned' }
        properties = @{
            replicaCount        = 1
            partitionCount      = 1
            hostingMode         = 'default'
            disableLocalAuth    = [bool]$Config.EntraOnlyAuth
            publicNetworkAccess = 'enabled'
        }
        tags = $Config.Tags
    }
    if (-not $Config.EntraOnlyAuth) {
        $searchBody.properties.authOptions = @{ aadOrApiKey = @{ aadAuthFailureMode = 'http401WithBearerChallenge' } }
    }
    Invoke-ArmRest -Method PUT -ResourceId $searchId -ApiVersion $searchApi -Body $searchBody | Out-Null
    Write-Ok "Azure AI Search '$($Config.SearchName)' ready ($($Config.SearchSku), keyless=$($Config.EntraOnlyAuth))."

    # --- Managed identity wiring: Foundry MI -> Search (service-to-service, keyless) ---
    # This is the correct use of a managed identity here: Foundry IQ (lab 07) builds/queries
    # Search indexes AS the Foundry account, with NO stored keys.
    if ($foundryMiPrincipalId) {
        foreach ($r in @('Search Service Contributor','Search Index Data Contributor')) {
            if (Set-RoleAssignmentIdempotent -ObjectId $foundryMiPrincipalId -RoleDefinitionName $r -Scope $searchId) {
                Write-Ok "Foundry managed identity granted '$r' on Search."
            }
        }
    }

    # --- Build + populate the 'hr-index' used by Foundry IQ (lab 07), keyless via Entra ---
    Initialize-HrSearchIndex -SearchName $Config.SearchName -SearchResourceId $searchId

    # --- Learner group RBAC on the shared resources (time-bound if requested) ---
    # ONE shared project: learners AUTHOR agents + Foundry IQ knowledge bases in it, so they need
    # project BUILD access (Azure AI User), not just inference. To avoid learner name clashes, tell
    # learners to suffix their objects (e.g. hr-agent-05, speech-agent-05).
    if ($group) {
        Grant-GroupAccess -ObjectId $group.Id -RoleDefinitionName 'Cognitive Services User'        -Scope $foundryId
        Grant-GroupAccess -ObjectId $group.Id -RoleDefinitionName 'Cognitive Services OpenAI User' -Scope $foundryId
        Grant-GroupAccess -ObjectId $group.Id -RoleDefinitionName 'Foundry User'                    -Scope $foundryId
        Grant-GroupAccess -ObjectId $group.Id -RoleDefinitionName 'Search Index Data Reader'       -Scope $searchId
        # 'Reader' (control plane) lets learners SELECT the shared Search resource in the Foundry IQ
        # "Connect to an AI Search resource" dialog. Indexing/query runs as the Foundry MI (keyless).
        Grant-GroupAccess -ObjectId $group.Id -RoleDefinitionName 'Reader'                         -Scope $searchId
    }

    Write-Ok "Foundry endpoint: https://$($Config.FoundryName).cognitiveservices.azure.com/"
    Write-Ok "Foundry portal  : https://ai.azure.com  (project '$($Config.FoundryProject)')"
    Write-Ok "Search service  : $($Config.SearchName)"
}
#endregion

#region ============= 7. DISCOVER VNET + WINDOWS 10 GALLERY IMAGE ===========
Write-Step '7. Discovering lab virtual network and Windows 10 Enterprise gallery image'

# 7a. Lab virtual network + subnet allowed for VM creation
$vnets = Invoke-DtlRest -Method GET -RelativePath '/virtualnetworks'
$labVnet = $vnets.value | Select-Object -First 1
if (-not $labVnet) { throw 'No virtual network found in the lab. Create/associate one in the portal first.' }
$labVnetId = $labVnet.id
$labSubnetName = ($labVnet.properties.subnetOverrides |
    Where-Object { $_.useInVmCreationPermission -eq 'Allow' } |
    Select-Object -First 1).labSubnetName
if (-not $labSubnetName) { $labSubnetName = $labVnet.properties.subnetOverrides[0].labSubnetName }
Write-Ok "Lab VNet: $($labVnet.name) / subnet: $labSubnetName"

# 7c. Enable the lab SHARED PUBLIC IP for RDP on this subnet and DENY per-VM public IPs.
#     VMs are created with disallowPublicIpAddress=true (no individual public IP); learners instead
#     reach each VM through the lab's single shared public IP on a unique NAT port (backend 3389 ->
#     an auto-assigned frontend port). This is what makes RDP work WITHOUT giving every VM its own
#     public IP and WITHOUT standing up Azure Bastion. Idempotent: PUT-ing the same config is a no-op.
$soList = @()
foreach ($so in $labVnet.properties.subnetOverrides) {
    $entry = @{
        labSubnetName             = $so.labSubnetName
        resourceId                = $so.resourceId
        useInVmCreationPermission = $so.useInVmCreationPermission
    }
    if ($so.labSubnetName -eq $labSubnetName) {
        $entry.usePublicIpAddressPermission     = 'Deny'
        $entry.sharedPublicIpAddressConfiguration = @{
            allowedPorts = @(@{ transportProtocol = 'Tcp'; backendPort = 3389 })
        }
    } elseif (($so.PSObject.Properties.Name -contains 'usePublicIpAddressPermission') -and $so.usePublicIpAddressPermission) {
        $entry.usePublicIpAddressPermission = $so.usePublicIpAddressPermission
    }
    $soList += $entry
}
$vnetBody = @{
    location   = $Config.Location
    properties = @{
        externalProviderResourceId = $labVnet.properties.externalProviderResourceId
        subnetOverrides            = $soList
    }
}
Invoke-DtlRest -Method PUT -RelativePath "/virtualnetworks/$($labVnet.name)" -Body $vnetBody | Out-Null
Write-Ok "Shared public IP enabled for RDP (TCP 3389) on subnet '$labSubnetName'; per-VM public IPs denied."

# 7b. Windows 10 Enterprise gallery image available in THIS lab (no invented URNs)
$images = Invoke-DtlRest -Method GET -RelativePath '/galleryimages'
$win10 = $images.value | Where-Object {
    $_.properties.imageReference.offer -like '*Windows-10*' -and
    $_.properties.imageReference.sku   -like '*ent*'
} | Sort-Object { $_.properties.imageReference.sku } -Descending | Select-Object -First 1

if (-not $win10) {
    Write-Warn2 'No Windows 10 Enterprise gallery image auto-detected in this lab.'
    Write-Warn2 'Available Windows 10 images:'
    $images.value |
        Where-Object { $_.properties.imageReference.offer -like '*Windows-10*' } |
        ForEach-Object { Write-Host ("      {0} | {1} | {2}" -f `
            $_.properties.imageReference.publisher, `
            $_.properties.imageReference.offer, `
            $_.properties.imageReference.sku) }
    throw 'Set the correct image manually from the list above, then re-run.'
}
$imgRef = $win10.properties.imageReference
Write-Ok "Image: $($imgRef.publisher) / $($imgRef.offer) / $($imgRef.sku) / $($imgRef.version)"
#endregion

#region ============================ 8. LAB POLICIES ========================
Write-Step '8. Configuring DevTest Lab policies'

function Set-DtlPolicy {
    param([string]$Name, [string]$FactName, [string]$EvaluatorType, [string]$Threshold)
    $body = @{
        properties = @{
            factName      = $FactName
            evaluatorType = $EvaluatorType
            threshold     = $Threshold
            status        = 'Enabled'
        }
    }
    Invoke-DtlRest -Method PUT -RelativePath "/policysets/default/policies/$Name" -Body $body | Out-Null
    Write-Ok "Policy '$Name' set ($Threshold)."
}

# Allowed VM size = Standard_B2ms only
Set-DtlPolicy -Name 'AllowedVmSizesInLab' -FactName 'LabVmSize' -EvaluatorType 'AllowedValuesPolicy' -Threshold ('["' + $Config.VMSize + '"]')
# Max 1 VM per user
Set-DtlPolicy -Name 'UserOwnedLabVmCount' -FactName 'UserOwnedLabVmCount' -EvaluatorType 'MaxValuePolicy' -Threshold '1'
# Total VMs: learner VMs plus the optional demo/test VM
$labVmCount = $Config.LearnerCount + $(if ($SkipDemoVm) { 0 } else { 1 })
Set-DtlPolicy -Name 'LabVmCount' -FactName 'LabVmCount' -EvaluatorType 'MaxValuePolicy' -Threshold "$labVmCount"
#endregion

#region ============================ 9. AUTO-SHUTDOWN =======================
Write-Step "9. Enabling auto-shutdown ($($Config.ShutdownTime) $($Config.ShutdownTimeZone)) and auto-start ($($Config.StartupTime))"

$shutdownBody = @{
    location   = $Config.Location
    properties = @{
        status          = 'Enabled'
        taskType        = 'LabVmsShutdownTask'
        dailyRecurrence = @{ time = $Config.ShutdownTime }
        timeZoneId      = $Config.ShutdownTimeZone
        notificationSettings = @{ status = 'Disabled'; timeInMinutes = 30 }
    }
}
Invoke-DtlRest -Method PUT -RelativePath '/schedules/LabVmsShutdown' -Body $shutdownBody | Out-Null
Write-Ok "Auto-shutdown at $($Config.ShutdownTime) ($($Config.ShutdownTimeZone))."

# Lab-level auto-start policy on the session's weekday. Each VM is additionally opted in at creation
# (Region 11) because DTL does NOT auto-start VMs from the lab policy alone.
$startupWeekday = $SessionStart.DayOfWeek.ToString()
$autoStartBody = @{
    location   = $Config.Location
    properties = @{
        status           = 'Enabled'
        taskType         = 'LabVmsStartupTask'
        weeklyRecurrence = @{ weekdays = @($startupWeekday); time = $Config.StartupTime }
        timeZoneId       = $Config.ShutdownTimeZone
        notificationSettings = @{ status = 'Disabled'; timeInMinutes = 15 }
    }
}
Invoke-DtlRest -Method PUT -RelativePath '/schedules/LabVmAutoStart' -Body $autoStartBody | Out-Null
Write-Ok "Auto-start at $($Config.StartupTime) ($startupWeekday, $($Config.ShutdownTimeZone)); VMs opted in at creation."
#endregion

#region 10. SECURE VM CREDENTIAL INPUT
Write-Step '10. Obtaining VM local admin password (never hard-coded)'

if ($KeyVaultName -and $VMAdminPasswordSecretName) {
    $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $VMAdminPasswordSecretName
    $vmSecurePassword = $secret.SecretValue
    Write-Ok "VM admin password retrieved from Key Vault '$KeyVaultName'."
} else {
    $vmSecurePassword = Read-Host -AsSecureString -Prompt "Enter LOCAL VM admin password for user '$($Config.LocalAdminUser)'"
    Write-Ok 'VM admin password captured securely (SecureString).'
}
#endregion

#region ============================ 11. CREATE VMs =========================
Write-Step "11. Creating $($Config.LearnerCount) DevTest Lab learner VMs (idempotent)"

$vmTemplate = @'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "labName":        { "type": "string" },
    "vmName":         { "type": "string" },
    "location":       { "type": "string" },
    "vmSize":         { "type": "string" },
    "storageType":    { "type": "string" },
    "userName":       { "type": "string" },
    "password":       { "type": "securestring" },
    "labVnetId":      { "type": "string" },
    "labSubnetName":  { "type": "string" },
    "imagePublisher": { "type": "string" },
    "imageOffer":     { "type": "string" },
    "imageSku":       { "type": "string" },
    "imageVersion":   { "type": "string" },
    "notes":          { "type": "string" }
  },
  "resources": [
    {
      "type": "Microsoft.DevTestLab/labs/virtualmachines",
      "name": "[concat(parameters('labName'), '/', parameters('vmName'))]",
      "apiVersion": "2018-09-15",
      "location": "[parameters('location')]",
      "properties": {
        "labVirtualNetworkId": "[parameters('labVnetId')]",
        "labSubnetName": "[parameters('labSubnetName')]",
        "size": "[parameters('vmSize')]",
        "userName": "[parameters('userName')]",
        "password": "[parameters('password')]",
        "isAuthenticationWithSshKey": false,
        "disallowPublicIpAddress": true,
        "sharedPublicIpAddressConfiguration": {
          "inboundNatRules": [
            { "transportProtocol": "Tcp", "backendPort": 3389 }
          ]
        },
        "storageType": "[parameters('storageType')]",
        "allowClaim": false,
        "notes": "[parameters('notes')]",
        "galleryImageReference": {
          "publisher": "[parameters('imagePublisher')]",
          "offer": "[parameters('imageOffer')]",
          "sku": "[parameters('imageSku')]",
          "osType": "Windows",
          "version": "[parameters('imageVersion')]"
        }
      }
    }
  ]
}
'@

$templatePath = Join-Path $OutputDir 'dtl-vm.template.json'
$vmTemplate | Set-Content -Path $templatePath -Encoding UTF8

# Per-learner double-click .rdp files land here (host/port/user pre-filled; learner types only the password).
$rdpDir = Join-Path $OutputDir 'rdp'
$null = New-Item -ItemType Directory -Path $rdpDir -Force

$summary = @()

for ($i = 1; $i -le $Config.LearnerCount; $i++) {
    $nn      = '{0:D2}' -f $i
    $vmName  = "$($Config.VmNamePrefix)$nn"
    $vmResId = "$LabResourceId/virtualmachines/$vmName"
    $upn     = if ($learnerMap.ContainsKey($i)) { $learnerMap[$i] } else { "$($Config.LearnerPrefix)$nn@$($Config.Domain)" }
    $note    = ''

    $existingVm = Get-AzResource -ResourceId $vmResId -ErrorAction SilentlyContinue
    if ($existingVm) {
        Write-Info "$vmName already exists - skipping creation."
        $note = 'Existing (skipped)'
    } elseif ($SkipVmCreation) {
        Write-Info "SkipVmCreation set - $vmName not created."
        $note = 'Not created (SkipVmCreation)'
    } else {
        $params = @{
            labName        = $Config.LabName
            vmName         = $vmName
            location       = $Config.Location
            vmSize         = $Config.VMSize
            storageType    = $Config.StorageType
            userName       = $Config.LocalAdminUser
            labVnetId      = $labVnetId
            labSubnetName  = $labSubnetName
            imagePublisher = $imgRef.publisher
            imageOffer     = $imgRef.offer
            imageSku       = $imgRef.sku
            imageVersion   = $imgRef.version
            notes          = "AI-901 $upn"
        }
        Write-Info "Creating $vmName ..."
        New-AzResourceGroupDeployment `
            -ResourceGroupName $Config.ResourceGroup `
            -Name "dtlvm-$vmName-$(Get-Date -Format 'yyyyMMddHHmmss')" `
            -TemplateFile $templatePath `
            -TemplateParameterObject $params `
            -password $vmSecurePassword `
            -ErrorAction Stop | Out-Null
        Write-Ok "$vmName created."
        $note = 'Created'
    }

    # Optional strict least-privilege: learnerNN owns ONLY ai901-studentNN
    $assignedRole = 'DevTest Labs User (group @ lab scope)'
    if ($AssignPerVmOwnership -and -not $SkipUserCreation) {
        $u = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($u -and (Get-AzResource -ResourceId $vmResId -ErrorAction SilentlyContinue)) {
            if (Set-RoleAssignmentIdempotent -ObjectId $u.Id -RoleDefinitionName 'DevTest Labs User' -Scope $vmResId) {
                Write-Info "Assigned $upn 'DevTest Labs User' on $vmName."
            }
            $assignedRole = 'DevTest Labs User (per-VM)'
        }
    }

    # Shared-IP RDP endpoint (host:port on the lab's single public IP) so learners know where to connect.
    $rdp = if ($note -like 'Not created*') { '(not created)' } else { Get-DtlVmRdpEndpoint -VmName $vmName }

    # Opt this VM into the auto-start safety net so it's already running at teaching time.
    if ($note -notlike 'Not created*') {
        [void](Enable-DtlVmAutoStart -VmName $vmName -Time $Config.StartupTime -Weekday $startupWeekday -TimeZoneId $Config.ShutdownTimeZone)
    }

    # Pre-built double-click .rdp handout named after the learner login (e.g. connect-learner01.rdp).
    $rdpFile = ''
    $loginName = ($upn -split '@')[0]
    $candidate = Join-Path $rdpDir "connect-$loginName.rdp"
    if (New-RdpFile -Endpoint $rdp -UserName $Config.LocalAdminUser -Path $candidate) { $rdpFile = $candidate }

    $summary += [pscustomobject]@{
        LearnerNumber = $nn
        Username      = $upn
        VMName        = $vmName
        VMResourceId  = $vmResId
        AssignedRole  = $assignedRole
        RdpConnect    = $rdp
        RdpFile       = $rdpFile
        Notes         = $note
    }
}

# --- Demo/test VM for the existing guest user (access via the time-bound group) ---
$demoVmName  = $Config.DemoVmName
$demoVmResId = "$LabResourceId/virtualmachines/$demoVmName"
$demoNote    = ''
$existingDemo = Get-AzResource -ResourceId $demoVmResId -ErrorAction SilentlyContinue
if ($SkipDemoVm) {
    Write-Info "SkipDemoVm set - $demoVmName not created."
    $demoNote = 'Not created (SkipDemoVm)'
} elseif ($existingDemo) {
    Write-Info "$demoVmName already exists - skipping creation."
    $demoNote = 'Existing (skipped)'
} elseif ($SkipVmCreation) {
    Write-Info "SkipVmCreation set - $demoVmName not created."
    $demoNote = 'Not created (SkipVmCreation)'
} else {
    $demoParams = @{
        labName        = $Config.LabName
        vmName         = $demoVmName
        location       = $Config.Location
        vmSize         = $Config.VMSize
        storageType    = $Config.StorageType
        userName       = $Config.LocalAdminUser
        labVnetId      = $labVnetId
        labSubnetName  = $labSubnetName
        imagePublisher = $imgRef.publisher
        imageOffer     = $imgRef.offer
        imageSku       = $imgRef.sku
        imageVersion   = $imgRef.version
        notes          = "AI-901 DEMO $($Config.DemoUserUpn)"
    }
    Write-Info "Creating $demoVmName ..."
    New-AzResourceGroupDeployment `
        -ResourceGroupName $Config.ResourceGroup `
        -Name "dtlvm-$demoVmName-$(Get-Date -Format 'yyyyMMddHHmmss')" `
        -TemplateFile $templatePath `
        -TemplateParameterObject $demoParams `
        -password $vmSecurePassword `
        -ErrorAction Stop | Out-Null
    Write-Ok "$demoVmName created."
    $demoNote = 'Created'
}
# The demo user is a group member, so it already gets DevTest Labs User at lab scope covering
# ai901-demo -- and it experiences the SAME time-bound cutoff as learners (good for testing).
if ($demoNote -notlike 'Not created*') {
    [void](Enable-DtlVmAutoStart -VmName $demoVmName -Time $Config.StartupTime -Weekday $startupWeekday -TimeZoneId $Config.ShutdownTimeZone)
}
$demoRdp     = if ($demoNote -like 'Not created*') { '(not created)' } else { Get-DtlVmRdpEndpoint -VmName $demoVmName }
$demoRdpFile = ''
$demoCandidate = Join-Path $rdpDir 'connect-demo.rdp'
if (New-RdpFile -Endpoint $demoRdp -UserName $Config.LocalAdminUser -Path $demoCandidate) { $demoRdpFile = $demoCandidate }
$summary += [pscustomobject]@{
    LearnerNumber = 'DEMO'
    Username      = $Config.DemoUserUpn
    VMName        = $demoVmName
    VMResourceId  = $demoVmResId
    AssignedRole  = ($(if ($PermanentAccess) { 'DevTest Labs User (group, permanent)' } else { 'DevTest Labs User (group, time-bound)' }))
    RdpConnect    = $demoRdp
    RdpFile       = $demoRdpFile
    Notes         = ($(if ($demoUser) { $demoNote } else { "$demoNote; demo user NOT in group - check UPN" }))
}
#endregion

#region ============================ 12. SUMMARY ============================
Write-Step '12. Deployment summary'

$summaryPath = Join-Path $OutputDir 'ai901-deployment-summary.csv'
$summary | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8
$summary | Format-Table -AutoSize

Write-Host ''
Write-Ok "Summary CSV: $summaryPath"
Write-Info "RDP: VMs have NO public IP; connect via the lab SHARED public IP using the 'RdpConnect' host:port in the summary CSV."
Write-Ok  "Double-click RDP handouts (one per learner, pre-filled host/port/user): $rdpDir"
if (-not $SkipUserCreation) { Write-Warn2 "Learner credentials CSV (delete after handout): $(Join-Path $OutputDir 'learner-credentials.csv')" }
if (-not $SkipUserCreation -and -not $SkipTapGeneration) { Write-Warn2 "Learner TAP codes CSV (primary sign-in; delete after handout): $(Join-Path $OutputDir 'learner-tap-codes.csv')" }
if ($PermanentAccess) {
    Write-Warn2 'PermanentAccess set - access does NOT auto-expire. Run Enforce-SessionTimeout.ps1 at the window end, or re-run without -PermanentAccess.'
} else {
    Write-Ok "Lab window: $($SessionStart.ToString('u')) -> $($SessionEnd.ToString('u')) (auto-revoke via PIM)."
    Write-Info 'If PIM (Entra P2) is unavailable, grants fell back to permanent - schedule Enforce-SessionTimeout.ps1 at the window end.'
}
Write-Host ''
Write-Host 'DEPLOYMENT COMPLETE' -ForegroundColor Green
Write-Host 'NEXT ACTION: Open docs/Instructor-Guide.md and complete section 4, "Test it yourself".' -ForegroundColor Cyan
Write-Info 'Learner instructions: docs/Learner-Guide.md'
Write-Info 'Keep credentials and TAP files private. Delete them after distribution and the session.'
#endregion
