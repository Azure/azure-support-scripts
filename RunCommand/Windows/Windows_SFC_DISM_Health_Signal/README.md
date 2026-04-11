# Windows SFC & DISM Health Signal

> **Bucket:** OS-Service-Failures / Component-Store-Corruption / Update-Failures

## What It Does

Checks the Windows component store (CBS/WinSxS) and system file integrity to determine if system file corruption is contributing to VM issues:

| Check | What is validated |
|---|---|
| **CBS log integrity marker** | Last 200 lines of `CBS.log` for "corrupt" or "Cannot repair" entries |
| **SFC last run result** | Whether the most recent `sfc /scannow` found violations |
| **Component store health (WinSxS)** | WinSxS folder count — flags bloat at ≥ 30,000 directories |
| **Pending component changes** | Registry key `RebootPending` under CBS — indicates servicing reboot needed |
| **TrustedInstaller service** | Whether the Windows Modules Installer service exists |
| **DISM image health** | Registry `RepairNeeded` flag — set when DISM detects corruption |

The script is **read-only** — it makes no changes to the system.

## How to Run

### Azure Run Command (recommended)
1. Go to your VM in the Azure portal
2. Select **Operations → Run Command → RunPowerShellScript**
3. Paste the contents of `Windows_SFC_DISM_Health_Signal.ps1`
4. Select **Run** and wait for output

### Azure CLI
```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <vm-name> \
  --command-id RunPowerShellScript \
  --scripts @Windows_SFC_DISM_Health_Signal.ps1
```

### Mock / Offline Test
```powershell
.\Windows_SFC_DISM_Health_Signal.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows SFC & DISM Health Signal ===
Check                                        Status
-------------------------------------------- ------
CBS log integrity marker                     FAIL    CorruptSignals=12
SFC last run result in CBS log               WARN    SFC=could not perform requested operation
Component store health (WinSxS)              OK      WinSxSFolders=18500
Pending component changes                    WARN    RebootPending=True
TrustedInstaller service                     OK      Status=Running
DISM image health (registry hint)            FAIL    RepairNeeded=1
-- Decision --
Likely cause severity                        FAIL
=== RESULT: 2 OK / 2 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix |
|---|---|---|
| CBS log corruption ≥ 4 signals | System files are damaged — updates and features may fail silently | Run `sfc /scannow` from an elevated prompt. If it reports "could not fix", proceed with DISM repair |
| SFC result shows violations | Previous scan found files it could not repair | Run `DISM /Online /Cleanup-Image /RestoreHealth` then re-run `sfc /scannow` |
| WinSxS folders ≥ 30,000 | Component store bloat — slows servicing and wastes disk | Run `DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase` |
| RebootPending = True | A servicing operation is waiting for reboot to complete | Reboot the VM, then re-run this script to confirm the pending state clears |
| TrustedInstaller not found | Windows Modules Installer was disabled or removed | Re-enable: `sc config TrustedInstaller start= demand` then `sc start TrustedInstaller` |
| DISM RepairNeeded ≠ 0 | Windows image integrity is compromised | Run `DISM /Online /Cleanup-Image /RestoreHealth`. If that fails, repair from a known-good WIM source |

## Related Articles

- [Repair a Windows VM using the Virtual Machine Repair Commands](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/repair-windows-vm-using-azure-virtual-machine-repair-commands)
- [Use DISM to repair Windows (Windows Server)](https://learn.microsoft.com/troubleshoot/windows-server/deployment/fix-windows-update-errors)
- [Troubleshoot Windows stop error — Bad System Config Info](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/windows-stop-error-bad-system-config-info)
