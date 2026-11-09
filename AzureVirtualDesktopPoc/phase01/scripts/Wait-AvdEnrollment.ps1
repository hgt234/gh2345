#Requires -Version 5.1

<#
.SYNOPSIS
    Waits until a session host is Entra-joined and enrolled in Intune.

.DESCRIPTION
    Wait-AvdReadiness.ps1 checks Intune only when compliance is required, so a VM
    that never enrolled would pass. This Phase 01 gate requires an enabled Entra
    device with trust type AzureAd and an Intune record for that same device ID.
    Matching on the device ID stops a stale record with the same name from passing.
    Compliance is not required, because it depends on the client's policy timing.

    Read-only: this script changes nothing in Azure, Entra, or Intune.

.PARAMETER VmName
    Session-host name, AVD followed by 1-12 digits.

.PARAMETER ReportPath
    JSON report written after every check and published with the pipeline run.

.PARAMETER TimeoutMinutes
    Maximum wait before the script fails. 0 checks once.

.PARAMETER PollSeconds
    Seconds between checks.

.EXAMPLE
    ./Wait-AvdEnrollment.ps1 -VmName AVD0012345 -ReportPath ./enrollment.json

.NOTES
    Needs Graph application permissions Device.Read.All and
    DeviceManagementManagedDevices.Read.All on the signed-in Azure CLI identity.
    https://learn.microsoft.com/graph/api/resources/device
    https://learn.microsoft.com/graph/api/resources/intune-devices-manageddevice
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('\AAVD[0-9]{1,12}\z')][string]$VmName,
    [Parameter(Mandatory)][string]$ReportPath,
    [ValidateRange(0, 60)][int]$TimeoutMinutes = 30,
    [ValidateRange(15, 300)][int]$PollSeconds = 60
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-GraphHeader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # Azure CLI caches and renews the token, and writes warnings to stderr.
    $ErrorActionPreference = 'Continue'
    $token = & az account get-access-token --resource 'https://graph.microsoft.com' --query accessToken --output tsv 2>$null
    $tokenExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($tokenExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw 'Azure CLI did not return a Microsoft Graph token.'
    }
    return @{ Authorization = "Bearer $token" }
}

function Get-EnrollmentState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][hashtable]$Headers)

    $deviceFilter = [Uri]::EscapeDataString("displayName eq '$VmName'")
    $devices = Invoke-RestMethod -Method Get -Headers $Headers `
        -Uri "https://graph.microsoft.com/v1.0/devices?`$filter=$deviceFilter&`$select=deviceId,displayName,accountEnabled,trustType"
    $joined = @($devices.value | Where-Object {
        $_.displayName -ceq $VmName -and $_.accountEnabled -eq $true -and [string]$_.trustType -ieq 'AzureAd'
    })

    $managedFilter = [Uri]::EscapeDataString("deviceName eq '$VmName'")
    $managed = Invoke-RestMethod -Method Get -Headers $Headers `
        -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=$managedFilter&`$select=id,deviceName,managementAgent,azureADDeviceId"
    $joinedIds = @($joined | ForEach-Object { [string]$_.deviceId })
    $enrolled = @($managed.value | Where-Object {
        $joinedIds -icontains [string]$_.azureADDeviceId -and [string]$_.managementAgent -notin @('', 'unknown')
    }) | Select-Object -First 1

    return [pscustomobject]@{
        EntraJoined = $joinedIds.Count -gt 0
        IntuneEnrolled = $null -ne $enrolled
        EntraDeviceId = if ($enrolled) { [string]$enrolled.azureADDeviceId } else { $null }
        IntuneDeviceId = if ($enrolled) { [string]$enrolled.id } else { $null }
    }
}

$deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
$report = [ordered]@{ vmName = $VmName; result = 'Waiting'; entraJoined = $false; intuneEnrolled = $false; lastError = $null }

while ($true) {
    try {
        $state = Get-EnrollmentState -Headers (Get-GraphHeader)
        $report.entraJoined = $state.EntraJoined
        $report.intuneEnrolled = $state.IntuneEnrolled
        $report.entraDeviceId = $state.EntraDeviceId
        $report.intuneDeviceId = $state.IntuneDeviceId
        $report.lastError = $null
    }
    catch {
        # A temporary Graph failure should not fail a build that may still enroll.
        $report.lastError = $_.Exception.Message
        Write-Warning "Enrollment check failed and will be retried: $($report.lastError)"
    }
    if ($report.entraJoined -and $report.intuneEnrolled) { $report.result = 'Enrolled' }
    elseif ([DateTime]::UtcNow -ge $deadline) { $report.result = 'TimedOut' }
    $report | ConvertTo-Json | Set-Content -LiteralPath $ReportPath -Encoding UTF8

    if ($report.result -eq 'Enrolled') {
        Write-Output "'$VmName' is Entra-joined and enrolled in Intune."
        return
    }
    if ($report.result -eq 'TimedOut') {
        throw "'$VmName' did not finish enrollment within $TimeoutMinutes minutes. Entra joined: $($report.entraJoined). Intune enrolled: $($report.intuneEnrolled). Last error: $($report.lastError)"
    }
    Write-Output "Waiting for '$VmName'. Entra joined: $($report.entraJoined). Intune enrolled: $($report.intuneEnrolled)."
    Start-Sleep -Seconds $PollSeconds
}
