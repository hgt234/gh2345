#requires -Version 5.1
<#
.SYNOPSIS
    Shared, testable logic for Invoke-AvdStorageBenchmark.ps1.

.DESCRIPTION
    Pure functions for the Visual Studio workload model, DiskSpd command-line generation,
    DiskSpd XML result parsing, performance counter selection and windowed
    counter summaries. Only Write-AvdTestFile, Remove-AvdTestFile and the two
    Win32 volume helpers touch the host; everything else is side-effect free.

    Primary sources (DiskSpd v2.3, github.com/microsoft/diskspd):
      - CmdLineParser/CmdLineParser.cpp   : switch syntax (-b -d -W -C -t -o -w
        -r -rdpct -s -si -Sh -Sb -Sw -g -L -D -Z<size> -Rxml).
      - XmlResultParser/XmlResultParser.cpp : result element names
        (Results/TimeSpan/Thread/Target, Latency/Bucket/Percentile).
      - IORequestGenerator/IORequestGenerator.cpp : targets are opened with
        FILE_SHARE_READ | FILE_SHARE_WRITE, so concurrent DiskSpd processes may
        share one pre-created file.
#>

Set-StrictMode -Version 3.0

# Pinned DiskSpd release. The SHA-256 is the asset digest published by the
# GitHub releases API for v2.3 and was verified against a download.
$script:AvdDiskSpdRelease = [pscustomobject]@{
    Version = '2.3'
    Uri     = 'https://github.com/microsoft/diskspd/releases/download/v2.3/DiskSpd.ZIP'
    Sha256  = '18609981E8B04B4F645F1FD182AD0541615FE71722DE36A9A933C54F747218A3'
}

$script:AvdInvariant = [System.Globalization.CultureInfo]::InvariantCulture

