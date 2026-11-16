#Requires -Version 5.1

<#
.SYNOPSIS
    Deallocates this session host through the Azure API when it has no user
    sessions and has been running past an idle threshold.

.DESCRIPTION
    Runs on the session host itself as SYSTEM. Usage-aware by design: it acts
    on the actual session state of the machine, not on a time window, so it
    suits 24/7 personal workloads.

    It runs in two steps, so Intune receives its result before the VM goes
    down:

    1. Schedule (default; run by Intune Remediations). Checks the gates
       below, proves the managed identity can read this VM, then registers a
       one-time SYSTEM scheduled task that runs this script again with
       -Deferred after DeallocateDelayMinutes, and exits. Intune then runs
       the detection script again and uploads the result while the VM is
       still up.
    2. Deferred (run by the scheduled task). Checks every gate again, so a
       user who connected during the delay is never cut off, then calls
       deallocate on this VM.

    Gates, cheapest first:

    - Sessions: any session reported by quser, active or disconnected, means
      the desktop is in use and nothing happens. Disconnected sessions are
      preserved on purpose; closing them would lose the user's running
      applications.
    - Uptime: the machine must have been up at least MinimumUptimeMinutes,
      so a host that Start VM on Connect just powered on is not fought over.
    - Identity loopback: the VM's compute metadata and a management-plane
      token are read from IMDS (169.254.169.254, link-local, no credential
      stored anywhere). The metadata name must match this computer's name;
      on mismatch the script refuses to act.

    Deallocate, not a guest shutdown: only deallocation releases the compute
    hardware and stops billing. The call returns accepted and Azure then
    stops the machine; the script does not wait.

    Deploy with Intune Remediations as the remediation script, paired with
    Detect-AvdSelfDeallocate.ps1 as the detection script, on an hourly
    schedule, as SYSTEM, in 64-bit PowerShell.

    State, under HKLM:\SOFTWARE\AvdSessionHostAutomation\SelfDeallocate:
    - DeallocateScheduledUtc: when the schedule step registered the task.
      The detection script reports the host as handled while this is recent,
      so Intune records the issue as fixed.
    - LastResult: a timestamped line from the latest schedule or deferred
      run (scheduled, deallocation accepted, cancelled, or failed). The
      detection script repeats it in its output, so the outcome of the
      deferred run shows in the Intune console on the next detection.

    For the deferred run, the script copies itself to
    C:\Program Files\AvdSessionHostAutomation, which standard users cannot
    write, so the SYSTEM task never runs a file a user could change. The
    task is registered as \AvdSessionHostAutomation\AvdSelfDeallocate and
    is replaced on each schedule run. Its trigger is one-time and does not
    start late, so a VM that was off at the due time does not deallocate on
    its next boot.

    -WhatIf is the identity test. It runs every read-only step even when a
    session is open or the uptime threshold is not met (so it can be run
    from an RDP session on the host): it reports the session and uptime
    verdict, requests the managed-identity token from IMDS, and reads this
    VM through Azure Resource Manager with that token. A pass proves the
    system-assigned identity is enabled and holds the self-deallocate role
    on this VM. It copies nothing, registers no task, writes no state, and
    never calls deallocate.

.PARAMETER MinimumUptimeMinutes
    Minimum minutes since boot before the host may deallocate itself. Intune
    Remediations pass no parameters, so the default is the configuration;
    keep it equal to the default in Detect-AvdSelfDeallocate.ps1. The
    schedule step passes its value to the deferred run.

.PARAMETER DeallocateDelayMinutes
    Minutes between the schedule step and the deferred deallocation. It
    gives Intune time to upload the remediation result. Must stay below
    MarkerValidMinutes in Detect-AvdSelfDeallocate.ps1 (the Pester suite
    checks the defaults).

.PARAMETER Deferred
    Runs the deferred step: re-check the gates and deallocate. Used by the
    scheduled task; not set in Intune.

.PARAMETER ManagementEndpoint
    Azure Resource Manager endpoint; the default is the public cloud.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-AvdSelfDeallocate.ps1 -WhatIf

    Tests the managed identity and role from an elevated prompt on the host,
    without scheduling or deallocating. Run the whole file; running a
    selection skips the param block and its defaults.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-AvdSelfDeallocate.ps1 -Deferred -WhatIf

    Shows what the deferred run would do now, without deallocating.

