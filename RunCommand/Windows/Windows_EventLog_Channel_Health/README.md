# Windows EventLog Channel Health

> **Tool ID:** RC-020 · **Bucket:** Monitoring · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates Windows Event Log channel health and accessibility. Checks that the EventLog service is running, core log channels (System, Application, Security) are readable, and the System event error volume is within normal thresholds. Critical for VMs where diagnostic data collection fails or event logs appear empty.

| Check area | What is validated |
|---|---|
| EventLog service | Windows Event Log service running |
| System channel | System event log readable |
| Application channel | Application event log readable |
| Security channel | Security event log readable |
| Error volume | System error events in last 4 hours below threshold |

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
  --scripts @Windows_EventLog_Channel_Health/Windows_EventLog_Channel_Health.ps1
```

### Mock test
```powershell
.\Windows_EventLog_Channel_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows EventLog Channel Health ===
Check                                        Status
-------------------------------------------- ------
EventLog service running                     FAIL
System channel readable                      FAIL
Application channel readable                 FAIL
Security channel readable                    WARN
System errors in last 4h below threshold     WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 3 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **EventLog service running** FAIL | EventLog service stopped or crashed. No events can be written or read. Diagnostic data collection fails. | `Start-Service EventLog` — this is a critical system service. If it fails to start, check for disk space issues or corrupted log files. | [IaaS diagnostic logs](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/iaas-logs) |
| **System channel readable** FAIL | System event log inaccessible. May be corrupted, at max size, or permissions changed. | `wevtutil cl System` to clear (after backup). Recreate: `wevtutil sl System /ms:20971520` (set max size). Check `C:\Windows\System32\winevt\Logs\System.evtx` permissions. | [Event log troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/iaas-logs) |
| **Application channel readable** FAIL | Application log inaccessible. Application-level diagnostics unavailable. | Same approach as System: `wevtutil cl Application` (after backup). Check file permissions and disk space. | [Azure VM IaaS logs](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/iaas-logs) |
| **Security channel readable** WARN | Security log inaccessible. May require elevated permissions or audit policy changes. Non-critical for basic diagnostics. | `wevtutil gl Security` to check config. May need `SeSecurityPrivilege`. Generally informational unless security auditing is required. | [Event ID troubleshoot VM RDP](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/event-id-troubleshoot-vm-rdp-connecton) |
| **System errors in last 4h below threshold** WARN | High error rate (>200 errors in 4 hours) in System log. May indicate a cascading failure or noisy service. | `Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=(Get-Date).AddHours(-4)} \| Group-Object ProviderName \| Sort-Object Count -Descending` to identify top error sources | [Event-based RDP troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/event-id-troubleshoot-vm-rdp-connecton) |

## Related Articles

| Article | Link |
|---|---|
| Azure VM IaaS diagnostic logs | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/iaas-logs) |
| Event ID-based RDP troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/event-id-troubleshoot-vm-rdp-connecton) |
-------------------------------------------- ------
EventLog service running                     FAIL
System channel readable                      FAIL
Application channel readable                 FAIL
Security channel readable                    WARN
System errors in last 4h below threshold     WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 3 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **EventLog service running** FAIL | EventLog service stopped or crashed. No events can be written or read. Diagnostic data collection fails. | `Start-Service EventLog` — this is a critical system service. If it fails to start, check for disk space issues or corrupted log files. | [IaaS diagnostic logs](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/iaas-logs) |
| **System channel readable** FAIL | System event log inaccessible. May be corrupted, at max size, or permissions changed. | `wevtutil cl System` to clear (after backup). Recreate: `wevtutil sl System /ms:20971520` (set max size). Check `C:\Windows\System32\winevt\Logs\System.evtx` permissions. | [Event log troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/iaas-logs) |
| **Application channel readable** FAIL | Application log inaccessible. Application-level diagnostics unavailable. | Same approach as System: `wevtutil cl Application` (after backup). Check file permissions and disk space. | [Azure VM IaaS logs](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/iaas-logs) |
| **Security channel readable** WARN | Security log inaccessible. May require elevated permissions or audit policy changes. Non-critical for basic diagnostics. | `wevtutil gl Security` to check config. May need `SeSecurityPrivilege`. Generally informational unless security auditing is required. | [Event ID troubleshoot VM RDP](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/event-id-troubleshoot-vm-rdp-connecton) |
| **System errors in last 4h below threshold** WARN | High error rate (>200 errors in 4 hours) in System log. May indicate a cascading failure or noisy service. | `Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=(Get-Date).AddHours(-4)} \| Group-Object ProviderName \| Sort-Object Count -Descending` to identify top error sources | [Event-based RDP troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/event-id-troubleshoot-vm-rdp-connecton) |

## Related Articles

| Article | Link |
|---|---|
| Azure VM IaaS diagnostic logs | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/iaas-logs) |
| Event ID-based RDP troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/event-id-troubleshoot-vm-rdp-connecton) |
