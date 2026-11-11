#requires -Version 5.1
<#
.SYNOPSIS
    Benchmarks AVD session host storage with DiskSpd using a modeled Visual
    Studio (devenv) developer workload, while recording performance counters.

.DESCRIPTION
    Runs on the session host, in the session of the user whose FSLogix profile
    should be measured. For each target location (OS disk, FSLogix profile
    container, optional data disk) it:

      1. Creates a few test files filled with random data (the fill rate is
         reported as a large sequential write result).
      2. Runs each workload scenario. A scenario is a set of streams that run
         concurrently, one DiskSpd process per stream, each with its own block
         size, access pattern, read/write mix, threads and queue depth.
      3. Removes the test files (unless -KeepTestFiles).

    Performance counters (LogicalDisk, PhysicalDisk, SMB Client Shares, CPU,
    memory) are sampled for the whole run and averaged over each scenario's
    measured window, so DiskSpd's view and the OS view line up per test.

    Workload model (built-in, see Get-AvdDefaultWorkload in
    AvdStorageBenchmark.Common.ps1):

      Scenario      Stream               Block   Pattern                Write  Threads x QD
      SolutionLoad  ProjectSourceRead     4 KiB  random, 90% in 10%       0%   4 x 1
                    AssemblyRead         64 KiB  random, 80% in 20%       0%   2 x 1
                    IntelliSenseDbLoad    4 KiB  random, write-through   20%   1 x 1
      Editing       SourceRead            4 KiB  random, 90% in 10%       0%   2 x 1 (50 IOPS/thread)
                    IntelliSenseDbWrite   4 KiB  random, write-through   50%   1 x 1 (20 IOPS)
                    AutoRecoverWrite      4 KiB  sequential, w-through  100%   1 x 1 (5 IOPS)
      Build         CompileSourceRead     4 KiB  random                   0%   CPUs x 1
                    ReferenceRead        64 KiB  random, 80% in 20%       0%   2 x 1
                    ObjBinWrite          64 KiB  sequential             100%   CPUs x 1
                    BuildStateWrite       4 KiB  random                  70%   1 x 1
      NuGetRestore  PackageDownload      64 KiB  sequential             100%   2 x 1
                    PackageExtract        4 KiB  random                  80%   4 x 1
      Debugging     SymbolRead            4 KiB  random, 80% in 20%       0%   2 x 1
                    BinaryLoad           64 KiB  sequential               0%   1 x 1

    "CPUs" is the logical processor count (max 32), the Visual Studio default
    for "Maximum number of parallel project builds". 4 KiB comes from the NTFS
    cluster size, the 4096-byte MSF block of PDB symbol files and the SQLite
    page of the IntelliSense browse database. The 64 KiB transfers, write
    ratios, hot sets and Editing rates are modeled. To calibrate against
    reality, run -Mode Capture during a real Visual Studio session, then
    -Mode ExportWorkload, edit the JSON and pass it back with -WorkloadPath.

    Where the IO lands with FSLogix: the default project location
    (%USERPROFILE%\source\repos), the NuGet global-packages folder
    (%USERPROFILE%\.nuget\packages) and the NuGet http-cache and Visual Studio
    caches (%LOCALAPPDATA%) are all inside the profile container. Only the
    Visual Studio installation (Program Files) is on the OS disk.

    Limits: DiskSpd generates data IO only. File create/open/enumerate
    (metadata) operations, which are heavy during restore, build and
    incremental up-to-date checks, are not simulated. Visual Studio's CPU and
    memory use during a real build is not reproduced either.

.PARAMETER Mode
    Benchmark (default) runs DiskSpd. Capture records counters only, while you
    use Visual Studio normally, and reports the observed IO sizes and mix.
    ExportWorkload writes the active workload definition to JSON for editing.

.PARAMETER Target
    Locations to test. Defaults to OsDisk and Profile, plus DataDisk when
    -DataDiskPath is given.

.PARAMETER OsDiskPath
    Test directory on the OS disk. Default: %ProgramData%\AvdStorageBenchmark\work.

.PARAMETER ProfilePath
    Test directory inside the user profile. Default:
    %USERPROFILE%\AvdStorageBenchmark. With FSLogix this lives in the mounted
    profile VHD(X).

.PARAMETER DataDiskPath
    Test directory on a data disk, for example F:\AvdStorageBenchmark.

.PARAMETER Scenario
    Scenario names to run. Default: all scenarios in the workload.

.PARAMETER WorkloadPath
    JSON workload definition (same shape as -Mode ExportWorkload output).

.PARAMETER DurationSeconds
    Measured duration of each scenario.

