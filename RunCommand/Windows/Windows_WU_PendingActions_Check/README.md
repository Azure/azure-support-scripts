# Windows WU Pending Actions Check

> **Tool ID:** RC-051 · **Bucket:** Updates · **Phase:** 2 (Deep diagnostic)

## What It Does

Detects pending Windows Update actions that may delay reboots, block further updates, or cause boot issues. Checks reboot-required flags, pending file rename operations, Component Based Servicing state, Windows Update service health, active installer sessions, and recent update failures. Critical for VMs stuck in update loops or failing to apply patches.

| Check area | What is validated |
|---|---|
| Reboot required | Reboot required registry flag |
| Pending renames | PendingFileRenameOperations count |
| CBS pending | Component Based Servicing reboot pending |
| WU service | Windows Update service state |
| Active installer | Update installer session in progress |
| Recent failures | Recent Windows Update install failures |

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
  --scripts @Windows_WU_PendingActions_Check/Windows_WU_PendingActions_Check.ps1
```

### Mock test
```powershell
.\Windows_WU_PendingActions_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows WU Pending Actions Check ===
Check                                        Status
-------------------------------------------- ------
Reboot required flag                         FAIL
Pending file rename operations               WARN
Component Based Servicing pending            FAIL
Windows Update service state                 OK
Update session in progress                   WARN
Recent update install failures               FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 1 OK / 3 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Reboot required flag** FAIL | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired` exists. VM needs restart to complete updates. | `Restart-Computer` — schedule during maintenance window if production VM | [Windows Update installation capacity](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-update-installation-capacity) |
| **Pending file rename operations** WARN | `PendingFileRenameOperations` in Session Manager registry has entries. Files will be replaced on next reboot. | Review: `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations`. Reboot to process. | [Pending reboot detection](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-update-installation-capacity) |
| **Component Based Servicing pending** FAIL | CBS flagged a pending reboot. Servicing stack operations (updates, features, roles) cannot proceed until reboot. | `Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"` — reboot to clear | [CBS and servicing stack](https://learn.microsoft.com/troubleshoot/windows-client/deployment/fix-windows-update-errors) |
| **Windows Update service state** WARN | wuauserv service is stopped or disabled. Updates cannot be detected, downloaded, or installed. | `Set-Service wuauserv -StartupType Automatic; Start-Service wuauserv` | [Windows Update reset tool](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-wureset-tool) |
| **Update session in progress** WARN | An update installer session is actively running. Running another may conflict. Wait for completion. | Check `C:\Windows\WindowsUpdate.log` or `Get-WindowsUpdateLog` for status. Wait for current install to finish. | [Windows Update troubleshooting](https://learn.microsoft.com/troubleshoot/windows-client/deployment/fix-windows-update-errors) |
| **Recent update install failures** FAIL | KB installations failed recently. May indicate disk space, corruption, or component store issues. | `Get-HotFix \| Sort-Object InstalledOn -Descending \| Select-Object -First 5`. Run DISM: `DISM /Online /Cleanup-Image /RestoreHealth` then `sfc /scannow` | [Fix Windows Update errors](https://learn.microsoft.com/troubleshoot/windows-client/deployment/fix-windows-update-errors) |

## Related Articles

| Article | Link |
|---|---|
| Windows Update installation capacity | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-update-installation-capacity) |
| Windows Update reset tool for Azure VMs | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-wureset-tool) |
| Fix Windows Update errors | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-client/deployment/fix-windows-update-errors) |

### Mock test
```powershell
.\Windows_WU_PendingActions_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows WU Pending Actions Check ===
Check                                        Status
-------------------------------------------- ------
Reboot required flag                         FAIL
Pending file rename operations               WARN
Component Based Servicing pending            FAIL
Windows Update service state                 OK
Update session in progress                   WARN
Recent update install failures               FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 1 OK / 3 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Reboot required flag** FAIL | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired` exists. VM needs restart to complete updates. | `Restart-Computer` — schedule during maintenance window if production VM | [Windows Update installation capacity](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-update-installation-capacity) |
| **Pending file rename operations** WARN | `PendingFileRenameOperations` in Session Manager registry has entries. Files will be replaced on next reboot. | Review: `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations`. Reboot to process. | [Pending reboot detection](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-update-installation-capacity) |
| **Component Based Servicing pending** FAIL | CBS flagged a pending reboot. Servicing stack operations (updates, features, roles) cannot proceed until reboot. | `Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"` — reboot to clear | [CBS and servicing stack](https://learn.microsoft.com/troubleshoot/windows-client/deployment/fix-windows-update-errors) |
| **Windows Update service state** WARN | wuauserv service is stopped or disabled. Updates cannot be detected, downloaded, or installed. | `Set-Service wuauserv -StartupType Automatic; Start-Service wuauserv` | [Windows Update reset tool](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-wureset-tool) |
| **Update session in progress** WARN | An update installer session is actively running. Running another may conflict. Wait for completion. | Check `C:\Windows\WindowsUpdate.log` or `Get-WindowsUpdateLog` for status. Wait for current install to finish. | [Windows Update troubleshooting](https://learn.microsoft.com/troubleshoot/windows-client/deployment/fix-windows-update-errors) |
| **Recent update install failures** FAIL | KB installations failed recently. May indicate disk space, corruption, or component store issues. | `Get-HotFix \| Sort-Object InstalledOn -Descending \| Select-Object -First 5`. Run DISM: `DISM /Online /Cleanup-Image /RestoreHealth` then `sfc /scannow` | [Fix Windows Update errors](https://learn.microsoft.com/troubleshoot/windows-client/deployment/fix-windows-update-errors) |

## Related Articles

| Article | Link |
|---|---|
| Windows Update installation capacity | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-update-installation-capacity) |
| Windows Update reset tool for Azure VMs | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-wureset-tool) |
| Fix Windows Update errors | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-client/deployment/fix-windows-update-errors) |
