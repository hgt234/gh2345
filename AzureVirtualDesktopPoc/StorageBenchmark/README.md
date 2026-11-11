# AVD storage benchmark (Visual Studio developer workload)

`Invoke-AvdStorageBenchmark.ps1` runs Microsoft DiskSpd on an AVD session host
against the OS disk, the FSLogix profile container and an optional data disk,
using a modeled Visual Studio (devenv) workload. Performance counters are
recorded for the whole run and averaged per scenario, so DiskSpd and OS numbers
line up.

Run it **in the target user's session** (not as SYSTEM) so `%USERPROFILE%` is the
mounted profile container. Windows PowerShell 5.1, no elevation required.

## Why the profile container matters for Visual Studio

With default settings most Visual Studio IO lands inside the FSLogix container:

| Data | Default location |
|---|---|
| Solutions / repos | `%USERPROFILE%\source\repos` |
| NuGet global-packages (reference assemblies, extracted packages) | `%USERPROFILE%\.nuget\packages` |
| NuGet http-cache | `%LOCALAPPDATA%\NuGet\v3-cache` |
| Visual Studio component and MEF caches | `%LOCALAPPDATA%\Microsoft\VisualStudio` |
| Visual Studio installation | `C:\Program Files\...` (OS disk) |

## Quick start

```powershell
# Plan only: checks targets, free space, FSLogix state; prints every DiskSpd command line.
.\Invoke-AvdStorageBenchmark.ps1 -DownloadDiskSpd -WhatIf

# Quick validation (about 1 minute): 1 s warm-up + 4 s per scenario, 64 MiB test files.
# Smoke test and ballpark latency only; use the full run for sizing decisions.
.\Invoke-AvdStorageBenchmark.ps1 -DownloadDiskSpd -Quick

# Full run (about 15 minutes for two targets with defaults)
.\Invoke-AvdStorageBenchmark.ps1 -DownloadDiskSpd

# Include a data disk (for example if repos or NUGET_PACKAGES are redirected there)
.\Invoke-AvdStorageBenchmark.ps1 -DataDiskPath 'F:\AvdStorageBenchmark'

# Find the profile container's ceiling for build and restore
.\Invoke-AvdStorageBenchmark.ps1 -Target Profile -Scenario Build, NuGetRestore -Saturate
```

`-DownloadDiskSpd` fetches DiskSpd v2.3 from the Microsoft GitHub release,
checks the pinned SHA-256 and the Microsoft Authenticode signature, and keeps it
in `%ProgramData%\AvdStorageBenchmark\tools` for later runs.

## Workload model

| Scenario | Stream | Block | Pattern | Write | Threads x QD |
|---|---|---|---|---|---|
| SolutionLoad | ProjectSourceRead | 4 KiB | random, 90% of IO in 10% of file | 0% | 4 x 1 |
| | AssemblyRead | 64 KiB | random, 80% in 20% | 0% | 2 x 1 |
| | IntelliSenseDbLoad | 4 KiB | random, write-through | 20% | 1 x 1 |
| Editing | SourceRead | 4 KiB | random, hot set | 0% | 2 x 1, 50 IOPS/thread |
| | IntelliSenseDbWrite | 4 KiB | random, write-through | 50% | 1 x 1, 20 IOPS |
| | AutoRecoverWrite | 4 KiB | sequential, write-through | 100% | 1 x 1, 5 IOPS |
| Build | CompileSourceRead | 4 KiB | random | 0% | CPUs x 1 |
| | ReferenceRead | 64 KiB | random, 80% in 20% | 0% | 2 x 1 |
| | ObjBinWrite | 64 KiB | sequential | 100% | CPUs x 1 |
| | BuildStateWrite | 4 KiB | random | 70% | 1 x 1 |
| NuGetRestore | PackageDownload | 64 KiB | sequential | 100% | 2 x 1 |
| | PackageExtract | 4 KiB | random | 80% | 4 x 1 |
| Debugging | SymbolRead | 4 KiB | random, 80% in 20% | 0% | 2 x 1 |
| | BinaryLoad | 64 KiB | sequential | 0% | 1 x 1 |

Streams in a scenario run concurrently (one DiskSpd process each). "CPUs" is the
logical processor count, capped at 32 (`Threads = 0` in the workload JSON).

Where the numbers come from:

| Value | Source | Status |
|---|---|---|
| 4 KiB source, project and package file IO | NTFS default cluster size (Microsoft Learn) | documented |
| 4 KiB symbol reads | PDB files are MSF containers with 4096-byte blocks (LLVM "The MSF File Format") | documented |
| 4 KiB IntelliSense DB IO | C++ browse database (`Browse.VC.db`) is SQLite; SQLite default page size 4096 | documented |
| Build threads = CPUs | Visual Studio "Maximum number of parallel project builds" defaults to the CPU count, max 32 (Microsoft Learn) | documented |
| Package and cache locations | NuGet global-packages and http-cache folders (Microsoft Learn) | documented |
| 64 KiB assembly, output and download transfers | none | **modeled** |
| Write ratios, hot sets, Editing IOPS caps, non-build thread counts | none | **modeled** |

Calibrate with your own developers:

1. `-Mode Capture -CaptureSeconds 1800` while someone works normally in Visual
   Studio (open solution, restore, build, debug). `capture-summary.json`
   reports, per disk, read/write mix, IO-weighted average read and write size,
   and a suggested power-of-two block size.
2. `-Mode ExportWorkload`, edit `BlockSizeBytes` / `WritePercent` /
   `IopsLimitPerThread` / `Threads` in the JSON.
3. Re-run with `-WorkloadPath <file>.json`.

## Output

`%ProgramData%\AvdStorageBenchmark\results\<COMPUTER>_<timestamp>\`

- `results.csv`: one row per stream (IOPS, MiB/s, avg / p50 / p95 / p99 / p99.9 / max latency, CPU)
- `report.json`: settings, targets, workload, scenario totals, fill rates, per-scenario counter averages
- `counters.csv`, `counters-by-scenario.csv`: raw and windowed perfmon samples
- `diskspd_*.xml`: raw DiskSpd output

Results contain the computer name; do not commit them.

## Caveats

- DiskSpd generates data IO only. Metadata operations (file create, open,
  enumerate, timestamp checks), which are heavy during restore, build and
  incremental up-to-date checks, are not simulated. Neither is the CPU and
  memory load of a real build.
- `-CacheMode Unbuffered` (default) bypasses the Windows cache to measure the
  storage path. Real Visual Studio IO is cached, so users see better read
  latency for hot files.
- The test writes 2.5 GiB per target. Inside a dynamically expanding profile
  VHD(X) this grows the container; the files are deleted afterwards, but the
  VHD(X) on the share only shrinks on compaction.
- The Azure OS disk host cache (ReadWrite by default) can serve part of the OS disk reads.
- Counter names are English; on a localized OS missing counters are skipped and
  listed in `report.json` (`CountersMissing`).

## Validation

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./tests -Output Detailed
```