function Get-AvdOptionalProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $InputObject,
        [Parameter(Mandatory)] [string] $Name,
        [AllowNull()] [object] $Default = $null
    )
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Get-AvdDefaultWorkload {
    <#
    .SYNOPSIS
        Returns the built-in Visual Studio (devenv) developer workload model.

    .DESCRIPTION
        Each scenario is a set of streams that run concurrently, one DiskSpd
        process per stream. Block sizes and concurrency are anchored on
        documented behavior where one exists; rates, write ratios and hot-set
        shapes are modeled and marked as such. Calibrate against a real session
        with -Mode Capture.

        Threads = 0 means "one thread per logical processor (max 32)", matching
        the Visual Studio default for "Maximum number of parallel project
        builds" (Microsoft Learn, "Configure build and run options in Visual
        Studio": the default matches the number of CPUs, maximum 32).

        Anchors:
          - NTFS default cluster size is 4 KiB (Microsoft Learn, "Default
            cluster size for NTFS, FAT, and exFAT"): small source, project and
            package files are read and written in 4 KiB units.
          - PDB symbol files are MSF containers with 4096-byte blocks (LLVM
            "The MSF File Format": valid sizes 512-4096, 4096 in practice).
          - SQLite default page size is 4096 bytes (sqlite.org); the C++
            browse database (.vs\...\Browse.VC.db) is SQLite.
          - NuGet global-packages is %userprofile%\.nuget\packages and the
            http-cache is %localappdata%\NuGet\v3-cache (Microsoft Learn,
            "Manage the global packages, cache, and temp folders"); with
            FSLogix both live inside the profile container, as does the default
            project location %userprofile%\source\repos.
        Modeled (no primary source): 64 KiB for memory-mapped assembly and
        build-output transfers, all write ratios, Editing IOPS caps and the
        hot-set percentages.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    function Get-StreamSpec {
        param($Name, $File, $BlockSizeBytes, $Pattern, $WritePercent, $Threads, $QueueDepth, $IopsLimitPerThread, $WriteThrough, $HotSpot, $Rationale)
        [pscustomobject]@{
            Name = $Name; File = $File; BlockSizeBytes = $BlockSizeBytes; Pattern = $Pattern
            WritePercent = $WritePercent; Threads = $Threads; QueueDepth = $QueueDepth
            IopsLimitPerThread = $IopsLimitPerThread; WriteThrough = $WriteThrough
            HotSpot = $HotSpot; Rationale = $Rationale
        }
    }

    [pscustomobject]@{
        Name    = 'VisualStudioDeveloper'
        Version = 1
        Files   = @(
            [pscustomobject]@{ Name = 'solution'; SizeMB = 1024; Purpose = 'Solution source, project files, obj and bin (source\repos)' }
            [pscustomobject]@{ Name = 'packages'; SizeMB = 1024; Purpose = 'NuGet global-packages, reference assemblies and PDB symbols' }
            [pscustomobject]@{ Name = 'state';    SizeMB = 256;  Purpose = '.vs folder IntelliSense/browse databases and component caches' }
            [pscustomobject]@{ Name = 'output';   SizeMB = 256;  Purpose = 'NuGet http-cache downloads, AutoRecover and logs' }
        )
        Scenarios = @(
            [pscustomobject]@{
                Name        = 'SolutionLoad'
                Description = 'Open a solution: read project and source files, page in reference assemblies, load the IntelliSense database.'
                Streams     = @(
                    Get-StreamSpec 'ProjectSourceRead' 'solution' 4096 'Random' 0 4 1 0 $false '90/10' 'Project, props/targets and source files are small and read whole in 4 KiB clusters. 90% of IO in 10% of the file models the hot working set (modeled).'
                    Get-StreamSpec 'AssemblyRead' 'packages' 65536 'Random' 0 2 1 0 $false '80/20' 'Reference assemblies from the NuGet global-packages folder are memory-mapped and paged in (64 KiB transfer size modeled).'
                    Get-StreamSpec 'IntelliSenseDbLoad' 'state' 4096 'Random' 20 1 1 0 $true '' 'IntelliSense/browse database (SQLite, 4096-byte pages) loaded and updated; commits are write-through.'
                )
            }
            [pscustomobject]@{
                Name        = 'Editing'
                Description = 'Steady-state editing: background code analysis, IntelliSense database updates, AutoRecover saves. Rates are modeled.'
                Streams     = @(
                    Get-StreamSpec 'SourceRead' 'solution' 4096 'Random' 0 2 1 50 $false '90/10' 'Background analysis and IntelliSense lookups against the hot set. Modeled rate: 50 IOPS per thread.'
                    Get-StreamSpec 'IntelliSenseDbWrite' 'state' 4096 'Random' 50 1 1 20 $true '' 'IntelliSense/browse database page updates (SQLite, 4096-byte pages). Modeled rate: 20 IOPS.'
                    Get-StreamSpec 'AutoRecoverWrite' 'output' 4096 'Sequential' 100 1 1 5 $true '' 'AutoRecover copies and logs written in small records. Modeled rate: 5 IOPS.'
                )
            }
            [pscustomobject]@{
                Name        = 'Build'
                Description = 'Solution build with parallel project builds (one per CPU): compilers read sources and references, write obj/bin.'
                Streams     = @(
                    Get-StreamSpec 'CompileSourceRead' 'solution' 4096 'Random' 0 0 1 0 $false '' 'Each parallel project build reads its source files (4 KiB clusters). Threads = CPU count, the Visual Studio default for parallel project builds.'
                    Get-StreamSpec 'ReferenceRead' 'packages' 65536 'Random' 0 2 1 0 $false '80/20' 'Compilers page in reference assemblies (64 KiB transfer size modeled).'
                    Get-StreamSpec 'ObjBinWrite' 'solution' 65536 'Sequential' 100 0 1 0 $false '' 'Assemblies and PDBs written to obj, then copied to bin, one writer per parallel project build (64 KiB transfer size modeled).'
                    Get-StreamSpec 'BuildStateWrite' 'state' 4096 'Random' 70 1 1 0 $false '' 'Incremental build state, assets and cache files under obj (small files, 4 KiB clusters; write ratio modeled).'
                )
            }
            [pscustomobject]@{
                Name        = 'NuGetRestore'
                Description = 'Package restore: download .nupkg files to the http-cache and extract them into the global-packages folder (both in the profile).'
                Streams     = @(
                    Get-StreamSpec 'PackageDownload' 'output' 65536 'Sequential' 100 2 1 0 $false '' 'Downloaded .nupkg files written sequentially to %localappdata%\NuGet\v3-cache (64 KiB transfer size modeled).'
                    Get-StreamSpec 'PackageExtract' 'packages' 4096 'Random' 80 4 1 0 $false '' 'Each package is fully expanded into many small files under %userprofile%\.nuget\packages (4 KiB clusters; write ratio modeled).'
                )
            }
            [pscustomobject]@{
                Name        = 'Debugging'
                Description = 'Start debugging: load built binaries and read PDB symbols.'
                Streams     = @(
                    Get-StreamSpec 'SymbolRead' 'packages' 4096 'Random' 0 2 1 0 $false '80/20' 'PDB symbol files are MSF containers with 4096-byte blocks; the debugger reads the blocks it needs.'
                    Get-StreamSpec 'BinaryLoad' 'solution' 65536 'Sequential' 0 1 1 0 $false '' 'Built assemblies and native images loaded for the debuggee (64 KiB transfer size modeled).'
                )
            }
        )
    }
}

function ConvertTo-AvdWorkload {
    <#
    .SYNOPSIS
        Validates and normalizes a workload object (built-in or from JSON).
        Throws one error listing every problem found.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [object] $InputObject)

    $errors = New-Object System.Collections.Generic.List[string]
    $files = @()
    foreach ($file in @(Get-AvdOptionalProperty $InputObject 'Files' @())) {
        $name = [string](Get-AvdOptionalProperty $file 'Name' '')
        $sizeMB = 0
        if (-not [int]::TryParse([string](Get-AvdOptionalProperty $file 'SizeMB' ''), [ref]$sizeMB) -or $sizeMB -lt 16 -or $sizeMB -gt 65536) {
            $errors.Add("File '$name': SizeMB must be an integer from 16 to 65536.")
        }
        if ($name -notmatch '^[A-Za-z0-9_-]{1,32}$') { $errors.Add("File name '$name' must be 1-32 characters of A-Z, 0-9, '_' or '-'.") }
        $files += [pscustomobject]@{ Name = $name; SizeMB = $sizeMB; Purpose = [string](Get-AvdOptionalProperty $file 'Purpose' '') }
    }
    if ($files.Count -eq 0) { $errors.Add('Workload must define at least one file.') }
    $fileNames = @($files | ForEach-Object { $_.Name })
    if (@($fileNames | Select-Object -Unique).Count -ne $fileNames.Count) { $errors.Add('File names must be unique.') }

    $scenarios = @()
    foreach ($scenario in @(Get-AvdOptionalProperty $InputObject 'Scenarios' @())) {
        $scenarioName = [string](Get-AvdOptionalProperty $scenario 'Name' '')
        if ($scenarioName -notmatch '^[A-Za-z0-9_-]{1,40}$') { $errors.Add("Scenario name '$scenarioName' must be 1-40 characters of A-Z, 0-9, '_' or '-'.") }
        $streams = @()
        foreach ($stream in @(Get-AvdOptionalProperty $scenario 'Streams' @())) {
            $streamName = [string](Get-AvdOptionalProperty $stream 'Name' '')
            $label = "$scenarioName/$streamName"
            if ($streamName -notmatch '^[A-Za-z0-9_-]{1,40}$') { $errors.Add("Stream name '$label' must be 1-40 characters of A-Z, 0-9, '_' or '-'.") }

            $intFields = [ordered]@{ BlockSizeBytes = @(512, 16777216); WritePercent = @(0, 100); Threads = @(0, 64); QueueDepth = @(1, 256); IopsLimitPerThread = @(0, 1000000) }
            $values = @{}
            foreach ($field in $intFields.Keys) {
                $parsed = 0
                $raw = [string](Get-AvdOptionalProperty $stream $field '')
                if ($field -eq 'IopsLimitPerThread' -and $raw -eq '') { $raw = '0' }
                $range = $intFields[$field]
                if (-not [int]::TryParse($raw, [ref]$parsed) -or $parsed -lt $range[0] -or $parsed -gt $range[1]) {
                    $errors.Add("Stream '$label': $field must be an integer from $($range[0]) to $($range[1]).")
                }
                $values[$field] = $parsed
            }
            # Unbuffered IO (FILE_FLAG_NO_BUFFERING) needs sector-aligned sizes; 4 KiB
            # covers 512e and 4Kn disks.
            if ($values.BlockSizeBytes % 4096 -ne 0) { $errors.Add("Stream '$label': BlockSizeBytes must be a multiple of 4096.") }

            $pattern = [string](Get-AvdOptionalProperty $stream 'Pattern' '')
            if ($pattern -notin @('Random', 'Sequential')) { $errors.Add("Stream '$label': Pattern must be 'Random' or 'Sequential'.") }

            $hotSpot = [string](Get-AvdOptionalProperty $stream 'HotSpot' '')
            if ($hotSpot -ne '') {
                if ($pattern -ne 'Random') { $errors.Add("Stream '$label': HotSpot is only valid with Pattern 'Random'.") }
                elseif ($hotSpot -notmatch '^(\d{1,3})/(\d{1,3})$' -or [int]$Matches[1] -lt 1 -or [int]$Matches[1] -gt 100 -or [int]$Matches[2] -lt 1 -or [int]$Matches[2] -gt 100) {
                    $errors.Add("Stream '$label': HotSpot must look like '90/10' (IO% / target%), each 1-100.")
                }
            }

            $file = [string](Get-AvdOptionalProperty $stream 'File' '')
            $fileDef = $files | Where-Object { $_.Name -eq $file } | Select-Object -First 1
            if ($null -eq $fileDef) { $errors.Add("Stream '$label': File '$file' is not defined in Files.") }
            elseif ($values.BlockSizeBytes -gt ([long]$fileDef.SizeMB * 1MB)) { $errors.Add("Stream '$label': BlockSizeBytes exceeds the size of file '$file'.") }

            $writeThrough = Get-AvdOptionalProperty $stream 'WriteThrough' $false
            if ($writeThrough -isnot [bool]) { $errors.Add("Stream '$label': WriteThrough must be true or false.") }

            $streams += [pscustomobject]@{
                Name = $streamName; File = $file; BlockSizeBytes = $values.BlockSizeBytes; Pattern = $pattern
                WritePercent = $values.WritePercent; Threads = $values.Threads; QueueDepth = $values.QueueDepth
                IopsLimitPerThread = $values.IopsLimitPerThread; WriteThrough = ($writeThrough -eq $true)
                HotSpot = $hotSpot; Rationale = [string](Get-AvdOptionalProperty $stream 'Rationale' '')
            }
        }
        if ($streams.Count -eq 0) { $errors.Add("Scenario '$scenarioName' must define at least one stream.") }
        $streamNames = @($streams | ForEach-Object { $_.Name })
        if (@($streamNames | Select-Object -Unique).Count -ne $streamNames.Count) { $errors.Add("Scenario '$scenarioName': stream names must be unique.") }
        $scenarios += [pscustomobject]@{ Name = $scenarioName; Description = [string](Get-AvdOptionalProperty $scenario 'Description' ''); Streams = $streams }
    }
    if ($scenarios.Count -eq 0) { $errors.Add('Workload must define at least one scenario.') }
    $scenarioNames = @($scenarios | ForEach-Object { $_.Name })
    if (@($scenarioNames | Select-Object -Unique).Count -ne $scenarioNames.Count) { $errors.Add('Scenario names must be unique.') }

    if ($errors.Count -gt 0) { throw ("Invalid workload definition:`n - " + ($errors -join "`n - ")) }

    [pscustomobject]@{
        Name      = [string](Get-AvdOptionalProperty $InputObject 'Name' 'Custom')
        Version   = Get-AvdOptionalProperty $InputObject 'Version' 1
        Files     = $files
        Scenarios = $scenarios
    }
}

