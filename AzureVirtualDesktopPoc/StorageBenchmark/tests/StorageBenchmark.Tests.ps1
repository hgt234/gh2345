#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
Offline Pester tests for AvdStorageBenchmark.Common.ps1. No DiskSpd, no
performance counters, no network. The XML fixture follows the element layout
emitted by DiskSpd v2.3 XmlResultParser.cpp.
#>

BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'AvdStorageBenchmark.Common.ps1')

    function Get-FixtureXml {
        param([switch] $Interrupted)
        if ($Interrupted) {
            return '<Results><System/><Profile/><TimeSpan><Error>The test was interrupted before the measurements began. No results are displayed.</Error></TimeSpan></Results>'
        }
        @'
<Results>
  <System><ComputerName>example</ComputerName></System>
  <Profile><TimeSpans><TimeSpan><Targets><Target><Path>x.dat</Path></Target></Targets></TimeSpan></TimeSpans></Profile>
  <TimeSpan>
    <TestTimeSeconds>10.00</TestTimeSeconds>
    <ThreadCount>2</ThreadCount>
    <RequestCount>0</RequestCount>
    <ProcCount>4</ProcCount>
    <CpuUtilization>
      <CPU><Socket>0</Socket><Id>0</Id><UsagePercent>9.00</UsagePercent></CPU>
      <Average><UsagePercent>3.50</UsagePercent><UserPercent>1.00</UserPercent><KernelPercent>2.50</KernelPercent><IdlePercent>96.50</IdlePercent></Average>
    </CpuUtilization>
    <Latency ReadHistoBuckets="1" WriteHistoBuckets="1" TotalHistoBuckets="1">
      <AverageReadMilliseconds>0.800</AverageReadMilliseconds>
      <ReadLatencyStdev>0.100</ReadLatencyStdev>
      <AverageWriteMilliseconds>2.000</AverageWriteMilliseconds>
      <WriteLatencyStdev>0.500</WriteLatencyStdev>
      <AverageTotalMilliseconds>1.100</AverageTotalMilliseconds>
      <LatencyStdev>0.400</LatencyStdev>
      <Bucket><Percentile>0</Percentile><ReadMilliseconds>0.100</ReadMilliseconds><WriteMilliseconds>0.900</WriteMilliseconds><TotalMilliseconds>0.100</TotalMilliseconds></Bucket>
      <Bucket><Percentile>50</Percentile><ReadMilliseconds>0.700</ReadMilliseconds><WriteMilliseconds>1.800</WriteMilliseconds><TotalMilliseconds>0.900</TotalMilliseconds></Bucket>
      <Bucket><Percentile>95</Percentile><ReadMilliseconds>1.500</ReadMilliseconds><WriteMilliseconds>3.000</WriteMilliseconds><TotalMilliseconds>2.500</TotalMilliseconds></Bucket>
      <Bucket><Percentile>99</Percentile><ReadMilliseconds>2.000</ReadMilliseconds><WriteMilliseconds>4.000</WriteMilliseconds><TotalMilliseconds>3.500</TotalMilliseconds></Bucket>
      <Bucket><Percentile>99.9</Percentile><ReadMilliseconds>5.000</ReadMilliseconds><WriteMilliseconds>9.000</WriteMilliseconds><TotalMilliseconds>8.000</TotalMilliseconds></Bucket>
      <Bucket><Percentile>100</Percentile><ReadMilliseconds>12.000</ReadMilliseconds><WriteMilliseconds>20.000</WriteMilliseconds><TotalMilliseconds>20.000</TotalMilliseconds></Bucket>
    </Latency>
    <Iops><ReadIopsStdDev>5.000</ReadIopsStdDev><WriteIopsStdDev>2.000</WriteIopsStdDev><IopsStdDev>6.000</IopsStdDev>
      <Bucket SampleMillisecond="1000" Read="700" Write="300" Total="1000"/>
    </Iops>
    <Thread><Id>0</Id>
      <Target><Path>x.dat</Path><BytesCount>20480000</BytesCount><FileSize>1073741824</FileSize><IOCount>5000</IOCount>
        <ReadBytes>14336000</ReadBytes><ReadCount>3500</ReadCount><WriteBytes>6144000</WriteBytes><WriteCount>1500</WriteCount></Target>
    </Thread>
    <Thread><Id>1</Id>
      <Target><Path>x.dat</Path><BytesCount>20480000</BytesCount><FileSize>1073741824</FileSize><IOCount>5000</IOCount>
        <ReadBytes>14336000</ReadBytes><ReadCount>3500</ReadCount><WriteBytes>6144000</WriteBytes><WriteCount>1500</WriteCount></Target>
    </Thread>
  </TimeSpan>
</Results>
'@
    }

    function Get-ValidStream {
        [pscustomobject]@{
            Name = 'S'; File = 'f'; BlockSizeBytes = 4096; Pattern = 'Random'; WritePercent = 0; Threads = 1; QueueDepth = 1
            IopsLimitPerThread = 0; WriteThrough = $false; HotSpot = ''; Rationale = ''
        }
    }

    function Get-WorkloadWith {
        param([pscustomobject] $Stream)
        [pscustomobject]@{
            Name = 'T'; Files = @([pscustomobject]@{ Name = 'f'; SizeMB = 64 })
            Scenarios = @([pscustomobject]@{ Name = 'Sc'; Streams = @($Stream) })
        }
    }
}

