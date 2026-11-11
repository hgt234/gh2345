#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
Offline Pester tests for AppPackagingTriage. Fixtures are small fake
EndpointExplorer snapshots written to TestDrive. No network, no tenant.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'AppPackagingTriage.Common.ps1')
    $script:scriptPath = Join-Path $PSScriptRoot 'Export-AppPackagingTriage.ps1'

    function Get-FakeRecord {
        param([string] $Name, [string] $Publisher, [string] $Version, [int] $DeviceCount, [string] $Platform = 'windows')
        @{ id = ''; name = $Name; publisher = $Publisher; version = $Version; platform = $Platform; deviceCount = $DeviceCount; sizeInByte = 0 }
    }

    function Get-FakeSnapshot {
        param([bool] $IncludeDeviceApps = $true)
        $records = @(
            (Get-FakeRecord '7-Zip' 'Igor Pavlov' '19.00' 1)                                                                     # 0
            (Get-FakeRecord '7-Zip' 'Igor Pavlov' '23.01' 2)                                                                     # 1
            (Get-FakeRecord 'Microsoft Teams' 'Microsoft Corporation' '24.1.0' 1)                                                # 2
            (Get-FakeRecord 'Microsoft Teams' 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' '25.2.0' 2) # 3
            (Get-FakeRecord 'Spotify Music' 'CN=Spotify AB, O=Spotify AB, L=Stockholm, C=SE' '1.2.3' 1)                          # 4
            (Get-FakeRecord 'Realtek Audio Console' 'CN=83564403-0B26-46B8-9D84-040F43691D31' '1.0.0' 3)                         # 5
            (Get-FakeRecord 'Visual C++ Runtime' 'Microsoft Corporations' '14.0' 3)                                              # 6
            (Get-FakeRecord '=HYPERLINK("x")' 'Example Corp' 'beta' 1)                                                           # 7
            (Get-FakeRecord 'Mac Only App' 'Example Corp' '2.0' 5 'macOS')                                                       # 8
        )
        # dev-1 has two 7-Zip versions and both Teams publisher forms: it must count once per app.
        $devices = @(
            @{ intuneDeviceId = 'dev-1'; appRecordIndexes = @(0, 1, 2, 3, 5, 6) }
            @{ intuneDeviceId = 'dev-2'; appRecordIndexes = @(1, 3, 4, 5, 6, 7) }
            @{ intuneDeviceId = 'dev-3'; appRecordIndexes = @(5, 6, 8) }
        )
        @{
            schemaVersion = 2; generatedAt = '2026-10-14T00:00:00Z'
            source = @{ windowsOnly = $false; includeDeviceApps = $IncludeDeviceApps }
            thresholds = @{}; warnings = @(); apps = @()
            devices = $devices; appRecords = $records
        }
    }

    function Write-FakeSnapshot {
        param([string] $Path, $Snapshot = (Get-FakeSnapshot))
        [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Snapshot -Depth 10))
        return $Path
    }

    function Get-FakeRow {
        param([switch] $AllPlatforms, [bool] $IncludeDeviceApps = $true)
        $path = Write-FakeSnapshot -Path (Join-Path $TestDrive ("rows-{0}.json" -f [guid]::NewGuid())) -Snapshot (Get-FakeSnapshot -IncludeDeviceApps $IncludeDeviceApps)
        return @(Get-AppTriageRow -Snapshot (Import-AppTriageSnapshot -Path $path) -AllPlatforms:$AllPlatforms)
    }
}

