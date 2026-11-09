#Requires -Version 5.1

<#
.SYNOPSIS
    Starts the Phase 01 AVD desktop build for a ServiceNow RITM.

.DESCRIPTION
    A technician runs this by hand with the RITM number and requested-for UPN.
    It checks the input, refuses a duplicate build, asks Azure DevOps to validate
    the request without starting anything, shows what will be built, and queues
    the pipeline after confirmation.

    Azure DevOps does the build; nothing is installed or changed on this computer.
    With -WhatIf every check runs but no pipeline run is created.

.PARAMETER Workload
    Workload that receives the desktop, as listed in the pipeline. It selects the
    host pool, resource groups, and subnet. Azure DevOps rejects an unknown name
    during the preview, before anything starts.

.PARAMETER RitmNumber
    RITM followed by 1-12 digits, for example RITM0012345.

.PARAMETER RequestedForUpn
    User principal name of the person receiving the desktop.

.PARAMETER AuthMethod
    AzCli uses your 'az login' session (preferred). Pat reads the
    AZURE_DEVOPS_EXT_PAT environment variable or prompts for a hidden entry.

.PARAMETER SettingsPath
    JSON file holding organization, project, pipelineId, and branch.

.PARAMETER Wait
    Stay until the pipeline finishes, then show text for the RITM work notes.

.PARAMETER WaitMinutes
    Maximum wait. The pipeline's job timeouts total about 200 minutes.

.PARAMETER PollSeconds
    Seconds between status checks while waiting.

.PARAMETER Force
    Queue even though a run for this RITM already succeeded. A run still in
    progress always blocks a new one.

.EXAMPLE
    .\Start-AvdBuild.ps1 -Workload finance -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -WhatIf

    Runs every check and shows what would be built. Starts nothing.

.EXAMPLE
    .\Start-AvdBuild.ps1 -Workload finance -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -Wait

    Queues the build after confirmation and waits for the result.

.NOTES
    Runs API: https://learn.microsoft.com/rest/api/azure/devops/pipelines/runs/run-pipeline
    Requires Queue builds on the pipeline, or a PAT with Build (Read & execute).
    499b84ac-1321-427f-aa17-267ca6975798 is the fixed Azure DevOps resource ID.
    Keep the two patterns in step with scripts/Test-AvdManualRequest.ps1.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9-]{0,30}\z')][string]$Workload,
    [Parameter(Mandatory)][string]$RitmNumber,
    [Parameter(Mandatory)][string]$RequestedForUpn,
    [ValidateSet('AzCli', 'Pat')][string]$AuthMethod = 'AzCli',
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'Start-AvdBuild.settings.json'),
    [switch]$Wait,
    [ValidateRange(1, 300)][int]$WaitMinutes = 230,
    [ValidateRange(15, 600)][int]$PollSeconds = 60,
    [switch]$Force
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:patHeader = $null
$adoAuthMethod = $AuthMethod

function Get-AdoHeader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Method)

    if ($Method -eq 'Pat') {
        if (-not $script:patHeader) {
            $pat = $env:AZURE_DEVOPS_EXT_PAT
            if ([string]::IsNullOrWhiteSpace($pat)) {
                $securePat = Read-Host -Prompt 'Azure DevOps PAT' -AsSecureString
                $pat = ([pscredential]::new('pat', $securePat)).GetNetworkCredential().Password
            }
            $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
            $script:patHeader = @{ Authorization = "Basic $encoded" }
        }
        return $script:patHeader
    }

    if (-not (Get-Command -Name az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI was not found. Install it, or use -AuthMethod Pat."
    }
    # Azure CLI writes warnings to stderr, which 'Stop' would turn into a failure.
    $ErrorActionPreference = 'Continue'
    $token = & az account get-access-token --resource '499b84ac-1321-427f-aa17-267ca6975798' --query accessToken --output tsv 2>$null
    $tokenExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($tokenExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "No Azure sign-in was found. Run 'az login', or use -AuthMethod Pat."
    }
    return @{ Authorization = "Bearer $token" }
}

function Invoke-AdoApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [string]$Body
    )

    $request = @{ Method = $Method; Uri = $Uri; Headers = (Get-AdoHeader -Method $adoAuthMethod) }
    if ($Body) {
        $request.ContentType = 'application/json'
        $request.Body = $Body
    }
    $response = Invoke-RestMethod @request
    # An expired or invalid credential can return the HTML sign-in page with a success code.
    if ($response -is [string]) {
        throw 'Azure DevOps did not accept the credential. Sign in again or replace the PAT.'
    }
    return $response
}

function Get-RunBody {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][bool]$Preview)

    return (@{
        previewRun = $Preview
        templateParameters = @{ workload = $Workload.ToLowerInvariant(); ritmNumber = $ritm; requestedForUpn = $upn }
        resources = @{ repositories = @{ self = @{ refName = "refs/heads/$($settings.branch)" } } }
    } | ConvertTo-Json -Depth 6 -Compress)
}

$ritmMatch = [regex]::Match($RitmNumber.Trim(), '\ARITM(?<digits>[0-9]{1,12})\z', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $ritmMatch.Success) {
    throw 'RITM number must be RITM followed by 1-12 digits, for example RITM0012345.'
}
$upn = $RequestedForUpn.Trim().ToLowerInvariant()
if ($upn -cnotmatch '\A[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\z') {
    throw 'Requested-for value is not a supported UPN, for example user@contoso.com.'
}
$ritm = "RITM$($ritmMatch.Groups['digits'].Value)"
$hostName = "AVD$($ritmMatch.Groups['digits'].Value)"

if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    throw "Settings file not found: $SettingsPath. Copy Start-AvdBuild.settings.example.json and fill it in."
}
$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
foreach ($name in @('organization', 'project', 'pipelineId', 'branch')) {
    if (-not $settings.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace([string]$settings.$name)) {
        throw "Settings file is missing '$name': $SettingsPath"
    }
}
if ([string]$settings.pipelineId -notmatch '\A[1-9][0-9]*\z') {
    throw "Settings value 'pipelineId' must be the numeric pipeline ID."
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$organization = [Uri]::EscapeDataString([string]$settings.organization)
$project = [Uri]::EscapeDataString([string]$settings.project)
$runsUri = "https://dev.azure.com/$organization/$project/_apis/pipelines/$($settings.pipelineId)/runs"

# Run names start with the RITM number; see 'name:' in the pipeline YAML.
$existingRuns = @((Invoke-AdoApi -Method GET -Uri "${runsUri}?api-version=7.1").value | Where-Object { [string]$_.name -like "$ritm-*" })
$activeRun = @($existingRuns | Where-Object { [string]$_.state -ne 'completed' }) | Select-Object -First 1
if ($activeRun) {
    throw "$ritm already has a run in progress: $($activeRun.name). Wait for it to finish."
}
$succeededRun = @($existingRuns | Where-Object { [string]$_.result -eq 'succeeded' }) | Select-Object -First 1
if ($succeededRun -and -not $Force) {
    throw "$ritm already succeeded in run $($succeededRun.name). Use -Force only for an approved rebuild."
}

# A preview compiles the pipeline with these values and creates no run.
$preview = Invoke-AdoApi -Method POST -Uri "${runsUri}?api-version=7.1" -Body (Get-RunBody -Preview $true)
if ([string]::IsNullOrWhiteSpace([string]$preview.finalYaml)) {
    throw 'Azure DevOps did not validate the pipeline preview.'
}

$summary = [ordered]@{
    Workload = $Workload.ToLowerInvariant()
    RitmNumber = $ritm
    HostName = $hostName
    RequestedForUpn = $upn
    RunId = $null
    RunUrl = $null
    State = 'NotQueued'
    Result = $null
    WorkNote = $null
}

if (-not $PSCmdlet.ShouldProcess("$hostName for $upn ($ritm) in workload $($summary.Workload)", 'Queue AVD desktop build')) {
    return [pscustomobject]$summary
}

$run = Invoke-AdoApi -Method POST -Uri "${runsUri}?api-version=7.1" -Body (Get-RunBody -Preview $false)
$summary.RunId = $run.id
$summary.RunUrl = [string]$run._links.web.href
$summary.State = [string]$run.state

if ($Wait) {
    $deadline = [DateTime]::UtcNow.AddMinutes($WaitMinutes)
    while ($summary.State -ne 'completed' -and [DateTime]::UtcNow -lt $deadline) {
        Write-Information -MessageData "$ritm is $($summary.State). Next check in $PollSeconds seconds." -InformationAction Continue
        Start-Sleep -Seconds $PollSeconds
        $status = Invoke-AdoApi -Method GET -Uri "$runsUri/$($summary.RunId)?api-version=7.1"
        $summary.State = [string]$status.state
        if ($status.PSObject.Properties['result']) { $summary.Result = [string]$status.result }
    }
    $summary.WorkNote = switch ($summary.Result) {
        'succeeded' { "AVD desktop $hostName is Entra-joined, enrolled in Intune, and assigned to $upn. Run: $($summary.RunUrl)" }
        $null { "AVD build for $hostName was still running when the wait ended. Run: $($summary.RunUrl)" }
        default { "AVD build for $hostName ended '$($summary.Result)'. The VM was preserved. Run: $($summary.RunUrl)" }
    }
}

[pscustomobject]$summary
if ($Wait -and $summary.Result -ne 'succeeded') {
    throw "$ritm did not finish successfully. Review $($summary.RunUrl)"
}