function Get-AvdDiskSpdArgumentList {
    <#
    .SYNOPSIS
        Builds the DiskSpd argument list for one stream against one file.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Stream,
        [Parameter(Mandatory)] [string] $TargetFile,
        [Parameter(Mandatory)] [ValidateRange(1, 86400)] [int] $DurationSeconds,
        [ValidateRange(0, 3600)] [int] $WarmupSeconds = 0,
        [ValidateRange(0, 3600)] [int] $CooldownSeconds = 0,
        [ValidateSet('Unbuffered', 'Cached')] [string] $CacheMode = 'Unbuffered',
        [switch] $Saturate
    )

    if ($Stream.Threads -lt 1) { throw "Stream '$($Stream.Name)': Threads must be resolved to 1 or more before building DiskSpd arguments." }
    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add("-b$($Stream.BlockSizeBytes)")
    $arguments.Add("-d$DurationSeconds")
    $arguments.Add("-W$WarmupSeconds")
    $arguments.Add("-C$CooldownSeconds")
    $arguments.Add("-t$($Stream.Threads)")
    $arguments.Add("-o$($Stream.QueueDepth)")
    $arguments.Add("-w$($Stream.WritePercent)")

    if ($Stream.Pattern -eq 'Random') {
        # -r aligns random offsets to the block size by default.
        $arguments.Add('-r')
        if ($Stream.HotSpot) { $arguments.Add("-rdpct$($Stream.HotSpot)") }
    }
    elseif ($Stream.Threads -gt 1) {
        # -si: threads share one interlocked sequential offset (one stream),
        # instead of each thread re-reading the same offsets.
        $arguments.Add('-si')
    }
    else {
        $arguments.Add('-s')
    }

    if ($CacheMode -eq 'Unbuffered') {
        # -Sh = -Suw: no OS cache (FILE_FLAG_NO_BUFFERING) and write-through.
        $arguments.Add('-Sh')
    }
    elseif ($Stream.WriteThrough) {
        $arguments.Add('-Sw')
    }
    else {
        $arguments.Add('-Sb')
    }

    if ($Stream.IopsLimitPerThread -gt 0 -and -not $Saturate) {
        # -g<value> is per thread per target in bytes per millisecond; this
        # form is accepted by every DiskSpd 2.x release.
        $bytesPerMs = [long][math]::Ceiling(($Stream.IopsLimitPerThread * [double]$Stream.BlockSizeBytes) / 1000)
        $arguments.Add("-g$([math]::Max(1, $bytesPerMs))")
    }

    $arguments.Add('-L')          # latency statistics and percentiles
    $arguments.Add('-D1000')      # per-second IOPS buckets (IopsStdDev)
    $arguments.Add('-Z1M')        # 1 MiB random write source buffer; defeats compression/dedup
    $arguments.Add('-Rxml')
    $arguments.Add($TargetFile)
    return $arguments.ToArray()
}

