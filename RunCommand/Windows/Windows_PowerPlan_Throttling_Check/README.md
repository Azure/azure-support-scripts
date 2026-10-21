# Windows PowerPlan Throttling Check

> **Tool ID:** RC-035 · **Bucket:** Performance · **Phase:** 2 (Deep diagnostic)

## What It Does

Audits power plan settings that can silently throttle CPU and disk performance on Azure VMs. Checks the active power plan, processor max/min states, hard disk timeout, USB selective suspend, and sleep/hibernate settings. A misconfigured power plan is a frequent root cause of unexplained performance degradation in Azure VMs.

| Check area | What is validated |
|---|---|
| Active plan | Power plan name (should be High Performance) |
| Processor max | Maximum processor state at 100% |
| Processor min | Minimum processor state reasonable |
| Disk timeout | Hard disk spin-down timeout |
| USB suspend | USB selective suspend disabled |
| Sleep/Hibernate | Sleep timeout disabled for server workloads |

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
  --scripts @Windows_PowerPlan_Throttling_Check/Windows_PowerPlan_Throttling_Check.ps1
```

### Mock test
```powershell
.\Windows_PowerPlan_Throttling_Check.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows PowerPlan Throttling Check ===
Check                                        Status
-------------------------------------------- ------
Active power plan                            FAIL
Processor max state = 100%                   FAIL
Processor min state reasonable               WARN
Hard disk timeout (not 0)                    WARN
USB selective suspend disabled               WARN
Sleep/Hibernate disabled for server          FAIL
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 0 OK / 3 FAIL / 3 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Active power plan** FAIL | Not running High Performance plan. Balanced or Power Saver throttles CPU frequency, adding latency. | `powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c` (High Performance GUID) | [Troubleshoot high CPU on Azure Windows VM](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-high-cpu-issues-azure-windows-vm) |
| **Processor max state = 100%** FAIL | Maximum processor state is capped below 100%. CPU cannot reach full clock speed, causing performance loss under load. | `powercfg /setacvalueindex scheme_current sub_processor PROCTHROTTLEMAX 100` then `powercfg /setactive scheme_current` | [Azure VM performance troubleshooting](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-high-cpu-issues-azure-windows-vm) |
| **Processor min state reasonable** WARN | Minimum processor state is very low (e.g., 5%). CPU may park at very low frequencies during idle, causing latency spikes on wake. | `powercfg /setacvalueindex scheme_current sub_processor PROCTHROTTLEMIN 100` for consistent performance | [Power plan settings](https://learn.microsoft.com/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning) |
| **Hard disk timeout (not 0)** WARN | Disk timeout is 0 (never spin down) or very short. On Azure managed disks this is usually informational but can mask issues. | `powercfg /setacvalueindex scheme_current sub_disk DISKIDLE 0` (0 = never timeout, appropriate for server) | [Performance tuning for disks](https://learn.microsoft.com/windows-server/administration/performance-tuning/subsystem/storage/) |
| **USB selective suspend disabled** WARN | USB selective suspend is enabled. Can cause device disconnects on USB-passthrough scenarios. | `powercfg /setacvalueindex scheme_current 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0` | [USB power management](https://learn.microsoft.com/windows-hardware/drivers/usbcon/usb-power-management) |
| **Sleep/Hibernate disabled for server** FAIL | Sleep or hibernate is enabled. Server VMs should never sleep — causes Azure heartbeat timeouts and potential deallocation. | `powercfg /h off` and `powercfg /setacvalueindex scheme_current sub_sleep STANDBYIDLE 0` (0 = never sleep) | [Azure VM memory issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-windows-vm-memory-issue) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot high CPU on Azure Windows VM | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-high-cpu-issues-azure-windows-vm) |
| Power and performance tuning | [learn.microsoft.com](https://learn.microsoft.com/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning) |
| Azure Windows VM memory issues | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/azure-windows-vm-memory-issue) |
