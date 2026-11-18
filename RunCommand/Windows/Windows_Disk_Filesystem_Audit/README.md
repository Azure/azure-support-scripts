# Windows Disk & Filesystem Audit

> **Tool ID:** RC-005 · **Bucket:** Disk / Unexpected-Restarts / Performance · **Phase:** 2

## What It Does

Audits disk capacity and filesystem health on a running Azure Windows VM:

| Check area | What is validated |
|---|---|
| **Drive free space** | All fixed drives — WARN <15%, FAIL <5% |
| **Pagefile** | Exists, auto-managed vs. custom, size adequacy |
| **Temp drive (D:)** | Present and has adequate free space |
| **Dirty bit** | Any volume flagged dirty (chkdsk pending reboot) |

Read-only — no changes to the system.

## How to Run

### Azure Run Command
1. Portal → VM → **Operations → Run Command → RunPowerShellScript**
2. Paste `Windows_Disk_Filesystem_Audit.ps1` → **Run**

### Azure CLI
```bash
az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript --scripts @Windows_Disk_Filesystem_Audit.ps1
```

### Mock / Offline Test
```powershell
.\Windows_Disk_Filesystem_Audit.ps1 -MockConfig .\mock_config_sample.json
```

## Sample Output (Issues Detected)

```
=== Windows Disk & Filesystem Audit ===
Check                                        Status
-------------------------------------------- ------
-- Drive Free Space --
C: Free space (2.1 GB / 127.9 GB)           FAIL
E: Free space (48.3 GB / 256.0 GB)          OK
-- Pagefile Configuration --
Pagefile mode: Custom                        OK
Pagefile: C:\pagefile.sys                    OK
-- Temp Drive (D:) --
D: Free space (0.9 GB / 32.0 GB)            FAIL
-- Filesystem Dirty Bit --
Volume C: dirty bit set                      WARN

=== RESULT: 3 OK / 2 FAIL / 1 WARN ===
```

## Interpretation Guide

| Condition | Action |
|---|---|
| C: < 5% free | Clear temp files: `cleanmgr`, `%TEMP%`, Windows Update cache in `SoftwareDistribution\Download` |
| Pagefile missing (non-auto) | Re-enable pagefile — VM may crash under memory pressure |
| D: temp drive < 5% | Azure diagnostics, dumps, and extensions write here — clear or expand |
| Dirty bit set | Non-critical unless preventing boot — chkdsk runs on next reboot |

## Related Articles
- [Troubleshoot Azure Windows VM disk issues](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/troubleshoot-recovery-disks-portal-windows)
- [Unexpected restart on Azure VM with attached VHDs](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/unexpected-reboots-attached-vhds)
