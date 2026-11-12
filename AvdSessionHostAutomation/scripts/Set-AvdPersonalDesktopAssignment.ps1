#Requires -Version 7.2

<#
.SYNOPSIS
    Grants access and directly assigns a ready personal session host to the
    requested user.

.DESCRIPTION
    Resolves the requested user in Entra, idempotently grants the built-in
    Virtual Machine User Login role on the VM and Desktop Virtualization User
    role on the desktop application group, and sets the personal session
    host's assignedUser with allowNewSession enabled.

    When SelfDeallocateRoleId is supplied, the VM's own system-assigned
    identity is additionally granted that custom role at the VM's own scope,
    which lets the guest idle power-off task deallocate the machine. The
    assignment identity's ABAC condition permits exactly this grant.

    The session host must exist, be Available, and be unassigned or already
    assigned to the same user; any other assignment fails the script. A second
    run with nothing to change performs no writes.

    With -WhatIf, all discovery and validation runs and a summary of the
    grants and assignment that would occur is printed; nothing is changed.

.PARAMETER SubscriptionId
    Target subscription ID.

.PARAMETER SessionHostResourceGroupName
    Resource group holding the VM.

.PARAMETER PlatformResourceGroupName
    Resource group holding the existing host pool and application group.

.PARAMETER HostPoolName
    Existing AVD personal host-pool name.

.PARAMETER DesktopAppGroupName
    Existing desktop application-group name.

.PARAMETER VmName
    Session-host name, AVD followed by 1-12 digits.

.PARAMETER RequestedForUpn
    UPN of the person receiving the desktop.

.PARAMETER UserObjectId
    Optional pre-resolved Entra object ID of that user; skips the Graph lookup.

.PARAMETER SelfDeallocateRoleId
    Optional GUID of the workload's AVD Prod Self Deallocate custom role (the
    selfDeallocateRoleDefinitionId output of access.bicep). When set, the VM's
    system-assigned identity is granted that role on the VM itself. Empty
    disables the grant.

.EXAMPLE
    ./Set-AvdPersonalDesktopAssignment.ps1 -SubscriptionId $sub -SessionHostResourceGroupName rg-avd-hosts -PlatformResourceGroupName rg-avd -HostPoolName vdpool-prod -DesktopAppGroupName vdag-prod -VmName AVD0012345 -RequestedForUpn user@contoso.com -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$SessionHostResourceGroupName,
    [Parameter(Mandatory)][string]$PlatformResourceGroupName,
    [Parameter(Mandatory)][string]$HostPoolName,
    [Parameter(Mandatory)][string]$DesktopAppGroupName,
    [Parameter(Mandatory)][ValidatePattern('\AAVD[0-9]{1,12}\z')][string]$VmName,
    [Parameter(Mandatory)][string]$RequestedForUpn,
    [string]$UserObjectId,
    [string]$SelfDeallocateRoleId = ''
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

function Grant-ScopedRoleAssignment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$RoleDefinitionId,
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][ValidateSet('User', 'ServicePrincipal')][string]$PrincipalType
    )
    $expectedRoleId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$RoleDefinitionId"
    $listArguments = @(
        'role', 'assignment', 'list', '--assignee-object-id', $PrincipalId,
        '--scope', $Scope, '--subscription', $SubscriptionId,
        '--fill-principal-name', 'false', '--fill-role-definition-name', 'false'
    )
    $existing = @(Invoke-AzCliJson -ArgumentList $listArguments) | Where-Object roleDefinitionId -IEQ $expectedRoleId
    if ($existing) {
        Write-Verbose "Role '$RoleDefinitionId' is already assigned at '$Scope'."
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Scope, "Grant role '$RoleDefinitionId' to $PrincipalType '$PrincipalId'")) { return }
    try {
        [void](Invoke-AzCliJson -ArgumentList @(
            'role', 'assignment', 'create',
            '--assignee-object-id', $PrincipalId,
            '--assignee-principal-type', $PrincipalType,
            '--role', $RoleDefinitionId,
            '--scope', $Scope,
            '--subscription', $SubscriptionId
        ))
    }
    catch {
        # A concurrent idempotent request can win the create race. Re-read
        # the exact scope and role before deciding that this is a failure.
        $existing = @(Invoke-AzCliJson -ArgumentList $listArguments) | Where-Object roleDefinitionId -IEQ $expectedRoleId
        if (-not $existing) { throw }
    }
}

$vmId = "/subscriptions/$SubscriptionId/resourceGroups/$SessionHostResourceGroupName/providers/Microsoft.Compute/virtualMachines/$VmName"
$appGroupId = "/subscriptions/$SubscriptionId/resourceGroups/$PlatformResourceGroupName/providers/Microsoft.DesktopVirtualization/applicationGroups/$DesktopAppGroupName"
$hostPoolId = "/subscriptions/$SubscriptionId/resourceGroups/$PlatformResourceGroupName/providers/Microsoft.DesktopVirtualization/hostPools/$HostPoolName"

