# Windows Group Policy Processing Health

> **Tool ID:** RC-024 · **Bucket:** Identity / Group Policy · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates Group Policy processing health on a domain-joined Azure VM. Checks GPSvc service state, operational log accessibility, recent GP error volume, and NETLOGON/SYSVOL path accessibility. Important for VMs stuck at "Applying Group Policy" or failing to apply policies.

| Check area | What is validated |
|---|---|
| GPSvc service | Group Policy Client service running |
| Operational log | GroupPolicy operational log readable |
| GP errors | Recent GP errors below threshold |
| NETLOGON path | NETLOGON network path accessible |
| SYSVOL path | SYSVOL network path accessible |

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
  --scripts @Windows_GroupPolicy_Processing_Health/Windows_GroupPolicy_Processing_Health.ps1
```

### Mock test
```powershell
.\Windows_GroupPolicy_Processing_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Group Policy Processing Health ===
Check                                        Status
-------------------------------------------- ------
GPSvc service running                        FAIL
GroupPolicy operational log readable         WARN
Recent GP errors below threshold             WARN
NETLOGON path accessible                     WARN
SYSVOL path accessible                       WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 1 FAIL / 4 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **GPSvc service running** FAIL | Group Policy Client service (gpsvc) is stopped. Policies cannot be applied. VM may be stuck at boot. | `Set-Service gpsvc -StartupType Automatic; Start-Service gpsvc`. If stuck at boot, use Serial Console. | [Unresponsive VM applying Group Policy](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/unresponsive-vm-apply-group-policy) |
| **GroupPolicy operational log readable** WARN | GroupPolicy operational event log is empty or inaccessible. Cannot determine GP processing state. | `wevtutil gl "Microsoft-Windows-GroupPolicy/Operational"` — if disabled, enable: `wevtutil sl "Microsoft-Windows-GroupPolicy/Operational" /e:true` | [Applying Group Policy services policy](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/applying-group-policy-services-policy) |
| **Recent GP errors below threshold** WARN | More than 5 GP errors in operational log. May indicate policy conflicts, missing DC, or WMI filter failures. | `gpresult /h C:\temp\gpreport.html` — review for failed policies. Check DC connectivity. | [Unresponsive VM applying Group Policy](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/unresponsive-vm-apply-group-policy) |
| **NETLOGON path accessible** WARN | `\\<domain>\NETLOGON` is inaccessible. Logon scripts and some policies will fail. | Verify DNS points to DC. Test: `net use \\<domain>\NETLOGON`. Check firewall allows SMB (445). | [Applying Group Policy services policy](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/applying-group-policy-services-policy) |
| **SYSVOL path accessible** WARN | `\\<domain>\SYSVOL` is inaccessible. GPO templates cannot be downloaded. | Same as NETLOGON — verify DNS, SMB connectivity, and DC replication. `dcdiag /test:sysvolcheck` on DC. | [Applying Group Policy services policy](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/applying-group-policy-services-policy) |

## Related Articles

| Article | Link |
|---|---|
| Unresponsive VM applying Group Policy | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/unresponsive-vm-apply-group-policy) |
| Applying Group Policy services policy | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/applying-group-policy-services-policy) |
