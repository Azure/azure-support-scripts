# Windows SMB Client Health

> **Tool ID:** RC-043 · **Bucket:** Networking · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates SMB client configuration and connectivity on an Azure VM. Checks that the Workstation service is running, SMB signing policy is set, the legacy SMBv1 protocol is disabled, multichannel is configured, and firewall rules allow file sharing. Critical for VMs experiencing file share access failures or Azure Files mount issues.

| Check area | What is validated |
|---|---|
| Workstation service | LanmanWorkstation service running |
| SMB signing | SMB signing required per client policy |
| SMBv1 disabled | Legacy SMBv1 protocol is not active |
| Active connections | Current SMB session count (informational) |
| Multichannel | SMB Multichannel enabled for multi-NIC VMs |
| Firewall rules | File sharing firewall rules enabled |

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
  --scripts @Windows_SMB_Client_Health/Windows_SMB_Client_Health.ps1
```

### Mock test
```powershell
.\Windows_SMB_Client_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows SMB Client Health ===
Check                                        Status
-------------------------------------------- ------
LanmanWorkstation service                    FAIL
SMB signing required (client)                WARN
SMBv1 protocol disabled                      FAIL
SMB connections active                       OK
Multichannel enabled                         WARN
File sharing firewall rules                  FAIL
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
| **LanmanWorkstation service** FAIL | Workstation (SMB client) service is stopped or disabled. File share access, mapped drives, and Azure Files mounts will fail. | `Set-Service LanmanWorkstation -StartupType Automatic; Start-Service LanmanWorkstation` | [Troubleshoot Azure Files connectivity (Windows)](https://learn.microsoft.com/troubleshoot/azure/azure-storage/files/connectivity/smb-troubleshoot-windows) |
| **SMB signing required (client)** WARN | Client-side SMB signing is not required. While connections work, unsigned SMB traffic is vulnerable to MITM attacks. | `Set-SmbClientConfiguration -RequireSecuritySignature $true -Force` | [SMB signing overview](https://learn.microsoft.com/troubleshoot/windows-server/networking/overview-server-message-block-signing) |
| **SMBv1 protocol disabled** FAIL | SMBv1 is active — deprecated, insecure, and a ransomware attack vector (WannaCry, NotPetya). Azure Files requires SMB 2.1+. | `Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force; Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol` | [Detect and disable SMBv1](https://learn.microsoft.com/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3) |
| **SMB connections active** WARN | Zero active connections may be normal (no shares mounted) or indicate access failures. Informational check. | `Get-SmbConnection` to verify. If shares should be mounted, test: `Test-Path \\server\share` | [Azure Files troubleshooting](https://learn.microsoft.com/troubleshoot/azure/azure-storage/files/connectivity/smb-troubleshoot-windows) |
| **Multichannel enabled** WARN | SMB Multichannel is disabled. VMs with multiple NICs or high-bandwidth NICs benefit from parallel SMB channels. | `Set-SmbClientConfiguration -EnableMultichannel $true -Force` | [SMB Multichannel overview](https://learn.microsoft.com/azure/storage/files/smb-multichannel-performance) |
| **File sharing firewall rules** FAIL | Windows Firewall is blocking SMB traffic (TCP 445). File share connections will fail. | `Enable-NetFirewallRule -Group "File and Printer Sharing"` or create specific rule: `New-NetFirewallRule -Name SMB -Direction Inbound -Protocol TCP -LocalPort 445 -Action Allow` | [Troubleshoot Azure Files connectivity](https://learn.microsoft.com/troubleshoot/azure/azure-storage/files/connectivity/smb-troubleshoot-windows) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot Azure Files on Windows (SMB) | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/azure-storage/files/connectivity/smb-troubleshoot-windows) |
| Detect and disable SMBv1 | [learn.microsoft.com](https://learn.microsoft.com/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3) |
| SMB Multichannel for Azure Files | [learn.microsoft.com](https://learn.microsoft.com/azure/storage/files/smb-multichannel-performance) |
| SMB signing overview | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/networking/overview-server-message-block-signing) |
