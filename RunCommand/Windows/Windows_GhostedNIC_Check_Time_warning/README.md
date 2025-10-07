
# Azure VM - Windows Ghosted NIC Check Time Warning Script

This PowerShell script is used to detect if there are 'ghosted nic' inside of the VM. A VM that has one ore more could experienced issues with connect to the VM or Windows Update could fail.This script detects ghosted (disconnected) network interface cards (NICs) and remove them from the registry.

## Features

- Detects for Ghosted Nics
- Removes Ghosted Nics

## Prerequisites

- PowerShell 5.1 or later (earlier versions may not support `-NoProxy`).

## Usage

Run the script in PowerShell **within an Azure VM**:

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_GhostedNIC_Check_Time_warning.ps1
```

### Cleanup may take time depending on the number of ghosted NICs detected.
- Up to 30 minutes if ~600 ghosted NICs are found.
- Up to 60+ minutes if over 1000 ghosted NICs are found.

