# TSS Offline Rescue Wrapper

## Overview
This script is for rescue-VM scenarios where the broken VM OS disk is attached offline:
- Copies offline Windows troubleshooting artifacts from the attached disk.
- Always runs TSS on the rescue VM context.
- Uses default TSS mode `-SDP Setup` when no explicit TSS arguments are provided.
- Supports explicit `-TssCollectLog` or full pass-through `-TssArguments`.
- Uses fixed output root `C:\MS_DATA\TSS_PERF_OFFLINE`.

## File
- `Invoke-TSSOfflineRescueWrapper.ps1`

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

## Examples

### Default run (uses `-SDP Setup`)
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -ZipOutput
```

### DND setup report
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -TssCollectLog DND_SetupReport -ZipOutput
```

### TSS UEX example
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -TssArguments @('-UEX_RDSsrv') -ZipOutput
```

### Directory Services (DS) example
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -TssArguments @('-SDP','Dom') -ZipOutput
```

### Use disk number auto-detection
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -TssCollectLog DND_SetupReport -ZipOutput
```

### Use wrapper-local default TSS path
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -ZipOutput
```

### Custom TSS switches
```powershell
.\Invoke-TSSOfflineRescueWrapper.ps1 -Disk 2 -TssPath C:\Tools\TSS\TSS.ps1 -TssArguments @('-SDP','Setup') -ZipOutput
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
- The script no longer uses `-RunTssOnRescueVm`.
- The script no longer uses `-OutputRoot`.
- If neither `-TssArguments` nor `-TssCollectLog` is provided, wrapper defaults to `-SDP Setup`.
- Note: `-SDP Perf` is deprecated in current TSS; use `-SDP Setup`.
- DS (Directory Services) SDP key is `Dom` in TSS (`-SDP Dom`).
- Use elevated PowerShell on the rescue VM.
