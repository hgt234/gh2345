#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
Offline Pester tests for ManagerDeviceExport. Invoke-MgGraphRequest is mocked
with a small fake tenant that returns real HttpResponseMessage objects, so the
request, paging, and $batch code paths run without network or sign-in.
All ids and names are obvious test fixtures.
#>
# The fake tenant must be reachable from inside the script under test, where
# $script: resolves to that script (dynamic scoping). It lives in one global
# table, $global:MdeFake, removed in AfterAll. Only PSAvoidGlobalVars is
# suppressed, and only in this test file.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Shared fake tenant for mocks; removed in AfterAll')]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'ManagerDeviceExport.Common.ps1')
    $script:scriptPath = Join-Path $PSScriptRoot 'Export-ManagerDeviceList.ps1'

    # Stubs so Mock has a command to replace when Microsoft.Graph is absent.
    # Their parameters exist only so Pester binds them inside mocks; the
    # bodies are empty by design, hence the narrow unused-parameter suppression.
    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        function global:Get-MgContext { }
    }
    if (-not (Get-Command Get-MgEnvironment -ErrorAction SilentlyContinue)) {
        function global:Get-MgEnvironment {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock signature stub')]
            param($Name)
        }
    }
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        function global:Invoke-MgGraphRequest {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock signature stub')]
            param($Method, $Uri, $Body, $ContentType, $OutputType, [switch] $SkipHttpErrorCheck)
        }
    }

    # PowerShell's $script: scope is dynamic: inside the mocked Graph call it
    # would resolve to the script under test, so the fake tenant lives in one
    # global table that AfterAll removes.
    $global:MdeFake = @{ Throttle = $false; Throttled = $false }
    $script:ids = @{
        Mgr   = '11111111-1111-1111-1111-111111111111'
        UserA = '22222222-2222-2222-2222-222222222222'
        UserB = '33333333-3333-3333-3333-333333333333'
        UserC = '44444444-4444-4444-4444-444444444444'
        Other = '55555555-5555-5555-5555-555555555555'
        EntA1 = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        EntA2 = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        EntC1 = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
        ObjA1 = 'a1a1a1a1-0000-0000-0000-000000000001'
        ObjC1 = 'c1c1c1c1-0000-0000-0000-000000000003'
    }
    $global:MdeFake.MgrId = $ids.Mgr

    function Get-FakeUser {
        param([string] $Id, [string] $Upn, [string] $Type = '#microsoft.graph.user')
        [ordered]@{ '@odata.type' = $Type; id = $Id; displayName = $Upn.Split('@')[0]; userPrincipalName = $Upn; accountEnabled = $true }
    }

    $global:MdeFake.DirectReports = @{
        $ids.Mgr   = @(
            (Get-FakeUser $ids.UserA 'usera@example.test')
            (Get-FakeUser $ids.UserB 'userb@example.test')
            (Get-FakeUser '66666666-6666-6666-6666-666666666666' 'contact@example.test' '#microsoft.graph.orgContact')
        )
        $ids.UserA = @((Get-FakeUser $ids.UserC 'userc@example.test'))
        # Cycle back to the manager must not loop or re-add the manager.
        $ids.UserC = @((Get-FakeUser $ids.Mgr 'mgr@example.test'))
        $ids.UserB = @()
    }

    $global:MdeFake.DevicePage1 = @(
        @{ id = 'intune-a1'; deviceName = 'PC-A1'; userId = $ids.UserA; azureADDeviceId = $ids.EntA1; operatingSystem = 'Windows'; osVersion = '10.0.26100'; managedDeviceOwnerType = 'company'; complianceState = 'compliant'; lastSyncDateTime = '2026-11-01T00:00:00Z'; serialNumber = 'SN-A1'; manufacturer = 'Example'; model = 'M1' }
        @{ id = 'intune-a2'; deviceName = 'PHONE-A2'; userId = $ids.UserA; azureADDeviceId = $ids.EntA2; operatingSystem = 'iOS'; osVersion = '18.0'; managedDeviceOwnerType = 'personal'; complianceState = 'compliant'; lastSyncDateTime = '2026-11-01T00:00:00Z'; serialNumber = 'SN-A2'; manufacturer = 'Example'; model = 'M2' }
    )
    $global:MdeFake.DevicePage2 = @(
        @{ id = 'intune-b1'; deviceName = '=PC-B1'; userId = $ids.UserB; azureADDeviceId = '00000000-0000-0000-0000-000000000000'; operatingSystem = 'Windows'; osVersion = '10.0.22631'; managedDeviceOwnerType = 'company'; complianceState = 'noncompliant'; lastSyncDateTime = '2026-11-02T00:00:00Z'; serialNumber = 'SN-B1'; manufacturer = 'Example'; model = 'M1' }
        @{ id = 'intune-c1'; deviceName = 'PC-C1'; userId = $ids.UserC; azureADDeviceId = $ids.EntC1; operatingSystem = 'Windows'; osVersion = '10.0.26100'; managedDeviceOwnerType = 'company'; complianceState = 'compliant'; lastSyncDateTime = '2026-11-03T00:00:00Z'; serialNumber = 'SN-C1'; manufacturer = 'Example'; model = 'M1' }
        @{ id = 'intune-x1'; deviceName = 'PC-X1'; userId = $ids.Other; azureADDeviceId = $ids.EntA1; operatingSystem = 'Windows'; osVersion = '10.0.26100'; managedDeviceOwnerType = 'company'; complianceState = 'compliant'; lastSyncDateTime = '2026-11-03T00:00:00Z'; serialNumber = 'SN-X1'; manufacturer = 'Example'; model = 'M1' }
    )
    $global:MdeFake.EntraObjects = @{
        $ids.EntA1 = @{ id = $ids.ObjA1; deviceId = $ids.EntA1; displayName = 'PC-A1' }
        $ids.EntC1 = @{ id = $ids.ObjC1; deviceId = $ids.EntC1; displayName = 'PC-C1' }
    }

    function Get-FakeResponse {
        param([int] $Status, $Object, [int] $RetryAfter = 0)
        $response = New-Object System.Net.Http.HttpResponseMessage ([System.Net.HttpStatusCode]$Status)
        if ($null -ne $Object) {
            $response.Content = New-Object System.Net.Http.StringContent ((ConvertTo-Json -InputObject $Object -Depth 10), [System.Text.Encoding]::UTF8, 'application/json')
        }
        if ($RetryAfter -gt 0) { $response.Headers.RetryAfter = New-Object System.Net.Http.Headers.RetryConditionHeaderValue ([TimeSpan]::FromSeconds($RetryAfter)) }
        return $response
    }

    function Get-FakeBatchItem {
        param($Request)
        $url = [string]$Request.url
        if ($url -match '^/users/([0-9a-f-]{36})/directReports') {
            return @{ id = $Request.id; status = 200; body = @{ value = @($global:MdeFake.DirectReports[$Matches[1]]) } }
        }
        if ($url -match "^/devices\(deviceId='([0-9a-f-]{36})'\)") {
            if ($global:MdeFake.EntraObjects.ContainsKey($Matches[1])) { return @{ id = $Request.id; status = 200; body = $global:MdeFake.EntraObjects[$Matches[1]] } }
            return @{ id = $Request.id; status = 404; body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } }
        }
        throw "Unhandled batch url in test: $url"
    }

    function Invoke-FakeGraph {
        param($Method, $Uri, $Body)
        if ($Method -eq 'GET' -and $Uri -match '/users/mgr%40example\.test\?') {
            return Get-FakeResponse 200 (Get-FakeUser $global:MdeFake.MgrId 'mgr@example.test')
        }
        if ($Method -eq 'GET' -and $Uri -match '/users/[^/?]+\?') {
            return Get-FakeResponse 404 @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } }
        }
        if ($Method -eq 'GET' -and $Uri -match '/deviceManagement/managedDevices\?page=2') {
            return Get-FakeResponse 200 @{ value = $global:MdeFake.DevicePage2 }
        }
        if ($Method -eq 'GET' -and $Uri -match '/deviceManagement/managedDevices\?') {
            return Get-FakeResponse 200 @{ value = $global:MdeFake.DevicePage1; '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?page=2' }
        }
        if ($Method -eq 'POST' -and $Uri -match '/\$batch$') {
            $requests = @(($Body | ConvertFrom-Json).requests)
            $responses = @(foreach ($request in $requests) {
                    if ($global:MdeFake.Throttle -and [string]$request.url -match '^/devices\(' -and -not $global:MdeFake.Throttled) {
                        $global:MdeFake.Throttled = $true
                        @{ id = $request.id; status = 429; headers = @{ 'Retry-After' = '7' }; body = @{} }
                        continue
                    }
                    Get-FakeBatchItem $request
                })
            return Get-FakeResponse 200 @{ responses = $responses }
        }
        throw "Unhandled Graph call in test: $Method $Uri"
    }
}