.PARAMETER WarmupSeconds
    DiskSpd warm-up before measurement starts (-W).

.PARAMETER CooldownSeconds
    DiskSpd cool-down after measurement ends (-C).

.PARAMETER PauseSeconds
    Idle gap between scenarios so counter windows stay separate.

.PARAMETER CacheMode
    Unbuffered (default, -Sh) bypasses the Windows cache and measures the
    storage path. Cached (-Sb, or -Sw for write-through streams) includes the
    OS cache, closer to what an application sees but dominated by RAM.

.PARAMETER Saturate
    Removes the per-stream IOPS limits to find the storage ceiling at the
    modeled block sizes and concurrency.

.PARAMETER CaptureSeconds
    Capture mode duration.

.PARAMETER SampleIntervalSeconds
    Performance counter sample interval.

.PARAMETER DiskSpdPath
    Path to diskspd.exe. If omitted, a copy downloaded earlier with
    -DownloadDiskSpd is used.

.PARAMETER DownloadDiskSpd
    Downloads DiskSpd v2.3 from the Microsoft GitHub release, verifies the
    pinned SHA-256 and the Microsoft Authenticode signature, and extracts it
    to %ProgramData%\AvdStorageBenchmark\tools.

.PARAMETER OutputPath
    Parent folder for results. A per-run subfolder is created.
    Default: %ProgramData%\AvdStorageBenchmark\results (outside the profile, so
    result writes do not add IO to the profile target).

.PARAMETER MinimumFreeSpaceGB
    Free space that must remain on each target after the test files are created.

.PARAMETER KeepTestFiles
    Leaves the test files in place after the run.

.PARAMETER Quick
    Quick validation preset: 1 s warm-up, 4 s measured, no cool-down or
    pause, 64 MiB test files. Two targets x five scenarios take about 60 s.
    Confirms the pipeline works and gives ballpark latency; use the default
    timings for numbers you size against. Timing parameters passed explicitly
    still win over the preset.

.PARAMETER TestFileSizeMB
    Overrides the size of every workload test file (16-65536 MiB).

.EXAMPLE
    .\Invoke-AvdStorageBenchmark.ps1 -DownloadDiskSpd -WhatIf

    Resolves targets, checks free space and FSLogix state, and prints every
    DiskSpd command line that would run. Downloads nothing and changes nothing.

.EXAMPLE
    .\Invoke-AvdStorageBenchmark.ps1 -DownloadDiskSpd -Quick

    Quick validation of the OS disk and FSLogix profile in about one minute.

.EXAMPLE
    .\Invoke-AvdStorageBenchmark.ps1 -DownloadDiskSpd -DataDiskPath 'F:\AvdStorageBenchmark'

    Benchmarks the OS disk, the FSLogix profile and the F: data disk.

.EXAMPLE
    .\Invoke-AvdStorageBenchmark.ps1 -DiskSpdPath C:\Tools\diskspd.exe -Target Profile -Scenario Build, NuGetRestore -Saturate

    Finds the profile container's ceiling for the build and restore patterns.

.EXAMPLE
    .\Invoke-AvdStorageBenchmark.ps1 -Mode Capture -CaptureSeconds 1800

    Records counters for 30 minutes while you work in Visual Studio, then reports the
    observed read/write mix and average IO sizes per disk.

.NOTES
    - Run in the target user's session (not as SYSTEM) so %USERPROFILE% is the
      mounted FSLogix container. Elevation is not required.
    - Writing test files into a dynamically expanding profile VHD(X) grows it.
      Deleting the files frees space inside the container, but the VHD(X) file
      on the share only shrinks when the container is compacted.
    - On an Azure VM, the OS disk host cache (ReadWrite by default for OS disks)
      can serve part of the reads; that matches what Visual Studio would see.
    - Results go to -OutputPath and contain the computer name. Do not commit them.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Benchmark', 'Capture', 'ExportWorkload')]
    [string] $Mode = 'Benchmark',

    [ValidateSet('OsDisk', 'Profile', 'DataDisk')]
    [string[]] $Target,

    [ValidateNotNullOrEmpty()]
    [string] $OsDiskPath = (Join-Path $env:ProgramData 'AvdStorageBenchmark\work'),

    [ValidateNotNullOrEmpty()]
    [string] $ProfilePath = (Join-Path $env:USERPROFILE 'AvdStorageBenchmark'),

    [ValidateNotNullOrEmpty()]
    [string] $DataDiskPath,

    [string[]] $Scenario,

    [ValidateNotNullOrEmpty()]
    [string] $WorkloadPath,

    [ValidateRange(1, 3600)]
    [int] $DurationSeconds = 60,

    [ValidateRange(0, 600)]
    [int] $WarmupSeconds = 10,

    [ValidateRange(0, 600)]
    [int] $CooldownSeconds = 5,

    [ValidateRange(0, 300)]
    [int] $PauseSeconds = 5,

    [ValidateSet('Unbuffered', 'Cached')]
    [string] $CacheMode = 'Unbuffered',

    [switch] $Saturate,

    [ValidateRange(60, 86400)]
    [int] $CaptureSeconds = 900,

    [ValidateRange(1, 60)]
    [int] $SampleIntervalSeconds = 1,

    [ValidateNotNullOrEmpty()]
    [string] $DiskSpdPath,

    [switch] $DownloadDiskSpd,

    [ValidateNotNullOrEmpty()]
    [string] $OutputPath = (Join-Path $env:ProgramData 'AvdStorageBenchmark\results'),

    [ValidateRange(0, 1024)]
    [int] $MinimumFreeSpaceGB = 2,

    [switch] $KeepTestFiles,

    [switch] $Quick,

    [ValidateRange(16, 65536)]
    [int] $TestFileSizeMB
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'This script runs on Windows session hosts only.' }

