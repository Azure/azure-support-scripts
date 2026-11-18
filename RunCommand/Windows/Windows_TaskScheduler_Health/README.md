# Windows TaskScheduler Health

> **Tool ID:** RC-046 · **Bucket:** Services · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates Task Scheduler health on an Azure VM. Checks service state, identifies failed scheduled tasks, reviews scheduler event errors, counts registered tasks, and checks for currently running tasks. Important for VMs where automated jobs (backups, updates, monitoring) fail silently.

| Check area | What is validated |
|---|---|
| Scheduler service | Task Scheduler service running |
| Failed tasks | Scheduled tasks in failed/errored state |
| Event errors | Task Scheduler event errors (7 days) |
| Registered tasks | Total active task count |
| Running tasks | Tasks currently executing |

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
  --scripts @Windows_TaskScheduler_Health/Windows_TaskScheduler_Health.ps1
```

### Mock test
```powershell
.\Windows_TaskScheduler_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows TaskScheduler Health ===
Check                                        Status
-------------------------------------------- ------
Task Scheduler service                       FAIL
Failed scheduled tasks                       FAIL
Task Scheduler event errors (7d)             WARN
Task registration count                      OK
Task queue latency (any running)             OK
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 2 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Task Scheduler service** FAIL | Schedule service (TaskScheduler) stopped or disabled. No scheduled tasks can execute. | `Set-Service Schedule -StartupType Automatic; Start-Service Schedule` | [Task Scheduler overview](https://learn.microsoft.com/windows/win32/taskschd/task-scheduler-start-page) |
| **Failed scheduled tasks** FAIL | One or more tasks have last-run result indicating failure. May be permissions, missing executable, or dependency issue. | `Get-ScheduledTask \| Where-Object { $_.LastTaskResult -ne 0 -and $_.LastTaskResult -ne 267009 } \| Select TaskName,LastTaskResult` — fix run-as account or path | [Troubleshoot scheduled tasks](https://learn.microsoft.com/troubleshoot/windows-server/system-management-components/scheduled-tasks-reference) |
| **Task Scheduler event errors (7d)** WARN | Task Scheduler logged errors in its operational log. May indicate task launch failures, permission denials, or timeout events. | `Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" -MaxEvents 20 \| Where-Object { $_.Level -eq 2 }` | [Task Scheduler events](https://learn.microsoft.com/windows/win32/taskschd/task-scheduler-start-page) |
| **Task registration count** WARN | Unusually high or zero registered tasks. High count may indicate malware persistence; zero may indicate task database corruption. | `Get-ScheduledTask \| Measure-Object` — review unexpected tasks. If corrupt: `schtasks /query /fo CSV > C:\temp\tasks.csv` | [Group Policy and scheduled tasks](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/unresponsive-vm-apply-group-policy) |
| **Task queue latency (any running)** WARN | Tasks currently running. If many tasks run simultaneously, they may contend for resources and slow the system. | `Get-ScheduledTask \| Where-Object { $_.State -eq 'Running' }` — investigate long-running tasks | [Performance tuning](https://learn.microsoft.com/windows-server/administration/performance-tuning/) |

## Related Articles

| Article | Link |
|---|---|
| Task Scheduler reference | [learn.microsoft.com](https://learn.microsoft.com/windows/win32/taskschd/task-scheduler-start-page) |
| Unresponsive VM applying Group Policy | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/unresponsive-vm-apply-group-policy) |
| Group Policy client wait issues | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/please-wait-for-the-group-policy-client) |
### Mock test
```powershell
.\Windows_TaskScheduler_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows TaskScheduler Health ===
Check                                        Status
-------------------------------------------- ------
Task Scheduler service                       FAIL
Failed scheduled tasks                       FAIL
Task Scheduler event errors (7d)             WARN
Task registration count                      OK
Task queue latency (any running)             OK
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 2 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Task Scheduler service** FAIL | Schedule service (TaskScheduler) stopped or disabled. No scheduled tasks can execute. | `Set-Service Schedule -StartupType Automatic; Start-Service Schedule` | [Task Scheduler overview](https://learn.microsoft.com/windows/win32/taskschd/task-scheduler-start-page) |
| **Failed scheduled tasks** FAIL | One or more tasks have last-run result indicating failure. May be permissions, missing executable, or dependency issue. | `Get-ScheduledTask \| Where-Object { $_.LastTaskResult -ne 0 -and $_.LastTaskResult -ne 267009 } \| Select TaskName,LastTaskResult` — fix run-as account or path | [Troubleshoot scheduled tasks](https://learn.microsoft.com/troubleshoot/windows-server/system-management-components/scheduled-tasks-reference) |
| **Task Scheduler event errors (7d)** WARN | Task Scheduler logged errors in its operational log. May indicate task launch failures, permission denials, or timeout events. | `Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" -MaxEvents 20 \| Where-Object { $_.Level -eq 2 }` | [Task Scheduler events](https://learn.microsoft.com/windows/win32/taskschd/task-scheduler-start-page) |
| **Task registration count** WARN | Unusually high or zero registered tasks. High count may indicate malware persistence; zero may indicate task database corruption. | `Get-ScheduledTask \| Measure-Object` — review unexpected tasks. If corrupt: `schtasks /query /fo CSV > C:\temp\tasks.csv` | [Group Policy and scheduled tasks](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/unresponsive-vm-apply-group-policy) |
| **Task queue latency (any running)** WARN | Tasks currently running. If many tasks run simultaneously, they may contend for resources and slow the system. | `Get-ScheduledTask \| Where-Object { $_.State -eq 'Running' }` — investigate long-running tasks | [Performance tuning](https://learn.microsoft.com/windows-server/administration/performance-tuning/) |

## Related Articles

| Article | Link |
|---|---|
| Task Scheduler reference | [learn.microsoft.com](https://learn.microsoft.com/windows/win32/taskschd/task-scheduler-start-page) |
| Unresponsive VM applying Group Policy | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/unresponsive-vm-apply-group-policy) |
| Group Policy client wait issues | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/please-wait-for-the-group-policy-client) |
