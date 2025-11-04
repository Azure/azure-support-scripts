
# Azure VM - Windows Ghosted NIC Check Removal Script

This PowerShell script is used to detect and remove 'ghosted nic' inside of the VM. A VM that has one ore more could experienced issues with connect to the VM or Windows Update could fail.  This script detects ghosted (disconnected) which are network interface cards (NICs) that are not valid.

## Features

- Detects for Ghosted Nics
- Removes Ghosted Nics

## Prerequisites

- PowerShell 5.1 or later (earlier versions may not support `-NoProxy`).

## Usage

<h3 style="color:red;">⚠️ IMPORTANT: It is strongly recommended to back up your VM before running this script.
Removing ghosted NICs modifies registry entries and device configurations.
Ensure you have a recovery point or snapshot in case rollback is needed.</h3>

Run the script in PowerShell **within an Azure VM**:

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_GhostedNIC_Removal_time.ps1
```


