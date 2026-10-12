# AI Doctor tests - read-only, no external installers, no real PyTorch import.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Kermit.AIDoctor.psm1') -Force

function Assert {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
}

$python = [pscustomobject]@{
    Found = $true
    ProbeStatus = 'ok'
    Packages = [pscustomobject]@{ torch = '2.0.0'; transformers = $null }
}
$base = [pscustomobject]@{
    Python = $python
    NvidiaGPUs = @([pscustomobject]@{Name='Mock GPU'})
    DeepCheck = [pscustomobject]@{Requested=$false;Status='not-run';CudaAvailable=$null}
    WSL = [pscustomobject]@{CommandFound=$true}
    CudaToolkit = [pscustomobject]@{NvccFound=$false}
}

$advice = @(Get-KermitAIFindings -Report $base)
Assert (@($advice | Where-Object Area -eq 'CUDA').Count -eq 1) 'GPU detected should recommend optional CUDA runtime check'
Assert (@($advice | Where-Object Area -eq 'Safety').Count -eq 1) 'Safety notice is required'
Assert (@($advice | Where-Object Area -eq 'WSL').Count -eq 1) 'WSL presence must not imply WSL2 is configured'

$base.DeepCheck = [pscustomobject]@{ Requested = $true; Status = 'ok'; CudaAvailable = $false }
$advice = @(Get-KermitAIFindings -Report $base)
Assert (@($advice | Where-Object { $_.Area -eq 'CUDA' -and $_.Level -eq 'warning' }).Count -eq 1) 'Unavailable CUDA should warn'

$base.Python = [pscustomobject]@{
    Found = $false
    ProbeStatus = 'not-found'
    Packages = [pscustomobject]@{torch=$null}
}
$advice = @(Get-KermitAIFindings -Report $base)
Assert (@($advice | Where-Object Area -eq 'Python').Count -eq 1) 'Missing Python should be actionable'

$exe = Get-Command powershell.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
$probe = Invoke-KermitProbe -Executable $exe.Source -Arguments '-NoProfile -Command "Write-Output kermit-probe"' -TimeoutSeconds 10
Assert ($probe.Status -eq 'ok') 'Bounded process probe should succeed'
Assert ($probe.Output -eq 'kermit-probe') 'Probe must capture stdout'
$failure = Invoke-KermitProbe -Executable (Join-Path $env:SystemRoot 'kermit-nonexistent.exe') -Arguments '--version' -TimeoutSeconds 3
Assert ($failure.Status -eq 'error') 'Nonexistent probe should be reported as error'

Write-Host 'Kermit AI Doctor smoke tests passed.' -ForegroundColor Green
