#Requires -Version 7.2

<#
.SYNOPSIS
    Dry run of the session-host build from your own session: the real ARM
    what-if, with no token renewal and no deployment.

.DESCRIPTION
    Template. Copy it to Invoke-AvdDryRun.ps1 in this folder (that name is
    git-ignored), replace every <PLACEHOLDER> in $values with the value from
    the avd-prod-<workload> variable group, and run the copy.

    It runs the same steps as the pipeline's Provision stage, always with
    -WhatIf, so it can never deploy:

    1. Test-AvdProvisionRequest.ps1 checks the RITM and UPN and derives the
       host name, exactly as the pipeline does.
    2. New-AvdSessionHost.ps1 -WhatIf checks the Entra user, the name
       collision, and the gallery image, then runs the ARM what-if and writes
       the report. It skips the registration-token renewal and the deployment.
    3. The report is checked. The run passes only when the VM, its NIC, and
       the two extensions are Creates, nothing else is created, modified, or
       deleted, and the NIC has no public IP. Existing resources in the
       resource group appear as Ignore; Incremental mode leaves them alone.

    It runs as you, not as the service connection, so it proves the template
    and the values but not the connection's permissions. ARM what-if needs the
    same rights as the deployment itself: write on the VM and NIC in the
    session-host resource group, Microsoft.Resources/deployments/*, and subnet
    join. Contributor on the session-host resource group plus Graph read on
    the user is enough. Without the host pool token permission the script
    uses a placeholder token, which is fine for a what-if.
    https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if

    Run 'az login --tenant <tenant-id>' first, from a location Conditional
    Access allows.

.PARAMETER RitmNumber
    Test RITM number; the host name is derived from it.

.PARAMETER RequestedForUpn
    Licensed test user, already in the access group for Group mode.

.PARAMETER ReportDirectory
    Where the what-if report is written. It holds tenant resource IDs, so the
    default is outside the repository. Delete it when finished.

.PARAMETER Workload
    Optional replacement for the values in $values below, with the same
    keys. Used by the tests; normally you edit the values in your copy.

.EXAMPLE
    ./examples/Invoke-AvdDryRun.ps1 -RitmNumber RITM0012345 -RequestedForUpn testuser@contoso.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RitmNumber,
    [Parameter(Mandatory)][string]$RequestedForUpn,
    [string]$ReportDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'avd-dryrun'),
    [System.Collections.IDictionary]$Workload
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Copy each value from the avd-prod-<workload> variable group. (Not named
# $workload: PowerShell variable names ignore case, so it would overwrite the
# -Workload parameter.)
$values = [ordered]@{
    SubscriptionId            = '<AVD_SUBSCRIPTION_ID>'
    TenantId                  = '<AVD_TENANT_ID>'
    ResourceGroupName         = '<AVD_SESSION_HOST_RESOURCE_GROUP>'
    PlatformResourceGroupName = '<AVD_PLATFORM_RESOURCE_GROUP>'
    HostPoolName              = '<AVD_HOST_POOL_NAME>'
    SubnetId                  = '<AVD_SESSION_HOST_SUBNET_ID>'
    EnvironmentName           = '<AVD_ENVIRONMENT_NAME>'
    Location                  = '<AVD_LOCATION>'
    VmSize                    = '<AVD_VM_SIZE>'
    OsDiskSku                 = '<AVD_OS_DISK_SKU>'
    # Gallery or Marketplace (AVD_IMAGE_SOURCE_TYPE).
    ImageSourceType           = '<AVD_IMAGE_SOURCE_TYPE>'
    # Leave both gallery values '' for Marketplace. A '' version means the
    # latest published version, as in the pipeline.
    GalleryImageDefinitionId  = '<AVD_GALLERY_IMAGE_DEFINITION_ID>'
    GalleryImageVersionId     = ''
    AvdDscConfigurationUri    = '<AVD_DSC_CONFIGURATION_URI>'
}
if ($Workload) { $values = $Workload }

$unfilled = @($values.GetEnumerator() | Where-Object { [string]$_.Value -match '<[A-Z_]+>' } | ForEach-Object { $_.Key })
if ($unfilled.Count -gt 0) {
    throw "Replace the placeholders from the avd-prod-<workload> variable group first: $($unfilled -join ', ')"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptsRoot = Join-Path $repoRoot 'scripts'

# 1. Same request validation and host-name derivation as the pipeline.
$requestLines = @(& (Join-Path $scriptsRoot 'Test-AvdProvisionRequest.ps1') -RitmNumber $RitmNumber -RequestedForUpn $RequestedForUpn)
function Get-RequestValue {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    $line = $requestLines | Where-Object { "$_" -like "*variable=$Name;*" } | Select-Object -First 1
    return ([string]$line -split '\]', 2)[1]
}
$vmName = Get-RequestValue -Name 'hostName'
$ritm = Get-RequestValue -Name 'ritmNumber'
$upn = Get-RequestValue -Name 'requestedForUpn'

# 2. The real ARM what-if. -WhatIf is fixed here so this can never deploy.
$reportPath = Join-Path $ReportDirectory "session-host-what-if-$vmName.json"
$deployArguments = @{}
foreach ($key in $values.Keys) { $deployArguments[$key] = $values[$key] }
$deployArguments.VmName = $vmName
$deployArguments.RitmNumber = $ritm
$deployArguments.RequestedForUpn = $upn
$deployArguments.TemplateFile = Join-Path $repoRoot 'infra/session-host.bicep'
$deployArguments.WhatIfReportPath = $reportPath
& (Join-Path $scriptsRoot 'New-AvdSessionHost.ps1') @deployArguments -WhatIf

# 3. Check the report against what a first build of this RITM must look like.
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 100
$nicName = "$($vmName.ToLowerInvariant())-nic"
$expected = @(
    "Microsoft.Compute/virtualMachines/$vmName"
    "Microsoft.Compute/virtualMachines/$vmName/extensions/AADLoginForWindows"
    "Microsoft.Compute/virtualMachines/$vmName/extensions/MicrosoftPowershellDSC"
    "Microsoft.Network/networkInterfaces/$nicName"
)
$problems = [System.Collections.Generic.List[string]]::new()
$ignored = 0
$summary = foreach ($change in @($report.changes)) {
    $resource = ([string]$change.resourceId -split '/providers/')[-1]
    $changeType = [string]$change.changeType
    if ($changeType -eq 'Ignore') { $ignored++; continue }
    if ($expected -notcontains $resource) {
        $problems.Add("Unexpected $changeType on $resource.")
    }
    elseif ($changeType -ne 'Create') {
        $problems.Add("$changeType on $resource; a first build of $ritm should only create. Does $vmName already exist?")
    }
    [pscustomobject]@{ ChangeType = $changeType; Resource = $resource }
}
foreach ($resource in $expected) {
    if (-not @($summary | Where-Object Resource -EQ $resource)) { $problems.Add("Missing from the what-if: $resource.") }
}

$vm = @($report.changes | Where-Object { ([string]$_.resourceId -split '/providers/')[-1] -eq $expected[0] })
$nic = @($report.changes | Where-Object { ([string]$_.resourceId -split '/providers/')[-1] -eq $expected[3] })
$imageReference = if ($vm.Count -gt 0 -and $vm[0].after) { $vm[0].after.properties.storageProfile.imageReference } else { $null }
$image = if (-not $imageReference) { '' }
    elseif ($imageReference.PSObject.Properties['id']) { [string]$imageReference.id }
    else { '{0}:{1}:{2}:{3}' -f $imageReference.publisher, $imageReference.offer, $imageReference.sku, $imageReference.version }
$identity = if ($vm.Count -gt 0 -and $vm[0].after -and $vm[0].after.PSObject.Properties['identity']) { [string]$vm[0].after.identity.type } else { '' }
$publicIp = $false
if ($nic.Count -gt 0 -and $nic[0].after) {
    $publicIp = @($nic[0].after.properties.ipConfigurations | Where-Object { $_.properties.PSObject.Properties['publicIPAddress'] }).Count -gt 0
}
if ($publicIp) { $problems.Add('The NIC has a public IP address.') }

$summary | Format-Table -AutoSize | Out-String | Write-Output
Write-Output "Image:     $image"
Write-Output "Identity:  $identity"
Write-Output "Public IP: $publicIp"
Write-Output "Existing resources left alone (Ignore): $ignored"
Write-Output "Report:    $reportPath"

if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Warning $_ }
    throw "Dry run FAILED with $($problems.Count) problem(s). Nothing was deployed."
}
Write-Output "Dry run PASSED for $vmName ($ritm, $upn). Nothing was deployed."
