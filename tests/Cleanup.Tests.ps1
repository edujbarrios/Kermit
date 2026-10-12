# Cleanup tests use an isolated fake LOCALAPPDATA and never uninstall apps or stop processes.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Kermit.Cleanup.psm1') -Force

function Assert-Kermit {
    param([bool]$Condition, [string]$Reason)
    if (-not $Condition) { throw "FAILED: $Reason" }
}
function Assert-Throws {
    param([scriptblock]$Block,[string]$Reason)
    $failed = $false
    try { & $Block | Out-Null } catch { $failed = $true }
    Assert-Kermit $failed $Reason
}

$catalog = Get-KermitCleanupCatalog
Assert-Kermit ($catalog.SchemaVersion -eq 1) 'Catalog schema should be supported'
Assert-Kermit (@($catalog.OptionalApps).Count -gt 0) 'Catalog should contain explicit optional apps'
Assert-Kermit (@($catalog.OptionalApps | Where-Object { $_.Name -eq 'Microsoft.Windows.ShellExperienceHost' }).Count -eq 0) 'Core Windows shell may not be in catalog'
Assert-Throws { Get-KermitCleanupPlan -Target App -AppName 'Microsoft.Windows.ShellExperienceHost' } 'Core Windows package must not be removable'
Assert-Throws { Get-KermitCleanupPlan -Target App -AppName 'C:\Windows\System32' } 'Arbitrary app strings must be refused'
Assert-Throws { Get-KermitCleanupPlan -Target Process -ProcessId 0 -ProcessName 'chrome' } 'Process selection must require positive PID'
Assert-Throws { Get-KermitCleanupPlan -Target Process -ProcessId $PID -ProcessName 'chrome' } 'Cannot stop own PowerShell process'

$oldLocalAppData = $env:LOCALAPPDATA
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("kermit-test-{0}" -f [guid]::NewGuid().ToString('N'))
$fakeTemp = Join-Path $fixtureRoot 'Temp'
$null = New-Item -Path $fakeTemp -ItemType Directory -Force
$oldPath = Join-Path $fakeTemp 'old.tmp'
$newPath = Join-Path $fakeTemp 'new.tmp'
$nested = Join-Path $fakeTemp 'nested'
$null = New-Item -Path $nested -ItemType Directory -Force
$nestedPath = Join-Path $nested 'old-nested.tmp'

try {
    $env:LOCALAPPDATA = $fixtureRoot
    [IO.File]::WriteAllText($oldPath, ('x' * 1024))
    [IO.File]::WriteAllText($newPath, 'keep')
    [IO.File]::WriteAllText($nestedPath, 'keep')
    $oldTime = (Get-Date).AddDays(-12)
    (Get-Item -LiteralPath $oldPath).CreationTime = $oldTime
    (Get-Item -LiteralPath $oldPath).LastWriteTime = $oldTime
    (Get-Item -LiteralPath $nestedPath).CreationTime = $oldTime
    (Get-Item -LiteralPath $nestedPath).LastWriteTime = $oldTime

    $plan = Get-KermitCleanupPlan -Target Temp -MinimumAgeDays 7
    Assert-Kermit ($plan.CandidateCount -eq 1) 'Only old top-level files should be targeted'
    Assert-Kermit (Test-Path -LiteralPath $oldPath) 'Dry run must not delete old file'
    Assert-Kermit (Test-Path -LiteralPath $newPath) 'Dry run must not delete new file'
    Assert-Kermit (Test-Path -LiteralPath $nestedPath) 'Dry run must not recurse'

    $outcome = Invoke-KermitCleanup -Plan $plan
    Assert-Kermit ($outcome.DeletedFiles -eq 1) 'Opt-in cleanup should remove one eligible file'
    Assert-Kermit (-not (Test-Path -LiteralPath $oldPath)) 'Eligible file was not removed'
    Assert-Kermit (Test-Path -LiteralPath $newPath) 'Recent file must be retained'
    Assert-Kermit (Test-Path -LiteralPath $nestedPath) 'Nested files must be retained'

    $inventory = Get-KermitCleanupInventory
    Assert-Kermit ($inventory.SchemaVersion -eq 1) 'Inventory schema should be supported'
    Assert-Kermit ($inventory.Temp.CandidateFiles -eq 0) 'No old top-level candidates should remain'
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
Write-Host 'Kermit cleanup smoke tests passed.' -ForegroundColor Green
