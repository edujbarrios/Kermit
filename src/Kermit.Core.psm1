Set-StrictMode -Version Latest

$script:BalancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:HighPerformanceGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

function Test-KermitCommand {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Get-KermitPowerInfo {
    $active = $null
    $available = @()

    if (Test-KermitCommand 'powercfg.exe') {
        try {
            $activeText = (& powercfg.exe /getactivescheme 2>$null) -join ' '
            $pattern = '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}'
            $match = [regex]::Match($activeText, $pattern)
            if ($match.Success) { $active = $match.Value.ToLowerInvariant() }

            $lines = @(& powercfg.exe /list 2>$null)
            foreach ($line in $lines) {
                $scheme = [regex]::Match([string]$line, $pattern)
                if ($scheme.Success) {
                    $available += $scheme.Value.ToLowerInvariant()
                }
            }
        }
        catch {
            # An unavailable powercfg utility should not abort a read-only scan.
        }
    }

    return [pscustomobject]@{
        ActiveSchemeGuid = $active
        AvailableSchemes = @($available | Select-Object -Unique)
        BalancedGuid = $script:BalancedGuid
        HighPerformanceGuid = $script:HighPerformanceGuid
    }
}

function Get-KermitInventory {
    [CmdletBinding()]
    param()

    $os = $null
    $computer = $null
    $processor = $null
    $disk = $null
    $video = @()
    $startup = @()

    try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch {}
    try { $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } catch {}
    try { $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1 } catch {}
    try { $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop } catch {}
    try {
        $video = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Select-Object Name, DriverVersion)
    } catch {}
    try {
        $startup = @(Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction Stop |
            Select-Object Name, Location, User)
    } catch {}

    $toolNames = @('python.exe', 'git.exe', 'wsl.exe', 'docker.exe', 'winget.exe', 'nvidia-smi.exe')
    $tools = [ordered]@{}
    foreach ($name in $toolNames) {
        $tools[$name.Replace('.exe', '')] = Test-KermitCommand $name
    }

    $nvidia = @()
    if ($tools['nvidia-smi']) {
        try {
            $rows = @(& nvidia-smi.exe --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader,nounits 2>$null)
            if ($LASTEXITCODE -eq 0) {
                foreach ($row in $rows) {
                    $values = ([string]$row).Split(',')
                    if ($values.Count -ge 4) {
                        $nvidia += [pscustomobject]@{
                            Name = $values[0].Trim()
                            MemoryTotalMiB = $values[1].Trim()
                            MemoryUsedMiB = $values[2].Trim()
                            UtilizationPercent = $values[3].Trim()
                        }
                    }
                }
            }
        } catch {}
    }

    $security = [ordered]@{
        DefenderAvailable = $false
        RealTimeProtectionEnabled = $null
        TamperProtectionEnabled = $null
    }
    if (Test-KermitCommand 'Get-MpComputerStatus') {
        try {
            $defender = Get-MpComputerStatus -ErrorAction Stop
            $security.DefenderAvailable = $true
            $security.RealTimeProtectionEnabled = [bool]$defender.RealTimeProtectionEnabled
            $security.TamperProtectionEnabled = [bool]$defender.IsTamperProtected
        } catch {}
    }

    $totalRam = $null
    if ($null -ne $computer -and $null -ne $computer.TotalPhysicalMemory) {
        $totalRam = [math]::Round([double]$computer.TotalPhysicalMemory / 1GB, 2)
    }
    $freeRam = $null
    if ($null -ne $os -and $null -ne $os.FreePhysicalMemory) {
        $freeRam = [math]::Round([double]$os.FreePhysicalMemory / 1MB, 2)
    }

    return [pscustomobject]@{
        SchemaVersion = 1
        CollectedAt = (Get-Date).ToUniversalTime().ToString('o')
        ComputerName = $env:COMPUTERNAME
        Windows = if ($null -ne $os) { $os.Caption } else { $null }
        WindowsBuild = if ($null -ne $os) { $os.BuildNumber } else { $null }
        CPU = if ($null -ne $processor) { $processor.Name } else { $null }
        RAMTotalGiB = $totalRam
        RAMFreeGiB = $freeRam
        SystemDisk = if ($null -ne $disk) {
            [pscustomobject]@{
                Drive = $disk.DeviceID
                FreeGiB = [math]::Round([double]$disk.FreeSpace / 1GB, 2)
                TotalGiB = [math]::Round([double]$disk.Size / 1GB, 2)
            }
        } else { $null }
        DisplayAdapters = @($video)
        NvidiaGPUs = @($nvidia)
        StartupItems = @($startup)
        Tooling = [pscustomobject]$tools
        Security = [pscustomobject]$security
        Power = Get-KermitPowerInfo
    }
}

