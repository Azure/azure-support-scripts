# Windows Update Pipeline Health

> Tool focus: Windows Update servicing pipeline triage for Azure Windows VMs.

## What It Checks

- Core services: `wuauserv`, `BITS`, `UsoSvc`
- Pending reboot gates (WU/CBS)
- CBS servicing corruption signal
- Recent update error volume

The script is read-only and safe for first-contact diagnostics.

## How To Run

```powershell
.\Windows_WindowsUpdate_Pipeline_Health.ps1
```

Mock/offline validation:

```powershell
.\Windows_WindowsUpdate_Pipeline_Health.ps1 -MockConfig .\mock_config_sample.json
```

## Mock Output Example

```
=== Windows Update Pipeline Health ===
Check                                        Status
-------------------------------------------- ------
-- Core Services --
Windows Update service state                 WARN
BITS service state                           OK
UsoSvc service state                         OK
-- Pending Reboot / Servicing --
Pending reboot not blocking                  WARN
CBS corruption signal                        WARN
Recent WU error count low                    OK

=== RESULT: 3 OK / 0 FAIL / 3 WARN ===
```

## Learn References

- https://learn.microsoft.com/azure/virtual-machines/troubleshooting/windows-update-installation-capacity
- https://learn.microsoft.com/azure/virtual-machines/troubleshooting/windows-update-errors-requiring-in-place-upgrade
- https://learn.microsoft.com/azure/virtual-machines/troubleshooting/windows-vm-wureset-tool
