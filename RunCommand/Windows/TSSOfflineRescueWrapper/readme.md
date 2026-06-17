# TSS Offline Log Collector

PowerShell script for rescue-VM scenarios that collects Windows troubleshooting logs from an offline (broken) VM OS disk attached to a working rescue VM.

## Design

**Pure offline static file collection** — this script collects diagnostic files from the attached broken disk only. It does NOT run TSS.ps1 or execute any live diagnostics. This is intentional: TSS.ps1 requires a running OS and cannot operate on offline disks.

## What It Collects

**Comprehensive offline diagnostic collection** (aligned with TSS.ps1 DND_SetupReport / SDP Setup):

- **Event logs** — All event logs from `winevt\Logs`
- **Windows Update & Servicing** — CBS, DISM, WindowsUpdate ETL trace files (Windows 10+) and WindowsUpdate.log (legacy OS), SoftwareDistribution, WinSxS pending/servicing, USO logs
  - *Note: On Windows 10+, use `Get-WindowsUpdateLog` on a running system to generate human-readable log from collected ETL files*
- **Setup & Upgrade** — Panther logs (Windows, $Windows.~BT, Sysprep), Modern Setup (MoSetup)
- **Drivers** — Complete INF folder (setupapi logs), DriverStore repository, DPX device setup logs
- **Certificates** — catroot2 certificate catalog
- **Error Reporting** — Windows Error Reporting (WER) logs and reports
- **Crash Analysis** — Minidumps, LiveKernelReports, optionally MEMORY.DMP with `-IncludeMemoryDump`
- **System Diagnostics** — System32\LogFiles, WinSAT performance, Windows Temp
- **Activation & Licensing** — Software Protection Platform (SPP) store
- **Security** — Windows Defender logs (if present), Firewall logs
- **Task Scheduler** — Scheduled tasks configuration and logs
- **Registry hives** (always collected):
  - Safe diagnostic hives: SYSTEM, SOFTWARE, COMPONENTS
  - Credential-bearing hives with explicit consent (`-IncludeCredentialHives`): SAM, SECURITY, DEFAULT

## Output

- **Chain-of-custody manifest** (`manifest.json`) — lists all collected/skipped files with size and SHA-256 hash
- **Self-transcript** (`wrapper-transcript.log`) — complete log of the wrapper's execution
- Optional zip bundle (`-ZipOutput`)

## Prerequisites

- PowerShell 5.1 or higher
- **Run from an elevated (Run as administrator) PowerShell console**
- The broken VM OS disk must already be attached to the rescue VM

## Usage

From an elevated PowerShell console:

```powershell
Set-ExecutionPolicy Bypass -Force
```

### Basic collection (disk 2 has the offline OS)
```powershell
.\tssofflinelogcollector.ps1 -Disk 2 -ZipOutput
```

### With MEMORY.DMP (if crash analysis is required)
```powershell
.\tssofflinelogcollector.ps1 -Disk 2 -IncludeMemoryDump -ZipOutput
```

### ⚠️ With credential-bearing registry hives (use with caution)
```powershell
# Only use when explicitly required for troubleshooting
.\tssofflinelogcollector.ps1 -Disk 2 -IncludeCredentialHives -ZipOutput
```

### Custom output path
```powershell
.\tssofflinelogcollector.ps1 -Disk 2 -OutputPath "D:\DiagnosticCollections" -ZipOutput
```

### Dry-run preview (no actual copy)
```powershell
.\tssofflinelogcollector.ps1 -Disk 2 -WhatIf
```

## Parameters

- `-OfflineWindowsRoot <path>`: Offline Windows directory (example `F:\Windows`).
- `-Disk <number|drive>`: Disk selector, supports disk number (`2`) or drive (`E`, `E:`, `E:\`).
- `-OutputPath <path>`: Override default output root (`C:\MS_DATA\TSS_PERF_OFFLINE`).
- `-IncludeCredentialHives`: **⚠️ SECURITY SENSITIVE** — Include credential-bearing hives (SAM, SECURITY, DEFAULT) in addition to the always-collected safe hives (SYSTEM, SOFTWARE, COMPONENTS). These hives contain password hashes, LSA secrets, and DPAPI material. Only use when explicitly required for troubleshooting.
- `-IncludeMemoryDump`: **⚠️ LARGE + SENSITIVE** — Include MEMORY.DMP (may be several GB and contain in-memory secrets). Only use when explicitly required for crash analysis.
- `-ZipOutput`: Create zip after collection.
- `-Force`: Allow overwrite when output folder already exists.
- `-WhatIf`: Preview what would be collected without actually copying files.

## Output

- **Default root**: `C:\MS_DATA\TSS_PERF_OFFLINE` (override with `-OutputPath`)
- **Run folder**: `offline-tss-wrapper-<timestamp>`
- **Manifest**: `manifest.json` (lists all collected/skipped files with size and SHA-256)
- **Transcript**: `wrapper-transcript.log` (complete execution log)
- **Optional zip**: `offline-tss-wrapper-<timestamp>.zip` (with `-ZipOutput`)

## Notes

- This wrapper collects **static files only** from the offline disk. It does not run TSS.ps1 or any live diagnostics.
- **Comprehensive collection** — collects all diagnostic files TSS.ps1 DND_SetupReport/SDP Setup would gather (event logs, servicing logs, driver store, WER, etc.)
- **Collection size** — expect several hundred MB to several GB depending on system state (more if DriverStore/WER contain many files). Use `-WhatIf` to preview before collecting.
- **Registry hives are always collected** (SYSTEM, SOFTWARE, COMPONENTS) — these are essential for proper troubleshooting.
- MEMORY.DMP is opt-in (`-IncludeMemoryDump`) because it can be several GB and may contain in-memory secrets.
- Credential-bearing registry hives (SAM/SECURITY/DEFAULT) require explicit consent (`-IncludeCredentialHives`) to prevent accidental exposure of password hashes and LSA secrets.
- Use `-WhatIf` to preview what would be collected without actually copying files.
- The manifest (`manifest.json`) provides chain-of-custody documentation for all collected artifacts with SHA-256 hashes.

## Known Issues

None currently.

## Liability

As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

We value your input. If you encounter problems with the scripts or have ideas on how they can be improved, please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.
