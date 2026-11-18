# Windows Firewall Profile Baseline Check

> **Tool ID:** RC-022 · **Bucket:** Network / Firewall · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates Windows Firewall profile configuration and critical rule state. Checks profile query capability, enabled profiles, RDP firewall rule, inbound default policy, and Base Filtering Engine (BFE) service. Essential for diagnosing VMs where connectivity is blocked by guest firewall misconfiguration.

| Check area | What is validated |
|---|---|
| Profile query | Firewall profiles query succeeds |
| Enabled profiles | At least one firewall profile enabled |
| RDP rule | Remote Desktop rule enabled |
| Inbound default | Inbound default block active |
| BFE service | Base Filtering Engine running |

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
  --scripts @Windows_Firewall_Profile_Baseline_Check/Windows_Firewall_Profile_Baseline_Check.ps1
```

### Mock test
```powershell
.\Windows_Firewall_Profile_Baseline_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Firewall Profile Baseline Check ===
Check                                        Status
-------------------------------------------- ------
Firewall profiles query succeeds             OK
At least one profile enabled                 FAIL
Remote Desktop rule enabled                  WARN
Inbound default block active                 WARN
BFE service running                          FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 1 OK / 2 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Firewall profiles query succeeds** FAIL | `Get-NetFirewallProfile` failed. WMI/CIM subsystem issue or firewall provider crashed. | Restart WMI: `Restart-Service winmgmt -Force`. If persistent, check WMI repository integrity. | [Guest OS firewall misconfigured](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/guest-os-firewall-misconfigured) |
| **At least one profile enabled** FAIL | All firewall profiles disabled. VM has no firewall protection and may allow unexpected traffic. | `Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True` | [Enable/disable firewall rule](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/enable-disable-firewall-rule-guest-os) |
| **Remote Desktop rule enabled** WARN | Windows Firewall RDP inbound rule is disabled. Remote Desktop connections will be blocked at the guest level. | `Enable-NetFirewallRule -DisplayGroup "Remote Desktop"` | [Enable/disable firewall rule](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/enable-disable-firewall-rule-guest-os) |
| **Inbound default block active** WARN | Default inbound policy is Allow instead of Block. VM is accepting all inbound traffic not explicitly denied. | `Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block` | [Guest OS firewall misconfigured](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/guest-os-firewall-misconfigured) |
| **BFE service running** FAIL | Base Filtering Engine stopped. Windows Firewall and all WFP-based filtering is non-functional. | `Set-Service BFE -StartupType Automatic; Start-Service BFE; Start-Service MpsSvc` | [Guest OS firewall misconfigured](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/guest-os-firewall-misconfigured) |

## Related Articles

| Article | Link |
|---|---|
| Guest OS firewall misconfigured | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/guest-os-firewall-misconfigured) |
| Enable/disable guest OS firewall rule | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/enable-disable-firewall-rule-guest-os) |