function Get-KermitGuidance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Inventory,
        [Parameter(Mandatory)][string]$Profile
    )

    $items = [System.Collections.Generic.List[object]]::new()

    if (@($Inventory.StartupItems).Count -ge 8) {
        $items.Add([pscustomobject]@{
            Level = 'info'
            Topic = 'startup'
            Message = 'Many startup entries were detected. Review them manually in Windows Settings > Apps > Startup; Kermit does not disable them automatically.'
        })
    }

    if ($Inventory.Security.DefenderAvailable -and $Inventory.Security.RealTimeProtectionEnabled -eq $false) {
        $items.Add([pscustomobject]@{
            Level = 'warning'
            Topic = 'security'
            Message = 'Microsoft Defender real-time protection appears to be off. Check which security product protects this PC.'
        })
    }

    if ($Profile -in @('AI-Training', 'AI-Inference')) {
        if (-not $Inventory.Tooling.python) {
            $items.Add([pscustomobject]@{
                Level = 'info'
                Topic = 'python'
                Message = 'Python was not found on PATH. Install a supported Python version and use an isolated virtual environment.'
            })
        }
        if (-not $Inventory.Tooling.wsl) {
            $items.Add([pscustomobject]@{
                Level = 'info'
                Topic = 'wsl'
                Message = 'WSL was not found. WSL2 may be useful for Linux-first training tools; assess hardware and virtualization requirements before installing.'
            })
        }
        if (@($Inventory.NvidiaGPUs).Count -eq 0) {
            $items.Add([pscustomobject]@{
                Level = 'info'
                Topic = 'gpu'
                Message = 'No NVIDIA GPU was confirmed by nvidia-smi. This does not rule out AMD, Intel, or CPU inference.'
            })
        }
    }

    $items.Add([pscustomobject]@{
        Level = 'info'
        Topic = 'safety'
        Message = 'Kermit never disables Defender, Windows Update, or virtualization security protections.'
    })
    return @($items.ToArray())
}

function New-KermitPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Inventory,
        [Parameter(Mandatory)][string]$Profile,
        [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Profiles/profiles.json')
    )

    $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $selected = @($config.profiles | Where-Object { $_.id -eq $Profile } | Select-Object -First 1)
    if ($selected.Count -eq 0) {
        throw "Unknown profile '$Profile'. Check Profiles/profiles.json."
    }

    $changes = @()
    $notices = @()
    $target = [string]$selected[0].powerSchemeGuid
    $current = [string]$Inventory.Power.ActiveSchemeGuid
    $available = @($Inventory.Power.AvailableSchemes)

    if ($target -notmatch $script:GuidPattern) {
        throw "Invalid power scheme GUID in profile '$Profile'."
    }

    if ([string]::IsNullOrWhiteSpace($current)) {
        $notices += 'Could not determine the active power plan; no changes will be offered.'
    }
    elseif ($available -notcontains $target) {
        $notices += 'The requested power plan is not installed or visible on this PC; no changes will be offered.'
    }
    elseif ($current -ne $target) {
        $changes += [pscustomobject]@{
            Id = 'power-plan'
            Description = 'Switch active Windows power scheme'
            Before = $current
            After = $target
            RequiresExplicitApproval = $true
        }
    }
    else {
        $notices += 'The selected Windows power scheme is already active.'
    }

    if ($Profile -in @('AI-Training', 'AI-Inference', 'Gaming')) {
        $notices += 'A performance power plan may increase heat and battery usage and does not guarantee faster AI workloads.'
    }

    return [pscustomobject]@{
        SchemaVersion = 1
        Profile = $Profile
        Description = $selected[0].description
        Changes = @($changes)
        Notices = @($notices)
        Guidance = @(Get-KermitGuidance -Inventory $Inventory -Profile $Profile)
    }
}