AfterAll {
    Remove-Variable -Name MdeFake -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-MdeDeviceRow' {
    BeforeAll {
        $root = [pscustomobject]@{ Id = $ids.Mgr; DisplayName = 'mgr'; UserPrincipalName = 'mgr@example.test' }
        $script:reports = @(
            [pscustomobject]@{ Id = $ids.UserA; DisplayName = 'usera'; UserPrincipalName = 'usera@example.test'; AccountEnabled = $true; ReportLevel = 1; DirectManagerUpn = 'mgr@example.test'; RootManager = $root }
            [pscustomobject]@{ Id = $ids.UserB; DisplayName = 'userb'; UserPrincipalName = 'userb@example.test'; AccountEnabled = $true; ReportLevel = 1; DirectManagerUpn = 'mgr@example.test'; RootManager = $root }
        )
        $script:index = @{ $ids.UserA = @($global:MdeFake.DevicePage1 | ForEach-Object { [pscustomobject]$_ }) }
        $script:entra = @{ $ids.EntA1 = [pscustomobject]@{ id = $ids.ObjA1 }; $ids.EntA2 = $null }
    }

    It 'assigns OK and NoEntraObject statuses' {
        $rows = Get-MdeDeviceRow -Reports $reports -DeviceIndex $index -EntraDevices $entra
        $rows.Count | Should -Be 2
        ($rows | Where-Object DeviceName -EQ 'PC-A1').Status | Should -Be 'OK'
        ($rows | Where-Object DeviceName -EQ 'PC-A1').EntraDeviceObjectId | Should -Be $ids.ObjA1
        ($rows | Where-Object DeviceName -EQ 'PHONE-A2').Status | Should -Be 'NoEntraObject'
    }

    It 'filters by operating system case-insensitively' {
        $rows = Get-MdeDeviceRow -Reports $reports -DeviceIndex $index -EntraDevices $entra -OperatingSystem 'windows'
        @($rows).Count | Should -Be 1
        $rows[0].DeviceName | Should -Be 'PC-A1'
    }

    It 'adds NoIntuneDevice rows only when asked' {
        @(Get-MdeDeviceRow -Reports $reports -DeviceIndex $index -EntraDevices $entra | Where-Object { $_.UserId -eq $ids.UserB }) | Should -BeNullOrEmpty
        $rows = Get-MdeDeviceRow -Reports $reports -DeviceIndex $index -EntraDevices $entra -IncludeUsersWithoutDevices
        ($rows | Where-Object UserId -EQ $ids.UserB).Status | Should -Be 'NoIntuneDevice'
    }
}