function ConvertTo-AvdProcessArgumentString {
    <#
    .SYNOPSIS
        Joins arguments into one Windows command line. Windows PowerShell 5.1
        Start-Process -ArgumentList does not quote array elements, so paths with
        spaces must be quoted here.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string[]] $ArgumentList)

    $parts = foreach ($argument in $ArgumentList) {
        if ($argument.Contains('"')) { throw "Argument contains a double quote and cannot be passed safely: $argument" }
        if ($argument -eq '' -or $argument -match '\s') {
            # A trailing backslash would escape the closing quote; double it.
            $escaped = $argument -replace '(\\+)$', '$1$1'
            '"' + $escaped + '"'
        }
        else { $argument }
    }
    return ($parts -join ' ')
}

function Get-AvdXmlNumber {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.Xml.XmlNode] $Node, [Parameter(Mandatory)] [string] $XPath)
    $match = $Node.SelectSingleNode($XPath)
    if ($null -eq $match) { return $null }
    return [double]::Parse($match.InnerText, $script:AvdInvariant)
}

function ConvertFrom-AvdDiskSpdXml {
    <#
    .SYNOPSIS
        Parses DiskSpd -Rxml output into one summary object.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $XmlText)

    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $document.LoadXml($XmlText)

    $timeSpan = $document.SelectSingleNode('/Results/TimeSpan')
    if ($null -eq $timeSpan) { throw 'DiskSpd XML has no Results/TimeSpan element.' }
    $errorNode = $timeSpan.SelectSingleNode('Error')
    if ($null -ne $errorNode) { throw "DiskSpd reported: $($errorNode.InnerText)" }

    $seconds = Get-AvdXmlNumber $timeSpan 'TestTimeSeconds'
    if (-not $seconds -or $seconds -le 0) { throw 'DiskSpd XML has no positive TestTimeSeconds.' }

    $readBytes = 0.0; $writeBytes = 0.0; $readCount = 0.0; $writeCount = 0.0
    foreach ($target in $timeSpan.SelectNodes('Thread/Target')) {
        $readBytes += Get-AvdXmlNumber $target 'ReadBytes'
        $writeBytes += Get-AvdXmlNumber $target 'WriteBytes'
        $readCount += Get-AvdXmlNumber $target 'ReadCount'
        $writeCount += Get-AvdXmlNumber $target 'WriteCount'
    }

    $percentiles = @{}
    foreach ($bucket in $timeSpan.SelectNodes('Latency/Bucket')) {
        $percentileNode = $bucket.SelectSingleNode('Percentile')
        if ($null -eq $percentileNode) { continue }
        $percentiles[$percentileNode.InnerText] = [pscustomobject]@{
            Read  = Get-AvdXmlNumber $bucket 'ReadMilliseconds'
            Write = Get-AvdXmlNumber $bucket 'WriteMilliseconds'
            Total = Get-AvdXmlNumber $bucket 'TotalMilliseconds'
        }
    }
    function Get-Percentile([string] $Key, [string] $Kind) {
        if ($percentiles.ContainsKey($Key)) { return $percentiles[$Key].$Kind }
        return $null
    }
    function Round3($Value) { if ($null -eq $Value) { return $null }; return [math]::Round($Value, 3) }

    [pscustomobject]@{
        TestTimeSeconds = $seconds
        ThreadCount     = [int](Get-AvdXmlNumber $timeSpan 'ThreadCount')
        CpuUsagePercent = Get-AvdXmlNumber $timeSpan 'CpuUtilization/Average/UsagePercent'
        ReadCount       = [long]$readCount
        WriteCount      = [long]$writeCount
        ReadIops        = [math]::Round($readCount / $seconds, 1)
        WriteIops       = [math]::Round($writeCount / $seconds, 1)
        TotalIops       = [math]::Round(($readCount + $writeCount) / $seconds, 1)
        ReadMiBps       = [math]::Round($readBytes / 1MB / $seconds, 2)
        WriteMiBps      = [math]::Round($writeBytes / 1MB / $seconds, 2)
        TotalMiBps      = [math]::Round(($readBytes + $writeBytes) / 1MB / $seconds, 2)
        IopsStdDev      = Get-AvdXmlNumber $timeSpan 'Iops/IopsStdDev'
        AvgReadMs       = Round3 (Get-AvdXmlNumber $timeSpan 'Latency/AverageReadMilliseconds')
        AvgWriteMs      = Round3 (Get-AvdXmlNumber $timeSpan 'Latency/AverageWriteMilliseconds')
        AvgTotalMs      = Round3 (Get-AvdXmlNumber $timeSpan 'Latency/AverageTotalMilliseconds')
        P50Ms           = Round3 (Get-Percentile '50' 'Total')
        P95Ms           = Round3 (Get-Percentile '95' 'Total')
        P99Ms           = Round3 (Get-Percentile '99' 'Total')
        P999Ms          = Round3 (Get-Percentile '99.9' 'Total')
        ReadP99Ms       = Round3 (Get-Percentile '99' 'Read')
        WriteP99Ms      = Round3 (Get-Percentile '99' 'Write')
        MaxMs           = Round3 (Get-Percentile '100' 'Total')
    }
}

function Get-AvdDesiredCounterPath {
    <#
    .SYNOPSIS
        Counter paths collected during a run. Names are English; on a localized
        OS the missing ones are dropped by Select-AvdCounterPath and reported.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $diskCounters = @(
        'Disk Reads/sec', 'Disk Writes/sec', 'Disk Read Bytes/sec', 'Disk Write Bytes/sec',
        'Avg. Disk Bytes/Read', 'Avg. Disk Bytes/Write', 'Avg. Disk sec/Read', 'Avg. Disk sec/Write',
        'Current Disk Queue Length', '% Idle Time'
    )
    $paths = @()
    foreach ($set in @('LogicalDisk', 'PhysicalDisk')) {
        $paths += $diskCounters | ForEach-Object { "\$set(*)\$_" }
    }
    # FSLogix containers on Azure Files / Azure NetApp Files are reached over SMB.
    $paths += @(
        'Avg. sec/Read', 'Avg. sec/Write', 'Read Bytes/sec', 'Write Bytes/sec',
        'Read Requests/sec', 'Write Requests/sec', 'Avg. Bytes/Read', 'Avg. Bytes/Write',
        'Current Data Queue Length'
    ) | ForEach-Object { "\SMB Client Shares(*)\$_" }
    $paths += '\Processor(_Total)\% Processor Time'
    $paths += '\Memory\Available MBytes'
    return $paths
}

