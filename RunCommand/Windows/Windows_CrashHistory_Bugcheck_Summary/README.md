# Windows Crash History Bugcheck Summary

> **Tool ID:** RC-013 · **Bucket:** Reliability · **Phase:** 2 (Deep diagnostic)

## What It Does

Scans for evidence of system crashes and blue-screen (bugcheck) events. Examines dump file presence, minidump directory, System event log for BugCheck and unexpected shutdown events, page file sizing, and CrashControl registry settings. Essential first-pass diagnostic for VMs experiencing unexpected reboots or BSOD.

| Check area | What is validated |
|---|---|
| System dump file | MEMORY.DMP exists under %SystemRoot% |
| Minidump directory | Minidump folder contains crash dump files |
| BugCheck events | Blue-screen events in System log (30 days) |
| Unexpected shutdowns | Unexpected shutdown events in System log (30 days) |
| Page file config | Page file is large enough for crash dump generation |
| CrashControl settings | Registry dump type configured (Complete/Kernel/Small) |

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
  --scripts @Windows_CrashHistory_Bugcheck_Summary/Windows_CrashHistory_Bugcheck_Summary.ps1
```

### Mock test
```powershell
.\Windows_CrashHistory_Bugcheck_Summary.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows Crash History Bugcheck Summary ===
Check                                        Status
-------------------------------------------- ------
System dump file exists                      WARN
Minidump directory populated                 OK
BugCheck events in System log (30d)          FAIL
Unexpected shutdown events (30d)             FAIL
Page file configuration adequate             WARN
CrashControl registry settings               OK
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
| **System dump file exists** WARN | No MEMORY.DMP found — either no crash has occurred (good) or dump generation failed during a crash (review CrashControl settings). | Verify CrashControl: `reg query "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl"` — ensure DumpType ≥ 1 and DedicatedDumpFile is not misconfigured | [Configure crash dump generation](https://learn.microsoft.com/troubleshoot/windows-client/performance/generate-a-kernel-or-complete-crash-dump) |
| **Minidump directory populated** WARN | %SystemRoot%\Minidump is empty. No small dumps collected. May indicate page file is too small for dump generation. | Check `C:\Windows\Minidump\` — if empty and crashes are occurring, increase page file size to at least 400 MB | [Read small dump files](https://learn.microsoft.com/troubleshoot/windows-client/performance/read-small-memory-dump-file) |
| **BugCheck events in System log (30d)** FAIL | BugCheck (Event ID 1001, source BugCheck) entries found — system experienced blue-screen crashes. Correlate with dump analysis. | Collect dump with `windbg -z C:\Windows\MEMORY.DMP` or upload to Azure support case. Check Event ID 1001 details for bugcheck code. | [Troubleshoot common blue-screen errors](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-common-blue-screen-error) |
| **Unexpected shutdown events (30d)** FAIL | Event ID 6008 (unexpected shutdown) found. VM lost power or crashed without clean shutdown. May indicate host-level issue if frequent. | Cross-reference with Azure Activity Log for host maintenance events. Check VM availability in Azure Portal → VM → Health. | [Troubleshoot Windows stop error](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-windows-stop-error) |
| **Page file configuration adequate** WARN | Page file size may be insufficient for generating kernel or complete dumps. Small page files prevent MEMORY.DMP creation. | Set page file: `wmic pagefileset where name="C:\\pagefile.sys" set InitialSize=1024,MaximumSize=8192` or use System → Advanced → Performance → Virtual Memory | [Determine page file size](https://learn.microsoft.com/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size) |
| **CrashControl registry settings** WARN | DumpType is 0 (none) or 3 (small only). Complete/Kernel dumps provide more diagnostic value. | `Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name CrashDumpEnabled -Value 2` (2 = Kernel dump) | [Configure crash dump generation](https://learn.microsoft.com/troubleshoot/windows-client/performance/generate-a-kernel-or-complete-crash-dump) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot common blue-screen errors on Azure VMs | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-common-blue-screen-error) |
| Troubleshoot Windows stop errors | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-windows-stop-error) |
| Configure crash dump file generation | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-client/performance/generate-a-kernel-or-complete-crash-dump) |
| Determine appropriate page file size | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size) |
