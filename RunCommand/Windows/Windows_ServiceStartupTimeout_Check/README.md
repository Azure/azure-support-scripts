# Windows Service Startup Timeout Check

> **Tool ID:** RC-042 · **Bucket:** Boot/Services · **Phase:** 2 (Deep diagnostic)

## What It Does

Detects service startup timeout issues that cause slow boot or service failures. Checks the ServicesPipeTimeout registry value, identifies auto-start services that failed, counts Service Control Manager errors, detects Event ID 7011 (service timeout) events, and validates critical services are running. Important for VMs that boot slowly or have services stuck in "Starting" state.

| Check area | What is validated |
|---|---|
| ServicesPipeTimeout | Registry timeout value for service startup |
| Failed auto-start | Auto-start services that failed to start |
| SCM errors | Service Control Manager error events (7 days) |
| Timeout events | Event ID 7011 (service timeout) count |
| Critical services | Essential services running |

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
  --scripts @Windows_ServiceStartupTimeout_Check/Windows_ServiceStartupTimeout_Check.ps1
```

### Mock test
```powershell
.\Windows_ServiceStartupTimeout_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Service Startup Timeout Check ===
Check                                        Status
-------------------------------------------- ------
ServicesPipeTimeout value                    WARN
Auto-start services failed                   FAIL
Service Control Manager errors (7d)          FAIL
Service timeout events (7011)                FAIL
Critical services running                    FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 4 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **ServicesPipeTimeout value** WARN | Default timeout (30 sec) may be insufficient for heavy VMs with many services. Value is 0 or not set. | Increase: `Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control" -Name ServicesPipeTimeout -Value 120000 -Type DWord` (120 sec in ms) then reboot | [Slow VM start troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/slow-vm-start-extensions-troubleshooting) |
| **Auto-start services failed** FAIL | One or more Automatic services didn't start. May indicate dependency failures, corrupted binaries, or permission issues. | `Get-Service \| Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }` to identify. Fix dependencies or reinstall service. | [Troubleshoot service startup](https://learn.microsoft.com/troubleshoot/windows-server/system-management-components/troubleshoot-service-startup) |
| **Service Control Manager errors (7d)** WARN | SCM logged errors (Event ID 7000-7009, 7023-7034). Indicates service start/stop failures. | `Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; Level=2; StartTime=(Get-Date).AddDays(-7)}` | [SCM error reference](https://learn.microsoft.com/troubleshoot/windows-server/system-management-components/troubleshoot-service-startup) |
| **Service timeout events (7011)** FAIL | Event ID 7011 — services exceeded the startup timeout. Common on VMs with slow storage or many services competing at boot. | Increase ServicesPipeTimeout (see above). Identify slow services from 7011 event details. Consider setting delayed start: `sc config <svc> start= delayed-auto` | [Slow boot troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/slow-vm-start-extensions-troubleshooting) |
| **Critical services running** FAIL | One or more critical services (RpcSs, Netlogon, W32Time, LanmanServer, etc.) not running. May cascade into other failures. | `Get-Service RpcSs,Netlogon,W32Time,LanmanWorkstation -ErrorAction SilentlyContinue \| Format-Table Name,Status`. Start stopped services. | [Understand VM reboot](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/understand-vm-reboot) |

## Related Articles

| Article | Link |
|---|---|
| Slow VM start and extension troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/slow-vm-start-extensions-troubleshooting) |
| Troubleshoot service startup | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/system-management-components/troubleshoot-service-startup) |
| Understand Azure VM reboot | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/understand-vm-reboot) |