function Select-AvdCounterPath {
    <#
    .SYNOPSIS
        Keeps desired counter paths that exist on this host. Available paths
        come from (Get-Counter -ListSet <set>).Paths, which list multi-instance
        counters as '\Set(*)\Counter'; a desired instance such as '(_Total)' is
        matched against that wildcard form.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string[]] $Desired,
        [AllowEmptyCollection()] [Parameter(Mandatory)] [string[]] $Available
    )
    $availableSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $Available) { [void]$availableSet.Add($path) }

    $selected = @(); $missing = @()
    foreach ($path in $Desired) {
        $normalized = $path -replace '^(\\[^\\(]+)\([^)]*\)', '$1(*)'
        if ($availableSet.Contains($path) -or $availableSet.Contains($normalized)) { $selected += $path }
        else { $missing += $path }
    }
    [pscustomobject]@{ Selected = $selected; Missing = $missing }
}

function ConvertFrom-AvdCounterCsvRow {
    <#
    .SYNOPSIS
        Converts rows written by the counter collector (invariant culture,
        round-trip timestamps) into typed samples.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory, ValueFromPipeline)] [object] $Row)
    process {
        [pscustomobject]@{
            Timestamp    = [datetime]::Parse($Row.Timestamp, $script:AvdInvariant, [System.Globalization.DateTimeStyles]::RoundtripKind)
            Path         = [string]$Row.Path
            InstanceName = [string]$Row.InstanceName
            Value        = [double]::Parse($Row.Value, $script:AvdInvariant)
        }
    }
}

function Get-AvdCounterWindowSummary {
    <#
    .SYNOPSIS
        Averages counter samples inside each test window in one pass.
        Paths whose samples are all zero in a window are omitted.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()] [Parameter(Mandatory)] [object[]] $Samples,
        [Parameter(Mandatory)] [object[]] $Windows
    )
    $accumulators = @{}
    foreach ($sample in $Samples) {
        foreach ($window in $Windows) {
            if ($sample.Timestamp -lt $window.Start -or $sample.Timestamp -gt $window.End) { continue }
            $key = "$($window.Id)|$($sample.Path)"
            $acc = $accumulators[$key]
            if ($null -eq $acc) {
                $acc = [pscustomobject]@{ Id = $window.Id; Path = $sample.Path; Sum = 0.0; Max = [double]::MinValue; Count = 0 }
                $accumulators[$key] = $acc
            }
            $acc.Sum += $sample.Value
            $acc.Count++
            if ($sample.Value -gt $acc.Max) { $acc.Max = $sample.Value }
        }
    }
    $accumulators.Values |
        Where-Object { $_.Max -ne 0 } |
        Sort-Object Id, Path |
        ForEach-Object {
            [pscustomobject]@{
                Id      = $_.Id
                Path    = $_.Path
                Average = [math]::Round($_.Sum / $_.Count, 6)
                Maximum = [math]::Round($_.Max, 6)
                Samples = $_.Count
            }
        }
}

function Get-AvdObservedIoProfile {
    <#
    .SYNOPSIS
        Summarizes a captured real session per disk instance: read/write mix,
        IO-weighted average transfer size and latency. These are the sizes that
        reached the storage stack after the OS cache, which is what the
        unbuffered benchmark replays.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([AllowEmptyCollection()] [Parameter(Mandatory)] [object[]] $Samples)

    $pattern = '^\\\\[^\\]+\\(?<set>logicaldisk|physicaldisk)\((?<instance>[^)]*)\)\\(?<counter>.+)$'
    $byInstance = @{}
    foreach ($sample in $Samples) {
        if ($sample.Path -notmatch $pattern) { continue }
        $instance = $Matches.instance.ToLowerInvariant()
        if ($instance -eq '_total') { continue }
        $key = "$($Matches.set.ToLowerInvariant())|$instance"
        if (-not $byInstance.ContainsKey($key)) { $byInstance[$key] = @{} }
        $stamp = $sample.Timestamp.Ticks
        if (-not $byInstance[$key].ContainsKey($stamp)) { $byInstance[$key][$stamp] = @{} }
        $byInstance[$key][$stamp][$Matches.counter.ToLowerInvariant()] = $sample.Value
    }

    function Get-SuggestedBlockKiB([double] $Bytes) {
        if ($Bytes -le 0) { return $null }
        $kib = 4
        while ($kib * 1024 -lt $Bytes -and $kib -lt 16384) { $kib *= 2 }
        return $kib
    }

    foreach ($key in ($byInstance.Keys | Sort-Object)) {
        $set, $instance = $key -split '\|', 2
        $reads = 0.0; $writes = 0.0; $readBytes = 0.0; $writeBytes = 0.0; $readLatency = 0.0; $writeLatency = 0.0
        $totals = @()
        foreach ($point in $byInstance[$key].Values) {
            $r = 0.0; $w = 0.0
            if ($point.ContainsKey('disk reads/sec')) { $r = $point['disk reads/sec'] }
            if ($point.ContainsKey('disk writes/sec')) { $w = $point['disk writes/sec'] }
            $reads += $r; $writes += $w; $totals += ($r + $w)
            if ($point.ContainsKey('avg. disk bytes/read')) { $readBytes += $r * $point['avg. disk bytes/read'] }
            if ($point.ContainsKey('avg. disk bytes/write')) { $writeBytes += $w * $point['avg. disk bytes/write'] }
            if ($point.ContainsKey('avg. disk sec/read')) { $readLatency += $r * $point['avg. disk sec/read'] }
            if ($point.ContainsKey('avg. disk sec/write')) { $writeLatency += $w * $point['avg. disk sec/write'] }
        }
        if (($reads + $writes) -le 0) { continue }
        $sorted = @($totals | Sort-Object)
        $p95Index = [math]::Min($sorted.Count - 1, [int][math]::Ceiling(0.95 * $sorted.Count) - 1)
        $avgRead = 0.0; if ($reads -gt 0) { $avgRead = $readBytes / $reads }
        $avgWrite = 0.0; if ($writes -gt 0) { $avgWrite = $writeBytes / $writes }
        $readMs = $null; if ($reads -gt 0) { $readMs = [math]::Round($readLatency / $reads * 1000, 3) }
        $writeMs = $null; if ($writes -gt 0) { $writeMs = [math]::Round($writeLatency / $writes * 1000, 3) }
        [pscustomobject]@{
            CounterSet          = $set
            Instance            = $instance
            Samples             = $sorted.Count
            AvgReadIops         = [math]::Round($reads / $sorted.Count, 1)
            AvgWriteIops        = [math]::Round($writes / $sorted.Count, 1)
            P95TotalIops        = [math]::Round($sorted[[math]::Max(0, $p95Index)], 1)
            WritePercent        = [math]::Round(100 * $writes / ($reads + $writes), 1)
            AvgReadSizeKiB      = [math]::Round($avgRead / 1KB, 1)
            AvgWriteSizeKiB     = [math]::Round($avgWrite / 1KB, 1)
            SuggestedReadKiB    = Get-SuggestedBlockKiB $avgRead
            SuggestedWriteKiB   = Get-SuggestedBlockKiB $avgWrite
            AvgReadLatencyMs    = $readMs
            AvgWriteLatencyMs   = $writeMs
        }
    }
}