Describe 'Default Visual Studio workload' {
    BeforeAll { $script:workload = ConvertTo-AvdWorkload -InputObject (Get-AvdDefaultWorkload) }

    It 'passes validation and defines the five scenarios' {
        @($workload.Scenarios.Name) | Should -Be @('SolutionLoad', 'Editing', 'Build', 'NuGetRestore', 'Debugging')
    }

    It 'uses only 4 KiB and 64 KiB blocks' {
        $sizes = @($workload.Scenarios.Streams.BlockSizeBytes | Select-Object -Unique | Sort-Object)
        $sizes | Should -Be @(4096, 65536)
    }

    It 'keeps every stream at QD 1 per thread' {
        @($workload.Scenarios.Streams | Where-Object { $_.QueueDepth -ne 1 }).Count | Should -Be 0
    }

    It 'documents a rationale for every stream' {
        @($workload.Scenarios.Streams | Where-Object { -not $_.Rationale }).Count | Should -Be 0
    }

    It 'round-trips through JSON (ExportWorkload -> WorkloadPath)' {
        $json = $workload | ConvertTo-Json -Depth 12
        $again = ConvertTo-AvdWorkload -InputObject ($json | ConvertFrom-Json)
        ($again | ConvertTo-Json -Depth 12) | Should -Be $json
    }

    It 'totals 2.5 GiB of test files' {
        Get-AvdWorkloadSize -Workload $workload | Should -Be (2560MB)
    }
}

Describe 'ConvertTo-AvdWorkload validation' {
    It 'rejects a block size that is not 4 KiB aligned' {
        $s = Get-ValidStream; $s.BlockSizeBytes = 6000
        { ConvertTo-AvdWorkload -InputObject (Get-WorkloadWith $s) } | Should -Throw '*multiple of 4096*'
    }

    It 'rejects an unknown pattern' {
        $s = Get-ValidStream; $s.Pattern = 'Strided'
        { ConvertTo-AvdWorkload -InputObject (Get-WorkloadWith $s) } | Should -Throw "*Pattern must be*"
    }

    It 'rejects a stream that references an undefined file' {
        $s = Get-ValidStream; $s.File = 'missing'
        { ConvertTo-AvdWorkload -InputObject (Get-WorkloadWith $s) } | Should -Throw "*File 'missing' is not defined*"
    }

    It 'rejects a hot spot on a sequential stream' {
        $s = Get-ValidStream; $s.Pattern = 'Sequential'; $s.HotSpot = '90/10'
        { ConvertTo-AvdWorkload -InputObject (Get-WorkloadWith $s) } | Should -Throw '*only valid with Pattern*'
    }

    It 'rejects a malformed hot spot' {
        $s = Get-ValidStream; $s.HotSpot = '90-10'
        { ConvertTo-AvdWorkload -InputObject (Get-WorkloadWith $s) } | Should -Throw "*HotSpot must look like*"
    }

    It 'rejects a write percent above 100' {
        $s = Get-ValidStream; $s.WritePercent = 101
        { ConvertTo-AvdWorkload -InputObject (Get-WorkloadWith $s) } | Should -Throw '*WritePercent*'
    }

    It 'reports every problem in one error' {
        $s = Get-ValidStream; $s.BlockSizeBytes = 6000; $s.Threads = 65
        $message = $null
        try { ConvertTo-AvdWorkload -InputObject (Get-WorkloadWith $s) } catch { $message = $_.Exception.Message }
        $message | Should -BeLike '*BlockSizeBytes*'
        $message | Should -BeLike '*Threads*'
    }
}

