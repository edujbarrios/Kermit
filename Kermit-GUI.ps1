#requires -Version 5.1
<#
.SYNOPSIS
  Kermit desktop UI for Windows PowerShell 5.1 (WPF).
.EXAMPLE
  powershell.exe -NoProfile -STA -File .\Kermit-GUI.ps1
.EXAMPLE
  powershell.exe -NoProfile -STA -File .\Kermit-GUI.ps1 -ValidateXaml
#>
[CmdletBinding()]
param([switch]$ValidateXaml)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Kermit GUI supports Windows only.'
}
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Run Kermit GUI with: powershell.exe -NoProfile -STA -File .\Kermit-GUI.ps1'
}
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Kermit | Workstation Toolkit"
        Width="980" Height="750" MinWidth="740" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="#0B1220"
        Foreground="#E2E8F0" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="#166534"/>
      <Setter Property="Padding" Value="13,9"/>
      <Setter Property="Margin" Value="0,0,10,10"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="MinHeight" Value="36"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#E2E8F0"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="MinHeight" Value="34"/>
      <Setter Property="Margin" Value="0,5,10,10"/>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="85"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="220"/>
      <RowDefinition Height="35"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#142238" Padding="24,12">
      <StackPanel>
        <TextBlock Text="KERMIT  /  WORKSTATION TOOLKIT" FontSize="22"
                   FontWeight="Bold" Foreground="#74E0A4"/>
        <TextBlock Text="Inspect. Preview. Optimize only what you choose."
                   Foreground="#A6B7C9" Margin="0,5,0,0"/>
      </StackPanel>
    </Border>
    <TabControl Grid.Row="1" Margin="16,14,16,8" Background="#101B2B">
      <TabItem Header="Dashboard">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="20">
            <TextBlock Text="System and AI readiness" FontSize="20"
                       FontWeight="SemiBold" Foreground="#166534"/>
            <TextBlock Text="Check Windows, RAM, storage, NVIDIA GPUs, and AI tools. Read-only."
                       Margin="0,8,0,16"/>
            <WrapPanel>
              <Button x:Name="ScanButton" Content="Scan PC"/>
              <Button x:Name="RefreshCleanupButton" Content="Find cleanup candidates"
                      Background="#2563EB"/>
            </WrapPanel>
            <TextBlock Text="Reports stay on your PC unless you share them."
                       Foreground="#64748B" Margin="0,14,0,0"/>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
      <TabItem Header="Power profiles">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="20">
            <TextBlock Text="Choose a workload" FontSize="20" FontWeight="SemiBold"/>
            <TextBlock Text="Changes only an installed Windows power scheme; performance is workload-dependent."
                       Margin="0,8,0,12"/>
            <ComboBox x:Name="ProfileCombo" Width="275" HorizontalAlignment="Left"/>
            <WrapPanel>
              <Button x:Name="PreviewProfileButton" Content="Preview"/>
              <Button x:Name="ApplyProfileButton" Content="Apply profile" Background="#2563EB"/>
              <Button x:Name="RestoreProfileButton" Content="Restore snapshot" Background="#475569"/>
            </WrapPanel>
            <TextBlock Text="Applying requires preview and confirmation. Power changes save a restore snapshot."
                       Foreground="#64748B" Margin="0,12,0,0"/>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
      <TabItem Header="Cleanup">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="20">
            <TextBlock Text="Cleanup (explicit opt-in)" FontSize="20"
                       FontWeight="SemiBold"/>
            <TextBlock Text="Preview every action. Temp deletion and app removal cannot be reliably undone."
                       Margin="0,8,0,16"/>
            <TextBlock Text="Old user temporary files" FontWeight="SemiBold"/>
            <WrapPanel Margin="0,8,0,2">
              <TextBlock Text="Minimum age (days)" VerticalAlignment="Center" Margin="0,0,12,0"/>
              <ComboBox x:Name="AgeCombo" Width="85"/>
              <Button x:Name="PreviewTempButton" Content="Preview"/>
              <Button x:Name="ApplyTempButton" Content="Delete selected temp files" Background="#B45309"/>
            </WrapPanel>
            <Border Background="#243349" Height="1" Margin="0,10,0,14"/>
            <TextBlock Text="Curated optional Windows apps" FontWeight="SemiBold"/>
            <TextBlock Text="Current-user uninstall only. Settings could be lost."
                       Foreground="#64748B" Margin="0,5,0,5"/>
            <ComboBox x:Name="AppCombo" MinWidth="540" MaxWidth="690"
                      HorizontalAlignment="Left" DisplayMemberPath="Display"/>
            <WrapPanel>
              <Button x:Name="PreviewAppButton" Content="Preview"/>
              <Button x:Name="ApplyAppButton" Content="Uninstall selected app" Background="#B45309"/>
            </WrapPanel>
            <Border Background="#243349" Height="1" Margin="0,10,0,14"/>
            <TextBlock Text="Selected running application" FontWeight="SemiBold"/>
            <TextBlock Text="Stopping an app may discard unsaved work."
                       Foreground="#64748B" Margin="0,5,0,5"/>
            <ComboBox x:Name="ProcessCombo" MinWidth="540" MaxWidth="690"
                      HorizontalAlignment="Left" DisplayMemberPath="Display"/>
            <WrapPanel>
              <Button x:Name="PreviewProcessButton" Content="Preview"/>
              <Button x:Name="ApplyProcessButton" Content="Stop selected process" Background="#B45309"/>
            </WrapPanel>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
    </TabControl>
    <Border Grid.Row="2" Margin="16,4,16,10" Padding="12" Background="#111C2D"
            BorderBrush="#2B4159" BorderThickness="1" CornerRadius="6">
      <DockPanel>
        <TextBlock DockPanel.Dock="Top" Text="ACTIVITY / PREVIEW" FontSize="12"
                   FontWeight="Bold" Foreground="#74E0A4" Margin="0,0,0,8"/>
        <TextBox x:Name="OutputBox" Background="#111C2D" Foreground="#E2E8F0"
                 BorderThickness="0" FontFamily="Consolas" FontSize="12"
                 IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True"
                 VerticalScrollBarVisibility="Auto"
                 Text="Ready. Scan or preview an operation."/>
      </DockPanel>
    </Border>
    <Border Grid.Row="3" Background="#142238" Padding="18,6">
      <TextBlock x:Name="StatusText" Text="Read-only by default."
                 Foreground="#A6B7C9"/>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.IO.StringReader($xaml)
