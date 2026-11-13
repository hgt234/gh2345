#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0'; MaximumVersion = '5.99.99' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptsRoot = Join-Path $script:repoRoot 'scripts'
    $script:validator = Join-Path $script:scriptsRoot 'Test-AvdProvisionRequest.ps1'
    $script:deployScript = Join-Path $script:scriptsRoot 'New-AvdSessionHost.ps1'
    $script:readinessScript = Join-Path $script:scriptsRoot 'Wait-AvdReadiness.ps1'
    $script:assignScript = Join-Path $script:scriptsRoot 'Set-AvdPersonalDesktopAssignment.ps1'
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

    Context 'Power-off identity' {
        BeforeEach {
            # A real (non -WhatIf) run writes the parameter file, so the
            # what-if mock copies it to TestDrive before the script deletes
            # it, and each test reads back exactly what the template receives.
            $script:capturedParameterFile = Join-Path $TestDrive 'template-parameters.json'
            Remove-Item -LiteralPath $script:capturedParameterFile -ErrorAction SilentlyContinue
            Mock az {
                $global:LASTEXITCODE = 0
                $command = $args -join ' '
                switch -Wildcard ($command) {
                    'account show*' { '{"id":"sub-1","tenantId":"tenant-1"}' }
                    'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","userPrincipalName":"user@contoso.com","accountEnabled":true}' }
                    'vm list*' { '[]' }
                    'rest --method POST --url *retrieveRegistrationToken*' { '{"token":"fixture-token","expirationTime":"2099-01-01T00:00:00Z"}' }
                    'deployment group what-if*' {
                        $parameterArgument = @($args | Where-Object { "$_" -like '@*' })[0]
                        Copy-Item -LiteralPath "$parameterArgument".Substring(1) -Destination (Join-Path $TestDrive 'template-parameters.json')
                        '{"changes":[]}'
                    }
                    'deployment group create*' { '{"properties":{"outputs":{"vmId":{"value":"/vm-1"}}}}' }
                    default { throw "Unexpected az call in test: az $command" }
                }
            }
            $script:powerOffIdentityId = '/subscriptions/sub-1/resourceGroups/rg-hosts/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-avd-poweroff'
        }

        It 'passes the identity resource ID to the template when set' {
            & $script:deployScript @script:deployArguments -PowerOffIdentityId $script:powerOffIdentityId *>&1 | Out-Null
            $captured = (Get-Content -LiteralPath $script:capturedParameterFile -Raw | ConvertFrom-Json).parameters
            $captured.powerOffIdentityId.value | Should -Be $script:powerOffIdentityId
        }

        It 'passes an empty value when the variable macro is unresolved' {
            & $script:deployScript @script:deployArguments -PowerOffIdentityId '$(AVD_POWER_OFF_IDENTITY_ID)' *>&1 | Out-Null
            $captured = (Get-Content -LiteralPath $script:capturedParameterFile -Raw | ConvertFrom-Json).parameters
            $captured.powerOffIdentityId.value | Should -Be ''
        }

        It 'rejects a value that is not a user-assigned identity resource ID before any Azure call' {
            { & $script:deployScript @script:deployArguments -PowerOffIdentityId '/subscriptions/sub-1/resourceGroups/rg-hosts/providers/Microsoft.Compute/virtualMachines/AVD1' -WhatIf *>&1 | Out-Null } |
                Should -Throw '*not a user-assigned managed identity resource ID*'
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

    It 'drains a registered host' {
        & $script:drainScript @script:drainArguments *>&1 | Out-Null
        Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*allowNewSession*' }
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

    It 'passes the workload power-off identity to the deployment script' {
        $script:pipeline | Should -Match 'POWER_OFF_IDENTITY_ID: \$\(AVD_POWER_OFF_IDENTITY_ID\)'
        $script:pipeline | Should -Match '-PowerOffIdentityId \$env:POWER_OFF_IDENTITY_ID'
    }

    It 'passes the workload user access mode to the assignment script' {
        $script:pipeline | Should -Match 'USER_ACCESS_MODE: \$\(AVD_USER_ACCESS_MODE\)'
        $script:pipeline | Should -Match '-UserAccessMode \$env:USER_ACCESS_MODE'
    }

    It 'reports readiness back to the build run' {
        $script:pipeline | Should -Match 'task\.uploadsummary'
    }

    It 'never references POC variable groups' {
        $script:pipeline | Should -Not -Match 'avd-poc-'
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

    It 'session host keeps the system-assigned identity and adds the power-off identity only when set' {
        $script:sessionHost | Should -Match "(?s)identity: empty\(powerOffIdentityId\)\s*\?\s*\{\s*type: 'SystemAssigned'\s*\}"
        $script:sessionHost | Should -Match "type: 'SystemAssigned, UserAssigned'"
        $script:sessionHost | Should -Not -Match "type: 'UserAssigned'"
        # Attaching the identity must never become a role assignment here.
        $script:sessionHost | Should -Not -Match 'Microsoft\.Authorization/roleAssignments'
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
        # Stand-ins so quser.exe and the Windows-only Get-CimInstance can be
        # mocked on any platform.
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
        Mock Invoke-RestMethod {
            [pscustomobject]@{ name = [Environment]::MachineName; subscriptionId = 'sub-1'; resourceGroupName = 'rg-hosts' }
        } -ParameterFilter { $Uri -match 'metadata/instance/compute' }
        Mock Invoke-RestMethod {
            [pscustomobject]@{ access_token = 'fixture-token' }
        } -ParameterFilter { $Uri -match 'metadata/identity/oauth2/token' }
        Mock Invoke-RestMethod { $null } -ParameterFilter { $Method -eq 'Post' }
    }

    It 'with -WhatIf discovers but requests no token and changes nothing' {
        $output = & $script:selfDeallocate -WhatIf *>&1 | Out-String
        $output | Should -BeLike '*Would deallocate*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Uri -match 'oauth2/token' }
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Method -eq 'Post' }
    }

    It 'does nothing while any session exists' {
        Mock quser { $global:LASTEXITCODE = 0; @(' USERNAME  SESSIONNAME  ID  STATE', '>user1  rdp-tcp#1  2  Active') }
        $output = & $script:selfDeallocate *>&1 | Out-String
        $output | Should -BeLike '*In use*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
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
    }

    It 'refuses to act when IMDS names a different VM' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ name = 'SOMEOTHERVM'; subscriptionId = 'sub-1'; resourceGroupName = 'rg-hosts' }
        } -ParameterFilter { $Uri -match 'metadata/instance/compute' }
        { & $script:selfDeallocate *>&1 | Out-Null } | Should -Throw '*Refusing to deallocate*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Method -eq 'Post' }
    }

    It 'deallocates itself when idle, treating a quser failure as zero sessions' {
        $output = & $script:selfDeallocate *>&1 | Out-String
        $output | Should -BeLike '*was accepted*'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and
            $Uri -like "https://management.azure.com/subscriptions/sub-1/resourceGroups/rg-hosts/providers/Microsoft.Compute/virtualMachines/$([Environment]::MachineName)/deallocate?api-version=*" -and
            $Headers.Authorization -eq 'Bearer fixture-token'
        }
    }

    It 'never writes the token to output' {
        $output = & $script:selfDeallocate *>&1 | Out-String
        $output | Should -Not -BeLike '*fixture-token*'
    }

    It 'requests the token without client_id when no identity is named' {
        & $script:selfDeallocate *>&1 | Out-Null
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -match 'oauth2/token' -and $Uri -notmatch 'client_id=' }
    }

    It 'requests the token for the named user-assigned identity' {
        & $script:selfDeallocate -ManagedIdentityClientId '11111111-1111-1111-1111-111111111111' *>&1 | Out-Null
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -match 'oauth2/token' -and $Uri -like '*&client_id=11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'Post' }
    }

    It 'rejects a client ID that is not a GUID before any call' {
        { & $script:selfDeallocate -ManagedIdentityClientId 'not-a-guid&resource=x' } | Should -Throw
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
}
