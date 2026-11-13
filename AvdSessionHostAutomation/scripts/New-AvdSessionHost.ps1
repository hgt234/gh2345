#Requires -Version 7.2

<#
.SYNOPSIS
    Deploys one private Entra-joined AVD personal session host into existing
    infrastructure.

.DESCRIPTION
    Resolves the requested Entra user, selects the newest usable gallery image
    version when none is pinned, reuses the host pool's AVD registration token
    when at least 30 minutes remain (otherwise renews it), and then deploys the
    reference-only session-host Bicep template additively.

    Safety rails: the VM name must be RITM-derived; an existing VM with the
    same name is only converged when its RITM and requested-for tags match the
    request; the ARM what-if result is evaluated first and any Delete or
    Recreate operation blocks the deployment; the deployment runs in
    Incremental mode so existing resources are never removed. The network,
    host pool, application group, and workspace are referenced, never created.

    With -WhatIf, every read-only step runs, the what-if report is produced,
    and the token renewal and deployment are skipped.

.PARAMETER SubscriptionId
    Target subscription ID.

.PARAMETER TenantId
    Expected Entra tenant ID; the authenticated context must match.

.PARAMETER ResourceGroupName
    Resource group that receives the VM, NIC, and OS disk.

.PARAMETER PlatformResourceGroupName
    Resource group holding the existing host pool.

.PARAMETER HostPoolName
    Existing AVD personal host-pool name.

.PARAMETER SubnetId
    Full resource ID of the existing session-host subnet.

.PARAMETER VmName
    RITM-derived host name, AVD followed by 1-12 digits.

.PARAMETER RitmNumber
    ServiceNow RITM number, kept as a resource tag.

.PARAMETER RequestedForUpn
    UPN of the person receiving the desktop, kept as a resource tag.

.PARAMETER TemplateFile
    Path of the session-host Bicep template.

.PARAMETER AvdDscConfigurationUri
    Microsoft AVD DSC configuration package URI.

.PARAMETER ImageSourceType
    Gallery for the corporate image or Marketplace for a fresh Microsoft image.

.PARAMETER GalleryImageDefinitionId
    Gallery image definition whose newest usable version is selected when no
    version is pinned.

.PARAMETER GalleryImageVersionId
    Pinned gallery image version. Overrides automatic selection.

.PARAMETER EnvironmentName
    Environment tag value written to every deployed resource.

.PARAMETER Location
    Azure region; must match the VNet region.

.PARAMETER VmSize
    Session-host VM size.

.PARAMETER LocalAdminUsername
    Local break-glass administrator name.

.PARAMETER OsDiskSku
    OS disk SKU.

.PARAMETER RegistrationTokenLifetimeMinutes
    Lifetime of a newly created registration token.

.PARAMETER WhatIfReportPath
    File that receives the full ARM what-if JSON.

