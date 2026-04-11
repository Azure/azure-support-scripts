# Windows Service & Boot Audit

> **Tool ID:** RC-002 · **Bucket:** VM-Responding / OS-Service-Failures / Unexpected-Restarts · **Phase:** 1

## What It Does

Audits the most common **in-guest service and boot configuration** issues that prevent an Azure Windows VM from functioning correctly:

| Check area | What is validated |
|---|---|
| **Critical Services** | 10 key services: start type not Disabled, required services Running |
| **SafeBoot** | VM is NOT running in safeboot mode (Minimal/Network/DsRepair) |
| **BCDEdit** | No non-standard boot recovery sequence active |
| **EventLog** | System and Application event log channels are accessible |

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
3. Paste the contents of `Windows_Service_Boot_Audit.ps1`
4. Select **Run** and wait for output

### Azure CLI
```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <vm-name> \
  --command-id RunPowerShellScript \
  --scripts @Windows_Service_Boot_Audit.ps1
```

### Elevated PowerShell (inside VM)
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Windows_Service_Boot_Audit.ps1
```

### Mock / Offline Test
```powershell
.\Windows_Service_Boot_Audit.ps1 -MockConfig .\mock_config_sample.json
```

## Sample Output (Issue Detected)

```
=== Windows Service & Boot Audit ===
Check                                        Status
-------------------------------------------- ------
-- Critical Services (Start Type + Running) --
RPC (RpcSs)                                  OK
Windows Event Log                            OK
Remote Desktop Service                       FAIL
DNS Client (Dnscache)                        OK
Workstation                                  OK
Netlogon                                     FAIL
DHCP Client                                  OK
Base Filtering Engine (BFE)                  OK
Cryptographic Services                       OK
Windows Update (wuauserv)                    OK
-- Boot Configuration --
SafeBoot NOT active (normal boot)            FAIL
Boot recovery sequence (recoveryenabled)     OK
-- EventLog Health --
System event log accessible                  OK
Application event log accessible             OK

=== RESULT: 11 OK / 3 FAIL / 0 WARN ===
```

## Mock Schema

| Key path | Values |
|---|---|
| `services.<Name>.startType` | `2` (Auto) · `3` (Manual) · `4` (Disabled) |
| `services.<Name>.running` | `true` / `false` |
| `boot.safeBootActive` | `true` / `false` |
| `boot.safeBootType` | `0` (Everything) · `1` (Minimal) · `2` (Network) · `3` (DsRepair) |
| `boot.recoveryMode` | `true` / `false` |
| `eventlog.systemOk` | `true` / `false` |
| `eventlog.applicationOk` | `true` / `false` |

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix |
|---|---|---|
| Service Disabled + FAIL | Manually disabled or GPO | Re-enable via Services console or registry `Start=2` |
| SafeBoot FAIL | VM booted via msconfig/bcdedit safeboot | `bcdedit /deletevalue {current} safeboot` then reboot |
| Netlogon FAIL | Domain-joined VM with DC connectivity issues | Check DNS, domain trust |
| BFE FAIL | Windows Firewall infrastructure broken | Critical — blocks all network filtering |
| EventLog FAIL | Log corruption or Windows instability | Run `sfc /scannow` and check DISM |

## Related Articles

- [Troubleshoot Azure Windows VM unexpected restarts](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/understand-vm-reboot)
- [How to reset the Remote Desktop service on a Windows VM](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/reset-rdp)
- [Use Run Command to run scripts in your Windows VM](https://learn.microsoft.com/azure/virtual-machines/windows/run-command)