Describe 'Get-AvdDiskSpdArgumentList' {
    It 'builds an unbuffered random hot-spot read' {
        $s = Get-ValidStream; $s.Threads = 4; $s.HotSpot = '90/10'
        $a = Get-AvdDiskSpdArgumentList -Stream $s -TargetFile 'C:\t\workspace.dat' -DurationSeconds 60 -WarmupSeconds 10 -CooldownSeconds 5
        $a | Should -Contain '-b4096'
        $a | Should -Contain '-d60'
        $a | Should -Contain '-W10'
        $a | Should -Contain '-C5'
        $a | Should -Contain '-t4'
        $a | Should -Contain '-o1'
        $a | Should -Contain '-w0'
        $a | Should -Contain '-r'
        $a | Should -Contain '-rdpct90/10'
        $a | Should -Contain '-Sh'
        $a | Should -Contain '-L'
        $a | Should -Contain '-Rxml'
        $a | Should -Not -Contain '-s'
        $a[-1] | Should -Be 'C:\t\workspace.dat'
    }

    It 'uses an interlocked sequential stream when more than one thread' {
        $s = Get-ValidStream; $s.Pattern = 'Sequential'; $s.Threads = 2
        $a = Get-AvdDiskSpdArgumentList -Stream $s -TargetFile 'x' -DurationSeconds 10
        $a | Should -Contain '-si'
        $a | Should -Not -Contain '-r'
    }

    It 'uses plain -s for a single-thread sequential stream' {
        $s = Get-ValidStream; $s.Pattern = 'Sequential'
        Get-AvdDiskSpdArgumentList -Stream $s -TargetFile 'x' -DurationSeconds 10 | Should -Contain '-s'
    }

    It 'converts an IOPS limit to bytes per millisecond, rounded up' {
        $s = Get-ValidStream; $s.IopsLimitPerThread = 50
        # 50 IOPS x 4096 B / 1000 ms = 204.8 -> 205
        Get-AvdDiskSpdArgumentList -Stream $s -TargetFile 'x' -DurationSeconds 10 | Should -Contain '-g205'
    }

    It 'drops the IOPS limit with -Saturate' {
        $s = Get-ValidStream; $s.IopsLimitPerThread = 50
        $a = Get-AvdDiskSpdArgumentList -Stream $s -TargetFile 'x' -DurationSeconds 10 -Saturate
        @($a | Where-Object { $_ -like '-g*' }).Count | Should -Be 0
    }

    It 'uses -Sw in cached mode for write-through streams and -Sb otherwise' {
        $s = Get-ValidStream; $s.WriteThrough = $true
        Get-AvdDiskSpdArgumentList -Stream $s -TargetFile 'x' -DurationSeconds 10 -CacheMode Cached | Should -Contain '-Sw'
        $s.WriteThrough = $false
        Get-AvdDiskSpdArgumentList -Stream $s -TargetFile 'x' -DurationSeconds 10 -CacheMode Cached | Should -Contain '-Sb'
    }
}

Describe 'Get-AvdDiskSpdArgumentList thread guard' {
    It 'refuses an unresolved Threads = 0 stream' {
        $s = Get-ValidStream; $s.Threads = 0
        { Get-AvdDiskSpdArgumentList -Stream $s -TargetFile 'x' -DurationSeconds 10 } | Should -Throw '*must be resolved*'
    }
}

