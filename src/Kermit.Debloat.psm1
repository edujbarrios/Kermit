Set-StrictMode -Version Latest

# Kermit Debloat deliberately supports a very short, audited allowlist.
# No Win32/uninstall registry, provisioned package, AllUsers, or OS service changes.
function Get-KermitDebloatRules {
    [CmdletBinding()]
    param()

    $catalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Cleanup/catalog.json'
    $catalog = Get-Content -LiteralPath $catalogPath -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
    if ($catalog.SchemaVersion -ne 1) {
        throw 'Unsupported optional app catalog version.'
    }

    $defaultNames = @(
        'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.BingWeather',
        'Microsoft.Getstarted'
    )
    $additionalNames = @(
        'Microsoft.WindowsFeedbackHub',
        'Microsoft.GetHelp'
    )

    $rules = @()
    foreach ($name in @($defaultNames + $additionalNames)) {
        $matches = @($catalog.OptionalApps | Where-Object { $_.Name -ceq $name })
        if ($matches.Count -ne 1) {
            throw "Required app definition '$name' is absent or ambiguous in Cleanup/catalog.json."
        }
        $rules += [pscustomobject]@{
            Name = $name
            Description = [string]$matches[0].Description
            Tier = if ($defaultNames -ccontains $name) { 'default' } else { 'optional' }
        }
    }
    return @($rules)
}

function Test-KermitAppxFlag {
    param([object]$Package,[string]$Property)
    $member = $Package.PSObject.Properties[$Property]
    return ($null -ne $member -and $member.Value -eq $true)
}

function Get-KermitDebloatInstalledPackages {
    [CmdletBinding()]
    param()

    if (-not (Get-Command 'Get-AppxPackage' -ErrorAction SilentlyContinue)) {
        throw 'Get-AppxPackage is unavailable. Kermit cannot determine current-user Appx applications.'
    }
    # This intentionally omits -AllUsers and -User, targeting the calling user's profile.
    return @(Get-AppxPackage -ErrorAction Stop)
}

function New-KermitDebloatPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$InstalledPackages,
        [switch]$IncludeOptional,
        [string[]]$Keep = @()
    )

    $rules = @(Get-KermitDebloatRules)
    $allNames = @($rules | ForEach-Object { $_.Name })
    foreach ($keepName in @($Keep)) {
        if ($allNames -cnotcontains $keepName) {
            throw "Unknown app in -Keep: '$keepName'. Only curated names may be excluded."
        }
    }

    $items = @()
    $skipped = @()
    foreach ($rule in $rules) {
        $name = [string]$rule.Name
        if ($rule.Tier -eq 'optional' -and -not $IncludeOptional) {
            $skipped += [pscustomobject]@{ Name=$name; Reason='Only selected with -IncludeOptional' }
            continue
        }
        if (@($Keep) -ccontains $name) {
            $skipped += [pscustomobject]@{ Name=$name; Reason='Excluded by -Keep' }
            continue
        }

        $matches = @($InstalledPackages | Where-Object { $_.Name -ceq $name })
        if ($matches.Count -eq 0) {
            $skipped += [pscustomobject]@{ Name=$name; Reason='Not installed for current user' }
            continue
        }
        if ($matches.Count -ne 1) {
            $skipped += [pscustomobject]@{ Name=$name; Reason='Ambiguous package variants; manual review required' }
            continue
        }

        $package = $matches[0]
        $fullName = [string]$package.PackageFullName
        if ([string]::IsNullOrWhiteSpace($fullName) -or
            -not $fullName.StartsWith($name + '_', [StringComparison]::Ordinal)) {
            $skipped += [pscustomobject]@{ Name=$name; Reason='Package identity cannot be verified' }
            continue
        }
        if ((Test-KermitAppxFlag $package 'NonRemovable') -or
            (Test-KermitAppxFlag $package 'IsFramework') -or
            (Test-KermitAppxFlag $package 'IsResourcePackage')) {
            $skipped += [pscustomobject]@{ Name=$name; Reason='Windows marks this package as protected/framework/resource' }
            continue
        }
        $items += [pscustomobject]@{
            Name = $name
            PackageFullName = $fullName
            Description = [string]$rule.Description
            Tier = [string]$rule.Tier
        }
    }

    return [pscustomobject]@{
        Schema = 'kermit.debloat-plan.v1'
        CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
        Scope = 'current-user-appx-only'
        IncludeOptional = [bool]$IncludeOptional
        Keep = @($Keep)
        Count = $items.Count
        Items = @($items)
        Skipped = @($skipped)
        Warning = 'Uninstall can delete app data. Not reliably reversible. No background services, system components or other users are modified.'
    }
}

