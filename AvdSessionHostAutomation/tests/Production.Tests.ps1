#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0'; MaximumVersion = '5.99.99' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptsRoot = Join-Path $script:repoRoot 'scripts'
    $script:validator = Join-Path $script:scriptsRoot 'Test-AvdProvisionRequest.ps1'
    $script:deployScript = Join-Path $script:scriptsRoot 'New-AvdSessionHost.ps1'
    $script:readinessScript = Join-Path $script:scriptsRoot 'Wait-AvdReadiness.ps1'
    $script:assignScript = Join-Path $script:scriptsRoot 'Set-AvdPersonalDesktopAssignment.ps1'
    $script:groupScript = Join-Path $script:scriptsRoot 'Add-AvdUserToAccessGroup.ps1'
    $script:drainScript = Join-Path $script:scriptsRoot 'Set-AvdDrainMode.ps1'
    $script:serviceNowScript = Join-Path $script:scriptsRoot 'Update-ServiceNowRitm.ps1'
    $script:pipelinePath = Join-Path $script:repoRoot 'pipelines/azure-pipelines-avd-provision.yml'
    $script:sessionHostBicep = Join-Path $script:repoRoot 'infra/session-host.bicep'
    $script:accessBicep = Join-Path $script:repoRoot 'infra/access.bicep'

    # The deployment and readiness scripts shell out to the Azure CLI. This
    # stand-in lets Pester mock it; the mocks dispatch on the argument text.
    function az { }
}

Describe 'Test-AvdProvisionRequest' {
    It 'derives the host name, preserves zeros, and normalizes' {
        $output = & $script:validator -RitmNumber ' ritm0012345 ' -RequestedForUpn 'User@Contoso.com'
        $output | Should -Contain '##vso[task.setvariable variable=ritmNumber;isOutput=true]RITM0012345'
        $output | Should -Contain '##vso[task.setvariable variable=hostName;isOutput=true]AVD0012345'
        $output | Should -Contain '##vso[task.setvariable variable=requestedForUpn;isOutput=true]user@contoso.com'
        $output | Should -Contain '##vso[task.setvariable variable=serviceNowEnabled;isOutput=true]false'
    }

    It 'enables ServiceNow callbacks only when a sys_id is supplied' {
        $output = & $script:validator -RitmNumber 'RITM0012345' -RequestedForUpn 'user@contoso.com' `
            -RitmSysId '0123456789ABCDEF0123456789abcdef' -RequestedHostName 'AVD0012345'
        $output | Should -Contain '##vso[task.setvariable variable=ritmSysId;isOutput=true]0123456789abcdef0123456789abcdef'
        $output | Should -Contain '##vso[task.setvariable variable=serviceNowEnabled;isOutput=true]true'
    }

    It 'rejects a ServiceNow host name that does not match the RITM' {
        { & $script:validator -RitmNumber 'RITM0012345' -RequestedForUpn 'user@contoso.com' -RequestedHostName 'AVD9999999' } |
            Should -Throw '*requires the exact host name*'
    }

    It 'rejects <Name>' -TestCases @(
        @{ Name = 'a non-RITM value'; Arguments = @{ RitmNumber = 'REQ0012345'; RequestedForUpn = 'user@contoso.com' } }
        @{ Name = '13 digits'; Arguments = @{ RitmNumber = 'RITM1234567890123'; RequestedForUpn = 'user@contoso.com' } }
        @{ Name = 'an embedded command'; Arguments = @{ RitmNumber = "RITM1'; Remove-Item x; '"; RequestedForUpn = 'user@contoso.com' } }
        @{ Name = 'a trailing logging command'; Arguments = @{ RitmNumber = 'RITM1'; RequestedForUpn = "user@contoso.com`n##vso[task.setvariable variable=x]y" } }
        @{ Name = 'a macro'; Arguments = @{ RitmNumber = 'RITM1'; RequestedForUpn = '$(System.AccessToken)@contoso.com' } }
        @{ Name = 'an apostrophe'; Arguments = @{ RitmNumber = 'RITM1'; RequestedForUpn = "o'neil@contoso.com" } }
        @{ Name = 'no domain'; Arguments = @{ RitmNumber = 'RITM1'; RequestedForUpn = 'jsmith' } }
        @{ Name = 'a short sys_id'; Arguments = @{ RitmNumber = 'RITM1'; RequestedForUpn = 'user@contoso.com'; RitmSysId = 'abc123' } }
        @{ Name = 'a non-hex sys_id'; Arguments = @{ RitmNumber = 'RITM1'; RequestedForUpn = 'user@contoso.com'; RitmSysId = 'zzzz6789abcdef0123456789abcdefzz' } }
    ) {
        { & $script:validator @Arguments } | Should -Throw
    }

    It 'agrees with technician Start-AvdBuild on the input patterns' {
        $starterText = Get-Content -LiteralPath (Join-Path $script:repoRoot 'technician/Start-AvdBuild.ps1') -Raw
        $validatorText = Get-Content -LiteralPath $script:validator -Raw
        foreach ($pattern in @("'\ARITM(?<digits>[0-9]{1,12})\z'", "'\A[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\z'")) {
            $starterText.Contains($pattern) | Should -BeTrue
            $validatorText.Contains($pattern) | Should -BeTrue
        }
    }
}