Describe 'ConvertTo-AvdProcessArgumentString' {
    It 'quotes arguments with spaces only' {
        ConvertTo-AvdProcessArgumentString -ArgumentList @('-b4096', 'C:\My Data\w.dat') | Should -Be '-b4096 "C:\My Data\w.dat"'
    }

    It 'doubles a trailing backslash inside quotes' {
        ConvertTo-AvdProcessArgumentString -ArgumentList @('C:\My Data\') | Should -Be '"C:\My Data\\"'
    }

    It 'refuses embedded double quotes' {
        { ConvertTo-AvdProcessArgumentString -ArgumentList @('a"b') } | Should -Throw '*double quote*'
    }
}

Describe 'ConvertFrom-AvdDiskSpdXml' {
    BeforeAll { $script:r = ConvertFrom-AvdDiskSpdXml -XmlText (Get-FixtureXml) }

    It 'sums IO across threads and divides by test time' {
        $r.ReadIops | Should -Be 700
        $r.WriteIops | Should -Be 300
        $r.TotalIops | Should -Be 1000
    }

    It 'computes MiB/s from bytes' {
        $r.TotalMiBps | Should -Be ([math]::Round(40960000 / 1MB / 10, 2))
    }

    It 'reads latency averages and percentiles from TimeSpan/Latency only (not Iops buckets)' {
        $r.AvgReadMs | Should -Be 0.8
        $r.AvgWriteMs | Should -Be 2
        $r.P50Ms | Should -Be 0.9
        $r.P95Ms | Should -Be 2.5
        $r.P99Ms | Should -Be 3.5
        $r.P999Ms | Should -Be 8
        $r.ReadP99Ms | Should -Be 2
        $r.WriteP99Ms | Should -Be 4
        $r.MaxMs | Should -Be 20
    }

    It 'reads CPU and IOPS deviation' {
        $r.CpuUsagePercent | Should -Be 3.5
        $r.IopsStdDev | Should -Be 6
        $r.ThreadCount | Should -Be 2
    }

    It 'throws on an interrupted run' {
        { ConvertFrom-AvdDiskSpdXml -XmlText (Get-FixtureXml -Interrupted) } | Should -Throw '*interrupted*'
    }

    It 'throws on non-DiskSpd XML' {
        { ConvertFrom-AvdDiskSpdXml -XmlText '<Other/>' } | Should -Throw '*Results/TimeSpan*'
    }

    It 'parses numbers independent of the current culture' {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
            (ConvertFrom-AvdDiskSpdXml -XmlText (Get-FixtureXml)).P999Ms | Should -Be 8
        }
        finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous }
    }
}

Describe 'Select-AvdCounterPath' {
    It 'matches a specific instance against the wildcard ListSet path and reports missing ones' {
        $available = @('\Processor(*)\% Processor Time', '\Memory\Available MBytes', '\LogicalDisk(*)\Disk Reads/sec')
        $desired = @('\Processor(_Total)\% Processor Time', '\Memory\Available MBytes', '\LogicalDisk(*)\Disk Reads/sec', '\SMB Client Shares(*)\Avg. sec/Read')
        $result = Select-AvdCounterPath -Desired $desired -Available $available
        $result.Selected | Should -Be @('\Processor(_Total)\% Processor Time', '\Memory\Available MBytes', '\LogicalDisk(*)\Disk Reads/sec')
        $result.Missing | Should -Be @('\SMB Client Shares(*)\Avg. sec/Read')
    }

    It 'is case-insensitive' {
        (Select-AvdCounterPath -Desired @('\memory\available mbytes') -Available @('\Memory\Available MBytes')).Selected.Count | Should -Be 1
    }
}

Describe 'Counter CSV rows and windows' {
    BeforeAll {
        $script:t0 = [datetime]::new(2026, 1, 1, 12, 0, 0, [DateTimeKind]::Local)
        $script:samples = @(
            foreach ($i in 0..9) {
                [pscustomobject]@{ Timestamp = $t0.AddSeconds($i); Path = '\\h\processor(_total)\% processor time'; InstanceName = '_total'; Value = [double](10 * $i) }
                [pscustomobject]@{ Timestamp = $t0.AddSeconds($i); Path = '\\h\logicaldisk(d:)\disk reads/sec'; InstanceName = 'd:'; Value = 0.0 }
            }
        )
    }

    It 'parses invariant numbers and round-trip timestamps' {
        $row = [pscustomobject]@{ Timestamp = $t0.ToString('o'); Path = 'p'; InstanceName = 'i'; Value = '1234.5' }
        $parsed = $row | ConvertFrom-AvdCounterCsvRow
        $parsed.Value | Should -Be 1234.5
        $parsed.Timestamp | Should -Be $t0
    }

    It 'averages only samples inside each window and drops all-zero counters' {
        $windows = @(
            [pscustomobject]@{ Id = 'A'; Start = $t0.AddSeconds(2); End = $t0.AddSeconds(4) }
            [pscustomobject]@{ Id = 'B'; Start = $t0.AddSeconds(8); End = $t0.AddSeconds(20) }
        )
        $summary = @(Get-AvdCounterWindowSummary -Samples $samples -Windows $windows)
        $summary.Count | Should -Be 2
        ($summary | Where-Object Id -eq 'A').Average | Should -Be 30
        ($summary | Where-Object Id -eq 'A').Samples | Should -Be 3
        ($summary | Where-Object Id -eq 'B').Maximum | Should -Be 90
    }
}

