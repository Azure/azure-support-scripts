# Windows VM Agent & Extension Health Dump

> **Tool ID:** RC-004 · **Bucket:** VM-Responding / AGEX / Extension-Failures · **Phase:** 1

## What It Does

Provides a complete health snapshot of the **Azure Guest Agent and all installed extension handlers** on a running Windows VM:

| Check area | What is validated |
|---|---|
| **Guest Agent Services** | WindowsAzureGuestAgent and RdAgent status + installed version |
| **Agent Heartbeat** | Agent log file exists and was written within the last 5 minutes |
| **Extension Handlers** | All handlers in registry — status (Ready/NotReady/Unresponsive) and sequence number |
| **Agent Log Errors** | Last 80 lines of WaAppAgent.log filtered for ERR/WARN entries |

The script is **read-only** — it makes no changes to the system.

## Run Command Constraints Met

- PowerShell 5.1 only
- No Az module used
- No internet access required
- Output < 4 KB
- No interactive prompts

## How to Run

### Azure Run Command (recommended)
1. Go to your VM in the Azure portal
2. Select **Operations → Run Command → RunPowerShellScript**
3. Paste the contents of `Windows_VM_Agent_Health_Dump.ps1`
4. Select **Run** and wait for output

### Azure CLI
```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <vm-name> \
  --command-id RunPowerShellScript \
  --scripts @Windows_VM_Agent_Health_Dump.ps1
```

### Elevated PowerShell (inside VM)
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Windows_VM_Agent_Health_Dump.ps1
```

### Mock / Offline Test
```powershell
.\Windows_VM_Agent_Health_Dump.ps1 -MockConfig .\mock_config_sample.json
```

## Sample Output (Issues Detected)

```
=== Windows VM Agent & Extension Health Dump ===
Check                                        Status
-------------------------------------------- ------
-- Guest Agent Services --
WindowsAzureGuestAgent                       OK
RdAgent                                      FAIL
-- Agent Heartbeat --
Agent log file exists                        OK
Agent log freshness (< 5 min)                WARN
-- Extension Handlers --
Ext: Microsoft.Compute.CustomScriptExtension OK
Ext: Microsoft.Azure.Diagnostics.IaaSDiagno OK
Ext: Microsoft.EnterpriseCloud.Monitoring.M. FAIL
Ext: Microsoft.CPlat.Core.WindowsPatchExten  WARN
-- Agent Log (recent ERR/WARN) --
WaAppAgent.log recent errors                 WARN
  >> [ERROR] GuestAgentPlugin Unresponsive ...
  >> [WARN]  HandlerManifest fetch retry 3/5 ...

=== RESULT: 5 OK / 2 FAIL / 3 WARN ===
```

## Mock Schema

| Key path | Values |
|---|---|
| `agentServices.<Name>.status` | `"Running"` · `"Stopped"` · `"NotFound"` |
| `agentServices.<Name>.version` | Version string e.g. `"2.7.41491.1090"` |
| `heartbeat.exists` | `true` / `false` |
| `heartbeat.ageMinutes` | Number (minutes since last write) |
| `extensions[].name` | Full extension handler name |
| `extensions[].status` | `"Ready"` · `"NotReady"` · `"Unresponsive"` · `"Installing"` |
| `extensions[].seqNo` | Sequence number string |
| `recentLogErrors` | Array of log line strings |

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix |
|---|---|---|
| WindowsAzureGuestAgent FAIL | Agent crashed, corrupt install, or blocked | Reinstall agent via offline repair or [Guest Agent extension reinstall](https://learn.microsoft.com/azure/virtual-machines/extensions/agent-windows) |
| RdAgent NotFound | Stripped image or agent removed | Reinstall Windows Azure Guest Agent |
| Heartbeat stale > 30 min | WireServer blocked or agent hung | Check NSG/UDR blocking 168.63.129.16, restart agent service |
| Extension Unresponsive | Hung handler process | Disable and re-enable extension from portal |
| Extension NotReady | Extension installing or failing to init | Check portal extension blade for detailed error state |
| Agent log errors | Transient WireServer retries or handler failures | Review full `C:\WindowsAzure\Logs\WaAppAgent.log` for context |

## Related Articles

- [Azure Windows VM agent overview](https://learn.microsoft.com/azure/virtual-machines/extensions/agent-windows)
- [Troubleshoot Azure VM extension issues](https://learn.microsoft.com/azure/virtual-machines/extensions/troubleshoot)
- [Azure VM Guest Agent](https://learn.microsoft.com/azure/virtual-machines/windows/windows-azure-guest-agent)