Describe 'New-AvdSessionHost' {
    BeforeEach {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'account show*' { '{"id":"sub-1","tenantId":"tenant-1"}' }
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","userPrincipalName":"user@contoso.com","accountEnabled":true}' }
                'vm list*' { '[]' }
                'rest --method POST --url *retrieveRegistrationToken*' { '{"token":"fixture-token","expirationTime":"2099-01-01T00:00:00Z"}' }
                'deployment group what-if*' { '{"changes":[]}' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        $script:deployArguments = @{
            SubscriptionId = 'sub-1'
            TenantId = 'tenant-1'
            ResourceGroupName = 'rg-hosts'
            PlatformResourceGroupName = 'rg-avd'
            HostPoolName = 'vdpool-prod'
            SubnetId = '/subscriptions/sub-1/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet'
            VmName = 'AVD0012345'
            RitmNumber = 'RITM0012345'
            RequestedForUpn = 'user@contoso.com'
            TemplateFile = $script:sessionHostBicep
            AvdDscConfigurationUri = 'https://example.test/dsc.zip'
            GalleryImageVersionId = '/subscriptions/sub-1/providers/Microsoft.Compute/galleries/g/images/i/versions/1.0.0'
        }
    }

    Context 'WhatIf' {
        It 'runs the what-if but never deploys or patches the host pool' {
            $output = & $script:deployScript @script:deployArguments -WhatIf *>&1 | Out-String
            $output | Should -BeLike '*No deployment was performed*'
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like 'deployment group what-if*' }
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'deployment group create*' }
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
        }

        # Regression: a local run printed the real registration token, because
        # the ##vso setsecret line only masks anything inside Azure DevOps.
        It 'never prints the registration token outside Azure DevOps' {
            $previous = $env:TF_BUILD
            try {
                $env:TF_BUILD = $null
                $output = & $script:deployScript @script:deployArguments -WhatIf *>&1 | Out-String
                $output | Should -Not -BeLike '*fixture-token*'
            }
            finally { $env:TF_BUILD = $previous }
        }

        It 'masks the registration token on an Azure DevOps agent' {
            $previous = $env:TF_BUILD
            try {
                $env:TF_BUILD = 'True'
                $output = & $script:deployScript @script:deployArguments -WhatIf *>&1 | Out-String
                $output | Should -BeLike '*##vso`[task.setsecret`]fixture-token*'
            }
            finally { $env:TF_BUILD = $previous }
        }

        It 'does not renew the registration token' {
            Mock az {
                $global:LASTEXITCODE = 0
                $command = $args -join ' '
                switch -Wildcard ($command) {
                    'account show*' { '{"id":"sub-1","tenantId":"tenant-1"}' }
                    'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","userPrincipalName":"user@contoso.com","accountEnabled":true}' }
                    'vm list*' { '[]' }
                    'rest --method POST --url *retrieveRegistrationToken*' { '{"token":"stale","expirationTime":"2000-01-01T00:00:00Z"}' }
                    'deployment group what-if*' { '{"changes":[]}' }
                    default { throw "Unexpected az call in test: az $command" }
                }
            }
            & $script:deployScript @script:deployArguments -WhatIf *>&1 | Out-Null
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
        }

        # Regression: -WhatIf once also skipped writing the temporary parameter
        # file, so the real ARM what-if failed with "Unable to parse parameter".
        It 'writes the parameter file the what-if reads, writes the report, and then deletes the file' {
            # The mock records what it saw in a TestDrive file: variables it
            # sets are not visible to the test body. -WhatIf:$false is needed
            # because the mock runs inside the script's -WhatIf scope.
            $capture = Join-Path $TestDrive 'what-if-capture.json'
            Mock az {
                $global:LASTEXITCODE = 0
                $command = $args -join ' '
                switch -Wildcard ($command) {
                    'account show*' { '{"id":"sub-1","tenantId":"tenant-1"}' }
                    'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","userPrincipalName":"user@contoso.com","accountEnabled":true}' }
                    'vm list*' { '[]' }
                    'rest --method POST --url *retrieveRegistrationToken*' { '{"token":"fixture-token","expirationTime":"2099-01-01T00:00:00Z"}' }
                    'deployment group what-if*' {
                        $path = ([string]($args | Where-Object { "$_" -like '@*' } | Select-Object -First 1)).Substring(1)
                        $vmName = if (Test-Path -LiteralPath $path) { [string](Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).parameters.vmName.value } else { '' }
                        @{ path = $path; vmName = $vmName } | ConvertTo-Json |
                            Set-Content -LiteralPath (Join-Path $TestDrive 'what-if-capture.json') -WhatIf:$false
                        '{"changes":[]}'
                    }
                    default { throw "Unexpected az call in test: az $command" }
                }
            }
            $report = Join-Path $TestDrive 'out/session-host-what-if.json'
            & $script:deployScript @script:deployArguments -WhatIfReportPath $report -WhatIf *>&1 | Out-Null
            $seen = Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
            $seen.vmName | Should -BeExactly 'AVD0012345'
            Test-Path -LiteralPath $report | Should -BeTrue
            Test-Path -LiteralPath $seen.path | Should -BeFalse
        }
    }

    Context 'OS disk' {
        BeforeEach {
            # One stateful mock for every disk test. The disk's tier lives in
            # a TestDrive file so a PATCH can change what the next GET sees;
            # tier-calls.txt records each disk call for the assertions.
            Set-Content -LiteralPath (Join-Path $TestDrive 'tier.txt') -Value 'P15'
            Set-Content -LiteralPath (Join-Path $TestDrive 'vm-list.json') -Value '[]'
            Mock Start-Sleep { }
            Mock az {
                $global:LASTEXITCODE = 0
                $command = $args -join ' '
                switch -Wildcard ($command) {
                    'account show*' { '{"id":"sub-1","tenantId":"tenant-1"}' }
                    'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","userPrincipalName":"user@contoso.com","accountEnabled":true}' }
                    'vm list*' { Get-Content -LiteralPath (Join-Path $TestDrive 'vm-list.json') -Raw }
                    'rest --method POST --url *retrieveRegistrationToken*' { '{"token":"fixture-token","expirationTime":"2099-01-01T00:00:00Z"}' }
                    'deployment group what-if*' {
                        $path = ([string]($args | Where-Object { "$_" -like '@*' } | Select-Object -First 1)).Substring(1)
                        Copy-Item -LiteralPath $path -Destination (Join-Path $TestDrive 'parameters.json') -WhatIf:$false
                        '{"changes":[]}'
                    }
                    'deployment group create*' { '{"properties":{"outputs":{"vmId":{"value":"/vm"},"osDiskName":{"value":"avd0012345-osdisk"}}}}' }
                    'rest --method GET --url https://management.azure.com/*/disks/avd0012345-osdisk*' {
                        $tier = (Get-Content -LiteralPath (Join-Path $TestDrive 'tier.txt') -Raw).Trim()
                        "{`"properties`":{`"tier`":`"$tier`"}}"
                    }
                    'rest --method PATCH --url https://management.azure.com/*/disks/avd0012345-osdisk*' {
                        $bodyArgument = [string]$args[([array]::IndexOf($args, '--body')) + 1]
                        $body = Get-Content -LiteralPath $bodyArgument.Substring(1) -Raw | ConvertFrom-Json
                        Set-Content -LiteralPath (Join-Path $TestDrive 'tier.txt') -Value $body.properties.tier -WhatIf:$false
                        Add-Content -LiteralPath (Join-Path $TestDrive 'tier-calls.txt') -Value "PATCH $($body.properties.tier)" -WhatIf:$false
                        ''
                    }
                    default { throw "Unexpected az call in test: az $command" }
                }
            }
            $script:premiumArguments = $script:deployArguments.Clone()
            $script:premiumArguments.OsDiskSku = 'Premium_LRS'
        }

        It 'deploys a 256 GiB OS disk by default' {
            & $script:deployScript @script:deployArguments -WhatIf *>&1 | Out-Null
            (Get-Content -LiteralPath (Join-Path $TestDrive 'parameters.json') -Raw | ConvertFrom-Json).parameters.osDiskSizeGB.value | Should -Be 256
        }

        It 'passes a configured size and SKU to the template' {
            & $script:deployScript @script:premiumArguments -OsDiskSizeGB 512 -WhatIf *>&1 | Out-Null
            $parameters = (Get-Content -LiteralPath (Join-Path $TestDrive 'parameters.json') -Raw | ConvertFrom-Json).parameters
            $parameters.osDiskSizeGB.value | Should -Be 512
            $parameters.osDiskSku.value | Should -BeExactly 'Premium_LRS'
        }

        It 'sets the requested tier after deployment and waits until the disk reports it' {
            $output = & $script:deployScript @script:premiumArguments -OsDiskPerformanceTier 'p30' *>&1 | Out-String
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like 'rest --method PATCH --url *disks/avd0012345-osdisk?api-version=*--body @*' }
            (Get-Content -LiteralPath (Join-Path $TestDrive 'tier-calls.txt')) | Should -Be @('PATCH P30')
            $output | Should -BeLike '*OS disk: Premium_LRS, 256 GiB, tier P30*'
            $output | Should -BeLike '*##vso`[task.setvariable variable=osDiskName;isOutput=true`]avd0012345-osdisk*'
        }

        It 'does not patch a disk that already has the tier' {
            Set-Content -LiteralPath (Join-Path $TestDrive 'tier.txt') -Value 'P30'
            & $script:deployScript @script:premiumArguments -OsDiskPerformanceTier 'P30' *>&1 | Out-Null
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
        }

        It 'leaves the tier alone when none is configured' {
            & $script:deployScript @script:premiumArguments -OsDiskPerformanceTier '$(AVD_OS_DISK_PERFORMANCE_TIER)' *>&1 | Out-Null
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*disks/*' }
        }

        It 'with -WhatIf reports the planned tier but never touches the disk' {
            $output = & $script:deployScript @script:premiumArguments -OsDiskPerformanceTier 'P30' -WhatIf *>&1 | Out-String
            $output | Should -BeLike '*performance tier P30 set after deployment*No deployment was performed*'
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*disks/*' }
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'deployment group create*' }
        }

        It 'rejects <Name> before any Azure call' -TestCases @(
            @{ Name = 'a tier on Standard SSD'; Sku = 'StandardSSD_LRS'; Tier = 'P30'; Message = '*needs OsDiskSku Premium_LRS*' }
            @{ Name = 'an unknown tier'; Sku = 'Premium_LRS'; Tier = 'P35'; Message = '*is not valid*' }
            @{ Name = 'a P60 tier'; Sku = 'Premium_LRS'; Tier = 'P60'; Message = '*is not valid*' }
        ) {
            # Pester supplies $Sku, $Tier, and $Message from the test case. A
            # param block would trip PSReviewUnusedParameter, because the
            # first two are used only inside the nested script block.
            { & $script:deployScript @script:deployArguments -OsDiskSku $Sku -OsDiskPerformanceTier $Tier -WhatIf *>&1 | Out-Null } | Should -Throw $Message
            Should -Invoke az -Times 0 -Exactly
        }

        It 'rejects a tier below the baseline of the disk size' {
            { & $script:deployScript @script:premiumArguments -OsDiskSizeGB 1024 -OsDiskPerformanceTier 'P20' -WhatIf *>&1 | Out-Null } |
                Should -Throw '*below the P30 baseline of a 1024 GiB disk*'
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'deployment group*' }
        }

        It 'keeps the OS disk size of an existing VM instead of resizing it' {
            Set-Content -LiteralPath (Join-Path $TestDrive 'vm-list.json') -Value '[{"name":"AVD0012345","tags":{"RITM":"RITM0012345","RequestedFor":"user@contoso.com"},"storageProfile":{"osDisk":{"diskSizeGB":127}}}]'
            $output = & $script:deployScript @script:deployArguments -WhatIf *>&1 | Out-String
            $output | Should -BeLike '*already exists with a 127 GiB OS disk; keeping that size*'
            (Get-Content -LiteralPath (Join-Path $TestDrive 'parameters.json') -Raw | ConvertFrom-Json).parameters.osDiskSizeGB.value | Should -Be 127
        }

        It 'checks the baseline against the size an existing VM keeps' {
            Set-Content -LiteralPath (Join-Path $TestDrive 'vm-list.json') -Value '[{"name":"AVD0012345","tags":{"RITM":"RITM0012345","RequestedFor":"user@contoso.com"},"storageProfile":{"osDisk":{"diskSizeGB":1024}}}]'
            { & $script:deployScript @script:premiumArguments -OsDiskPerformanceTier 'P20' -WhatIf *>&1 | Out-Null } | Should -Throw '*below the P30 baseline*'
        }
    }

    Context 'Safety rails' {
        It 'refuses a VM owned by another RITM before any deployment' {
            Mock az {
                $global:LASTEXITCODE = 0
                $command = $args -join ' '
                switch -Wildcard ($command) {
                    'account show*' { '{"id":"sub-1","tenantId":"tenant-1"}' }
                    'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","userPrincipalName":"user@contoso.com","accountEnabled":true}' }
                    'vm list*' { '[{"name":"AVD0012345","tags":{"RITM":"RITM0099999","RequestedFor":"other@contoso.com"}}]' }
                    default { throw "Unexpected az call in test: az $command" }
                }
            }
            { & $script:deployScript @script:deployArguments -WhatIf *>&1 | Out-Null } | Should -Throw '*already exists but is owned by RITM*'
        }

        It 'blocks a what-if containing a delete even before ShouldProcess' {
            Mock az {
                $global:LASTEXITCODE = 0
                $command = $args -join ' '
                switch -Wildcard ($command) {
                    'account show*' { '{"id":"sub-1","tenantId":"tenant-1"}' }
                    'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","userPrincipalName":"user@contoso.com","accountEnabled":true}' }
                    'vm list*' { '[]' }
                    'rest --method POST --url *retrieveRegistrationToken*' { '{"token":"fixture-token","expirationTime":"2099-01-01T00:00:00Z"}' }
                    'deployment group what-if*' { '{"changes":[{"changeType":"Delete"}]}' }
                    default { throw "Unexpected az call in test: az $command" }
                }
            }
            { & $script:deployScript @script:deployArguments -WhatIf *>&1 | Out-Null } | Should -Throw '*Deployment is blocked*'
        }

        It 'rejects a host name that is not RITM-derived' {
            { & $script:deployScript @script:deployArguments -VmName 'EVIL01' -WhatIf } | Should -Throw
            Should -Invoke az -Times 0 -Exactly
        }
    }
}

Describe 'Wait-AvdReadiness' {
    BeforeAll {
        $script:reportPath = Join-Path $TestDrive 'readiness.json'
        $script:readinessArguments = @{
            SubscriptionId = 'sub-1'
            SessionHostResourceGroupName = 'rg-hosts'
            PlatformResourceGroupName = 'rg-avd'
            HostPoolName = 'vdpool-prod'
            VmName = 'AVD0012345'
            RequiredAppName = @('Example App')
            RequireIntuneEnrolled = $true
            TimeoutMinutes = 5
            PollSeconds = 15
            ReportPath = $script:reportPath
        }
        function Get-ReadinessReport { Get-Content -LiteralPath $script:reportPath -Raw | ConvertFrom-Json }
    }

    BeforeEach {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'vm get-instance-view*' { '{"provisioningState":"Succeeded","instanceView":{"statuses":[{"code":"PowerState/running"}]}}' }
                'account get-access-token*' { '{"accessToken":"fixture-token"}' }
                'vm run-command invoke*' {
                    # Mock bodies run in the callee scope, so the payload is
                    # built here instead of referencing a test-scope variable.
                    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"detected":["Example App"],"missing":[]}'))
                    "{""value"":[{""message"":""AVD_APP_CHECK:$payload""}]}"
                }
                'rest --method GET --url *sessionHosts*' { '{"value":[{"name":"vdpool-prod/AVD0012345.contoso.com","id":"/subscriptions/sub-1/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-prod/sessionHosts/AVD0012345.contoso.com","properties":{"status":"Available","allowNewSession":true,"assignedUser":null}}]}' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        Mock Invoke-RestMethod {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'entra-1'; deviceId = 'device-1'; displayName = 'AVD0012345'; accountEnabled = $true; trustType = 'AzureAd' }) }
        } -ParameterFilter { $Uri -match '/v1\.0/devices\?' }
        Mock Invoke-RestMethod {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'managed-1'; deviceName = 'AVD0012345'; complianceState = 'noncompliant'; managementAgent = 'mdm'; lastSyncDateTime = '2026-11-12T00:00:00Z'; azureADDeviceId = 'device-1' }) }
        } -ParameterFilter { $Uri -match '/managedDevices\?' }
        Mock Start-Sleep { throw 'stop-after-first-poll' }
    }

    It 'passes when every enabled gate is green on the first poll' {
        $output = & $script:readinessScript @script:readinessArguments *>&1 | Out-String
        $output | Should -BeLike '*passed every enabled readiness gate*'
        (Get-ReadinessReport).result | Should -Be 'Ready'
    }

    It 'ignores compliance when only enrollment is required' {
        & $script:readinessScript @script:readinessArguments *>&1 | Out-Null
        $report = Get-ReadinessReport
        $report.checks.intuneEnrolled | Should -BeTrue
        $report.checks.intuneCompliant | Should -BeTrue
    }

    It 'fails the compliance gate for a noncompliant device' {
        { & $script:readinessScript @script:readinessArguments -RequireIntuneCompliant *>&1 | Out-Null } | Should -Throw '*stop-after-first-poll*'
        (Get-ReadinessReport).checks.intuneCompliant | Should -BeFalse
    }

    It 'does not pass a stale Intune record from another device' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'old'; deviceName = 'AVD0012345'; complianceState = 'compliant'; managementAgent = 'mdm'; lastSyncDateTime = '2020-01-01T00:00:00Z'; azureADDeviceId = 'device-old' }) }
        } -ParameterFilter { $Uri -match '/managedDevices\?' }
        { & $script:readinessScript @script:readinessArguments *>&1 | Out-Null } | Should -Throw '*stop-after-first-poll*'
        $report = Get-ReadinessReport
        $report.checks.entraJoined | Should -BeTrue
        $report.checks.intuneEnrolled | Should -BeFalse
    }

    It 'does not pass a workplace-registered device as Entra-joined' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'entra-1'; deviceId = 'device-1'; displayName = 'AVD0012345'; accountEnabled = $true; trustType = 'Workplace' }) }
        } -ParameterFilter { $Uri -match '/v1\.0/devices\?' }
        { & $script:readinessScript @script:readinessArguments *>&1 | Out-Null } | Should -Throw '*stop-after-first-poll*'
        (Get-ReadinessReport).checks.entraJoined | Should -BeFalse
    }

    It 'fails the app gate and reports the missing application' {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'vm get-instance-view*' { '{"provisioningState":"Succeeded","instanceView":{"statuses":[{"code":"PowerState/running"}]}}' }
                'account get-access-token*' { '{"accessToken":"fixture-token"}' }
                'vm run-command invoke*' {
                    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"detected":[],"missing":["Example App"]}'))
                    "{""value"":[{""message"":""AVD_APP_CHECK:$payload""}]}"
                }
                'rest --method GET --url *sessionHosts*' { '{"value":[]}' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        { & $script:readinessScript @script:readinessArguments *>&1 | Out-Null } | Should -Throw '*stop-after-first-poll*'
        $report = Get-ReadinessReport
        $report.checks.requiredApps | Should -BeFalse
        @($report.details.requiredApps.missing) | Should -Contain 'Example App'
    }

    It 'skips Run Command entirely when no apps are required' {
        & $script:readinessScript @script:readinessArguments -RequiredAppName @() *>&1 | Out-Null
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'vm run-command*' }
    }

    It 'rejects a host name that could alter the OData filter' {
        { & $script:readinessScript @script:readinessArguments -VmName "AVD1' or 1 eq 1" } | Should -Throw
        Should -Invoke az -Times 0 -Exactly
    }
}

Describe 'Set-AvdPersonalDesktopAssignment' {
    BeforeEach {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","accountEnabled":true}' }
                'role assignment list*' { '[]' }
                'role assignment create*' { '{"id":"assignment-1"}' }
                'vm show*' { '{"identity":{"principalId":"vm-mi-1"}}' }
                'rest --method GET --url *sessionHosts*' { '{"value":[{"name":"vdpool-prod/AVD0012345.contoso.com","id":"/subscriptions/sub-1/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-prod/sessionHosts/AVD0012345.contoso.com","properties":{"status":"Available","allowNewSession":true,"assignedUser":null}}]}' }
                'rest --method PATCH*' { '{"name":"AVD0012345.contoso.com"}' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        $script:assignArguments = @{
            SubscriptionId = 'sub-1'
            SessionHostResourceGroupName = 'rg-hosts'
            PlatformResourceGroupName = 'rg-avd'
            HostPoolName = 'vdpool-prod'
            DesktopAppGroupName = 'vdag-prod'
            VmName = 'AVD0012345'
            RequestedForUpn = 'user@contoso.com'
        }
    }

    It 'with -WhatIf discovers everything but changes nothing' {
        $output = & $script:assignScript @script:assignArguments -WhatIf *>&1 | Out-String
        $output | Should -BeLike '*Nothing was changed*'
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'role assignment create*' }
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
    }

    It 'grants both roles and assigns the host' {
        & $script:assignScript @script:assignArguments *>&1 | Out-Null
        Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '*role assignment create*fb879df8-f326-4884-b1cf-06f3ad86be52*' }
        Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '*role assignment create*1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63*' }
        Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
    }

    It 'is a no-op when the roles already exist' {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","accountEnabled":true}' }
                # The list call carries the scope, not the role, so dispatch on it.
                'role assignment list*virtualMachines/AVD0012345*' { '[{"roleDefinitionId":"/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/fb879df8-f326-4884-b1cf-06f3ad86be52"}]' }
                'role assignment list*applicationGroups/vdag-prod*' { '[{"roleDefinitionId":"/subscriptions/sub-1/providers/Microsoft.Authorization/roleDefinitions/1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63"}]' }
                'rest --method GET --url *sessionHosts*' { '{"value":[{"name":"vdpool-prod/AVD0012345.contoso.com","id":"/subscriptions/sub-1/resourceGroups/rg-avd/providers/Microsoft.DesktopVirtualization/hostPools/vdpool-prod/sessionHosts/AVD0012345.contoso.com","properties":{"status":"Available","allowNewSession":true,"assignedUser":null}}]}' }
                'rest --method PATCH*' { '{"name":"AVD0012345.contoso.com"}' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        & $script:assignScript @script:assignArguments *>&1 | Out-Null
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'role assignment create*' }
    }

    It 'grants the self-deallocate role to the VM identity when configured' {
        & $script:assignScript @script:assignArguments -SelfDeallocateRoleId '11111111-1111-1111-1111-111111111111' *>&1 | Out-Null
        Should -Invoke az -Times 1 -Exactly -ParameterFilter {
            ($args -join ' ') -like '*role assignment create*ServicePrincipal*11111111-1111-1111-1111-111111111111*'
        }
        Should -Invoke az -Times 3 -Exactly -ParameterFilter { ($args -join ' ') -like 'role assignment create*' }
    }

    It 'skips the self-deallocate grant when the variable macro is unresolved' {
        & $script:assignScript @script:assignArguments -SelfDeallocateRoleId '$(AVD_SELF_DEALLOCATE_ROLE_ID)' *>&1 | Out-Null
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'vm show*' }
        Should -Invoke az -Times 2 -Exactly -ParameterFilter { ($args -join ' ') -like 'role assignment create*' }
    }

    It 'with -WhatIf grants nothing even when the self-deallocate role is configured' {
        & $script:assignScript @script:assignArguments -SelfDeallocateRoleId '11111111-1111-1111-1111-111111111111' -WhatIf *>&1 | Out-Null
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'role assignment create*' }
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
    }

    Context 'UserAccessMode' {
        It 'in Group mode grants no user roles but still checks the user and assigns the host' {
            & $script:assignScript @script:assignArguments -UserAccessMode Group *>&1 | Out-Null
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'role assignment*' }
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like 'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' }
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
        }

        It 'in Group mode still grants the self-deallocate role when configured' {
            & $script:assignScript @script:assignArguments -UserAccessMode Group -SelfDeallocateRoleId '11111111-1111-1111-1111-111111111111' *>&1 | Out-Null
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like 'role assignment create*' }
            Should -Invoke az -Times 1 -Exactly -ParameterFilter {
                ($args -join ' ') -like '*role assignment create*ServicePrincipal*11111111-1111-1111-1111-111111111111*'
            }
        }

        It 'in Group mode with -WhatIf changes nothing' {
            $output = & $script:assignScript @script:assignArguments -UserAccessMode Group -WhatIf *>&1 | Out-String
            $output | Should -BeLike '*Nothing was changed*'
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'role assignment create*' }
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
        }

        It 'in Group mode still refuses a disabled user' {
            Mock az {
                $global:LASTEXITCODE = 0
                $command = $args -join ' '
                switch -Wildcard ($command) {
                    'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","accountEnabled":false}' }
                    default { throw "Unexpected az call in test: az $command" }
                }
            }
            { & $script:assignScript @script:assignArguments -UserAccessMode Group *>&1 | Out-Null } | Should -Throw '*not found or is disabled*'
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
        }

        It 'treats <Value> as Direct and grants both user roles' -TestCases @(
            @{ Value = '$(AVD_USER_ACCESS_MODE)' }
            @{ Value = '' }
            @{ Value = 'direct' }
        ) {
            param($Value)
            & $script:assignScript @script:assignArguments -UserAccessMode $Value *>&1 | Out-Null
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '*role assignment create*fb879df8-f326-4884-b1cf-06f3ad86be52*' }
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '*role assignment create*1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63*' }
        }

        It 'rejects an unknown mode before any Azure call' {
            { & $script:assignScript @script:assignArguments -UserAccessMode 'Groups' *>&1 | Out-Null } | Should -Throw '*not valid*'
            Should -Invoke az -Times 0 -Exactly
        }
    }

    It 'refuses a host assigned to someone else' {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","accountEnabled":true}' }
                'role assignment list*' { '[]' }
                'role assignment create*' { '{"id":"assignment-1"}' }
                'rest --method GET --url *sessionHosts*' { '{"value":[{"name":"vdpool-prod/AVD0012345.contoso.com","id":"/host","properties":{"status":"Available","allowNewSession":true,"assignedUser":"other@contoso.com"}}]}' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        { & $script:assignScript @script:assignArguments *>&1 | Out-Null } | Should -Throw '*already assigned*'
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
    }
}

Describe 'Add-AvdUserToAccessGroup' {
    BeforeAll {
        $script:groupId = '11111111-2222-3333-4444-555555555555'
    }

    BeforeEach {
        # The membership query goes through Invoke-RestMethod, not az (see the
        # cmd.exe regression tests below), so az only supplies its token.
        Mock Invoke-RestMethod { [pscustomobject]@{ value = @() } }
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","accountEnabled":true}' }
                'account get-access-token*' { '{"accessToken":"fixture-token"}' }
                'rest --method GET --url https://graph.microsoft.com/v1.0/groups/*' { '{"id":"11111111-2222-3333-4444-555555555555","displayName":"AVD Users","securityEnabled":true,"groupTypes":[],"onPremisesSyncEnabled":null,"isAssignableToRole":null}' }
                'rest --method POST*' {
                    $bodyArgument = [string]$args[([array]::IndexOf($args, '--body')) + 1]
                    if ($bodyArgument -like '@*') {
                        Copy-Item -LiteralPath $bodyArgument.Substring(1) -Destination (Join-Path $TestDrive 'member-body.json') -WhatIf:$false
                    }
                    ''
                }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        $script:groupArguments = @{ RequestedForUpn = 'user@contoso.com'; AccessGroupId = $script:groupId }
    }

    It 'skips the step when the group is <Name>' -TestCases @(
        @{ Name = 'empty'; Value = '' }
        @{ Name = 'an unresolved macro'; Value = '$(AVD_ACCESS_GROUP_ID)' }
    ) {
        param($Value)
        $output = & $script:groupScript -RequestedForUpn 'user@contoso.com' -AccessGroupId $Value *>&1 | Out-String
        $output | Should -BeLike '*No access group is configured*'
        Should -Invoke az -Times 0 -Exactly
    }

    It 'rejects a group value that is not an object ID before any Azure call' {
        { & $script:groupScript -RequestedForUpn 'user@contoso.com' -AccessGroupId 'AVD Users' *>&1 | Out-Null } | Should -Throw '*not a group object ID*'
        Should -Invoke az -Times 0 -Exactly
    }

    It 'with -WhatIf reads the user, group, and membership but adds nothing' {
        $output = & $script:groupScript @script:groupArguments -WhatIf *>&1 | Out-String
        $output | Should -BeLike "*Would add 'user@contoso.com' to group 'AVD Users'. Nothing was changed.*"
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -like '*groups/11111111-2222-3333-4444-555555555555/members*' }
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'rest --method POST*' }
    }

    It 'checks membership with the advanced query the owner-only identity needs' {
        & $script:groupScript @script:groupArguments -WhatIf *>&1 | Out-Null
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            # -Uri binds as [Uri], whose ToString() decodes %20 and %27.
            $Uri.OriginalString -like '*members?$filter=id%20eq%20%27user-1%27&$select=id&$count=true' -and
            $Headers.ConsistencyLevel -eq 'eventual' -and $Headers.Authorization -eq 'Bearer fixture-token'
        }
    }

    It 'adds the user as a direct member with the body passed as a file' {
        $output = & $script:groupScript @script:groupArguments *>&1 | Out-String
        $output | Should -BeLike "*Added 'user@contoso.com' to group 'AVD Users'.*"
        Should -Invoke az -Times 1 -Exactly -ParameterFilter {
            ($args -join ' ') -like 'rest --method POST --url https://graph.microsoft.com/v1.0/groups/11111111-2222-3333-4444-555555555555/members/$ref*--body @*'
        }
        (Get-Content -LiteralPath (Join-Path $TestDrive 'member-body.json') -Raw | ConvertFrom-Json).'@odata.id' |
            Should -BeExactly 'https://graph.microsoft.com/v1.0/directoryObjects/user-1'
    }

    It 'is a no-op when the user is already a member' {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","accountEnabled":true}' }
                'account get-access-token*' { '{"accessToken":"fixture-token"}' }
                'rest --method GET --url https://graph.microsoft.com/v1.0/groups/*' { '{"id":"g","displayName":"AVD Users","securityEnabled":true,"groupTypes":[],"onPremisesSyncEnabled":null,"isAssignableToRole":null}' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        Mock Invoke-RestMethod { [pscustomobject]@{ value = @([pscustomobject]@{ id = 'user-1' }) } }
        $output = & $script:groupScript @script:groupArguments *>&1 | Out-String
        $output | Should -BeLike '*already a member*Nothing was changed*'
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'rest --method POST*' }
    }

    # Lab finding: Graph answers 400 when the member already exists, and the
    # eventual-consistency membership query can lag a recent add.
    It 'treats the Graph "already exist" answer as success' {
        Mock az {
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { $global:LASTEXITCODE = 0; '{"id":"user-1","accountEnabled":true}' }
                'account get-access-token*' { $global:LASTEXITCODE = 0; '{"accessToken":"fixture-token"}' }
                'rest --method GET --url https://graph.microsoft.com/v1.0/groups/*' { $global:LASTEXITCODE = 0; '{"id":"g","displayName":"AVD Users","securityEnabled":true,"groupTypes":[],"onPremisesSyncEnabled":null,"isAssignableToRole":null}' }
                'rest --method POST*' { $global:LASTEXITCODE = 1; "ERROR: Bad Request({`"error`":{`"code`":`"Request_BadRequest`",`"message`":`"One or more added object references already exist for the following modified properties: 'members'.`"}})" }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        $output = & $script:groupScript @script:groupArguments *>&1 | Out-String
        $output | Should -BeLike '*already a member*'
    }

    # Regression: on a Windows agent az is az.cmd, and cmd.exe split the
    # membership URL at each '&'. Graph got the query without $count or the
    # ConsistencyLevel header and answered 403 Authorization_RequestDenied,
    # and cmd.exe tried to run "$select=id" as a command. Reproduced with
    # Windows pwsh and az.cmd; no az argument may contain '&'.
    It 'never passes an ampersand to az' {
        & $script:groupScript @script:groupArguments *>&1 | Out-Null
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*&*' }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'names group ownership when Graph refuses the membership check' {
        Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 403 (Forbidden).' }
        { & $script:groupScript @script:groupArguments *>&1 | Out-Null } | Should -Throw "*refused the membership check on group 'AVD Users'*owner of the group*"
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'rest --method POST*' }
    }

    It 'names group ownership when Graph refuses to read the group' {
        Mock az {
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { $global:LASTEXITCODE = 0; '{"id":"user-1","accountEnabled":true}' }
                'rest --method GET --url https://graph.microsoft.com/v1.0/groups/*' { $global:LASTEXITCODE = 1; 'ERROR: Forbidden({"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}})' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        { & $script:groupScript @script:groupArguments *>&1 | Out-Null } | Should -Throw '*service principal is an owner of the group*'
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'rest --method POST*' }
    }

    It 'refuses a <Name> group and adds nothing' -TestCases @(
        @{ Name = 'dynamic'; Group = '{"id":"g","displayName":"G","securityEnabled":true,"groupTypes":["DynamicMembership"],"onPremisesSyncEnabled":null,"isAssignableToRole":null}'; Message = '*dynamic membership*' }
        @{ Name = 'synced'; Group = '{"id":"g","displayName":"G","securityEnabled":true,"groupTypes":[],"onPremisesSyncEnabled":true,"isAssignableToRole":null}'; Message = '*synced from on-premises*' }
        @{ Name = 'role-assignable'; Group = '{"id":"g","displayName":"G","securityEnabled":true,"groupTypes":[],"onPremisesSyncEnabled":null,"isAssignableToRole":true}'; Message = '*role-assignable*' }
        @{ Name = 'non-security'; Group = '{"id":"g","displayName":"G","securityEnabled":false,"groupTypes":["Unified"],"onPremisesSyncEnabled":null,"isAssignableToRole":null}'; Message = '*not a security group*' }
    ) {
        param($Group, $Message)
        Set-Content -LiteralPath (Join-Path $TestDrive 'group.json') -Value $Group
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","accountEnabled":true}' }
                'rest --method GET --url https://graph.microsoft.com/v1.0/groups/*' { Get-Content -LiteralPath (Join-Path $TestDrive 'group.json') -Raw }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        { & $script:groupScript @script:groupArguments *>&1 | Out-Null } | Should -Throw $Message
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'rest --method POST*' }
    }

    It 'refuses a disabled user' {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","accountEnabled":false}' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        { & $script:groupScript @script:groupArguments *>&1 | Out-Null } | Should -Throw '*not found or is disabled*'
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*groups/*' }
    }

    It 'skips the UPN lookup when the object ID is supplied' {
        & $script:groupScript @script:groupArguments -UserObjectId 'user-1' -WhatIf *>&1 | Out-Null
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*graph.microsoft.com/v1.0/users/*' }
    }
}

Describe 'Set-AvdDrainMode' {
    BeforeEach {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url *sessionHosts*' { '{"value":[{"name":"vdpool-prod/AVD0012345.contoso.com","id":"/host","properties":{"status":"Available","allowNewSession":true}}]}' }
                'rest --method PATCH*' { '' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        $script:drainArguments = @{
            SubscriptionId = 'sub-1'
            PlatformResourceGroupName = 'rg-avd'
            HostPoolName = 'vdpool-prod'
            VmName = 'AVD0012345'
        }
    }

    It 'with -WhatIf changes nothing' {
        $output = & $script:drainScript @script:drainArguments -WhatIf *>&1 | Out-String
        $output | Should -BeLike '*Nothing was changed*'
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
    }

    # Regression: an inline JSON body lost its quotes through az.cmd on the
    # Windows agent. The body must arrive as a file reference.
    It 'drains a registered host with the body passed as a file' {
        $capture = Join-Path $TestDrive 'drain-body.json'
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url *sessionHosts*' { '{"value":[{"name":"vdpool-prod/AVD0012345.contoso.com","id":"/host","properties":{"status":"Available","allowNewSession":true}}]}' }
                'rest --method PATCH*' {
                    $bodyArgument = [string]$args[([array]::IndexOf($args, '--body')) + 1]
                    if ($bodyArgument -like '@*') {
                        Copy-Item -LiteralPath $bodyArgument.Substring(1) -Destination (Join-Path $TestDrive 'drain-body.json') -WhatIf:$false
                    }
                    ''
                }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        & $script:drainScript @script:drainArguments *>&1 | Out-Null
        Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*--body @*' }
        (Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json).properties.allowNewSession | Should -BeFalse
    }

    It 'changes nothing when no registration exists' {
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'rest --method GET --url *sessionHosts*' { '{"value":[]}' }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
        $output = & $script:drainScript @script:drainArguments *>&1 | Out-String
        $output | Should -BeLike '*no drain-mode change was required*'
    }
}

Describe 'Update-ServiceNowRitm' {
    BeforeEach {
        Mock Invoke-RestMethod { [pscustomobject]@{ access_token = 'fixture-token' } } -ParameterFilter { $Uri -match 'oauth_token\.do' }
        Mock Invoke-RestMethod { [pscustomobject]@{ result = [pscustomobject]@{ sys_id = '0123456789abcdef0123456789abcdef' } } } -ParameterFilter { $Method -eq 'Patch' }
        $script:serviceNowArguments = @{
            InstanceUrl = 'https://example.service-now.com'
            RitmSysId = '0123456789abcdef0123456789abcdef'
            Status = 'Ready'
            Message = 'Build finished.'
            HostName = 'AVD0012345'
            ClientId = 'client-1'
            ClientSecret = 'secret-1'
        }
    }

    It 'with -WhatIf sends nothing, not even the token request' {
        $output = & $script:serviceNowScript @script:serviceNowArguments -WhatIf *>&1 | Out-String
        $output | Should -BeLike '*Nothing was sent*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'uses OAuth and patches exactly one RITM' {
        & $script:serviceNowScript @script:serviceNowArguments *>&1 | Out-Null
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -match 'oauth_token\.do' }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Patch' -and
            $Uri -eq 'https://example.service-now.com/api/now/table/sc_req_item/0123456789abcdef0123456789abcdef' -and
            $Headers.Authorization -eq 'Bearer fixture-token'
        }
    }

    It 'treats unresolved pipeline macros as absent and falls back to Basic' {
        & $script:serviceNowScript @script:serviceNowArguments -ClientId '$(SN_CLIENT_ID)' -ClientSecret '$(SN_CLIENT_SECRET)' `
            -UserName 'avd.integration' -Password 'fixture-password' *>&1 | Out-Null
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Uri -match 'oauth_token\.do' }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'Patch' -and $Headers.Authorization -like 'Basic *' }
    }

    It 'rejects a status outside the lifecycle' {
        { & $script:serviceNowScript @script:serviceNowArguments -Status 'Done' } | Should -Throw
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
}

Describe 'Provision pipeline' {
    BeforeAll { $script:pipeline = Get-Content -LiteralPath $script:pipelinePath -Raw }

    It 'exposes exactly the five request parameters' {
        $names = @([regex]::Matches($script:pipeline, '(?m)^  - name: (\w+)\r?\n    displayName:') | ForEach-Object { $_.Groups[1].Value })
        ($names -join ',') | Should -Be 'workload,ritmNumber,requestedForUpn,ritmSysId,requestedHostName'
    }

    It 'restricts workload to a list' {
        $script:pipeline | Should -Match '(?m)^  - name: workload\r?\n(    .*\r?\n)*?    values:'
    }

    It 'guards every ServiceNow piece behind the sys_id parameter' {
        $guards = @([regex]::Matches($script:pipeline, [regex]::Escape("`${{ if ne(parameters.ritmSysId, '') }}:")))
        $guards.Count | Should -Be 5
        # Guarded pieces: the variable group, the in-progress step, the
        # NotifyReady stage, its entry in OnFailure dependsOn, and the
        # failure-notification step.
        $script:pipeline.IndexOf('avd-prod-servicenow') | Should -BeGreaterThan $script:pipeline.IndexOf("if ne(parameters.ritmSysId, '')")
        @([regex]::Matches($script:pipeline, 'Update-ServiceNowRitm\.ps1')).Count | Should -Be 3
    }

    It 'calls only scripts and templates that exist in this repository' {
        $paths = @([regex]::Matches($script:pipeline, "'((?:scripts|infra)/[^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $paths.Count | Should -BeGreaterThan 4
        foreach ($path in $paths) { Join-Path $script:repoRoot $path | Should -Exist }
    }

    It 'has no repository-prefix paths left over from a nested checkout' {
        $script:pipeline | Should -Not -Match 'AzureVirtualDesktopPoc'
    }

    It 'orders provision, readiness, and assignment correctly' {
        $script:pipeline.IndexOf('Wait-AvdReadiness.ps1') | Should -BeGreaterThan $script:pipeline.IndexOf('New-AvdSessionHost.ps1')
        $script:pipeline.IndexOf('Set-AvdPersonalDesktopAssignment.ps1') | Should -BeGreaterThan $script:pipeline.IndexOf('Wait-AvdReadiness.ps1')
    }

    It 'passes the workload user access mode to the assignment script' {
        $script:pipeline | Should -Match 'USER_ACCESS_MODE: \$\(AVD_USER_ACCESS_MODE\)'
        $script:pipeline | Should -Match '-UserAccessMode \$env:USER_ACCESS_MODE'
    }

    It 'passes the OS disk size and performance tier to the deploy script' {
        $script:pipeline | Should -Match 'OS_DISK_SIZE_GB: \$\(AVD_OS_DISK_SIZE_GB\)'
        $script:pipeline | Should -Match 'OS_DISK_PERFORMANCE_TIER: \$\(AVD_OS_DISK_PERFORMANCE_TIER\)'
        $script:pipeline | Should -Match '-OsDiskPerformanceTier \$env:OS_DISK_PERFORMANCE_TIER'
        # Only a number reaches -OsDiskSizeGB; an undefined macro keeps 256.
        $script:pipeline | Should -Match ([regex]::Escape("if (`$env:OS_DISK_SIZE_GB -match '^\s*\d+\s*`$') { `$diskArguments.OsDiskSizeGB = [int]`$env:OS_DISK_SIZE_GB }"))
    }

    It 'adds the user to the workload access group before binding the desktop' {
        $script:pipeline | Should -Match 'ACCESS_GROUP_ID: \$\(AVD_ACCESS_GROUP_ID\)'
        $script:pipeline | Should -Match '-AccessGroupId \$env:ACCESS_GROUP_ID'
        $groupStep = $script:pipeline.IndexOf('Add-AvdUserToAccessGroup.ps1')
        $groupStep | Should -BeGreaterThan $script:pipeline.IndexOf('Wait-AvdReadiness.ps1')
        $script:pipeline.IndexOf('Set-AvdPersonalDesktopAssignment.ps1') | Should -BeGreaterThan $groupStep
        $script:pipeline | Should -Match '(?s)Add the user to the workload access group.*?azureSubscription: \$\(AVD_ASSIGNMENT_SERVICE_CONNECTION\)'
    }

    It 'reports readiness back to the build run' {
        $script:pipeline | Should -Match 'task\.uploadsummary'
    }

    It 'never references POC variable groups' {
        $script:pipeline | Should -Not -Match 'avd-poc-'
    }
}

Describe 'Azure CLI request bodies' {
    # Regression: on Windows agents az is az.cmd, and cmd.exe strips the double
    # quotes from an inline JSON --body, which ARM rejects as invalid content.
    # Every --body must therefore be a file reference (@path).
    It '<Name> passes every --body as a file reference' -TestCases @(
        Get-ChildItem -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts') -Filter '*.ps1' |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        $lines = @(Get-Content -LiteralPath $Path | Where-Object { $_ -match "--body" -and $_ -notmatch '^\s*#' })
        foreach ($line in $lines) {
            $line | Should -Match "--body'?,?\s+`"@" -Because "an inline JSON body breaks through az.cmd: $($line.Trim())"
        }
    }
}

Describe 'Azure CLI URLs' {
    # Regression: cmd.exe treats '&' as a command separator, so a URL with a
    # query string of more than one parameter cannot go through az.cmd on a
    # Windows agent. Use Invoke-RestMethod with a token from az instead.
    It '<Name> passes no literal URL containing an ampersand to az' -TestCases @(
        Get-ChildItem -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts') -Filter '*.ps1' |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        $lines = @(Get-Content -LiteralPath $Path | Where-Object { $_ -match "'--url'" -and $_ -notmatch '^\s*#' })
        foreach ($line in $lines) {
            $line | Should -Not -Match '&' -Because "cmd.exe splits an az argument at '&': $($line.Trim())"
        }
    }
}

Describe 'Infrastructure safety' {
    BeforeAll {
        $script:sessionHost = Get-Content -LiteralPath $script:sessionHostBicep -Raw
        $script:access = Get-Content -LiteralPath $script:accessBicep -Raw
    }

    It 'session host has no public IP and only references the network' {
        $script:sessionHost | Should -Not -Match 'Microsoft\.Network/publicIPAddresses'
        $script:sessionHost | Should -Match "existing = \{"
    }

    It 'session host never declares an AVD control-plane resource' {
        $script:sessionHost | Should -Not -Match 'Microsoft\.DesktopVirtualization'
    }

    It 'session host carries the production lifecycle tags' {
        $script:sessionHost | Should -Match "ManagedBy: 'AvdProduction'"
        $script:sessionHost | Should -Match 'RITM: ritmNumber'
    }

    It 'session host sizes the OS disk at 256 GiB by default' {
        $script:sessionHost | Should -Match 'param osDiskSizeGB int = 256'
        $script:sessionHost | Should -Match 'diskSizeGB: osDiskSizeGB'
        $script:sessionHost | Should -Match ([regex]::Escape('output osDiskName string = vm.properties.storageProfile.osDisk.name'))
    }

    # Lab finding: a 256 GiB disk from the Windows 11 24H2 image kept a
    # 126 GiB C: volume until the partition was extended.
    It 'session host extends C: only when there is space to gain' {
        $script:sessionHost | Should -Match "(?s)resource extendOsVolume.*?type: 'CustomScriptExtension'"
        $script:sessionHost | Should -Match ([regex]::Escape('if ($maximum -gt ($partition.Size + 1GB)) { Resize-Partition -DriveLetter C -Size $maximum'))
    }

    It 'access roles grant no delete action or network write' {
        $script:access | Should -Not -Match '/delete'
        $script:access | Should -Not -Match 'Microsoft\.Network/virtualNetworks/[^''"]*write'
    }

    It 'access roles limit role assignment to the two AVD roles for users' {
        $script:access | Should -Match "assignableRoleIds = 'fb879df8-f326-4884-b1cf-06f3ad86be52, 1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63'"
        $script:access | Should -Match 'PrincipalType\] ForAnyOfAnyValues:StringEqualsIgnoreCase'
        @([regex]::Matches($script:access, 'condition: assignmentCondition')).Count | Should -Be @([regex]::Matches($script:access, "'Microsoft.Authorization/roleAssignments/write'\r?\n")).Count
    }

    It 'grants Run Command only once, to the readiness identity' {
        @([regex]::Matches($script:access, 'runCommand/action')).Count | Should -Be 1
        $script:access | Should -Match "(?s)name: 'Check VMs'.*?readinessPrincipalId.*?runCommand/action"
    }

    It 'namespaces role GUIDs away from earlier POC role definitions' {
        $script:access | Should -Match ([regex]::Escape("guid(subscription().id, 'avd-prod', workload, spec.name)"))
    }

    It 'defines the self-deallocate role with only read and deallocate on the VM scope' {
        $script:access | Should -Match "(?s)resource selfDeallocateRole.*?'Microsoft.Compute/virtualMachines/read'\s*'Microsoft.Compute/virtualMachines/deallocate/action'\s*\]"
        $script:access | Should -Match ([regex]::Escape('output selfDeallocateRoleDefinitionId string = selfDeallocateRole.name'))
    }

    It 'extends the ABAC condition to the self-deallocate role for service principals only' {
        $script:access | Should -Match ([regex]::Escape('GuidEquals {${selfDeallocateRoleName}}'))
        $script:access | Should -Match "ForAnyOfAnyValues:StringEqualsIgnoreCase \{\\'ServicePrincipal\\'\}"
    }
}

Describe 'Invoke-AvdSelfDeallocate' {
    BeforeAll {
        $script:selfDeallocate = Join-Path $script:repoRoot 'endpoint/Invoke-AvdSelfDeallocate.ps1'
        $script:savedProgramFiles = $env:ProgramFiles
        $script:savedSystemRoot = $env:SystemRoot
        $env:ProgramFiles = 'C:\Program Files'
        $env:SystemRoot = 'C:\Windows'
        $script:installedScript = 'C:\Program Files\AvdSessionHostAutomation\Invoke-AvdSelfDeallocate.ps1'

        # Stand-ins so quser.exe, the Windows-only Get-CimInstance, and the
        # ScheduledTasks module can be mocked on any platform. Their
        # parameters exist only so Pester's mocks accept the script's
        # named arguments.
        function quser { }
        function Get-CimInstance {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Offline stand-in for a Windows-only cmdlet; the mock replaces it.')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Declared so the mocked call binds its arguments.')]
            param($ClassName)
        }
        function New-ScheduledTaskAction {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stand-in for a cmdlet that only builds an in-memory object.')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Declared so the mocked call binds its arguments.')]
            param($Execute, $Argument)
        }
        function New-ScheduledTaskTrigger {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stand-in for a cmdlet that only builds an in-memory object.')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Declared so the mocked call binds its arguments.')]
            param([switch]$Once, $At)
        }
        function New-ScheduledTaskPrincipal {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stand-in for a cmdlet that only builds an in-memory object.')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Declared so the mocked call binds its arguments.')]
            param($UserId, $LogonType, $RunLevel)
        }
        function New-ScheduledTaskSettingsSet {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stand-in for a cmdlet that only builds an in-memory object.')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Declared so the mocked call binds its arguments.')]
            param($ExecutionTimeLimit, $MultipleInstances, [switch]$StartWhenAvailable)
        }
        function Register-ScheduledTask {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Declared so the mocked call binds its arguments.')]
            param($TaskName, $TaskPath, $Action, $Trigger, $Principal, $Settings, [switch]$Force, $Description)
        }

        $script:sessionOpen = { $global:LASTEXITCODE = 0; @(' USERNAME  SESSIONNAME  ID  STATE', '>user1  rdp-tcp#1  2  Active') }
        $script:noMutation = {
            Should -Invoke Register-ScheduledTask -Times 0 -Exactly
            Should -Invoke Copy-Item -Times 0 -Exactly
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
            Should -Invoke New-Item -Times 0 -Exactly
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Method -eq 'Post' }
        }
    }

    AfterAll {
        $env:ProgramFiles = $script:savedProgramFiles
        $env:SystemRoot = $script:savedSystemRoot
    }

    BeforeEach {
        Mock quser { $global:LASTEXITCODE = 1; $null }
        Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = (Get-Date).AddHours(-3) } }
        Mock Invoke-RestMethod {
            [pscustomobject]@{ name = [Environment]::MachineName; subscriptionId = 'sub-1'; resourceGroupName = 'rg-hosts' }
        } -ParameterFilter { $Uri -match 'metadata/instance/compute' }
        Mock Invoke-RestMethod {
            [pscustomobject]@{ access_token = 'fixture-token' }
        } -ParameterFilter { $Uri -match 'metadata/identity/oauth2/token' }
        Mock Invoke-RestMethod { [pscustomobject]@{ name = 'vm' } } -ParameterFilter {
            $Method -eq 'Get' -and $Uri -like 'https://management.azure.com/*'
        }
        Mock Invoke-RestMethod { $null } -ParameterFilter { $Method -eq 'Post' }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like 'HKLM:*' -or $LiteralPath -like 'C:\Program Files*' }
        Mock New-Item { } -ParameterFilter { $Path -like 'HKLM:*' -or $Path -like 'C:\Program Files*' }
        Mock Set-ItemProperty { } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        Mock Copy-Item { } -ParameterFilter { $Destination -like 'C:\Program Files*' }
        Mock New-ScheduledTaskAction { 'task-action' }
        Mock New-ScheduledTaskTrigger { 'task-trigger' }
        Mock New-ScheduledTaskPrincipal { 'task-principal' }
        Mock New-ScheduledTaskSettingsSet { 'task-settings' }
        Mock Register-ScheduledTask { }
    }

    Context 'Schedule step (Intune remediation)' {
        It 'registers a one-time SYSTEM task that runs the installed copy with -Deferred' {
            & $script:selfDeallocate *>&1 | Out-Null
            Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskName -eq 'AvdSelfDeallocate' -and $TaskPath -eq '\AvdSessionHostAutomation\' -and $Force -and
                $Action -eq 'task-action' -and $Trigger -eq 'task-trigger' -and
                $Principal -eq 'task-principal' -and $Settings -eq 'task-settings'
            }
            Should -Invoke New-ScheduledTaskPrincipal -Times 1 -Exactly -ParameterFilter {
                $UserId -eq 'NT AUTHORITY\SYSTEM' -and $LogonType -eq 'ServiceAccount' -and $RunLevel -eq 'Highest'
            }
            Should -Invoke New-ScheduledTaskAction -Times 1 -Exactly -ParameterFilter {
                $Execute -eq 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -and
                $Argument -eq ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Deferred -MinimumUptimeMinutes 60 -ManagementEndpoint https://management.azure.com' -f $script:installedScript)
            }
        }

        It 'schedules the deallocation DeallocateDelayMinutes out' {
            $before = Get-Date
            & $script:selfDeallocate -DeallocateDelayMinutes 7 *>&1 | Out-Null
            Should -Invoke New-ScheduledTaskTrigger -Times 1 -Exactly -ParameterFilter {
                $Once -and $At -ge $before.AddMinutes(7) -and $At -le (Get-Date).AddMinutes(7)
            }
        }

        It 'never lets a missed trigger start late and bounds the run time' {
            & $script:selfDeallocate *>&1 | Out-Null
            Should -Invoke New-ScheduledTaskSettingsSet -Times 1 -Exactly -ParameterFilter {
                -not $StartWhenAvailable -and $ExecutionTimeLimit -eq (New-TimeSpan -Minutes 15) -and $MultipleInstances -eq 'IgnoreNew'
            }
        }

        It 'installs itself under Program Files for the task' {
            & $script:selfDeallocate *>&1 | Out-Null
            Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'C:\Program Files\AvdSessionHostAutomation' -and $ItemType -eq 'Directory'
            }
            Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -eq $script:selfDeallocate -and $Destination -eq $script:installedScript -and $Force
            }
        }

        It 'proves the identity can read the VM and does not deallocate' {
            $output = & $script:selfDeallocate *>&1 | Out-String
            $output | Should -BeLike "*Identity check passed. Deallocation of '$([Environment]::MachineName)' scheduled for *"
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Get' -and $Uri -like 'https://management.azure.com/*' -and $Headers.Authorization -eq 'Bearer fixture-token'
            }
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Method -eq 'Post' }
        }

        It 'records the schedule marker and result for the detection script' {
            & $script:selfDeallocate *>&1 | Out-Null
            Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -eq 'HKLM:\SOFTWARE\AvdSessionHostAutomation\SelfDeallocate' -and
                $Name -eq 'DeallocateScheduledUtc' -and
                [datetime]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) -gt (Get-Date).ToUniversalTime().AddMinutes(-1)
            }
            Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'LastResult' -and $Value -match '\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ Identity check passed\. Deallocation of .+ scheduled for '
            }
        }

        It 'fails before scheduling when ARM refuses the read' {
            Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 403 (Forbidden).' } -ParameterFilter {
                $Method -eq 'Get' -and $Uri -like 'https://management.azure.com/*'
            }
            { & $script:selfDeallocate *>&1 | Out-Null } | Should -Throw '*AVD Prod Self Deallocate role*'
            & $script:noMutation
        }

        It 'still reports success when the state cannot be written' {
            Mock Set-ItemProperty { throw 'Access denied' } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
            $output = & $script:selfDeallocate *>&1 | Out-String
            $output | Should -BeLike '*Could not record DeallocateScheduledUtc*'
            $output | Should -BeLike '*scheduled for*'
        }

        It 'does nothing while any session exists' {
            Mock quser $script:sessionOpen
            $output = & $script:selfDeallocate *>&1 | Out-String
            $output | Should -BeLike '*In use*No action*'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
            & $script:noMutation
        }

        It 'treats a disconnected session as in use' {
            Mock quser { $global:LASTEXITCODE = 0; @(' USERNAME  SESSIONNAME  ID  STATE', ' user1  4  Disc') }
            $output = & $script:selfDeallocate *>&1 | Out-String
            $output | Should -BeLike '*In use*'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }

        It 'does nothing before the uptime threshold' {
            Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = (Get-Date).AddMinutes(-10) } }
            $output = & $script:selfDeallocate *>&1 | Out-String
            $output | Should -BeLike '*minimum minutes*'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
            & $script:noMutation
        }

        It 'refuses to act when IMDS names a different VM' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{ name = 'SOMEOTHERVM'; subscriptionId = 'sub-1'; resourceGroupName = 'rg-hosts' }
            } -ParameterFilter { $Uri -match 'metadata/instance/compute' }
            { & $script:selfDeallocate *>&1 | Out-Null } | Should -Throw '*Refusing to deallocate*'
            & $script:noMutation
        }
    }

    Context 'Deferred step (scheduled task)' {
        It 'deallocates itself when still idle, treating a quser failure as zero sessions' {
            $output = & $script:selfDeallocate -Deferred *>&1 | Out-String
            $output | Should -BeLike '*accepted*'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'Get' -and $Uri -like 'https://management.azure.com/*'
            }
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Post' -and
                $Uri -like "https://management.azure.com/subscriptions/sub-1/resourceGroups/rg-hosts/providers/Microsoft.Compute/virtualMachines/$([Environment]::MachineName)/deallocate?api-version=*" -and
                $Headers.Authorization -eq 'Bearer fixture-token'
            }
            Should -Invoke Register-ScheduledTask -Times 0 -Exactly
            Should -Invoke Copy-Item -Times 0 -Exactly
        }

        It 'records the accepted deallocation as the last result' {
            & $script:selfDeallocate -Deferred *>&1 | Out-Null
            Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'LastResult' -and $Value -like '*Deallocation of * accepted (0 sessions, up * minutes).'
            }
            Should -Invoke Set-ItemProperty -Times 0 -Exactly -ParameterFilter { $Name -eq 'DeallocateScheduledUtc' }
        }

        It 'cancels and records why when a user connected during the delay' {
            Mock quser $script:sessionOpen
            $output = & $script:selfDeallocate -Deferred *>&1 | Out-String
            $output | Should -BeLike '*In use*No action*'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
            Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'LastResult' -and $Value -like '*Deallocation cancelled. In use: 1 session(s) present.'
            }
        }

        It 'records the failure when Azure refuses the deallocation' {
            Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 403 (Forbidden).' } -ParameterFilter { $Method -eq 'Post' }
            { & $script:selfDeallocate -Deferred *>&1 | Out-Null } | Should -Throw '*403*'
            Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'LastResult' -and $Value -like '*Deallocation failed. *403*'
            }
        }

        It 'with -WhatIf tests the identity and changes nothing' {
            $output = & $script:selfDeallocate -Deferred -WhatIf *>&1 | Out-String
            $output | Should -BeLike '*Identity check passed*'
            $output | Should -BeLike '*Would deallocate*'
            & $script:noMutation
        }
    }

    Context 'WhatIf identity test' {
        It 'with -WhatIf tests the token against ARM and changes nothing' {
            $output = & $script:selfDeallocate -WhatIf *>&1 | Out-String
            $output | Should -BeLike '*Identity check passed*'
            $output | Should -BeLike '*Would schedule deallocation*'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -match 'oauth2/token' -and $Uri -like '*resource=https%3A%2F%2Fmanagement.azure.com%2F'
            }
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Get' -and
                $Uri -like "https://management.azure.com/subscriptions/sub-1/resourceGroups/rg-hosts/providers/Microsoft.Compute/virtualMachines/$([Environment]::MachineName)?api-version=*" -and
                $Headers.Authorization -eq 'Bearer fixture-token'
            }
            & $script:noMutation
        }

        It 'with -WhatIf still tests the identity while a session is open' {
            Mock quser { $global:LASTEXITCODE = 0; @(' USERNAME  SESSIONNAME  ID  STATE', '>tech1  rdp-tcp#1  2  Active') }
            $output = & $script:selfDeallocate -WhatIf *>&1 | Out-String
            $output | Should -BeLike '*Identity check passed*'
            $output | Should -BeLike '*In use: 1 session(s) present. Would take no action*'
            & $script:noMutation
        }

        It 'with -WhatIf reports a missing role when ARM refuses the read' {
            Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 403 (Forbidden).' } -ParameterFilter {
                $Method -eq 'Get' -and $Uri -like 'https://management.azure.com/*'
            }
            { & $script:selfDeallocate -WhatIf *>&1 | Out-Null } | Should -Throw '*AVD Prod Self Deallocate role*'
            & $script:noMutation
        }

        It 'names the requested resource when IMDS refuses the token' {
            Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 400 (Bad Request).' } -ParameterFilter {
                $Uri -match 'metadata/identity/oauth2/token'
            }
            { & $script:selfDeallocate -WhatIf *>&1 | Out-Null } | Should -Throw "*resource 'https://management.azure.com/'*"
        }

        It 'never writes the token to output' {
            foreach ($arguments in @(@{}, @{ WhatIf = $true }, @{ Deferred = $true }, @{ Deferred = $true; WhatIf = $true })) {
                $output = & $script:selfDeallocate @arguments *>&1 | Out-String
                $output | Should -Not -BeLike '*fixture-token*'
            }
        }
    }
}

Describe 'Detect-AvdSelfDeallocate' {
    BeforeAll {
        $script:detect = Join-Path $script:repoRoot 'endpoint/Detect-AvdSelfDeallocate.ps1'
        function quser { }
        function Get-CimInstance {
            # Get-CimInstance only exists on Windows; this stub lets the
            # offline tests mock it, and ClassName exists only so Pester's
            # mock accepts the script's -ClassName argument.
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Offline stand-in for a Windows-only cmdlet; the mock replaces it.')]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ClassName', Justification = 'Declared so the mocked call binds -ClassName.')]
            param($ClassName)
        }
    }

    BeforeEach {
        Mock quser { $global:LASTEXITCODE = 1; $null }
        Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = (Get-Date).AddHours(-3) } }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        Mock Invoke-RestMethod { throw 'Detection must not call any API.' }
    }

    It 'exits 1 when idle past the threshold' {
        $output = & $script:detect *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $output | Should -BeLike '*Idle: 0 sessions*'
    }

    It 'exits 0 while any session exists, including a disconnected one' {
        Mock quser { $global:LASTEXITCODE = 0; @(' USERNAME  SESSIONNAME  ID  STATE', ' user1  4  Disc') }
        $output = & $script:detect *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -BeLike '*In use: 1 session(s)*'
    }

    It 'exits 0 before the uptime threshold' {
        Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = (Get-Date).AddMinutes(-10) } }
        $output = & $script:detect *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -BeLike '*minimum minutes*'
    }

    It 'exits 0 when a deallocation was scheduled during this boot' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        Mock Get-ItemProperty {
            [pscustomobject]@{ DeallocateScheduledUtc = (Get-Date).ToUniversalTime().AddMinutes(-2).ToString('o') }
        } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        $output = & $script:detect *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -BeLike '*Deallocation scheduled 2 minute(s) ago*'
    }

    It 'repeats the last self-deallocate result in its output' {
        Mock quser { $global:LASTEXITCODE = 0; @(' USERNAME  SESSIONNAME  ID  STATE', '>user1  rdp-tcp#1  2  Active') }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        Mock Get-ItemProperty {
            [pscustomobject]@{ LastResult = "2026-01-01T10:20:00Z Deallocation of 'AVD0012345' accepted (0 sessions, up 75 minutes)." }
        } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        $output = & $script:detect *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -BeLike "*In use: 1 session(s) present. Last self-deallocate: 2026-01-01T10:20:00Z Deallocation of 'AVD0012345' accepted*"
    }

    It 'ignores a marker from an earlier boot' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        Mock Get-ItemProperty {
            [pscustomobject]@{ DeallocateScheduledUtc = (Get-Date).ToUniversalTime().AddHours(-5).ToString('o') }
        } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        & $script:detect *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'ignores a stale marker so a failed deallocation is retried' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        Mock Get-ItemProperty {
            [pscustomobject]@{ DeallocateScheduledUtc = (Get-Date).ToUniversalTime().AddMinutes(-45).ToString('o') }
        } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        & $script:detect *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'ignores an unparseable marker' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        Mock Get-ItemProperty { [pscustomobject]@{ DeallocateScheduledUtc = 'not-a-date' } } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        & $script:detect *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits 2, not 1, when detection itself fails' {
        Mock Get-CimInstance { throw 'WMI unavailable' }
        $output = & $script:detect *>&1 | Out-String
        $LASTEXITCODE | Should -Be 2
        $output | Should -BeLike '*Detection failed: WMI unavailable*'
    }

    It 'calls no Azure API' {
        & $script:detect *>&1 | Out-Null
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
}

Describe 'Self-deallocate detection and remediation stay in sync' {
    BeforeAll {
        $script:parse = {
            param([string]$Path)
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        }
        $script:detectAst = & $script:parse (Join-Path $script:repoRoot 'endpoint/Detect-AvdSelfDeallocate.ps1')
        $script:remediateAst = & $script:parse (Join-Path $script:repoRoot 'endpoint/Invoke-AvdSelfDeallocate.ps1')
        $script:functionText = {
            param($Ast, [string]$Name)
            $functions = $Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true)
            foreach ($function in $functions) {
                if ($function.Name -eq $Name) { return $function.Extent.Text }
            }
        }
        $script:assignedValue = {
            param($Ast, [string]$VariableName)
            $assignments = $Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst]
                }, $false)
            foreach ($assignment in $assignments) {
                if ($assignment.Left.Extent.Text -eq "`$$VariableName") { return $assignment.Right.Extent.Text }
            }
        }
        $script:parameterDefault = {
            param($Ast, [string]$Name)
            ($Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $Name }).DefaultValue.Extent.Text
        }
    }

    It 'shares an identical <_> function' -ForEach @('Get-ActiveSessionCount', 'Get-HostUptime') {
        $detectText = & $script:functionText $script:detectAst $_
        $detectText | Should -Not -BeNullOrEmpty
        $detectText | Should -BeExactly (& $script:functionText $script:remediateAst $_)
    }

    It 'uses the same <_> value' -ForEach @('markerKey', 'markerValueName', 'resultValueName') {
        $detectValue = & $script:assignedValue $script:detectAst $_
        $detectValue | Should -Not -BeNullOrEmpty
        $detectValue | Should -BeExactly (& $script:assignedValue $script:remediateAst $_)
    }

    It 'uses the same MinimumUptimeMinutes default' {
        (& $script:parameterDefault $script:detectAst 'MinimumUptimeMinutes') |
            Should -BeExactly (& $script:parameterDefault $script:remediateAst 'MinimumUptimeMinutes')
    }

    It 'keeps the marker valid well past the deallocation delay' {
        $markerValid = [int](& $script:parameterDefault $script:detectAst 'MarkerValidMinutes')
        $delay = [int](& $script:parameterDefault $script:remediateAst 'DeallocateDelayMinutes')
        $delay | Should -BeGreaterThan 0
        $markerValid | Should -BeGreaterOrEqual ($delay + 10)
    }
}
