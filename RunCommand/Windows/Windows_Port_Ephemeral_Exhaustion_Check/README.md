# Windows Port Ephemeral Exhaustion Check

> **Bucket:** Connectivity / Port-Exhaustion / Intermittent-Drops

## What It Does

Detects ephemeral (dynamic) TCP port exhaustion on a Windows VM — a common cause of intermittent connection failures, RDP drops, and application timeouts:

| Check | What is validated |
|---|---|
| **Dynamic port range size** | `netsh int ipv4 show dynamicport tcp` — ensures range ≥ 16,384 ports |
| **TCP connection count** | Total active TCP connections — flags if ≥ 10,000 (WARN) or ≥ 30,000 (FAIL) |
| **TIME_WAIT count** | Connections stuck in TIME_WAIT — flags if ≥ 5,000 (WARN) or ≥ 15,000 (FAIL) |
| **Ephemeral port usage ratio** | Ports in use ÷ total range — flags if ≥ 60% (WARN) or ≥ 85% (FAIL) |
| **MaxUserPort registry** | Checks if `MaxUserPort` is set too low (< 32,768) |
| **TcpTimedWaitDelay** | Checks if TIME_WAIT timeout is tuned (≤ 60 sec = OK, default 240 sec = WARN) |

The script is **read-only** — it makes no changes to the system.

## How to Run

### Azure Run Command (recommended)
1. Go to your VM in the Azure portal
2. Select **Operations → Run Command → RunPowerShellScript**
3. Paste the contents of `Windows_Port_Ephemeral_Exhaustion_Check.ps1`
4. Select **Run** and wait for output

### Azure CLI
```bash
az vm run-command invoke \
  --resource-group <rg> \
  --name <vm-name> \
  --command-id RunPowerShellScript \
  --scripts @Windows_Port_Ephemeral_Exhaustion_Check.ps1
```

### Elevated PowerShell (inside VM)
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Windows_Port_Ephemeral_Exhaustion_Check.ps1
```

### Mock / Offline Test
```powershell
.\Windows_Port_Ephemeral_Exhaustion_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Port Ephemeral Exhaustion Check ===
Check                                        Status
-------------------------------------------- ------
Dynamic port range size                      WARN    Start=49152 Count=8192
Current TCP connections count                FAIL    TCPConns=34291
TIME_WAIT connection count                   FAIL    TimeWait=22000
Ephemeral port usage ratio                   FAIL    EphUsed=7800 Ratio=95.2%
MaxUserPort registry override                OK      MaxUserPort=default
TcpTimedWaitDelay tuned                      WARN    TWDelay=240 sec
-- Decision --
Likely cause severity                        FAIL
Next action                                  OK
-- More Info --
Remediation references available             OK

=== RESULT: 1 OK / 3 FAIL / 2 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix |
|---|---|---|
| Dynamic port range < 16,384 | Range was reduced via `netsh` or GPO | Run: `netsh int ipv4 set dynamicport tcp start=49152 num=16384` then reboot |
| TCP connections ≥ 30,000 | Application connection leak or high-traffic burst | Identify the process holding connections: `Get-NetTCPConnection \| Group-Object OwningProcess \| Sort-Object Count -Desc` |
| TIME_WAIT ≥ 15,000 | Rapid connect/disconnect cycles (web servers, load balancers) | Reduce `TcpTimedWaitDelay` to 30 sec (see below) and investigate the calling app |
| Ephemeral port ratio ≥ 85% | Active port exhaustion — new connections will fail | Immediate: restart the leaking process. Long-term: increase range or fix connection reuse |
| MaxUserPort < 32,768 | Legacy registry override limiting available ports | Remove or increase `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\MaxUserPort` |
| TcpTimedWaitDelay > 60 sec | Default 240 sec keeps ports locked in TIME_WAIT too long | Set `TcpTimedWaitDelay` to 30: `Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name TcpTimedWaitDelay -Value 30 -Type DWord` then reboot |

## Related Articles

- [Troubleshoot intermittent RDP connectivity to Azure VM](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/troubleshoot-rdp-intermittent-connectivity)
- [Troubleshoot application connectivity issues on Azure VMs](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/troubleshoot-app-connection)
- [Default dynamic port range for TCP/IP (Windows Server)](https://learn.microsoft.com/troubleshoot/windows-server/networking/default-dynamic-port-range-tcpip-702)
