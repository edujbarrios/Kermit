#requires -Version 5.1
<#
.SYNOPSIS
  Kermit AI Doctor - local, read-only AI development environment diagnostics.
.EXAMPLE
  .\AI-Doctor.ps1
.EXAMPLE
  .\AI-Doctor.ps1 -Json -OutputPath .\ai-doctor-report.json
.EXAMPLE
  .\AI-Doctor.ps1 -DeepCheck
#>
[CmdletBinding()]
param(
    [switch]$DeepCheck,
    [switch]$Json,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Kermit AI Doctor currently supports Windows only.'
}

Import-Module (Join-Path $PSScriptRoot 'src/Kermit.AIDoctor.psm1') -Force -ErrorAction Stop
$result = Get-KermitAIReport -DeepCheck:$DeepCheck
$serialized = $result | ConvertTo-Json -Depth 12

if ($OutputPath) {
    $serialized | Set-Content -LiteralPath $OutputPath -Encoding UTF8 -ErrorAction Stop
}
if ($Json) {
    Write-Output $serialized
    return
}

Write-Host ''
Write-Host ' KERMIT AI DOCTOR | local, read-only diagnostic' -ForegroundColor Green
Write-Host ''
Write-Host (' Windows: {0}' -f $result.Report.Windows)
Write-Host (' Python: {0} ({1})' -f $result.Report.Python.Version, $result.Report.Python.ProbeStatus)
Write-Host (' PyTorch: {0} | Transformers: {1}' -f $result.Report.Python.Packages.torch, $result.Report.Python.Packages.transformers)
Write-Host (' NVIDIA GPUs detected: {0}' -f @($result.Report.NvidiaGPUs).Count)
Write-Host (' CUDA compiler (nvcc) release: {0}' -f $result.Report.CudaToolkit.Release)
Write-Host (' WSL command found: {0} | Docker command found: {1}' -f $result.Report.WSL.CommandFound, $result.Report.Docker.CommandFound)
Write-Host (' PyTorch runtime probe: {0}' -f $result.Report.DeepCheck.Status)
Write-Host ''
foreach ($finding in $result.Findings) {
    Write-Host (' [{0}] {1}: {2}' -f $finding.Level, $finding.Area, $finding.Message)
}
if ($OutputPath) { Write-Host (' Report saved to: {0}' -f $OutputPath) }
