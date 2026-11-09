# ManagerDeviceExport

Exports the Intune devices of every user who reports to one or more managers, as a CSV for building Entra device groups. Read-only against the tenant. Uses your existing `Connect-MgGraph` session.

```powershell
Connect-MgGraph -Scopes User.Read.All,DeviceManagementManagedDevices.Read.All,Device.Read.All

# Direct reports of one manager, Windows devices only
.\ManagerDeviceExport\Export-ManagerDeviceList.ps1 -Manager jane.doe@contoso.com -OperatingSystem Windows

# Several managers, the whole reporting chain, preview only
.\ManagerDeviceExport\Export-ManagerDeviceList.ps1 -Manager jane.doe@contoso.com, john.roe@contoso.com -Recurse -WhatIf
```

Output: `exports/ManagerDeviceExport/ManagerDevices_<timestamp>.csv` (git-ignored). There is one row per device.

| Column | Meaning |
| --- | --- |
| `ManagerUPN`, `ReportLevel`, `DirectManagerUPN` | The `-Manager` the user was found under; 1 = direct report |
| `UserPrincipalName`, `UserId`, `UserAccountEnabled` | The report |
| `DeviceName`, `OperatingSystem`, `OSVersion`, `Ownership`, `ComplianceState`, `LastSyncDateTime`, `SerialNumber` | From Intune |
| `IntuneDeviceId` | Intune managed device id |
| `EntraDeviceId` | Entra `deviceId` (Intune `azureADDeviceId`) |
| `EntraDeviceObjectId` | Entra device **object id**: use this for group membership |
| `Status` | `OK`, `NoEntraObject`, `NoEntraDeviceId`, or `NoIntuneDevice` (with `-IncludeUsersWithoutDevices`) |

Notes:

- A device belongs to a user when Intune's `managedDevice.userId` matches that user. Graph does not document a `userId` filter for managedDevices, so the script lists managed devices once (one call per 1,000 devices) and matches them locally.
- Unknown managers stop the run, so a typo cannot silently shrink a group.
- Results are limited by your Intune RBAC scope tags.

Validation: `pwsh` with PSScriptAnalyzer (`PSScriptAnalyzerSettings.psd1`, PS 5.1 rules) and `Invoke-Pester -Path .\ManagerDeviceExport`. The tests mock Graph and run offline.
