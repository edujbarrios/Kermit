#requires -Version 5.1
<#
.SYNOPSIS
  Kermit Benchmark: measure resource snapshots and compare Before/After.
.EXAMPLE
  .\Benchmark.ps1 -Action Capture -Label Before
.EXAMPLE
  .\Benchmark.ps1 -Action Capture -Label After -Json
.EXAMPLE
  .\Benchmark.ps1 -Action Compare -BeforePath "before.json" -AfterPath "after.json"
#>
[CmdletBinding()]
param(
    [ValidateSet('Capture','Compare')][string]$Action = 'Capture',
    [ValidateSet('Before','After')][string]$Label = 'Before',
    [string]$BeforePath,
    [string]$AfterPath,
    [string]$Directory,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Kermit Benchmark supports Windows 10/11 only.'
}
Import-Module (Join-Path $PSScriptRoot 'src/Kermit.Benchmark.psm1') -Force -ErrorAction Stop

if ($Action -eq 'Capture') {
    $snapshot = Get-KermitBenchmark -Label $Label
    $args = @{ Snapshot = $snapshot }
    if (-not [string]::IsNullOrWhiteSpace($Directory)) { $args.Directory = $Directory }
    $path = Save-KermitBenchmark @args
    $result = [pscustomobject]@{ Action='Capture'; Path=$path; Snapshot=$snapshot }
}
else {
    if ([string]::IsNullOrWhiteSpace($BeforePath) -or [string]::IsNullOrWhiteSpace($AfterPath)) {
        throw 'Compare requires -BeforePath and -AfterPath pointing to saved Kermit snapshots.'
    }
    $before = Read-KermitBenchmark -Path $BeforePath
    $after = Read-KermitBenchmark -Path $AfterPath
    $result = [pscustomobject]@{
        Action='Compare'
        Result=(Compare-KermitBenchmarks -Before $before -After $after)
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
    return
}
Write-Host ''
Write-Host ' KERMIT BENCHMARK | resource snapshots' -ForegroundColor Green
if ($Action -eq 'Capture') {
    Write-Host (' Captured: {0}' -f $Label)
    Write-Host (' Saved: {0}' -f $result.Path)
    Write-Host (' RAM used: {0} MiB | Processes: {1}' -f $snapshot.Metrics.RAMUsedMiB, $snapshot.Metrics.ProcessCount)
}
else {
    $result.Result.Metrics | Format-Table Metric, Before, After, Delta, Unit -AutoSize | Out-Host
}
Write-Host ' These are instantaneous measurements, not an AI model-speed benchmark.'