$xmlReader = [System.Xml.XmlReader]::Create($reader)
try { $window = [Windows.Markup.XamlReader]::Load($xmlReader) }
finally { $xmlReader.Dispose(); $reader.Dispose() }

$controls = @{}
$names = @('ScanButton','RefreshCleanupButton','ProfileCombo','PreviewProfileButton',
           'ApplyProfileButton','RestoreProfileButton','AgeCombo','PreviewTempButton',
           'ApplyTempButton','AppCombo','PreviewAppButton','ApplyAppButton',
           'ProcessCombo','PreviewProcessButton','ApplyProcessButton','OutputBox','StatusText')
foreach ($name in $names) {
    $controls[$name] = $window.FindName($name)
    if ($null -eq $controls[$name]) { throw "Missing GUI control: $name" }
}
if ($ValidateXaml) { Write-Output 'Kermit WPF XAML validated.'; return }

Import-Module (Join-Path $PSScriptRoot 'src/Kermit.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src/Kermit.Cleanup.psm1') -Force

$script:ProfilePlan = $null
$script:TempPlan = $null
$script:AppPlan = $null
$script:ProcessPlan = $null

function Show-Result {
    param([object]$Value, [string]$Status = 'Ready')
    $controls.OutputBox.Text = if ($Value -is [string]) { $Value } else { $Value | ConvertTo-Json -Depth 10 }
    $controls.OutputBox.ScrollToHome()
    $controls.StatusText.Text = $Status
}
function Show-Error {
    param([string]$Message)
    Show-Result -Value ("Error: {0}" -f $Message) -Status 'Operation not completed'
    [System.Windows.MessageBox]::Show($window, $Message, 'Kermit', 'OK', 'Error') | Out-Null
}
function Confirm-Action {
    param([string]$Message)
    $question = $Message + [Environment]::NewLine + [Environment]::NewLine + 'Continue?'
    return ([System.Windows.MessageBox]::Show($window, $question, 'Kermit | Confirm',
                'YesNo', 'Warning') -eq [System.Windows.MessageBoxResult]::Yes)
}
function Refresh-Candidates {
    $inventory = Get-KermitCleanupInventory
    $controls.AppCombo.Items.Clear()
    foreach ($app in @($inventory.OptionalInstalledApps)) {
        [void]$controls.AppCombo.Items.Add([pscustomobject]@{
            Name = $app.Name
            Display = ('{0} - {1}' -f $app.Name, $app.Description)
        })
    }
    $controls.ProcessCombo.Items.Clear()
    foreach ($p in @($inventory.TopProcesses | Where-Object EligibleForOptInStop)) {
        [void]$controls.ProcessCombo.Items.Add([pscustomobject]@{
            Id = $p.Id
            Name = $p.Name
            Display = ('{0}, PID {1}, {2} MiB' -f $p.Name, $p.Id, $p.WorkingSetMiB)
        })
    }
    $script:AppPlan = $null
    $script:ProcessPlan = $null
    Show-Result -Value $inventory -Status 'Cleanup inventory only; no changes'
}

