# Windows Proxy WinHTTP WinINET Check

> **Tool ID:** RC-035 · **Bucket:** Network / Proxy · **Phase:** 2 (Deep diagnostic)

## What It Does

Audits proxy configuration across WinHTTP and WinINET layers. Checks proxy detection, registry settings, bypass list configuration, and verifies Azure fabric endpoints (IMDS, WireServer) are reachable without proxy interference. Critical for VMs where agent/extensions fail due to proxy misconfiguration.

| Check area | What is validated |
|---|---|
| WinHTTP proxy | WinHTTP proxy settings parsed |
| WinINET proxy | WinINET proxy registry key readable |
| Bypass list | Proxy bypass list defined |
| IMDS bypass | IMDS reachable without proxy |
| WireServer bypass | WireServer reachable without proxy |

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
  --scripts @Windows_Proxy_WinHTTP_WinINET_Check/Windows_Proxy_WinHTTP_WinINET_Check.ps1
```

### Mock test
```powershell
.\Windows_Proxy_WinHTTP_WinINET_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Proxy WinHTTP WinINET Check ===
Check                                        Status
-------------------------------------------- ------
WinHTTP proxy parsed                         WARN
WinINET proxy key readable                   WARN
Proxy bypass list defined                    WARN
IMDS reachable without proxy                 FAIL
WireServer reachable without proxy           FAIL
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
| **WinHTTP proxy parsed** WARN | WinHTTP proxy is configured system-wide. May route Azure fabric traffic through proxy that cannot reach 168.63.129.16 or 169.254.169.254. | `netsh winhttp show proxy` — if set, ensure bypass list includes `168.63.129.16;169.254.169.254`. Reset: `netsh winhttp reset proxy` | [No internet access multi-IP](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/no-internet-access-multi-ip) |
| **WinINET proxy key readable** WARN | WinINET (Internet Explorer/user-level) proxy settings detected. Applications using WinINET will route through proxy. | Check: `reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer`. Clear if unneeded. | [Troubleshoot app connection](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-app-connection) |
| **Proxy bypass list defined** WARN | Bypass list is missing or does not include Azure fabric endpoints. Proxy will intercept IMDS/WireServer calls. | Add to bypass: `netsh winhttp set proxy proxy-server="proxy:8080" bypass-list="168.63.129.16;169.254.169.254;<local>"` | [No internet access multi-IP](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/no-internet-access-multi-ip) |
| **IMDS reachable without proxy** FAIL | Cannot reach IMDS (169.254.169.254) bypassing proxy. Proxy intercepts link-local traffic or route is missing. | Ensure bypass list includes `169.254.169.254`. Test: `Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' -Headers @{Metadata='true'} -NoProxy` | [IMDS connection troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-imds-connection) |
| **WireServer reachable without proxy** FAIL | Cannot reach WireServer (168.63.129.16) bypassing proxy. Guest agent and extensions will fail. | Ensure bypass list includes `168.63.129.16`. Verify no firewall rules blocking. Test: `Test-NetConnection 168.63.129.16 -Port 80` | [What is IP 168.63.129.16](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16) |

## Related Articles

| Article | Link |
|---|---|
| No internet access multi-IP | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/no-internet-access-multi-ip) |
| Troubleshoot app connection | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-app-connection) |
| IMDS connection troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-imds-connection) |
