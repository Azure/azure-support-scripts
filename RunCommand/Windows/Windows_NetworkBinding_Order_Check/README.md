# Windows Network Binding Order Check

> **Tool ID:** RC-031 · **Bucket:** Networking · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates network adapter binding order and interface metric configuration. Ensures the primary NIC has the lowest metric, no duplicate metrics cause routing ambiguity, DNS registration is correct, and tunnel adapters (ISATAP/Teredo) aren't taking priority. Critical for multi-NIC Azure VMs experiencing intermittent connectivity or wrong-NIC routing.

| Check area | What is validated |
|---|---|
| Primary NIC metric | Primary adapter has lowest interface metric |
| Duplicate metrics | No two adapters share the same metric value |
| DNS registration | NIC registration order for DNS client |
| Binding completeness | TCP/IP binding count on primary adapter |
| Tunnel preference | ISATAP/Teredo not preferred over physical NICs |

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
  --scripts @Windows_NetworkBinding_Order_Check/Windows_NetworkBinding_Order_Check.ps1
```

### Mock test
```powershell
.\Windows_NetworkBinding_Order_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows Network Binding Order Check ===
Check                                        Status
-------------------------------------------- ------
Primary NIC interface metric                 WARN
No duplicate interface metrics               FAIL
DNS client NIC registration order            OK
Primary adapter binding complete             OK
ISATAP/Teredo not preferred                  WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 1 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Primary NIC interface metric** WARN | Primary NIC doesn't have the lowest metric. Traffic may route through the wrong adapter, causing connectivity issues or asymmetric routing. | `Set-NetIPInterface -InterfaceAlias "Ethernet" -InterfaceMetric 10` — set primary NIC lower than all others | [Troubleshoot multi-IP no internet](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/no-internet-access-multi-ip) |
| **No duplicate interface metrics** FAIL | Two or more adapters share the same metric value. Windows picks one arbitrarily, causing non-deterministic routing. | Assign unique metrics: `Get-NetIPInterface \| Set-NetIPInterface -InterfaceMetric <unique_value>` | [Azure VM network binding order](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/no-internet-access-multi-ip) |
| **DNS client NIC registration order** WARN | DNS registration is on a non-primary NIC. DNS updates may register the wrong IP address. | `Set-DnsClient -InterfaceAlias "Ethernet" -RegisterThisConnectionsAddress $true` and disable on secondary NICs | [DNS client configuration](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-cannot-rdp-dns-check) |
| **Primary adapter binding complete** WARN | TCP/IP binding missing on primary adapter. Network protocols may not function correctly. | Open `ncpa.cpl` → right-click primary NIC → Properties → verify TCP/IPv4 and TCP/IPv6 are checked | [Troubleshoot ghosted NIC](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-ghostednic-troubleshooting) |
| **ISATAP/Teredo not preferred** WARN | Tunnel adapters have a lower metric than physical NICs. Traffic may try to route through tunnels instead of direct Azure fabric networking. | Disable tunnels: `netsh interface isatap set state disabled` and `netsh interface teredo set state disabled` | [Configure IPv6 in Windows](https://learn.microsoft.com/troubleshoot/windows-server/networking/configure-ipv6-in-windows) |

## Related Articles

| Article | Link |
|---|---|
| No internet access with multi-IP Azure VM | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/no-internet-access-multi-ip) |
| Ghosted NIC troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-ghostednic-troubleshooting) |
| Configure IPv6 in Windows | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/networking/configure-ipv6-in-windows) |
