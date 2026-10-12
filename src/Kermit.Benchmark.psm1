Set-StrictMode -Version Latest

# Instantaneous OS resource snapshots, not a synthetic CPU/GPU performance test.
function ConvertTo-KermitNumber {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    $n = [double]0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$n) -and
        -not [double]::IsNaN($n) -and -not [double]::IsInfinity($n) -and $n -ge 0) {
        return $n
    }
    return $null
}

function Get-KermitBenchmark {
    [CmdletBinding()]
    param([ValidateSet('Before','After')][string]$Label = 'Before')

    Import-Module (Join-Path $PSScriptRoot 'Kermit.Core.psm1') -ErrorAction Stop
    $inv = Get-KermitInventory
    $total = $null
    $free = $null
    $used = $null
    if ($null -ne $inv.RAMTotalGiB) { $total = [math]::Round([double]$inv.RAMTotalGiB * 1024,1) }
    if ($null -ne $inv.RAMFreeGiB) { $free = [math]::Round([double]$inv.RAMFreeGiB * 1024,1) }
    if ($null -ne $total -and $null -ne $free -and $total -gt 0) {
        $used = [math]::Max(0,[math]::Round($total - $free,1))
    }
    $processCount = $null
    try { $processCount = @(Get-Process -ErrorAction Stop).Count } catch {}
    $cpuPercent = $null
    try {
        $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
        if ($null -ne $cpu) {
            $cpuPercent = ConvertTo-KermitNumber $cpu.PercentProcessorTime
            if ($null -ne $cpuPercent -and $cpuPercent -gt 100) { $cpuPercent = $null }
        }
    } catch {}
    $gpuMetrics = @()
    foreach ($gpu in @($inv.NvidiaGPUs)) {
        $gpuMetrics += [pscustomobject]@{
            Name = [string]$gpu.Name
            VRAMUsedMiB = ConvertTo-KermitNumber $gpu.MemoryUsedMiB
            VRAMTotalMiB = ConvertTo-KermitNumber $gpu.MemoryTotalMiB
            GPUUtilizationPercent = ConvertTo-KermitNumber $gpu.UtilizationPercent
        }
    }
    $diskFree = $null
    if ($null -ne $inv.SystemDisk -and $null -ne $inv.SystemDisk.FreeGiB) {
        $diskFree = [math]::Round([double]$inv.SystemDisk.FreeGiB * 1024,1)
    }
    return [pscustomobject]@{
        Schema = 'kermit.benchmark.v1'
        Label = $Label
        CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
        Host = [pscustomobject]@{
            ComputerName = [string]$inv.ComputerName
            CPU = $inv.CPU
            WindowsBuild = $inv.WindowsBuild
        }
        Metrics = [pscustomobject]@{
            RAMUsedMiB = $used
            RAMFreeMiB = $free
            ProcessCount = $processCount
            StartupEntryCount = @($inv.StartupItems).Count
            SystemDiskFreeMiB = $diskFree
            CPUUtilizationPercent = $cpuPercent
            NvidiaGPUs = @($gpuMetrics)
        }
        Note = 'Instantaneous resource snapshot only; not a training or inference benchmark.'
    }
}

function Assert-KermitBenchmark {
    param([Parameter(Mandatory)][object]$Snapshot)
    if ($Snapshot.Schema -cne 'kermit.benchmark.v1' -or $Snapshot.Label -notin @('Before','After') -or
        $null -eq $Snapshot.Host -or $null -eq $Snapshot.Metrics -or
        [string]::IsNullOrWhiteSpace([string]$Snapshot.Host.ComputerName)) {
        throw 'Invalid or unsupported Kermit benchmark snapshot.'
    }
    foreach ($field in @('RAMUsedMiB','RAMFreeMiB','ProcessCount','StartupEntryCount',
                         'SystemDiskFreeMiB','CPUUtilizationPercent')) {
        $value = $Snapshot.Metrics.$field
        if ($null -ne $value -and $null -eq (ConvertTo-KermitNumber $value)) {
            throw "Invalid benchmark metric: $field."
        }
    }
}

