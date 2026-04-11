# Windows VSS Writer Health

> **Tool ID:** RC-052 · **Bucket:** Backup / Recovery · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates Volume Shadow Copy Service (VSS) health and writer state. Checks writer enumeration, failed writer count, VSS service availability, startup mode, and provider registration. Essential for VMs where Azure Backup or application-consistent snapshots fail.

| Check area | What is validated |
|---|---|
| Writers query | vssadmin writers query succeeds |
| Failed writers | Failed VSS writers count |
| VSS service | VSS service available |
| Startup mode | VSS service startup mode acceptable |
| Provider | At least one VSS provider found |

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
  --scripts @Windows_VSS_Writer_Health/Windows_VSS_Writer_Health.ps1
```

### Mock test
```powershell
.\Windows_VSS_Writer_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows VSS Writer Health ===
Check                                        Status
-------------------------------------------- ------
vssadmin writers query succeeds              FAIL
Failed VSS writers count                     FAIL
VSS service available                        FAIL
VSS service startup mode acceptable          WARN
At least one VSS provider found              WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 3 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **vssadmin writers query succeeds** FAIL | `vssadmin list writers` failed to return results. VSS subsystem may be hung or service crashed. | `vssadmin list writers` — if hangs, restart VSS: `Restart-Service VSS`. If COM errors, register: `cd /d %windir%\system32 && regsvr32 ole32.dll && regsvr32 vss_ps.dll` | [Troubleshoot Azure Backup VSS](https://learn.microsoft.com/azure/backup/backup-azure-vms-troubleshoot#step-2-check-azure-vm-extension-health) |
| **Failed VSS writers count** FAIL | One or more VSS writers in failed/error state. Application-consistent backups will fail. | `vssadmin list writers \| findstr /i "state"` to identify failed writers. Common fix: restart the owning service (SQL Writer → restart SQLWriter service). | [VSS troubleshooting](https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/vss-error-8004231f) |
| **VSS service available** FAIL | Volume Shadow Copy service is not running. All VSS operations (backup, snapshot) will fail. | `Set-Service VSS -StartupType Manual; Start-Service VSS` — VSS startup should be Manual (starts on demand). | [Troubleshoot recovery disks](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-recovery-disks-portal-windows) |
| **VSS service startup mode acceptable** WARN | VSS startup type is Disabled. VSS cannot start on demand for backup operations. | `Set-Service VSS -StartupType Manual` — Manual is the correct default (VSS starts when backup requests it). | [Azure Backup VSS troubleshooting](https://learn.microsoft.com/azure/backup/backup-azure-vms-troubleshoot) |
| **At least one VSS provider found** WARN | No VSS providers registered. Shadow copies cannot be created without a provider. | `vssadmin list providers` — should show "Microsoft Software Shadow Copy provider 1.0". If missing, run `regsvr32 swprv.dll`. | [VSS error troubleshooting](https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/vss-error-8004231f) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot Azure VM backup | [learn.microsoft.com](https://learn.microsoft.com/azure/backup/backup-azure-vms-troubleshoot) |
| VSS error 8004231F | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/vss-error-8004231f) |
| Troubleshoot recovery disks | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-recovery-disks-portal-windows) |
