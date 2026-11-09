#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0'; MaximumVersion = '5.99.99' }

BeforeAll {
    $script:phaseRoot = Split-Path -Parent $PSScriptRoot
    $script:starter = Join-Path $script:phaseRoot 'Start-AvdBuild.ps1'
    $script:validator = Join-Path $script:phaseRoot 'scripts/Test-AvdManualRequest.ps1'
    $script:pipelinePath = Join-Path $script:phaseRoot 'pipelines/azure-pipelines-session-host-manual.yml'
    $script:settingsPath = Join-Path $TestDrive 'settings.json'
    '{"organization":"example-org","project":"example project","pipelineId":7,"branch":"main"}' |
        Set-Content -LiteralPath $script:settingsPath
    $env:AZURE_DEVOPS_EXT_PAT = 'fixture-pat'
    $script:request = @{
        Workload = 'example-workload'
        RitmNumber = 'RITM0012345'
        RequestedForUpn = 'user@contoso.com'
        AuthMethod = 'Pat'
        SettingsPath = $script:settingsPath
        InformationAction = 'SilentlyContinue'
    }
    # Pester matches filters against the Body string given to Invoke-RestMethod.
    function Test-RealRunBody { param([string]$Body) $Body -match '"previewRun":false' }
    function Test-PreviewBody { param([string]$Body) $Body -match '"previewRun":true' }
}

AfterAll {
    Remove-Item -Path Env:AZURE_DEVOPS_EXT_PAT -ErrorAction SilentlyContinue
}

