# Windows Service Dependency Analyzer

Analyzes Windows service dependency chains, startup type mismatches, and volatile temp-drive path references on Azure VMs. Designed to run via **Run Command** or locally with mock data for testing.

## What It Does

| Section                        | Checks                                                                                      |
|--------------------------------|---------------------------------------------------------------------------------------------|
| **Dependency Chain Analysis**  | Maps `DependOnService` chains; detects circular dependencies; flags chains deeper than 4 levels; finds services depending on Disabled/Manual services |
| **Startup Type Mismatches**    | Automatic services that are Stopped (non-trigger-started); Disabled services with Automatic dependents; failed services (non-zero exit code) |
| **Volatile Temp Drive Paths**  | Scans `ImagePath` and registry `Parameters` for references to the Azure temp drive (default `D:\`) — data on this drive is lost on redeployment/resize |

## Why This Matters

Windows VM Admin support cases frequently involve:
- **Failover Cluster issues** caused by circular or broken service dependency chains
- **Boot-time failures** from services depending on a Disabled prerequisite
- **Data loss after redeployment** when SQL Server, custom agents, or other software is installed on the volatile temp drive

This script identifies all three categories in a single pass.

## Prerequisites

- PowerShell 5.1 or higher
- Administrator privileges (when running live on an Azure VM)

## Usage

### Via Azure Run Command

1. Open the Azure Portal and navigate to the VM.
2. Go to **Operations** > **Run command** > **RunPowerShellScript**.
3. Paste the contents of `Windows_Service_Dependency_Analyzer.ps1`.
4. Click **Run**.

> **Note:** Run Command output is limited to 4 KB. The script's table format is optimized to stay within this limit.

### Manual Download and Run

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_Service_Dependency_Analyzer.ps1
```

### Parameters

| Parameter          | Type   | Default | Description                                                                 |
|--------------------|--------|---------|-----------------------------------------------------------------------------|
| `-TempDriveLetter` | String | `D`     | Azure temporary disk letter. Some VM sizes use `E` or another letter.       |
| `-MaxDepth`        | Int    | `4`     | Maximum dependency chain depth before flagging as a deep chain.             |
| `-IncludeHealthy`  | Switch | Off     | Also lists services that passed all checks (verbose output).                |
| `-MockConfig`      | String | —       | Path to a JSON file with mock service data for local testing.               |

### Examples

```powershell
# Default — scan all services for issues
.\Windows_Service_Dependency_Analyzer.ps1

# Temp drive is E: on this VM size, show healthy services too
.\Windows_Service_Dependency_Analyzer.ps1 -TempDriveLetter E -IncludeHealthy

# Local testing with mock data (no admin needed)
.\Windows_Service_Dependency_Analyzer.ps1 -MockConfig .\mock_config_sample.json
```

## Local Testing with Mock Data

The script includes a built-in mock mode for local testing without admin privileges or an Azure VM.

### Setup

1. The mock config file `mock_config_sample.json` is included in this folder.
2. Run the script with the `-MockConfig` parameter:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Windows_Service_Dependency_Analyzer.ps1 -MockConfig .\mock_config_sample.json
```

### Mock Config Schema

The `mock_config_sample.json` file provides a `Services` array. Each service object has:

| Key                 | Type     | Description                                                          |
|---------------------|----------|----------------------------------------------------------------------|
| `Name`              | string   | Service short name (e.g., `"RpcSs"`)                                |
| `DisplayName`       | string   | Human-readable service name                                          |
| `Status`            | string   | `"Running"`, `"Stopped"`, `"Paused"`, etc.                          |
| `StartType`         | string   | `"Automatic"`, `"Manual"`, `"Disabled"`                              |
| `DependOnService`   | string[] | Array of service names this service depends on                       |
| `DependentServices` | string[] | Array of service names that depend on this service                   |
| `ImagePath`         | string   | Full path to the service binary (from `Win32_Service.PathName`)      |
| `ExitCode`          | int      | Service exit code (`0` = normal, non-zero = error)                   |
| `DelayedAutoStart`  | bool     | Whether the service uses delayed auto-start                          |
| `IsTriggerStart`    | bool     | Whether the service is trigger-started (legitimately Stopped+Auto)   |

### What the Mock Config Covers

The included `mock_config_sample.json` exercises every check category:

| Scenario                     | Services                                     | Expected Findings                    |
|------------------------------|----------------------------------------------|--------------------------------------|
| Circular dependency          | `SvcAlpha` → `SvcBeta` → `SvcGamma` → ring  | 3 CRITICAL (circular chain)          |
| Deep chain (depth 6)         | `DeepLayer1` through `DeepLayer6`            | 1 WARNING (deep chain >4)            |
| Automatic + Stopped (failed) | `ContosoAgent` (ExitCode 1603)               | 1 CRITICAL (non-zero exit)           |
| Automatic + Stopped (clean)  | `WinDefend` (ExitCode 0, delayed)            | 1 WARNING (auto but stopped)         |
| Trigger-started (OK)         | `WbioSrvc` (trigger-start flag set)          | INFO only (expected behavior)        |
| Disabled with auto deps      | `LanmanWorkstation` → `Netlogon`, `Browser`  | 1 CRITICAL (disabled + auto deps)    |
| Auto depends on Disabled     | `Netlogon`, `Browser`                        | 2 CRITICAL (depends on Disabled svc) |
| Temp drive ImagePath         | `ContosoTempSvc`, `SQLAgent`, `MSSQLSERVER`  | 3 CRITICAL (D:\ references)          |
| Healthy services             | `RpcSs`, `Dnscache`, `NlaSvc`, etc.          | No findings (pass)                   |

### Validation

Run mock mode and verify the expected output:

```powershell
# Run with mock data
$findings = .\Windows_Service_Dependency_Analyzer.ps1 -MockConfig .\mock_config_sample.json

# Validate finding counts
$crit = ($findings | Where-Object Severity -eq 'CRITICAL').Count
$warn = ($findings | Where-Object Severity -eq 'WARNING').Count

Write-Host "CRITICAL: $crit (expected ~13)  WARNING: $warn (expected ~4)"
if ($crit -ge 10 -and $warn -ge 3) {
    Write-Host "PASS — Mock validation successful" -ForegroundColor Green
} else {
    Write-Host "FAIL — Unexpected finding counts" -ForegroundColor Red
}
```

## Sample Output (Run Command)

```
======================================================================
  Windows Service Dependency Analyzer
======================================================================
Temp drive: D:\    Max chain depth: 4
Timestamp: 2026-01-15 18:30:00 UTC
** MOCK MODE — using .\mock_config_sample.json **
Services loaded: 24

-- 1. Dependency Chain Analysis --
Service                                                 [Severity] Finding
------------------------------------------------------- ---------- ----------------------------------------
SvcAlpha                                                [CRITICAL] Circular dependency detected: SvcAlpha -> SvcBeta -> SvcGamma -> SvcAlpha
SvcBeta                                                 [CRITICAL] Circular dependency detected: SvcBeta -> SvcGamma -> SvcAlpha -> SvcBeta
SvcGamma                                                [CRITICAL] Circular dependency detected: SvcGamma -> SvcAlpha -> SvcBeta -> SvcGamma
DeepLayer1                                              [WARNING]  Deep chain (depth 6): DeepLayer1 -> DeepLayer2 -> DeepLayer3 -> DeepLayer4 -> DeepLayer5 -> DeepLayer6
Netlogon                                                [CRITICAL] StartType=Automatic but depends on 'LanmanWorkstation' which is Disabled
Browser                                                 [CRITICAL] StartType=Automatic but depends on 'LanmanWorkstation' which is Disabled

Chain summary: 3 circular, 1 deep (>4), 2 broken/mismatched

-- 2. Startup Type Mismatch Detection --
SvcAlpha                                                [CRITICAL] StartType=Automatic but Status=Stopped (ExitCode: 1067)
SvcBeta                                                 [CRITICAL] StartType=Automatic but Status=Stopped (ExitCode: 1067)
SvcGamma                                                [CRITICAL] StartType=Automatic but Status=Stopped (ExitCode: 1067)
ContosoAgent                                            [CRITICAL] StartType=Automatic but Status=Stopped (ExitCode: 1603)
WinDefend                                               [WARNING]  StartType=Automatic but Status=Stopped
Netlogon                                                [WARNING]  StartType=Automatic but Status=Stopped
Browser                                                 [WARNING]  StartType=Automatic but Status=Stopped
LanmanWorkstation                                       [CRITICAL] Disabled but has Automatic dependents: Netlogon, Browser

Mismatch summary: 7 auto+stopped, 1 disabled-with-auto-deps, 4 failed (non-zero exit)

-- 3. Volatile Temp Drive Path Detection --
ContosoTempSvc                                          [CRITICAL] ImagePath references temp drive (D:\): D:\ContosoApp\service.exe --config D:\ContosoApp\config.yaml
SQLAgent                                                [CRITICAL] ImagePath references temp drive (D:\): D:\MSSQL\Binn\SQLAGENT.EXE -i MSSQLSERVER
MSSQLSERVER                                             [CRITICAL] ImagePath references temp drive (D:\): D:\MSSQL\Binn\sqlservr.exe -sMSSQLSERVER

Volatile path hits: 3

======================================================================
  Summary Report
======================================================================
Total services scanned              24
CRITICAL findings                   13
WARNING findings                    4
INFO findings                       0
  Circular dependencies             3
  Deep chains (>depth)              1
  Broken/mismatched deps            2
  Automatic but Stopped             7
  Disabled with auto deps           1
  Failed (non-zero exit)            4
  Temp drive references             3

======================================================================
  Recommended Actions
======================================================================

  [TEMP DRIVE] 3 service(s) reference the Azure temp drive (D:\).
  This drive is wiped on VM resize, redeployment, or host maintenance.
  ACTION: Move service binaries and data to an OS disk or attached data disk.
  DOCS:   https://learn.microsoft.com/azure/virtual-machines/managed-disks-overview#temporary-disk

  [CIRCULAR] 3 circular dependency chain(s) detected.
  ACTION: Review the listed chains and remove or restructure dependencies.
  CMD:    sc.exe config <ServiceName> depend= <CorrectedList>

  [DEPENDENCY MISMATCH] 2 service(s) depend on Disabled/Manual services.
  ACTION: Either enable the dependency or change the dependent's StartType.

  [FAILED] 4 service(s) are Automatic but stopped with non-zero exit code.
  ACTION: Check Event Log and set recovery actions via sc.exe failure.

  [AUTO+STOPPED] 7 Automatic service(s) are not running.
  ACTION: Start them or change StartType to Manual/Disabled.
```

## Output Legend

| Status   | Color  | Meaning                                                   |
|----------|--------|-----------------------------------------------------------|
| CRITICAL | Red    | Service failure or broken dependency — action required     |
| WARNING  | Yellow | Mismatch likely to cause issues after reboot/redeploy     |
| INFO     | Gray   | Advisory observation (e.g., trigger-started service is OK) |
| OK       | Green  | Check passed                                              |

## Liability

As described in the [MIT license](../../../LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

If you encounter problems or have ideas for improvement, please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section.
