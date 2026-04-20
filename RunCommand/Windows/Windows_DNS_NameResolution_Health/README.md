# Windows DNS Name Resolution Health

> **Tool ID:** RC-015 · **Bucket:** Network / DNS · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates DNS resolution capabilities on an Azure VM. Checks DNS server configuration, public name resolution, Azure metadata alias resolution, DNS suffix search list, and hosts file overrides. Essential for troubleshooting connectivity issues where DNS is the root cause.

| Check area | What is validated |
|---|---|
| DNS servers | DNS servers configured on NICs |
| Public resolution | Public DNS resolution works (microsoft.com) |
| Metadata alias | Azure metadata alias resolves |
| Suffix list | DNS suffix search list present |
| Hosts overrides | Hosts file overrides absent |

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
  --scripts @Windows_DNS_NameResolution_Health/Windows_DNS_NameResolution_Health.ps1
```

### Mock test
```powershell
.\Windows_DNS_NameResolution_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows DNS Name Resolution Health ===
Check                                        Status
-------------------------------------------- ------
DNS servers configured                       FAIL
Public DNS resolution works                  FAIL
Metadata alias resolves                      WARN
DNS suffix search list present               WARN
Hosts overrides absent                       WARN
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
| **DNS servers configured** FAIL | No DNS server addresses set on any NIC. Name resolution will fail entirely. | Set DNS via `Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter|Select -First 1).ifIndex -ServerAddresses 168.63.129.16` for Azure DNS. | [Troubleshoot app connection](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-app-connection) |
| **Public DNS resolution works** WARN | Cannot resolve external names (microsoft.com). Outbound DNS port 53 may be blocked or DNS servers unresponsive. | `Resolve-DnsName microsoft.com` — if fails, check NSG/firewall rules for UDP/TCP 53 outbound. | [Troubleshoot app connection](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-app-connection) |
| **Metadata alias resolves** WARN | Azure metadata hostname does not resolve. IMDS queries using hostname will fail. Link-local route may be missing. | `Resolve-DnsName 169.254.169.254` — usually resolves via hosts file or link-local. Check `C:\Windows\System32\drivers\etc\hosts`. | [Instance metadata service](https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service) |
| **DNS suffix search list present** WARN | No DNS suffix search list configured. Short-name resolution (e.g., `server1`) will not append domain suffixes. | `Set-DnsClientGlobalSetting -SuffixSearchList @("contoso.com")` — or configure via DHCP/Group Policy. | [Name resolution overview](https://learn.microsoft.com/azure/virtual-network/virtual-networks-name-resolution-for-vms-and-role-instances) |
| **Hosts overrides absent** WARN | Custom entries in `C:\Windows\System32\drivers\etc\hosts` file detected. These override DNS and may cause unexpected resolution. | Review hosts file: `Get-Content $env:SystemRoot\System32\drivers\etc\hosts | Where-Object { $_ -notmatch '^#' -and $_.Trim() }` — remove stale entries. | [Troubleshoot app connection](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-app-connection) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot application connectivity | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-app-connection) |
| Name resolution for VMs | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-network/virtual-networks-name-resolution-for-vms-and-role-instances) |
| Instance metadata service | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service) |