function Assert-KermitDebloatPlan {
    param([Parameter(Mandatory)][object]$Plan)

    if ($Plan.Schema -cne 'kermit.debloat-plan.v1' -or
        $Plan.Scope -cne 'current-user-appx-only' -or
        $null -eq $Plan.Items -or
        $null -eq $Plan.IncludeOptional -or
        $null -eq $Plan.Count) {
        throw 'Invalid Kermit debloat plan schema.'
    }

    $created = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Plan.CreatedAt, [ref]$created)) {
        throw 'Debloat plan timestamp is invalid.'
    }
    if ($created.ToUniversalTime() -lt (Get-Date).ToUniversalTime().AddHours(-1) -or
        $created.ToUniversalTime() -gt (Get-Date).ToUniversalTime().AddMinutes(2)) {
        throw 'Debloat plan has expired or has an invalid creation time. Make a new preview.'
    }

    $rules = @(Get-KermitDebloatRules)
    $allNames = @($rules | ForEach-Object { $_.Name })
    foreach ($keepName in @($Plan.Keep)) {
        if ($allNames -cnotcontains [string]$keepName) {
            throw "The plan's exclusion list is not from the Kermit allowlist."
        }
    }
    $items = @($Plan.Items)
    if ($items.Count -ne [int]$Plan.Count) { throw 'Debloat plan item count mismatch.' }
    if ($items.Count -gt $rules.Count) { throw 'Debloat plan exceeds the allowlist.' }
    $seen = @{}
    foreach ($item in $items) {
        $name = [string]$item.Name
        $fullName = [string]$item.PackageFullName
        $rule = @($rules | Where-Object { $_.Name -ceq $name })
        if ($rule.Count -ne 1 -or $seen.ContainsKey($name) -or
            @($Plan.Keep) -ccontains $name -or
            ($rule[0].Tier -eq 'optional' -and -not [bool]$Plan.IncludeOptional) -or
            [string]::IsNullOrWhiteSpace($fullName) -or
            -not $fullName.StartsWith($name + '_', [StringComparison]::Ordinal)) {
            throw "Unsafe, duplicate or unexpected package in debloat plan: '$name'."
        }
        $seen[$name] = $true
    }
}

function Save-KermitDebloatPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [string]$Directory = (Join-Path $env:LOCALAPPDATA 'Kermit\Debloat\Plans')
    )
    Assert-KermitDebloatPlan $Plan
    $null = New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop
    $path = Join-Path $Directory ("plan-{0}-{1}.json" -f
        (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
    $stream = New-Object System.IO.FileStream($path, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Plan | ConvertTo-Json -Depth 9))
        $stream.Write($bytes,0,$bytes.Length)
    }
    finally { $stream.Dispose() }
    return $path
}

function Read-KermitDebloatPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 1048576) {
        throw 'Invalid or oversized debloat plan.'
    }
    $plan = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
    Assert-KermitDebloatPlan $plan
    return $plan
}

function Invoke-KermitDebloatPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [switch]$Approve
    )
    if (-not $Approve) { throw 'Bulk uninstall requires explicit -Approve.' }
    Assert-KermitDebloatPlan $Plan

    $current = @(Get-KermitDebloatInstalledPackages)
    $removed = @()
    $skipped = @()
    $failed = @()

    foreach ($item in @($Plan.Items)) {
        $name = [string]$item.Name
        $matches = @($current | Where-Object { $_.Name -ceq $name })
        if ($matches.Count -ne 1 -or
            $matches[0].PackageFullName -cne [string]$item.PackageFullName -or
            (Test-KermitAppxFlag $matches[0] 'NonRemovable') -or
            (Test-KermitAppxFlag $matches[0] 'IsFramework') -or
            (Test-KermitAppxFlag $matches[0] 'IsResourcePackage')) {
            $skipped += [pscustomobject]@{
                Name = $name
                Reason = 'Package no longer matches the reviewed plan, or is not removable'
            }
            continue
        }
        try {
            # Default Remove-AppxPackage operation applies only to current user.
            Remove-AppxPackage -Package ([string]$item.PackageFullName) -ErrorAction Stop
            $removed += $name
        }
        catch {
            $failed += [pscustomobject]@{ Name=$name; Error=$_.Exception.Message }
        }
    }
    return [pscustomobject]@{
        Schema = 'kermit.debloat-result.v1'
        Removed = @($removed)
        Skipped = @($skipped)
        Failed = @($failed)
        RemovedCount = $removed.Count
        SkippedCount = $skipped.Count
        FailedCount = $failed.Count
        Warning = 'Uninstalling can remove user data; changes may not be reversible. Performance improvement is not guaranteed.'
    }
}

Export-ModuleMember -Function Get-KermitDebloatRules, Get-KermitDebloatInstalledPackages, New-KermitDebloatPlan, Save-KermitDebloatPlan, Read-KermitDebloatPlan, Invoke-KermitDebloatPlan
