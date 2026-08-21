# Windows Crash Dump Config Validator

> **Tool ID:** RC-009 · **Bucket:** Unexpected-Restarts / BSOD · **Phase:** 3 (Config audit)

## What It Does

Validates crash dump capture readiness on a Windows VM. Checks dump type, dump file paths, AutoReboot/overwrite policies, pagefile configuration, and existing dump artifacts. Essential for VMs experiencing BSODs where crash data is not being collected.

| Check area | What is validated |
|---|---|
| Dump path | Dump file path configured |
| AutoReboot | AutoReboot disabled during triage |
| Overwrite | Overwrite existing dump enabled |
| Minidump dir | Minidump directory configured |
| Pagefile | Pagefile configured |
| OS pagefile | OS drive pagefile present |
| MEMORY.DMP | MEMORY.DMP artifact present |
| Minidumps | Minidump files present |

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
  --scripts @Windows_CrashDump_Config_Validator/Windows_CrashDump_Config_Validator.ps1
```

### Mock test
```powershell
.\Windows_CrashDump_Config_Validator.ps1 -MockConfig .\mock_config_sample.json -MockProfile degraded
```

## Sample Output (Issues Detected)

```
=== Windows Crash Dump Config Validator ===
Check                                        Status
-------------------------------------------- ------
Dump file path configured                    OK
AutoReboot disabled during triage            WARN
Overwrite existing dump enabled              WARN
Minidump directory configured                OK
Pagefile configured                          FAIL
OS drive pagefile present                    WARN
MEMORY.DMP present                           WARN
Minidump files present                       WARN
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 1 FAIL / 5 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Dump file path configured** FAIL | CrashControl registry has no dump path. Crash dumps cannot be written. | Set `HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl\DumpFile` to `%SystemRoot%\MEMORY.DMP` | [Collect OS memory dump](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/collect-os-memory-dump-file) |
| **AutoReboot disabled during triage** WARN | AutoReboot=1 means VM reboots immediately after BSOD, hiding the stop-code from Serial Console. | Set `AutoReboot=0` in `CrashControl` during active triage. Restore to 1 after investigation. | [Enable serial console memory dump](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/enable-serial-console-memory-dump-collection) |
| **Overwrite existing dump enabled** WARN | Previous dump files are overwritten on each crash. Set to 0 if you need to preserve multiple dumps. | `reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v Overwrite /t REG_DWORD /d 0 /f` | [Collect OS memory dump](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/collect-os-memory-dump-file) |
| **Pagefile configured** FAIL | No pagefile detected. Kernel/complete memory dumps require a pagefile on the OS disk at least equal to RAM size. | `wmic pagefileset create name="C:\pagefile.sys"` then set initial/maximum size. Reboot required. | [Enable serial console memory dump](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/enable-serial-console-memory-dump-collection) |
| **OS drive pagefile present** WARN | Pagefile exists but not on C: drive. OS crash dumps write to the OS volume pagefile specifically. | Move or add pagefile to C: via System Properties → Performance → Virtual Memory. | [Collect OS memory dump](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/collect-os-memory-dump-file) |
| **MEMORY.DMP present** WARN | A MEMORY.DMP already exists — previous crash data available for analysis. Informational. | `dir %SystemRoot%\MEMORY.DMP` — collect before next crash if Overwrite=1. | [Collect OS memory dump](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/collect-os-memory-dump-file) |
| **Minidump files present** WARN | Minidump files found in `%SystemRoot%\Minidump`. Indicates previous crashes. Informational — useful for analysis. | `dir %SystemRoot%\Minidump\*.dmp` — analyze with WinDbg or `!analyze -v`. | [BSOD troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-common-blue-screen-error) |

## Related Articles

| Article | Link |
|---|---|
| Collect OS memory dump file | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/collect-os-memory-dump-file) |
| Enable serial console memory dump collection | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/enable-serial-console-memory-dump-collection) |
| Common BSOD troubleshooting | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-common-blue-screen-error) |
- https://learn.microsoft.com/azure/virtual-machines/troubleshooting/troubleshoot-common-blue-screen-error