Describe 'ConvertTo-AppTriagePublisher' {
    It 'returns <Expected> for <Publisher>' -ForEach @(
        @{ Publisher = 'Igor Pavlov'; Expected = 'Igor Pavlov' }
        @{ Publisher = '  Mozilla  '; Expected = 'Mozilla' }
        @{ Publisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'; Expected = 'Microsoft Corporation' }
        @{ Publisher = 'CN=Microsoft Windows, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'; Expected = 'Microsoft Corporation' }
        @{ Publisher = 'CN=Microsoft Windows'; Expected = 'Microsoft Corporation' }
        @{ Publisher = 'CN=Spotify AB, O=Spotify AB, L=Stockholm, C=SE'; Expected = 'Spotify AB' }
        @{ Publisher = 'CN=Example Signer, O="Contoso, Ltd.", C=US'; Expected = 'Contoso, Ltd.' }
        @{ Publisher = 'CN=Fabrikam Tools'; Expected = 'Fabrikam Tools' }
        @{ Publisher = 'CN=83564403-0B26-46B8-9D84-040F43691D31'; Expected = 'Unknown (Store-signed)' }
        @{ Publisher = 'CN=11111111-1111-1111-1111-111111111111, O=Example Corp'; Expected = 'Example Corp' }
        @{ Publisher = ''; Expected = '' }
    ) {
        ConvertTo-AppTriagePublisher $Publisher | Should -BeExactly $Expected
    }

    It 'returns an empty string for $null' {
        ConvertTo-AppTriagePublisher $null | Should -BeExactly ''
    }
}

Describe 'Test-AppTriageMicrosoftPublisher' {
    It 'is <Expected> for <Publisher>' -ForEach @(
        @{ Publisher = 'Microsoft Corporation'; Expected = $true }
        @{ Publisher = 'Microsoft Corporations'; Expected = $true }
        @{ Publisher = 'Microsoft'; Expected = $true }
        @{ Publisher = 'Microsoft Corp.'; Expected = $true }
        @{ Publisher = 'MicrosoftXYZ Ltd'; Expected = $false }
        @{ Publisher = 'Not Microsoft'; Expected = $false }
        @{ Publisher = ''; Expected = $false }
    ) {
        Test-AppTriageMicrosoftPublisher $Publisher | Should -Be $Expected
    }
}

Describe 'Get-AppTriageRow' {
    It 'merges both Microsoft publisher forms of an app into one row' {
        $teams = @(Get-FakeRow | Where-Object App -EQ 'Microsoft Teams')
        $teams.Count | Should -Be 1
        $teams[0].Publisher | Should -BeExactly 'Microsoft Corporation'
        $teams[0].Section | Should -Be 'Microsoft'
        $teams[0].Versions | Should -BeExactly '25.2.0; 24.1.0'
        $teams[0].PublisherRaw | Should -BeExactly 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
    }

    It 'counts distinct devices when the snapshot has per-device apps' {
        $rows = Get-FakeRow
        ($rows | Where-Object App -EQ '7-Zip').Devices | Should -Be 2
        ($rows | Where-Object App -EQ 'Microsoft Teams').Devices | Should -Be 2
        @($rows | Where-Object DevicesApproximate).Count | Should -Be 0
    }

    It 'sums per-version counts and flags them approximate without per-device apps' {
        $rows = Get-FakeRow -IncludeDeviceApps $false
        $zip = $rows | Where-Object App -EQ '7-Zip'
        $zip.Devices | Should -Be 3
        $zip.DevicesApproximate | Should -BeTrue
    }

    It 'keeps Windows apps only by default' {
        @(Get-FakeRow | Where-Object Platform -NE 'windows').Count | Should -Be 0
        @(Get-FakeRow -AllPlatforms | Where-Object App -EQ 'Mac Only App').Count | Should -Be 1
    }

    It 'splits sections and ranks each by devices, then name' {
        $rows = Get-FakeRow
        $third = @($rows | Where-Object Section -EQ 'ThirdParty')
        $third.App | Should -Be @('Realtek Audio Console', '7-Zip', '=HYPERLINK("x")', 'Spotify Music')
        $third.Priority | Should -Be @(1, 2, 3, 4)
        $ms = @($rows | Where-Object Section -EQ 'Microsoft')
        $ms.App | Should -Be @('Visual C++ Runtime', 'Microsoft Teams')
        $ms.Priority | Should -Be @(1, 2)
    }

    It 'treats a GUID-only certificate publisher as third-party' {
        $row = Get-FakeRow | Where-Object App -EQ 'Realtek Audio Console'
        $row.Publisher | Should -BeExactly 'Unknown (Store-signed)'
        $row.Section | Should -Be 'ThirdParty'
    }

    It 'orders versions newest first' {
        (Get-FakeRow | Where-Object App -EQ '7-Zip').Versions | Should -BeExactly '23.01; 19.00'
    }
}

Describe 'Import-AppTriageSnapshot' {
    It 'rejects <Case>' -ForEach @(
        @{ Case = 'invalid JSON'; Content = '{ not json'; Message = '*not valid JSON*' }
        @{ Case = 'an empty file'; Content = ' '; Message = '*is empty*' }
        @{ Case = 'a JSON array'; Content = '[1,2]'; Message = '*not a JSON object*' }
        @{ Case = 'a missing appRecords'; Content = '{"schemaVersion":2,"generatedAt":"x","source":{"includeDeviceApps":true},"devices":[]}'; Message = "*Missing 'appRecords'*" }
        @{ Case = 'another schema version'; Content = '{"schemaVersion":9,"generatedAt":"x","source":{"includeDeviceApps":true},"devices":[],"appRecords":[]}'; Message = '*schemaVersion*' }
        @{ Case = 'a record without publisher'; Content = '{"schemaVersion":2,"generatedAt":"x","source":{"includeDeviceApps":true},"devices":[],"appRecords":[{"name":"a","version":"1","platform":"windows","deviceCount":1}]}'; Message = '*missing: publisher*' }
    ) {
        $path = Join-Path $TestDrive 'bad.json'
        [IO.File]::WriteAllText($path, $Content)
        { Import-AppTriageSnapshot -Path $path } | Should -Throw $Message
    }
}

Describe 'Export-AppPackagingTriage.ps1' {
    BeforeEach {
        $script:snapshotPath = Write-FakeSnapshot -Path (Join-Path $TestDrive 'EndpointInventory.json')
        $script:outDir = Join-Path $TestDrive ('out-{0}' -f [guid]::NewGuid())
    }

    It 'writes nothing with -WhatIf' {
        & $script:scriptPath -SnapshotPath $script:snapshotPath -OutputDirectory $script:outDir -WhatIf 6>$null
        Test-Path -LiteralPath $script:outDir | Should -BeFalse
    }

    It 'writes both CSVs with the expected columns and order' {
        & $script:scriptPath -SnapshotPath $script:snapshotPath -OutputDirectory $script:outDir 6>$null
        $third = @(Import-Csv -LiteralPath (Join-Path $script:outDir 'ThirdPartyApps.csv'))
        $ms = @(Import-Csv -LiteralPath (Join-Path $script:outDir 'MicrosoftApps.csv'))
        $third[0].PSObject.Properties.Name | Should -Be @('Priority', 'App', 'Publisher', 'Versions', 'VersionCount', 'Platform', 'Devices', 'DevicesApproximate', 'PublisherRaw')
        $third.App | Should -Contain 'Spotify Music'
        $third.App | Should -Not -Contain 'Microsoft Teams'
        $ms.App | Should -Be @('Visual C++ Runtime', 'Microsoft Teams')
    }

    It 'guards formula-like cells' {
        & $script:scriptPath -SnapshotPath $script:snapshotPath -OutputDirectory $script:outDir 6>$null
        $third = @(Import-Csv -LiteralPath (Join-Path $script:outDir 'ThirdPartyApps.csv'))
        $third.App | Should -Contain "'=HYPERLINK(""x"")"
    }

    It 'returns rows with -PassThru and gives the same files on a second run' {
        $rows = @(& $script:scriptPath -SnapshotPath $script:snapshotPath -OutputDirectory $script:outDir -PassThru 6>$null)
        $rows.Count | Should -Be 6
        $first = Get-Content -LiteralPath (Join-Path $script:outDir 'ThirdPartyApps.csv') -Raw
        & $script:scriptPath -SnapshotPath $script:snapshotPath -OutputDirectory $script:outDir 6>$null
        Get-Content -LiteralPath (Join-Path $script:outDir 'ThirdPartyApps.csv') -Raw | Should -BeExactly $first
    }

    It 'writes a header-only file for an empty section' {
        $snapshot = Get-FakeSnapshot
        $snapshot.appRecords = @((Get-FakeRecord '7-Zip' 'Igor Pavlov' '23.01' 1))
        $snapshot.devices = @(@{ intuneDeviceId = 'dev-1'; appRecordIndexes = @(0) })
        $path = Write-FakeSnapshot -Path (Join-Path $TestDrive 'only-third.json') -Snapshot $snapshot
        & $script:scriptPath -SnapshotPath $path -OutputDirectory $script:outDir 6>$null
        $lines = @(Get-Content -LiteralPath (Join-Path $script:outDir 'MicrosoftApps.csv'))
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match '^"Priority","App"'
    }

    It 'fails clearly when the snapshot is missing' {
        { & $script:scriptPath -SnapshotPath (Join-Path $TestDrive 'nope.json') -OutputDirectory $script:outDir 6>$null } | Should -Throw '*not found*'
    }
}