.EXAMPLE
    ./New-AvdSessionHost.ps1 -SubscriptionId $sub -TenantId $tenant -ResourceGroupName rg-avd-hosts -PlatformResourceGroupName rg-avd -HostPoolName vdpool-prod -SubnetId $subnetId -VmName AVD0012345 -RitmNumber RITM0012345 -RequestedForUpn user@contoso.com -TemplateFile ../infra/session-host.bicep -AvdDscConfigurationUri $dscUri -GalleryImageDefinitionId $imageDefId -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$PlatformResourceGroupName,
    [Parameter(Mandatory)][string]$HostPoolName,
    [Parameter(Mandatory)][string]$SubnetId,
    [Parameter(Mandatory)][ValidatePattern('\AAVD[0-9]{1,12}\z')][string]$VmName,
    [Parameter(Mandatory)][string]$RitmNumber,
    [Parameter(Mandatory)][string]$RequestedForUpn,
    [Parameter(Mandatory)][string]$TemplateFile,
    [Parameter(Mandatory)][string]$AvdDscConfigurationUri,
    [ValidateSet('Gallery', 'Marketplace')][string]$ImageSourceType = 'Gallery',
    [string]$GalleryImageDefinitionId,
    [string]$GalleryImageVersionId,
    [string]$EnvironmentName = 'Production',
    [string]$Location = 'centralus',
    [string]$VmSize = 'Standard_E4bs_v5',
    [string]$LocalAdminUsername = 'avdlocaladmin',
    [ValidateSet('StandardSSD_LRS', 'Premium_LRS')][string]$OsDiskSku = 'StandardSSD_LRS',
    [ValidateRange(30, 1440)][int]$RegistrationTokenLifetimeMinutes = 1440,
    [string]$WhatIfReportPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Invoke-AzCliJson {
    param([Parameter(Mandatory)][string[]]$ArgumentList)
    $raw = & az @ArgumentList --only-show-errors --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: az $($ArgumentList -join ' ')`n$($raw -join [Environment]::NewLine)"
    }
    $text = $raw -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 100
}

function Get-RandomPassword {
    $random = [Security.Cryptography.RandomNumberGenerator]::GetBytes(24)
    return ([Convert]::ToBase64String($random).TrimEnd('=') + '!aA7')
}

if ($ImageSourceType -eq 'Gallery' -and
    [string]::IsNullOrWhiteSpace($GalleryImageVersionId) -and
    [string]::IsNullOrWhiteSpace($GalleryImageDefinitionId)) {
    throw 'GalleryImageDefinitionId or GalleryImageVersionId is required when ImageSourceType is Gallery.'
}
if (-not (Test-Path -LiteralPath $TemplateFile -PathType Leaf)) {
    throw "Session-host Bicep template was not found: $TemplateFile"
}

$account = Invoke-AzCliJson -ArgumentList @('account', 'show')
if ([string]$account.id -ine $SubscriptionId) {
    & az account set --subscription $SubscriptionId --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Unable to select subscription '$SubscriptionId'." }
    $account = Invoke-AzCliJson -ArgumentList @('account', 'show')
}
if ([string]$account.tenantId -ine $TenantId) {
    throw "Authenticated tenant '$($account.tenantId)' does not match requested tenant '$TenantId'."
}

$encodedUpn = [Uri]::EscapeDataString($RequestedForUpn)
$user = Invoke-AzCliJson -ArgumentList @(
    'rest', '--method', 'GET',
    '--url', "https://graph.microsoft.com/v1.0/users/${encodedUpn}?`$select=id,userPrincipalName,accountEnabled"
)
if (-not $user -or -not $user.id) { throw "Entra user '$RequestedForUpn' was not found." }
if ($user.accountEnabled -ne $true) { throw "Entra user '$RequestedForUpn' is disabled." }

# A name collision is only acceptable when it is the same request converging:
# the existing VM must carry this exact RITM and requested-for owner.
$existingVms = @(Invoke-AzCliJson -ArgumentList @('vm', 'list', '--resource-group', $ResourceGroupName, '--subscription', $SubscriptionId))
$existingVm = $existingVms | Where-Object name -CEQ $VmName | Select-Object -First 1
if ($existingVm) {
    $existingRitm = if ($existingVm.tags) { [string]($existingVm.tags.PSObject.Properties | Where-Object Name -IEQ 'RITM' | Select-Object -First 1).Value } else { '' }
    $existingUser = if ($existingVm.tags) { [string]($existingVm.tags.PSObject.Properties | Where-Object Name -IEQ 'RequestedFor' | Select-Object -First 1).Value } else { '' }
    if ($existingRitm -cne $RitmNumber -or $existingUser -ine $RequestedForUpn) {
        throw "VM '$VmName' already exists but is owned by RITM '$existingRitm' for '$existingUser'."
    }
}

if ($ImageSourceType -eq 'Gallery' -and [string]::IsNullOrWhiteSpace($GalleryImageVersionId)) {
    $versionResponse = Invoke-AzCliJson -ArgumentList @(
        'rest', '--method', 'GET',
        '--url', "https://management.azure.com${GalleryImageDefinitionId}/versions?api-version=2024-03-03"
    )
    $latestVersion = @($versionResponse.value) | Where-Object {
        $_.properties.publishingProfile.excludeFromLatest -ne $true -and
        [string]$_.properties.provisioningState -ieq 'Succeeded'
    } | Sort-Object { [DateTime]$_.properties.publishingProfile.publishedDate } -Descending | Select-Object -First 1
    if (-not $latestVersion) { throw "No usable image version exists under '$GalleryImageDefinitionId'." }
    $GalleryImageVersionId = [string]$latestVersion.id
}

