# Windows TLS Cipher RDP Compatibility Audit

> **Tool ID:** RC-049 · **Bucket:** RDP / Security · **Phase:** 2 (Deep diagnostic)

## What It Does

Audits TLS protocol configuration and RDP compatibility settings. Checks RDP port listener, NLA enforcement, SecurityLayer mode, TLS 1.2 server enablement, and TLS 1.0 legacy presence. Essential for diagnosing RDP handshake failures caused by TLS misconfiguration or disabled protocols.

| Check area | What is validated |
|---|---|
| RDP listener | RDP 3389 listening |
| NLA | NLA setting present |
| SecurityLayer | SecurityLayer valid (0/1/2) |
| TLS 1.2 | TLS 1.2 server enabled |
| TLS 1.0 | TLS 1.0 server enabled (legacy check) |

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
  --scripts @Windows_TLS_Cipher_RDP_Compatibility_Audit/Windows_TLS_Cipher_RDP_Compatibility_Audit.ps1
```

### Mock test
```powershell
.\Windows_TLS_Cipher_RDP_Compatibility_Audit.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows TLS + RDP Compatibility Audit ===
Check                                        Status
-------------------------------------------- ------
RDP 3389 listening                           FAIL
NLA setting present                          WARN
SecurityLayer valid (0/1/2)                  WARN
TLS 1.2 server enabled                       FAIL
TLS 1.0 server enabled                       WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 2 FAIL / 3 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **RDP 3389 listening** FAIL | Nothing listening on TCP 3389. TermService stopped, port changed, or conflict. | `Get-Service TermService \| Start-Service`. Check port: `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber` | [Troubleshoot RDP general error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-general-error) |
| **NLA setting present** WARN | NLA (UserAuthentication) registry value missing or unreadable. Cannot determine if NLA is enforced. | Set NLA: `reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 1 /f` | [CredSSP encryption oracle remediation](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/credssp-encryption-oracle-remediation) |
| **SecurityLayer valid (0/1/2)** WARN | SecurityLayer value is not in expected range. 0=RDP, 1=Negotiate, 2=TLS. Unexpected values may cause client incompatibility. | `reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v SecurityLayer /t REG_DWORD /d 2 /f` for TLS mode | [Troubleshoot RDP internal error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-internal-error) |
| **TLS 1.2 server enabled** FAIL | TLS 1.2 is disabled on the server. Modern RDP clients require TLS 1.2. Connections will fail. | Enable: `New-Item "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" -Force; New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" -Name Enabled -Value 1 -Type DWord` | [TLS best practices](https://learn.microsoft.com/windows-server/security/tls/tls-registry-settings) |
| **TLS 1.0 server enabled** WARN | TLS 1.0 is still enabled. Security risk — legacy clients may connect but protocol has known vulnerabilities. | Disable after confirming no legacy clients: set `Enabled=0` under `HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server` | [TLS registry settings](https://learn.microsoft.com/windows-server/security/tls/tls-registry-settings) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot RDP general error | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-general-error) |
| Troubleshoot RDP internal error | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-internal-error) |
| CredSSP encryption oracle remediation | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/credssp-encryption-oracle-remediation) |
| TLS registry settings | [learn.microsoft.com](https://learn.microsoft.com/windows-server/security/tls/tls-registry-settings) |
