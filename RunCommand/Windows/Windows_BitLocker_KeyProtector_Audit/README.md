# Windows BitLocker KeyProtector Audit

> **Tool ID:** RC-011 · **Bucket:** Security · **Phase:** 2 (Deep diagnostic)

## What It Does

Audits BitLocker encryption state and key protector configuration on the OS volume. Validates that recovery keys, TPM protectors, and encryption methods meet Azure VM best practices. Critical for VMs where BitLocker was enabled via Azure Disk Encryption or Group Policy.

| Check area | What is validated |
|---|---|
| Volume protection | BitLocker protection is active on C: |
| Key protectors | At least one protector configured |
| Recovery password | Recovery password protector exists for break-glass |
| TPM protector | TPM protector present (hardware-backed) |
| Encryption method | XTS-AES-128 or stronger |
| Conversion status | Volume is fully encrypted (not mid-conversion) |

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
  --scripts @Windows_BitLocker_KeyProtector_Audit/Windows_BitLocker_KeyProtector_Audit.ps1
```

### Mock test
```powershell
.\Windows_BitLocker_KeyProtector_Audit.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows BitLocker KeyProtector Audit ===
Check                                        Status
-------------------------------------------- ------
BitLocker volume protection status           FAIL
Key protector count (C:)                     WARN
Recovery password protector present          FAIL
TPM protector present                        WARN
Encryption method strength                   OK
Conversion status (fully encrypted)          FAIL
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
| **BitLocker volume protection status** FAIL | BitLocker protection is suspended or off. May happen after OS updates, firmware changes, or manual suspension. | `Resume-BitLocker -MountPoint "C:"` or `manage-bde -resume C:` | [Troubleshoot BitLocker boot errors](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-bitlocker-boot-error) |
| **Key protector count (C:)** WARN | Fewer key protectors than expected. Single protector means no backup recovery path. | `Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector` | [Cannot extend encrypted OS volume](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/cannot-extend-encrypted-os-volume) |
| **Recovery password protector present** FAIL | No recovery password protector — system cannot be unlocked if TPM fails or VM is moved. | `Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector` | [BitLocker recovery guide](https://learn.microsoft.com/windows/security/operating-system-security/data-protection/bitlocker/recovery-overview) |
| **TPM protector present** WARN | No TPM-based protector. Azure VMs use vTPM; if missing, encryption relies only on password/recovery key. | `Add-BitLockerKeyProtector -MountPoint "C:" -TpmProtector` (requires vTPM enabled on VM) | [Azure Disk Encryption scenarios](https://learn.microsoft.com/azure/virtual-machines/windows/disk-encryption-overview) |
| **Encryption method strength** WARN | Weak encryption method (below XTS-AES-128). Older volumes may use AES-128-CBC. | Re-encrypt with `manage-bde -changekey C: -EncryptionMethod xts_aes128` or rebuild with stronger policy | [BitLocker Group Policy settings](https://learn.microsoft.com/windows/security/operating-system-security/data-protection/bitlocker/configure) |
| **Conversion status (fully encrypted)** FAIL | Volume encryption is in-progress or paused. Can occur if encryption was interrupted by reboot or disk space issue. | `Resume-BitLocker -MountPoint "C:"` — if stuck, check Event Viewer → Application → BitLocker-API events | [Troubleshoot BitLocker boot errors](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-bitlocker-boot-error) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot BitLocker boot errors on Azure VMs | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-bitlocker-boot-error) |
| Cannot extend encrypted OS volume | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/cannot-extend-encrypted-os-volume) |
| Azure Disk Encryption for Windows VMs | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-machines/windows/disk-encryption-overview) |
| BitLocker recovery overview | [learn.microsoft.com](https://learn.microsoft.com/windows/security/operating-system-security/data-protection/bitlocker/recovery-overview) |
