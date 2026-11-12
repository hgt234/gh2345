#Requires -Version 7.2

<#
.SYNOPSIS
    Waits until a session host passes the production readiness gates and writes
    a JSON report for the build.

.DESCRIPTION
    Polls until every enabled gate passes or the timeout expires:

    - azureVm: the VM deployment succeeded and the VM is running.
    - entraJoined: an enabled Entra device with trust type AzureAd exists for
      the host name.
    - intuneEnrolled (optional): an Intune record exists whose Entra device ID
      matches the joined device, so a stale record with the same name cannot
      pass. Intune then delivers policy, applications, and Defender onboarding.
    - intuneCompliant (optional): that same Intune record reports compliant.
    - requiredApps: every configured application DisplayName is installed,
      verified by a fixed read-only inventory script through VM Run Command.
    - mde (optional): Defender for Endpoint shows the device Onboarded and
      Active.
    - avd: the session host is Available in the host pool.

    The report is rewritten after every poll so a failed or cancelled build
    still publishes the latest state. Azure, Entra, Intune, and AVD are only
    read. The single exception is VM Run Command, which executes the fixed
    read-only inventory script inside the guest as SYSTEM; it changes nothing
    but is a privileged operation and is why the readiness identity needs
    runCommand/action.

.PARAMETER SubscriptionId
    Target subscription ID.

.PARAMETER SessionHostResourceGroupName
    Resource group holding the VM.

.PARAMETER PlatformResourceGroupName
    Resource group holding the existing host pool.

.PARAMETER HostPoolName
    Existing AVD personal host-pool name.

.PARAMETER VmName
    Session-host name, AVD followed by 1-12 digits.

.PARAMETER RequiredAppName
    Exact installed application DisplayName values that must all be present.
    Empty disables the gate.

.PARAMETER RequireIntuneEnrolled
    Gate on Intune enrollment of the joined device.

.PARAMETER RequireIntuneCompliant
    Gate on Intune compliance. Implies the enrollment gate.

.PARAMETER RequireMde
    Gate on Defender for Endpoint onboarding.

.PARAMETER TimeoutMinutes
    Maximum wait before the script fails.

.PARAMETER PollSeconds
    Seconds between polls.

.PARAMETER MdeApiBaseUrl
    Defender for Endpoint API base URL.

.PARAMETER ReportPath
    JSON report written after every poll and published with the pipeline run.

.EXAMPLE
    ./Wait-AvdReadiness.ps1 -SubscriptionId $sub -SessionHostResourceGroupName rg-avd-hosts -PlatformResourceGroupName rg-avd -HostPoolName vdpool-prod -VmName AVD0012345 -RequiredAppName @('Example App') -RequireIntuneEnrolled

