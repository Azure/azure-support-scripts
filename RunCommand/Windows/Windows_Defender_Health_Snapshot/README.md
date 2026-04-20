# Windows Defender Health Snapshot

> **Tool ID:** RC-015 · **Bucket:** Security · **Phase:** 2 (Deep diagnostic)

## What It Does

Checks the health of Microsoft Defender Antivirus on an Azure VM. Validates that real-time protection is active, definitions are current, and no threats are detected. Critical for security compliance and identifying VMs with degraded endpoint protection.

| Check area | What is validated |
|---|---|
| Service state | Defender (WinDefend) service running |
| Real-time protection | Real-time monitoring is enabled |
| Definition freshness | Antivirus signatures are not stale |
| Full scan recency | A full scan has been completed recently |
| Tamper protection | Tamper protection prevents unauthorized changes |
| Active threats | No unresolved malware detections |

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
  --scripts @Windows_Defender_Health_Snapshot/Windows_Defender_Health_Snapshot.ps1
```

### Mock test
```powershell
.\Windows_Defender_Health_Snapshot.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Defender Health Snapshot ===
Check                                        Status
-------------------------------------------- ------
Defender service running                     FAIL
Real-time protection enabled                 FAIL
Antivirus definitions age                    WARN
Full scan completed recently                 WARN
Tamper protection enabled                    FAIL
No active threats detected                   FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 4 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Defender service running** FAIL | WinDefend service stopped or disabled. Common when third-party AV is installed or GPO disables Defender. | `Set-Service WinDefend -StartupType Automatic; Start-Service WinDefend` — if third-party AV is present, Defender enters passive mode by design | [Defender compatibility with other AV](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/microsoft-defender-antivirus-compatibility) |
| **Real-time protection enabled** FAIL | Real-time monitoring turned off by policy, user, or third-party AV conflict. | `Set-MpPreference -DisableRealtimeMonitoring $false` or check GPO: Computer Config → Admin Templates → Windows Defender → Real-time Protection | [Configure real-time protection](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/configure-real-time-protection-microsoft-defender-antivirus) |
| **Antivirus definitions age** WARN | Signature definitions are older than expected. VM may lack internet for auto-update, or WSUS is misconfigured. | `Update-MpSignature` — if offline, download definitions from [Security Intelligence Updates](https://www.microsoft.com/wdsi/defenderupdates) | [Manage Defender updates](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/manage-updates-baselines-microsoft-defender-antivirus) |
| **Full scan completed recently** WARN | No recent full scan. Quick scans run on schedule but full scans may not be configured. | `Start-MpScan -ScanType FullScan` or set scheduled full scan via GPO/PowerShell | [Schedule scans](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/schedule-antivirus-scans) |
| **Tamper protection enabled** FAIL | Tamper protection is off — malware could disable Defender silently. | Enable via Microsoft 365 Defender portal (cloud-managed) or `Set-MpPreference -TamperProtection Enabled` if available | [Protect security settings with tamper protection](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/prevent-changes-to-security-settings-with-tamper-protection) |
| **No active threats detected** FAIL | Unresolved malware detections exist. VM may have threats in quarantine or active infections. | `Get-MpThreat` to list threats, then `Remove-MpThreat` or manual investigation | [Respond to threats](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/respond-machine-alerts) |

## Related Articles

| Article | Link |
|---|---|
| Microsoft Defender AV compatibility | [learn.microsoft.com](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/microsoft-defender-antivirus-compatibility) |
| Configure real-time protection | [learn.microsoft.com](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/configure-real-time-protection-microsoft-defender-antivirus) |
| Manage Defender signature updates | [learn.microsoft.com](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/manage-updates-baselines-microsoft-defender-antivirus) |
