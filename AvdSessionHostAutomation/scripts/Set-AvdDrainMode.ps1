#Requires -Version 7.2

<#
.SYNOPSIS
    Places a registered session host in drain mode after a failed build.

.DESCRIPTION
    Looks up the session host in the existing host pool and, when it is
    registered, sets allowNewSession to false so nobody can sign in to a host
    that failed its readiness gates. The VM itself is preserved for
    investigation; nothing is deleted. When no registration exists the script
    reports that and changes nothing.

    With -WhatIf, the lookup runs and the drain change is only reported.

.PARAMETER SubscriptionId
    Target subscription ID.

.PARAMETER PlatformResourceGroupName
    Resource group holding the existing host pool.

.PARAMETER HostPoolName
    Existing AVD personal host-pool name.

.PARAMETER VmName
    Session-host name, AVD followed by 1-12 digits.

.EXAMPLE
    ./Set-AvdDrainMode.ps1 -SubscriptionId $sub -PlatformResourceGroupName rg-avd -HostPoolName vdpool-prod -VmName AVD0012345 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$PlatformResourceGroupName,
    [Parameter(Mandatory)][string]$HostPoolName,
    [Parameter(Mandatory)][ValidatePattern('\AAVD[0-9]{1,12}\z')][string]$VmName
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$hostPoolId = "/subscriptions/$SubscriptionId/resourceGroups/$PlatformResourceGroupName/providers/Microsoft.DesktopVirtualization/hostPools/$HostPoolName"
$raw = & az rest --method GET --url "https://management.azure.com$hostPoolId/sessionHosts?api-version=2024-04-03" --only-show-errors --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Unable to inspect AVD session hosts: $($raw -join [Environment]::NewLine)"
    return
}
$response = ($raw -join [Environment]::NewLine) | ConvertFrom-Json -Depth 100
$sessionHost = @($response.value) | Where-Object {
    $leaf = (([string]$_.name -split '/')[-1] -split '\.')[0]
    $leaf -ieq $VmName
} | Select-Object -First 1
if (-not $sessionHost) {
    Write-Output "No AVD registration exists for '$VmName'; no drain-mode change was required."
    return
}

if (-not $PSCmdlet.ShouldProcess($VmName, "Set allowNewSession=false on session host in '$HostPoolName'")) {
    Write-Output "Would place '$VmName' in drain mode. Nothing was changed."
    return
}

$body = @{ properties = @{ allowNewSession = $false } } | ConvertTo-Json -Compress
$raw = & az rest --method PATCH --url "https://management.azure.com$($sessionHost.id)?api-version=2024-04-03" --headers 'Content-Type=application/json' --body $body --only-show-errors --output none 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to place '$VmName' in drain mode: $($raw -join [Environment]::NewLine)"
}
Write-Output "Placed '$VmName' in drain mode after provisioning failure."
