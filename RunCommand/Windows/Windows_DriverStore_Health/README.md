# Windows DriverStore Health

> **Tool ID:** RC-019 · **Bucket:** Storage/Drivers · **Phase:** 2 (Deep diagnostic)

## What It Does

Assesses the health of the Windows driver store (FileRepository). Checks store size for bloat, staged package count, PnP devices reporting problems, pending installations, and the Driver Store maintenance service. A bloated or corrupted driver store can cause slow boot, failed driver updates, and disk space issues.

| Check area | What is validated |
|---|---|
| Store size | Driver store folder size in MB |
| Staged packages | Number of staged driver packages (pnputil) |
| Problem devices | PnP devices with error codes |
| Pending installs | Driver installations pending reboot |
| DsmSvc service | Driver Store maintenance service status |

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
  --scripts @Windows_DriverStore_Health/Windows_DriverStore_Health.ps1
```

### Mock test
```powershell
.\Windows_DriverStore_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows DriverStore Health ===
Check                                        Status
-------------------------------------------- ------
Driver store folder size                     WARN
Staged driver packages (pnputil)             WARN
PnP devices with problems                   FAIL
Pending driver installations                 WARN
DriverStore service healthy                  OK
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
| **Driver store folder size** WARN | Driver store exceeds expected size (>2 GB). Accumulation of old driver versions consuming disk space. | `pnputil /enum-drivers` then `pnputil /delete-driver <oem#.inf> /uninstall` for superseded versions. Use DISM: `DISM /online /Cleanup-Image /StartComponentCleanup` | [pnputil command reference](https://learn.microsoft.com/windows-server/administration/windows-commands/pnputil) |
| **Staged driver packages (pnputil)** WARN | Unusually high number of staged packages. Normal is 50-200; hundreds may indicate failed cleanup or repeated driver pushes. | Review with `pnputil /enum-drivers` and remove duplicates. Check Windows Update history for repeated driver install attempts. | [Manage drivers with pnputil](https://learn.microsoft.com/windows-server/administration/windows-commands/pnputil) |
| **PnP devices with problems** FAIL | One or more devices have error codes (yellow bang in Device Manager). Missing drivers, conflicts, or hardware issues. | `Get-PnpDevice \| Where-Object { $_.Status -ne 'OK' }` to identify. Update driver or disable problematic device. | [Troubleshoot Mellanox driver crash](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-virtual-machine-mellanox-driver-crash-troubleshooting) |
| **Pending driver installations** WARN | Driver installations are pending reboot. May block further updates until completed. | Reboot the VM to complete pending installations: `Restart-Computer` | [Extension supported OS and driver requirements](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/extension-supported-os) |
| **DriverStore service healthy** WARN | DsmSvc (Device Setup Manager) not running. Optional on some SKUs but needed for Plug and Play device setup. | `Set-Service DsmSvc -StartupType Automatic; Start-Service DsmSvc` (if service exists on this Windows edition) | [Device installation overview](https://learn.microsoft.com/windows-hardware/drivers/install/overview-of-device-and-driver-installation) |

## Related Articles

| Article | Link |
|---|---|
| pnputil command reference | [learn.microsoft.com](https://learn.microsoft.com/windows-server/administration/windows-commands/pnputil) |
| Mellanox driver crash troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-virtual-machine-mellanox-driver-crash-troubleshooting) |
| DISM image cleanup | [learn.microsoft.com](https://learn.microsoft.com/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder) |
