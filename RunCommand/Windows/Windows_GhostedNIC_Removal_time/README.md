
# Azure VM - Windows Ghosted NIC Check Time Warning Script

This PowerShell script is used to detect if there are 'ghosted nic' inside of the VM. A VM that has one ore more could experienced issues with connect to the VM or Windows Update could fail.This script detects ghosted (disconnected) which are network interface cards (NICs) that are notr valid.

## Features

- Fetches attested metadata from the Azure Instance Metadata Service.
- Extracts and decodes the signature.
- Attempts to build a certificate chain for verification.
- Warns if any certificates in the chain are missing and provides a link to Microsoft’s documentation.

## Prerequisites

- PowerShell 5.1 or later (earlier versions may not support `-NoProxy`).

## Usage

<h3 style="color:red;">⚠️ IMPORTANT: It is strongly recommended to back up your VM before running this script.
Removing ghosted NICs modifies registry entries and device configurations.
Ensure you have a recovery point or snapshot in case rollback is needed.</h3>

Run the script in PowerShell **within an Azure VM**:

```powershell
Invoke-WebRequest -Uri https://github.com/Azure/azure-support-scripts/blob/master/Windows_GhostedNIC_Removal_time/Windows_GhostedNIC_Removal_time.ps1 -OutFile Windows_GhostedNIC_Removal_time.ps1
Set-ExecutionPolicy Bypass -Force
.\Windows_GhostedNIC_Removal_time.ps1
```