Describe 'Start-AvdBuild' {
    BeforeEach {
        Mock Start-Sleep {}
        Mock Invoke-RestMethod { [pscustomobject]@{ value = @() } } -ParameterFilter { $Method -eq 'GET' -and $Uri -match '/runs\?' }
        Mock Invoke-RestMethod { [pscustomobject]@{ finalYaml = 'stages: []' } } -ParameterFilter { $Method -eq 'POST' -and (Test-PreviewBody $Body) }
        Mock Invoke-RestMethod {
            [pscustomobject]@{ id = 42; state = 'inProgress'; _links = [pscustomobject]@{ web = [pscustomobject]@{ href = 'https://example.test/run/42' } } }
        } -ParameterFilter { $Method -eq 'POST' -and (Test-RealRunBody $Body) }
    }

    Context 'WhatIf' {
        It 'creates no run and reports NotQueued' {
            $result = & $script:starter @script:request -WhatIf
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' -and (Test-RealRunBody $Body) }
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and (Test-PreviewBody $Body) }
            $result.State | Should -Be 'NotQueued'
            $result.HostName | Should -Be 'AVD0012345'
        }

        It 'still refuses a duplicate' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{ value = @([pscustomobject]@{ name = 'RITM0012345-20261030.1'; state = 'inProgress' }) }
            } -ParameterFilter { $Method -eq 'GET' -and $Uri -match '/runs\?' }
            { & $script:starter @script:request -WhatIf } | Should -Throw '*in progress*'
        }
    }

    Context 'Queueing' {
        It 'sends only the three parameters, normalized, for the configured branch' {
            $result = & $script:starter @script:request -Workload 'Example-Workload' -RitmNumber ' ritm0012345 ' -RequestedForUpn 'User@Contoso.com' -Confirm:$false
            $result.RunId | Should -Be 42
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                if ($Method -ne 'POST' -or -not (Test-RealRunBody $Body)) { return $false }
                $sent = $Body | ConvertFrom-Json
                $names = @($sent.templateParameters.PSObject.Properties.Name | Sort-Object)
                ($names -join ',') -eq 'requestedForUpn,ritmNumber,workload' -and
                $sent.templateParameters.workload -ceq 'example-workload' -and
                $sent.templateParameters.ritmNumber -ceq 'RITM0012345' -and
                $sent.templateParameters.requestedForUpn -ceq 'user@contoso.com' -and
                $sent.resources.repositories.self.refName -ceq 'refs/heads/main' -and
                $Uri -eq 'https://dev.azure.com/example-org/example%20project/_apis/pipelines/7/runs?api-version=7.1'
            }
        }

        It 'never places the PAT in the URI or body' {
            & $script:starter @script:request -Confirm:$false | Out-Null
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { "$Uri $Body" -match 'fixture-pat' }
        }
    }

    Context 'Duplicate protection' {
        BeforeEach {
            Mock Invoke-RestMethod {
                [pscustomobject]@{ value = @([pscustomobject]@{ name = 'RITM0012345-20261030.1'; state = 'completed'; result = 'succeeded' }) }
            } -ParameterFilter { $Method -eq 'GET' -and $Uri -match '/runs\?' }
        }

        It 'refuses a RITM that already succeeded' {
            { & $script:starter @script:request -Confirm:$false } | Should -Throw '*already succeeded*'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }

        It 'allows it with -Force' {
            (& $script:starter @script:request -Force -Confirm:$false).RunId | Should -Be 42
        }

        It 'does not match a longer RITM number' {
            (& $script:starter @script:request -RitmNumber 'RITM001234' -Confirm:$false).RunId | Should -Be 42
        }

        It 'allows a retry after a failed run' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{ value = @([pscustomobject]@{ name = 'RITM0012345-20261030.1'; state = 'completed'; result = 'failed' }) }
            } -ParameterFilter { $Method -eq 'GET' -and $Uri -match '/runs\?' }
            (& $script:starter @script:request -Confirm:$false).RunId | Should -Be 42
        }
    }

    Context 'Waiting' {
        It 'returns a work note on success' {
            Mock Invoke-RestMethod { [pscustomobject]@{ state = 'completed'; result = 'succeeded' } } -ParameterFilter { $Method -eq 'GET' -and $Uri -match '/runs/42\?' }
            $result = & $script:starter @script:request -Wait -Confirm:$false
            $result.Result | Should -Be 'succeeded'
            $result.WorkNote | Should -BeLike '*AVD0012345*enrolled in Intune*assigned to user@contoso.com*'
        }

        It 'emits the summary and then fails on a failed run' {
            Mock Invoke-RestMethod { [pscustomobject]@{ state = 'completed'; result = 'failed' } } -ParameterFilter { $Method -eq 'GET' -and $Uri -match '/runs/42\?' }
            { & $script:starter @script:request -Wait -Confirm:$false } | Should -Throw '*did not finish successfully*'
        }
    }

    Context 'Error paths' {
        It 'stops when Azure DevOps returns a sign-in page' {
            Mock Invoke-RestMethod { '<html>sign in</html>' } -ParameterFilter { $Method -eq 'GET' }
            { & $script:starter @script:request -Confirm:$false } | Should -Throw '*did not accept the credential*'
        }

        It 'stops on a missing settings file' {
            { & $script:starter @script:request -SettingsPath (Join-Path $TestDrive 'absent.json') -WhatIf } | Should -Throw '*Settings file not found*'
        }

        It 'stops on incomplete settings' {
            $partial = Join-Path $TestDrive 'partial.json'
            '{"organization":"example-org"}' | Set-Content -LiteralPath $partial
            { & $script:starter @script:request -SettingsPath $partial -WhatIf } | Should -Throw "*missing 'project'*"
        }

        It 'stops before any call on bad input' {
            { & $script:starter @script:request -RitmNumber 'REQ001' -WhatIf } | Should -Throw '*RITM followed by*'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }

        It 'rejects a workload that could alter the variable group name' {
            { & $script:starter @script:request -Workload 'a/../b' -WhatIf } | Should -Throw
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }
    }
}