$hostPoolId = "/subscriptions/$SubscriptionId/resourceGroups/$PlatformResourceGroupName/providers/Microsoft.DesktopVirtualization/hostPools/$HostPoolName"
$tokenResponse = $null
try {
    $tokenResponse = Invoke-AzCliJson -ArgumentList @(
        'rest', '--method', 'POST',
        '--url', "https://management.azure.com$hostPoolId/retrieveRegistrationToken?api-version=2024-04-03"
    )
}
catch {
    Write-Verbose 'No reusable AVD registration token was available; a new token will be requested.'
}
$registrationToken = if ($tokenResponse -and $tokenResponse.PSObject.Properties.Name -contains 'token') { [string]$tokenResponse.token } else { '' }
$tokenExpiration = if ($tokenResponse -and $tokenResponse.PSObject.Properties.Name -contains 'expirationTime' -and $tokenResponse.expirationTime) {
    [DateTime]$tokenResponse.expirationTime
}
else {
    [DateTime]::MinValue
}
if ([string]::IsNullOrWhiteSpace($registrationToken) -or $tokenExpiration -lt [DateTime]::UtcNow.AddMinutes(30)) {
    if ($PSCmdlet.ShouldProcess($hostPoolId, 'Renew AVD registration token')) {
        $expiration = [DateTime]::UtcNow.AddMinutes($RegistrationTokenLifetimeMinutes).ToString('o')
        $registrationBody = @{
            properties = @{
                registrationInfo = @{
                    expirationTime = $expiration
                    registrationTokenOperation = 'Update'
                }
            }
        } | ConvertTo-Json -Depth 10 -Compress
        # The body goes through a file: on Windows agents az is az.cmd, and
        # cmd.exe strips the double quotes from an inline JSON argument.
        $registrationBodyPath = Join-Path ([IO.Path]::GetTempPath()) "avd-registration-$([Guid]::NewGuid().ToString('N')).json"
        try {
            $registrationBody | Set-Content -LiteralPath $registrationBodyPath -Encoding utf8
            [void](Invoke-AzCliJson -ArgumentList @(
                'rest', '--method', 'PATCH',
                '--url', "https://management.azure.com${hostPoolId}?api-version=2024-04-03",
                '--headers', 'Content-Type=application/json',
                '--body', "@$registrationBodyPath"
            ))
        }
        finally {
            Remove-Item -LiteralPath $registrationBodyPath -Force -ErrorAction SilentlyContinue
        }
        $tokenResponse = Invoke-AzCliJson -ArgumentList @(
            'rest', '--method', 'POST',
            '--url', "https://management.azure.com$hostPoolId/retrieveRegistrationToken?api-version=2024-04-03"
        )
        $registrationToken = if ($tokenResponse -and $tokenResponse.PSObject.Properties.Name -contains 'token') { [string]$tokenResponse.token } else { '' }
        if ([string]::IsNullOrWhiteSpace($registrationToken)) {
            throw "AVD did not return a registration token for host pool '$HostPoolName'."
        }
    }
    else {
        # What-if evaluation still needs a parameter value; this placeholder is
        # never deployed because the deployment itself is also skipped.
        $registrationToken = 'whatif-placeholder-token'
    }
}
# setsecret masks the token only inside Azure DevOps (TF_BUILD is set on every
# agent). Anywhere else the line would just print the token, so it is skipped.
# https://learn.microsoft.com/azure/devops/pipelines/build/variables#system-variables
if ($registrationToken -cne 'whatif-placeholder-token' -and $env:TF_BUILD -ieq 'True') {
    Write-Output "##vso[task.setsecret]$registrationToken"
}

