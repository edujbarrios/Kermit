Set-StrictMode -Version Latest

# Run bounded, read-only external probes without shell expansion or PowerShell Invoke-Expression.
# stdout and stderr are drained concurrently to avoid pipe-buffer deadlocks.
function Invoke-KermitProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$Arguments,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 10
    )

    $p = New-Object System.Diagnostics.Process
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $p.StartInfo = $info

    try {
        if (-not $p.Start()) {
            return [pscustomobject]@{ Status = 'error'; ExitCode = $null; Output = ''; Error = 'Process did not start.' }
        }
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch {}
            return [pscustomobject]@{ Status = 'timeout'; ExitCode = $null; Output = ''; Error = 'Probe exceeded its time limit.' }
        }
        [void]$outTask.Wait(3000)
        [void]$errTask.Wait(3000)
        $stdout = if ($outTask.IsCompleted) { $outTask.Result.Trim() } else { '' }
        $stderr = if ($errTask.IsCompleted) { $errTask.Result.Trim() } else { '' }
        if ($stdout.Length -gt 8192) { $stdout = $stdout.Substring(0,8192) }
        if ($stderr.Length -gt 500) { $stderr = $stderr.Substring(0,500) }
        $status = if ($p.ExitCode -eq 0) { 'ok' } else { 'error' }
        return [pscustomobject]@{ Status = $status; ExitCode = $p.ExitCode; Output = $stdout; Error = $stderr }
    }
    catch {
        return [pscustomobject]@{ Status = 'error'; ExitCode = $null; Output = ''; Error = $_.Exception.Message }
    }
    finally {
        $p.Dispose()
    }
}

function Get-KermitAIFindings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Report)

    $messages = [System.Collections.Generic.List[object]]::new()
    if (-not $Report.Python.Found) {
        $messages.Add([pscustomobject]@{
            Level = 'action'; Area = 'Python'
            Message = 'A usable Python executable was not detected. Install Python from an official source and create a virtual environment.'
        })
    }
    elseif ($Report.Python.ProbeStatus -ne 'ok') {
        $messages.Add([pscustomobject]@{
            Level = 'warning'; Area = 'Python'
            Message = 'Python was detected but the version/package check failed or timed out. Verify this installation manually.'
        })
    }
    elseif (-not $Report.Python.Packages.torch) {
        $messages.Add([pscustomobject]@{
            Level = 'action'; Area = 'PyTorch'
            Message = 'PyTorch was not found in the checked Python environment. This does not rule out another virtual environment or WSL.'
        })
    }

    if (@($Report.NvidiaGPUs).Count -gt 0) {
        if ($Report.DeepCheck.Requested -and $Report.DeepCheck.Status -eq 'ok' -and
            $Report.DeepCheck.CudaAvailable -eq $false) {
            $messages.Add([pscustomobject]@{
                Level = 'warning'; Area = 'CUDA'
                Message = 'This Python/PyTorch environment did not report CUDA availability. Check its build, driver, environment, and GPU compatibility.'
            })
        }
        elseif (-not $Report.DeepCheck.Requested) {
            $messages.Add([pscustomobject]@{
                Level = 'info'; Area = 'CUDA'
                Message = 'NVIDIA GPU detection alone does not prove that PyTorch can use CUDA. Use -DeepCheck to test torch.cuda.is_available().'
            })
        }
    }
    else {
        $messages.Add([pscustomobject]@{
            Level = 'info'; Area = 'GPU'
            Message = 'No NVIDIA GPU was confirmed by nvidia-smi. Other vendors and CPU-only AI workflows may still be supported.'
        })
    }

    if (-not $Report.WSL.CommandFound) {
        $messages.Add([pscustomobject]@{
            Level = 'info'; Area = 'WSL'
            Message = 'WSL executable was not detected. Many Linux-first AI tools work best inside a configured WSL2 environment.'
        })
    }
    else {
        $messages.Add([pscustomobject]@{
            Level = 'info'; Area = 'WSL'
            Message = 'WSL executable exists; installed distributions and WSL2 configuration were not verified.'
        })
    }

    if ($Report.CudaToolkit.NvccFound -eq $false) {
        $messages.Add([pscustomobject]@{
            Level = 'info'; Area = 'CUDA toolkit'
            Message = 'nvcc is not on PATH. A separate CUDA Toolkit is not always required for prebuilt PyTorch wheels.'
        })
    }
    $messages.Add([pscustomobject]@{
        Level = 'info'; Area = 'Safety'
        Message = 'AI Doctor is diagnostic only; it never installs, updates, or removes software.'
    })
    return @($messages.ToArray())
}

