# Windows Driver Signature Integrity Check

> **Tool ID:** RC-018 · **Bucket:** Security · **Phase:** 2 (Deep diagnostic)

## What It Does

Audits driver signing integrity on an Azure VM. Checks for unsigned kernel drivers, code integrity policy violations, driver store consistency, and Secure Boot status. Important for diagnosing BSODs caused by unsigned drivers and for verifying HVCI/VBS compliance.

| Check area | What is validated |
|---|---|
| Code integrity policy | CI policy loaded and accessible |
| Unsigned drivers | Unsigned kernel-mode drivers detected |
| Driver store | pnputil driver inventory integrity |
| CI event errors | Code Integrity event log errors (7 days) |
| WHQL enforcement | Root certificate store accessible for WHQL validation |
| Secure Boot | UEFI Secure Boot enabled |

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
  --scripts @Windows_DriverSignature_Integrity_Check/Windows_DriverSignature_Integrity_Check.ps1
```

### Mock test
```powershell
.\Windows_DriverSignature_Integrity_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Driver Signature Integrity Check ===
Check                                        Status
-------------------------------------------- ------
Code integrity policy loaded                 OK
Unsigned kernel drivers loaded               FAIL
Driver store integrity (pnputil)             OK
Code integrity event errors (7d)             FAIL
WHQL enforcement active                      OK
Secure Boot with UEFI                        WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 3 OK / 2 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Unsigned kernel drivers loaded** FAIL | One or more kernel-mode drivers lack valid signatures. Can cause BSODs under enforced code integrity or Secure Boot. | Identify unsigned drivers: `driverquery /v \| findstr /i "FALSE"`. Update or remove the offending driver. | [Troubleshoot driver-related BSODs](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-stop-error-system-thread-exception-not-handled) |
| **Code integrity event errors (7d)** FAIL | Code Integrity events (Event ID 3033/3034) in CodeIntegrity log — drivers or binaries blocked by CI policy. | `Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents 20` to identify blocked files. Update driver or adjust CI policy. | [Windows Defender Application Control](https://learn.microsoft.com/windows/security/application-security/application-control/windows-defender-application-control/wdac) |
| **Secure Boot with UEFI** WARN | Secure Boot is off or VM uses BIOS (Gen1). Without Secure Boot, unsigned bootloaders could load. | Convert to Gen2 VM (UEFI) if possible. Enable Secure Boot in VM security settings: Azure Portal → VM → Configuration → Security type | [Trusted Launch for Azure VMs](https://learn.microsoft.com/azure/virtual-machines/trusted-launch) |
| **Driver store integrity (pnputil)** WARN | Abnormal driver package count — bloated store can slow boot and cause version conflicts. | `pnputil /enum-drivers` to list. Remove old versions: `pnputil /delete-driver <oem#.inf> /uninstall` | [pnputil reference](https://learn.microsoft.com/windows-server/administration/windows-commands/pnputil) |
| **WHQL enforcement active** WARN | Cannot validate WHQL signatures — root certificate store may be corrupted or incomplete. | Run `certutil -verifyCTL AuthRootWU` to refresh root certificates. If offline, import from a known-good system. | [Manage trusted root certificates](https://learn.microsoft.com/troubleshoot/windows-server/identity/valid-root-ca-certificates-untrusted) |
| **Code integrity policy loaded** WARN | No CI policy loaded — HVCI/VBS memory integrity is not enforced. Informational for non-secured-core VMs. | Enable memory integrity: Settings → Device security → Core isolation → Memory integrity ON | [Core isolation](https://support.microsoft.com/windows/core-isolation-e30ed737-17d8-42f3-a2a9-87521df09b78) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot SYSTEM_THREAD_EXCEPTION_NOT_HANDLED | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-stop-error-system-thread-exception-not-handled) |
| Trusted Launch for Azure VMs | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-machines/trusted-launch) |
| Common blue-screen errors on Azure VMs | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-common-blue-screen-error) |
