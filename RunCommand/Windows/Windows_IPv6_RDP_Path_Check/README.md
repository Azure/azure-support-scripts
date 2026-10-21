# Windows IPv6 RDP Path Check

> **Tool ID:** RC-025 · **Bucket:** Networking/RDP · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates IPv6 configuration and its impact on RDP connectivity. Checks IPv6 enablement on the primary NIC, address assignment, RDP listener binding, firewall rules for IPv6 RDP, dual-stack DNS resolution, and presence of transition technologies (Teredo/ISATAP). Important for VMs where RDP fails due to IPv6 misconfigurations or when IPv6 takes priority over IPv4.

| Check area | What is validated |
|---|---|
| IPv6 enabled | IPv6 protocol active on primary NIC |
| IPv6 addresses | Global IPv6 addresses assigned |
| RDP listener | RDP listener NIC binding (0 = all NICs) |
| RDP firewall | Firewall rules allow RDP over IPv6 |
| Dual-stack DNS | AAAA record resolution works |
| Transition tech | Teredo/ISATAP tunneling status |

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
  --scripts @Windows_IPv6_RDP_Path_Check/Windows_IPv6_RDP_Path_Check.ps1
```

### Mock test
```powershell
.\Windows_IPv6_RDP_Path_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows IPv6 RDP Path Check ===
Check                                        Status
-------------------------------------------- ------
IPv6 enabled on primary NIC                  OK
IPv6 addresses assigned                      OK
RDP listener address binding                 WARN
RDP firewall rule for IPv6                   FAIL
Dual-stack DNS resolution works              WARN
Teredo/ISATAP transition disabled            WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 1 FAIL / 3 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **IPv6 enabled on primary NIC** WARN | IPv6 is disabled — some Azure services use IPv6 internally. Disabling can cause subtle issues. | Re-enable: `Enable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6`. Note: Microsoft does not support disabling IPv6 on Azure VMs. | [Troubleshoot RDP connection](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-connection) |
| **RDP listener address binding** WARN | RDP listener (TermService) bound to a specific NIC adapter instead of all (LanAdapter=0). May miss connections arriving on other NICs. | Set to all NICs: `Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name LanAdapter -Value 0` | [RDP listener configuration](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-general-error) |
| **RDP firewall rule for IPv6** FAIL | Windows Firewall blocks inbound RDP (TCP 3389) on IPv6. Azure may route RDP internally via IPv6. | `Enable-NetFirewallRule -DisplayName "Remote Desktop - User Mode (TCP-In)"` — ensure rule covers both IPv4 and IPv6 profiles | [Troubleshoot RDP firewall rules](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-nsg-problem) |
| **Dual-stack DNS resolution works** WARN | No AAAA records resolved. May be normal if environment is IPv4-only, but dual-stack improves resilience. | Verify DNS servers support IPv6: `Resolve-DnsName -Name <hostname> -Type AAAA`. Check if DNS forwarders return AAAA records. | [Azure DNS overview](https://learn.microsoft.com/azure/dns/dns-overview) |
| **Teredo/ISATAP transition disabled** WARN | Teredo or ISATAP tunnel adapters are active. These transition technologies are generally unnecessary on Azure VMs and can cause routing confusion. | Disable: `netsh interface teredo set state disabled` and `netsh interface isatap set state disabled` | [IPv6 transition technologies](https://learn.microsoft.com/troubleshoot/windows-server/networking/configure-ipv6-in-windows) |
| **IPv6 addresses assigned** WARN | No global IPv6 addresses. If dual-stack is expected, check Azure VNet IPv6 configuration. | Verify VNet has IPv6 address space: Azure Portal → VNet → Address space. Check NIC for IPv6 config. | [IPv6 for Azure VNet](https://learn.microsoft.com/azure/virtual-network/ip-services/ipv6-overview) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot RDP connections to Azure VM | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-connection) |
| Troubleshoot RDP general error | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-general-error) |
| Configure IPv6 in Windows | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/networking/configure-ipv6-in-windows) |
| IPv6 for Azure Virtual Network | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-network/ip-services/ipv6-overview) |
