# Azure VM - Windows Ghosted NIC Check Time Warning Script

This PowerShell script is used to detect if there are 'ghosted nic' inside of the VM. A VM that has one ore more could experienced issues with connect to the VM or Windows Update could fail.This script detects ghosted (disconnected) network interface cards (NICs) and remove them from the registry.

## Features

- Detects for Ghosted Nics

## Prerequisites

- PowerShell 5.1 or later
- Must be executed within an Azure VM

## Usage

Run the script in PowerShell **within an Azure VM**:

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_GhostedNIC_Detection.ps1
```


### Awareness
Cleanup may take time depending on the number of ghosted NICs detected.

- Up to 30 minutes if ~600 ghosted NICs are found.
- Up to 60+ minutes if over 1000 ghosted NICs are found.

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues