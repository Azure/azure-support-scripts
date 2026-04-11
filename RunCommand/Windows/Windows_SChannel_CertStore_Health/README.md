# Windows SChannel CertStore Health

> **Tool ID:** RC-041 · **Bucket:** Security/TLS · **Phase:** 2 (Deep diagnostic)

## What It Does

Audits SChannel (TLS/SSL) configuration and certificate store health. Validates that TLS 1.2 is enabled for both client and server roles, SSL 3.0 is disabled, the Personal certificate store has valid certs, the Root CA store is accessible, and no expired certificates remain. Essential for diagnosing RDP TLS handshake failures and HTTPS connectivity issues.

| Check area | What is validated |
|---|---|
| TLS 1.2 (client) | TLS 1.2 enabled for outbound connections |
| TLS 1.2 (server) | TLS 1.2 enabled for inbound connections |
| SSL 3.0 | Legacy SSL 3.0 disabled (POODLE vulnerable) |
| Personal certs | Certificates in Personal (My) store |
| Root CA store | Root certificate authority store accessible |
| Expired certs | No expired certificates in Personal store |

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
  --scripts @Windows_SChannel_CertStore_Health/Windows_SChannel_CertStore_Health.ps1
```

### Mock test
```powershell
.\Windows_SChannel_CertStore_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows SChannel CertStore Health ===
Check                                        Status
-------------------------------------------- ------
TLS 1.2 enabled (client)                     FAIL
TLS 1.2 enabled (server)                     FAIL
SSL 3.0 disabled                             FAIL
Personal cert store populated                OK
Root CA store accessible                     OK
Expired certs in Personal store              WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 3 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **TLS 1.2 enabled (client)** FAIL | TLS 1.2 disabled for client connections. Outbound HTTPS calls to Azure services will fail if they require TLS 1.2. | `New-Item "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" -Force; Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" -Name Enabled -Value 1 -Type DWord` | [Transport Layer Security registry settings](https://learn.microsoft.com/windows-server/security/tls/tls-registry-settings) |
| **TLS 1.2 enabled (server)** FAIL | TLS 1.2 disabled for server role. RDP and any TLS-serving applications cannot negotiate TLS 1.2. Causes RDP internal errors. | Same registry path with `\Server` instead of `\Client`. Set `Enabled=1` and `DisabledByDefault=0`. | [Troubleshoot RDP internal error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-internal-error) |
| **SSL 3.0 disabled** FAIL | SSL 3.0 is still enabled — vulnerable to POODLE attack. Security compliance risk. | `New-Item "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server" -Force; Set-ItemProperty ... -Name Enabled -Value 0` | [Disable SSL 3.0](https://learn.microsoft.com/troubleshoot/developer/webapps/iis/health-diagnostic-performance/disable-ssl-poodle) |
| **Personal cert store populated** WARN | No certificates in Personal store. RDP uses a self-signed cert by default — if missing, RDP TLS handshake fails. | Check: `Get-ChildItem Cert:\LocalMachine\My`. Regenerate RDP cert: `wmic /namespace:\\root\cimv2\TerminalServices PATH Win32_TSGeneralSetting CALL SSLCertificateSHA1HashType 2` | [CredSSP encryption oracle remediation](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/credssp-encryption-oracle-remediation) |
| **Root CA store accessible** WARN | Root certificate store inaccessible or empty. TLS certificate chain validation will fail for all HTTPS connections. | `certutil -verifyCTL AuthRootWU` to refresh. If offline, import roots from a known-good machine. | [Manage trusted root certificates](https://learn.microsoft.com/troubleshoot/windows-server/identity/valid-root-ca-certificates-untrusted) |
| **Expired certs in Personal store** WARN | Expired certificates present. If RDP is bound to an expired cert, clients will get TLS errors. | `Get-ChildItem Cert:\LocalMachine\My \| Where-Object { $_.NotAfter -lt (Get-Date) }` — remove or renew expired certs | [Troubleshoot RDP internal error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-internal-error) |

## Related Articles

| Article | Link |
|---|---|
| TLS registry settings reference | [learn.microsoft.com](https://learn.microsoft.com/windows-server/security/tls/tls-registry-settings) |
| Troubleshoot RDP internal error | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-internal-error) |
| CredSSP encryption oracle remediation | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/credssp-encryption-oracle-remediation) |
