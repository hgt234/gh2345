#requires -Version 5.1
<#
Shared logic for Export-AppPackagingTriage.ps1. Reads an EndpointExplorer
snapshot (EndpointInventory.json) and turns its detected-app records into a
prioritized packaging list, split into third-party and Microsoft apps.

Standalone on purpose: it does not dot-source EndpointExplorer code. It reads
only the snapshot fields listed in $script:AppTriageSchemaVersion's comment.
Pure functions (no file writes) so AppPackagingTriage.Tests.ps1 can test them.
#>

Set-StrictMode -Version 3.0

# EndpointExplorer snapshot schema this reader understands. Fields used:
# schemaVersion, generatedAt, source.includeDeviceApps,
# appRecords[].name/publisher/version/platform/deviceCount,
# devices[].intuneDeviceId/appRecordIndexes.
$script:AppTriageSchemaVersion = 2

# The text shown for a certificate-style publisher with no readable name.
$script:AppTriageStoreSignedPublisher = 'Unknown (Store-signed)'

function Get-AppTriageProperty {
    # Null-safe property read under StrictMode (missing property -> $null).
    param($Object, [Parameter(Mandatory)] [string] $Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function ConvertTo-AppTriagePublisher {
    <#
    Simplifies a publisher for display.

    MSIX/Store apps report the signing certificate subject as the publisher,
    for example 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond,
    S=Washington, C=US'. The package manifest's Identity/@Publisher "must match
    the publisher subject information of the certificate used to sign a
    package" (learn.microsoft.com, uapmanifestschema element-identity).

    For a distinguished name, the organization (O=) is used, else the common
    name (CN=). Microsoft names (Microsoft Corporation, Microsoft Windows, ...)
    become 'Microsoft Corporation'. A name that is only a GUID, which Store-
    assigned publishers use, becomes 'Unknown (Store-signed)'. Any other
    publisher is returned trimmed and unchanged.
    #>
    param([AllowNull()] [AllowEmptyString()] [string] $Publisher)
    if ($null -eq $Publisher) { return '' }
    $text = $Publisher.Trim()
    if ($text -notmatch '^(CN|O|OU|L|S|ST|C|E)\s*=') { return $text }

    $parts = @{}
    # RDN values are either "quoted" ("" escapes a quote) or run to the next comma.
    foreach ($match in [regex]::Matches($text, '(?:^|,)\s*([A-Za-z]+)\s*=\s*("(?:[^"]|"")*"|[^,]*)')) {
        $key = $match.Groups[1].Value.ToUpperInvariant()
        $value = $match.Groups[2].Value.Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Substring(1, $value.Length - 2).Replace('""', '"') }
        if (-not $parts.ContainsKey($key)) { $parts[$key] = $value.Trim() }
    }
    $name = ''
    foreach ($key in @('O', 'CN')) {
        if ($parts.ContainsKey($key) -and $parts[$key] -and $parts[$key] -notmatch '^\{?[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}?$') { $name = $parts[$key]; break }
    }
    if (-not $name) { return $script:AppTriageStoreSignedPublisher }
    if (Test-AppTriageMicrosoftPublisher $name) { return 'Microsoft Corporation' }
    return $name
}

function Test-AppTriageMicrosoftPublisher {
    # True for publishers starting with the word Microsoft: 'Microsoft
    # Corporation', 'Microsoft Corporations' (as some VC++ runtimes report it),
    # 'Microsoft Windows', 'Microsoft Corp.'. Not 'MicrosoftXYZ Ltd'.
    param([AllowNull()] [AllowEmptyString()] [string] $Publisher)
    return ($null -ne $Publisher -and $Publisher.Trim() -match '^Microsoft\b')
}

function ConvertTo-AppTriageVersion {
    # Leading dotted number of an inventory version: '23.01' -> 23.1,
    # '12' -> 12.0, '1.2.3-beta' -> 1.2.3. Returns $null otherwise. Matches
    # EndpointExplorer's ConvertTo-EndpointVersion so versions sort the same.
    param([AllowNull()] [AllowEmptyString()] [string] $Value)
    if ($null -eq $Value -or $Value.Trim() -notmatch '^\d+(\.\d+){0,3}') { return $null }
    $parts = @($Matches[0].Split('.'))
    if ($parts.Count -eq 1) { $parts += '0' }
    $parsed = $null
    if ([version]::TryParse(($parts -join '.'), [ref]$parsed)) { return $parsed }
    return $null
}

function Import-AppTriageSnapshot {
    # Loads an EndpointExplorer snapshot and checks the fields this script uses.
    # Throws with every problem found rather than producing an empty list.
    param([Parameter(Mandatory)] [string] $Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "Snapshot '$Path' is empty." }
    try { $snapshot = $raw | ConvertFrom-Json }
    catch { throw "Snapshot '$Path' is not valid JSON: $($_.Exception.Message)" }
    if ($null -eq $snapshot -or $snapshot -is [string] -or $snapshot -is [array]) { throw "Snapshot '$Path' is not a JSON object." }

    $problems = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in @('schemaVersion', 'generatedAt', 'source', 'devices', 'appRecords')) {
        if (-not $snapshot.PSObject.Properties[$name]) { $problems.Add("Missing '$name'.") }
    }
    if ($problems.Count -eq 0) {
        if ([string]$snapshot.schemaVersion -ne [string]$script:AppTriageSchemaVersion) {
            $problems.Add("Unsupported schemaVersion '$($snapshot.schemaVersion)' (expected $script:AppTriageSchemaVersion).")
        }
        if ($null -eq $snapshot.appRecords) { $problems.Add("'appRecords' is null.") }
        if ($null -eq (Get-AppTriageProperty $snapshot.source 'includeDeviceApps')) { $problems.Add("Missing 'source.includeDeviceApps'.") }
        $index = 0
        foreach ($record in @($snapshot.appRecords)) {
            $missing = @('name', 'publisher', 'version', 'platform', 'deviceCount' | Where-Object { $null -eq $record -or -not $record.PSObject.Properties[$_] })
            if ($missing.Count -gt 0) { $problems.Add("App record #$index is missing: $($missing -join ', ')."); break }
            $index++
        }
    }
    if ($problems.Count -gt 0) { throw "Snapshot '$Path' is not a usable EndpointExplorer snapshot: $($problems -join ' ')" }
    return $snapshot
}

