#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0'; MaximumVersion = '5.99.99' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:starter = Join-Path $script:repoRoot 'technician/Start-AvdBuild.ps1'
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
