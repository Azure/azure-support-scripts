# Windows Storage Spaces Health

> **Tool ID:** RC-045 · **Bucket:** Storage · **Phase:** 2 (Deep diagnostic)

## What It Does

Assesses Storage Spaces and Storage Spaces Direct (S2D) health on an Azure VM. Checks subsystem availability, storage pool health, virtual disk status, physical disk health, and S2D cluster state. Important for VMs using Storage Spaces for disk pooling or running Azure Stack HCI / failover cluster storage.

| Check area | What is validated |
|---|---|
| Storage subsystem | Storage Spaces subsystem present |
| Pool health | Storage pools healthy (no degraded/failed) |
| Virtual disk health | Virtual disks healthy |
| Physical disk health | Physical disks healthy |
| S2D state | Storage Spaces Direct state (if clustered) |

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
  --scripts @Windows_StorageSpaces_Health/Windows_StorageSpaces_Health.ps1
```

### Mock test
```powershell
.\Windows_StorageSpaces_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows Storage Spaces Health ===
Check                                        Status
-------------------------------------------- ------
Storage Spaces subsystem                     OK
Storage pool health                          FAIL
Virtual disk health                          FAIL
Physical disk health                         WARN
Storage Spaces Direct (S2D) state            OK
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 2 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Storage Spaces subsystem** FAIL | Storage Spaces subsystem not found. Feature may not be installed or WMI provider missing. | `Get-StorageSubSystem` — if empty, Storage Spaces is not configured. Install feature if needed: `Install-WindowsFeature Storage-Services` | [Storage Spaces overview](https://learn.microsoft.com/windows-server/storage/storage-spaces/overview) |
| **Storage pool health** FAIL | One or more storage pools in degraded or unhealthy state. May indicate physical disk failure or insufficient redundancy. | `Get-StoragePool \| Where-Object { $_.HealthStatus -ne 'Healthy' }` to identify. Check physical disks in the pool for failures. | [Troubleshoot Storage Spaces](https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-states) |
| **Virtual disk health** FAIL | Virtual disks are degraded or detached. Data may be at risk if redundancy is depleted. | `Get-VirtualDisk \| Where-Object { $_.HealthStatus -ne 'Healthy' }` — repair: `Repair-VirtualDisk -FriendlyName <name>` | [Virtual disk states](https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-states) |
| **Physical disk health** WARN | Physical disks reporting warnings. May indicate reallocated sectors, latency issues, or predicted failure. | `Get-PhysicalDisk \| Where-Object { $_.HealthStatus -ne 'Healthy' }` — replace failing disks. In Azure, detach and reattach data disk. | [Troubleshoot recovery disks](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-recovery-disks-portal-windows) |
| **Storage Spaces Direct (S2D) state** WARN | S2D is not enabled or in maintenance mode. Only relevant for clustered VMs. Single VMs show N/A. | `Get-ClusterS2D` to check. If maintenance: `Resume-ClusterNode`. Informational if not clustered. | [Storage Spaces Direct overview](https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-direct-overview) |

## Related Articles

| Article | Link |
|---|---|
| Storage Spaces overview | [learn.microsoft.com](https://learn.microsoft.com/windows-server/storage/storage-spaces/overview) |
| Storage Spaces states | [learn.microsoft.com](https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-states) |
| Troubleshoot recovery disks in Azure | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-recovery-disks-portal-windows) |
### Mock test
```powershell
.\Windows_StorageSpaces_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows Storage Spaces Health ===
Check                                        Status
-------------------------------------------- ------
Storage Spaces subsystem                     OK
Storage pool health                          FAIL
Virtual disk health                          FAIL
Physical disk health                         WARN
Storage Spaces Direct (S2D) state            OK
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 2 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Storage Spaces subsystem** FAIL | Storage Spaces subsystem not found. Feature may not be installed or WMI provider missing. | `Get-StorageSubSystem` — if empty, Storage Spaces is not configured. Install feature if needed: `Install-WindowsFeature Storage-Services` | [Storage Spaces overview](https://learn.microsoft.com/windows-server/storage/storage-spaces/overview) |
| **Storage pool health** FAIL | One or more storage pools in degraded or unhealthy state. May indicate physical disk failure or insufficient redundancy. | `Get-StoragePool \| Where-Object { $_.HealthStatus -ne 'Healthy' }` to identify. Check physical disks in the pool for failures. | [Troubleshoot Storage Spaces](https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-states) |
| **Virtual disk health** FAIL | Virtual disks are degraded or detached. Data may be at risk if redundancy is depleted. | `Get-VirtualDisk \| Where-Object { $_.HealthStatus -ne 'Healthy' }` — repair: `Repair-VirtualDisk -FriendlyName <name>` | [Virtual disk states](https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-states) |
| **Physical disk health** WARN | Physical disks reporting warnings. May indicate reallocated sectors, latency issues, or predicted failure. | `Get-PhysicalDisk \| Where-Object { $_.HealthStatus -ne 'Healthy' }` — replace failing disks. In Azure, detach and reattach data disk. | [Troubleshoot recovery disks](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-recovery-disks-portal-windows) |
| **Storage Spaces Direct (S2D) state** WARN | S2D is not enabled or in maintenance mode. Only relevant for clustered VMs. Single VMs show N/A. | `Get-ClusterS2D` to check. If maintenance: `Resume-ClusterNode`. Informational if not clustered. | [Storage Spaces Direct overview](https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-direct-overview) |

## Related Articles

| Article | Link |
|---|---|
| Storage Spaces overview | [learn.microsoft.com](https://learn.microsoft.com/windows-server/storage/storage-spaces/overview) |
| Storage Spaces states | [learn.microsoft.com](https://learn.microsoft.com/windows-server/storage/storage-spaces/storage-spaces-states) |
| Troubleshoot recovery disks in Azure | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-recovery-disks-portal-windows) |
