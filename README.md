# 🐸 Kermit

**A safer, PowerShell-first Windows workstation optimizer for AI, development, gaming, and everyday work.**

> **Windows isn't always the first choice for AI development. Let's change that. ;)**
>
> Built with PowerShell. Ready for AI. Made for Windows.

Kermit is a publicly developed toolkit for understanding the state of your Windows PC and applying *small, explainable, reversible* changes. The objective is less unnecessary background work, easier AI environment setup, and measurable results — **not** "magical" GPU or VRAM gains.

> [!IMPORTANT]
> **Early MVP / experimental software.** This project is not a security hardening certification, an antivirus, or a performance guarantee. Review the plan before applying it. Do not execute remote scripts blindly.

## About Kermit

**Windows performance and AI-readiness, without risky blanket debloating.** Kermit is a PowerShell workstation toolkit that inspects Windows, explains optional optimizations, and only changes settings after explicit approval. Suitable for developers, AI researchers, and power users who want an auditable local-first tool.

Keywords: `powershell`, `windows`, `optimization`, `debloat`, `ai`, `gpu`, `workstation`.

## Cleanup: optional apps, processes and temporary files

The separate `Cleanup.ps1` script is **opt-in only** and intentionally conservative. Its inventory provides a shortlist rather than claiming every listed item is unnecessary.

| Operation | Dry-run | Applied effect | Limitations |
| --- | --- | --- | --- |
| Temp | Counts top-level old files in user Temp | Deletes eligible regular files | Minimum age 7 days; no recursion; not reversible |
| App | Checks a curated optional Appx package | Uninstalls that exact package for **current user only** | Settings may be lost, reinstall not guaranteed; no system provisioning changes |
| Process | Checks an exact running PID, name and executable path | Requests a non-forced stop for one selected process | Unsaved work may be lost; process may restart |

**Inventory:**

```powershell
.\Cleanup.ps1 -Action Inventory
.\Cleanup.ps1 -Action Inventory -Json
```

**User TEMP:**

```powershell
.\Cleanup.ps1 -Action Plan -Target Temp -MinimumAgeDays 14
# Only after inspecting the plan:
.\Cleanup.ps1 -Action Apply -Target Temp -MinimumAgeDays 14 -Approve
```

**Optional built-in Appx app (only when present in the curated list):**

```powershell
.\Cleanup.ps1 -Action Plan -Target App -AppName Microsoft.BingWeather
# Uninstalls the app for the current user, not automatically reversible:
.\Cleanup.ps1 -Action Apply -Target App -AppName Microsoft.BingWeather -Approve
```

**One explicitly chosen background application process:**

```powershell
.\Cleanup.ps1 -Action Inventory
.\Cleanup.ps1 -Action Plan -Target Process -ProcessId 1234 -ProcessName Discord
# Only if you have saved your work and verified the PID:
.\Cleanup.ps1 -Action Apply -Target Process -ProcessId 1234 -ProcessName Discord -Approve
```

Kermit **does not** uninstall arbitrary software, remove provisioned packages or Windows components, perform a recursive disk clean, bulk-stop tasks, disable services, modify Defender, or disable Windows Update. The initial process shortlist is in `Cleanup/catalog.json` and **inclusion is not a recommendation to stop that program**. Reopening apps or restarting Windows may restart their processes.

**Important:** `-Approve` is explicit consent to the named action, not a promise of a backup. Deleting temp files and uninstalling apps do not have a guaranteed restore path. Back up important data and start with inventory/plan.

## What works today

- **Read-only Windows audit**: OS/build, CPU, RAM, system drive, display adapters, startup entry count, security status, and power schemes.
- **AI environment discovery**: checks for Python, Git, WSL, Docker, winget, NVIDIA tooling, and available NVIDIA GPU memory/utilization from `nvidia-smi`.
- **Five profiles**: `Balanced`, `AI-Training`, `AI-Inference`, `Gaming`, and `Development`.
- **Dry-run first**: `Plan` shows exactly what would change; `Scan` and `Plan` never change system settings.
- **Explicit opt-in**: `Apply` requires `-Approve`. The MVP can **only switch to an already available Windows power scheme**, and only when one is different from the active scheme.
- **Restore**: snapshots record the previous power scheme in `%LOCALAPPDATA%\Kermit\Snapshots`; you can restore it later with explicit approval.
- **Optional cleanup script**: inventories candidate Appx applications, high-memory processes and aged user Temp files; explicit per-item actions with a preview (see above).
- **JSON reports**: for automation, comparisons, and future desktop UI integrations.
- **No silent debloat**: no default removal of apps, disabling startup items, registry "hacks", services, Defender, Windows Update, or VBS/Hyper-V.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7+
- For NVIDIA GPU metrics, an installed compatible NVIDIA driver providing `nvidia-smi`
- Administrator permissions **may be needed** for some Windows power-plan configurations. `Scan` and `Plan` should generally work without elevation.

## Quick start

Download or clone the repository, review the source, then run commands from its root:

