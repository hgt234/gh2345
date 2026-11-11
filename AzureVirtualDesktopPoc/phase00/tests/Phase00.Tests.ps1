#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0'; MaximumVersion = '5.99.99' }

BeforeAll {
    $script:deploy = Join-Path (Split-Path -Parent $PSScriptRoot) 'Deploy-AvdVm.ps1'
    $script:request = @{
        VmName = 'AVD-TEST-01'
        ResourceGroupName = 'rg-vms'
        HostPoolName = 'vdpool-example'
        HostPoolResourceGroupName = 'rg-avd'
        SubnetId = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-a/subnets/snet-a'
        InformationAction = 'SilentlyContinue'
    }
    $script:capturePath = Join-Path $TestDrive 'parameters.json'
    function az { param([Parameter(ValueFromRemainingArguments)]$Items) $null = $Items }
    function Test-AzCall { param($Items, [string]$Pattern) ($Items -join ' ') -match $Pattern }
}

Describe 'Deploy-AvdVm' {
    BeforeEach {
        Remove-Item -LiteralPath $script:capturePath -ErrorAction SilentlyContinue
        $tokenExpiry = [DateTime]::UtcNow.AddHours(2).ToString('o')
        $capture = $script:capturePath
        Mock Get-Command { [pscustomobject]@{ Name = 'az' } } -ParameterFilter { $Name -eq 'az' }
        Mock az {
            $global:LASTEXITCODE = 0
            $line = $Items -join ' '
            if ($line -match 'account show') { return '{"id":"11111111-1111-1111-1111-111111111111","user":{"name":"tech@example.test"}}' }
            if ($line -match 'vm list') { return '[]' }
            if ($line -match 'lock list') { return '[{"level":"CanNotDelete","id":"/lock"}]' }
            if ($line -match 'retrieveRegistrationToken') { return "{`"token`":`"fixture-token`",`"expirationTime`":`"$tokenExpiry`"}" }
            if ($line -match '--method GET') { return '{"properties":{"customRdpProperty":"targetisaadjoined:i:1;"}}' }
            if ($line -match 'what-if') {
                $file = ($Items | Where-Object { "$_" -like '@*' } | Select-Object -First 1).ToString().TrimStart('@')
                [IO.File]::WriteAllText($capture, "$file`n" + [IO.File]::ReadAllText($file))
                return '{"changes":[{"changeType":"Create","resourceId":"/vm"}]}'
            }
            if ($line -match 'group create') {
                $file = ($Items | Where-Object { "$_" -like '@*' } | Select-Object -First 1).ToString().TrimStart('@')
                [IO.File]::WriteAllText($capture, "$file`n" + [IO.File]::ReadAllText($file))
                return '{"properties":{"outputs":{"vmId":{"value":"/fixture/vm"}}}}'
            }
        }
    }

    Context 'WhatIf' {
        It 'creates nothing and reports the planned changes' {
            $result = & $script:deploy @script:request -WhatIf
            $result.State | Should -Be 'NotDeployed'
            $result.Changes | Should -Contain 'Create: /vm'
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { Test-AzCall $Items 'what-if' }
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { Test-AzCall $Items 'group create|--method PATCH|retrieveRegistrationToken' }
        }

        It 'runs the what-if in Incremental mode with a placeholder token' {
            & $script:deploy @script:request -WhatIf | Out-Null
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { Test-AzCall $Items 'what-if .*--mode Incremental' }
            $json = Get-Content -LiteralPath $script:capturePath | Select-Object -Skip 1 | Out-String | ConvertFrom-Json
            $json.parameters.registrationToken.value | Should -Be 'whatif-placeholder-token'
        }

        It 'does not renew an expired token' {
            Mock az { $global:LASTEXITCODE = 0; '{"token":"","expirationTime":null}' } -ParameterFilter { Test-AzCall $Items 'retrieveRegistrationToken' }
            (& $script:deploy @script:request -WhatIf).State | Should -Be 'NotDeployed'
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { Test-AzCall $Items '--method PATCH' }
        }

        It 'still removes the parameter file' {
            & $script:deploy @script:request -WhatIf | Out-Null
            $file = (Get-Content -LiteralPath $script:capturePath -TotalCount 1)
            Test-Path -LiteralPath $file | Should -BeFalse
        }
    }

    Context 'Deployment' {
        It 'deploys and returns the VM ID' {
            $result = & $script:deploy @script:request
            $result.State | Should -Be 'Deployed'
            $result.VmId | Should -Be '/fixture/vm'
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { Test-AzCall $Items 'group create .*--mode Incremental' }
        }

        It 'uses the Marketplace image and the real token by default' {
            & $script:deploy @script:request | Out-Null
            $json = Get-Content -LiteralPath $script:capturePath | Select-Object -Skip 1 | Out-String | ConvertFrom-Json
            $json.parameters.imageSourceType.value | Should -Be 'Marketplace'
            $json.parameters.registrationToken.value | Should -Be 'fixture-token'
            $json.parameters.subnetId.value | Should -Be $script:request.SubnetId
        }

        It 'uses the gallery image when one is supplied' {
            & $script:deploy @script:request -GalleryImageVersionId '/fixture/version' | Out-Null
            $json = Get-Content -LiteralPath $script:capturePath | Select-Object -Skip 1 | Out-String | ConvertFrom-Json
            $json.parameters.imageSourceType.value | Should -Be 'Gallery'
        }

        It 'renews a token that is close to expiry, then deploys' {
            $near = [DateTime]::UtcNow.AddMinutes(5).ToString('o')
            $later = [DateTime]::UtcNow.AddHours(4).ToString('o')
            $state = Join-Path $TestDrive 'renewed.txt'
            Remove-Item -LiteralPath $state -ErrorAction SilentlyContinue
            Mock az {
                $global:LASTEXITCODE = 0
                if (Test-Path -LiteralPath $state) { "{`"token`":`"new-token`",`"expirationTime`":`"$later`"}" } else { "{`"token`":`"old-token`",`"expirationTime`":`"$near`"}" }
            } -ParameterFilter { Test-AzCall $Items 'retrieveRegistrationToken' }
            Mock az { $global:LASTEXITCODE = 0; [IO.File]::WriteAllText($state, 'done') } -ParameterFilter { Test-AzCall $Items '--method PATCH' }
            (& $script:deploy @script:request).State | Should -Be 'Deployed'
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { Test-AzCall $Items '--method PATCH' }
        }
    }

    Context 'Delete lock check' {
        It 'warns when the resource group has no delete lock' {
            Mock az { $global:LASTEXITCODE = 0; '[]' } -ParameterFilter { Test-AzCall $Items 'lock list' }
            & $script:deploy @script:request -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
            ($warnings -join ' ') | Should -BeLike '*no CanNotDelete lock*'
        }

        It 'does not warn when a CanNotDelete lock exists' {
            & $script:deploy @script:request -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
            ($warnings -join ' ') | Should -Not -BeLike '*CanNotDelete*'
        }

        It 'only reads locks and never creates or removes one' {
            & $script:deploy @script:request | Out-Null
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { Test-AzCall $Items 'lock (create|delete)' }
        }
    }

    Context 'Refusals' {
        It 'refuses a VM that already exists' {
            Mock az { $global:LASTEXITCODE = 0; '[{"name":"avd-test-01"}]' } -ParameterFilter { Test-AzCall $Items 'vm list' }
            { & $script:deploy @script:request } | Should -Throw '*already exists*'
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { Test-AzCall $Items 'what-if|group create' }
        }

        It 'refuses a what-if that deletes a resource and cleans up' {
            Mock az {
                $global:LASTEXITCODE = 0
                $file = ($Items | Where-Object { "$_" -like '@*' } | Select-Object -First 1).ToString().TrimStart('@')
                [IO.File]::WriteAllText($capture, "$file`n")
                '{"changes":[{"changeType":"Delete","resourceId":"/nic"}]}'
            } -ParameterFilter { Test-AzCall $Items 'what-if' }
            { & $script:deploy @script:request } | Should -Throw '*change existing resources*'
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { Test-AzCall $Items 'group create' }
            Test-Path -LiteralPath (Get-Content -LiteralPath $capture -TotalCount 1) | Should -BeFalse
        }

        It 'refuses a what-if with <ChangeType> before any write' -TestCases @(
            @{ ChangeType = 'Modify' }
            @{ ChangeType = 'Deploy' }
            @{ ChangeType = 'Unsupported' }
            @{ ChangeType = 'SomethingNew' }
        ) {
            $body = '{"changes":[{"changeType":"Create","resourceId":"/vm"},{"changeType":"' + $ChangeType + '","resourceId":"/nic"}]}'
            Mock az { $global:LASTEXITCODE = 0; $body } -ParameterFilter { Test-AzCall $Items 'what-if' }
            { & $script:deploy @script:request } | Should -Throw "*$($ChangeType): /nic*"
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { Test-AzCall $Items 'group create|--method PATCH|retrieveRegistrationToken' }
        }

        It 'allows Ignore entries for other resources in the group' {
            Mock az { $global:LASTEXITCODE = 0; '{"changes":[{"changeType":"Create","resourceId":"/vm"},{"changeType":"Ignore","resourceId":"/other-vm"}]}' } -ParameterFilter { Test-AzCall $Items 'what-if' }
            (& $script:deploy @script:request).State | Should -Be 'Deployed'
        }

        It 'refuses an empty what-if result' {
            Mock az { $global:LASTEXITCODE = 0; '{}' } -ParameterFilter { Test-AzCall $Items 'what-if' }
            { & $script:deploy @script:request } | Should -Throw '*what-if returned no result*'
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { Test-AzCall $Items 'group create' }
        }

        It 'fails when Azure CLI fails' {
            Mock az { $global:LASTEXITCODE = 1 } -ParameterFilter { Test-AzCall $Items '--method GET' }
            { & $script:deploy @script:request } | Should -Throw '*Azure CLI failed*'
        }

        It 'rejects <Name>' -TestCases @(
            @{ Name = 'an all-digit style name'; Field = 'VmName'; Value = '1234' }
            @{ Name = 'a name over 15 characters'; Field = 'VmName'; Value = 'AVD-THIS-IS-TOO-LONG' }
            @{ Name = 'a value that is not a subnet ID'; Field = 'SubnetId'; Value = 'snet-a' }
        ) {
            $bad = $script:request.Clone()
            $bad[$Field] = $Value
            { & $script:deploy @bad -WhatIf } | Should -Throw
            Should -Invoke az -Times 0 -Exactly
        }
    }
}
