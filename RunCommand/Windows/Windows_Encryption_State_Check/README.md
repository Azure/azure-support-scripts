# Windows Encryption State Check

> **Tool ID:** RC-008 · **Bucket:** Azure-Encryption / Cant-RDP-SSH / Disk · **Phase:** 2

## What It Does

Reports BitLocker and Azure Disk Encryption (ADE) state across all volumes:

| Check area | What is validated |
|---|---|
| **BitLocker volumes** | Protection status + conversion state per drive |
| **ADE extension** | Handler registry state (Ready/NotReady/Unresponsive) |
| **ADE settings** | Registry presence + OS drive encryption state |

Read-only — no changes to the system.

## Key Concept

An encrypted OS disk that has lost Key Vault access will prevent the VM from booting in a recoverable state. This script surfaces whether ADE is active and in what state — critical context before any disk or extension remediation.

## How to Run

### Azure Run Command
1. Portal → VM → **Operations → Run Command → RunPowerShellScript**
2. Paste `Windows_Encryption_State_Check.ps1` → **Run**

### Azure CLI
```bash
az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript --scripts @Windows_Encryption_State_Check.ps1
```

### Mock / Offline Test
```powershell
.\Windows_Encryption_State_Check.ps1 -MockConfig .\mock_config_sample.json
```

## Sample Output (ADE Active, Extension Unresponsive)

```
=== Windows Encryption State Check ===
Check                                        Status
-------------------------------------------- ------
-- BitLocker Volume Status --
C: Encryption: Protected                     WARN   Conv=FullyEncrypted
F: Encryption: Protected                     WARN   Conv=EncryptionInProgress
-- Azure Disk Encryption (ADE) Extension --
ADE: Microsoft.Azure.Security.AzureDiskEnc.. FAIL   Seq=2 State=Unresponsive
-- ADE Encryption Settings --
ADE settings registry present                WARN   ADE was or is active on this VM
OS drive (C:) encrypted by ADE               WARN

=== RESULT: 0 OK / 1 FAIL / 4 WARN ===
```

## Interpretation Guide

| Condition | Meaning | Next Step |
|---|---|---|
| Volume Protected (WARN) | ADE or BitLocker active — normal if intentional | Verify Key Vault access and KEK/BEK availability |
| Conversion in progress | Encryption/decryption not complete | Do NOT resize or stop VM — wait for completion |
| ADE Unresponsive | Extension hung | Try disable/re-enable from portal; check Key Vault firewall |
| ADE settings present + OS encrypted | ADE managing OS disk | Verify Key Vault is accessible from VM subnet |

## Related Articles
- [Troubleshoot Azure Disk Encryption](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/troubleshoot-bitlocker-boot-error)
- [Azure Disk Encryption for Windows VMs](https://learn.microsoft.com/azure/virtual-machines/windows/disk-encryption-overview)
- [Cannot extend an encrypted OS volume](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/cannot-extend-encrypted-os-volume)