.NOTES
    Needs Graph application permissions Device.Read.All and
    DeviceManagementManagedDevices.Read.All, plus WindowsDefenderATP
    Machine.Read.All when -RequireMde is used.
    https://learn.microsoft.com/graph/api/resources/device
    https://learn.microsoft.com/graph/api/resources/intune-devices-manageddevice
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$SessionHostResourceGroupName,
    [Parameter(Mandatory)][string]$PlatformResourceGroupName,
    [Parameter(Mandatory)][string]$HostPoolName,
    [Parameter(Mandatory)][ValidatePattern('\AAVD[0-9]{1,12}\z')][string]$VmName,
    [string[]]$RequiredAppName = @(),
    [switch]$RequireIntuneEnrolled,
    [switch]$RequireIntuneCompliant,
    [switch]$RequireMde,
    [ValidateRange(5, 180)][int]$TimeoutMinutes = 100,
    [ValidateRange(15, 300)][int]$PollSeconds = 60,
    [string]$MdeApiBaseUrl = 'https://api.securitycenter.microsoft.com',
    [string]$ReportPath = (Join-Path $PWD 'avd-readiness.json')
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Invoke-AzCliJson {
    param([Parameter(Mandatory)][string[]]$ArgumentList)
    $raw = & az @ArgumentList --only-show-errors --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: az $($ArgumentList -join ' ')`n$($raw -join [Environment]::NewLine)"
    }
    $text = $raw -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 100
}

function Save-ReadinessReport {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Report,
        [Parameter(Mandatory)][string]$Path
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

# Compliance can only be evaluated on the enrolled device record.
$checkEnrollment = $RequireIntuneEnrolled -or $RequireIntuneCompliant

$deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
$hostPoolId = "/subscriptions/$SubscriptionId/resourceGroups/$PlatformResourceGroupName/providers/Microsoft.DesktopVirtualization/hostPools/$HostPoolName"
$graphToken = $null
$graphTokenRefreshUtc = [DateTime]::MinValue
$mdeToken = $null
$mdeTokenRefreshUtc = [DateTime]::MinValue
$appsVerified = $RequiredAppName.Count -eq 0
$appDetails = $null
$report = [ordered]@{
    schemaVersion = 2
    vmName = $VmName
    startedUtc = [DateTime]::UtcNow.ToString('o')
    deadlineUtc = $deadline.ToString('o')
    requiredApps = @($RequiredAppName)
    requireIntuneEnrolled = [bool]$checkEnrollment
    requireIntuneCompliant = [bool]$RequireIntuneCompliant
    requireMde = [bool]$RequireMde
    result = 'Waiting'
    checks = @{}
    errors = @()
}

while ([DateTime]::UtcNow -lt $deadline) {
    $checks = [ordered]@{
        azureVm = $false
        entraJoined = $false
        intuneEnrolled = -not $checkEnrollment
        intuneCompliant = -not $RequireIntuneCompliant
        requiredApps = $appsVerified
        mde = -not $RequireMde
        avd = $false
    }
    $details = [ordered]@{}
    $pollErrors = [System.Collections.Generic.List[string]]::new()

    try {
        $vm = Invoke-AzCliJson -ArgumentList @(
            'vm', 'get-instance-view', '--resource-group', $SessionHostResourceGroupName,
            '--name', $VmName, '--subscription', $SubscriptionId
        )
        $powerState = [string](@($vm.instanceView.statuses | Where-Object code -Like 'PowerState/*') | Select-Object -First 1).code
        $checks.azureVm = [string]$vm.provisioningState -ieq 'Succeeded' -and $powerState -ieq 'PowerState/running'
        $details.azureVm = @{ provisioningState = $vm.provisioningState; powerState = $powerState }
    }
    catch { $pollErrors.Add("Azure VM: $($_.Exception.Message)") }

    $joinedDeviceIds = @()
    try {
        if (-not $graphToken -or [DateTime]::UtcNow -ge $graphTokenRefreshUtc) {
            $tokenResult = Invoke-AzCliJson -ArgumentList @(
                'account', 'get-access-token', '--resource', 'https://graph.microsoft.com',
                '--subscription', $SubscriptionId
            )
            $graphToken = [string]$tokenResult.accessToken
            $graphTokenRefreshUtc = [DateTime]::UtcNow.AddMinutes(40)
        }
        $filter = [Uri]::EscapeDataString("displayName eq '$VmName'")
        $entra = Invoke-RestMethod -Method Get `
            -Uri "https://graph.microsoft.com/v1.0/devices?`$filter=$filter&`$select=id,deviceId,displayName,accountEnabled,trustType" `
            -Headers @{ Authorization = "Bearer $graphToken" }
        $joinedDevices = @($entra.value | Where-Object {
            $_.displayName -ceq $VmName -and $_.accountEnabled -eq $true -and [string]$_.trustType -ieq 'AzureAd'
        })
        $joinedDeviceIds = @($joinedDevices | ForEach-Object { [string]$_.deviceId })
        $checks.entraJoined = $joinedDeviceIds.Count -gt 0
        if ($joinedDevices.Count -gt 0) {
            $first = $joinedDevices[0]
            $details.entra = @{ id = $first.id; deviceId = $first.deviceId; trustType = $first.trustType; accountEnabled = $first.accountEnabled }
        }
    }
    catch { $pollErrors.Add("Entra: $($_.Exception.Message)") }

    if ($checkEnrollment) {
        try {
            $filter = [Uri]::EscapeDataString("deviceName eq '$VmName'")
            $intune = Invoke-RestMethod -Method Get `
                -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=$filter&`$select=id,deviceName,complianceState,managementAgent,lastSyncDateTime,azureADDeviceId" `
                -Headers @{ Authorization = "Bearer $graphToken" }
            # Matching on the Entra device ID stops a stale Intune record with
            # the same name from passing the gate.
            $managedDevice = @($intune.value | Where-Object {
                $joinedDeviceIds -icontains [string]$_.azureADDeviceId -and
                [string]$_.managementAgent -notin @('', 'unknown')
            }) | Sort-Object lastSyncDateTime -Descending | Select-Object -First 1
            $checks.intuneEnrolled = $null -ne $managedDevice
            if ($managedDevice) {
                $checks.intuneCompliant = -not $RequireIntuneCompliant -or [string]$managedDevice.complianceState -ieq 'compliant'
                $details.intune = @{
                    id = $managedDevice.id
                    complianceState = $managedDevice.complianceState
                    managementAgent = $managedDevice.managementAgent
                    lastSyncDateTime = $managedDevice.lastSyncDateTime
                }
            }
            else {
                $checks.intuneCompliant = -not $RequireIntuneCompliant
            }
        }
        catch { $pollErrors.Add("Intune: $($_.Exception.Message)") }
    }

    if (-not $appsVerified -and $checks.azureVm) {
        try {
            $requiredJson = $RequiredAppName | ConvertTo-Json -Compress
            $requiredBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($requiredJson))
            $guestScript = @'
$requiredJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__REQUIRED_APPS__'))
$required = @($requiredJson | ConvertFrom-Json)
$registryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$detected = @(Get-ItemProperty -Path $registryPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName } |
    ForEach-Object { [string]$_.DisplayName } |
    Sort-Object -Unique)