.NOTES
    Requires the VM's system-assigned managed identity to hold
    Microsoft.Compute/virtualMachines/read and
    Microsoft.Compute/virtualMachines/deallocate/action on this VM (granted
    by the build pipeline's Assign stage). IMDS calls must not go through a
    proxy; SYSTEM normally has none configured. The scheduled task runs
    powershell.exe with -ExecutionPolicy Bypass; an execution policy set by
    Group Policy overrides that and would block the deferred run.
    https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service
    https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token
    https://learn.microsoft.com/powershell/module/scheduledtasks/register-scheduledtask
    https://learn.microsoft.com/powershell/module/scheduledtasks/new-scheduledtasksettingsset
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateRange(5, 1440)][int]$MinimumUptimeMinutes = 60,
    [ValidateRange(1, 20)][int]$DeallocateDelayMinutes = 10,
    [switch]$Deferred,
    [ValidatePattern('\Ahttps://[a-z0-9.-]+\z')][string]$ManagementEndpoint = 'https://management.azure.com'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$markerKey = 'HKLM:\SOFTWARE\AvdSessionHostAutomation\SelfDeallocate'
$markerValueName = 'DeallocateScheduledUtc'
$resultValueName = 'LastResult'
$taskName = 'AvdSelfDeallocate'
$taskPath = '\AvdSessionHostAutomation\'
$installDirectory = '{0}\AvdSessionHostAutomation' -f $env:ProgramFiles
$installedScript = '{0}\Invoke-AvdSelfDeallocate.ps1' -f $installDirectory

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

function Get-ImdsComputeInstance {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    return Invoke-RestMethod -Method Get -TimeoutSec 10 `
        -Headers @{ Metadata = 'true' } `
        -Uri 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01'
}

function Get-ImdsAccessToken {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Resource)

    $encodedResource = [Uri]::EscapeDataString($Resource)
    try {
        $response = Invoke-RestMethod -Method Get -TimeoutSec 10 `
            -Headers @{ Metadata = 'true' } `
            -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$encodedResource"
    }
    catch {
        throw "IMDS token request for resource '$Resource' failed. Check that the VM's system-assigned identity is enabled. $($_.Exception.Message)"
    }
    if (-not $response.access_token) {
        throw "IMDS did not return a managed-identity access token for resource '$Resource'."
    }
    return [string]$response.access_token
}

function Write-SelfDeallocateState {
    # Callers invoke this only after their ShouldProcess decision. A failed
    # write is a warning, not an error: the state is for reporting and must
    # never turn a successful run into a failed one.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    try {
        if (-not (Test-Path -LiteralPath $Key)) {
            New-Item -Path $Key -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $Key -Name $Name -Value $Value
    }
    catch {
        Write-Warning "Could not record $Name under $Key for the detection script: $($_.Exception.Message)"
    }
}

function Write-SelfDeallocateResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Message
    )

    # Kept short: the detection script repeats this line, and Intune keeps
    # only the first 2,048 characters of script output.
    if ($Message.Length -gt 400) { $Message = $Message.Substring(0, 400) }
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    Write-SelfDeallocateState -Key $Key -Name $Name -Value "$stamp $Message"
}

$isWhatIf = [bool]$WhatIfPreference
$recordsResult = $Deferred -and -not $isWhatIf