. (Join-Path $PSScriptRoot 'AvdStorageBenchmark.Common.ps1')

$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$toolsRoot = Join-Path $env:ProgramData 'AvdStorageBenchmark\tools'
$runStamp = (Get-Date).ToString('yyyyMMdd-HHmmss', $invariant)
$runDirectory = Join-Path $OutputPath ('{0}_{1}' -f $env:COMPUTERNAME, $runStamp)

#region Quick preset (explicit parameters win)
if ($Quick) {
    $preset = Get-AvdQuickSetting
    foreach ($name in @('WarmupSeconds', 'DurationSeconds', 'CooldownSeconds', 'PauseSeconds', 'TestFileSizeMB')) {
        if (-not $PSBoundParameters.ContainsKey($name)) { Set-Variable -Name $name -Value $preset[$name] }
    }
}
$runClock = [System.Diagnostics.Stopwatch]::StartNew()
#endregion

#region Workload
if ($WorkloadPath) {
    $workload = ConvertTo-AvdWorkload -InputObject (Get-Content -LiteralPath $WorkloadPath -Raw | ConvertFrom-Json)
}
else {
    $workload = ConvertTo-AvdWorkload -InputObject (Get-AvdDefaultWorkload)
}
if ($Scenario) {
    $unknown = @($Scenario | Where-Object { $_ -notin @($workload.Scenarios | ForEach-Object { $_.Name }) })
    if ($unknown.Count -gt 0) { throw "Unknown scenario(s): $($unknown -join ', '). Available: $(($workload.Scenarios | ForEach-Object { $_.Name }) -join ', ')." }
    $workload.Scenarios = @($workload.Scenarios | Where-Object { $_.Name -in $Scenario })
}
if ($TestFileSizeMB) { $workload = Get-AvdResizedWorkload -Workload $workload -SizeMB $TestFileSizeMB }
#endregion

function Write-AvdStatus {
    # Interactive progress text on the information stream (redirectable with 6>).
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] [AllowEmptyString()] [string] $Message)
    process { Write-Information -MessageData $Message -InformationAction Continue }
}

function New-AvdRunDirectory {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string] $LiteralPath)
    if (Test-Path -LiteralPath $LiteralPath -PathType Container) { return $true }
    if ($PSCmdlet.ShouldProcess($LiteralPath, 'Create results directory')) {
        New-Item -ItemType Directory -Path $LiteralPath -Force | Out-Null
        return $true
    }
    return $false
}

function Get-AvdAvailableCounterPath {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string[]] $Desired)
    $sets = @($Desired | ForEach-Object { ($_ -split '\\')[1] -replace '\(.*$', '' } | Select-Object -Unique)
    $available = @()
    foreach ($set in $sets) {
        $listSet = Get-Counter -ListSet $set -ErrorAction SilentlyContinue
        if ($listSet) { $available += @($listSet.Paths) + @($listSet.PathsWithInstances) }
    }
    return $available
}

function Write-AvdJson {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([Parameter(Mandatory)] [object] $InputObject, [Parameter(Mandatory)] [string] $LiteralPath)
    if ($PSCmdlet.ShouldProcess($LiteralPath, 'Write JSON report')) {
        $InputObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $LiteralPath -Encoding UTF8
    }
}