$missing = @($required | Where-Object { $detected -inotcontains [string]$_ })
$payload = @{ detected = $detected; missing = $missing } | ConvertTo-Json -Compress
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
Write-Output "AVD_APP_CHECK:$encoded"
'@.Replace('__REQUIRED_APPS__', $requiredBase64)
            $guestScriptPath = Join-Path ([IO.Path]::GetTempPath()) "avd-app-check-$([Guid]::NewGuid().ToString('N')).ps1"
            try {
                $guestScript | Set-Content -LiteralPath $guestScriptPath -Encoding utf8
                $runCommand = Invoke-AzCliJson -ArgumentList @(
                    'vm', 'run-command', 'invoke',
                    '--resource-group', $SessionHostResourceGroupName,
                    '--name', $VmName,
                    '--subscription', $SubscriptionId,
                    '--command-id', 'RunPowerShellScript',
                    '--scripts', "@$guestScriptPath"
                )
            }
            finally {
                Remove-Item -LiteralPath $guestScriptPath -Force -ErrorAction SilentlyContinue
            }
            $message = @($runCommand.value | ForEach-Object { [string]$_.message }) -join [Environment]::NewLine
            $payloadMatch = [regex]::Match($message, 'AVD_APP_CHECK:(?<payload>[A-Za-z0-9+/=]+)')
            if (-not $payloadMatch.Success) { throw 'The guest application check returned no parseable result.' }
            $appJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloadMatch.Groups['payload'].Value))
            $appDetails = $appJson | ConvertFrom-Json -Depth 20
            $appsVerified = @($appDetails.missing).Count -eq 0
            $checks.requiredApps = $appsVerified
        }
        catch { $pollErrors.Add("Required apps: $($_.Exception.Message)") }
    }
    if ($appDetails) {
        $details.requiredApps = @{ missing = @($appDetails.missing); detectedCount = @($appDetails.detected).Count }
    }

    if ($RequireMde -and $joinedDeviceIds.Count -gt 0) {
        try {
            if (-not $mdeToken -or [DateTime]::UtcNow -ge $mdeTokenRefreshUtc) {
                $tokenResult = Invoke-AzCliJson -ArgumentList @(
                    'account', 'get-access-token', '--resource', $MdeApiBaseUrl,
                    '--subscription', $SubscriptionId
                )
                $mdeToken = [string]$tokenResult.accessToken
                $mdeTokenRefreshUtc = [DateTime]::UtcNow.AddMinutes(40)
            }
            $mdeResponse = Invoke-RestMethod -Method Get `
                -Uri "$MdeApiBaseUrl/api/machines" `
                -Headers @{ Authorization = "Bearer $mdeToken" }
            $mdeMachine = @($mdeResponse.value | Where-Object { $joinedDeviceIds -icontains [string]$_.aadDeviceId }) |
                Sort-Object lastSeen -Descending | Select-Object -First 1
            $checks.mde = $null -ne $mdeMachine -and [string]$mdeMachine.onboardingStatus -ieq 'Onboarded' -and [string]$mdeMachine.healthStatus -ieq 'Active'
            if ($mdeMachine) {
                $details.mde = @{ id = $mdeMachine.id; onboardingStatus = $mdeMachine.onboardingStatus; healthStatus = $mdeMachine.healthStatus; lastSeen = $mdeMachine.lastSeen }
            }
        }
        catch { $pollErrors.Add("MDE: $($_.Exception.Message)") }
    }

    try {
        $sessionHostResponse = Invoke-AzCliJson -ArgumentList @(
            'rest', '--method', 'GET',
            '--url', "https://management.azure.com$hostPoolId/sessionHosts?api-version=2024-04-03"
        )
        $sessionHost = @($sessionHostResponse.value) | Where-Object {
            $leaf = (([string]$_.name -split '/')[-1] -split '\.')[0]
            $leaf -ieq $VmName
        } | Select-Object -First 1
        $checks.avd = $null -ne $sessionHost -and [string]$sessionHost.properties.status -ieq 'Available'
        if ($sessionHost) {
            $details.avd = @{ id = $sessionHost.id; status = $sessionHost.properties.status; allowNewSession = $sessionHost.properties.allowNewSession }
        }
    }
    catch { $pollErrors.Add("AVD: $($_.Exception.Message)") }

    $report.checks = $checks
    $report.details = $details
    $report.errors = @($pollErrors)
    $report.lastCheckedUtc = [DateTime]::UtcNow.ToString('o')
    Save-ReadinessReport -Report $report -Path $ReportPath

    $pending = @($checks.Keys | Where-Object { -not $checks[$_] })
    if ($pending.Count -eq 0) {
        $report.result = 'Ready'
        $report.completedUtc = [DateTime]::UtcNow.ToString('o')
        Save-ReadinessReport -Report $report -Path $ReportPath
        Write-Output "'$VmName' passed every enabled readiness gate."
        return
    }

    Write-Output "Waiting for '$VmName': $($pending -join ', '). Next check in $PollSeconds seconds."
    Start-Sleep -Seconds $PollSeconds
}

$report.result = 'TimedOut'
$report.completedUtc = [DateTime]::UtcNow.ToString('o')
Save-ReadinessReport -Report $report -Path $ReportPath
throw "'$VmName' did not become ready within $TimeoutMinutes minutes. Pending checks: $((@($report.checks.Keys | Where-Object { -not $report.checks[$_] })) -join ', ')."
