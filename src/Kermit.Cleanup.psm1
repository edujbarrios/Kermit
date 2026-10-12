Set-StrictMode -Version Latest

function Get-KermitCleanupCatalog {
    [CmdletBinding()]
    param([string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Cleanup/catalog.json'))

    $catalog = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($catalog.SchemaVersion -ne 1) { throw 'Unsupported cleanup catalog version.' }
    return $catalog
}

function Get-KermitUserTempFiles {
    [CmdletBinding()]
    param([ValidateRange(7,365)][int]$MinimumAgeDays = 7)

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { return @() }
    $folder = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Temp'))
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return @() }
    $directory = Get-Item -LiteralPath $folder -Force -ErrorAction Stop
    if (([int]($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) -ne 0) {
        throw 'User Temp directory is a junction or symbolic link. Refusing to clean it.'
    }
    $cutoff = (Get-Date).AddDays(-$MinimumAgeDays)
    $files = @()
    foreach ($item in @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction Stop)) {
        if (([int]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) -ne 0) { continue }
        if ($item.LastWriteTime -ge $cutoff -or $item.CreationTime -ge $cutoff) { continue }
        if (-not [string]::Equals([IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($item.FullName)),
                $folder, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $files += $item
    }
    return @($files)
}

function Get-KermitCleanupInventory {
    [CmdletBinding()]
    param([ValidateRange(7,365)][int]$MinimumAgeDays = 7)

    $catalog = Get-KermitCleanupCatalog
    $apps = @()
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        try {
            $installed = @(Get-AppxPackage -ErrorAction Stop)
            foreach ($entry in @($catalog.OptionalApps)) {
                foreach ($app in @($installed | Where-Object { $_.Name -ceq $entry.Name })) {
                    $apps += [pscustomobject]@{
                        Name = $app.Name
                        Description = $entry.Description
                        PackageFullName = $app.PackageFullName
                        Action = 'Explicitly selected per-user uninstall only'
                    }
                }
            }
        }
        catch {
            Write-Verbose "Could not enumerate Appx packages: $($_.Exception.Message)"
        }
    }

    $processes = @()
    try {
        $processes = @(Get-Process -ErrorAction Stop |
            Sort-Object -Property WorkingSet64 -Descending |
            Select-Object -First 20 |
            ForEach-Object {
                [pscustomobject]@{
                    Id = $_.Id
                    Name = $_.ProcessName
                    WorkingSetMiB = [math]::Round($_.WorkingSet64 / 1MB, 1)
                    EligibleForOptInStop = @($catalog.StoppableProcesses) -contains $_.ProcessName
                }
            })
    } catch { Write-Verbose "Process inventory failed: $($_.Exception.Message)" }

    $files = @(Get-KermitUserTempFiles -MinimumAgeDays $MinimumAgeDays)
    $bytes = [long]0
    foreach ($file in $files) { $bytes += [long]$file.Length }

    return [pscustomobject]@{
        SchemaVersion = 1
        CollectedAt = (Get-Date).ToUniversalTime().ToString('o')
        OptionalInstalledApps = @($apps)
        TopProcesses = @($processes)
        StoppableProcessNames = @($catalog.StoppableProcesses)
        Temp = [pscustomobject]@{
            Scope = '%LOCALAPPDATA%\Temp (top-level regular files only)'
            MinimumAgeDays = $MinimumAgeDays
            CandidateFiles = $files.Count
            CandidateMiB = [math]::Round($bytes / 1MB, 2)
        }
    }
}

function Get-KermitCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Temp','App','Process')][string]$Target,
        [string]$AppName,
        [int]$ProcessId,
        [string]$ProcessName,
        [ValidateRange(7,365)][int]$MinimumAgeDays = 7
    )

    $catalog = Get-KermitCleanupCatalog
    switch ($Target) {
        'Temp' {
            $files = @(Get-KermitUserTempFiles -MinimumAgeDays $MinimumAgeDays)
            $bytes = [long]0
            foreach ($file in $files) { $bytes += [long]$file.Length }
            return [pscustomobject]@{
                Target = 'Temp'
                Selection = '%LOCALAPPDATA%\Temp, top-level files'
                CandidateCount = $files.Count
                EstimatedMiB = [math]::Round($bytes / 1MB, 2)
                MinimumAgeDays = $MinimumAgeDays
                Warning = 'Deletion is permanent. In-use, recent, nested and linked items are skipped.'
            }
        }
        'App' {
            if ([string]::IsNullOrWhiteSpace($AppName) -or @($catalog.OptionalApps | Where-Object { $_.Name -ceq $AppName }).Count -ne 1) {
                throw "App not approved by the curated catalog. Run -Action Inventory to see optional apps."
            }
            if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
                throw 'Get-AppxPackage is unavailable.'
            }
            $apps = @(Get-AppxPackage -Name $AppName -ErrorAction Stop | Where-Object { $_.Name -ceq $AppName })
            if ($apps.Count -ne 1) { throw 'Expected exactly one matching per-user Appx package. Nothing will be removed.' }
            return [pscustomobject]@{
                Target = 'App'
                Selection = $AppName
                PackageFullName = $apps[0].PackageFullName
                Warning = 'Uninstalling may remove per-user app settings. Reinstallation and recovery are not guaranteed. No OS-wide packages are changed.'
            }
        }
        'Process' {
            if ($ProcessId -le 0 -or [string]::IsNullOrWhiteSpace($ProcessName)) {
                throw 'Provide both -ProcessId and -ProcessName.'
            }
            if ($ProcessId -eq $PID) { throw 'Kermit cannot stop its own process.' }
            if (@($catalog.StoppableProcesses) -cnotcontains $ProcessName) {
                throw 'Process name is not on the conservative opt-in stop list.'
            }
            $process = Get-Process -Id $ProcessId -ErrorAction Stop
            if ($process.ProcessName -cne $ProcessName) {
                throw 'The PID no longer belongs to the expected process.'
            }
            $path = $null
            try { $path = $process.Path } catch {}
            if ([string]::IsNullOrWhiteSpace($path)) { throw 'Cannot verify process executable path; refusing to stop it.' }
            if (-not [IO.Path]::IsPathRooted($path)) { throw 'Executable path is not absolute; refusing to stop it.' }
            if (-not [string]::IsNullOrWhiteSpace($env:WINDIR)) {
                $windows = [IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\') + '\'
                if ($path.StartsWith($windows, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Refusing to stop a process running from the Windows directory.'
                }
            }
            return [pscustomobject]@{
                Target = 'Process'
                Selection = $ProcessName
                ProcessId = $ProcessId
                ExecutablePath = $path
                Warning = 'This may discard unsaved application data. Kermit does not kill process trees or force-stop services.'
            }
        }
    }
}

function Invoke-KermitCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Plan
    )

    switch ([string]$Plan.Target) {
        'Temp' {
            # Recompute eligibility immediately before deletion; never trust paths from a saved plan.
            $age = [int]$Plan.MinimumAgeDays
            $files = @(Get-KermitUserTempFiles -MinimumAgeDays $age)
            $deleted = 0
            $skipped = 0
            $bytes = [long]0
            foreach ($file in $files) {
                try {
                    $live = Get-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    if ($live.PSIsContainer -or
                        (([int]($live.Attributes -band [IO.FileAttributes]::ReparsePoint)) -ne 0) -or
                        $live.LastWriteTime -ge (Get-Date).AddDays(-$age) -or
                        $live.CreationTime -ge (Get-Date).AddDays(-$age)) {
                        $skipped++
                        continue
                    }
                    Remove-Item -LiteralPath $live.FullName -Force -ErrorAction Stop
                    $deleted++
                    $bytes += [long]$live.Length
                }
                catch { $skipped++ }
            }
            return [pscustomobject]@{
                Target = 'Temp'
                DeletedFiles = $deleted
                SkippedFiles = $skipped
                FreedMiB = [math]::Round($bytes / 1MB, 2)
                Reversible = $false
            }
        }
        'App' {
            # Check the curated catalog and exact installed package again.
            $live = Get-KermitCleanupPlan -Target App -AppName ([string]$Plan.Selection)
            if ($live.PackageFullName -cne $Plan.PackageFullName) {
                throw 'Installed Appx package changed since planning; rescan before proceeding.'
            }
            Remove-AppxPackage -Package $live.PackageFullName -ErrorAction Stop
            return [pscustomobject]@{
                Target = 'App'
                RemovedPackage = $live.PackageFullName
                Reversible = $false
                Message = 'App removed from the current user. Reinstall via its official source if needed.'
            }
        }
        'Process' {
            $live = Get-KermitCleanupPlan -Target Process -ProcessId ([int]$Plan.ProcessId) -ProcessName ([string]$Plan.Selection)
            if ($live.ExecutablePath -cne $Plan.ExecutablePath) {
                throw 'Process path changed since planning; rescan before proceeding.'
            }
            Stop-Process -Id ([int]$live.ProcessId) -ErrorAction Stop
            return [pscustomobject]@{
                Target = 'Process'
                ProcessId = $live.ProcessId
                Name = $live.Selection
                Message = 'A single selected process was asked to stop. It may restart automatically.'
            }
        }
        default { throw 'Unsupported cleanup operation.' }
    }
}

Export-ModuleMember -Function Get-KermitCleanupCatalog, Get-KermitUserTempFiles, Get-KermitCleanupInventory, Get-KermitCleanupPlan, Invoke-KermitCleanup
