#requires -Version 5.1
<#
.SYNOPSIS
  Kermit Cleanup: read-only audit and explicit, narrowly-scoped cleanup.
.DESCRIPTION
  Inventory and Plan never modify Windows. Apply requires -Approve and a
  matching Target plus selectors. Temp deletes only old, top-level regular
  files from the current user's LOCALAPPDATA\Temp; App removes only one
  curated per-user Appx package; Process stops only one selected opt-in PID.
.EXAMPLE
  .\Cleanup.ps1 -Action Inventory
.EXAMPLE
  .\Cleanup.ps1 -Action Plan -Target Temp
.EXAMPLE
  .\Cleanup.ps1 -Action Apply -Target Temp -Approve
.EXAMPLE
  .\Cleanup.ps1 -Action Plan -Target App -AppName Microsoft.BingWeather
.EXAMPLE
  .\Cleanup.ps1 -Action Apply -Target App -AppName Microsoft.BingWeather -Approve
.EXAMPLE
  .\Cleanup.ps1 -Action Plan -Target Process -ProcessId 1256 -ProcessName Discord
#>
[CmdletBinding()]
param(
    [ValidateSet('Inventory', 'Plan', 'Apply')][string]$Action = 'Inventory',
    [ValidateSet('Temp', 'App', 'Process')][string]$Target = 'Temp',
    [string]$AppName,
    [int]$ProcessId,
    [string]$ProcessName,
    [ValidateRange(7,365)][int]$MinimumAgeDays = 7,
    [switch]$Approve,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Kermit Cleanup only runs on Windows.'
}

Import-Module (Join-Path $PSScriptRoot 'src/Kermit.Cleanup.psm1') -Force -ErrorAction Stop

if ($Action -eq 'Inventory') {
    $result = [pscustomobject]@{
        Action = 'Inventory'
        Inventory = (Get-KermitCleanupInventory -MinimumAgeDays $MinimumAgeDays)
    }
}
else {
    # Create and recheck a current plan on every run, never execute serialized plans.
    $planArgs = @{ Target = $Target; MinimumAgeDays = $MinimumAgeDays }
    if ($Target -eq 'App') { $planArgs.AppName = $AppName }
    if ($Target -eq 'Process') {
        $planArgs.ProcessId = $ProcessId
        $planArgs.ProcessName = $ProcessName
    }
    $plan = Get-KermitCleanupPlan @planArgs
    if ($Action -eq 'Plan') {
        $result = [pscustomobject]@{ Action = 'Plan'; Plan = $plan }
    }
    else {
        if (-not $Approve) {
            throw 'Cleanup requires explicit -Approve. Review -Action Plan first.'
        }
        $result = [pscustomobject]@{
            Action = 'Apply'
            Plan = $plan
            Result = (Invoke-KermitCleanup -Plan $plan)
        }
    }
}

if ($Json) { $result | ConvertTo-Json -Depth 9; return }

Write-Host ''
Write-Host ' KERMIT CLEANUP | Safe, opt-in workstation cleanup' -ForegroundColor Green
Write-Host ''
if ($Action -eq 'Inventory') {
    Write-Host (' Optional apps detected: {0}' -f @($result.Inventory.OptionalInstalledApps).Count)
    $result.Inventory.OptionalInstalledApps | Format-Table Name, Description -AutoSize | Out-Host
    Write-Host (' Temp files eligible (age >= {0} days): {1}, about {2} MiB' -f $MinimumAgeDays, $result.Inventory.Temp.CandidateFiles, $result.Inventory.Temp.CandidateMiB)
    Write-Host ' Top processes by working set:'
    $result.Inventory.TopProcesses | Format-Table Id, Name, WorkingSetMiB, EligibleForOptInStop -AutoSize | Out-Host
    Write-Host ' Process selection requires an exact PID and a listed allowed name.'
}
else {
    $plan | Format-List | Out-Host
    if ($Action -eq 'Plan') { Write-Host 'Dry run only; nothing changed. To proceed, rerun with -Action Apply -Approve.' }
    else { $result.Result | Format-List | Out-Host }
}
