#Requires -Version 7.2

<#
.SYNOPSIS
    Adds the requested user to the workload's Entra access group.

.DESCRIPTION
    Reads the group named by AccessGroupId (the workload variable
    AVD_ACCESS_GROUP_ID), checks that it is a group the build may manage, and
    adds the requested user as a direct member if they are not one already.
    A second run with nothing to change performs no writes.

    The pipeline identity needs no Graph write permission. It must be an
    owner of the group, and it needs Graph User.Read.All (Application) to
    resolve the UPN, which the build already requires. Owner rights reach
    only groups the identity owns: reading or changing any other group
    returns 403. This was verified in a lab tenant with an app-only token
    that held no Graph permission but User.Read.All.

    The group must be a cloud security group with assigned membership:
    - Dynamic groups are rejected, because their membership comes from a rule
      and cannot be written.
    - Groups synced from on-premises AD are rejected, because their
      membership is managed on-premises.
    - Role-assignable groups are rejected, because adding members to them
      needs RoleManagement.ReadWrite.Directory, which the build is not given.

    An empty AccessGroupId, or the unresolved $(AVD_ACCESS_GROUP_ID) macro of
    a variable group that does not define it, skips the step: the workload
    then manages membership outside the build.

    With -WhatIf, the user and group are read and validated and the summary
    says whether the user would be added; nothing is changed.

.PARAMETER RequestedForUpn
    UPN of the person receiving the desktop.

.PARAMETER AccessGroupId
    Object ID of the Entra access group (AVD_ACCESS_GROUP_ID). Empty skips
    the step.

.PARAMETER UserObjectId
    Optional pre-resolved Entra object ID of that user; skips the UPN lookup.

.EXAMPLE
    ./Add-AvdUserToAccessGroup.ps1 -RequestedForUpn user@contoso.com -AccessGroupId 11111111-1111-1111-1111-111111111111 -WhatIf

.NOTES
    Graph references:
    https://learn.microsoft.com/graph/api/group-post-members
    https://learn.microsoft.com/graph/api/group-list-members
    https://learn.microsoft.com/graph/aad-advanced-queries
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$RequestedForUpn,
    # Not validated as a GUID here: an undefined variable arrives as the
    # literal $(AVD_ACCESS_GROUP_ID) macro and must mean "skip".
    [string]$AccessGroupId = '',
    [string]$UserObjectId
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

$AccessGroupId = if ($AccessGroupId -match '^\$\([A-Za-z0-9_.-]+\)$') { '' } else { $AccessGroupId.Trim() }
if (-not $AccessGroupId) {
    Write-Output 'No access group is configured (AVD_ACCESS_GROUP_ID is empty), so group membership was not changed.'
    return
}
if ($AccessGroupId -notmatch '\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z') {
    throw "AccessGroupId '$AccessGroupId' is not a group object ID (GUID)."
}

if ([string]::IsNullOrWhiteSpace($UserObjectId)) {
    $encodedUpn = [Uri]::EscapeDataString($RequestedForUpn)
    try {
        $user = Invoke-AzCliJson -ArgumentList @(
            'rest', '--method', 'GET',
            '--url', "https://graph.microsoft.com/v1.0/users/${encodedUpn}?`$select=id,accountEnabled"
        )
    }
    catch {
        throw "Entra user '$RequestedForUpn' was not found or could not be read. $($_.Exception.Message)"
    }
    if (-not $user -or -not $user.id -or $user.accountEnabled -ne $true) {
        throw "Entra user '$RequestedForUpn' was not found or is disabled."
    }
    $UserObjectId = [string]$user.id
}