#region ExportWorkload mode
if ($Mode -eq 'ExportWorkload') {
    if (New-AvdRunDirectory -LiteralPath $runDirectory) {
        $exportPath = Join-Path $runDirectory 'workload.json'
        Write-AvdJson -InputObject $workload -LiteralPath $exportPath
        if (Test-Path -LiteralPath $exportPath) { Get-Item -LiteralPath $exportPath }
    }
    return
}
#endregion

#region Counter selection (read-only)
$desiredCounters = @(Get-AvdDesiredCounterPath)
$counterSelection = Select-AvdCounterPath -Desired $desiredCounters -Available @(Get-AvdAvailableCounterPath -Desired $desiredCounters)
foreach ($missing in $counterSelection.Missing) { Write-Verbose "Counter not available on this host, skipped: $missing" }
if (@($counterSelection.Selected).Count -eq 0) { Write-Warning 'No performance counters are available; results will contain DiskSpd data only.' }
#endregion

#region Capture mode
if ($Mode -eq 'Capture') {
    $maxSamples = [math]::Max(2, [int][math]::Ceiling($CaptureSeconds / $SampleIntervalSeconds))
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Record $(@($counterSelection.Selected).Count) performance counters for $CaptureSeconds s into $runDirectory")) {
        $counterSelection.Selected | ForEach-Object { [pscustomobject]@{ Counter = $_ } }
        return
    }
    [void](New-AvdRunDirectory -LiteralPath $runDirectory)
    Write-AvdStatus "Capturing for $CaptureSeconds seconds. Use Visual Studio normally now: open the solution, restore, build, edit and debug."
    $samples = New-Object System.Collections.Generic.List[object]
    Get-Counter -Counter $counterSelection.Selected -SampleInterval $SampleIntervalSeconds -MaxSamples $maxSamples -ErrorAction SilentlyContinue |
        ForEach-Object {
            $timestamp = $_.Timestamp
            foreach ($counterSample in $_.CounterSamples) {
                $samples.Add([pscustomobject]@{ Timestamp = $timestamp; Path = $counterSample.Path; InstanceName = $counterSample.InstanceName; Value = $counterSample.CookedValue })
            }
        }
    $samples | Select-Object @{ n = 'Timestamp'; e = { $_.Timestamp.ToString('o', $invariant) } }, Path, InstanceName, @{ n = 'Value'; e = { $_.Value.ToString('R', $invariant) } } |
        Export-Csv -LiteralPath (Join-Path $runDirectory 'capture-counters.csv') -NoTypeInformation -Encoding UTF8
    $observed = @(Get-AvdObservedIoProfile -Samples $samples.ToArray())
    Write-AvdJson -LiteralPath (Join-Path $runDirectory 'capture-summary.json') -InputObject ([pscustomobject]@{
            ComputerName = $env:COMPUTERNAME; CapturedSeconds = $CaptureSeconds; SampleIntervalSeconds = $SampleIntervalSeconds
            Note = 'Sizes are IO-weighted averages of what reached each disk after the OS cache. Use them to set BlockSizeBytes and WritePercent in the workload JSON.'
            Disks = $observed
        })
    $observed
    return
}
#endregion

#region Targets (read-only discovery)
if (-not $PSBoundParameters.ContainsKey('Target')) {
    $Target = @('OsDisk', 'Profile')
    if ($DataDiskPath) { $Target += 'DataDisk' }
}
if ('DataDisk' -in $Target -and -not $DataDiskPath) { throw 'Target DataDisk requires -DataDiskPath.' }

