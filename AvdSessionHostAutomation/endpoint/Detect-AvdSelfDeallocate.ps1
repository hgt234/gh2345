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
         was already accepted during this boot within the last
         MarkerValidMinutes (the VM is shutting down).
      1  Idle: no sessions and past the uptime threshold. Intune then runs
         the remediation, which re-checks every gate before acting.
      2  Detection itself failed; the output line carries the reason.
         Any exit code other than 1 keeps the remediation from running.

    The marker exists because Intune runs detection again right after the
    remediation, while the VM is still shutting down. Without it, that
    second run would see an idle host and report the issue as recurring.
    The remediation writes the marker to HKLM, which standard users cannot
    write. A marker from an earlier boot is ignored, and so is one older
    than MarkerValidMinutes, so a deallocation that Azure accepted but never
    carried out is retried on the next hourly run.

    Intune passes no parameters to Remediations scripts; the defaults are
    the configuration. Keep MinimumUptimeMinutes, the marker key, and the
    shared functions identical to Invoke-AvdSelfDeallocate.ps1 (the Pester
    suite checks this).

.PARAMETER MinimumUptimeMinutes
    Minimum minutes since boot before the host counts as idle. Must match
    Invoke-AvdSelfDeallocate.ps1.

.PARAMETER MarkerValidMinutes
    How long after an accepted deallocation detection keeps reporting
    "already handled" during the same boot.

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
$markerValueName = 'DeallocateRequestedUtc'

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

function Get-DeallocateRequestTime {
    [CmdletBinding()]
    [OutputType([Nullable[datetime]])]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$ValueName
    )

    if (-not (Test-Path -LiteralPath $Key)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue
    if (-not $item -or -not ($item.PSObject.Properties.Name -contains $ValueName)) { return $null }
    $parsed = [datetime]::MinValue
    $styles = [Globalization.DateTimeStyles]::RoundtripKind
    if (-not [datetime]::TryParse([string]$item.$ValueName, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $null
    }
    return $parsed.ToUniversalTime()
}

try {
    $sessionCount = Get-ActiveSessionCount
    if ($sessionCount -gt 0) {
        Write-Output "In use: $sessionCount session(s) present."
        exit 0
    }

    $uptimeMinutes = [Math]::Floor((Get-HostUptime))
    if ($uptimeMinutes -lt $MinimumUptimeMinutes) {
        Write-Output "Up $uptimeMinutes of $MinimumUptimeMinutes minimum minutes."
        exit 0
    }

    $requestedUtc = Get-DeallocateRequestTime -Key $markerKey -ValueName $markerValueName
    if ($null -ne $requestedUtc) {
        $nowUtc = (Get-Date).ToUniversalTime()
        $bootUtc = $nowUtc.AddMinutes(-$uptimeMinutes - 1)
        $ageMinutes = [Math]::Floor(($nowUtc - $requestedUtc).TotalMinutes)
        if ($requestedUtc -gt $bootUtc -and $ageMinutes -ge 0 -and $ageMinutes -lt $MarkerValidMinutes) {
            Write-Output "Deallocation accepted $ageMinutes minute(s) ago; waiting for Azure to stop the VM."
            exit 0
        }
    }

    Write-Output "Idle: 0 sessions, up $uptimeMinutes minutes."
    exit 1
}
catch {
    Write-Output "Detection failed: $($_.Exception.Message)"
    exit 2
}
