# Windows NTFS Integrity Check

> **Tool ID:** RC-032 · **Bucket:** Storage / Disk · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates NTFS volume integrity on an Azure VM. Checks for detected fixed volumes, dirty volume flags, BootExecute (chkdsk-on-boot) configuration, recent disk error events, and OS volume C: presence. Essential for VMs with boot failures, data corruption, or "check disk" errors.

| Check area | What is validated |
|---|---|
| Fixed volumes | Fixed volumes detected |
| Dirty volumes | Dirty volume flag count |
| BootExecute | BootExecute key present (chkdsk autorun) |
| Disk errors | Recent disk errors below threshold |
| OS volume | OS volume C: exists |

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
  --scripts @Windows_NTFS_Integrity_Check/Windows_NTFS_Integrity_Check.ps1
```

### Mock test
```powershell
.\Windows_NTFS_Integrity_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows NTFS Integrity Check ===
Check                                        Status
-------------------------------------------- ------
Fixed volumes detected                       OK
Dirty volumes count                          WARN
BootExecute key present                      WARN
Recent disk errors below threshold           WARN
OS volume C exists                           FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 1 OK / 1 FAIL / 3 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Fixed volumes detected** FAIL | No fixed volumes found. Disk may be offline, detached, or controller driver missing. | Check Disk Management or `Get-Disk \| Format-Table Number,OperationalStatus,Size`. If offline: `Set-Disk -Number <n> -IsOffline $false` | [Troubleshoot check disk boot error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-check-disk-boot-error) |
| **Dirty volumes count** WARN | One or more volumes have dirty bit set. Volume was not cleanly unmounted — chkdsk will run on next boot. | `chkntfs C:` to check dirty state. Clear: `chkntfs /x C:` to exclude from auto-check, or run `chkdsk C: /f` offline. | [Troubleshoot check disk boot error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-check-disk-boot-error) |
| **BootExecute key present** WARN | `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\BootExecute` has chkdsk entries. System will run disk check on boot, potentially delaying startup. | `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v BootExecute` — default value should be `autocheck autochk *`. Remove extra entries if causing boot loops. | [Check disk boot error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-check-disk-boot-error) |
| **Recent disk errors below threshold** WARN | More than 20 disk-related events (Event ID 7, 11, 51, 153, 157) in System log. Indicates potential hardware or driver issues. | `Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Disk';StartTime=(Get-Date).AddDays(-7)} \| Measure-Object` — investigate top error sources. | [Disk surprise removed event 157](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/disk-has-been-surprise-removed-event-id-157) |
| **OS volume C exists** FAIL | OS volume C: not found. Boot volume may be missing, offline, or assigned wrong drive letter. | Attach OS disk as data disk to rescue VM. Verify partition table and drive letter assignment. | [Troubleshoot recovery disks](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-recovery-disks-portal-windows) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot check disk boot error | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-check-disk-boot-error) |
| Disk surprise removed event 157 | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/disk-has-been-surprise-removed-event-id-157) |
| Troubleshoot recovery disks | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-recovery-disks-portal-windows) |
