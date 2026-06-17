# TSS Offline Log Collector

This PowerShell script is for rescue-VM scenarios where the broken VM OS disk is attached offline to a working rescue VM. It collects offline Windows troubleshooting logs from the attached disk and then runs TSS in the rescue VM context.

## What It Does

1. **Offline Log Collection**
   - Copies offline Windows troubleshooting logs from the attached disk (event logs, CBS, DISM, Panther, setupapi, Software Distribution, catroot2, USO logs, and optional registry hives).

2. **TSS Execution**
   - Always runs TSS on the rescue VM context.
   - Uses default TSS mode `-SDP Setup` when no explicit TSS arguments are provided.
   - Supports explicit `-TssCollectLog` or full pass-through `-TssArguments`.

3. **Output Packaging**
   - Writes to fixed output root `C:\MS_DATA\TSS_PERF_OFFLINE`.
   - Optionally creates a zip of the run folder.

## Prerequisites

- PowerShell 5.1 or higher.
- **Run from an elevated (Run as administrator) PowerShell console.**
- **Must run in the standard PowerShell console host (`ConsoleHost`), not PowerShell ISE.**
- The broken VM OS disk must already be attached to the rescue VM.

## TSS Folder Expectation (Default)

If `-TssPath` is not provided, the script expects:

```text
<wrapper-folder>\TSS\TSS.ps1
```

Example:

```text
RunCommand\Windows\TSSOfflineRescueWrapper\Invoke-TSSOfflineRescueWrapper.ps1
RunCommand\Windows\TSSOfflineRescueWrapper\TSS\TSS.ps1
```

If not present, the script prints screen guidance and stops.

Disk selection note: `-Disk 2` in examples is sample syntax. Replace `2` with the disk number that contains the offline OS.

## Usage

From an elevated PowerShell console, in the directory that contains the script:

```powershell
Set-ExecutionPolicy Bypass -Force
```

## Quick Start

### Default is Setup/Perf Report
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -ZipOutput
```

### DND setup report
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -TssCollectLog DND_SetupReport -ZipOutput
```

### UEX Report
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -TssArguments @('-UEX_RDSsrv') -ZipOutput
```

### Directory Services (DS) report
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -TssArguments @('-SDP','Dom') -ZipOutput
```

## Parameters

- `-OfflineWindowsRoot <path>`: Offline Windows directory (example `F:\Windows`).
- `-Disk <number|drive>`: Disk selector, supports disk number (`2`) or drive (`E`, `E:`, `E:\`).
- `-TssPath <path>`: Optional explicit path to `TSS.ps1`. If omitted, wrapper-local default is used.
- `-TssCollectLog <name>`: Optional override to run `-CollectLog <name>`.
- `-TssArguments <string[]>`: Any TSS args passed as-is.
- `-IncludeRegistryHives`: Include SYSTEM/SOFTWARE/SAM/SECURITY/DEFAULT/COMPONENTS hives.
- `-NoAcceptEula`: Prevent automatic `-AcceptEula` append.
- `-ZipOutput`: Create zip after collection.
- `-Force`: Allow overwrite when output folder already exists.

## Output

- Root: `C:\MS_DATA\TSS_PERF_OFFLINE`
- Run folder: `offline-tss-wrapper-<timestamp>`
- Optional zip: `offline-tss-wrapper-<timestamp>.zip`

## Notes

- If neither `-TssArguments` nor `-TssCollectLog` is provided, wrapper defaults to `-SDP Setup`.
- `-SDP Perf` is deprecated in current TSS; use `-SDP Setup`.
- DS (Directory Services) SDP key is `Dom` in TSS (`-SDP Dom`).

## Known Issues

- TSS SDP collection must run in the standard PowerShell console host. Running directly inside PowerShell ISE fails because the SDP module depends on console-host-only properties. Use a standard elevated PowerShell console, or invoke with `powershell -ExecutionPolicy Bypass -File <script>` which launches a fresh console host.

## Liability

As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

We value your input. If you encounter problems with the scripts or have ideas on how they can be improved, please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.