function Get-AppTriageRow {
    <#
    Groups the snapshot's app records by app name + simplified publisher +
    platform, so 'Microsoft Corporation' and 'CN=Microsoft Corporation, O=...'
    entries for the same app become one row.

    With per-device apps (source.includeDeviceApps), Devices is the number of
    distinct devices with any version of the app. Without them it is the sum of
    Intune's per-version counts (a device with two versions counts twice) and
    DevicesApproximate is true, as in the report's Installed apps tab.

    Returns rows sorted by Devices (descending) then App, each with a
    Section of 'ThirdParty' or 'Microsoft' and a Priority rank (1 = most
    devices) within its section.
    #>
    param(
        [Parameter(Mandatory)] $Snapshot,
        [switch] $AllPlatforms
    )
    $records = @($Snapshot.appRecords)
    $exact = [bool](Get-AppTriageProperty $Snapshot.source 'includeDeviceApps')

    $groups = [ordered]@{}
    $groupOfIndex = @{}
    for ($i = 0; $i -lt $records.Count; $i++) {
        $record = $records[$i]
        $platform = [string]$record.platform
        if (-not $AllPlatforms -and $platform -ne 'windows') { continue }
        $name = ([string]$record.name).Trim()
        $publisher = ConvertTo-AppTriagePublisher ([string]$record.publisher)
        $key = ('{0}|{1}|{2}' -f $name, $publisher, $platform).ToLowerInvariant()
        if (-not $groups.Contains($key)) {
            $groups[$key] = @{
                Name = $name; Publisher = $publisher; Platform = $platform
                Versions = New-Object 'System.Collections.Generic.List[string]'
                RawPublishers = New-Object 'System.Collections.Generic.List[string]'
                SummedCount = [long]0
                Devices = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            }
        }
        $group = $groups[$key]
        $version = [string]$record.version
        if (-not $group.Versions.Contains($version)) { $group.Versions.Add($version) }
        $rawPublisher = ([string]$record.publisher).Trim()
        if (-not $group.RawPublishers.Contains($rawPublisher)) { $group.RawPublishers.Add($rawPublisher) }
        $group.SummedCount += [long]$record.deviceCount
        $groupOfIndex[$i] = $key
    }

    if ($exact) {
        foreach ($device in @($Snapshot.devices)) {
            $deviceId = [string](Get-AppTriageProperty $device 'intuneDeviceId')
            foreach ($index in @(Get-AppTriageProperty $device 'appRecordIndexes')) {
                if ($null -eq $index) { continue }
                $key = $groupOfIndex[[int]$index]
                if ($key) { [void]$groups[$key].Devices.Add($deviceId) }
            }
        }
    }

    $rows = foreach ($key in $groups.Keys) {
        $group = $groups[$key]
        $versions = @($group.Versions.ToArray() | Sort-Object -Property @(
                @{ Expression = { $parsed = ConvertTo-AppTriageVersion $_; if ($null -eq $parsed) { [version]'0.0' } else { $parsed } }; Descending = $true },
                @{ Expression = { $_ }; Descending = $true }))
        [pscustomobject][ordered]@{
            Section = $(if (Test-AppTriageMicrosoftPublisher $group.Publisher) { 'Microsoft' } else { 'ThirdParty' })
            Priority = 0
            App = $group.Name
            Publisher = $group.Publisher
            Versions = ($versions -join '; ')
            VersionCount = $versions.Count
            Platform = $group.Platform
            Devices = $(if ($exact) { $group.Devices.Count } else { $group.SummedCount })
            DevicesApproximate = -not $exact
            PublisherRaw = (@($group.RawPublishers.ToArray() | Where-Object { $_ -ne $group.Publisher }) -join '; ')
        }
    }
    $sorted = @($rows | Sort-Object -Property @{ Expression = 'Devices'; Descending = $true }, @{ Expression = 'App'; Descending = $false }, @{ Expression = 'Publisher'; Descending = $false })
    $rank = @{ ThirdParty = 0; Microsoft = 0 }
    foreach ($row in $sorted) {
        $rank[$row.Section]++
        $row.Priority = $rank[$row.Section]
    }
    return $sorted
}