$parameterFile = [IO.Path]::Combine([IO.Path]::GetTempPath(), "avd-$VmName-$([Guid]::NewGuid().ToString('N')).parameters.json")
try {
    $parameters = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = [ordered]@{
            vmName = @{ value = $VmName }
            location = @{ value = $Location }
            vmSize = @{ value = $VmSize }
            subnetId = @{ value = $SubnetId }
            hostPoolName = @{ value = $HostPoolName }
            ritmNumber = @{ value = $RitmNumber }
            requestedForUpn = @{ value = $RequestedForUpn }
            environmentName = @{ value = $EnvironmentName }
            imageSourceType = @{ value = $ImageSourceType }
            galleryImageVersionId = @{ value = [string]$GalleryImageVersionId }
            avdDscConfigurationUri = @{ value = $AvdDscConfigurationUri }
            registrationToken = @{ value = $registrationToken }
            localAdminUsername = @{ value = $LocalAdminUsername }
            localAdminPassword = @{ value = (Get-RandomPassword) }
            osDiskSku = @{ value = $OsDiskSku }
        }
    }
    # The temporary parameter file and the what-if report are local working
    # files, not changes to Azure. They are exempt from -WhatIf and -Confirm:
    # otherwise -WhatIf skips writing the file and the ARM what-if, the one
    # step -WhatIf exists to run, cannot read its parameters.
    $parameters | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $parameterFile -Encoding utf8 -WhatIf:$false -Confirm:$false

    $whatIfRaw = & az deployment group what-if `
        --name "avd-$($VmName.ToLowerInvariant())-whatif" `
        --resource-group $ResourceGroupName `
        --subscription $SubscriptionId `
        --template-file $TemplateFile `
        --parameters "@$parameterFile" `
        --result-format FullResourcePayloads `
        --no-pretty-print `
        --only-show-errors `
        --output json
    if ($LASTEXITCODE -ne 0) { throw 'Session-host what-if failed.' }
    $whatIfText = $whatIfRaw -join [Environment]::NewLine
    if ($WhatIfReportPath) {
        $reportParent = Split-Path -Parent $WhatIfReportPath
        if ($reportParent -and -not (Test-Path -LiteralPath $reportParent)) {
            New-Item -ItemType Directory -Path $reportParent -Force -WhatIf:$false -Confirm:$false | Out-Null
        }
        $whatIfText | Set-Content -LiteralPath $WhatIfReportPath -Encoding utf8 -WhatIf:$false -Confirm:$false
    }
    $whatIfResult = $whatIfText | ConvertFrom-Json -Depth 100
    if (@($whatIfResult.changes | Where-Object changeType -In @('Delete', 'Recreate')).Count -gt 0) {
        throw 'Session-host what-if contains a delete or recreate operation. Deployment is blocked.'
    }

    if (-not $PSCmdlet.ShouldProcess($VmName, "Deploy session host into '$ResourceGroupName' for '$RequestedForUpn'")) {
        Write-Output "What-if completed for '$VmName'. No deployment was performed."
        return
    }

    $deploymentName = "avd-$($VmName.ToLowerInvariant())-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
    $deployment = Invoke-AzCliJson -ArgumentList @(
        'deployment', 'group', 'create',
        '--name', $deploymentName,
        '--resource-group', $ResourceGroupName,
        '--subscription', $SubscriptionId,
        '--template-file', $TemplateFile,
        '--parameters', "@$parameterFile",
        '--mode', 'Incremental'
    )
}
finally {
    if (Test-Path -LiteralPath $parameterFile) {
        # Always delete: the file holds the generated local admin password.
        Remove-Item -LiteralPath $parameterFile -Force -WhatIf:$false -Confirm:$false
    }
    $registrationToken = $null
}

$vmId = [string]$deployment.properties.outputs.vmId.value
Write-Output "##vso[task.setvariable variable=vmId;isOutput=true]$vmId"
Write-Output "##vso[task.setvariable variable=userObjectId;isOutput=true]$($user.id)"
Write-Output "##vso[task.setvariable variable=deploymentName;isOutput=true]$deploymentName"
Write-Output "##vso[task.setvariable variable=galleryImageVersionId;isOutput=true]$GalleryImageVersionId"
Write-Output "Deployed or converged '$VmName' for '$RequestedForUpn' without a public IP address."
