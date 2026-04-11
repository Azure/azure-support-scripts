# Windows Service Dependency Break Check

> **Tool ID:** RC-040 · **Bucket:** Services · **Phase:** 2 (Deep diagnostic)

## What It Does

Checks for broken Windows service dependencies that can cascade into broader failures. Validates service inventory access, counts auto-start services that failed to start, verifies critical infrastructure services (RpcSs, DcomLaunch), and monitors Service Control Manager error volume. Essential for VMs with multiple services failing after a change.

| Check area | What is validated |
|---|---|
| Service inventory | Service inventory query succeeds |
| Auto-start failures | Auto-start services stopped count |
| RpcSs | RPC service running |
| DcomLaunch | DCOM Launch service running |
| SCM errors | SCM error volume below threshold |

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
  --scripts @Windows_Service_Dependency_Break_Check/Windows_Service_Dependency_Break_Check.ps1
```

### Mock test
```powershell
.\Windows_Service_Dependency_Break_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Service Dependency Break Check ===
Check                                        Status
-------------------------------------------- ------
Service inventory query succeeds             OK
Auto services stopped count                  WARN
RpcSs running                                FAIL
DcomLaunch running                           FAIL
SCM error volume below threshold             WARN
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
| **Service inventory query succeeds** FAIL | Cannot enumerate services via WMI/CIM. WMI repository may be corrupted or service is stopped. | `winmgmt /verifyrepository` — if inconsistent: `winmgmt /salvagerepository`. Restart: `Restart-Service winmgmt -Force`. | [Netlogon not starting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-netlogon-not-starting) |
| **Auto services stopped count** WARN | More than 10 auto-start services failed to start. Indicates cascading dependency failure or system corruption. | `Get-Service \| Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } \| Select-Object Name,Status,DependentServices` — start from lowest-level dependency first. | [NSI not starting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-nsi-not-starting) |
| **RpcSs running** FAIL | RPC (Remote Procedure Call) service stopped. Most Windows services depend on RPC — this is usually the root cause of mass service failures. | `Start-Service RpcSs` — if fails, check `sc qc RpcSs` for disabled state and `sc config RpcSs start=auto`. | [Netlogon not starting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-netlogon-not-starting) |
| **DcomLaunch running** FAIL | DCOM Server Process Launcher stopped. COM-based services and WMI will fail. | `Start-Service DcomLaunch` — this is a critical system service. Check for group policy disabling it. | [NSI not starting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-nsi-not-starting) |
| **SCM error volume below threshold** WARN | More than 30 Service Control Manager errors in System log. Indicates widespread service startup failures. | `Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Service Control Manager';Level=2;StartTime=(Get-Date).AddDays(-1)} \| Group-Object Id \| Sort-Object Count -Descending` | [Netlogon not starting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-netlogon-not-starting) |

## Related Articles

| Article | Link |
|---|---|
| Azure VM Netlogon not starting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-netlogon-not-starting) |
| Azure VM NSI not starting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-nsi-not-starting) |
