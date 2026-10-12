#requires -Version 5.1
<#
.SYNOPSIS
    Kermit: auditable Windows workstation diagnostics and opt-in optimization.
.EXAMPLE
    .\Kermit.ps1 -Action Scan
.EXAMPLE
    .\Kermit.ps1 -Action Plan -Profile AI-Training -Json
.EXAMPLE
    .\Kermit.ps1 -Action Apply -Profile AI-Training -Approve
.EXAMPLE
    .\Kermit.ps1 -Action Restore -SnapshotPath "$env:LOCALAPPDATA\Kermit\Snapshots\snapshot.json" -Approve
#>
[CmdletBinding()]
param(
    [ValidateSet('Scan', 'Plan', 'Apply', 'Restore')]
    [string]$Action = 'Scan',

    [ValidateSet('Balanced', 'AI-Training', 'AI-Inference', 'Gaming', 'Development')]
    [string]$Profile = 'Balanced',

    [switch]$Json,
    [switch]$Approve,
    [string]$SnapshotPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Kermit MVP targets Windows 10/11. No changes were made.'
}

Import-Module (Join-Path $PSScriptRoot 'src/Kermit.Core.psm1') -Force -ErrorAction Stop

switch ($Action) {
    'Scan' {
        $inventory = Get-KermitInventory
        $result = [pscustomobject]@{
            Action = 'Scan'
            Inventory = $inventory
            Guidance = @(Get-KermitGuidance -Inventory $inventory -Profile $Profile)
        }
    }
    'Plan' {
        $inventory = Get-KermitInventory
        $result = [pscustomobject]@{
            Action = 'Plan'
            Inventory = $inventory
            Plan = New-KermitPlan -Inventory $inventory -Profile $Profile
        }
    }
    'Apply' {
        if (-not $Approve) {
            throw 'Apply requires -Approve. Run -Action Plan first to review proposed changes.'
        }
        $inventory = Get-KermitInventory
        $plan = New-KermitPlan -Inventory $inventory -Profile $Profile
        $applied = Invoke-KermitPlan -Plan $plan
        $result = [pscustomobject]@{
            Action = 'Apply'
            Profile = $Profile
            Plan = $plan
            Result = $applied
        }
    }
    'Restore' {
        if (-not $Approve) {
            throw 'Restore requires -Approve.'
        }
        if ([string]::IsNullOrWhiteSpace($SnapshotPath)) {
            throw 'Restore requires -SnapshotPath pointing to a Kermit snapshot JSON file.'
        }
        $restored = Restore-KermitSnapshot -Path $SnapshotPath
        $result = [pscustomobject]@{
            Action = 'Restore'
            Result = $restored
        }
    }
}

$serialized = $result | ConvertTo-Json -Depth 12
if ($OutputPath) {
    $serialized | Set-Content -LiteralPath $OutputPath -Encoding UTF8 -ErrorAction Stop
}

if ($Json) {
    Write-Output $serialized
    return
}

Write-Host ''
Write-Host ' KERMIT | Windows workstation toolkit' -ForegroundColor Green
Write-Host (' Action: {0}   Profile: {1}' -f $Action, $Profile)
Write-Host ''

if ($Action -in @('Scan', 'Plan')) {
    Write-Host (' Windows: {0} (build {1})' -f $inventory.Windows, $inventory.WindowsBuild)
    Write-Host (' CPU: {0}' -f $inventory.CPU)
    Write-Host (' RAM: {0} GiB total, {1} GiB free' -f $inventory.RAMTotalGiB, $inventory.RAMFreeGiB)
    Write-Host (' Startup items: {0}' -f @($inventory.StartupItems).Count)
    Write-Host (' NVIDIA GPUs detected: {0}' -f @($inventory.NvidiaGPUs).Count)
    Write-Host (' Python: {0} | WSL: {1} | Docker: {2}' -f $inventory.Tooling.python, $inventory.Tooling.wsl, $inventory.Tooling.docker)
}
if ($Action -eq 'Scan') {
    Write-Host ''
    foreach ($tip in $result.Guidance) {
        Write-Host (' [{0}] {1}' -f $tip.Level, $tip.Message)
    }
}
if ($Action -eq 'Plan') {
    Write-Host ''
    Write-Host (' Proposed changes: {0}' -f @($result.Plan.Changes).Count)
    foreach ($change in $result.Plan.Changes) {
        Write-Host (' - {0}: {1} -> {2}' -f $change.Description, $change.Before, $change.After)
    }
    foreach ($note in $result.Plan.Notices) { Write-Host (' Note: {0}' -f $note) }
    foreach ($tip in $result.Plan.Guidance) { Write-Host (' [{0}] {1}' -f $tip.Level, $tip.Message) }
    Write-Host ''
    Write-Host ' No changes have been made. Apply only after reviewing the plan.'
}
if ($Action -eq 'Apply') {
    Write-Host (' {0}' -f $result.Result.Message)
    if ($result.Result.SnapshotPath) {
        Write-Host (' Snapshot: {0}' -f $result.Result.SnapshotPath)
        Write-Host ' Restore this change later using -Action Restore -SnapshotPath <path> -Approve'
    }
}
if ($Action -eq 'Restore') {
    Write-Host (' {0}' -f $result.Result.Message)
}
if ($OutputPath) { Write-Host (' Report saved to: {0}' -f $OutputPath) }
