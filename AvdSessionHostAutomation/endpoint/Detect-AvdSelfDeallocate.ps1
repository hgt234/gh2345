#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Remediations detection script: reports whether this session host
    is idle and should deallocate itself.

.DESCRIPTION
    Pairs with Invoke-AvdSelfDeallocate.ps1 as the remediation script in one
    Intune Remediations script package, run hourly as SYSTEM in 64-bit
    PowerShell. Strictly read-only: it reads session state, uptime, and a
    local marker, and calls no Azure API.

    Exit codes:
      0  No action needed: a session exists (active or disconnected), the
         host has not been up MinimumUptimeMinutes yet, or a deallocation
         was scheduled during this boot within the last MarkerValidMinutes.
      1  Idle: no sessions and past the uptime threshold. Intune then runs
         the remediation, which re-checks every gate before acting.
      2  Detection itself failed; the output line carries the reason.
         Any exit code other than 1 keeps the remediation from running.

    The remediation does not deallocate directly: it schedules a deferred
    deallocation a few minutes out and writes a marker, so Intune can run
    this script again and upload the result while the VM is still up. That
    second run sees the marker and reports the issue as fixed. The marker
    lives in HKLM, which standard users cannot write. A marker from an
    earlier boot is ignored, and so is one older than MarkerValidMinutes,
    so a deallocation that never happened is retried on the next hourly run.

    Every output line ends with the last recorded self-deallocate result
    (scheduled, accepted, cancelled, or failed), when there is one. The
    deferred run itself cannot report to Intune, so this is where its
    outcome reaches the console: in the detection output of the next run.

    Intune passes no parameters to Remediations scripts; the defaults are
    the configuration. Keep MinimumUptimeMinutes, the registry names, and
    the shared functions identical to Invoke-AvdSelfDeallocate.ps1 (the
    Pester suite checks this).

.PARAMETER MinimumUptimeMinutes
    Minimum minutes since boot before the host counts as idle. Must match
    Invoke-AvdSelfDeallocate.ps1.

.PARAMETER MarkerValidMinutes
    How long after the remediation schedules a deallocation detection keeps
    reporting "already handled" during the same boot. Must exceed
    DeallocateDelayMinutes in Invoke-AvdSelfDeallocate.ps1.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Detect-AvdSelfDeallocate.ps1; $LASTEXITCODE

    Shows the verdict and exit code on a host. Read-only.

.NOTES
    Intune Remediations: a remediation runs only when detection exits 1.
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations
#>
[CmdletBinding()]
param(
    [ValidateRange(5, 1440)][int]$MinimumUptimeMinutes = 60,
    [ValidateRange(5, 240)][int]$MarkerValidMinutes = 30
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$markerKey = 'HKLM:\SOFTWARE\AvdSessionHostAutomation\SelfDeallocate'
$markerValueName = 'DeallocateScheduledUtc'
$resultValueName = 'LastResult'

function Get-ActiveSessionCount {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    # quser exits nonzero and writes to stderr when no user is logged on, so
    # stderr handling is relaxed for just this call.
    $ErrorActionPreference = 'Continue'
    $output = & quser 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($exitCode -ne 0 -or -not $output) { return 0 }
    $rows = @($output | Select-Object -Skip 1 | Where-Object { $_ -match '\S' })
    return $rows.Count
}

function Get-HostUptime {
    [CmdletBinding()]
    [OutputType([double])]
    param()

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    return ((Get-Date) - $os.LastBootUpTime).TotalMinutes
}

function Get-SelfDeallocateState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$MarkerName,
        [Parameter(Mandatory)][string]$ResultName
    )

    $state = [pscustomobject]@{ ScheduledUtc = $null; LastResult = $null }
    if (-not (Test-Path -LiteralPath $Key)) { return $state }
    $item = Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue
    if (-not $item) { return $state }
    $names = @($item.PSObject.Properties.Name)

    if ($names -contains $ResultName -and $item.$ResultName) {
        $state.LastResult = [string]$item.$ResultName
    }
    if ($names -contains $MarkerName) {
        $parsed = [datetime]::MinValue
        $styles = [Globalization.DateTimeStyles]::RoundtripKind
        if ([datetime]::TryParse([string]$item.$MarkerName, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
            $state.ScheduledUtc = $parsed.ToUniversalTime()
        }
    }
    return $state
}

try {
    $state = Get-SelfDeallocateState -Key $markerKey -MarkerName $markerValueName -ResultName $resultValueName
    $suffix = ''
    if ($state.LastResult) { $suffix = " Last self-deallocate: $($state.LastResult)" }

    $sessionCount = Get-ActiveSessionCount
    if ($sessionCount -gt 0) {
        Write-Output "In use: $sessionCount session(s) present.$suffix"
        exit 0
    }

    $uptimeMinutes = [Math]::Floor((Get-HostUptime))
    if ($uptimeMinutes -lt $MinimumUptimeMinutes) {
        Write-Output "Up $uptimeMinutes of $MinimumUptimeMinutes minimum minutes.$suffix"
        exit 0
    }

    if ($null -ne $state.ScheduledUtc) {
        $nowUtc = (Get-Date).ToUniversalTime()
        $bootUtc = $nowUtc.AddMinutes(-$uptimeMinutes - 1)
        $ageMinutes = [Math]::Floor(($nowUtc - $state.ScheduledUtc).TotalMinutes)
        if ($state.ScheduledUtc -gt $bootUtc -and $ageMinutes -ge 0 -and $ageMinutes -lt $MarkerValidMinutes) {
            Write-Output "Deallocation scheduled $ageMinutes minute(s) ago; the host deallocates itself unless a user connects first.$suffix"
            exit 0
        }
    }

    Write-Output "Idle: 0 sessions, up $uptimeMinutes minutes.$suffix"
    exit 1
}
catch {
    Write-Output "Detection failed: $($_.Exception.Message)"
    exit 2
}
