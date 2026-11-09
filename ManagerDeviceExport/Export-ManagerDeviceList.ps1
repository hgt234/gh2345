#requires -Version 5.1
<#
.SYNOPSIS
Exports the Intune devices of every user who reports to one or more managers,
as a CSV ready for building Entra device groups.

.DESCRIPTION
Read-only against the tenant. Uses your existing Microsoft Graph session
(Connect-MgGraph); it does not sign in or handle credentials.

  1. Resolves each -Manager (UPN or object id). An unknown manager stops the run.
  2. Gets their direct reports (users only; org contacts are skipped).
     -Recurse walks the whole reporting chain below each manager.
  3. Lists Intune managed devices once and keeps those whose associated user
     (managedDevice.userId) is one of the reports.
  4. Looks up each device's Entra object id via $batch, because Entra group
     membership needs the device object id, not the Intune id or Entra deviceId.
  5. Writes one CSV row per device.

Use EntraDeviceObjectId (rows with Status = OK) as the group member id.
Status values: OK, NoEntraObject, NoEntraDeviceId, NoIntuneDevice
(the last only with -IncludeUsersWithoutDevices).

Required delegated scopes (least privileged):
  User.Read.All                            directReports with accountEnabled
  DeviceManagementManagedDevices.Read.All  Intune managed devices
  Device.Read.All                          Entra device object lookup
Results are limited by your Intune RBAC scope tags.

The CSV contains UPNs, device names, and object ids. The default location is
under the git-ignored exports/ folder; treat the file as sensitive.

.PARAMETER Manager
One or more managers, by UPN or Entra object id.

.PARAMETER Recurse
Include the full reporting chain under each manager, not just direct reports.
Each user is listed once, under the first -Manager that reaches them.

.PARAMETER OperatingSystem
Keep only devices whose Intune operatingSystem equals one of these values
(case-insensitive), for example Windows, iOS, Android, macOS.

.PARAMETER IncludeUsersWithoutDevices
Add a NoIntuneDevice row for each report that has no matching device.

.PARAMETER OutputPath
CSV file to write. Relative paths resolve against the current location.
Defaults to exports/ManagerDeviceExport/ManagerDevices_<timestamp>.csv.

.PARAMETER PassThru
Also return the rows to the pipeline.

.EXAMPLE
Connect-MgGraph -Scopes User.Read.All,DeviceManagementManagedDevices.Read.All,Device.Read.All
.\ManagerDeviceExport\Export-ManagerDeviceList.ps1 -Manager jane.doe@contoso.com -OperatingSystem Windows

Exports the Windows devices of Jane's direct reports.

.EXAMPLE
.\ManagerDeviceExport\Export-ManagerDeviceList.ps1 -Manager jane.doe@contoso.com, john.roe@contoso.com -Recurse -WhatIf

Does every read and prints the summary, but writes no file.

.EXAMPLE
.\ManagerDeviceExport\Export-ManagerDeviceList.ps1 -Manager jane.doe@contoso.com -PassThru |
    Where-Object Status -EQ 'OK' | Select-Object -ExpandProperty EntraDeviceObjectId

Returns the Entra device object ids ready to add to a group.

.NOTES
Graph v1.0 sources are listed in ManagerDeviceExport.Common.ps1.
Validated offline with Pester mocks; not executed against a tenant by the author.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Manager,

    [switch] $Recurse,

    [ValidateNotNullOrEmpty()]
    [string[]] $OperatingSystem,

    [switch] $IncludeUsersWithoutDevices,

    [ValidateNotNullOrEmpty()]
    [string] $OutputPath = ('exports/ManagerDeviceExport/ManagerDevices_{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss')),

    [switch] $PassThru
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'ManagerDeviceExport.Common.ps1')

$session = Initialize-MdeGraphSession
Write-Verbose ('Graph session: {0} (tenant {1}).' -f $session.Account, $session.TenantId)

$managers = Resolve-MdeManager -Identity $Manager
$reports = Get-MdeReport -Managers $managers -Recurse:$Recurse
Write-Verbose ('{0} report(s) found under {1} manager(s).' -f $reports.Count, $managers.Count)

$rows = @()
if ($reports.Count -gt 0) {
    $deviceIndex = Get-MdeManagedDeviceIndex
    $entraIds = New-Object 'System.Collections.Generic.List[string]'
    foreach ($user in $reports) {
        if (-not $deviceIndex.ContainsKey($user.Id)) { continue }
        foreach ($device in $deviceIndex[$user.Id]) {
            if ($OperatingSystem -and $OperatingSystem -notcontains [string](Get-MdeProperty $device 'operatingSystem')) { continue }
            $id = ConvertTo-MdeGuid (Get-MdeProperty $device 'azureADDeviceId')
            if ($id) { $entraIds.Add($id) }
        }
    }
    $entraDevices = Resolve-MdeEntraDevice -DeviceIds $entraIds.ToArray()
    $rows = Get-MdeDeviceRow -Reports $reports -DeviceIndex $deviceIndex -EntraDevices $entraDevices `
        -OperatingSystem $OperatingSystem -IncludeUsersWithoutDevices:$IncludeUsersWithoutDevices
}

$deviceRows = @($rows | Where-Object Status -NE 'NoIntuneDevice')
$usersWithDevices = @($deviceRows | Select-Object -ExpandProperty UserId -Unique).Count
$summary = @(
    ('Managers:             {0}' -f (@($managers | ForEach-Object { $_.UserPrincipalName }) -join ', '))
    ('Reports (users):      {0}' -f $reports.Count)
    ('Users with devices:   {0}' -f $usersWithDevices)
    ('Users without:        {0}' -f ($reports.Count - $usersWithDevices))
    ('Devices:              {0}' -f $deviceRows.Count)
    ('  Ready (Status OK):  {0}' -f @($deviceRows | Where-Object Status -EQ 'OK').Count)
    ('  NoEntraObject:      {0}' -f @($deviceRows | Where-Object Status -EQ 'NoEntraObject').Count)
    ('  NoEntraDeviceId:    {0}' -f @($deviceRows | Where-Object Status -EQ 'NoEntraDeviceId').Count)
)
foreach ($line in $summary) { Write-Information $line -InformationAction Continue }

$resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ($rows.Count -eq 0) {
    Write-Warning 'No rows to export; no file written.'
}
elseif ($PSCmdlet.ShouldProcess($resolvedPath, "Write CSV with $($rows.Count) row(s)")) {
    $directory = Split-Path -Path $resolvedPath -Parent
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false -Confirm:$false | Out-Null
    }
    $rows | ForEach-Object {
        $safe = [ordered]@{}
        foreach ($property in $_.PSObject.Properties) { $safe[$property.Name] = ConvertTo-MdeCsvValue $property.Value }
        [pscustomobject]$safe
    } | Export-Csv -LiteralPath $resolvedPath -NoTypeInformation -Encoding UTF8 -WhatIf:$false -Confirm:$false
    Write-Information ('CSV written: {0}' -f $resolvedPath) -InformationAction Continue
}

if ($PassThru) { $rows }