$directories = @{ OsDisk = $OsDiskPath; Profile = $ProfilePath; DataDisk = $DataDiskPath }
$requiredBytes = Get-AvdWorkloadSize -Workload $workload
$osVolume = Get-AvdVolumeInfo -Path $env:SystemDrive
$targets = foreach ($name in ($Target | Select-Object -Unique)) {
    $directory = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($directories[$name])
    $volume = Get-AvdVolumeInfo -Path $directory
    $notes = @()
    $needed = $requiredBytes + ([long]$MinimumFreeSpaceGB * 1GB)
    if ($volume.FreeBytes -lt $needed) {
        throw ("Target {0} ({1}): {2:N1} GiB free on {3}, need {4:N1} GiB (test files {5:N1} GiB + MinimumFreeSpaceGB)." -f $name, $directory, ($volume.FreeBytes / 1GB), $volume.VolumeRoot, ($needed / 1GB), ($requiredBytes / 1GB))
    }
    if ($name -eq 'Profile') {
        # Read the 64-bit view explicitly so a 32-bit host is not redirected to WOW6432Node.
        $fslogixEnabled = $null
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $key = $baseKey.OpenSubKey('SOFTWARE\FSLogix\Profiles')
            if ($key) { try { $fslogixEnabled = $key.GetValue('Enabled') } finally { $key.Dispose() } }
        }
        finally { $baseKey.Dispose() }
        if ($fslogixEnabled -ne 1) { $notes += 'FSLogix Profiles is not enabled (HKLM\SOFTWARE\FSLogix\Profiles\Enabled is not 1).' }
        if ($volume.VolumeRoot -eq $osVolume.VolumeRoot) { $notes += "Profile path resolves to the OS volume ($($volume.VolumeRoot)); no profile container appears to be mounted, so this measures the OS disk." }
        else { $notes += "Writing test files grows the dynamic profile VHD(X); it shrinks on the share only after compaction." }
    }
    if ($name -eq 'DataDisk' -and $volume.VolumeRoot -eq $osVolume.VolumeRoot) {
        $notes += "Data disk path resolves to the OS volume ($($volume.VolumeRoot))."
    }
    foreach ($note in $notes) { Write-Warning "${name}: $note" }
    [pscustomobject]@{
        Name = $name; Directory = $directory; VolumeRoot = $volume.VolumeRoot
        FreeGiB = [math]::Round($volume.FreeBytes / 1GB, 1); TotalGiB = [math]::Round($volume.TotalBytes / 1GB, 1); Notes = $notes
    }
}
$targets = @($targets)
$plan = @(Get-AvdBenchmarkPlan -Targets $targets -Workload $workload -DurationSeconds $DurationSeconds -WarmupSeconds $WarmupSeconds -CooldownSeconds $CooldownSeconds -CacheMode $CacheMode -Saturate:$Saturate)
$estimatedSeconds = Get-AvdEstimatedRunSecond -TargetCount $targets.Count -ScenarioCount $workload.Scenarios.Count -DurationSeconds $DurationSeconds -WarmupSeconds $WarmupSeconds -CooldownSeconds $CooldownSeconds -PauseSeconds $PauseSeconds
if ($Quick -and $estimatedSeconds -gt 60) { Write-Warning "Quick run is estimated at $estimatedSeconds s of DiskSpd time; reduce -Target or -Scenario to stay within 60 s." }
Write-Verbose ("Plan: {0} target(s) x {1} scenario(s), {2} DiskSpd processes, about {3:N0} min plus file creation." -f $targets.Count, $workload.Scenarios.Count, $plan.Count, ($estimatedSeconds / 60))
#endregion

#region DiskSpd
function Get-AvdDiskSpdArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    switch ($architecture) {
        'AMD64' { return 'amd64' }
        'ARM64' { return 'arm64' }
        default { throw "DiskSpd $($script:AvdDiskSpdRelease.Version) ships amd64 and arm64 only; this host is '$architecture'." }
    }
}

function Test-AvdMicrosoftSignature {
    param([Parameter(Mandatory)] [string] $LiteralPath)
    $signature = Get-AuthenticodeSignature -LiteralPath $LiteralPath
    return ($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match '(^|,\s*)O=Microsoft Corporation(,|$)')
}

function Install-AvdDiskSpd {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Destination)
    $release = $script:AvdDiskSpdRelease
    if (-not $PSCmdlet.ShouldProcess($Destination, "Download DiskSpd $($release.Version) from $($release.Uri) and extract")) { return $null }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $zipPath = Join-Path $Destination 'DiskSpd.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $release.Uri -OutFile $zipPath -UseBasicParsing
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    if ($hash -ne $release.Sha256) {
        Remove-Item -LiteralPath $zipPath -Force
        throw "DiskSpd download hash mismatch: expected $($release.Sha256), got $hash. File removed."
    }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $Destination -Force
    Remove-Item -LiteralPath $zipPath -Force
    $exe = Join-Path $Destination ((Get-AvdDiskSpdArchitecture) + '\diskspd.exe')
    if (-not (Test-AvdMicrosoftSignature -LiteralPath $exe)) { throw "Downloaded $exe does not carry a valid Microsoft Authenticode signature." }
    return $exe
}