Describe 'Get-AvdObservedIoProfile' {
    It 'weights transfer size and latency by IO count and suggests a power-of-two block' {
        $t0 = Get-Date
        $rows = foreach ($p in @(
                @{ s = 0; r = 100; br = 4096; w = 10; bw = 65536; lr = 0.001; lw = 0.004 }
                @{ s = 1; r = 300; br = 8192; w = 30; bw = 65536; lr = 0.003; lw = 0.004 }
            )) {
            $ts = $t0.AddSeconds($p.s)
            [pscustomobject]@{ Timestamp = $ts; Path = '\\h\logicaldisk(c:)\disk reads/sec'; Value = [double]$p.r }
            [pscustomobject]@{ Timestamp = $ts; Path = '\\h\logicaldisk(c:)\disk writes/sec'; Value = [double]$p.w }
            [pscustomobject]@{ Timestamp = $ts; Path = '\\h\logicaldisk(c:)\avg. disk bytes/read'; Value = [double]$p.br }
            [pscustomobject]@{ Timestamp = $ts; Path = '\\h\logicaldisk(c:)\avg. disk bytes/write'; Value = [double]$p.bw }
            [pscustomobject]@{ Timestamp = $ts; Path = '\\h\logicaldisk(c:)\avg. disk sec/read'; Value = [double]$p.lr }
            [pscustomobject]@{ Timestamp = $ts; Path = '\\h\logicaldisk(c:)\avg. disk sec/write'; Value = [double]$p.lw }
            [pscustomobject]@{ Timestamp = $ts; Path = '\\h\logicaldisk(_total)\disk reads/sec'; Value = [double]$p.r }
        }
        $result = @(Get-AvdObservedIoProfile -Samples @($rows))
        $result.Count | Should -Be 1
        $result[0].Instance | Should -Be 'c:'
        $result[0].AvgReadIops | Should -Be 200
        $result[0].WritePercent | Should -Be ([math]::Round(100 * 40 / 440, 1))
        # (100*4096 + 300*8192) / 400 = 7168 B = 7 KiB -> 8 KiB block
        $result[0].AvgReadSizeKiB | Should -Be 7
        $result[0].SuggestedReadKiB | Should -Be 8
        $result[0].SuggestedWriteKiB | Should -Be 64
        # (100*1 + 300*3) / 400 = 2.5 ms
        $result[0].AvgReadLatencyMs | Should -Be 2.5
    }

    It 'skips disks with no IO' {
        $row = [pscustomobject]@{ Timestamp = (Get-Date); Path = '\\h\physicaldisk(0 c:)\disk reads/sec'; Value = 0.0 }
        @(Get-AvdObservedIoProfile -Samples @($row)).Count | Should -Be 0
    }
}