function Get-KermitAIReport {
    [CmdletBinding()]
    param([switch]$DeepCheck)

    $coreModule = Join-Path $PSScriptRoot 'Kermit.Core.psm1'
    Import-Module $coreModule -ErrorAction Stop

    $inventory = Get-KermitInventory
    $packages = [ordered]@{
        torch = $null
        transformers = $null
        accelerate = $null
        peft = $null
        diffusers = $null
    }

    $pythonPath = $null
    $pythonVersion = $null
    $pythonStatus = 'not-found'
    $pythonError = $null
    $command = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $command) {
        $candidate = [string]$command.Source
        # Windows Store app-execution aliases can open the Store rather than Python.
        if ($candidate -match '\\Microsoft\\WindowsApps\\') {
            $pythonStatus = 'store-alias'
            $pythonError = 'A Windows Store Python execution alias was found, not a verified interpreter.'
        }
        else {
            $pythonPath = $candidate
            # Python metadata check: no imports of torch, no network, and isolated mode
            # to avoid loading local scripts and user-site customizations.
            $pyCode = "import sys,json,importlib.metadata as m; d={str(x.metadata.get('Name','')).lower().replace('_','-'):x.version for x in m.distributions()}; print(json.dumps({'python':sys.version.split()[0],'packages':{n:d.get(n) for n in ['torch','transformers','accelerate','peft','diffusers']}}))"
            $probe = Invoke-KermitProbe -Executable $pythonPath -Arguments ('-I -c "' + $pyCode + '"') -TimeoutSeconds 15
            $pythonStatus = $probe.Status
            $pythonError = $probe.Error
            if ($probe.Status -eq 'ok') {
                try {
                    $parsed = $probe.Output | ConvertFrom-Json -ErrorAction Stop
                    $pythonVersion = [string]$parsed.python
                    foreach ($key in @($packages.Keys)) {
                        if ($null -ne $parsed.packages.$key) {
                            $packages[$key] = [string]$parsed.packages.$key
                        }
                    }
                }
                catch {
                    $pythonStatus = 'error'
                    $pythonError = 'Could not parse Python metadata response.'
                }
            }
        }
    }

    $toolkit = [ordered]@{ NvccFound = $false; Release = $null; ProbeStatus = 'not-found' }
    $nvcc = Get-Command nvcc.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $nvcc) {
        $toolkit.NvccFound = $true
        $cudaProbe = Invoke-KermitProbe -Executable ([string]$nvcc.Source) -Arguments '--version' -TimeoutSeconds 8
        $toolkit.ProbeStatus = $cudaProbe.Status
        if ($cudaProbe.Status -eq 'ok' -and $cudaProbe.Output -match 'release\s+([0-9]+(?:\.[0-9]+)?)') {
            $toolkit.Release = $Matches[1]
        }
    }

    $runtime = [ordered]@{
        Requested = [bool]$DeepCheck
        Status = 'not-run'
        TorchVersion = $null
        TorchCudaBuild = $null
        CudaAvailable = $null
        DeviceCount = $null
        Note = 'Deep check imports PyTorch and may initialize a CUDA context; it is optional.'
    }

    if ($DeepCheck) {
        if ([string]::IsNullOrWhiteSpace($pythonPath) -or $pythonStatus -ne 'ok' -or -not $packages.torch) {
            $runtime.Status = 'not-applicable'
            $runtime.Note = 'No verified Python interpreter with PyTorch found.'
        }
        else {
            $testCode = "import torch,json; a=bool(torch.cuda.is_available()); print(json.dumps({'torch':torch.__version__,'cuda_build':torch.version.cuda,'available':a,'count':torch.cuda.device_count() if a else 0}))"
            $deep = Invoke-KermitProbe -Executable $pythonPath -Arguments ('-I -c "' + $testCode + '"') -TimeoutSeconds 30
            $runtime.Status = $deep.Status
            if ($deep.Status -eq 'ok') {
                try {
                    $tested = $deep.Output | ConvertFrom-Json -ErrorAction Stop
                    $runtime.TorchVersion = [string]$tested.torch
                    if ($null -ne $tested.cuda_build) { $runtime.TorchCudaBuild = [string]$tested.cuda_build }
                    $runtime.CudaAvailable = [bool]$tested.available
                    $runtime.DeviceCount = [int]$tested.count
                }
                catch {
                    $runtime.Status = 'error'
                    $runtime.Note = 'Could not parse PyTorch runtime output.'
                }
            }
            else {
                $runtime.Note = 'PyTorch runtime probe failed or timed out. Check the Python environment manually.'
            }
        }
    }

    $report = [pscustomobject]@{
        SchemaVersion = 1
        CollectedAt = (Get-Date).ToUniversalTime().ToString('o')
        ReadOnly = $true
        Windows = $inventory.Windows
        Python = [pscustomobject]@{
            Found = -not [string]::IsNullOrWhiteSpace($pythonPath)
            Path = $pythonPath
            Version = $pythonVersion
            ProbeStatus = $pythonStatus
            ProbeError = $pythonError
            Packages = [pscustomobject]$packages
        }
        NvidiaGPUs = @($inventory.NvidiaGPUs)
        CudaToolkit = [pscustomobject]$toolkit
        WSL = [pscustomobject]@{
            CommandFound = [bool]$inventory.Tooling.wsl
            VerifiedWSL2 = $false
        }
        Docker = [pscustomobject]@{ CommandFound = [bool]$inventory.Tooling.docker }
        DeepCheck = [pscustomobject]$runtime
    }
    return [pscustomobject]@{
        Report = $report
        Findings = @(Get-KermitAIFindings -Report $report)
    }
}

Export-ModuleMember -Function Invoke-KermitProbe, Get-KermitAIReport, Get-KermitAIFindings
