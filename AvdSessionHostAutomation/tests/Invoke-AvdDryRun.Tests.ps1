#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0'; MaximumVersion = '5.99.99' }

BeforeAll {
    $script:dryRun = Join-Path (Split-Path -Parent $PSScriptRoot) 'examples/Invoke-AvdDryRun.example.ps1'

    # The dry run shells out to the Azure CLI through New-AvdSessionHost.
    function az { }

    $script:sub = '/subscriptions/sub-1/resourceGroups/rg-hosts/providers'
    function ConvertTo-WhatIfJson {
        param([object[]]$Changes)
        return (@{ status = 'Succeeded'; changes = $Changes } | ConvertTo-Json -Depth 20 -Compress)
    }
    function Get-ChangeFixture {
        param([string]$Type, [string]$Resource, [object]$After = $null)
        return @{ changeType = $Type; resourceId = "$script:sub/$Resource"; after = $After }
    }
    $script:vmAfter = @{
        identity = @{ type = 'SystemAssigned' }
        properties = @{ storageProfile = @{ imageReference = @{ id = '/subscriptions/sub-1/providers/Microsoft.Compute/galleries/g/images/i/versions/1.0.0' } } }
    }
    $script:nicAfter = @{ properties = @{ ipConfigurations = @(@{ name = 'ipconfig1'; properties = @{ privateIPAllocationMethod = 'Dynamic' } }) } }
    $script:cleanChanges = @(
        (Get-ChangeFixture 'Create' 'Microsoft.Compute/virtualMachines/AVD0012345' $script:vmAfter)
        (Get-ChangeFixture 'Create' 'Microsoft.Compute/virtualMachines/AVD0012345/extensions/AADLoginForWindows')
        (Get-ChangeFixture 'Create' 'Microsoft.Compute/virtualMachines/AVD0012345/extensions/MicrosoftPowershellDSC')
        (Get-ChangeFixture 'Create' 'Microsoft.Network/networkInterfaces/avd0012345-nic' $script:nicAfter)
        (Get-ChangeFixture 'Ignore' 'Microsoft.Compute/virtualMachines/AVD0099999')
    )

    # Mock bodies cannot see variables set here, so the what-if fixture is
    # handed over through a TestDrive file.
    function Use-AzMock {
        param([string]$WhatIfJson)
        Set-Content -LiteralPath (Join-Path $TestDrive 'what-if-fixture.json') -Value $WhatIfJson
        Mock az {
            $global:LASTEXITCODE = 0
            $command = $args -join ' '
            switch -Wildcard ($command) {
                'account show*' { '{"id":"sub-1","tenantId":"tenant-1"}' }
                'rest --method GET --url https://graph.microsoft.com/v1.0/users/*' { '{"id":"user-1","userPrincipalName":"testuser@contoso.com","accountEnabled":true}' }
                'vm list*' { '[]' }
                'rest --method POST --url *retrieveRegistrationToken*' { '{"token":"fixture-token","expirationTime":"2099-01-01T00:00:00Z"}' }
                'deployment group what-if*' { Get-Content -LiteralPath (Join-Path $TestDrive 'what-if-fixture.json') -Raw }
                default { throw "Unexpected az call in test: az $command" }
            }
        }
    }
}

Describe 'Invoke-AvdDryRun example' {
    BeforeEach {
        $script:arguments = @{
            RitmNumber = 'RITM0012345'
            RequestedForUpn = 'TestUser@contoso.com'
            ReportDirectory = Join-Path $TestDrive 'dryrun'
            Workload = [ordered]@{
                SubscriptionId = 'sub-1'
                TenantId = 'tenant-1'
                ResourceGroupName = 'rg-hosts'
                PlatformResourceGroupName = 'rg-avd'
                HostPoolName = 'vdpool-prod'
                SubnetId = '/subscriptions/sub-1/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet'
                EnvironmentName = 'Production'
                Location = 'centralus'
                VmSize = 'Standard_E4bs_v5'
                OsDiskSku = 'StandardSSD_LRS'
                ImageSourceType = 'Gallery'
                GalleryImageDefinitionId = '/subscriptions/sub-1/providers/Microsoft.Compute/galleries/g/images/i'
                GalleryImageVersionId = '/subscriptions/sub-1/providers/Microsoft.Compute/galleries/g/images/i/versions/1.0.0'
                AvdDscConfigurationUri = 'https://example.test/dsc.zip'
            }
        }
    }

    It 'refuses to run while the template placeholders are unfilled, before any Azure call' {
        Use-AzMock -WhatIfJson (ConvertTo-WhatIfJson $script:cleanChanges)
        $arguments.Remove('Workload')
        { & $script:dryRun @arguments *>&1 | Out-Null } | Should -Throw '*Replace the placeholders*SubscriptionId*'
        Should -Invoke az -Times 0 -Exactly
    }

    It 'passes a clean what-if, derives the host name, and never deploys' {
        Use-AzMock -WhatIfJson (ConvertTo-WhatIfJson $script:cleanChanges)
        $output = & $script:dryRun @arguments *>&1 | Out-String
        $output | Should -BeLike '*Dry run PASSED for AVD0012345 (RITM0012345, testuser@contoso.com)*'
        $output | Should -BeLike '*Existing resources left alone (Ignore): 1*'
        $output | Should -BeLike '*Identity:  SystemAssigned*'
        $output | Should -Not -BeLike '*fixture-token*'
        Test-Path -LiteralPath (Join-Path $TestDrive 'dryrun/session-host-what-if-AVD0012345.json') | Should -BeTrue
        Should -Invoke az -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like 'deployment group what-if*' }
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like 'deployment group create*' }
        Should -Invoke az -Times 0 -Exactly -ParameterFilter { ($args -join ' ') -like '*--method PATCH*' }
    }

    It 'fails when the what-if touches a resource outside the expected four' {
        $changes = $script:cleanChanges + @(Get-ChangeFixture 'Modify' 'Microsoft.Network/virtualNetworks/vnet/subnets/snet')
        Use-AzMock -WhatIfJson (ConvertTo-WhatIfJson $changes)
        { & $script:dryRun @arguments *>&1 | Out-Null } | Should -Throw '*Dry run FAILED*'
    }

    It 'fails when an expected resource is modified rather than created' {
        $changes = @($script:cleanChanges | ForEach-Object { $_.Clone() })
        $changes[0].changeType = 'Modify'
        Use-AzMock -WhatIfJson (ConvertTo-WhatIfJson $changes)
        { & $script:dryRun @arguments *>&1 | Out-Null } | Should -Throw '*Dry run FAILED*'
    }

    It 'fails when an expected resource is missing' {
        Use-AzMock -WhatIfJson (ConvertTo-WhatIfJson @($script:cleanChanges | Select-Object -SkipLast 2))
        { & $script:dryRun @arguments *>&1 | Out-Null } | Should -Throw '*Dry run FAILED*'
    }

    It 'fails when the NIC would get a public IP' {
        $publicNic = @{ properties = @{ ipConfigurations = @(@{ name = 'ipconfig1'; properties = @{ publicIPAddress = @{ id = '/pip' } } }) } }
        $changes = @($script:cleanChanges | ForEach-Object { $_.Clone() })
        $changes[3].after = $publicNic
        Use-AzMock -WhatIfJson (ConvertTo-WhatIfJson $changes)
        { & $script:dryRun @arguments *>&1 | Out-Null } | Should -Throw '*Dry run FAILED*'
    }
}
