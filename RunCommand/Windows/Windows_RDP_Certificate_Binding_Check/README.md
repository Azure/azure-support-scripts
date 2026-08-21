# Windows RDP Certificate Binding Check

> **Tool ID:** RC-036 · **Bucket:** RDP / Connectivity · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates RDP certificate binding and TLS readiness. Checks certificate thumbprint configuration, certificate presence in the local machine store, expiry status, NLA settings, and RDP port listener. Critical for diagnosing RDP failures caused by expired or missing certificates.

| Check area | What is validated |
|---|---|
| Cert thumbprint | RDP certificate thumbprint configured |
| Cert present | Bound certificate present in LM\\My store |
| Cert expiry | Bound certificate not near expiry |
| NLA setting | NLA setting readable |
| Port listener | RDP port 3389 listening |

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
  --scripts @Windows_RDP_Certificate_Binding_Check/Windows_RDP_Certificate_Binding_Check.ps1
```

### Mock test
```powershell
.\Windows_RDP_Certificate_Binding_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows RDP Certificate Binding Check ===
Check                                        Status
-------------------------------------------- ------
RDP certificate thumbprint configured        WARN
Bound certificate present in LM\My           FAIL
Bound certificate not near expiry            WARN
NLA setting readable                         OK
RDP port 3389 listening                      FAIL
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
| **RDP certificate thumbprint configured** WARN | No certificate thumbprint is set in RDP-Tcp registry. RDP will use a self-signed cert (may cause warnings but usually works). | Check: `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v SSLCertificateSHA1Hash`. If needed, bind a certificate. | [Troubleshoot RDP general error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-general-error) |
| **Bound certificate present in LM\\My** FAIL | Certificate thumbprint is configured but the certificate is missing from `Cert:\LocalMachine\My`. RDP handshake will fail. | Re-enroll or import the certificate. Quick fix: clear thumbprint to fall back to self-signed: `reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v SSLCertificateSHA1Hash /f` | [Reset RDP](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/reset-rdp) |
| **Bound certificate not near expiry** WARN | Certificate expires within 30 days. RDP will fail after expiry. | Renew the certificate before expiry. `Get-ChildItem Cert:\LocalMachine\My \| Where-Object { $_.NotAfter -lt (Get-Date).AddDays(30) }` to identify. | [Troubleshoot RDP general error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-general-error) |
| **NLA setting readable** WARN | Cannot read NLA (UserAuthentication) registry value. NLA enforcement state unknown. | Check: `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication` — set to 1 for NLA enabled. | [CredSSP encryption oracle remediation](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/credssp-encryption-oracle-remediation) |
| **RDP port 3389 listening** FAIL | Nothing listening on TCP 3389. TermService may be stopped, port changed, or another service conflict. | `Get-Service TermService \| Start-Service`. If port changed: `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber`. | [Reset RDP](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/reset-rdp) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot RDP general error | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-general-error) |
| Reset RDP configuration | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/reset-rdp) |
| CredSSP encryption oracle remediation | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/credssp-encryption-oracle-remediation) |
