# Windows Extension Install Chain Health

> **Tool ID:** RC-022 · **Bucket:** Azure Agent · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates the Azure VM Agent extension installation pipeline. Checks that the Guest Agent (WindowsAzureGuestAgent) and RdAgent services are running, extension handler registry entries exist, the extension plugin directory is accessible, WireServer (168.63.129.16) is reachable, and agent logs are free of recent errors. Critical for diagnosing extension install/update failures.

| Check area | What is validated |
|---|---|
| VM Agent service | Guest Agent (WindowsAzureGuestAgent) running |
| RdAgent service | RdAgent service running |
| Handler registry | Extension handler registry entries present |
| Config folder | C:\Packages\Plugins exists and accessible |
| WireServer | Connectivity to 168.63.129.16 |
| Agent log errors | Recent errors in Guest Agent logs |

## Run Command Constraints Met

- ✅ PowerShell 5.1 only
- ✅ No Az module required
- ✅ No internet access needed (WireServer is host-local)
- ✅ Output < 4 KB
- ✅ No interactive prompts
- ✅ Read-only (diagnostic only)

## How to Run

### Azure Run Command (recommended)
Navigate to VM → Operations → Run Command → RunPowerShellScript → paste script.

### Azure CLI
```bash
az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript \
  --scripts @Windows_Extension_Install_Chain_Health/Windows_Extension_Install_Chain_Health.ps1
```

### Mock test
```powershell
.\Windows_Extension_Install_Chain_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Extension Install Chain Health ===
Check                                        Status
-------------------------------------------- ------
VM Agent service running                     FAIL
RdAgent service running                      FAIL
Extension handler registry entries           WARN
Extension config folder accessible           FAIL
WireServer connectivity (168.63.129.16)      FAIL
Agent log recent errors                      FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 5 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **VM Agent service running** FAIL | Guest Agent service is stopped, crashed, or was uninstalled. Extensions cannot install or report status without it. | Reinstall agent from `https://aka.ms/waagent`. Restart service: `Start-Service WindowsAzureGuestAgent` | [Troubleshoot Azure VM Agent](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/support-agent-extensions) |
| **RdAgent service running** FAIL | RdAgent is stopped — it coordinates with the fabric and launches extension handlers. | `Start-Service RdAgent`. If missing, reinstall the VM Agent MSI. | [VM Agent overview](https://learn.microsoft.com/azure/virtual-machines/extensions/agent-windows) |
| **Extension handler registry entries** WARN | Few or no handler registry keys. May indicate agent was recently installed or extensions were cleaned. | Check `HKLM:\SOFTWARE\Microsoft\Windows Azure\HandlerState`. If empty, trigger extension reinstall from Azure Portal. | [Extension troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-extension-certificates-issues-windows-vm) |
| **Extension config folder accessible** FAIL | `C:\Packages\Plugins` missing or inaccessible. Extensions cannot be staged or executed. | Create if missing: `mkdir 'C:\Packages\Plugins'`. Check disk space on C: drive. Verify NTFS permissions allow SYSTEM full access. | [Troubleshoot extension certificates](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-extension-certificates-issues-windows-vm) |
| **WireServer connectivity (168.63.129.16)** FAIL | Cannot reach WireServer — NSG, UDR, or Windows Firewall blocking 168.63.129.16. Agent cannot fetch configuration or report status. | Check: `Test-NetConnection 168.63.129.16 -Port 80`. Verify no UDR overrides the 168.63.129.16 route. Allow in firewall. | [What is IP 168.63.129.16?](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16) |
| **Agent log recent errors** WARN | Errors in `C:\WindowsAzure\Logs\WaAppAgent.log`. May indicate extension timeout, download failure, or certificate issue. | Review last 50 lines: `Get-Content 'C:\WindowsAzure\Logs\WaAppAgent.log' -Tail 50`. Common: cert expired, disk full, proxy block. | [Collect VM Agent logs](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/support-agent-extensions) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot Azure VM Agent and extensions | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/support-agent-extensions) |
| Azure VM Agent for Windows | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-machines/extensions/agent-windows) |
| What is IP address 168.63.129.16? | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16) |
| Troubleshoot extension certificate issues | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-extension-certificates-issues-windows-vm) |