Describe 'Wait-AvdEnrollment' {
    BeforeAll {
        $script:enrollment = Join-Path $script:phaseRoot 'scripts/Wait-AvdEnrollment.ps1'
        $script:reportPath = Join-Path $TestDrive 'enrollment.json'
        $script:wait = @{ VmName = 'AVD0012345'; ReportPath = $script:reportPath; TimeoutMinutes = 1; PollSeconds = 15 }
        function az { }
        function Get-EnrollmentReport { Get-Content -LiteralPath $script:reportPath -Raw | ConvertFrom-Json }
    }

    BeforeEach {
        Mock az { $global:LASTEXITCODE = 0; 'fixture-token' }
        Mock Start-Sleep {}
        Mock Invoke-RestMethod {
            [pscustomobject]@{ value = @([pscustomobject]@{ deviceId = 'device-1'; displayName = 'AVD0012345'; accountEnabled = $true; trustType = 'AzureAd' }) }
        } -ParameterFilter { $Uri -match '/v1\.0/devices\?' }
        Mock Invoke-RestMethod {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'managed-1'; deviceName = 'AVD0012345'; managementAgent = 'mdm'; azureADDeviceId = 'device-1' }) }
        } -ParameterFilter { $Uri -match '/managedDevices\?' }
    }

    It 'passes when the Entra-joined device is enrolled in Intune' {
        & $script:enrollment @script:wait | Should -BeLike '*enrolled in Intune*'
        (Get-EnrollmentReport).result | Should -Be 'Enrolled'
    }

    It 'only reads from Microsoft Graph' {
        & $script:enrollment @script:wait | Out-Null
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Method -ne 'Get' }
    }

    It 'fails with the pending state when the wait ends' {
        Mock Invoke-RestMethod { [pscustomobject]@{ value = @() } } -ParameterFilter { $Uri -match '/managedDevices\?' }
        { & $script:enrollment @script:wait -TimeoutMinutes 0 } | Should -Throw '*Entra joined: True. Intune enrolled: False*'
        (Get-EnrollmentReport).result | Should -Be 'TimedOut'
    }

    Context 'Failures' {
        BeforeEach {
            # Stops the script after its first poll so the report can be inspected.
            Mock Start-Sleep { throw 'stop-after-first-poll' }
        }

        It 'does not pass a workplace-registered device' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{ value = @([pscustomobject]@{ deviceId = 'device-1'; displayName = 'AVD0012345'; accountEnabled = $true; trustType = 'Workplace' }) }
            } -ParameterFilter { $Uri -match '/v1\.0/devices\?' }
            { & $script:enrollment @script:wait } | Should -Throw '*stop-after-first-poll*'
            (Get-EnrollmentReport).entraJoined | Should -BeFalse
        }

        It 'does not pass a stale Intune record from another device' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{ value = @([pscustomobject]@{ id = 'old'; deviceName = 'AVD0012345'; managementAgent = 'mdm'; azureADDeviceId = 'device-old' }) }
            } -ParameterFilter { $Uri -match '/managedDevices\?' }
            { & $script:enrollment @script:wait } | Should -Throw '*stop-after-first-poll*'
            $report = Get-EnrollmentReport
            $report.entraJoined | Should -BeTrue
            $report.intuneEnrolled | Should -BeFalse
        }

        It 'does not pass an unknown management agent' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{ value = @([pscustomobject]@{ id = 'managed-1'; deviceName = 'AVD0012345'; managementAgent = 'unknown'; azureADDeviceId = 'device-1' }) }
            } -ParameterFilter { $Uri -match '/managedDevices\?' }
            { & $script:enrollment @script:wait } | Should -Throw '*stop-after-first-poll*'
            (Get-EnrollmentReport).intuneEnrolled | Should -BeFalse
        }

        It 'retries a Graph failure and never reports the token' {
            Mock Invoke-RestMethod { throw 'Graph returned 503' } -ParameterFilter { $Uri -match '/v1\.0/devices\?' }
            { & $script:enrollment @script:wait -WarningAction SilentlyContinue } | Should -Throw '*stop-after-first-poll*'
            $reportText = Get-Content -LiteralPath $script:reportPath -Raw
            $reportText | Should -BeLike '*Graph returned 503*'
            $reportText | Should -Not -BeLike '*fixture-token*'
        }
    }

    It 'rejects a host name that could alter the OData filter' {
        { & $script:enrollment -VmName "AVD1' or 1 eq 1" -ReportPath $script:reportPath } | Should -Throw
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
}

Describe 'Test-AvdManualRequest' {
    It 'derives the host name, preserves zeros, and normalizes' {
        $output = & $script:validator -RitmNumber ' ritm0012345 ' -RequestedForUpn 'User@Contoso.com'
        $output | Should -Contain '##vso[task.setvariable variable=ritmNumber;isOutput=true]RITM0012345'
        $output | Should -Contain '##vso[task.setvariable variable=hostName;isOutput=true]AVD0012345'
        $output | Should -Contain '##vso[task.setvariable variable=requestedForUpn;isOutput=true]user@contoso.com'
    }

    It 'rejects <Name>' -TestCases @(
        @{ Name = 'a non-RITM value'; Ritm = 'REQ0012345'; Upn = 'user@contoso.com' }
        @{ Name = '13 digits'; Ritm = 'RITM1234567890123'; Upn = 'user@contoso.com' }
        @{ Name = 'an embedded command'; Ritm = "RITM1'; Remove-Item x; '"; Upn = 'user@contoso.com' }
        @{ Name = 'a trailing logging command'; Ritm = 'RITM1'; Upn = "user@contoso.com`n##vso[task.setvariable variable=x]y" }
        @{ Name = 'a macro'; Ritm = 'RITM1'; Upn = '$(System.AccessToken)@contoso.com' }
        @{ Name = 'an apostrophe'; Ritm = 'RITM1'; Upn = "o'neil@contoso.com" }
        @{ Name = 'no domain'; Ritm = 'RITM1'; Upn = 'jsmith' }
    ) {
        { & $script:validator -RitmNumber $Ritm -RequestedForUpn $Upn } | Should -Throw
    }

    It 'agrees with Start-AvdBuild on the input patterns' {
        $starterText = Get-Content -LiteralPath $script:starter -Raw
        $validatorText = Get-Content -LiteralPath $script:validator -Raw
        foreach ($pattern in @("'\ARITM(?<digits>[0-9]{1,12})\z'", "'\A[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\z'")) {
            $starterText.Contains($pattern) | Should -BeTrue
            $validatorText.Contains($pattern) | Should -BeTrue
        }
    }
}

