#Requires -Version 5.1

<#
.SYNOPSIS
    Deploys one AVD session host from your own interactive Azure session.

.DESCRIPTION
    Creates a VM, NIC, and OS disk from infra/session-host.bicep, joins the VM to
    Entra with automatic Intune enrollment, and registers it in an existing host
    pool. The VM attaches to an existing subnet. Nothing else is created, and the
    VM is not assigned to a user.

    The deployment finishes when the extensions finish. Intune enrollment continues
    in the background and is not checked here.

    With -WhatIf every read-only check and the Azure what-if run, and nothing changes.
    The host pool registration token is renewed only if it is missing or close to expiry.

.PARAMETER VmName
    Computer name: 4-15 letters, digits, or hyphens, starting with a letter.

.PARAMETER ResourceGroupName
    Existing resource group that receives the VM.

.PARAMETER HostPoolName
    Existing host pool.

.PARAMETER HostPoolResourceGroupName
    Resource group holding the host pool.

.PARAMETER SubnetId
    Full resource ID of the existing subnet. It must be in the VM's region.

.PARAMETER SubscriptionId
    Subscription for the VM and host pool. Defaults to the current az login context.

.PARAMETER Location
    VM region. Defaults to the region of the VM resource group.

.PARAMETER VmSize
    VM size.

.PARAMETER OsDiskSku
    OS disk SKU.

.PARAMETER GalleryImageVersionId
    Azure Compute Gallery image version ID. Without it, the template's Windows 11
    Enterprise Marketplace image is used.

.PARAMETER AvdDscConfigurationUri
    Microsoft AVD DSC package used to register the VM.

.EXAMPLE
    .\Deploy-AvdVm.ps1 -VmName AVD-TEST-01 -ResourceGroupName rg-vms -HostPoolName vdpool-a -HostPoolResourceGroupName rg-avd -SubnetId $subnetId -WhatIf

    Runs every check and the Azure what-if. Changes nothing.

.EXAMPLE
    .\Deploy-AvdVm.ps1 -VmName AVD-TEST-01 -ResourceGroupName rg-vms -HostPoolName vdpool-a -HostPoolResourceGroupName rg-avd -SubnetId $subnetId

    Deploys the VM.

.NOTES
    Requires Azure CLI signed in with 'az login'.
    Host pool API: https://learn.microsoft.com/rest/api/desktopvirtualization/host-pools
    Temporary files use [IO.File] so that -WhatIf cannot stop their cleanup.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)][ValidatePattern('\A[A-Za-z][A-Za-z0-9-]{2,13}[A-Za-z0-9]\z')][string]$VmName,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$HostPoolName,
    [Parameter(Mandatory)][string]$HostPoolResourceGroupName,
    [Parameter(Mandatory)][ValidatePattern('(?i)\A/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+/subnets/[^/]+\z')][string]$SubnetId,
    [ValidatePattern('(?i)\A[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\z')][string]$SubscriptionId,
    [string]$Location,
    [string]$VmSize = 'Standard_E4bs_v5',
    [ValidateSet('StandardSSD_LRS', 'Premium_LRS')][string]$OsDiskSku = 'StandardSSD_LRS',
    [string]$GalleryImageVersionId,
    [string]$AvdDscConfigurationUri = 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02774.414.zip'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$hostPoolApiVersion = '2024-04-03'
$tokenRenewalHours = 4
$whatIfToken = 'whatif-placeholder-token'

function Invoke-AzCli {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$ArgumentList)

    # Azure CLI writes warnings to stderr, which 'Stop' would turn into a failure.
    $ErrorActionPreference = 'Continue'
    $output = & az @ArgumentList --only-show-errors --output json 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    $stderr = @($output | Where-Object { $_ -is [Management.Automation.ErrorRecord] }) -join [Environment]::NewLine
    if ($exitCode -ne 0) {
        throw "Azure CLI failed: az $($ArgumentList[0]) $($ArgumentList[1])`n$stderr"
    }
    $text = @($output | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] }) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json
}