```powershell
git clone https://github.com/edujbarrios/Kermit.git
cd Kermit

# Inspect your computer without changing anything
.\Kermit.ps1 -Action Scan

# Review proposed changes for training workloads
.\Kermit.ps1 -Action Plan -Profile AI-Training

# Return a machine-readable report
.\Kermit.ps1 -Action Scan -Json

# Save a JSON report in an existing directory
.\Kermit.ps1 -Action Scan -Json -OutputPath .\my-kermit-report.json
```

### Apply a profile (optional)

Run a plan first. **Only if you agree with it**, use:

```powershell
.\Kermit.ps1 -Action Plan -Profile AI-Training
.\Kermit.ps1 -Action Apply -Profile AI-Training -Approve
```

If your machine doesn't expose the Windows High Performance plan, Kermit will **not** create or force it: the plan will explain why it offers no change. Laptops can run hotter and use more battery in performance mode. Different machines and workloads may see no measurable benefit.

The `Apply` output shows the snapshot file path. Keep that path to restore:

```powershell
.\Kermit.ps1 -Action Restore -SnapshotPath 'C:\Users\YOU\AppData\Local\Kermit\Snapshots\YOUR-SNAPSHOT.json' -Approve
```

The `Balanced` profile selects the built-in Balanced scheme, where available; it is **not** a universal undo of unrelated Windows tweaks. `Restore` uses your actual recorded original value.

### Commands

| Action | Changes Windows? | Description |
| --- | --- | --- |
| `Scan` | No | Collect system and AI readiness diagnostics |
| `Plan` | No | Show possible power-scheme change and human guidance |
| `Apply -Approve` | Yes, narrowly | Activate a different, already-installed power scheme and save a snapshot |
| `Restore -Approve -SnapshotPath ...` | Yes, narrowly | Restore the recorded previous power scheme |

Use `-Json` for structured output. Use `-OutputPath` to save the same JSON to a file.

## Design principles

1. **Safety first** — no disabling Defender, Windows Update, security virtualization, or essential services for benchmark scores.
2. **Auditability** — human-readable PowerShell, declarative profile definitions in `Profiles/profiles.json`, and simple state snapshots.
3. **Reversibility** — every supported change should have a documented restoration path.
4. **Honest measurements** — lower idle RAM does not automatically translate to faster GPU-bound training.
5. **Hardware-aware changes** — do not assume all Windows editions, power schemes, or GPU drivers behave alike.
6. **No unattended remote execution** — clone/review local code instead of piping a web download directly into PowerShell.

## Architecture

```text
Kermit.ps1               # User-facing command line
src/Kermit.Core.psm1      # Read-only audit, planning, apply and restore
Cleanup.ps1               # Separate opt-in cleaning command
src/Kermit.Cleanup.psm1   # Narrow temp / optional Appx / process operations
Cleanup/catalog.json      # Curated optional apps and process allowlist
Profiles/profiles.json    # Declarative presets, no executable snippets
tests/Smoke.Tests.ps1     # Safe planner tests with synthetic inventory
tests/Cleanup.Tests.ps1   # Isolated test TEMP; never removes real apps/processes
.github/workflows/        # PowerShell syntax and read-only smoke CI
```

The module deliberately separates inventory from planning and mutations. Profile JSON files specify **known Windows power scheme GUIDs**, not arbitrary shell commands.

## Security and privacy

Kermit runs locally. It does **not** transmit analytics or inventory to a server. When you choose `-Json` or `-OutputPath`, the report may include your computer name, installed device information, and startup entry metadata; treat reports as potentially sensitive and review before sharing.

Snapshot files are stored in your Windows user profile, not in the Git repository. They contain the previous and new power scheme GUID, profile, and timestamp. Keep them until you no longer need restoration.

`Get-MpComputerStatus` being unavailable does not mean that a PC is unprotected; third-party endpoint protection may be installed. Kermit doesn't disable security tools.

## Roadmap

- [x] Windows hardware and software inventory
- [x] Dry-run planning and JSON output
- [x] Narrow, reversible power-profile action
- [x] Read-only CLI tests and Windows CI workflow
- [ ] GUI with grouped, explainable recommendations
- [ ] Version/compatibility diagnostics for CUDA, PyTorch, WSL2, and installed Python environments
- [x] Read-only optional Appx/process inventory and curated, opt-in single-item actions
- [x] User-scoped, top-level aged temp cleaning with dry-run and isolated tests
- [ ] Restore-friendly uninstall workflow and optional startup-item management
- [ ] Benchmark captures before and after changes (e.g., idle RAM and workload-specific inference speed)
- [ ] Signed releases and reproducible packaging

## Contributing

Bug reports and small PRs are welcome. For a new optimization, include: supported Windows versions, why it helps, evidence/measurements, possible side effects, an explicit opt-in mechanism, and a verified rollback path. **Do not submit blanket Defender/Update disabling or hidden destructive tweaks.**

*A license has not yet been selected by the maintainer. Until a license is added, do not assume permission to redistribute derivative versions.*