Describe 'Export-ManagerDeviceList.ps1' {
    BeforeEach {
        $global:MdeFake.Throttle = $false
        $global:MdeFake.Throttled = $false
        Mock Get-MgContext { [pscustomobject]@{ Account = 'admin@example.test'; TenantId = '00000000-0000-0000-0000-000000000000'; Environment = 'Global'; Scopes = @('User.Read.All', 'DeviceManagementManagedDevices.Read.All', 'Device.Read.All') } }
        Mock Invoke-MgGraphRequest { Invoke-FakeGraph -Method $Method -Uri $Uri -Body $Body }
        Mock Start-Sleep { }
        $script:outFile = Join-Path (Join-Path $TestDrive ('out-{0}' -f [guid]::NewGuid())) 'devices.csv'
    }

    It 'exports direct reports devices with correct statuses and skips contacts' {
        & $scriptPath -Manager 'mgr@example.test' -OutputPath $outFile -InformationAction SilentlyContinue
        $rows = @(Import-Csv -LiteralPath $outFile)
        $rows.Count | Should -Be 3
        ($rows | Where-Object DeviceName -EQ 'PC-A1').Status | Should -Be 'OK'
        ($rows | Where-Object DeviceName -EQ 'PC-A1').EntraDeviceObjectId | Should -Be $ids.ObjA1
        ($rows | Where-Object DeviceName -EQ 'PHONE-A2').Status | Should -Be 'NoEntraObject'
        ($rows | Where-Object SerialNumber -EQ 'SN-B1').Status | Should -Be 'NoEntraDeviceId'
        $rows.UserPrincipalName | Should -Not -Contain 'contact@example.test'
        $rows.UserPrincipalName | Should -Not -Contain 'userc@example.test'
        $rows.DeviceName | Should -Not -Contain 'PC-X1'
    }

    It 'neutralizes spreadsheet formulas in CSV cells' {
        & $scriptPath -Manager 'mgr@example.test' -OutputPath $outFile -InformationAction SilentlyContinue
        (Import-Csv -LiteralPath $outFile | Where-Object SerialNumber -EQ 'SN-B1').DeviceName | Should -Be "'=PC-B1"
    }

    It 'walks the reporting chain with -Recurse and stops on cycles' {
        $rows = & $scriptPath -Manager 'mgr@example.test' -Recurse -OutputPath $outFile -PassThru -InformationAction SilentlyContinue
        $c1 = $rows | Where-Object DeviceName -EQ 'PC-C1'
        $c1.ReportLevel | Should -Be 2
        $c1.ManagerUPN | Should -Be 'mgr@example.test'
        $c1.DirectManagerUPN | Should -Be 'usera@example.test'
        $rows.UserPrincipalName | Should -Not -Contain 'mgr@example.test'
    }

    It 'makes zero changes under -WhatIf but still performs the reads' {
        & $scriptPath -Manager 'mgr@example.test' -OutputPath $outFile -WhatIf -InformationAction SilentlyContinue
        Test-Path -LiteralPath (Split-Path $outFile -Parent) | Should -BeFalse
        Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Uri -match 'managedDevices' }
        Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -match '\$batch' }
    }

    It 'only ever sends GET and $batch requests' {
        & $scriptPath -Manager 'mgr@example.test' -Recurse -OutputPath $outFile -InformationAction SilentlyContinue
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { -not ($Method -eq 'GET' -or ($Method -eq 'POST' -and $Uri -match '/\$batch$')) }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and @(($Body | ConvertFrom-Json).requests | Where-Object method -NE 'GET').Count -gt 0
        }
    }

    It 'retries throttled batch sub-requests honoring Retry-After' {
        $global:MdeFake.Throttle = $true
        & $scriptPath -Manager 'mgr@example.test' -OutputPath $outFile -InformationAction SilentlyContinue -WarningAction SilentlyContinue
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
        (Import-Csv -LiteralPath $outFile | Where-Object DeviceName -EQ 'PC-A1').Status | Should -Be 'OK'
    }

    It 'stops when a manager is not found' {
        { & $scriptPath -Manager 'nobody@example.test' -OutputPath $outFile -InformationAction SilentlyContinue } | Should -Throw '*nobody@example.test*not found*'
        Test-Path -LiteralPath $outFile | Should -BeFalse
    }

    It 'stops when there is no Graph session' {
        Mock Get-MgContext { $null }
        { & $scriptPath -Manager 'mgr@example.test' -OutputPath $outFile } | Should -Throw '*Connect-MgGraph*'
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
    }
}
