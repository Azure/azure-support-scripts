# Windows TimeSync Kerberos Health

> **Tool ID:** RC-047 · **Bucket:** Identity / Time · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates time synchronization and Kerberos authentication prerequisites. Checks time source detection, clock offset tolerance, timezone configuration, KDC reachability, Netlogon state, and Kerberos error trends. Essential for domain-joined VMs where clock skew causes authentication failures.

| Check area | What is validated |
|---|---|
| Time source | Time source detected (W32Time) |
| Clock offset | Clock offset within tolerance (±5 min) |
| Timezone | Timezone configured |
| KDC reachability | KDC reachability signal |
| Netlogon | Netlogon service running |
| Kerberos errors | Recent Kerberos errors low |

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
  --scripts @Windows_TimeSync_Kerberos_Health/Windows_TimeSync_Kerberos_Health.ps1
```

### Mock test
```powershell
.\Windows_TimeSync_Kerberos_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows TimeSync + Kerberos Health ===
Check                                        Status
-------------------------------------------- ------
Time source detected                         WARN
Clock offset within tolerance                FAIL
Timezone configured                          OK
KDC reachability signal                      FAIL
Netlogon running                             WARN
Recent Kerberos errors low                   WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 1 OK / 2 FAIL / 3 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Time source detected** WARN | W32Time has no configured time source or is using local CMOS clock. Time may drift causing Kerberos failures. | `w32tm /query /source` — if "Local CMOS Clock": `w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:YES /update` then `Restart-Service w32time; w32tm /resync` | [Windows Time Service](https://learn.microsoft.com/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings) |
| **Clock offset within tolerance** FAIL | Clock offset exceeds ±5 minutes. Kerberos authentication will fail (default skew tolerance is 5 min). | `w32tm /resync /force` — if fails, manually set: `Set-Date -Date (Get-Date).AddMinutes(<correction>)`. Check NTP source. | [Windows Time Service](https://learn.microsoft.com/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings) |
| **Timezone configured** WARN | Timezone is not set or set to unexpected value. May cause confusion in log analysis but does not affect Kerberos (which uses UTC). | `tzutil /g` to view. Set: `tzutil /s "UTC"` or appropriate timezone. | [Must change password](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/must-change-password) |
| **KDC reachability signal** FAIL | Cannot reach Key Distribution Center. Kerberos ticket requests will fail. Usually indicates DC unreachable. | `nltest /dsgetdc:<domain> /KDC` — verify DNS resolves DC, network path open on ports 88/464 (Kerberos), 389 (LDAP). | [Kerberos authentication](https://learn.microsoft.com/windows-server/security/kerberos/kerberos-authentication-overview) |
| **Netlogon running** WARN | Netlogon service stopped. Secure channel maintenance and DC locator will not function. | `Start-Service Netlogon`. If fails: `sc config Netlogon start=auto` then start. | [Netlogon not starting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-vm-netlogon-not-starting) |
| **Recent Kerberos errors low** WARN | More than 20 Kerberos-related events in System log. Indicates ongoing authentication issues. | `Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kerberos-Key-Distribution-Center';StartTime=(Get-Date).AddDays(-7)} \| Measure-Object` | [Kerberos authentication](https://learn.microsoft.com/windows-server/security/kerberos/kerberos-authentication-overview) |

## Related Articles

| Article | Link |
|---|---|
| Windows Time Service tools and settings | [learn.microsoft.com](https://learn.microsoft.com/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings) |
| Must change password at login | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/must-change-password) |
| Kerberos authentication overview | [learn.microsoft.com](https://learn.microsoft.com/windows-server/security/kerberos/kerberos-authentication-overview) |
