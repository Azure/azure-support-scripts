# Windows RouteTable Anomaly Check

> **Tool ID:** RC-039 · **Bucket:** Networking · **Phase:** 2 (Deep diagnostic)

## What It Does

Analyzes the Windows routing table for anomalies that break Azure VM connectivity. Validates default gateway configuration, detects split-default routing, verifies IMDS and WireServer routes exist, checks for persistent routes that may conflict, and identifies blackhole routes. Critical for diagnosing VMs that lose internet or Azure service access after route table changes.

| Check area | What is validated |
|---|---|
| Default gateway | Default gateway is configured |
| Single default | No split-default routing (one 0.0.0.0 route) |
| IMDS route | Route to 169.254.169.254 exists |
| Persistent routes | Count of persistent routes (may conflict) |
| WireServer route | Route to 168.63.129.16 exists |
| Blackhole routes | No routes pointing to unreachable next-hops |

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
  --scripts @Windows_RouteTable_Anomaly_Check/Windows_RouteTable_Anomaly_Check.ps1
```

### Mock test
```powershell
.\Windows_RouteTable_Anomaly_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows RouteTable Anomaly Check ===
Check                                        Status
-------------------------------------------- ------
Default gateway configured                   FAIL
Single default route (no split)              FAIL
IMDS route 169.254.169.254                   FAIL
Persistent routes count                      WARN
WireServer route (168.63.129.16)             FAIL
No blackhole routes (unreachable)            WARN
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
| **Default gateway configured** FAIL | No default gateway — VM cannot reach anything outside its subnet. Gateway may have been removed by static IP misconfiguration. | `New-NetRoute -DestinationPrefix 0.0.0.0/0 -NextHop <gateway-IP> -InterfaceAlias "Ethernet"`. Find gateway: first usable IP in subnet. | [Troubleshoot no internet with multi-IP](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/no-internet-access-multi-ip) |
| **Single default route (no split)** FAIL | Multiple 0.0.0.0/0 routes cause non-deterministic routing. Common with VPN agents or multiple NICs. | `Get-NetRoute -DestinationPrefix 0.0.0.0/0` to list all. Remove extras: `Remove-NetRoute -DestinationPrefix 0.0.0.0/0 -InterfaceAlias <secondary>` | [Azure VM routing](https://learn.microsoft.com/azure/virtual-network/virtual-networks-udr-overview) |
| **IMDS route 169.254.169.254** FAIL | Route to Azure Instance Metadata Service missing. IMDS, managed identity, and scheduled events won't work. | `New-NetRoute -DestinationPrefix 169.254.169.254/32 -NextHop <gateway> -InterfaceAlias "Ethernet"` (or it should be automatically provided by DHCP) | [Azure Instance Metadata Service](https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service) |
| **WireServer route (168.63.129.16)** FAIL | No route to WireServer. Guest agent, extensions, and health probes will fail. | Verify DHCP is assigning routes. Route should come from Azure fabric. `Test-NetConnection 168.63.129.16 -Port 80` | [What is IP 168.63.129.16?](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16) |
| **Persistent routes count** WARN | Persistent routes exist. These survive reboots and may override Azure DHCP-assigned routes. | `route print -p` to list. Remove conflicting: `route delete <destination>` | [Troubleshoot connectivity](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-app-connection) |
| **No blackhole routes (unreachable)** WARN | Routes pointing to non-existent or unreachable next-hops detected. Traffic matching these routes will be silently dropped. | `Get-NetRoute \| Where-Object { $_.State -ne 'Alive' }` — remove or correct stale routes | [Virtual network traffic routing](https://learn.microsoft.com/azure/virtual-network/virtual-networks-udr-overview) |

## Related Articles

| Article | Link |
|---|---|
| Azure VM routing overview | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-network/virtual-networks-udr-overview) |
| No internet access with multi-IP | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/no-internet-access-multi-ip) |
| What is IP address 168.63.129.16? | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16) |