try {
    $sessionCount = Get-ActiveSessionCount
    $uptimeMinutes = [Math]::Floor((Get-HostUptime))
    $blockReason = $null
    if ($sessionCount -gt 0) {
        $blockReason = "In use: $sessionCount session(s) present."
    }
    elseif ($uptimeMinutes -lt $MinimumUptimeMinutes) {
        $blockReason = "Up $uptimeMinutes of $MinimumUptimeMinutes minimum minutes."
    }
    if ($blockReason -and -not $isWhatIf) {
        if ($recordsResult) {
            Write-SelfDeallocateResult -Key $markerKey -Name $resultValueName -Message "Deallocation cancelled. $blockReason"
        }
        Write-Output "$blockReason No action."
        return
    }

    $metadata = Get-ImdsComputeInstance
    $vmName = [string]$metadata.name
    $localName = [Environment]::MachineName
    if ($vmName -ine $localName) {
        throw "IMDS reports VM '$vmName' but this computer is '$localName'. Refusing to deallocate."
    }

    $vmUri = '{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Compute/virtualMachines/{3}' -f `
        $ManagementEndpoint, [string]$metadata.subscriptionId, [string]$metadata.resourceGroupName, $vmName
    $apiVersion = 'api-version=2024-03-01'
    $idleSummary = "0 sessions, up $uptimeMinutes minutes"

    $token = Get-ImdsAccessToken -Resource "$ManagementEndpoint/"
    try {
        # The schedule step and -WhatIf prove the identity can read this VM,
        # so a missing role fails the Intune remediation visibly instead of
        # failing later inside the scheduled task.
        if ($isWhatIf -or -not $Deferred) {
            try {
                Invoke-RestMethod -Method Get -TimeoutSec 30 `
                    -Headers @{ Authorization = "Bearer $token" } `
                    -Uri ('{0}?{1}' -f $vmUri, $apiVersion) | Out-Null
            }
            catch {
                throw "A token was issued, but Azure Resource Manager refused to read VM '$vmName'. Check that the VM's identity holds the AVD Prod Self Deallocate role on this VM. $($_.Exception.Message)"
            }
            if ($isWhatIf) {
                Write-Output "Identity check passed: the managed-identity token for $ManagementEndpoint/ can read VM '$vmName'."
            }
        }

        if ($blockReason) {
            Write-Output "$blockReason Would take no action. Nothing was changed."
            return
        }

        if ($Deferred) {
            if (-not $PSCmdlet.ShouldProcess($vmName, "Deallocate idle session host ($idleSummary)")) {
                Write-Output "Would deallocate '$vmName'. Nothing was changed."
                return
            }
            Invoke-RestMethod -Method Post -TimeoutSec 60 `
                -Headers @{ Authorization = "Bearer $token" } `
                -Uri ('{0}/deallocate?{1}' -f $vmUri, $apiVersion) | Out-Null
        }
    }
    finally {
        $token = $null
    }

    if ($Deferred) {
        $message = "Deallocation of '$vmName' accepted ($idleSummary)."
        Write-SelfDeallocateResult -Key $markerKey -Name $resultValueName -Message $message
        Write-Output $message
        return
    }

    $dueLocal = (Get-Date).AddMinutes($DeallocateDelayMinutes)
    $dueText = $dueLocal.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $action = "Schedule deallocation of idle session host in $DeallocateDelayMinutes minute(s) ($idleSummary)"
    if (-not $PSCmdlet.ShouldProcess($vmName, $action)) {
        Write-Output "Would schedule deallocation of '$vmName' for $dueText (in $DeallocateDelayMinutes minute(s)). Nothing was changed."
        return
    }

    if (-not $PSCommandPath) {
        throw 'Cannot locate this script file to install it for the deferred run. Run it with -File.'
    }
    if (-not (Test-Path -LiteralPath $installDirectory)) {
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
    }
    if ($PSCommandPath -ine $installedScript) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
    }

    $powershellPath = '{0}\System32\WindowsPowerShell\v1.0\powershell.exe' -f $env:SystemRoot
    $taskArguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Deferred -MinimumUptimeMinutes {1} -ManagementEndpoint {2}' -f `
        $installedScript, $MinimumUptimeMinutes, $ManagementEndpoint
    $taskAction = New-ScheduledTaskAction -Execute $powershellPath -Argument $taskArguments
    $taskTrigger = New-ScheduledTaskTrigger -Once -At $dueLocal
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    # StartWhenAvailable is deliberately not set: a run missed while the VM
    # was off must not fire at the next boot.
    $taskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $taskAction -Trigger $taskTrigger `
        -Principal $taskPrincipal -Settings $taskSettings -Force `
        -Description 'Deallocates this AVD session host if it is still idle. Registered by Invoke-AvdSelfDeallocate.ps1 (Intune Remediations).' |
        Out-Null

    Write-SelfDeallocateState -Key $markerKey -Name $markerValueName `
        -Value ((Get-Date).ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture))
    $message = "Identity check passed. Deallocation of '$vmName' scheduled for $dueText ($idleSummary); it is cancelled if a user connects first."
    Write-SelfDeallocateResult -Key $markerKey -Name $resultValueName -Message $message
    Write-Output $message
}
catch {
    if ($recordsResult) {
        Write-SelfDeallocateResult -Key $markerKey -Name $resultValueName -Message "Deallocation failed. $($_.Exception.Message)"
    }
    throw
}
