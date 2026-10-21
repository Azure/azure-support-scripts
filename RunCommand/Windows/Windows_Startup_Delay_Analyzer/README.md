# Windows Startup Delay Analyzer

> **Tool ID:** RC-044 · **Bucket:** Performance/Boot · **Phase:** 2 (Deep diagnostic)

## What It Does

Analyzes boot and logon timing to identify sources of startup delay. Checks last boot time, kernel+user initialization duration, logon delay events, auto-start program impact, Group Policy processing time, and pending reboot state. Essential for diagnosing VMs that take excessively long to become responsive after start/restart.

| Check area | What is validated |
|---|---|
| Boot time | Last boot time and current uptime |
| Boot duration | Kernel + user init time in seconds |
| Logon delays | Logon delay events in event log |
| Startup apps | Auto-start program count and delays |
| GP processing | Group Policy apply time in milliseconds |
| Pending reboot | Reboot pending from updates or config changes |

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
  --scripts @Windows_Startup_Delay_Analyzer/Windows_Startup_Delay_Analyzer.ps1
```

### Mock test
```powershell
.\Windows_Startup_Delay_Analyzer.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Startup Delay Analyzer ===
Check                                        Status
-------------------------------------------- ------
Last boot time                               OK
Boot duration (Kernel+User init)             FAIL
Logon delay events                           WARN
Auto-start program delays                    WARN
GroupPolicy processing time                  FAIL
Pending reboot state                         FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 1 OK / 3 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Boot duration (Kernel+User init)** FAIL | Boot takes excessively long (>120 sec). May indicate slow storage, too many services, or driver initialization delays. | Check Event ID 100/101 in `Microsoft-Windows-Diagnostics-Performance/Operational`. Identify slow drivers/services. Consider changing services to delayed-auto start. | [Slow VM start troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/slow-vm-start-extensions-troubleshooting) |
| **Logon delay events** WARN | Slow logon detected — profile load, network drive mapping, or login scripts taking too long. | Check Event ID 6005/6006 in `Microsoft-Windows-Diagnostics-Performance/Operational`. Review logon scripts and profile size. | [Troubleshoot Windows logon delay](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/slow-logon-with-user-profile) |
| **Auto-start program delays** WARN | Many startup programs competing for resources during boot. Each adds to total boot time. | `Get-CimInstance Win32_StartupCommand` to list. Disable non-essential: `Disable-ScheduledTask` or remove from `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` | [Performance tuning for startup](https://learn.microsoft.com/windows-server/administration/performance-tuning/) |
| **GroupPolicy processing time** FAIL | GP apply time is excessive (>30 sec). May indicate unreachable DC, large number of policies, or script-heavy GPOs. | `gpresult /h C:\temp\gpreport.html` for detailed report. Check DC connectivity. Remove unnecessary linked GPOs. | [Troubleshoot Group Policy processing](https://learn.microsoft.com/troubleshoot/windows-server/group-policy/applying-group-policy-troubleshooting-guidance) |
| **Pending reboot state** FAIL | Reboot pending — Component Based Servicing, Windows Update, or config change waiting for restart. VM may not apply updates until rebooted. | Check: `Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue`. Reboot to clear: `Restart-Computer` | [Understand VM reboot](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/understand-vm-reboot) |
| **Last boot time** WARN | Very long uptime (>90 days). Pending patches may not be applied, and resource leaks accumulate. Informational. | Consider scheduling a maintenance reboot if uptime is excessive and patches are pending. | [Azure VM maintenance overview](https://learn.microsoft.com/azure/virtual-machines/maintenance-and-updates) |

## Related Articles

| Article | Link |
|---|---|
| Slow VM start and extension troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/slow-vm-start-extensions-troubleshooting) |
| Troubleshoot Group Policy processing | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/group-policy/applying-group-policy-troubleshooting-guidance) |
| Understand Azure VM reboot | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/understand-vm-reboot) |
