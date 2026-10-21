# Windows WinRM Remoting Health

> **Tool ID:** RC-052 · **Bucket:** VM-Responding · **Phase:** 2 (Deep diagnostic)

## What It Does

Checks the end-to-end health of Windows Remote Management (WinRM) on an Azure VM. WinRM is required for PowerShell remoting, Azure Run Command delivery, and many VM extensions. A broken WinRM stack blocks remote management without RDP.

| Check area | What is validated |
|---|---|
| WinRM service state | Service is installed and running |
| WinRM listener | At least one HTTP/HTTPS listener is configured |
| Firewall rules | Windows Remote Management firewall rules are enabled |
| WS-Management endpoint | Test-WSMan can reach localhost |
| Authentication providers | WinRM auth config (Kerberos, Negotiate, etc.) is readable |

## Run Command Constraints Met

- ✅ PowerShell 5.1 only (no PS7 syntax)
- ✅ No Az module required
- ✅ No internet access needed
- ✅ Output < 4 KB
- ✅ No interactive prompts
- ✅ Read-only (diagnostic only, no system changes)

## How to Run

### Azure Run Command (recommended)
Navigate to VM → Operations → Run Command → RunPowerShellScript → paste script.

### Azure CLI
```bash
az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript \
  --scripts @Windows_WinRM_Remoting_Health/Windows_WinRM_Remoting_Health.ps1
```

### Elevated PowerShell (local)
```powershell
.\Windows_WinRM_Remoting_Health.ps1
```

### Mock test
```powershell
.\Windows_WinRM_Remoting_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile healthy
.\Windows_WinRM_Remoting_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
.\Windows_WinRM_Remoting_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows WinRM Remoting Health ===
Check                                        Status
-------------------------------------------- ------
WinRM service running                        FAIL
WinRM listener exists                        FAIL
WinRM firewall rules enabled                 FAIL
Test-WSMan localhost succeeds                WARN
Auth providers readable                      WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 3 OK / 3 FAIL / 2 WARN ===
```

## Mock Schema

| Key path | Healthy | Degraded | Broken |
|---|---|---|---|
| `WinRM service running` | OK — Running | OK — Running | FAIL — Stopped |
| `WinRM listener exists` | OK — HTTP listener on 5985 | OK — HTTP listener on 5985 | FAIL — No listeners |
| `WinRM firewall rules enabled` | OK — Rules enabled | OK — Rules enabled | FAIL — No enabled rules |
| `Test-WSMan localhost succeeds` | OK — Responding | WARN — Null response | WARN — Not responding |
| `Auth providers readable` | OK — Kerberos+Negotiate | WARN — Cannot enumerate | WARN — Config inaccessible |

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **WinRM service running** FAIL | WinRM service is stopped or disabled. Common after security hardening, GPO changes, or image customization. | `Set-Service WinRM -StartupType Automatic; Start-Service WinRM` (via Serial Console or Run Command if available via another channel) | [Remote tools to troubleshoot Azure VM issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/remote-tools-troubleshoot-azure-vm-issues) |
| **WinRM listener exists** FAIL | No WinRM listener configured. Can happen after `winrm delete` or image sysprep without re-configuration. | `winrm quickconfig -force` — creates default HTTP listener on port 5985. For HTTPS: `winrm quickconfig -transport:https` | [WinRM listeners](https://learn.microsoft.com/windows/win32/winrm/installation-and-configuration-for-windows-remote-management) |
| **WinRM firewall rules enabled** FAIL | Windows Firewall blocks WinRM port 5985/5986. Happens when firewall profile changes (Domain → Public) or rules are manually disabled. | `Enable-NetFirewallRule -DisplayGroup "Windows Remote Management"` or `netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes` | [Remote tools to troubleshoot Azure VM issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/remote-tools-troubleshoot-azure-vm-issues) |
| **Test-WSMan localhost succeeds** WARN | WinRM service is running but not responding to WS-Management requests. Possible TLS/auth misconfiguration or resource exhaustion. | `Restart-Service WinRM -Force` — if persists, run `winrm quickconfig -force` to reset configuration | [WinRM configuration](https://learn.microsoft.com/windows/win32/winrm/installation-and-configuration-for-windows-remote-management) |
| **Auth providers readable** WARN | Cannot enumerate WinRM auth providers. May indicate config corruption, WMI repository damage, or permission issue. | `winrm set winrm/config/service/auth @{Negotiate="true";Kerberos="true"}` — if fully broken: `winrm invoke restore winrm/config @{}` | [WinRM authentication](https://learn.microsoft.com/windows/win32/winrm/authentication-for-remote-connections) |

## Related Articles

| Article | Link |
|---|---|
| Use remote tools to troubleshoot Azure VM issues | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/remote-tools-troubleshoot-azure-vm-issues) |
| Run Command for Windows VMs | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-machines/windows/run-command) |
| WinRM installation and configuration | [learn.microsoft.com](https://learn.microsoft.com/windows/win32/winrm/installation-and-configuration-for-windows-remote-management) |
| WinRM authentication for remote connections | [learn.microsoft.com](https://learn.microsoft.com/windows/win32/winrm/authentication-for-remote-connections) |