function ConvertTo-AppTriageCsvSafeRow {
    # Spreadsheet formula injection (OWASP "CSV Injection"): a text cell that
    # starts with = + - @ tab or CR is prefixed with a single quote so Excel
    # shows it as text. App names and publishers come from endpoints.
    param([Parameter(Mandatory)] $Row)
    $safe = [ordered]@{}
    foreach ($property in $Row.PSObject.Properties) {
        if ($property.Name -eq 'Section') { continue }
        $value = $property.Value
        if ($value -is [string] -and $value -match '^[=+\-@\t\r]') { $value = "'" + $value }
        $safe[$property.Name] = $value
    }
    return [pscustomobject]$safe
}

function Invoke-AppPackagingTriage {
    # Body of Export-AppPackagingTriage.ps1; see its help for parameters.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [string] $SnapshotPath,
        [Parameter(Mandatory)] [string] $OutputDirectory,
        [switch] $AllPlatforms,
        [switch] $PassThru
    )
    $snapshotFile = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SnapshotPath)
    if (-not (Test-Path -LiteralPath $snapshotFile -PathType Leaf)) {
        throw "Snapshot '$snapshotFile' not found. Run EndpointExplorer/Export-EndpointInventory.ps1 first, or pass -SnapshotPath."
    }
    $directory = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)

    $snapshot = Import-AppTriageSnapshot -Path $snapshotFile
    $rows = @(Get-AppTriageRow -Snapshot $snapshot -AllPlatforms:$AllPlatforms)
    $thirdParty = @($rows | Where-Object Section -EQ 'ThirdParty')
    $microsoft = @($rows | Where-Object Section -EQ 'Microsoft')

    Write-Information ('Snapshot: {0} (generated {1}).' -f $snapshotFile, $snapshot.generatedAt) -InformationAction Continue
    Write-Information ('Apps ({0}): {1} third-party, {2} Microsoft.' -f $(if ($AllPlatforms) { 'all platforms' } else { 'Windows' }), $thirdParty.Count, $microsoft.Count) -InformationAction Continue
    if (-not $snapshot.source.includeDeviceApps) {
        Write-Warning 'The snapshot has no per-device apps, so Devices is the sum of per-version counts (approximate). Rebuild it with Export-EndpointInventory.ps1 -AppInventoryPath for exact counts.'
    }
    foreach ($row in @($thirdParty | Select-Object -First 10)) {
        Write-Information ('  {0,3}. {1} ({2}) - {3} device(s), {4} version(s)' -f $row.Priority, $row.App, $row.Publisher, $row.Devices, $row.VersionCount) -InformationAction Continue
    }

    $files = [ordered]@{
        (Join-Path $directory 'ThirdPartyApps.csv') = $thirdParty
        (Join-Path $directory 'MicrosoftApps.csv') = $microsoft
    }
    foreach ($path in $files.Keys) {
        $section = $files[$path]
        if ($PSCmdlet.ShouldProcess($path, ('Write {0} app row(s)' -f $section.Count))) {
            if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -Path $directory -ItemType Directory -Force | Out-Null }
            if ($section.Count -gt 0) {
                $section | ForEach-Object { ConvertTo-AppTriageCsvSafeRow $_ } | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
            }
            else {
                # Export-Csv writes nothing for no input; keep a header-only file
                # so a stale list from an earlier run is not left behind.
                $header = '"Priority","App","Publisher","Versions","VersionCount","Platform","Devices","DevicesApproximate","PublisherRaw"'
                Set-Content -LiteralPath $path -Value $header -Encoding UTF8
            }
            Write-Information "Wrote: $path" -InformationAction Continue
        }
    }
    if ($PassThru) { return $rows }
}
