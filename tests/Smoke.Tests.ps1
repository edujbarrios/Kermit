# Kermit smoke tests - safe to run without administrator rights.
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Kermit.Core.psm1') -Force
$balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
$fast = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

function Assert-Kermit {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
}

function New-FakeInventory {
    param([string]$Active, [string[]]$Available)
    return [pscustomobject]@{
        StartupItems = @()
        NvidiaGPUs = @()
        Security = [pscustomobject]@{
            DefenderAvailable = $true
            RealTimeProtectionEnabled = $true
        }
        Tooling = [pscustomobject]@{
            python = $true
            wsl = $true
        }
        Power = [pscustomobject]@{
            ActiveSchemeGuid = $Active
            AvailableSchemes = @($Available)
        }
    }
}

$inventory = New-FakeInventory -Active $balanced -Available @($balanced, $fast)
$plan = New-KermitPlan -Inventory $inventory -Profile 'AI-Training'
Assert-Kermit (@($plan.Changes).Count -eq 1) 'AI-Training should offer one power plan change'
Assert-Kermit ($plan.Changes[0].Before -eq $balanced) 'Plan must preserve previous GUID'
Assert-Kermit ($plan.Changes[0].After -eq $fast) 'Plan must target high performance'

$balancedPlan = New-KermitPlan -Inventory $inventory -Profile 'Balanced'
Assert-Kermit (@($balancedPlan.Changes).Count -eq 0) 'Balanced is no-op when already active'

$absent = New-FakeInventory -Active $balanced -Available @($balanced)
$absentPlan = New-KermitPlan -Inventory $absent -Profile 'AI-Training'
Assert-Kermit (@($absentPlan.Changes).Count -eq 0) 'Do not offer unavailable power scheme'
Assert-Kermit (@($absentPlan.Notices).Count -gt 0) 'Unavailable scheme should explain why'

$guidance = @(Get-KermitGuidance -Inventory $inventory -Profile 'AI-Training')
Assert-Kermit (@($guidance | Where-Object Topic -eq 'safety').Count -eq 1) 'Safety guidance required'

$unknownThrew = $false
try { $null = New-KermitPlan -Inventory $inventory -Profile 'UnknownProfile' }
catch { $unknownThrew = $true }
Assert-Kermit $unknownThrew 'Unknown profiles must be rejected'

Write-Host 'Kermit smoke tests passed.' -ForegroundColor Green
