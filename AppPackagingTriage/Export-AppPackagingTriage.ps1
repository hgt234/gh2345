#requires -Version 5.1
<#
.SYNOPSIS
Turns an EndpointExplorer inventory snapshot into a prioritized app packaging
list, with third-party apps separated from Microsoft apps.

.DESCRIPTION
Reads EndpointInventory.json (written by EndpointExplorer/
Export-EndpointInventory.ps1) and writes two CSVs, each sorted by device count
(most installed first):

  ThirdPartyApps.csv  Apps to review for packaging.
  MicrosoftApps.csv   Apps whose publisher starts with "Microsoft", kept apart
                      to cut the noise of built-in and Microsoft-managed apps.

Columns: Priority, App, Publisher, Versions (newest first), VersionCount,
Platform, Devices, DevicesApproximate, PublisherRaw.

Certificate-style publishers from MSIX/Store apps (CN=..., O=...) are shown as
a plain name; Microsoft ones become "Microsoft Corporation". PublisherRaw keeps
the original value whenever it differs from Publisher.

Offline: no Graph calls and no sign-in. The script writes the CSVs directly,
so they do not carry the browser's Mark of the Web. They contain app names and
counts only (no device names or UPNs); the default location is still under the
git-ignored exports/ folder.

.PARAMETER SnapshotPath
EndpointExplorer snapshot to read. Relative paths resolve against the current
location. Defaults to exports/EndpointExplorer/EndpointInventory.json.

.PARAMETER OutputDirectory
Folder for the two CSVs. Relative paths resolve against the current location.
Defaults to exports/AppPackagingTriage.

.PARAMETER AllPlatforms
Includes apps from every platform in the snapshot. Default is Windows only.

.PARAMETER PassThru
Returns the rows (with a Section property) for further filtering, for example
with Out-GridView.

.EXAMPLE
.\AppPackagingTriage\Export-AppPackagingTriage.ps1
Reads the default snapshot and writes both CSVs to exports/AppPackagingTriage.

.EXAMPLE
.\AppPackagingTriage\Export-AppPackagingTriage.ps1 -WhatIf
Reads the snapshot, prints the counts and the top 10 third-party apps, and
writes nothing.

.EXAMPLE
.\AppPackagingTriage\Export-AppPackagingTriage.ps1 -SnapshotPath C:\Temp\EndpointInventory.json -PassThru |
    Where-Object Section -EQ 'ThirdParty' | Out-GridView
Writes the CSVs and opens the third-party list in a grid view.

.NOTES
For exact device counts, build the snapshot with per-device apps
(Export-EndpointInventory.ps1 -AppInventoryPath or -IncludeDeviceApps).
Without them, Devices sums Intune's per-version counts and is approximate.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateNotNullOrEmpty()]
    [string] $SnapshotPath = 'exports/EndpointExplorer/EndpointInventory.json',
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory = 'exports/AppPackagingTriage',
    [switch] $AllPlatforms,
    [switch] $PassThru
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'AppPackagingTriage.Common.ps1')

# All writes happen inside Invoke-AppPackagingTriage, each behind its own
# ShouldProcess call. -WhatIf/-Confirm reach it through $PSBoundParameters;
# the path defaults are added because unbound parameters are not in it.
$PSBoundParameters['SnapshotPath'] = $SnapshotPath
$PSBoundParameters['OutputDirectory'] = $OutputDirectory
Invoke-AppPackagingTriage @PSBoundParameters
