# Windows NIC Advanced Properties Baseline

> **Tool ID:** RC-032 · **Bucket:** Networking · **Phase:** 2 (Deep diagnostic)

## What It Does

Inspects NIC advanced driver properties that impact network performance on Azure VMs. Validates Receive Side Scaling (RSS), checksum offload, Large Send Offload v2 (LSOv2), VMQ settings, jumbo frames, and speed/duplex configuration. Important for diagnosing throughput issues, packet loss, or netvsc driver problems in Azure VMs.

| Check area | What is validated |
|---|---|
| RSS | Receive Side Scaling enabled for multi-core packet processing |
| Checksum offload | Hardware checksum offloading active |
| LSOv2 | Large Send Offload v2 for TCP throughput |
| VMQ | Virtual Machine Queue status (informational) |
| Jumbo frames | Jumbo frame not set (Azure default — 1500 MTU) |
| Speed/Duplex | Auto-negotiation for speed and duplex |

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
  --scripts @Windows_NIC_AdvancedProperties_Baseline/Windows_NIC_AdvancedProperties_Baseline.ps1
```

### Mock test
```powershell
.\Windows_NIC_AdvancedProperties_Baseline.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows NIC Advanced Properties Baseline ===
Check                                        Status
-------------------------------------------- ------
RSS (Receive Side Scaling) enabled           FAIL
Checksum offload enabled                     WARN
Large Send Offload v2 (LSOv2)               WARN
VMQ (Virtual Machine Queue)                  OK
Jumbo Frame not set (Azure default)          FAIL
Speed and duplex auto-negotiation            OK
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 2 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **RSS (Receive Side Scaling) enabled** FAIL | RSS disabled — all network interrupts go to a single CPU core, causing packet loss under load. Azure netvsc driver supports RSS. | `Enable-NetAdapterRss -Name "Ethernet"` or `Set-NetAdapterRss -Name "Ethernet" -Enabled $true` | [Troubleshoot netvsc driver issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-driver-netvsc) |
| **Checksum offload enabled** WARN | Hardware checksum offload disabled. CPU handles all checksum calculations, increasing overhead and reducing throughput. | `Set-NetAdapterChecksumOffload -Name "Ethernet" -TcpIPv4 RxTxEnabled -UdpIPv4 RxTxEnabled` | [Azure VM networking best practices](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-overview) |
| **Large Send Offload v2 (LSOv2)** WARN | LSO disabled. Large TCP sends are segmented by CPU instead of NIC, reducing throughput on large transfers. | `Enable-NetAdapterLso -Name "Ethernet"` | [Accelerated Networking overview](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-overview) |
| **Jumbo Frame not set (Azure default)** FAIL | Jumbo frames enabled (MTU > 1500). Azure virtual network MTU is 1500; jumbo frames cause fragmentation and packet drops. | `Set-NetAdapterAdvancedProperty -Name "Ethernet" -RegistryKeyword "*JumboPacket" -RegistryValue "1514"` (1514 = disabled/standard) | [Azure VM MTU and fragmentation](https://learn.microsoft.com/azure/virtual-network/virtual-network-tcpip-performance-tuning) |
| **VMQ (Virtual Machine Queue)** WARN | VMQ disabled or not supported. Informational on most Azure VM sizes — Hyper-V handles RSS instead. | Usually no action needed on Azure VMs. If using Accelerated Networking, VMQ is managed by the hardware. | [Accelerated Networking](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-overview) |
| **Speed and duplex auto-negotiation** WARN | Forced speed/duplex setting. Azure synthetic NICs should use auto-negotiation. Manual settings can cause connectivity issues. | `Set-NetAdapterAdvancedProperty -Name "Ethernet" -RegistryKeyword "*SpeedDuplex" -RegistryValue "0"` (0 = auto) | [Troubleshoot netvsc driver](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-driver-netvsc) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot netvsc driver issues | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-driver-netvsc) |
| Accelerated Networking overview | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-overview) |
| TCP/IP performance tuning for Azure VMs | [learn.microsoft.com](https://learn.microsoft.com/azure/virtual-network/virtual-network-tcpip-performance-tuning) |