foreach ($profile in @('Balanced','AI-Training','AI-Inference','Gaming','Development')) {
    [void]$controls.ProfileCombo.Items.Add($profile)
}
$controls.ProfileCombo.SelectedIndex = 0
foreach ($age in @(7,14,30)) { [void]$controls.AgeCombo.Items.Add($age) }
$controls.AgeCombo.SelectedItem = 14

$controls.ProfileCombo.Add_SelectionChanged({ $script:ProfilePlan = $null })
$controls.AgeCombo.Add_SelectionChanged({ $script:TempPlan = $null })
$controls.AppCombo.Add_SelectionChanged({ $script:AppPlan = $null })
$controls.ProcessCombo.Add_SelectionChanged({ $script:ProcessPlan = $null })

$controls.ScanButton.Add_Click({
    try {
        $inventory = Get-KermitInventory
        Show-Result -Value ([pscustomobject]@{
            Inventory = $inventory
            AIRecommendations = @(Get-KermitGuidance -Inventory $inventory -Profile 'AI-Training')
        }) -Status 'Read-only system scan complete'
    } catch { Show-Error $_.Exception.Message }
})
$controls.RefreshCleanupButton.Add_Click({
    try { Refresh-Candidates } catch { Show-Error $_.Exception.Message }
})

$controls.PreviewProfileButton.Add_Click({
    try {
        $script:ProfilePlan = New-KermitPlan -Inventory (Get-KermitInventory) -Profile ([string]$controls.ProfileCombo.SelectedItem)
        Show-Result -Value $script:ProfilePlan -Status 'Power profile preview only'
    } catch { $script:ProfilePlan = $null; Show-Error $_.Exception.Message }
})
$controls.ApplyProfileButton.Add_Click({
    try {
        if ($null -eq $script:ProfilePlan -or
            $script:ProfilePlan.Profile -ne [string]$controls.ProfileCombo.SelectedItem) {
            throw 'Preview the selected power profile first.'
        }
        if (@($script:ProfilePlan.Changes).Count -eq 0) {
            Show-Result -Value 'No changes are needed or available.' -Status 'Nothing to apply'
            return
        }
        if (-not (Confirm-Action "Apply selected Windows power plan? Kermit saves a restore snapshot.")) { return }
        $result = Invoke-KermitPlan -Plan $script:ProfilePlan
        $script:ProfilePlan = $null
        Show-Result -Value $result -Status 'Power profile applied'
    } catch { $script:ProfilePlan = $null; Show-Error $_.Exception.Message }
})
$controls.RestoreProfileButton.Add_Click({
    try {
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = 'Select a Kermit power snapshot'
        $dialog.Filter = 'JSON snapshots (*.json)|*.json'
        $folder = Join-Path $env:LOCALAPPDATA 'Kermit\Snapshots'
        if (Test-Path -LiteralPath $folder) { $dialog.InitialDirectory = $folder }
        if ($dialog.ShowDialog($window) -ne $true) { return }
        if (-not (Confirm-Action 'Restore the power scheme recorded in this snapshot?')) { return }
        $result = Restore-KermitSnapshot -Path $dialog.FileName
        $script:ProfilePlan = $null
        Show-Result -Value $result -Status 'Power profile restored'
    } catch { Show-Error $_.Exception.Message }
})

