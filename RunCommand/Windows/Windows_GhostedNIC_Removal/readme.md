# Azure VM - Windows Ghosted NIC Check Removal Script

This PowerShell script is used to detect and remove 'ghosted nic' inside of the VM. A VM that has one ore more could experienced issues with connect to the VM or Windows Update could fail.  This script detects ghosted (disconnected) which are network interface cards (NICs) that are not valid.

## Features

- Detects for Ghosted Nics
- Removes Ghosted Nics

## Prerequisites

- PowerShell 5.1 or later
- Must be executed within an Azure VM

## Usage

<h3 style="color:red;">⚠️ IMPORTANT: It is strongly recommended to back up your VM before running this script.
Removing ghosted NICs modifies registry entries and device configurations.
Ensure you have a recovery point or snapshot in case rollback is needed.</h3>

Run the script in PowerShell **within an Azure VM**:

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_GhostedNIC_Removal.ps1
```

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues

