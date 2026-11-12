#Requires -Version 7.2

<#
.SYNOPSIS
    Validates an AVD build request from ServiceNow or a technician and publishes
    normalized pipeline variables.

.DESCRIPTION
    Single validator for both request sources. The host name is always derived
    here from the RITM number, so neither source can choose an arbitrary name.
    When ServiceNow also supplies its derived host name, the two must match
    exactly; a mismatch fails the build before anything is deployed. When a
    RITM sys_id is supplied, ServiceNow callbacks are enabled for the run and
    the sys_id format is enforced.

    Later pipeline stages consume the output variables written here, never the
    raw parameters. Only allow-listed characters are accepted, which also keeps
    the values safe for the Graph URLs and logging commands built from them.

    Read-only: this script changes nothing.

.PARAMETER RitmNumber
    RITM followed by 1-12 digits. Case-insensitive; surrounding spaces are removed.

.PARAMETER RequestedForUpn
    User principal name of the person receiving the desktop.

.PARAMETER RitmSysId
    Optional ServiceNow sys_id of the RITM, exactly 32 hexadecimal characters.
    Supplying it enables ServiceNow status callbacks for the run.

.PARAMETER RequestedHostName
    Optional host name supplied by ServiceNow. When present it must equal the
    name derived from the RITM number, including leading zeros.

.EXAMPLE
    ./Test-AvdProvisionRequest.ps1 -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com

.EXAMPLE
    ./Test-AvdProvisionRequest.ps1 -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -RitmSysId 0123456789abcdef0123456789abcdef -RequestedHostName AVD0012345

.NOTES
    Apostrophes are valid in Entra UPNs but are rejected here because the
    deployment scripts build Graph URLs from this value without OData quote
    escaping. Keep the patterns in step with technician/Start-AvdBuild.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RitmNumber,
    [Parameter(Mandatory)][string]$RequestedForUpn,
    [string]$RitmSysId = '',
    [string]$RequestedHostName = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ritmMatch = [regex]::Match($RitmNumber.Trim(), '\ARITM(?<digits>[0-9]{1,12})\z', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $ritmMatch.Success) {
    throw 'RITM number must be RITM followed by 1-12 digits, for example RITM0012345.'
}
$digits = $ritmMatch.Groups['digits'].Value
$hostName = "AVD$digits"

if (-not [string]::IsNullOrWhiteSpace($RequestedHostName) -and $RequestedHostName.Trim() -cne $hostName) {
    throw "ServiceNow supplied host name '$($RequestedHostName.Trim())', but RITM$digits requires the exact host name '$hostName'."
}

$upn = $RequestedForUpn.Trim().ToLowerInvariant()
if ($upn -cnotmatch '\A[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\z') {
    throw 'Requested-for value is not a supported UPN, for example user@contoso.com.'
}

$sysId = $RitmSysId.Trim().ToLowerInvariant()
if ($sysId -and $sysId -cnotmatch '\A[0-9a-f]{32}\z') {
    throw 'RITM sys_id must contain exactly 32 hexadecimal characters.'
}
$serviceNowEnabled = if ($sysId) { 'true' } else { 'false' }

$result = [ordered]@{
    ritmNumber = "RITM$digits"
    hostName = $hostName
    requestedForUpn = $upn
    ritmSysId = $sysId
    serviceNowEnabled = $serviceNowEnabled
}

# Azure DevOps reads logging commands from standard output.
Write-Output "##vso[task.setvariable variable=ritmNumber;isOutput=true]$($result.ritmNumber)"
Write-Output "##vso[task.setvariable variable=hostName;isOutput=true]$($result.hostName)"
Write-Output "##vso[task.setvariable variable=requestedForUpn;isOutput=true]$($result.requestedForUpn)"
Write-Output "##vso[task.setvariable variable=ritmSysId;isOutput=true]$($result.ritmSysId)"
Write-Output "##vso[task.setvariable variable=serviceNowEnabled;isOutput=true]$($result.serviceNowEnabled)"
Write-Output "Validated $($result.ritmNumber): $($result.hostName) for $($result.requestedForUpn). ServiceNow callbacks: $serviceNowEnabled."
