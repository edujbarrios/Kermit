# Kermit Benchmark tests: snapshots use synthetic data and an isolated temp directory.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Kermit.Benchmark.psm1') -Force

function Assert {
    param([bool]$Valid,[string]$Reason)
    if (-not $Valid) { throw "Benchmark test failed: $Reason" }
}
function Assert-Throws {
    param([scriptblock]$Call,[string]$Reason)
    $failed = $false
    try { & $Call | Out-Null } catch { $failed = $true }
    Assert $failed $Reason
}
function New-TestSnapshot {
    param([string]$Label,[string]$Computer='kermit-fixture')
    return [pscustomobject]@{
        Schema = 'kermit.benchmark.v1'
        Label = $Label
        CapturedAt = '2026-10-12T00:00:00Z'
        Host = [pscustomobject]@{
            ComputerName = $Computer
            CPU = 'Synthetic CPU'
            WindowsBuild = '26100'
        }
        Metrics = [pscustomobject]@{
            RAMUsedMiB = 4000
            RAMFreeMiB = 8000
            ProcessCount = 112
            StartupEntryCount = 8
            SystemDiskFreeMiB = 100000
            CPUUtilizationPercent = 12
            NvidiaGPUs = @([pscustomobject]@{
                Name='Mock GPU'
                VRAMUsedMiB=800
                VRAMTotalMiB=16000
                GPUUtilizationPercent=4
            })
        }
    }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('kermit-benchmark-' + [guid]::NewGuid().ToString('N'))
try {
    $before = New-TestSnapshot Before
    $after = New-TestSnapshot After
    $after.Metrics.RAMUsedMiB = 3500
    $after.Metrics.RAMFreeMiB = 8500
    $after.Metrics.ProcessCount = 100
    $after.Metrics.StartupEntryCount = 5
    $after.Metrics.SystemDiskFreeMiB = 101000
    $after.Metrics.NvidiaGPUs[0].VRAMUsedMiB = 600

    $bp = Save-KermitBenchmark -Snapshot $before -Directory $root
    $ap = Save-KermitBenchmark -Snapshot $after -Directory $root
    Assert (Test-Path -LiteralPath $bp) 'Before report should be saved'
    Assert (Test-Path -LiteralPath $ap) 'After report should be saved'
    $loadedBefore = Read-KermitBenchmark -Path $bp
    $loadedAfter = Read-KermitBenchmark -Path $ap
    $comparison = Compare-KermitBenchmarks -Before $loadedBefore -After $loadedAfter
    Assert ($comparison.Schema -eq 'kermit.benchmark-comparison.v1') 'Comparison schema wrong'
    Assert (@($comparison.Metrics | Where-Object { $_.Metric -eq 'RAMUsedMiB' -and $_.Delta -eq -500 }).Count -eq 1) 'RAM delta wrong'
    Assert (@($comparison.Metrics | Where-Object { $_.Metric -eq 'ProcessCount' -and $_.Delta -eq -12 }).Count -eq 1) 'Process delta wrong'
    Assert ($comparison.NvidiaGPUs[0].VRAMUsed.Delta -eq -200) 'GPU memory delta wrong'

    $after.Host.ComputerName = 'other-host'
    Assert-Throws { Compare-KermitBenchmarks -Before $before -After $after } 'Different host must be rejected'
    $after.Host.ComputerName = $before.Host.ComputerName
    $after.Host.CPU = 'Other CPU'
    Assert-Throws { Compare-KermitBenchmarks -Before $before -After $after } 'Different CPU must be rejected'
    $after.Host.CPU = $before.Host.CPU
    $after.Metrics.RAMUsedMiB = -4
    Assert-Throws { Compare-KermitBenchmarks -Before $before -After $after } 'Negative metrics must be rejected'
    $after.Metrics.RAMUsedMiB = 3500
    $after.Label = 'Before'
    Assert-Throws { Compare-KermitBenchmarks -Before $before -After $after } 'Wrong snapshot label must be rejected'
    $after.Label = 'After'

    $after.Metrics.NvidiaGPUs[0].Name = 'Different GPU'
    $result = Compare-KermitBenchmarks -Before $before -After $after
    Assert (@($result.NvidiaGPUs).Count -eq 0) 'Different GPU must not be compared'

    $bad = Join-Path $root 'bad.json'
    [IO.File]::WriteAllText($bad,'{"Schema":"unknown"}')
    Assert-Throws { Read-KermitBenchmark -Path $bad } 'Unknown schema must be rejected'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
Write-Host 'Kermit benchmark tests passed.' -ForegroundColor Green