function Write-TempJson {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Json)

    # Windows PowerShell 5.1 writes a BOM with -Encoding UTF8; this does not.
    $path = Join-Path ([IO.Path]::GetTempPath()) "avd-$([Guid]::NewGuid().ToString('N')).json"
    [IO.File]::WriteAllText($path, $Json, [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-RandomPassword {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $bytes = New-Object byte[] 24
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd('=') + '!aA7'
}

function Get-RegistrationToken {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$HostPoolUri)

    $response = Invoke-AzCli -ArgumentList @('rest', '--method', 'POST', '--url', "$HostPoolUri/retrieveRegistrationToken?api-version=$hostPoolApiVersion")
    if (-not $response -or -not $response.PSObject.Properties['token'] -or [string]::IsNullOrWhiteSpace([string]$response.token)) { return $null }
    if (-not $response.PSObject.Properties['expirationTime'] -or -not $response.expirationTime) { return $null }
    if (([DateTime]$response.expirationTime).ToUniversalTime() -lt [DateTime]::UtcNow.AddMinutes(30)) { return $null }
    return [string]$response.token
}

if (-not (Get-Command -Name az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Install it, then run az login.'
}
$templateFile = Join-Path $PSScriptRoot '../infra/session-host.bicep'
if (-not (Test-Path -LiteralPath $templateFile -PathType Leaf)) {
    throw "Session-host template was not found: $templateFile"
}

$account = Invoke-AzCli -ArgumentList @('account', 'show')
if (-not $SubscriptionId) { $SubscriptionId = [string]$account.id }
Write-Verbose "Signed in as $($account.user.name), subscription $SubscriptionId."

$existingVms = @(Invoke-AzCli -ArgumentList @('vm', 'list', '--resource-group', $ResourceGroupName, '--subscription', $SubscriptionId))
if (@($existingVms | Where-Object { [string]$_.name -ieq $VmName }).Count -gt 0) {
    throw "VM '$VmName' already exists in '$ResourceGroupName'. This script only creates new VMs."
}

$hostPoolUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$HostPoolResourceGroupName/providers/Microsoft.DesktopVirtualization/hostPools/$HostPoolName"
$hostPool = Invoke-AzCli -ArgumentList @('rest', '--method', 'GET', '--url', "${hostPoolUri}?api-version=$hostPoolApiVersion")
$rdpProperties = [string]$hostPool.properties.customRdpProperty
if ($rdpProperties -notmatch '(?i)targetisaadjoined:i:1') {
    Write-Warning "Host pool '$HostPoolName' does not have targetisaadjoined:i:1 in its RDP properties. Users may not be able to connect to Entra-joined VMs."
}

$registrationToken = Get-RegistrationToken -HostPoolUri $hostPoolUri
if (-not $registrationToken) {
    if ($PSCmdlet.ShouldProcess($HostPoolName, "Renew registration token for $tokenRenewalHours hours")) {
        $body = @{
            properties = @{
                registrationInfo = @{
                    expirationTime = [DateTime]::UtcNow.AddHours($tokenRenewalHours).ToString('o')
                    registrationTokenOperation = 'Update'
                }
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $bodyFile = Write-TempJson -Json $body
        try {
            [void](Invoke-AzCli -ArgumentList @('rest', '--method', 'PATCH', '--url', "${hostPoolUri}?api-version=$hostPoolApiVersion", '--headers', 'Content-Type=application/json', '--body', "@$bodyFile"))
        }
        finally {
            [IO.File]::Delete($bodyFile)
        }
        $registrationToken = Get-RegistrationToken -HostPoolUri $hostPoolUri
        if (-not $registrationToken) { throw "Host pool '$HostPoolName' did not return a registration token." }
    }
    else {
        # What-if only validates the template, so it does not need a real token.
        $registrationToken = $whatIfToken
    }
}

$parameterValues = [ordered]@{
    vmName = @{ value = $VmName }
    vmSize = @{ value = $VmSize }
    subnetId = @{ value = $SubnetId }
    hostPoolName = @{ value = $HostPoolName }
    ritmNumber = @{ value = 'Phase00' }
    requestedForUpn = @{ value = 'Unassigned' }
    imageSourceType = @{ value = $(if ($GalleryImageVersionId) { 'Gallery' } else { 'Marketplace' }) }
    galleryImageVersionId = @{ value = [string]$GalleryImageVersionId }
    avdDscConfigurationUri = @{ value = $AvdDscConfigurationUri }
    registrationToken = @{ value = $registrationToken }
    localAdminPassword = @{ value = (Get-RandomPassword) }
    osDiskSku = @{ value = $OsDiskSku }
}
if ($Location) { $parameterValues.location = @{ value = $Location } }

$parameterFile = Write-TempJson -Json (@{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = $parameterValues
} | ConvertTo-Json -Depth 5)

$summary = [ordered]@{ VmName = $VmName; HostPool = $HostPoolName; State = 'NotDeployed'; VmId = $null; Changes = @() }
$deploymentName = "avd-$($VmName.ToLowerInvariant())-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
$deployArguments = @(
    '--resource-group', $ResourceGroupName,
    '--subscription', $SubscriptionId,
    '--template-file', $templateFile,
    '--parameters', "@$parameterFile"
)
try {
    $whatIf = Invoke-AzCli -ArgumentList (@('deployment', 'group', 'what-if', '--name', $deploymentName, '--no-pretty-print', '--result-format', 'ResourceIdOnly') + $deployArguments)
    $changes = @($whatIf.changes)
    $summary.Changes = @($changes | ForEach-Object { "$($_.changeType): $($_.resourceId)" })
    if (@($changes | Where-Object { [string]$_.changeType -in @('Delete', 'Recreate') }).Count -gt 0) {
        throw "The deployment would delete or recreate a resource: $($summary.Changes -join '; ')"
    }

    if ($PSCmdlet.ShouldProcess("$VmName in $ResourceGroupName", "Deploy session host for host pool $HostPoolName")) {
        Write-Information -MessageData "Deploying $VmName. This can take 20 minutes." -InformationAction Continue
        $deployment = Invoke-AzCli -ArgumentList (@('deployment', 'group', 'create', '--name', $deploymentName, '--mode', 'Incremental') + $deployArguments)
        $summary.State = 'Deployed'
        $summary.VmId = [string]$deployment.properties.outputs.vmId.value
    }
}
finally {
    [IO.File]::Delete($parameterFile)
    $registrationToken = $null
}

[pscustomobject]$summary
