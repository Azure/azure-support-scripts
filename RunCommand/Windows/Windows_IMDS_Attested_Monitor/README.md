# Azure VM IMDS Attested Data Access Monitor

This PowerShell script monitors which processes on an Azure VM are accessing the Instance Metadata Service (IMDS) attested data endpoint (`http://169.254.169.254/metadata/attested`). It runs for a configurable time window (default 30 minutes), captures all processes making connections to 169.254.169.254, and reports the process name, PID, path, and command line.

## Features

- Monitors all connections to the IMDS endpoint (169.254.169.254) over a configurable time window
- Uses three detection methods for maximum coverage:
  - **TCP Connection Polling** – polls active TCP connections every 5 seconds
  - **WFP Audit Events** – leverages Windows Filtering Platform audit logs (Security Event ID 5156) for process-to-connection correlation
  - **HTTP ETW Tracing** – checks WebIO diagnostic events for HTTP-level attested endpoint access
- Captures an ETW network trace (netsh trace) filtered to IMDS IP for offline analysis
- Reports process name, PID, executable path, and command line for each detected process
- Exports full results to CSV
- Provides a summary of unique processes and hit counts at completion

## Prerequisites

- PowerShell 5.1 or later
- Must be run as **Administrator** (required for ETW tracing and audit policy)
- Must be executed within an Azure VM (accesses the IMDS endpoint at 169.254.169.254)

## Usage

### Option 1 – Azure Run Command (Portal)

1. Navigate to the Azure Portal → Virtual Machine → **Operations** → **Run Command** → **RunPowerShellScript**
2. Paste the contents of `Windows_IMDS_Attested_Monitor.ps1`
3. Execute

> **Note:** Run Command has a default timeout. For 30-minute monitoring, consider running directly on the VM instead.

### Option 2 – Directly on the VM

```powershell
# Default 30-minute monitoring window
Set-ExecutionPolicy Bypass -Force
.\Windows_IMDS_Attested_Monitor.ps1

# Custom duration (e.g., 60 minutes)
.\Windows_IMDS_Attested_Monitor.ps1 -MonitorMinutes 60
```

## Output

The script produces:

1. **Console output** – real-time detection alerts as processes are caught accessing IMDS
2. **CSV file** – full results exported to `%TEMP%\IMDS_Attested_Monitor_<timestamp>.csv`
3. **ETL trace** – network trace file at `%TEMP%\IMDSAttestedMonitor.etl` (can be converted with `netsh trace convert`)

### Sample Output

```
[14:32:15] DETECTED - PID: 4832 | Process: python | State: Established | Port: 49721->80
           Path: C:\Python39\python.exe
           CmdLine: python.exe fetch_attested.py

[14:45:02] DETECTED (WFP) - PID: 1284 | Process: WaAppAgent | Path: \device\harddiskvolume2\windowsazure\packages\...
```

### Results Summary

```
Unique Processes Detected Accessing IMDS (169.254.169.254):
---------------------------------------------------------
  Process     : python
  PID(s)      : 4832
  Hit Count   : 3
  Path        : C:\Python39\python.exe
  First Seen  : 2026-02-13 14:32:15
  Last Seen   : 2026-02-13 14:45:02
```

## How It Works

1. **ETW Trace** – starts a `netsh trace` session filtered to 169.254.169.254 for packet-level capture
2. **Audit Policy** – temporarily enables WFP connection auditing to generate Security Event 5156 entries that include the owning process
3. **Polling Loop** – every 5 seconds, checks `Get-NetTCPConnection` for active connections to IMDS; every 50 seconds checks WFP audit events; every 150 seconds checks HTTP ETW events
4. **Cleanup** – stops the trace, restores audit policy, and outputs results

## References

- [Azure Instance Metadata Service](https://learn.microsoft.com/azure/virtual-machines/windows/instance-metadata-service)
- [IMDS Attested Data](https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service?tabs=windows#attested-data)

## Liability

As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues

- Azure Run Command has a default execution timeout that may be shorter than the monitoring window. For long monitoring sessions, run directly on the VM.
- Very short-lived connections (sub-second) may be missed by TCP polling but should be captured by WFP audit events or the ETW trace.
- WFP audit events require the Security event log to have sufficient capacity.
