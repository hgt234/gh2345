# AppPackagingTriage

Turns an [EndpointExplorer](../EndpointExplorer/README.md) inventory snapshot
into a prioritized app packaging list. Third-party apps are kept separate from
Microsoft apps, so built-in and Microsoft-managed apps do not crowd the list.

The script is offline: it makes no Graph calls and needs no sign-in. It reads
`EndpointInventory.json` and writes two CSVs directly to disk. Because the
script writes them and no browser downloads them, they carry no Mark of the
Web and open normally.

## Usage

```powershell
# 1. Build or refresh the snapshot (per-device apps give exact device counts)
.\EndpointExplorer\Export-EndpointInventory.ps1 -AppInventoryPath C:\Temp\AppInvRawData.zip

# 2. Build the packaging list
.\AppPackagingTriage\Export-AppPackagingTriage.ps1

# Preview the counts and the top 10 without writing anything
.\AppPackagingTriage\Export-AppPackagingTriage.ps1 -WhatIf

# Browse the third-party list interactively
.\AppPackagingTriage\Export-AppPackagingTriage.ps1 -PassThru |
    Where-Object Section -EQ 'ThirdParty' | Out-GridView
```

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-SnapshotPath` | `exports/EndpointExplorer/EndpointInventory.json` | Snapshot to read |
| `-OutputDirectory` | `exports/AppPackagingTriage` | Folder for the CSVs (git-ignored) |
| `-AllPlatforms` | off | Include non-Windows apps |
| `-PassThru` | off | Return the rows, with a `Section` property |

## Output

`ThirdPartyApps.csv` and `MicrosoftApps.csv` have the same columns. Each file
is sorted by device count, highest first:

| Column | Meaning |
| --- | --- |
| Priority | Rank within the file (1 = most devices) |
| App | App name as Intune reports it |
| Publisher | Simplified publisher (see below) |
| Versions | Distinct versions, newest first |
| VersionCount | Number of distinct versions |
| Platform | `windows` unless `-AllPlatforms` is used |
| Devices | Devices with any version of the app |
| DevicesApproximate | `True` when the snapshot has no per-device apps (see below) |
| PublisherRaw | The original publisher value when it differs from Publisher |

## Publisher rules

- **Certificate-style publishers** (MSIX/Store apps, for example
  `CN=Spotify AB, O=Spotify AB, L=Stockholm, C=SE`) are shown by their
  organization (`O=`), or by their common name (`CN=`) when there is no `O=`.
  The package publisher is the signing certificate's subject; see the
  [Identity element](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-identity)
  docs.
- **Microsoft certificate names** (`CN=Microsoft Corporation, ...`,
  `CN=Microsoft Windows, O=Microsoft Corporation, ...`) become
  `Microsoft Corporation`.
- **GUID-only names** (`CN=83564403-...`, as used by Store-assigned
  publishers) become `Unknown (Store-signed)`. These apps stay in the
  third-party list, and PublisherRaw shows the original value.
- **Microsoft list:** a publisher goes there when it starts with the word
  `Microsoft`, for example `Microsoft Corporation`, `Microsoft Corporations`, or
  `Microsoft Corp.`. All other publishers, including blank ones, go to the
  third-party list.

When an app appears under both a plain and a certificate-style form of the same
publisher, the two are merged into one row.

## Device counts

When the snapshot has per-device apps (built with `-AppInventoryPath` or
`-IncludeDeviceApps`), Devices counts distinct devices. A device with two
versions of an app counts once. Without per-device apps, Devices adds up
Intune's per-version counts, so a device with two versions counts twice. In
that case DevicesApproximate is `True` and the script prints a warning. The
report's Installed apps tab counts the same way.

## Validation

```powershell
cd AppPackagingTriage
$findings = Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
if ($findings) { $findings | Format-Table -AutoSize; throw "PSScriptAnalyzer: $(@($findings).Count) finding(s)" }
Invoke-Pester -Path . -Output Detailed
```

The Pester tests are offline and use small fake snapshots.
