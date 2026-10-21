# Windows Domain Trust Secure Channel Check

> **Tool ID:** RC-016 · **Bucket:** Identity / Domain · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates Active Directory domain trust and secure channel health. Checks domain join state, Netlogon service, secure channel connectivity, DC discovery, and DNS SRV records. Critical for domain-joined VMs experiencing login failures or trust relationship errors.

| Check area | What is validated |
|---|---|
| Domain join | Machine is domain joined |
| Netlogon | Netlogon service running |
| Secure channel | Secure channel healthy (Test-ComputerSecureChannel) |
| DC discovery | DC discovery succeeds (nltest /dsgetdc) |
| DNS SRV | DNS SRV lookup signal for DC |

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
  --scripts @Windows_Domain_Trust_SecureChannel_Check/Windows_Domain_Trust_SecureChannel_Check.ps1
```

### Mock test
```powershell
.\Windows_Domain_Trust_SecureChannel_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Domain Trust + Secure Channel ===
Check                                        Status
-------------------------------------------- ------
Machine is domain joined                     OK
Netlogon service running                     OK
Secure channel healthy                       FAIL
DC discovery succeeds                        FAIL
DNS SRV lookup signal                        OK
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 3 OK / 2 FAIL / 0 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Machine is domain joined** WARN | VM is not domain joined (workgroup). Domain trust checks are not applicable. | If expected: join to domain via `Add-Computer -DomainName <domain>`. If workgroup is intentional, this is informational. | [Troubleshoot domain join](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-cannot-sign-into-account) |
| **Netlogon service running** WARN | Netlogon service stopped. Domain authentication and DC discovery cannot function. | `Set-Service Netlogon -StartupType Automatic; Start-Service Netlogon` | [Troubleshoot broken secure channel](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-broken-secure-channel) |
| **Secure channel healthy** FAIL | Trust relationship between the VM and domain is broken. Users cannot authenticate. | `Test-ComputerSecureChannel -Repair -Credential (Get-Credential)` with domain admin creds. If fails, rejoin: `Remove-Computer; Add-Computer -DomainName <domain>` | [Troubleshoot broken secure channel](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-broken-secure-channel) |
| **DC discovery succeeds** FAIL | VM cannot locate a domain controller. DNS failure, network isolation, or DC is down. | `nltest /dsgetdc:<domain>` to diagnose. Check DNS points to DC. Verify network connectivity to DC IP. | [Troubleshoot broken secure channel](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-broken-secure-channel) |
| **DNS SRV lookup signal** WARN | DNS SRV records for `_ldap._tcp.dc._msdcs.<domain>` not resolving. DNS may not point to a DC-aware resolver. | `nslookup -type=SRV _ldap._tcp.dc._msdcs.<domain>` — configure DNS to point to DC IP addresses. | [Troubleshoot RDP sign-in](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-cannot-sign-into-account) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot broken secure channel | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-broken-secure-channel) |
| Troubleshoot RDP cannot sign into account | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-cannot-sign-into-account) |