function Get-AvdBenchmarkPlan {
    <#
    .SYNOPSIS
        Expands targets x scenarios x streams into concrete DiskSpd runs.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [object[]] $Targets,
        [Parameter(Mandatory)] [pscustomobject] $Workload,
        [Parameter(Mandatory)] [int] $DurationSeconds,
        [int] $WarmupSeconds = 0,
        [int] $CooldownSeconds = 0,
        [ValidateSet('Unbuffered', 'Cached')] [string] $CacheMode = 'Unbuffered',
        [ValidateRange(1, 4096)] [int] $ProcessorCount = [Environment]::ProcessorCount,
        [switch] $Saturate
    )
    $autoThreads = [math]::Max(1, [math]::Min(32, $ProcessorCount))
    foreach ($target in $Targets) {
        foreach ($scenario in $Workload.Scenarios) {
            foreach ($workloadStream in $scenario.Streams) {
                # Threads = 0 resolves to one thread per logical processor (max 32).
                $stream = $workloadStream.PSObject.Copy()
                if ($stream.Threads -eq 0) { $stream.Threads = $autoThreads }
                # Windows path joined explicitly; Join-Path would require the drive to exist.
                $file = "{0}\{1}.dat" -f $target.Directory.TrimEnd([char]0x5C), $stream.File
                $arguments = Get-AvdDiskSpdArgumentList -Stream $stream -TargetFile $file -DurationSeconds $DurationSeconds `
                    -WarmupSeconds $WarmupSeconds -CooldownSeconds $CooldownSeconds -CacheMode $CacheMode -Saturate:$Saturate
                $limit = 0
                if (-not $Saturate) { $limit = $stream.IopsLimitPerThread }
                [pscustomobject]@{
                    Target             = $target.Name
                    TargetDirectory    = $target.Directory
                    Scenario           = $scenario.Name
                    Stream             = $stream.Name
                    File               = $file
                    BlockSizeKiB       = $stream.BlockSizeBytes / 1KB
                    Pattern            = $stream.Pattern
                    HotSpot            = $stream.HotSpot
                    WritePercent       = $stream.WritePercent
                    Threads            = $stream.Threads
                    QueueDepth         = $stream.QueueDepth
                    IopsLimitPerThread = $limit
                    Arguments          = $arguments
                    CommandLine        = 'diskspd.exe ' + (ConvertTo-AvdProcessArgumentString -ArgumentList $arguments)
                }
            }
        }
    }
}

function Get-AvdWorkloadSize {
    [CmdletBinding()]
    [OutputType([long])]
    param([Parameter(Mandatory)] [pscustomobject] $Workload)
    $total = [long]0
    foreach ($file in $Workload.Files) { $total += [long]$file.SizeMB * 1MB }
    return $total
}

function Get-AvdQuickSetting {
    <#
    .SYNOPSIS
        Timing and file-size preset for -Quick: a functional validation pass
        that fits two targets x five scenarios into about 60 seconds. Results
        from a 4-second window are a smoke test, not a sizing measurement.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    @{
        WarmupSeconds   = 1
        DurationSeconds = 4
        CooldownSeconds = 0
        PauseSeconds    = 0
        TestFileSizeMB  = 64
    }
}

function Get-AvdEstimatedRunSecond {
    <#
    .SYNOPSIS
        Estimated DiskSpd wall-clock time (excludes test file creation and
        process start-up, which are a few seconds per target).
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [int] $TargetCount,
        [Parameter(Mandatory)] [int] $ScenarioCount,
        [Parameter(Mandatory)] [int] $DurationSeconds,
        [int] $WarmupSeconds = 0,
        [int] $CooldownSeconds = 0,
        [int] $PauseSeconds = 0
    )
    return $TargetCount * $ScenarioCount * ($WarmupSeconds + $DurationSeconds + $CooldownSeconds + $PauseSeconds)
}

function Get-AvdResizedWorkload {
    <#
    .SYNOPSIS
        Returns a copy of the workload with every test file set to SizeMB,
        re-validated (block sizes must still fit). The input is not modified.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Workload,
        [Parameter(Mandatory)] [ValidateRange(16, 65536)] [int] $SizeMB
    )
    $copy = $Workload | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    foreach ($file in $copy.Files) { $file.SizeMB = $SizeMB }
    return ConvertTo-AvdWorkload -InputObject $copy
}

function Write-AvdTestFile {
    <#
    .SYNOPSIS
        Creates a new test file filled with pseudo-random data. Never
        overwrites: FileMode.CreateNew fails if the file exists. Returns the
        fill throughput (a large sequential write) as a bonus measurement.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $LiteralPath,
        [Parameter(Mandatory)] [ValidateRange(1MB, 68719476736)] [long] $SizeBytes
    )
    if (-not $PSCmdlet.ShouldProcess($LiteralPath, ("Create {0:N0} MiB test file" -f ($SizeBytes / 1MB)))) { return }

    $chunk = New-Object byte[] (1MB)
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    try { $rng.GetBytes($chunk) } finally { $rng.Dispose() }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $stream = New-Object System.IO.FileStream($LiteralPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 1MB)
    try {
        $written = [long]0; $index = [long]0
        while ($written -lt $SizeBytes) {
            # Stamp each chunk so no two 1 MiB blocks are identical.
            [System.BitConverter]::GetBytes($index).CopyTo($chunk, 0)
            $count = [int][math]::Min($chunk.Length, $SizeBytes - $written)
            $stream.Write($chunk, 0, $count)
            $written += $count; $index++
        }
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
    $stopwatch.Stop()

    [pscustomobject]@{
        Path      = $LiteralPath
        SizeBytes = $SizeBytes
        Seconds   = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        MiBps     = [math]::Round(($SizeBytes / 1MB) / [math]::Max(0.001, $stopwatch.Elapsed.TotalSeconds), 1)
    }
}

function Remove-AvdTestFile {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)] [string] $LiteralPath)
    if ((Test-Path -LiteralPath $LiteralPath -PathType Leaf) -and $PSCmdlet.ShouldProcess($LiteralPath, 'Remove benchmark test file')) {
        Remove-Item -LiteralPath $LiteralPath -Force
    }
}

function Get-AvdVolumeDeviceFromNtPath {
    <#
    .SYNOPSIS
        Extracts the volume device ('\Device\HarddiskVolume3') from an NT path
        returned by GetFinalPathNameByHandle with VOLUME_NAME_NT.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $NtPath)
    if ($NtPath -match '^(\\Device\\[^\\]+)') { return $Matches[1] }
    return $null
}

function Get-AvdCloudCacheProviderSummary {
    <#
    .SYNOPSIS
        Counts Cloud Cache providers by type from the CCDLocations value
        (REG_SZ or REG_MULTI_SZ). Only types are returned; share paths and
        key names are never copied into results.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([AllowNull()] [object] $CcdLocations)
    $text = (@($CcdLocations) | Where-Object { $null -ne $_ }) -join "`n"
    # Values are case sensitive per the FSLogix reference ('type=smb', 'type=azure').
    $smb = ([regex]::Matches($text, '(?<![A-Za-z])type=smb(?![A-Za-z])')).Count
    $azure = ([regex]::Matches($text, '(?<![A-Za-z])type=azure(?![A-Za-z])')).Count
    [pscustomobject]@{ Configured = ($text.Trim() -ne ''); Smb = $smb; Azure = $azure; Total = $smb + $azure }
}

function Get-AvdProfileStorageNote {
    <#
    .SYNOPSIS
        Explains what the Profile target actually measures, from discovered
        FSLogix state and volume identities.

    .DESCRIPTION
        FSLogix Cloud Cache (Microsoft Learn, "Cloud Cache Overview") runs the
        session from a local cache VHD(X) in CacheDirectory (default
        C:\ProgramData\FSLogix\Cache), hydrates missing data from the first
        CCDLocations provider, and flushes writes asynchronously to all
        providers; sign-out waits until providers have caught up.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()] [object] $FslogixEnabled,
        [Parameter(Mandatory)] [bool] $ProfileOnOsVolume,
        [Parameter(Mandatory)] [pscustomobject] $CloudCache,
        [AllowEmptyString()] [string] $CacheDirectory = '',
        [bool] $CacheOnOsVolume = $true
    )
    $notes = @()
    if ($FslogixEnabled -ne 1) { $notes += 'FSLogix Profiles is not enabled (HKLM\SOFTWARE\FSLogix\Profiles\Enabled is not 1).' }
    if ($ProfileOnOsVolume) {
        $notes += 'No FSLogix container is attached for this user (no FSLogix session key, and the profile path resolves to the OS volume), so this target measures the OS disk.'
        return $notes
    }
    if ($CloudCache.Configured) {
        $where = 'on the OS disk'
        if (-not $CacheOnOsVolume) { $where = 'not on the OS disk' }
        $notes += ("Cloud Cache: profile IO is served by the local cache in '{0}' ({1}). Writes flush asynchronously to {2} provider(s) (smb: {3}, azure: {4}); smb flushes appear in the SMB Client Shares counters. This target measures the local cache path plus flush overhead, not the remote share directly." -f $CacheDirectory, $where, $CloudCache.Total, $CloudCache.Smb, $CloudCache.Azure)
        $notes += 'Cloud Cache: test data is flushed to every provider and sign-out waits until providers catch up; prefer -Quick or -TestFileSizeMB to keep the flush small.'
    }
    else {
        $notes += 'Writing test files grows the dynamic profile VHD(X); it shrinks on the share only after compaction.'
    }
    return $notes
}

