# Windows Domain Join Readiness

> **Tool ID:** RC-017 · **Bucket:** Identity · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates that an Azure VM is properly domain-joined and can communicate with its Active Directory domain controller. Checks DNS suffix configuration, DC reachability, secure channel health, Netlogon service state, and computer account password age. Critical for VMs that lose domain trust or fail GPO processing after long periods offline.

| Check area | What is validated |
|---|---|
| Domain membership | Computer is joined to a domain |
| DNS suffix | DNS suffixes configured for domain resolution |
| DC reachability | Domain controller is reachable via LDAP/Kerberos |
| Secure channel | Secure channel between VM and DC is healthy |
| Netlogon | Netlogon service is running |
| Account password age | Computer account password age (default max: 30 days) |

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
  --scripts @Windows_DomainJoin_Readiness/Windows_DomainJoin_Readiness.ps1
```

### Mock test
```powershell
.\Windows_DomainJoin_Readiness.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Domain Join Readiness ===
Check                                        Status
-------------------------------------------- ------
Computer domain membership                   FAIL
DNS suffix configured                        WARN
Domain controller reachable                  FAIL
Secure channel healthy                       FAIL
Netlogon service running                     FAIL
Computer account password age                WARN
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
| **Computer domain membership** FAIL | VM is not joined to any domain (WORKGROUP). May have been provisioned without domain join or was removed. | Join domain: `Add-Computer -DomainName contoso.com -Credential (Get-Credential) -Restart` | [Troubleshoot broken secure channel](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-broken-secure-channel) |
| **DNS suffix configured** WARN | No DNS suffix configured — domain name resolution may fail. VM cannot find DCs by SRV records. | Set DNS suffix: `Set-DnsClientGlobalSetting -SuffixSearchList @("contoso.com")` or configure via DHCP/GPO | [Configure DNS for domain join](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-cannot-rdp-dns-check) |
| **Domain controller reachable** FAIL | Cannot reach any DC — DNS misconfiguration, NSG blocking LDAP/Kerberos (TCP 389/88), or no line-of-sight to DC network. | Verify DNS points to DC: `nslookup _ldap._tcp.dc._msdcs.contoso.com`. Check NSG allows TCP 88, 389, 636, 445, 3268 to DC subnet. | [Troubleshoot RDP — DNS check](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-cannot-rdp-dns-check) |
| **Secure channel healthy** FAIL | Trust between VM and domain is broken. Common after VM restored from old snapshot or powered off > 60 days. | `Test-ComputerSecureChannel -Repair -Credential (Get-Credential)` — if fails, re-join: `Reset-ComputerMachinePassword -Credential (Get-Credential)` | [Troubleshoot broken secure channel](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-broken-secure-channel) |
| **Netlogon service running** FAIL | Netlogon service is stopped — domain authentication, GPO, and DC discovery won't work. | `Set-Service Netlogon -StartupType Automatic; Start-Service Netlogon` | [Netlogon service overview](https://learn.microsoft.com/troubleshoot/windows-server/networking/verify-srv-dns-records-have-been-created) |
| **Computer account password age** WARN | Computer password is older than 30 days. While auto-rotation normally handles this, long-powered-off VMs may exceed the DC's tolerance. | `Reset-ComputerMachinePassword -Server <DC-name> -Credential (Get-Credential)` | [Machine account password process](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-broken-secure-channel) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot broken secure channel on Azure VM | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-broken-secure-channel) |
| Cannot sign in with domain credentials | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-cannot-sign-into-account) |
| Azure VM DNS resolution troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-cannot-rdp-dns-check) |