$managedDiskSpd = Join-Path $toolsRoot ("diskspd-{0}\{1}\diskspd.exe" -f $script:AvdDiskSpdRelease.Version, (Get-AvdDiskSpdArchitecture))
if ($DiskSpdPath) {
    if (-not (Test-Path -LiteralPath $DiskSpdPath -PathType Leaf)) { throw "DiskSpd not found: $DiskSpdPath" }
    $diskSpd = (Resolve-Path -LiteralPath $DiskSpdPath).ProviderPath
    if (-not (Test-AvdMicrosoftSignature -LiteralPath $diskSpd)) { Write-Warning "$diskSpd is not Microsoft-signed. Make sure it is a build you trust." }
}
elseif (Test-Path -LiteralPath $managedDiskSpd -PathType Leaf) {
    $diskSpd = $managedDiskSpd
    if (-not (Test-AvdMicrosoftSignature -LiteralPath $diskSpd)) { throw "$diskSpd no longer carries a valid Microsoft signature. Delete it and use -DownloadDiskSpd." }
}
elseif ($DownloadDiskSpd) {
    $diskSpd = Install-AvdDiskSpd -Destination (Split-Path -Parent (Split-Path -Parent $managedDiskSpd))
}
else {
    $notFound = "DiskSpd not found. Pass -DiskSpdPath, or -DownloadDiskSpd to fetch v$($script:AvdDiskSpdRelease.Version) from github.com/microsoft/diskspd."
    if (-not $WhatIfPreference) { throw $notFound }
    Write-Warning $notFound
    $diskSpd = $null
}
#endregion

#region WhatIf summary
if ($WhatIfPreference) {
    foreach ($t in $targets) {
        Write-AvdStatus ("What if: target {0} -> {1} (volume {2}, {3} GiB free). Would create {4:N1} GiB of test files: {5}" -f $t.Name, $t.Directory, $t.VolumeRoot, $t.FreeGiB, ($requiredBytes / 1GB), (($workload.Files | ForEach-Object { "$($_.Name).dat $($_.SizeMB) MiB" }) -join ', '))
    }
    Write-AvdStatus ("What if: would run {0} DiskSpd processes over about {1:N0} minutes and record {2} counters into {3}." -f $plan.Count, ($estimatedSeconds / 60), @($counterSelection.Selected).Count, $runDirectory)
    $plan | Select-Object Target, Scenario, Stream, BlockSizeKiB, Pattern, HotSpot, WritePercent, Threads, QueueDepth, IopsLimitPerThread, CommandLine
    return
}
#endregion

#region Run
if (-not (New-AvdRunDirectory -LiteralPath $runDirectory)) { return }
$counterCsv = Join-Path $runDirectory 'counters.csv'
$counterStop = Join-Path $runDirectory 'counters.stop'
$counterJob = $null
if (@($counterSelection.Selected).Count -gt 0) {
    $jobPaths = [string[]]@($counterSelection.Selected)
    $counterJob = Start-Job -Name 'AvdStorageBenchmarkCounters' -ScriptBlock {
        $Paths = $using:jobPaths; $Interval = $using:SampleIntervalSeconds; $CsvPath = $using:counterCsv; $StopPath = $using:counterStop
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        [System.IO.File]::WriteAllText($CsvPath, "Timestamp,Path,InstanceName,Value`r`n")
        while (-not [System.IO.File]::Exists($StopPath)) {
            # Short batches so the stop file is noticed within a few samples.
            $sets = @(Get-Counter -Counter $Paths -SampleInterval $Interval -MaxSamples 2 -ErrorAction SilentlyContinue)
            if ($sets.Count -eq 0) { Start-Sleep -Seconds $Interval; continue }
            $builder = New-Object System.Text.StringBuilder
            foreach ($set in $sets) {
                $stamp = $set.Timestamp.ToString('o', $inv)
                foreach ($s in $set.CounterSamples) {
                    [void]$builder.AppendFormat($inv, '"{0}","{1}","{2}","{3}"', $stamp, $s.Path.Replace('"', '""'), ([string]$s.InstanceName).Replace('"', '""'), $s.CookedValue.ToString('R', $inv))
                    [void]$builder.Append("`r`n")
                }
            }
            [System.IO.File]::AppendAllText($CsvPath, $builder.ToString())
        }
    }
    # Baseline before the first test.
    $baselineSeconds = 3
    if ($Quick) { $baselineSeconds = 1 }
    Start-Sleep -Seconds ([math]::Max($baselineSeconds, $SampleIntervalSeconds))
}

$results = New-Object System.Collections.Generic.List[object]
$fills = New-Object System.Collections.Generic.List[object]
$windows = New-Object System.Collections.Generic.List[object]
$running = New-Object System.Collections.Generic.List[System.Diagnostics.Process]
$timeoutMs = ($WarmupSeconds + $DurationSeconds + $CooldownSeconds + 180) * 1000

