# Windows ReliabilityMonitor Event Signal

> **Tool ID:** RC-038 · **Bucket:** Reliability · **Phase:** 2 (Deep diagnostic)

## What It Does

Scans Windows event logs for reliability signals that indicate system instability. Counts application failures (crashes), application hangs, system BSODs, service terminations, disk errors, and unexpected shutdowns over recent time windows. Provides a quick health snapshot similar to the Windows Reliability Monitor but remotely accessible via Run Command.

## Threshold Logic (from script)

Use this table to interpret status transitions exactly as the script calculates them.

| Check | Data source | Window | OK | WARN | FAIL |
|---|---|---|---|---|---|
| Application failures | Application log, Event ID 1000 | 7 days | 0 events | 1-5 events | >5 events |
| Application hangs | Application log, Event ID 1002 | 7 days | 0 events | 1-3 events | >3 events |
| Windows failures/BSODs | System log, Event ID 1001, provider `Microsoft-Windows-WER-SystemErrorReporting` | 30 days | 0 events | 1-2 events | >2 events |
| Service terminations | System log, Event ID 7034 | 7 days | 0 events | 1-5 events | >5 events |
| Disk errors | System log, Event IDs 7/11/51 | 7 days | 0 events | 1-3 events | >3 events |
| Unexpected shutdowns | System log, Event ID 6008 | 14 days | 0 events | 1-2 events | >2 events |

## Engineer Investigation Flow

1. Treat any `FAIL` row as priority one and resolve in this order: disk errors -> BSODs -> unexpected shutdowns -> service terminations -> app failures/hangs.
2. Confirm time correlation first. Pull all implicated events with timestamps and align to Azure Activity Log operations.
3. If both disk and crash signals fail, capture crash artifacts before reboot/redeploy actions.
4. If only app-level signals fail, triage by top crashing process names and recency, then isolate infra versus workload fault domain.
5. Re-run this script after each fix batch and compare result trend, not only single-run status.

### Correlation commands

```powershell
# Event timelines by probe family
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=(Get-Date).AddDays(-7)}
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1002; StartTime=(Get-Date).AddDays(-7)}
Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=(Get-Date).AddDays(-30)}
Get-WinEvent -FilterHashtable @{LogName='System'; Id=7034; StartTime=(Get-Date).AddDays(-7)}
Get-WinEvent -FilterHashtable @{LogName='System'; Id=7,11,51; StartTime=(Get-Date).AddDays(-7)}
Get-WinEvent -FilterHashtable @{LogName='System'; Id=6008; StartTime=(Get-Date).AddDays(-14)}
```

| Check area | What is validated |
|---|---|
| App failures | Application crash events (7 days) |
| App hangs | Application hang/not responding events (7 days) |
| System crashes | Windows failures / BSODs (30 days) |
| Service terminations | Unexpected service termination events (7 days) |
| Disk errors | Disk read/write error events (7 days) |
| Unexpected shutdowns | Unclean shutdown events (14 days) |

## Run Command Constraints Met

- ✅ PowerShell 5.1 only
- ✅ No Az module required
- ✅ No internet access needed
- ✅ Output < 4 KB
- ✅ No interactive prompts
- ✅ Read-only (diagnostic only)

## How to Run

### Azure Run Command (recommended)
Navigate to VM → Operations → Run Command → RunPowerShellScript → paste script.

### Azure CLI
```bash
az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript \
  --scripts @Windows_ReliabilityMonitor_Event_Signal/Windows_ReliabilityMonitor_Event_Signal.ps1
```

### Mock test
```powershell
.\Windows_ReliabilityMonitor_Event_Signal.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows ReliabilityMonitor Event Signal ===
Check                                        Status
-------------------------------------------- ------
Application failures (7d)                    FAIL
Application hangs (7d)                       WARN
Windows failures/BSODs (30d)                 FAIL
Service termination events (7d)              WARN
Disk errors (7d)                             FAIL
Unexpected shutdown events (14d)             FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 4 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Application failures (7d)** FAIL | Frequent application crashes detected. May indicate incompatible software, missing dependencies, or memory corruption. | `Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=(Get-Date).AddDays(-7)}` to identify crashing apps. Update or reinstall offending application. | [Troubleshoot app connection issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-app-connection) |
| **Application hangs (7d)** WARN | Applications freezing (Event ID 1002). May indicate resource contention (CPU, memory, disk) or deadlocks. | Check concurrent resource usage. `Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1002; StartTime=(Get-Date).AddDays(-7)}` to identify hanging processes. | [Troubleshoot high CPU issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-high-cpu-issues-azure-windows-vm) |
| **Windows failures/BSODs (30d)** FAIL | System-level blue-screen crashes. Correlate with Windows_CrashHistory_Bugcheck_Summary for dump analysis and bugcheck codes. | Collect MEMORY.DMP for analysis. Check Event ID 1001 (BugCheck). Run `Windows_CrashHistory_Bugcheck_Summary` for detailed crash data. | [Troubleshoot common blue-screen errors](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-common-blue-screen-error) |
| **Service termination events (7d)** WARN | Services terminated unexpectedly (Event ID 7034). May indicate service crashes, dependency failures, or forced kills. | `Get-WinEvent -FilterHashtable @{LogName='System'; Id=7034; StartTime=(Get-Date).AddDays(-7)}` to identify failing services. Check service dependencies. | [Understand VM reboot](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/understand-vm-reboot) |
| **Disk errors (7d)** FAIL | Disk hardware or logical errors detected. May indicate failing disk (rare on Azure managed disks) or file system corruption. | Run `chkdsk C: /scan` (online check). Review Event ID 7, 51, 52 in System log. For persistent errors, consider VM redeployment. | [Troubleshoot data disk issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-data-disk-caching) |
| **Unexpected shutdown events (14d)** FAIL | Event ID 6008 (unexpected shutdown) — VM lost power without clean shutdown. May be Azure host maintenance, crash, or forced reboot. | Cross-reference with Azure Activity Log: Portal → VM → Activity Log. Check for `Microsoft.Compute/virtualMachines/restart` events. | [Unexpected VM reboot root cause analysis](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/unexpected-vm-reboot-root-cause-analysis) |

## Related Articles

| Article | Link |
|---|---|
| Understand Azure VM reboot | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/understand-vm-reboot) |
| Unexpected VM reboot root cause analysis | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/unexpected-vm-reboot-root-cause-analysis) |
| Troubleshoot common blue-screen errors | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-common-blue-screen-error) |

## Internal handoff notes

- Include probe counts from `Detail` in case notes (`AppCrashes`, `AppHangs`, `SystemCrashes`, `SvcTerminations`, `DiskErrors`, `UnexpectedShutdowns`).
- Capture whether failures are bursty (single date cluster) or persistent (multi-day spread).
- When escalation is needed, provide top 3 event IDs by frequency and first/last seen timestamps.