Describe 'Get-AvdBenchmarkPlan' {
    It 'expands targets x scenarios x streams and points each stream at its file' {
        $workload = ConvertTo-AvdWorkload -InputObject (Get-AvdDefaultWorkload)
        $targets = @(
            [pscustomobject]@{ Name = 'OsDisk'; Directory = 'C:\b' }
            [pscustomobject]@{ Name = 'Profile'; Directory = 'C:\Users\u\b' }
        )
        $plan = @(Get-AvdBenchmarkPlan -Targets $targets -Workload $workload -DurationSeconds 30)
        $plan.Count | Should -Be (2 * 14)
        $state = $plan | Where-Object { $_.Target -eq 'Profile' -and $_.Stream -eq 'IntelliSenseDbWrite' }
        $state.File | Should -BeLike '*state.dat'
        $state.IopsLimitPerThread | Should -Be 20
        $state.CommandLine | Should -BeLike 'diskspd.exe -b4096 *'
    }

    It 'resolves Threads = 0 to the processor count, capped at 32, without changing the workload' {
        $workload = ConvertTo-AvdWorkload -InputObject (Get-AvdDefaultWorkload)
        $target = @([pscustomobject]@{ Name = 'OsDisk'; Directory = 'C:\b' })
        $plan4 = @(Get-AvdBenchmarkPlan -Targets $target -Workload $workload -DurationSeconds 30 -ProcessorCount 4)
        ($plan4 | Where-Object Stream -eq 'CompileSourceRead').Threads | Should -Be 4
        ($plan4 | Where-Object Stream -eq 'ObjBinWrite').Arguments | Should -Contain '-t4'
        $plan64 = @(Get-AvdBenchmarkPlan -Targets $target -Workload $workload -DurationSeconds 30 -ProcessorCount 64)
        ($plan64 | Where-Object Stream -eq 'CompileSourceRead').Threads | Should -Be 32
        ($workload.Scenarios | Where-Object Name -eq 'Build').Streams[0].Threads | Should -Be 0
    }

    It 'puts restore IO on the packages and output files' {
        $workload = ConvertTo-AvdWorkload -InputObject (Get-AvdDefaultWorkload)
        $plan = @(Get-AvdBenchmarkPlan -Targets @([pscustomobject]@{ Name = 'Profile'; Directory = 'C:\Users\u\b' }) -Workload $workload -DurationSeconds 30)
        ($plan | Where-Object Stream -eq 'PackageExtract').File | Should -Be 'C:\Users\u\b\packages.dat'
        ($plan | Where-Object Stream -eq 'PackageDownload').File | Should -Be 'C:\Users\u\b\output.dat'
    }

    It 'reports zero IOPS limit when saturating' {
        $workload = ConvertTo-AvdWorkload -InputObject (Get-AvdDefaultWorkload)
        $plan = @(Get-AvdBenchmarkPlan -Targets @([pscustomobject]@{ Name = 'OsDisk'; Directory = 'C:\b' }) -Workload $workload -DurationSeconds 30 -Saturate)
        @($plan | Where-Object { $_.IopsLimitPerThread -ne 0 }).Count | Should -Be 0
    }
}