$groupUrl = "https://graph.microsoft.com/v1.0/groups/${AccessGroupId}?`$select=id,displayName,securityEnabled,groupTypes,onPremisesSyncEnabled,isAssignableToRole"
try {
    $group = Invoke-AzCliJson -ArgumentList @('rest', '--method', 'GET', '--url', $groupUrl)
}
catch {
    # With owner rights only, a group the identity does not own returns 403,
    # the same as a missing permission, so the message names both causes.
    throw "Cannot read Entra group '$AccessGroupId'. Check that the ID is right and that the pipeline's service principal is an owner of the group. $($_.Exception.Message)"
}
$groupName = [string]$group.displayName
if ($group.securityEnabled -ne $true) {
    throw "Group '$groupName' is not a security group, so it cannot grant Azure access."
}
if (@($group.groupTypes) -contains 'DynamicMembership') {
    throw "Group '$groupName' has dynamic membership; its members come from a rule and cannot be added."
}
if ($group.onPremisesSyncEnabled -eq $true) {
    throw "Group '$groupName' is synced from on-premises AD; add the user there instead."
}
if ($group.isAssignableToRole -eq $true) {
    throw "Group '$groupName' is role-assignable; the build cannot add members to it."
}

# Advanced query: the $filter on members needs ConsistencyLevel eventual and
# $count (without them the owner-only identity gets 403). The answer can lag
# a recent change; a stale "not a member" only leads to the add below, which
# then reports the existing membership.
#
# This query must not go through 'az rest'. On a Windows agent az is az.cmd,
# so its arguments pass through cmd.exe, which splits the URL at each '&'.
# Graph then received only the $filter part, without $count or the
# ConsistencyLevel header, and answered 403; cmd.exe also tried to run
# "$select=id" as a command. Only the token comes from az; that command has
# no special characters. Wait-AvdReadiness.ps1 queries Graph the same way.
$memberUrl = "https://graph.microsoft.com/v1.0/groups/$AccessGroupId/members?`$filter=id%20eq%20%27$UserObjectId%27&`$select=id&`$count=true"
$graphToken = [string](Invoke-AzCliJson -ArgumentList @('account', 'get-access-token', '--resource', 'https://graph.microsoft.com')).accessToken
try {
    $membership = Invoke-RestMethod -Method Get -Uri $memberUrl -Headers @{
        Authorization = "Bearer $graphToken"
        ConsistencyLevel = 'eventual'
    }
}
catch {
    $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
    throw "Graph refused the membership check on group '$groupName'. The pipeline's service principal must be an owner of the group. $detail"
}
finally {
    $graphToken = $null
}
if (@($membership.value).Count -gt 0) {
    Write-Output "'$RequestedForUpn' is already a member of '$groupName'. Nothing was changed."
    return
}

if (-not $PSCmdlet.ShouldProcess($groupName, "Add '$RequestedForUpn' as a member")) {
    Write-Output "Would add '$RequestedForUpn' to group '$groupName'. Nothing was changed."
    return
}

$memberBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$UserObjectId" } | ConvertTo-Json -Compress
$memberBodyPath = Join-Path ([IO.Path]::GetTempPath()) "avd-group-member-$([Guid]::NewGuid().ToString('N')).json"
try {
    $memberBody | Set-Content -LiteralPath $memberBodyPath -Encoding utf8
    [void](Invoke-AzCliJson -ArgumentList @(
        'rest', '--method', 'POST',
        '--url', "https://graph.microsoft.com/v1.0/groups/$AccessGroupId/members/`$ref",
        '--headers', 'Content-Type=application/json',
        '--body', "@$memberBodyPath"
    ))
}
catch {
    # Graph answers 400 "One or more added object references already exist"
    # when the user is already a member.
    if ($_.Exception.Message -match 'added object references already exist') {
        Write-Output "'$RequestedForUpn' is already a member of '$groupName'. Nothing was changed."
        return
    }
    if ($_.Exception.Message -match 'Authorization_RequestDenied') {
        throw "Graph refused to add '$RequestedForUpn' to '$groupName'. The pipeline's service principal must be an owner of the group. $($_.Exception.Message)"
    }
    throw
}
finally {
    Remove-Item -LiteralPath $memberBodyPath -Force -ErrorAction SilentlyContinue
}

Write-Output "Added '$RequestedForUpn' to group '$groupName'."