try {
    foreach ($t in $targets) {
        $createdDirectory = $false
        $createdFiles = New-Object System.Collections.Generic.List[string]
        try {
            if (-not (Test-Path -LiteralPath $t.Directory -PathType Container)) {
                if (-not $PSCmdlet.ShouldProcess($t.Directory, 'Create benchmark test directory')) { continue }
                New-Item -ItemType Directory -Path $t.Directory -Force | Out-Null
                $createdDirectory = $true
            }
            $filesReady = $true
            foreach ($file in $workload.Files) {
                $path = Join-Path $t.Directory "$($file.Name).dat"
                if (Test-Path -LiteralPath $path) { throw "Refusing to reuse or overwrite existing file: $path" }
                Write-AvdStatus ("[{0}] Creating {1} ({2} MiB)..." -f $t.Name, $path, $file.SizeMB)
                $fill = Write-AvdTestFile -LiteralPath $path -SizeBytes ([long]$file.SizeMB * 1MB)
                if ($null -eq $fill) { $filesReady = $false; break }
                $createdFiles.Add($path)
                $fills.Add([pscustomobject]@{ Target = $t.Name; File = $file.Name; SizeMB = $file.SizeMB; Seconds = $fill.Seconds; MiBps = $fill.MiBps })
            }
            if (-not $filesReady) { continue }

            foreach ($scenarioItem in $workload.Scenarios) {
                $runs = @($plan | Where-Object { $_.Target -eq $t.Name -and $_.Scenario -eq $scenarioItem.Name })
                if (-not $PSCmdlet.ShouldProcess("$($t.Name) / $($scenarioItem.Name)", "Run $($runs.Count) concurrent DiskSpd streams for $DurationSeconds s")) { continue }
                Write-AvdStatus ("[{0}] {1}: {2} streams, {3}s warm-up + {4}s measured..." -f $t.Name, $scenarioItem.Name, $runs.Count, $WarmupSeconds, $DurationSeconds)

                $launched = @()
                $launchTime = Get-Date
                foreach ($run in $runs) {
                    $base = Join-Path $runDirectory ('diskspd_{0}_{1}_{2}' -f $run.Target, $run.Scenario, $run.Stream)
                    $process = Start-Process -FilePath $diskSpd -ArgumentList (ConvertTo-AvdProcessArgumentString -ArgumentList $run.Arguments) `
                        -RedirectStandardOutput "$base.xml" -RedirectStandardError "$base.err.txt" -NoNewWindow -PassThru
                    # Caching the handle keeps ExitCode readable after exit (Windows PowerShell 5.1).
                    $null = $process.Handle
                    $running.Add($process)
                    $launched += [pscustomobject]@{ Run = $run; Process = $process; Base = $base }
                }
                foreach ($item in $launched) {
                    if (-not $item.Process.WaitForExit($timeoutMs)) {
                        Write-Warning "DiskSpd for $($item.Run.Stream) exceeded the timeout; stopping it."
                        $item.Process.Kill()
                        $item.Process.WaitForExit()
                    }
                    [void]$running.Remove($item.Process)
                }
                $windowId = "$($t.Name)|$($scenarioItem.Name)"
                $windows.Add([pscustomobject]@{ Id = $windowId; Start = $launchTime.AddSeconds($WarmupSeconds); End = $launchTime.AddSeconds($WarmupSeconds + $DurationSeconds) })

                foreach ($item in $launched) {
                    $run = $item.Run
                    $parsed = $null; $errorText = $null
                    if ($item.Process.ExitCode -ne 0) {
                        $errorText = "DiskSpd exit code $($item.Process.ExitCode): " + ((Get-Content -LiteralPath "$($item.Base).err.txt" -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ')
                    }
                    else {
                        try { $parsed = ConvertFrom-AvdDiskSpdXml -XmlText (Get-Content -LiteralPath "$($item.Base).xml" -Raw) }
                        catch { $errorText = $_.Exception.Message }
                    }
                    if ($errorText) { Write-Warning "[$($t.Name)] $($scenarioItem.Name)/$($run.Stream): $errorText" }
                    $row = [ordered]@{
                        Target = $run.Target; Scenario = $run.Scenario; Stream = $run.Stream; BlockSizeKiB = $run.BlockSizeKiB
                        Pattern = $run.Pattern; WritePercent = $run.WritePercent; Threads = $run.Threads; QueueDepth = $run.QueueDepth
                        IopsLimitPerThread = $run.IopsLimitPerThread; Error = $errorText
                    }
                    foreach ($metric in @('TotalIops', 'ReadIops', 'WriteIops', 'TotalMiBps', 'AvgReadMs', 'AvgWriteMs', 'P50Ms', 'P95Ms', 'P99Ms', 'P999Ms', 'MaxMs', 'IopsStdDev', 'CpuUsagePercent')) {
                        $value = $null
                        if ($parsed) { $value = $parsed.$metric }
                        $row[$metric] = $value
                    }
                    $row.CommandLine = $run.CommandLine
                    $results.Add([pscustomobject]$row)
                }
                if ($PauseSeconds -gt 0) { Start-Sleep -Seconds $PauseSeconds }
            }
        }
        finally {
            if (-not $KeepTestFiles) {
                foreach ($path in $createdFiles) { Remove-AvdTestFile -LiteralPath $path }
                if ($createdDirectory -and (Test-Path -LiteralPath $t.Directory) -and -not (Get-ChildItem -LiteralPath $t.Directory -Force | Select-Object -First 1)) {
                    Remove-Item -LiteralPath $t.Directory -Force
                }
            }
        }
    }
}
finally {
    foreach ($process in @($running)) {
        if (-not $process.HasExited) { $process.Kill() }
    }
    if ($counterJob) {
        [System.IO.File]::WriteAllText($counterStop, '')
        if (-not (Wait-Job -Job $counterJob -Timeout (($SampleIntervalSeconds * 2) + 30))) { Stop-Job -Job $counterJob }
        Receive-Job -Job $counterJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $counterJob -Force
        Remove-Item -LiteralPath $counterStop -Force -ErrorAction SilentlyContinue
    }
}
#endregion

#region Report
$counterSummary = @()
if ((Test-Path -LiteralPath $counterCsv) -and $windows.Count -gt 0) {
    $samples = @(Import-Csv -LiteralPath $counterCsv | ConvertFrom-AvdCounterCsvRow)
    $counterSummary = @(Get-AvdCounterWindowSummary -Samples $samples -Windows $windows.ToArray())
}
$cpuPath = '\processor(_total)\% processor time'
foreach ($row in $results) {
    $match = $counterSummary | Where-Object { $_.Id -eq "$($row.Target)|$($row.Scenario)" -and $_.Path -like "*$cpuPath" } | Select-Object -First 1
    $hostCpu = $null
    if ($match) { $hostCpu = [math]::Round($match.Average, 1) }
    $row | Add-Member -NotePropertyName HostCpuPercent -NotePropertyValue $hostCpu
}

$scenarioSummary = @($results | Group-Object Target, Scenario | ForEach-Object {
        $group = @($_.Group)
        $ok = @($group | Where-Object { -not $_.Error })
        $worstP99 = $null
        if ($ok.Count) { $worstP99 = ($ok | Measure-Object P99Ms -Maximum).Maximum }
        [pscustomobject]@{
            Target = $group[0].Target; Scenario = $group[0].Scenario; Streams = $group.Count; Failed = $group.Count - $ok.Count
            TotalIops = [math]::Round((($ok | Measure-Object TotalIops -Sum).Sum), 1)
            TotalMiBps = [math]::Round((($ok | Measure-Object TotalMiBps -Sum).Sum), 2)
            WorstStreamP99Ms = $worstP99
        }
    })

$results | Select-Object -Property * -ExcludeProperty CommandLine |
    Export-Csv -LiteralPath (Join-Path $runDirectory 'results.csv') -NoTypeInformation -Encoding UTF8
$counterSummary | Export-Csv -LiteralPath (Join-Path $runDirectory 'counters-by-scenario.csv') -NoTypeInformation -Encoding UTF8
Write-AvdJson -LiteralPath (Join-Path $runDirectory 'report.json') -InputObject ([pscustomobject]@{
        ComputerName = $env:COMPUTERNAME; StartedLocal = $runStamp; DiskSpd = $diskSpd
        Settings = [pscustomobject]@{ Quick = [bool]$Quick; ElapsedSeconds = [math]::Round($runClock.Elapsed.TotalSeconds, 1); DurationSeconds = $DurationSeconds; WarmupSeconds = $WarmupSeconds; CooldownSeconds = $CooldownSeconds; CacheMode = $CacheMode; Saturate = [bool]$Saturate; SampleIntervalSeconds = $SampleIntervalSeconds }
        Workload = $workload; Targets = $targets; FileFill = $fills.ToArray(); Scenarios = $scenarioSummary; Streams = $results.ToArray()
        CountersMissing = $counterSelection.Missing; CounterWindows = $windows.ToArray(); CountersByScenario = $counterSummary
    })

Write-AvdStatus -Message ''
Write-AvdStatus 'Scenario summary:'
$scenarioSummary | Format-Table -AutoSize | Out-String -Width 200 | Write-AvdStatus
Write-AvdStatus 'Test file fill (large sequential write):'
$fills | Format-Table -AutoSize | Out-String -Width 200 | Write-AvdStatus
$runClock.Stop()
Write-AvdStatus ("Elapsed: {0:N0} s. Results: {1}" -f $runClock.Elapsed.TotalSeconds, $runDirectory)
$results
#endregion
