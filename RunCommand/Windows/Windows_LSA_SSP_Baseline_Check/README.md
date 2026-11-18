# Windows LSA SSP Baseline Check

> **Tool ID:** RC-027 · **Bucket:** Security · **Phase:** 2 (Deep diagnostic)

## What It Does

Audits the Local Security Authority (LSA) configuration for security hardening. Checks RunAsPPL protection, Credential Guard status, registered Security Support Providers (SSPs), and LSASS audit mode. Detects unauthorized SSP injection — a common credential theft technique — and validates that modern protections are enabled.

| Check area | What is validated |
|---|---|
| RunAsPPL | LSA runs as Protected Process Light |
| Credential Guard | VBS Credential Guard active |
| Security packages | Registered SSPs match expected baseline |
| Unauthorized SSPs | No unknown SSPs loaded |
| LSASS audit | LSASS audit mode level |

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
  --scripts @Windows_LSA_SSP_Baseline_Check/Windows_LSA_SSP_Baseline_Check.ps1
```

### Mock test
```powershell
.\Windows_LSA_SSP_Baseline_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows LSA SSP Baseline Check ===
Check                                        Status
-------------------------------------------- ------
LSA RunAsPPL protection                      FAIL
Credential Guard status                      WARN
Security packages registered                 OK
No unauthorized SSPs loaded                  FAIL
LSASS audit mode                             WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 1 OK / 2 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **LSA RunAsPPL protection** FAIL | LSA is not running as a Protected Process Light. Credential extraction tools (Mimikatz) can read LSASS memory. | `Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name RunAsPPL -Value 1 -Type DWord` then reboot | [Configure LSA protection](https://learn.microsoft.com/windows-server/security/credentials-protection-and-management/configuring-additional-lsa-protection) |
| **Credential Guard status** WARN | VBS Credential Guard is not active. NTLM hashes and Kerberos tickets are stored in plain LSASS memory. | Enable via GPO: Computer Config → Admin Templates → System → Device Guard → Turn On Virtualization Based Security. Requires UEFI, Secure Boot, and Gen2 VM. | [Credential Guard overview](https://learn.microsoft.com/windows/security/identity-protection/credential-guard/) |
| **No unauthorized SSPs loaded** FAIL | Unknown Security Support Providers detected in `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Security Packages`. May indicate credential theft malware. | Review `Security Packages` reg value. Known-good: `kerberos`, `msv1_0`, `schannel`, `wdigest`, `tspkg`, `pku2u`, `cloudAP`. Remove unknown entries. | [SSP/AP overview](https://learn.microsoft.com/windows-server/security/windows-authentication/security-support-provider-interface-architecture) |
| **LSASS audit mode** WARN | LSASS audit logging is disabled. Cannot detect credential access attempts. | `Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe" -Name AuditLevel -Value 8 -Type DWord` | [Audit LSASS access](https://learn.microsoft.com/windows-server/security/credentials-protection-and-management/configuring-additional-lsa-protection#auditing-mode) |
| **Security packages registered** WARN | Non-standard packages present. May be legitimate (third-party SSO) or suspicious. Cross-reference with installed software. | `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "Security Packages"` — validate each entry against known-good list | [SSP/AP architecture](https://learn.microsoft.com/windows-server/security/windows-authentication/security-support-provider-interface-architecture) |

## Related Articles

| Article | Link |
|---|---|
| Configure LSA additional protection | [learn.microsoft.com](https://learn.microsoft.com/windows-server/security/credentials-protection-and-management/configuring-additional-lsa-protection) |
| Credential Guard overview | [learn.microsoft.com](https://learn.microsoft.com/windows/security/identity-protection/credential-guard/) |
| Troubleshoot RDP access denied | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-access-denied) |