Describe 'Write-AvdTestFile and Remove-AvdTestFile' {
    It 'creates a file of the exact size with non-repeating chunks' {
        $path = Join-Path $TestDrive 'w.dat'
        $fill = Write-AvdTestFile -LiteralPath $path -SizeBytes (3MB)
        (Get-Item -LiteralPath $path).Length | Should -Be (3MB)
        $fill.MiBps | Should -BeGreaterThan 0
        $bytes = [System.IO.File]::ReadAllBytes($path)
        [System.BitConverter]::ToInt64($bytes, 0) | Should -Be 0
        [System.BitConverter]::ToInt64($bytes, 1MB) | Should -Be 1
    }

    It 'never overwrites an existing file' {
        $path = Join-Path $TestDrive 'existing.dat'
        Set-Content -LiteralPath $path -Value 'keep'
        { Write-AvdTestFile -LiteralPath $path -SizeBytes (1MB) } | Should -Throw
        Get-Content -LiteralPath $path | Should -Be 'keep'
    }

    It 'makes no changes under -WhatIf' {
        $path = Join-Path $TestDrive 'whatif.dat'
        Write-AvdTestFile -LiteralPath $path -SizeBytes (1MB) -WhatIf | Should -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -BeFalse

        $keep = Join-Path $TestDrive 'keep.dat'
        Set-Content -LiteralPath $keep -Value 'x'
        Remove-AvdTestFile -LiteralPath $keep -WhatIf
        Test-Path -LiteralPath $keep | Should -BeTrue
    }

    It 'removes a test file' {
        $path = Join-Path $TestDrive 'gone.dat'
        Set-Content -LiteralPath $path -Value 'x'
        Remove-AvdTestFile -LiteralPath $path
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

Describe 'Quick validation preset' {
    BeforeAll {
        $script:workload = ConvertTo-AvdWorkload -InputObject (Get-AvdDefaultWorkload)
        $script:quick = Get-AvdQuickSetting
    }

    It 'fits OsDisk + Profile x all scenarios into 60 seconds of DiskSpd time' {
        $seconds = Get-AvdEstimatedRunSecond -TargetCount 2 -ScenarioCount $workload.Scenarios.Count `
            -DurationSeconds $quick.DurationSeconds -WarmupSeconds $quick.WarmupSeconds -CooldownSeconds $quick.CooldownSeconds -PauseSeconds $quick.PauseSeconds
        $seconds | Should -BeLessOrEqual 60
    }

    It 'keeps a measured window of at least 3 seconds' {
        $quick.DurationSeconds | Should -BeGreaterOrEqual 3
    }

    It 'estimates the default timings at about 13 minutes for two targets' {
        Get-AvdEstimatedRunSecond -TargetCount 2 -ScenarioCount 5 -DurationSeconds 60 -WarmupSeconds 10 -CooldownSeconds 5 -PauseSeconds 5 | Should -Be 800
    }

    It 'resizes every test file on a copy and leaves the original untouched' {
        $small = Get-AvdResizedWorkload -Workload $workload -SizeMB $quick.TestFileSizeMB
        @($small.Files.SizeMB | Select-Object -Unique) | Should -Be @(64)
        Get-AvdWorkloadSize -Workload $small | Should -Be (4 * 64MB)
        Get-AvdWorkloadSize -Workload $workload | Should -Be (2560MB)
        @($small.Scenarios.Streams).Count | Should -Be @($workload.Scenarios.Streams).Count
    }

    It 'produces quick DiskSpd arguments with 1 s warm-up, 4 s duration and no cool-down' {
        $plan = @(Get-AvdBenchmarkPlan -Targets @([pscustomobject]@{ Name = 'OsDisk'; Directory = 'C:\b' }) -Workload $workload `
            -DurationSeconds $quick.DurationSeconds -WarmupSeconds $quick.WarmupSeconds -CooldownSeconds $quick.CooldownSeconds -ProcessorCount 4)
        $plan[0].Arguments | Should -Contain '-W1'
        $plan[0].Arguments | Should -Contain '-d4'
        $plan[0].Arguments | Should -Contain '-C0'
    }
}

Describe 'Volume identity (FSLogix profile on C:\Users path)' {
    It 'extracts the volume device from an NT final path' {
        Get-AvdVolumeDeviceFromNtPath -NtPath '\Device\HarddiskVolume12\Profile\AvdStorageBenchmark' | Should -Be '\Device\HarddiskVolume12'
        Get-AvdVolumeDeviceFromNtPath -NtPath 'C:\Users\u' | Should -BeNullOrEmpty
    }

    It 'treats a profile with the same C:\ root but a different resolved device as a separate volume (regression)' {
        $os = [pscustomobject]@{ VolumeRoot = 'C:\'; VolumeDevice = '\Device\HarddiskVolume3'; TotalBytes = 136365211648 }
        $profileVolume = [pscustomobject]@{ VolumeRoot = 'C:\'; VolumeDevice = '\Device\HarddiskVolume12'; TotalBytes = 136365211648 }
        Test-AvdSameVolume -First $profileVolume -Second $os | Should -BeFalse
    }

    It 'treats a different capacity as a separate volume even when the device matches (filter-driver redirection)' {
        $os = [pscustomobject]@{ VolumeRoot = 'C:\'; VolumeDevice = '\Device\HarddiskVolume3'; TotalBytes = 136365211648 }
        $profileVolume = [pscustomobject]@{ VolumeRoot = 'C:\'; VolumeDevice = '\Device\HarddiskVolume3'; TotalBytes = 32212254720 }
        Test-AvdSameVolume -First $profileVolume -Second $os | Should -BeFalse
    }

    It 'reports the same volume when device and capacity both match' {
        $a = [pscustomobject]@{ VolumeRoot = 'C:\'; VolumeDevice = '\device\harddiskvolume3'; TotalBytes = 100 }
        $b = [pscustomobject]@{ VolumeRoot = 'C:\'; VolumeDevice = '\Device\HarddiskVolume3'; TotalBytes = 100 }
        Test-AvdSameVolume -First $a -Second $b | Should -BeTrue
    }

    It 'falls back to the path root when no device is known' {
        $a = [pscustomobject]@{ VolumeRoot = 'F:\'; VolumeDevice = $null; TotalBytes = 0 }
        $b = [pscustomobject]@{ VolumeRoot = 'C:\'; VolumeDevice = $null; TotalBytes = 0 }
        Test-AvdSameVolume -First $a -Second $b | Should -BeFalse
    }
}

Describe 'Cloud Cache detection' {
    It 'counts providers by type from REG_MULTI_SZ without keeping paths' {
        $value = @('type=smb,name="Primary",connectionString=\\files1.example.test\profiles', 'type=azure,name="Blob",connectionString="|fslogix/key1|"')
        $summary = Get-AvdCloudCacheProviderSummary -CcdLocations $value
        $summary.Configured | Should -BeTrue
        $summary.Smb | Should -Be 1
        $summary.Azure | Should -Be 1
        ($summary | ConvertTo-Json) | Should -Not -BeLike '*example.test*'
    }

    It 'counts providers in a single REG_SZ value' {
        (Get-AvdCloudCacheProviderSummary -CcdLocations 'type=smb,connectionString=\\a\p;type=smb,connectionString=\\b\p').Smb | Should -Be 2
    }

    It 'reports not configured for a null value' {
        (Get-AvdCloudCacheProviderSummary -CcdLocations $null).Configured | Should -BeFalse
    }

    It 'explains that a Cloud Cache profile measures the local cache, not the share' {
        $cc = Get-AvdCloudCacheProviderSummary -CcdLocations 'type=smb,connectionString=\\a\p'
        $notes = @(Get-AvdProfileStorageNote -FslogixEnabled 1 -ProfileOnOsVolume $false -CloudCache $cc -CacheDirectory 'C:\ProgramData\FSLogix\Cache' -CacheOnOsVolume $true)
        $notes[0] | Should -BeLike "Cloud Cache: *local cache in 'C:\ProgramData\FSLogix\Cache' (on the OS disk)*1 provider(s)*"
        $notes[1] | Should -BeLike '*sign-out waits*'
        @($notes | Where-Object { $_ -like '*No FSLogix container*' }).Count | Should -Be 0
    }

    It 'warns only when the profile really is on the OS volume' {
        $none = Get-AvdCloudCacheProviderSummary -CcdLocations $null
        $notes = @(Get-AvdProfileStorageNote -FslogixEnabled 1 -ProfileOnOsVolume $true -CloudCache $none)
        $notes.Count | Should -Be 1
        $notes[0] | Should -BeLike '*No FSLogix container is attached*'
    }

    It 'notes VHD growth for a classic VHDLocations container' {
        $none = Get-AvdCloudCacheProviderSummary -CcdLocations $null
        @(Get-AvdProfileStorageNote -FslogixEnabled 1 -ProfileOnOsVolume $false -CloudCache $none)[0] | Should -BeLike '*grows the dynamic profile VHD(X)*'
    }
}

Describe 'Resolve-AvdProfileAttachment (FSLogix filter-driver redirection)' {
    It 'uses the FSLogix session Volume even though the path probe says OS volume (regression)' {
        $r = Resolve-AvdProfileAttachment -SessionFound $true -SessionVolume '\\?\Volume{11111111-1111-1111-1111-111111111111}\' -ProbeOnOsVolume $true
        $r.Attached | Should -BeTrue
        $r.Source | Should -Be 'FSLogixSession'
        $r.VolumeGuidPath | Should -Be '\\?\Volume{11111111-1111-1111-1111-111111111111}\'
    }

    It 'treats a session key without a usable Volume as attached, volume unknown' {
        $r = Resolve-AvdProfileAttachment -SessionFound $true -SessionVolume 'not-a-volume' -ProbeOnOsVolume $true
        $r.Attached | Should -BeTrue
        $r.Source | Should -Be 'FSLogixSessionNoVolume'
        $r.VolumeGuidPath | Should -BeNullOrEmpty
    }

    It 'falls back to the volume probe without a session key' {
        (Resolve-AvdProfileAttachment -SessionFound $false -SessionVolume $null -ProbeOnOsVolume $false).Source | Should -Be 'VolumeProbe'
    }

    It 'reports not attached when there is no session key and the probe says OS volume' {
        $r = Resolve-AvdProfileAttachment -SessionFound $false -SessionVolume '' -ProbeOnOsVolume $true
        $r.Attached | Should -BeFalse
        $r.Source | Should -Be 'None'
    }
}
