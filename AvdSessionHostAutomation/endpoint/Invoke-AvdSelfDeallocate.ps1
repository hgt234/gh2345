#Requires -Version 5.1

<#
.SYNOPSIS
    Deallocates this session host through the Azure API when it has no user
    sessions and has been running past an idle threshold.

.DESCRIPTION
    Runs on the session host itself, on a schedule, as SYSTEM. Usage-aware by
    design: it acts on the actual session state of the machine, not on a time
    window, so it suits 24/7 personal workloads.

    Order of checks, cheapest first:

    1. Sessions: any session reported by quser, active or disconnected,
       means the desktop is in use and the script exits without touching
       anything. Disconnected sessions are preserved on purpose; closing
       them would lose the user's running applications.
    2. Uptime: the machine must have been up at least MinimumUptimeMinutes,
       so a host that Start VM on Connect just powered on is not fought over.
    3. Identity loopback: the VM's compute metadata and a management-plane
       token are read from IMDS (169.254.169.254, link-local, no credential
       stored anywhere). The metadata name must match this computer's name;
       on mismatch the script refuses to act.
    4. Deallocate: a single POST to this VM's own deallocate action, using
       one of two identities:
       - without ManagedIdentityClientId, the system-assigned identity,
         which holds the AVD Prod Self Deallocate role on this VM only;
       - with ManagedIdentityClientId, the workload's shared user-assigned
         power-off identity, which holds deallocate rights over the whole
         session-host resource group. This script still targets only its
         own VM, but any code running as SYSTEM or local administrator on
         any host can request that identity's token.

    Deallocate, not a guest shutdown: only deallocation releases the compute
    hardware and stops billing. The call returns accepted and Azure then
    stops the machine; the script does not wait.

    Deploy with Intune as a scheduled task (for example every 15 minutes).
    A second run while the first deallocation is in flight is a no-op from
    Azure's point of view.

.PARAMETER MinimumUptimeMinutes
    Minimum minutes since boot before the host may deallocate itself.

.PARAMETER ManagementEndpoint
    Azure Resource Manager endpoint; the default is the public cloud.

.PARAMETER ManagedIdentityClientId
    Client ID of the workload's user-assigned power-off identity. Sent to
    IMDS as client_id so the token always comes from that identity. The VM
    also has a system-assigned identity, and the IMDS docs do not define
    which one is used when neither is named, so set this whenever the
    shared identity is in use. Omit it to use the system-assigned identity.

.EXAMPLE
    .\Invoke-AvdSelfDeallocate.ps1 -MinimumUptimeMinutes 60 -WhatIf

.EXAMPLE
    .\Invoke-AvdSelfDeallocate.ps1 -MinimumUptimeMinutes 60 -ManagedIdentityClientId 11111111-1111-1111-1111-111111111111 -WhatIf

.NOTES
    Requires the identity used to hold
    Microsoft.Compute/virtualMachines/read and
    Microsoft.Compute/virtualMachines/deallocate/action on this VM: either
    the system-assigned identity (granted by the build pipeline's Assign
    stage) or the shared user-assigned identity (granted once during
    workload preparation). IMDS calls must not go through a proxy; SYSTEM
    normally has none configured.
    https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service
    https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateRange(5, 1440)][int]$MinimumUptimeMinutes = 60,
    [ValidatePattern('\Ahttps://[a-z0-9.-]+\z')][string]$ManagementEndpoint = 'https://management.azure.com',
    [ValidatePattern('\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z')][string]$ManagedIdentityClientId
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-ActiveSessionCount {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    # quser exits nonzero and writes to stderr when no user is logged on, so
    # stderr handling is relaxed for just this call.
    $ErrorActionPreference = 'Continue'
    $output = & quser 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($exitCode -ne 0 -or -not $output) { return 0 }
    $rows = @($output | Select-Object -Skip 1 | Where-Object { $_ -match '\S' })
    return $rows.Count
}

function Get-HostUptime {
    [CmdletBinding()]
    [OutputType([double])]
    param()

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    return ((Get-Date) - $os.LastBootUpTime).TotalMinutes
}

function Get-ImdsComputeInstance {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    return Invoke-RestMethod -Method Get -TimeoutSec 10 `
        -Headers @{ Metadata = 'true' } `
        -Uri 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01'
}

function Get-ImdsAccessToken {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Resource,
        [string]$ClientId
    )

    $encodedResource = [Uri]::EscapeDataString($Resource)
    $tokenUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$encodedResource"
    if ($ClientId) {
        # Name the user-assigned identity explicitly; see the parameter help.
        $tokenUri += "&client_id=$([Uri]::EscapeDataString($ClientId))"
    }
    $response = Invoke-RestMethod -Method Get -TimeoutSec 10 `
        -Headers @{ Metadata = 'true' } `
        -Uri $tokenUri
    if (-not $response.access_token) {
        throw 'IMDS did not return a managed-identity access token.'
    }
    return [string]$response.access_token
}

$sessionCount = Get-ActiveSessionCount
if ($sessionCount -gt 0) {
    Write-Output "In use: $sessionCount session(s) present. No action."
    return
}

$uptimeMinutes = [Math]::Floor((Get-HostUptime))
if ($uptimeMinutes -lt $MinimumUptimeMinutes) {
    Write-Output "Up $uptimeMinutes of $MinimumUptimeMinutes minimum minutes. No action."
    return
}

$metadata = Get-ImdsComputeInstance
$vmName = [string]$metadata.name
$localName = [Environment]::MachineName
if ($vmName -ine $localName) {
    throw "IMDS reports VM '$vmName' but this computer is '$localName'. Refusing to deallocate."
}

$deallocateUri = '{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Compute/virtualMachines/{3}/deallocate?api-version=2024-03-01' -f `
    $ManagementEndpoint, [string]$metadata.subscriptionId, [string]$metadata.resourceGroupName, $vmName

if (-not $PSCmdlet.ShouldProcess($vmName, "Deallocate idle session host (0 sessions, up $uptimeMinutes minutes)")) {
    Write-Output "Would deallocate '$vmName'. Nothing was changed."
    return
}

$token = Get-ImdsAccessToken -Resource "$ManagementEndpoint/" -ClientId $ManagedIdentityClientId
try {
    Invoke-RestMethod -Method Post -TimeoutSec 60 `
        -Headers @{ Authorization = "Bearer $token" } `
        -Uri $deallocateUri | Out-Null
}
finally {
    $token = $null
}
Write-Output "Deallocation of '$vmName' was accepted after $uptimeMinutes idle minutes with no sessions."
