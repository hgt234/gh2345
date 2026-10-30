#Requires -Version 5.1

<#
.SYNOPSIS
    Validates a hand-entered AVD build request and publishes normalized values.

.DESCRIPTION
    Phase 01 replacement for Test-AvdRequest.ps1. A technician types the RITM
    number and UPN, so the host name is derived here instead of being supplied,
    and only allow-listed characters are accepted. Later pipeline stages consume
    the output variables written here, never the raw parameters.

    Read-only: this script changes nothing.

.PARAMETER RitmNumber
    RITM followed by 1-12 digits. Case-insensitive; surrounding spaces are removed.

.PARAMETER RequestedForUpn
    User principal name of the person receiving the desktop.

.EXAMPLE
    ./Test-AvdManualRequest.ps1 -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com

.NOTES
    Keep the two patterns in step with Start-AvdBuild.ps1. Apostrophes are valid
    in Entra UPNs but are rejected here because the existing scripts build Graph
    URLs from this value without OData quote escaping.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RitmNumber,
    [Parameter(Mandatory)][string]$RequestedForUpn
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ritmMatch = [regex]::Match($RitmNumber.Trim(), '\ARITM(?<digits>[0-9]{1,12})\z', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $ritmMatch.Success) {
    throw 'RITM number must be RITM followed by 1-12 digits, for example RITM0012345.'
}
$upn = $RequestedForUpn.Trim().ToLowerInvariant()
if ($upn -cnotmatch '\A[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\z') {
    throw 'Requested-for value is not a supported UPN, for example user@contoso.com.'
}

$digits = $ritmMatch.Groups['digits'].Value
$result = [ordered]@{
    ritmNumber = "RITM$digits"
    hostName = "AVD$digits"
    requestedForUpn = $upn
}

# Azure DevOps reads logging commands from standard output.
Write-Output "##vso[task.setvariable variable=ritmNumber;isOutput=true]$($result.ritmNumber)"
Write-Output "##vso[task.setvariable variable=hostName;isOutput=true]$($result.hostName)"
Write-Output "##vso[task.setvariable variable=requestedForUpn;isOutput=true]$($result.requestedForUpn)"
Write-Output "Validated $($result.ritmNumber): $($result.hostName) for $($result.requestedForUpn)."