function Resolve-AvdProfileAttachment {
    <#
    .SYNOPSIS
        Decides whether the user's FSLogix container is attached and where.

    .DESCRIPTION
        FSLogix redirects C:\Users\<user> with its filter driver (no reparse
        point or mount point), so path and volume APIs report the OS volume.
        The primary signal is FSLogix's per-session key
        HKLM\SOFTWARE\FSLogix\Profiles\Sessions\<SID> and its Volume value
        (\\?\Volume{GUID}\). That key is not in the Microsoft Learn reference;
        it is used by community tooling and is treated as best effort, with the
        volume probe as fallback.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [bool] $SessionFound,
        [AllowEmptyString()] [AllowNull()] [string] $SessionVolume,
        [Parameter(Mandatory)] [bool] $ProbeOnOsVolume
    )
    if ($SessionVolume -match '^\\\\\?\\Volume\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}\\$') {
        return [pscustomobject]@{ Attached = $true; Source = 'FSLogixSession'; VolumeGuidPath = $SessionVolume }
    }
    if ($SessionFound) {
        return [pscustomobject]@{ Attached = $true; Source = 'FSLogixSessionNoVolume'; VolumeGuidPath = $null }
    }
    if (-not $ProbeOnOsVolume) {
        return [pscustomobject]@{ Attached = $true; Source = 'VolumeProbe'; VolumeGuidPath = $null }
    }
    return [pscustomobject]@{ Attached = $false; Source = 'None'; VolumeGuidPath = $null }
}

function Get-AvdVolumeSpace {
    <#
    .SYNOPSIS
        Free and total bytes for a volume root such as \\?\Volume{GUID}\.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $RootPath)
    Initialize-AvdNativeMethod
    $free = [uint64]0; $total = [uint64]0; $totalFree = [uint64]0
    if (-not [AvdStorageBenchmark.VolumeApi]::GetDiskFreeSpaceExW($RootPath, [ref]$free, [ref]$total, [ref]$totalFree)) {
        throw "GetDiskFreeSpaceEx failed for '$RootPath' (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
    }
    [pscustomobject]@{ FreeBytes = [long]$free; TotalBytes = [long]$total }
}

