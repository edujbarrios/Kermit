# 🐸 Kermit

**A PowerShell toolkit to prepare Windows for AI, development, and gaming.**

> Windows isn't always the first choice for AI development. Let's change that. ;)

Kermit audits your PC, recommends changes, and lets **you** decide what to apply. No magic FPS or GPU claims.

## Run it

Requires **Windows 10/11** and **Windows PowerShell 5.1**. NVIDIA tools are optional.

```powershell
git clone https://github.com/edujbarrios/Kermit.git
cd Kermit

# Desktop GUI (Windows PowerShell)
powershell.exe -NoProfile -STA -File .\Kermit-GUI.ps1

# CLI: inspect without changing anything
.\Kermit.ps1 -Action Scan
.\Kermit.ps1 -Action Plan -Profile AI-Training
.\Cleanup.ps1 -Action Inventory
```

## What it does

- **Scan:** hardware, RAM, storage, startup apps, security status, NVIDIA GPUs, Python, WSL, and Docker.
- **Profiles:** Balanced, AI Training, AI Inference, Gaming, and Development. Currently, applying a profile can change only an *existing* Windows power plan; snapshots allow restoring it.
- **Cleanup:** preview optional Appx apps, selected background processes, and old user Temp files. Nothing is removed automatically.
- **GUI + CLI:** all actions are local; diagnostic output is available as JSON from the CLI.

## Optional cleanup commands

```powershell
# Preview old user Temp files; files are not deleted yet
.\Cleanup.ps1 -Action Plan -Target Temp -MinimumAgeDays 14

# Apply only if you accept permanent deletion
.\Cleanup.ps1 -Action Apply -Target Temp -MinimumAgeDays 14 -Approve

# Optional built-in app, current user only
.\Cleanup.ps1 -Action Plan -Target App -AppName Microsoft.BingWeather
.\Cleanup.ps1 -Action Apply -Target App -AppName Microsoft.BingWeather -Approve

# Power-profile changes are reversible via a saved snapshot
.\Kermit.ps1 -Action Apply -Profile AI-Training -Approve
.\Kermit.ps1 -Action Restore -SnapshotPath "PATH_TO_KERMIT_SNAPSHOT.json" -Approve
```

For process selection, use `.\Cleanup.ps1 -Action Inventory` then preview a named allowed process using `-Target Process -ProcessId <PID> -ProcessName <Name>`. Only the specified process is affected; unsaved work may be lost.

## Safety first

**Experimental MVP.** Always preview before applying. App uninstall and Temp deletion **cannot be reliably undone**. Kermit never bulk-kills processes or disables Windows Update, Defender, security protections, or essential services. Power settings may increase battery use and heat; speedups are not guaranteed.

Everything runs locally. JSON reports may contain device and application names; review them before sharing. See [cleanup catalog](Cleanup/catalog.json) and [source code](src/) before changing settings.

## Project

- [CLI](Kermit.ps1) · [Cleanup](Cleanup.ps1) · [Desktop GUI](Kermit-GUI.ps1)
- [Tests](tests/) · [PowerShell CI](.github/workflows/powershell.yml)
- Roadmap: CUDA/PyTorch compatibility checks, benchmarks, signed releases.

**License:** Not yet selected. Do not assume redistribution rights until the maintainer adds one.
