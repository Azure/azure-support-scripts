# Windows EventForwarding WEF Health

> **Tool ID:** RC-021 · **Bucket:** Monitoring · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates the Windows Event Forwarding (WEF) infrastructure on an Azure VM. Checks that the Event Collector service is running, WinRM is active, subscriptions are configured, and the ForwardedEvents log channel exists with adequate sizing. Essential for VMs that should be collecting or forwarding events but logs appear empty.

| Check area | What is validated |
|---|---|
| Event Collector service | Windows Event Collector (Wecsvc) running |
| WinRM service | WinRM service active (required for event forwarding) |
| Subscriptions | Event forwarding subscriptions are configured |
| ForwardedEvents log | ForwardedEvents log channel exists and sized |
| WinRM listener | At least one WinRM listener configured |

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
  --scripts @Windows_EventForwarding_WEF_Health/Windows_EventForwarding_WEF_Health.ps1
```

### Mock test
```powershell
.\Windows_EventForwarding_WEF_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows EventForwarding WEF Health ===
Check                                        Status
-------------------------------------------- ------
Windows Event Collector service              FAIL
WinRM service running                        FAIL
Event subscriptions configured               FAIL
ForwardedEvents log exists                   WARN
WinRM listener configured                    FAIL
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
| **Windows Event Collector service** FAIL | Wecsvc is stopped or disabled. WEF cannot function without this service. | `Set-Service Wecsvc -StartupType Automatic; Start-Service Wecsvc` | [Configure computers to forward events](https://learn.microsoft.com/windows/win32/wec/setting-up-a-source-initiated-subscription) |
| **WinRM service running** FAIL | WinRM is stopped — required for WS-Management event delivery. | `Enable-PSRemoting -Force` or `winrm quickconfig` — also verify firewall allows TCP 5985/5986 | [WinRM installation and configuration](https://learn.microsoft.com/windows/win32/winrm/installation-and-configuration-for-windows-remote-management) |
| **Event subscriptions configured** FAIL | No event forwarding subscriptions found. Collector has no rules defining what events to collect. | `wecutil cs <subscription.xml>` to create subscriptions or configure via GPO: Computer Config → Admin Templates → Windows Components → Event Forwarding | [Create WEF subscriptions](https://learn.microsoft.com/windows/win32/wec/setting-up-a-source-initiated-subscription) |
| **ForwardedEvents log exists** WARN | ForwardedEvents log channel missing or undersized. Events may overflow and be lost. | Increase log size: `wevtutil sl ForwardedEvents /ms:1073741824` (1 GB). Default 20 MB is usually insufficient. | [Event log channels](https://learn.microsoft.com/windows-server/administration/windows-commands/wevtutil) |
| **WinRM listener configured** FAIL | No WinRM listener — remote connections cannot be established for event delivery. | `winrm create winrm/config/Listener?Address=*+Transport=HTTP` or `Enable-PSRemoting -Force` | [WinRM troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-remote-connection-winrm) |

## Related Articles

| Article | Link |
|---|---|
| Windows Event Forwarding overview | [learn.microsoft.com](https://learn.microsoft.com/windows/win32/wec/windows-event-collector) |
| Setting up source-initiated subscriptions | [learn.microsoft.com](https://learn.microsoft.com/windows/win32/wec/setting-up-a-source-initiated-subscription) |
| WinRM configuration for Azure VMs | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-remote-connection-winrm) |
| Azure VM diagnostics IaaS logs | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/iaas-logs) |