$controls.PreviewTempButton.Add_Click({
    try {
        $script:TempPlan = Get-KermitCleanupPlan -Target Temp -MinimumAgeDays ([int]$controls.AgeCombo.SelectedItem)
        Show-Result -Value $script:TempPlan -Status 'Temporary files preview only'
    } catch { $script:TempPlan = $null; Show-Error $_.Exception.Message }
})
$controls.ApplyTempButton.Add_Click({
    try {
        $age = [int]$controls.AgeCombo.SelectedItem
        if ($null -eq $script:TempPlan -or $script:TempPlan.MinimumAgeDays -ne $age) {
            throw 'Preview the selected temporary file cleanup first.'
        }
        if ($script:TempPlan.CandidateCount -eq 0) {
            Show-Result -Value 'Nothing eligible to clean.' -Status 'No files deleted'
            return
        }
        if (-not (Confirm-Action "Permanently delete eligible user Temp files older than $age days? This cannot be undone.")) { return }
        $result = Invoke-KermitCleanup -Plan $script:TempPlan
        $script:TempPlan = $null
        Show-Result -Value $result -Status 'User Temp cleanup complete'
    } catch { $script:TempPlan = $null; Show-Error $_.Exception.Message }
})
$controls.PreviewAppButton.Add_Click({
    try {
        $selected = $controls.AppCombo.SelectedItem
        if ($null -eq $selected) { throw 'Refresh candidates and select an optional app first.' }
        $script:AppPlan = Get-KermitCleanupPlan -Target App -AppName $selected.Name
        Show-Result -Value $script:AppPlan -Status 'App removal preview only'
    } catch { $script:AppPlan = $null; Show-Error $_.Exception.Message }
})
$controls.ApplyAppButton.Add_Click({
    try {
        $selected = $controls.AppCombo.SelectedItem
        if ($null -eq $selected -or $null -eq $script:AppPlan -or
            $script:AppPlan.Selection -cne $selected.Name) {
            throw 'Preview this specific optional app first.'
        }
        if (-not (Confirm-Action "Uninstall $($selected.Name) from this Windows user? Settings may be lost.")) { return }
        $result = Invoke-KermitCleanup -Plan $script:AppPlan
        $script:AppPlan = $null
        Refresh-Candidates
        Show-Result -Value $result -Status 'Optional app uninstalled'
    } catch { $script:AppPlan = $null; Show-Error $_.Exception.Message }
})
$controls.PreviewProcessButton.Add_Click({
    try {
        $selected = $controls.ProcessCombo.SelectedItem
        if ($null -eq $selected) { throw 'Refresh candidates and select a running app first.' }
        $script:ProcessPlan = Get-KermitCleanupPlan -Target Process -ProcessId $selected.Id -ProcessName $selected.Name
        Show-Result -Value $script:ProcessPlan -Status 'Process stop preview only'
    } catch { $script:ProcessPlan = $null; Show-Error $_.Exception.Message }
})
$controls.ApplyProcessButton.Add_Click({
    try {
        $selected = $controls.ProcessCombo.SelectedItem
        if ($null -eq $selected -or $null -eq $script:ProcessPlan -or
            $script:ProcessPlan.ProcessId -ne $selected.Id -or $script:ProcessPlan.Selection -cne $selected.Name) {
            throw 'Preview this specific process first.'
        }
        if (-not (Confirm-Action "Stop $($selected.Name) (PID $($selected.Id))? Unsaved work may be lost.")) { return }
        $result = Invoke-KermitCleanup -Plan $script:ProcessPlan
        $script:ProcessPlan = $null
        Refresh-Candidates
        Show-Result -Value $result -Status 'Selected process stop requested'
    } catch { $script:ProcessPlan = $null; Show-Error $_.Exception.Message }
})

[void]$window.ShowDialog()