function Invoke-KermitPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Plan,
        [string]$SnapshotDirectory = (Join-Path $env:LOCALAPPDATA 'Kermit\Snapshots')
    )

    $changes = @($Plan.Changes)
    if ($changes.Count -eq 0) {
        return [pscustomobject]@{ Applied = $false; SnapshotPath = $null; Message = 'No changes needed or available.' }
    }
    if ($changes.Count -ne 1 -or $changes[0].Id -ne 'power-plan') {
        throw 'This MVP only supports changing the active power plan.'
    }
    if ($changes[0].Before -notmatch $script:GuidPattern -or $changes[0].After -notmatch $script:GuidPattern) {
        throw 'Invalid power scheme GUID.'
    }

    # Check again just before applying to avoid overwriting an intervening user change.
    $live = Get-KermitPowerInfo
    if ($live.ActiveSchemeGuid -ne $changes[0].Before -or $live.AvailableSchemes -notcontains $changes[0].After) {
        throw 'The active or available power schemes changed after the scan. Scan again before applying.'
    }

    $null = New-Item -ItemType Directory -Path $SnapshotDirectory -Force -ErrorAction Stop
    $snapshotPath = Join-Path $SnapshotDirectory ("{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
    $snapshot = [ordered]@{
        SchemaVersion = 1
        CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
        Profile = $Plan.Profile
        ChangeId = 'power-plan'
        PreviousPowerSchemeGuid = $changes[0].Before
        AppliedPowerSchemeGuid = $changes[0].After
    }

    & powercfg.exe /setactive $changes[0].After
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg failed to activate plan $($changes[0].After). No snapshot was created."
    }

    try {
        $snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Best-effort rollback if the state file could not be persisted.
        & powercfg.exe /setactive $changes[0].Before | Out-Null
        throw 'The plan was changed but the snapshot could not be saved. A rollback was attempted.'
    }

    return [pscustomobject]@{
        Applied = $true
        SnapshotPath = $snapshotPath
        Message = 'Power plan updated; use Restore with this snapshot to revert.'
    }
}

function Restore-KermitSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $snapshot = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($snapshot.SchemaVersion -ne 1 -or $snapshot.ChangeId -ne 'power-plan') {
        throw 'Unsupported Kermit snapshot.'
    }
    $guid = [string]$snapshot.PreviousPowerSchemeGuid
    if ($guid -notmatch $script:GuidPattern) {
        throw 'Snapshot contains an invalid power scheme GUID.'
    }

    $live = Get-KermitPowerInfo
    if ($live.AvailableSchemes -notcontains $guid) {
        throw 'The original power scheme is no longer available; restore was not attempted.'
    }

    & powercfg.exe /setactive $guid
    if ($LASTEXITCODE -ne 0) { throw 'Windows could not restore the original power scheme.' }

    return [pscustomobject]@{
        Restored = $true
        PowerSchemeGuid = $guid
        Message = 'Previous power plan restored.'
    }
}

Export-ModuleMember -Function Get-KermitInventory, Get-KermitPowerInfo, Get-KermitGuidance, New-KermitPlan, Invoke-KermitPlan, Restore-KermitSnapshot
