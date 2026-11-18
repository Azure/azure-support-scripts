# Windows Boot Policy Drift Check

> **Bucket:** Boot-Failures / BCD-Corruption / Secure-Boot

## What It Does

Validates that the Boot Configuration Data (BCD) store is intact and has not drifted from expected Azure VM defaults:

| Check | What is validated |
|---|---|
| **BCD store accessible** | `bcdedit /enum {bootmgr}` succeeds — store is not corrupt |
| **Default boot entry** | Default OS entry points to a valid Windows partition |
| **Secure Boot state** | UEFI Secure Boot is enabled (expected ON for Gen2 VMs) |
| **Boot status policy** | Set to `IgnoreAllFailures` — prevents recovery loops in Azure |
| **Recovery sequence** | Recovery sequence entry is configured |
| **Integrity checks** | `nointegritychecks` is not set — driver signing enforced |

The script is **read-only** — it makes no changes to the system.

## How to Run

### Azure Run Command (recommended)
1. Go to your VM in the Azure portal
2. Select **Operations → Run Command → RunPowerShellScript**
3. Paste the contents of `Windows_BootPolicy_Drift_Check.ps1`
4. Select **Run** and wait for output

### Azure CLI
```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <vm-name> \
  --command-id RunPowerShellScript \
  --scripts @Windows_BootPolicy_Drift_Check.ps1
```

### Mock / Offline Test
```powershell
.\Windows_BootPolicy_Drift_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Boot Policy Drift Check ===
Check                                        Status
-------------------------------------------- ------
BCD store accessible                         OK
Default boot entry points to Windows         FAIL
Secure Boot state                            WARN    SecureBoot=OFF
Boot status policy (ignore failures)         WARN    default
Recovery sequence configured                 WARN    absent
Integrity checks enabled                     OK      not set (default=on)
-- Decision --
Likely cause severity                        FAIL
=== RESULT: 2 OK / 1 FAIL / 3 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix |
|---|---|---|
| BCD store not accessible | BCD is corrupt or missing | Use [Azure VM repair commands](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/repair-windows-vm-using-azure-virtual-machine-repair-commands) to attach OS disk and rebuild BCD: `bcdedit /rebuildbcd` |
| Default entry not pointing to Windows | BCD hijacked by recovery or third-party bootloader | Run `bcdedit /set {default} osdevice partition=C:` from repair disk |
| Secure Boot OFF on Gen2 VM | Secure Boot was disabled — may block Windows Update or driver loading | Re-enable via Azure portal: VM → Settings → Configuration → Secure Boot |
| Boot status policy not IgnoreAllFailures | VM may enter recovery loop on transient boot issues | Set: `bcdedit /set {default} bootstatuspolicy IgnoreAllFailures` |
| Recovery sequence absent | No recovery fallback if boot fails | Usually harmless in Azure (serial console is the recovery path) |
| Integrity checks disabled | Unsigned drivers allowed — security risk and may cause BSOD | Remove override: `bcdedit /deletevalue {default} nointegritychecks` |

## Related Articles

- [Troubleshoot Windows boot failure](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/windows-boot-failure)
- [Boot error — Invalid image hash](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/windows-boot-error-invalid-image-hash)
- [Repair Windows VM boot configuration data](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/virtual-machines-windows-repair-boot-configuration-data)