Describe 'Manual pipeline' {
    BeforeAll { $script:pipeline = Get-Content -LiteralPath $script:pipelinePath -Raw }

    It 'has no ServiceNow dependency' {
        $script:pipeline | Should -Not -Match '(?i)avd-poc-servicenow|Update-ServiceNowRitm|\bSN_[A-Z]'
    }

    It 'exposes exactly the three technician parameters' {
        $names = @([regex]::Matches($script:pipeline, '(?m)^  - name: (\w+)\r?\n    displayName:') | ForEach-Object { $_.Groups[1].Value })
        ($names -join ',') | Should -Be 'workload,ritmNumber,requestedForUpn'
    }

    It 'restricts workload to a list' {
        $script:pipeline | Should -Match '(?m)^  - name: workload\r?\n(    .*\r?\n)*?    values:'
    }

    It 'uses raw parameters only for the run name, variable group, and validation step' {
        $uses = @([regex]::Matches($script:pipeline, '(?m)^.*\$\{\{\s*parameters\..*$') | ForEach-Object { $_.Value.Trim() })
        $uses | Should -HaveCount 4
        $uses[0] | Should -BeLike 'name: *'
        $uses[1] | Should -Be '- group: avd-phase01-${{ parameters.workload }}'
        $uses[2] | Should -BeLike 'RITM_NUMBER: *'
        $uses[3] | Should -BeLike 'REQUESTED_FOR_UPN: *'
    }

    It 'gates the build on Intune enrollment after readiness' {
        $script:pipeline.IndexOf('Wait-AvdEnrollment.ps1') | Should -BeGreaterThan $script:pipeline.IndexOf('Wait-AvdReadiness.ps1')
    }
}

Describe 'Workload configuration' {
    BeforeAll {
        $script:access = Get-Content -LiteralPath (Join-Path $script:phaseRoot 'infra/access.bicep') -Raw
        $script:variables = Get-Content -LiteralPath (Join-Path $script:phaseRoot 'config/avd-phase01-workload.variables.example.yml') -Raw
    }

    It 'turns off the app and Defender gates' {
        $script:variables | Should -Match "AVD_REQUIRED_APP_NAMES_JSON: '\[\]'"
        $script:variables | Should -Match "AVD_REQUIRE_MDE: 'false'"
    }

    It 'limits role assignment to the two AVD roles for users' {
        $script:access | Should -Match "assignableRoleIds = 'fb879df8-f326-4884-b1cf-06f3ad86be52, 1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63'"
        $script:access | Should -Match 'PrincipalType\] ForAnyOfAnyValues:StringEqualsIgnoreCase'
        @([regex]::Matches($script:access, 'condition: assignmentCondition')).Count | Should -Be @([regex]::Matches($script:access, "'Microsoft.Authorization/roleAssignments/write'\r?\n")).Count
    }

    It 'grants no delete action, Run Command, or network write' {
        $script:access | Should -Not -Match '/delete'
        $script:access | Should -Not -Match 'runCommand'
        $script:access | Should -Not -Match 'Microsoft\.Network/virtualNetworks/[^''"]*write'
    }

    It 'calls only scripts that exist in the repository' {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $script:phaseRoot)
        $paths = @([regex]::Matches($script:pipeline, "'(AzureVirtualDesktopPoc/[^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $paths.Count | Should -BeGreaterThan 4
        foreach ($path in $paths) { Join-Path $repoRoot $path | Should -Exist }
    }
}
