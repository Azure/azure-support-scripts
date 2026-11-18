# Windows ProfileDisk TempIo Storm Check

> Tool focus: temp/profile growth and write-pressure triage.

## What It Checks

- `%TEMP%` size signal
- `C:\Users` profile footprint signal
- current disk queue pressure
- top write-heavy process sample

## How To Run

```powershell
.\Windows_ProfileDisk_TempIo_Storm_Check.ps1
```

Mock/offline validation:

```powershell
.\Windows_ProfileDisk_TempIo_Storm_Check.ps1 -MockConfig .\mock_config_sample.json
```

## Mock Output Example

```
=== Windows Profile/Temp I/O Storm Check ===
Check                                        Status
-------------------------------------------- ------
-- Temp and Profile Pressure --
Temp folder size healthy                     WARN
User profiles size signal                    WARN
Disk queue pressure                          WARN
-- Top Writers --
Top writer sample collected                  OK

=== RESULT: 1 OK / 0 FAIL / 3 WARN ===
```

## Learn References

- https://learn.microsoft.com/azure/virtual-machines/troubleshooting/azure-windows-vm-memory-issue
- https://learn.microsoft.com/azure/virtual-machines/troubleshooting/poor-performance-emulated-storage-stack
- https://learn.microsoft.com/azure/virtual-machines/troubleshooting/troubleshoot-high-cpu-issues-azure-windows-vm
