# Windows RPC Endpoint Mapper Check

> **Tool ID:** RC-040 · **Bucket:** Services · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates the RPC (Remote Procedure Call) infrastructure that underpins Windows interprocess communication. Checks the RPC Endpoint Mapper service, DCOM Launch service, port 135 listener status, dynamic port range, recent RPC errors, and WMI repository health. RPC failures cascade into AD authentication, WMI queries, and many management tools failing.

| Check area | What is validated |
|---|---|
| RPC service | RPC Endpoint Mapper service running |
| DCOM Launch | DCOM Server Process Launcher service running |
| Port 135 | Port 135 listening for RPC |
| Dynamic ports | RPC dynamic port range configured |
| RPC errors | RPC-related errors in System log (7 days) |
| WMI health | WMI repository consistency |

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
  --scripts @Windows_RPC_EndpointMapper_Check/Windows_RPC_EndpointMapper_Check.ps1
```

### Mock test
```powershell
.\Windows_RPC_EndpointMapper_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows RPC Endpoint Mapper Check ===
Check                                        Status
-------------------------------------------- ------
RPC Endpoint Mapper service                  FAIL
DCOM Launch service                          FAIL
RPC port range (135 listening)               FAIL
RPC dynamic port range                       WARN
RPC errors in System log (7d)                FAIL
WMI repository healthy                       WARN
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
| **RPC Endpoint Mapper service** FAIL | RpcSs service stopped. All RPC-dependent operations (WMI, DCOM, AD auth, many management tools) will fail. | `Set-Service RpcSs -StartupType Automatic; Start-Service RpcSs` — this is a critical system service, should never be disabled | [Troubleshoot RDP general error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-general-error) |
| **DCOM Launch service** FAIL | DcomLaunch service stopped. COM+ applications and DCOM servers cannot start. | `Start-Service DcomLaunch` — dependency of many Windows services including WMI | [RPC troubleshooting](https://learn.microsoft.com/troubleshoot/windows-server/networking/rpc-errors-troubleshooting) |
| **RPC port range (135 listening)** FAIL | TCP 135 not listening. RPC clients cannot resolve endpoints. May indicate RpcSs crash or firewall block. | Verify: `Test-NetConnection -ComputerName localhost -Port 135`. Enable firewall rule or restart RpcSs. | [RPC Endpoint Mapper](https://learn.microsoft.com/troubleshoot/windows-server/networking/rpc-errors-troubleshooting) |
| **RPC dynamic port range** WARN | Dynamic port range is non-standard or restricted. Default: 49152-65535 (16384 ports). Too few ports causes RPC exhaustion under load. | `netsh int ipv4 show dynamicport tcp` to check. Reset: `netsh int ipv4 set dynamicport tcp start=49152 num=16384` | [Configure RPC dynamic port range](https://learn.microsoft.com/troubleshoot/windows-server/networking/default-dynamic-port-range-tcpip-702) |
| **RPC errors in System log (7d)** WARN | RPC error events found. May indicate transient connectivity issues, firewall blocks, or service instability. | `Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-RPC-Events'; StartTime=(Get-Date).AddDays(-7)}` | [RPC errors troubleshooting](https://learn.microsoft.com/troubleshoot/windows-server/networking/rpc-errors-troubleshooting) |
| **WMI repository healthy** WARN | WMI repository may be corrupted. WMI queries (used by monitoring, SCOM, extensions) will fail. | `winmgmt /verifyrepository` — if inconsistent: `winmgmt /salvagerepository` | [WMI troubleshooting](https://learn.microsoft.com/troubleshoot/windows-server/system-management-components/scenario-guide-troubleshoot-wmi-connectivity) |

## Related Articles

| Article | Link |
|---|---|
| RPC errors troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/networking/rpc-errors-troubleshooting) |
| Default dynamic port range | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/networking/default-dynamic-port-range-tcpip-702) |
| RDP general error troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-general-error) |
