# Windows RDP Health Snapshot

> **Tool ID:** RC-001 · **Bucket:** VM-Responding / Cant-RDP-SSH · **Phase:** 1

## What It Does

Diagnoses the five most common **in-guest** causes of RDP connectivity failure on an Azure Windows VM:

| Check area | What is validated |
|---|---|
| **Services** | TermService, Netlogon, Dnscache, LanmanWorkstation, LSM, BFE all Running |
| **Registry** | `fDenyTSConnections = 0` (RDP not blocked by policy/GPO) |
| **NLA** | `SecurityLayer` value is a valid setting (0/1/2) |
| **Firewall** | RDP inbound rule enabled for port 3389; BFE running |
| **Listener** | Port 3389 is in LISTENING state |

The script is **read-only** — it makes no changes to the system.

## Run Command Constraints Met

- PowerShell 5.1 only (no `?.`, ternary, or PS7 syntax)
- No Az module used
- No internet access required
- Output < 4 KB
- No interactive prompts

## How to Run

### Azure Run Command (recommended)
1. Go to your VM in the Azure portal
2. Select **Operations → Run Command → RunPowerShellScript**
3. Paste the contents of `Windows_RDP_Health_Snapshot.ps1`
4. Select **Run** and wait for output

### Azure CLI
```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <vm-name> \
  --command-id RunPowerShellScript \
  --scripts @Windows_RDP_Health_Snapshot.ps1
```

### Elevated PowerShell (inside VM)
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Windows_RDP_Health_Snapshot.ps1
```

### Mock / Offline Test
```powershell
.\Windows_RDP_Health_Snapshot.ps1 -MockConfig .\mock_config_sample.json
```

## Sample Output (Healthy VM)

```
=== Windows RDP Health Snapshot ===
Check                                        Status
-------------------------------------------- ------
-- Services --
Remote Desktop Service (TermService)         OK
Netlogon                                     OK
DNS Client (Dnscache)                        OK
Workstation (LanmanWorkstation)              OK
Local Session Manager (LSM)                  OK
Base Filtering Engine (BFE/Firewall)         OK
-- Registry --
fDenyTSConnections = 0 (RDP allowed)         OK
NLA SecurityLayer: Negotiate                 OK
-- Windows Firewall --
RDP inbound rule enabled (port 3389)         OK
BFE running (firewall enforcement)           OK
-- RDP Listener --
Port 3389 in LISTENING state                 OK

=== RESULT: 11 OK / 0 FAIL / 0 WARN ===
```

## Mock Schema

| Key path | Values |
|---|---|
| `services.<ServiceName>` | `"Running"` \| `"Stopped"` \| `"NotFound"` |
| `registry.fDenyTSConnections` | `0` (OK) · `1` (FAIL) |
| `registry.SecurityLayer` | `0` (RDP) · `1` (Negotiate) · `2` (NLA/SSL) |
| `firewall.rdpRuleEnabled` | `true` / `false` |
| `firewall.bfeRunning` | `true` / `false` |
| `listener.port3389Listening` | `true` / `false` |

## Interpretation Guide

| FAIL condition | Likely cause | Quick fix |
|---|---|---|
| TermService FAIL | Service crashed or disabled | `Set-Service TermService -StartupType Auto; Start-Service TermService` |
| fDenyTSConnections = 1 | GPO or manual policy block | Check `HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server` |
| RDP firewall rule FAIL | Rule deleted or custom FW profile | `Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'` |
| Port 3389 not listening | Service stopped OR listener misconfigured | Restart TermService, check `netsh interface portproxy` |
| BFE FAIL | Windows Firewall enforcement broken | Critical — restart BFE and associated services |

## Related Articles

- [Troubleshoot RDP connections to an Azure VM](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/troubleshoot-rdp-connection)
- [Detailed troubleshooting steps for RDP](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/detailed-troubleshoot-rdp)
- [Remote Desktop Services issues](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/troubleshoot-remote-desktop-services-issues)
