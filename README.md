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

# Resource baseline before optimizing
.\Benchmark.ps1 -Action Capture -Label Before

# AI diagnostics without modifying Windows
.\AI-Doctor.ps1

# CLI: inspect without changing anything
.\Kermit.ps1 -Action Scan
.\Kermit.ps1 -Action Plan -Profile AI-Training
.\Cleanup.ps1 -Action Inventory
```

## What it does

- **Scan:** hardware, RAM, storage, startup apps, security status, NVIDIA GPUs, Python, WSL, and Docker.
- **AI Doctor:** checks Python and installed AI package versions, NVIDIA GPUs, CUDA compiler, and WSL/Docker presence. Optional deeper PyTorch/CUDA runtime test.
- **Profiles:** Balanced, AI Training, AI Inference, Gaming, and Development. Currently, applying a profile can change only an *existing* Windows power plan; snapshots allow restoring it.
- **Cleanup:** preview optional Appx apps, selected background processes, and old user Temp files. Nothing is removed automatically.
- **Benchmarks:** save resource snapshots before/after and compare RAM, processes, disk, CPU and optional NVIDIA GPU readings. Not a training-speed test.
- **GUI + CLI:** all actions are local; diagnostic output is available as JSON from the CLI.

## AI Doctor

```powershell
# Read-only diagnosis, with optional JSON export
.\AI-Doctor.ps1 -Json -OutputPath .\ai-report.json

# Opt-in deep check: imports PyTorch and tests torch.cuda.is_available()
.\AI-Doctor.ps1 -DeepCheck
```

The CUDA version advertised by a driver **is not** the installed CUDA Toolkit; `nvcc` reports a compiler version if installed. Finding NVIDIA GPUs or PyTorch does **not** guarantee working GPU acceleration. AI Doctor checks only the Python interpreter found on PATH, not every virtual environment or WSL installation. No auto-installers or background downloads.

## Before / After measurements

Run the first command **before** making changes, then the second **after**. Both save JSON reports under your user profile in %LOCALAPPDATA%\Kermit\Benchmarks.

```powershell
.\Benchmark.ps1 -Action Capture -Label Before
# Run your chosen Kermit optimization, then repeat under similar idle/workload conditions.
.\Benchmark.ps1 -Action Capture -Label After
.\Benchmark.ps1 -Action Compare -BeforePath "PATH_TO_BEFORE.json" -AfterPath "PATH_TO_AFTER.json"

# Machine-readable comparison
.\Benchmark.ps1 -Action Compare -BeforePath "PATH_TO_BEFORE.json" -AfterPath "PATH_TO_AFTER.json" -Json
```

The desktop GUI also offers a **Benchmarks** tab. Reports are tied to a single computer/Windows build. Readings vary between runs: **lower RAM usage does not automatically mean faster PyTorch training**. Measure tokens/second or steps/second separately using the actual AI workload.

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

- [CLI](Kermit.ps1) · [AI Doctor](AI-Doctor.ps1) · [Benchmarks](Benchmark.ps1) · [Cleanup](Cleanup.ps1) · [Desktop GUI](Kermit-GUI.ps1)
- [Tests](tests/) · [PowerShell CI](.github/workflows/powershell.yml)
- Roadmap: validated compatibility matrix, workload-specific inference/training benchmarks, signed releases.

**License:** Not yet selected. Do not assume redistribution rights until the maintainer adds one.
