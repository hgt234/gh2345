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

    Guardrails against changing or deleting existing objects:
    - The deployment runs in Incremental mode, which never deletes resources.
    - The Azure what-if must show only Create (Ignore, NoChange, and NoEffect are
      allowed). Modify, Deploy, Delete, or any other change type stops the run
      before anything is written, including the token renewal.
    - The subnet is an 'existing' reference in the template and is never deployed.
    - A warning is shown when the VM resource group has no CanNotDelete lock.
      Contributor cannot create or remove locks, so an Owner must add it.

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

# Delete protection: the deployment itself deletes nothing (Incremental mode
# never deletes, and the what-if below refuses anything but Create). Locks
# are the only control that stops a Contributor deleting the VM afterwards, and
# Contributor cannot create or remove locks, so an Owner must place one.
# https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources
$locks = @(Invoke-AzCli -ArgumentList @('lock', 'list', '--resource-group', $ResourceGroupName, '--subscription', $SubscriptionId))
if (@($locks | Where-Object { [string]$_.level -in @('CanNotDelete', 'ReadOnly') }).Count -eq 0) {
    Write-Warning "Resource group '$ResourceGroupName' has no CanNotDelete lock. Anyone with Contributor can delete this VM and its disk. Ask an Owner to add one."
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
    # The what-if only validates the template, so it runs with a placeholder
    # token. The real token is written in just before the deployment.
    registrationToken = @{ value = $whatIfToken }
    localAdminPassword = @{ value = (Get-RandomPassword) }
    osDiskSku = @{ value = $OsDiskSku }
}
if ($Location) { $parameterValues.location = @{ value = $Location } }
$parameterDocument = [ordered]@{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = $parameterValues
}

# What-if change types that leave existing resources untouched. Anything else
# (Modify, Deploy, Delete, Unsupported, or an unknown value) means an existing
# object would be changed, so the run stops before any write.
# https://learn.microsoft.com/azure/azure-resource-manager/templates/deploy-what-if#change-types
$allowedChangeTypes = @('Create', 'Ignore', 'NoChange', 'NoEffect')

$summary = [ordered]@{ VmName = $VmName; HostPool = $HostPoolName; State = 'NotDeployed'; VmId = $null; Changes = @() }
$deploymentName = "avd-$($VmName.ToLowerInvariant())-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
$registrationToken = $null

# No write (token renewal or deployment) happens until the what-if passes.
$parameterFile = Write-TempJson -Json ($parameterDocument | ConvertTo-Json -Depth 5)
$deployArguments = @(
    '--resource-group', $ResourceGroupName,
    '--subscription', $SubscriptionId,
    '--template-file', $templateFile,
    '--parameters', "@$parameterFile",
    '--mode', 'Incremental'
)
try {
    $whatIf = Invoke-AzCli -ArgumentList (@('deployment', 'group', 'what-if', '--name', $deploymentName, '--no-pretty-print', '--result-format', 'ResourceIdOnly') + $deployArguments)
    if (-not $whatIf -or -not $whatIf.PSObject.Properties['changes']) {
        throw 'Azure what-if returned no result. Nothing was deployed.'
    }
    $changes = @($whatIf.changes)
    $summary.Changes = @($changes | ForEach-Object { "$($_.changeType): $($_.resourceId)" })
    $refused = @($changes | Where-Object { [string]$_.changeType -notin $allowedChangeTypes })
    if ($refused.Count -gt 0) {
        throw ("The deployment would change existing resources, and this script only creates new ones: {0}" -f
            (@($refused | ForEach-Object { "$($_.changeType): $($_.resourceId)" }) -join '; '))
    }

    if ($PSCmdlet.ShouldProcess("$VmName in $ResourceGroupName", "Deploy session host for host pool $HostPoolName")) {
        $registrationToken = Get-RegistrationToken -HostPoolUri $hostPoolUri
        if (-not $registrationToken -and $PSCmdlet.ShouldProcess($HostPoolName, "Renew registration token for $tokenRenewalHours hours")) {
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
    }
    if ($registrationToken) {
        $parameterValues.registrationToken = @{ value = $registrationToken }
        [IO.File]::WriteAllText($parameterFile, ($parameterDocument | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
        Write-Information -MessageData "Deploying $VmName. This can take 20 minutes." -InformationAction Continue
        $deployment = Invoke-AzCli -ArgumentList (@('deployment', 'group', 'create', '--name', $deploymentName) + $deployArguments)
        $summary.State = 'Deployed'
        $summary.VmId = [string]$deployment.properties.outputs.vmId.value
    }
}
finally {
    [IO.File]::Delete($parameterFile)
    $registrationToken = $null
    $parameterValues = $null
    $parameterDocument = $null
}

[pscustomobject]$summary