function Initialize-AvdNativeMethod {
    [CmdletBinding()]
    param()
    if ($null -eq ('AvdStorageBenchmark.VolumeApi' -as [type])) {
        # fileapi.h (Microsoft Learn): GetVolumePathNameW, GetDiskFreeSpaceExW,
        # CreateFileW and GetFinalPathNameByHandleW. GetVolumePathName works on
        # the path string and stops at C:\ for a profile redirected through a
        # reparse point; GetFinalPathNameByHandle resolves the opened directory
        # to the volume that really holds it.
        Add-Type -Namespace 'AvdStorageBenchmark' -Name 'VolumeApi' -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GetVolumePathNameW(string lpszFileName, System.Text.StringBuilder lpszVolumePathName, uint cchBufferLength);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GetDiskFreeSpaceExW(string lpDirectoryName, out ulong lpFreeBytesAvailable, out ulong lpTotalNumberOfBytes, out ulong lpTotalNumberOfFreeBytes);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern uint GetFinalPathNameByHandleW(Microsoft.Win32.SafeHandles.SafeFileHandle hFile, System.Text.StringBuilder lpszFilePath, uint cchFilePath, uint dwFlags);
'@
    }
}

function Get-AvdExistingAncestor {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Path)
    $current = $Path
    while ($current -and -not (Test-Path -LiteralPath $current -PathType Container)) {
        $current = Split-Path -Path $current -Parent
    }
    if (-not $current) { throw "No existing parent directory for '$Path'." }
    return $current
}

function Get-AvdFinalNtPath {
    <#
    .SYNOPSIS
        Opens a directory (read attributes only) and returns its final NT
        path, following junctions, symbolic links and mount points.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Directory)
    Initialize-AvdNativeMethod
    $FILE_READ_ATTRIBUTES = [uint32]0x80
    $FILE_SHARE_ALL = [uint32]0x7            # read | write | delete
    $OPEN_EXISTING = [uint32]3
    $FILE_FLAG_BACKUP_SEMANTICS = [uint32]0x02000000   # required to open a directory
    $VOLUME_NAME_NT = [uint32]0x2
    $handle = [AvdStorageBenchmark.VolumeApi]::CreateFileW($Directory, $FILE_READ_ATTRIBUTES, $FILE_SHARE_ALL, [IntPtr]::Zero, $OPEN_EXISTING, $FILE_FLAG_BACKUP_SEMANTICS, [IntPtr]::Zero)
    if ($handle.IsInvalid) { throw "CreateFile failed for '$Directory' (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))." }
    try {
        $buffer = New-Object System.Text.StringBuilder 1024
        $length = [AvdStorageBenchmark.VolumeApi]::GetFinalPathNameByHandleW($handle, $buffer, [uint32]$buffer.Capacity, $VOLUME_NAME_NT)
        if ($length -ge $buffer.Capacity) {
            $buffer = New-Object System.Text.StringBuilder ([int]$length + 1)
            $length = [AvdStorageBenchmark.VolumeApi]::GetFinalPathNameByHandleW($handle, $buffer, [uint32]$buffer.Capacity, $VOLUME_NAME_NT)
        }
        if ($length -eq 0) { throw "GetFinalPathNameByHandle failed for '$Directory' (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))." }
        return $buffer.ToString()
    }
    finally { $handle.Dispose() }
}

function Get-AvdVolumeInfo {
    <#
    .SYNOPSIS
        Returns the volume identity and free space for a path (or its nearest
        existing parent). VolumeDevice comes from the resolved final path, so
        an FSLogix profile attached from a VHD(X) reports the container volume
        even though its path starts with C:\.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $Path)
    Initialize-AvdNativeMethod
    $existing = Get-AvdExistingAncestor -Path $Path
    $probe = $existing.TrimEnd('\') + '\'
    $buffer = New-Object System.Text.StringBuilder 1024
    if (-not [AvdStorageBenchmark.VolumeApi]::GetVolumePathNameW($probe, $buffer, [uint32]$buffer.Capacity)) {
        throw "GetVolumePathName failed for '$probe' (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
    }
    $finalPath = $null; $device = $null
    try {
        $finalPath = Get-AvdFinalNtPath -Directory $existing
        $device = Get-AvdVolumeDeviceFromNtPath -NtPath $finalPath
    }
    catch { Write-Warning "Could not resolve the final volume of '$existing': $($_.Exception.Message)" }
    # GetDiskFreeSpaceEx operates on the target of a symbolic link (Microsoft Learn), so
    # free space is reported for the volume that really holds the directory.
    $free = [uint64]0; $total = [uint64]0; $totalFree = [uint64]0
    if (-not [AvdStorageBenchmark.VolumeApi]::GetDiskFreeSpaceExW($probe, [ref]$free, [ref]$total, [ref]$totalFree)) {
        throw "GetDiskFreeSpaceEx failed for '$probe' (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
    }
    [pscustomobject]@{
        Path           = $Path
        ExistingParent = $existing
        VolumeRoot     = $buffer.ToString()
        FinalPath      = $finalPath
        VolumeDevice   = $device
        FreeBytes      = [long]$free
        TotalBytes     = [long]$total
    }
}

function Test-AvdSameVolume {
    <#
    .SYNOPSIS
        Decides whether two Get-AvdVolumeInfo results are on the same volume.

    .DESCRIPTION
        Two independent signals: the resolved volume device (final path) and
        the volume capacity reported by GetDiskFreeSpaceEx. Either one
        differing means different volumes; this stays correct whether FSLogix
        reaches the container through a reparse point or through its filter
        driver. With neither device known, the path-string root is compared.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [pscustomobject] $First, [Parameter(Mandatory)] [pscustomobject] $Second)
    if ($First.VolumeDevice -and $Second.VolumeDevice -and
        -not [string]::Equals($First.VolumeDevice, $Second.VolumeDevice, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if ($First.TotalBytes -gt 0 -and $Second.TotalBytes -gt 0 -and $First.TotalBytes -ne $Second.TotalBytes) {
        return $false
    }
    if ($First.VolumeDevice -and $Second.VolumeDevice) { return $true }
    return [string]::Equals($First.VolumeRoot, $Second.VolumeRoot, [StringComparison]::OrdinalIgnoreCase)
}
