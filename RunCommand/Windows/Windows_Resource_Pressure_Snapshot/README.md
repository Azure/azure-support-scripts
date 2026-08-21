# Windows Resource Pressure Snapshot

> **Tool ID:** RC-006 · **Bucket:** Performance / High-CPU / Memory-Pressure · **Phase:** 2

## What It Does

Point-in-time resource utilization snapshot for diagnosing Azure Windows VM performance complaints:

| Check area | What is captured |
|---|---|
| **CPU** | Overall utilization (2-sample avg) + top 5 CPU processes |
| **Memory** | Physical used %, commit charge %, top 5 processes by Working Set |
| **Disk I/O** | Current queue length per physical disk |

Read-only — no changes to the system. One 1-second sleep for CPU sampling.

## Thresholds

| Metric | WARN | FAIL |
|---|---|---|
| CPU % | ≥ 75% | ≥ 90% |
| Memory used % | ≥ 85% | ≥ 95% |
| Commit charge % | ≥ 85% | ≥ 95% |
| Disk queue length | ≥ 2 | ≥ 4 |

## How to Run

### Azure Run Command
1. Portal → VM → **Operations → Run Command → RunPowerShellScript**
2. Paste `Windows_Resource_Pressure_Snapshot.ps1` → **Run**

### Azure CLI
```bash
az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript --scripts @Windows_Resource_Pressure_Snapshot.ps1
```

### Mock / Offline Test
```powershell
.\Windows_Resource_Pressure_Snapshot.ps1 -MockConfig .\mock_config_sample.json
```

## Sample Output (High Pressure)

```
=== Windows Resource Pressure Snapshot ===
Check                                        Status
-------------------------------------------- ------
-- CPU --
Overall CPU utilization                      FAIL   92.5%
  Top CPU processes:
    sqlservr                        PID=1234   CPUsec=4821.3
    w3wp                            PID=5678   CPUsec=1203.7
-- Memory --
Physical memory used                         FAIL   96.2% (0.6 GB free / 16.0 GB)
Commit charge                                FAIL   98.1% of virtual memory committed
  Top memory processes (Working Set):
    sqlservr                        PID=1234   WS=9240 MB
    w3wp                            PID=5678   WS=2180 MB
-- Disk I/O Queue --
Disk queue: 0 C:                             FAIL   Queue=5
Disk queue: 1 D:                             OK     Queue=0

=== RESULT: 1 OK / 4 FAIL / 0 WARN ===
```

## Interpretation Guide

| FAIL condition | Likely cause | Next step |
|---|---|---|
| CPU ≥ 90% | Runaway process, AV scan, Windows Update | Check top proc — if svchost, identify child service |
| Memory ≥ 95% | Memory leak, undersized VM, missing pagefile | Review top WS procs; consider resize or pagefile increase |
| Commit ≥ 95% | Pagefile exhaustion imminent | Expand pagefile or stop non-critical services |
| Disk queue ≥ 4 | Disk throttling, Premium tier needed, I/O storm | Check VM + disk SKU IOPS limits in portal |

## Related Articles
- [Troubleshoot high CPU issues on Azure Windows VMs](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/troubleshoot-high-cpu-issues-azure-windows-vm)
- [Azure VM sizes](https://learn.microsoft.com/azure/virtual-machines/sizes)