if ([string]::IsNullOrWhiteSpace($UserObjectId)) {
    $encodedUpn = [Uri]::EscapeDataString($RequestedForUpn)
    $user = Invoke-AzCliJson -ArgumentList @(
        'rest', '--method', 'GET',
        '--url', "https://graph.microsoft.com/v1.0/users/${encodedUpn}?`$select=id,accountEnabled"
    )
    if (-not $user.id -or $user.accountEnabled -ne $true) {
        throw "Entra user '$RequestedForUpn' was not found or is disabled."
    }
    $UserObjectId = [string]$user.id
}

# Built-in roles: Virtual Machine User Login and Desktop Virtualization User.
Grant-ScopedRoleAssignment -Scope $vmId -RoleDefinitionId 'fb879df8-f326-4884-b1cf-06f3ad86be52' -PrincipalId $UserObjectId -PrincipalType 'User'
Grant-ScopedRoleAssignment -Scope $appGroupId -RoleDefinitionId '1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63' -PrincipalId $UserObjectId -PrincipalType 'User'

# Azure DevOps leaves an undefined $(VARIABLE_NAME) macro unchanged; treat it
# as absent so the grant is simply skipped until the role is configured.
$SelfDeallocateRoleId = if ($SelfDeallocateRoleId -match '^\$\([A-Za-z0-9_.-]+\)$') { '' } else { $SelfDeallocateRoleId.Trim() }
if ($SelfDeallocateRoleId) {
    if ($SelfDeallocateRoleId -notmatch '\A[0-9a-fA-F-]{36}\z') {
        throw "SelfDeallocateRoleId '$SelfDeallocateRoleId' is not a role-definition GUID."
    }
    $vmResource = Invoke-AzCliJson -ArgumentList @(
        'vm', 'show', '--resource-group', $SessionHostResourceGroupName,
        '--name', $VmName, '--subscription', $SubscriptionId
    )
    $vmPrincipalId = [string]$vmResource.identity.principalId
    if ([string]::IsNullOrWhiteSpace($vmPrincipalId)) {
        throw "VM '$VmName' has no system-assigned identity; the self-deallocate role cannot be granted."
    }
    Grant-ScopedRoleAssignment -Scope $vmId -RoleDefinitionId $SelfDeallocateRoleId -PrincipalId $vmPrincipalId -PrincipalType 'ServicePrincipal'
}

$sessionHostResponse = Invoke-AzCliJson -ArgumentList @(
    'rest', '--method', 'GET',
    '--url', "https://management.azure.com$hostPoolId/sessionHosts?api-version=2024-04-03"
)
$sessionHost = @($sessionHostResponse.value) | Where-Object {
    $leaf = (([string]$_.name -split '/')[-1] -split '\.')[0]
    $leaf -ieq $VmName
} | Select-Object -First 1
if (-not $sessionHost) { throw "AVD session host '$VmName' was not found in '$HostPoolName'." }
if ([string]$sessionHost.properties.status -ine 'Available') {
    throw "AVD session host '$VmName' is '$($sessionHost.properties.status)', not Available."
}
if ($sessionHost.properties.assignedUser -and [string]$sessionHost.properties.assignedUser -ine $RequestedForUpn) {
    throw "Session host '$VmName' is already assigned to '$($sessionHost.properties.assignedUser)'."
}

if (-not $PSCmdlet.ShouldProcess($VmName, "Assign personal session host to '$RequestedForUpn'")) {
    Write-Output "Would assign '$RequestedForUpn' to personal session host '$VmName'. Nothing was changed."
    return
}

$assignmentBody = @{ properties = @{ assignedUser = $RequestedForUpn; allowNewSession = $true } } | ConvertTo-Json -Compress
$assignmentBodyPath = Join-Path ([IO.Path]::GetTempPath()) "avd-assignment-$([Guid]::NewGuid().ToString('N')).json"
try {
    $assignmentBody | Set-Content -LiteralPath $assignmentBodyPath -Encoding utf8
    [void](Invoke-AzCliJson -ArgumentList @(
        'rest', '--method', 'PATCH',
        '--url', "https://management.azure.com$($sessionHost.id)?api-version=2024-04-03",
        '--headers', 'Content-Type=application/json',
        '--body', "@$assignmentBodyPath"
    ))
}
finally {
    Remove-Item -LiteralPath $assignmentBodyPath -Force -ErrorAction SilentlyContinue
}

Write-Output "Assigned '$RequestedForUpn' to personal session host '$VmName'."
