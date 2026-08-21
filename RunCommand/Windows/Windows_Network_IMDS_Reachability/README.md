# Windows Network + IMDS Reachability

> **Tool ID:** RC-007 · **Bucket:** Network / Cant-RDP-SSH / AGEX · **Phase:** 3 (Config audit)

## What It Does

Validates network stack and Azure endpoint health from inside a Windows VM. Checks for IP-enabled NICs, default route presence, WireServer (168.63.129.16) connectivity, and IMDS (169.254.169.254) accessibility. Critical first-pass diagnostic for VMs with agent/extension failures or network isolation.

| Check area | What is validated |
|---|---|
| NIC | IP-enabled NIC present |
| Default route | Default route 0.0.0.0/0 exists |
| WireServer | WireServer 168.63.129.16 reachable |
| IMDS TCP | IMDS TCP endpoint reachable |
| IMDS HTTP | IMDS metadata response HTTP 200 |

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
  --scripts @Windows_Network_IMDS_Reachability/Windows_Network_IMDS_Reachability.ps1
```

### Mock test
```powershell
.\Windows_Network_IMDS_Reachability.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Network + IMDS Reachability ===
Check                                        Status
-------------------------------------------- ------
IP-enabled NIC present                       OK
Default route 0.0.0.0/0 exists               FAIL
WireServer 168.63.129.16 reachable           FAIL
IMDS TCP endpoint reachable                  FAIL
IMDS metadata response HTTP 200              FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 1 OK / 4 FAIL / 0 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **IP-enabled NIC present** FAIL | No IP-enabled network adapters found. VM has no network connectivity. | Check Device Manager for hidden/disabled NICs. `Get-NetAdapter \| Format-Table Name,Status,LinkSpeed` — if none, the VM may need a NIC reset via Azure portal (redeploy). | [Troubleshoot NIC issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-nic-disabled) |
| **Default route 0.0.0.0/0 exists** FAIL | No default gateway route. Traffic cannot leave the VM subnet. Guest routing table is broken. | `route print 0.0.0.0` — if empty, re-add: `route add 0.0.0.0 mask 0.0.0.0 <gateway-ip> -p`. DHCP renewal may fix: `ipconfig /release && ipconfig /renew`. | [No internet access multi-IP](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/no-internet-access-multi-ip) |
| **WireServer 168.63.129.16 reachable** FAIL | Cannot reach Azure WireServer. Guest agent, extensions, and DHCP will fail. Firewall or route blocking 168.63.129.16. | Check `Get-NetFirewallRule \| Where-Object { $_.Action -eq 'Block' }` for rules blocking 168.63.129.16. Ensure no custom route overrides. | [What is IP 168.63.129.16](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16) |
| **IMDS TCP endpoint reachable** FAIL | TCP connection to 169.254.169.254:80 fails. Link-local route missing or firewall blocks. | Verify route: `route print 169.254.169.254`. Add if missing: `route add 169.254.169.254/32 <gateway>`. Check no proxy intercepts link-local. | [IMDS connection troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-imds-connection) |
| **IMDS metadata response HTTP 200** WARN | TCP connects but HTTP response is not 200. Request header or path issue, or transient IMDS issue. | Test: `Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' -Headers @{Metadata='true'}` — ensure `Metadata:true` header is set. | [Instance metadata service](https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service) |

## Related Articles

| Article | Link |
|---|---|
| Instance metadata service | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service) |
| IMDS connection troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-imds-connection) |
| What is IP 168.63.129.16 | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16) |