function Save-KermitBenchmark {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [string]$Directory = (Join-Path $env:LOCALAPPDATA 'Kermit\Benchmarks')
    )
    Assert-KermitBenchmark $Snapshot
    $null = New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop
    $path = Join-Path $Directory ('{0}-{1}-{2}.json' -f $Snapshot.Label.ToLowerInvariant(),
        (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
    $stream = New-Object System.IO.FileStream($path, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Snapshot | ConvertTo-Json -Depth 10))
        $stream.Write($bytes,0,$bytes.Length)
    }
    finally { $stream.Dispose() }
    return $path
}

function Read-KermitBenchmark {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $f = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($f.PSIsContainer -or $f.Length -gt 1048576) { throw 'Invalid or oversized benchmark report.' }
    $snapshot = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-KermitBenchmark $snapshot
    return $snapshot
}

function Get-KermitBenchmarkDelta {
    param([object]$Before,[object]$After,[string]$Name,[string]$Unit)
    $a = ConvertTo-KermitNumber $Before
    $b = ConvertTo-KermitNumber $After
    $delta = $null
    if ($null -ne $a -and $null -ne $b) { $delta = [math]::Round($b - $a,2) }
    return [pscustomobject]@{ Metric = $Name; Unit = $Unit; Before = $a; After = $b; Delta = $delta }
}

function Compare-KermitBenchmarks {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Before,[Parameter(Mandatory)][object]$After)

    Assert-KermitBenchmark $Before
    Assert-KermitBenchmark $After
    if ($Before.Label -cne 'Before' -or $After.Label -cne 'After') {
        throw 'Comparison requires a Before report and an After report in that order.'
    }
    if ($Before.Host.ComputerName -cne $After.Host.ComputerName -or
        $Before.Host.CPU -cne $After.Host.CPU -or
        $Before.Host.WindowsBuild -cne $After.Host.WindowsBuild) {
        throw 'Reports were captured on different computer hardware or Windows builds.'
    }
    $spec = @(
        @{Name='RAMUsedMiB';Unit='MiB'},
        @{Name='RAMFreeMiB';Unit='MiB'},
        @{Name='ProcessCount';Unit='processes'},
        @{Name='StartupEntryCount';Unit='entries'},
        @{Name='SystemDiskFreeMiB';Unit='MiB'},
        @{Name='CPUUtilizationPercent';Unit='percentage points'}
    )
    $metrics = @()
    foreach ($field in $spec) {
        $name = $field.Name
        $metrics += Get-KermitBenchmarkDelta -Before $Before.Metrics.$name -After $After.Metrics.$name -Name $name -Unit $field.Unit
    }
    $gpuDeltas = @()
    $gpusBefore = @($Before.Metrics.NvidiaGPUs)
    $gpusAfter = @($After.Metrics.NvidiaGPUs)
    if ($gpusBefore.Count -gt 0 -and $gpusBefore.Count -eq $gpusAfter.Count) {
        $matched = $true
        for ($i=0;$i -lt $gpusBefore.Count;$i++) {
            if ($gpusBefore[$i].Name -cne $gpusAfter[$i].Name) { $matched=$false }
        }
        if ($matched) {
            for ($i=0;$i -lt $gpusBefore.Count;$i++) {
                $gpuDeltas += [pscustomobject]@{
                    GPU = [string]$gpusBefore[$i].Name
                    Index = $i
                    VRAMUsed = Get-KermitBenchmarkDelta -Before $gpusBefore[$i].VRAMUsedMiB -After $gpusAfter[$i].VRAMUsedMiB -Name 'VRAMUsedMiB' -Unit 'MiB'
                    GPUUtilization = Get-KermitBenchmarkDelta -Before $gpusBefore[$i].GPUUtilizationPercent -After $gpusAfter[$i].GPUUtilizationPercent -Name 'GPUUtilizationPercent' -Unit 'percentage points'
                }
            }
        }
    }
    return [pscustomobject]@{
        Schema = 'kermit.benchmark-comparison.v1'
        Host = $Before.Host.ComputerName
        BeforeCapturedAt = $Before.CapturedAt
        AfterCapturedAt = $After.CapturedAt
        Metrics = @($metrics)
        NvidiaGPUs = @($gpuDeltas)
        Interpretation = 'Changes are After minus Before. Resource readings fluctuate and do not prove increased training throughput or inference speed.'
    }
}
Export-ModuleMember -Function Get-KermitBenchmark, Save-KermitBenchmark, Read-KermitBenchmark, Compare-KermitBenchmarks
