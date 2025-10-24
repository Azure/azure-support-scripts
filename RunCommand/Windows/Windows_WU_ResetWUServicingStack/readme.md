# Windows Update Servicing Stack Reset Script


This PowerShell script is designed to **reset Windows Update components** on Azure virtual machines (VMs). It performs a series of actions that can help resolve update failures, corruption issues, or stuck servicing stack states.

> [!WARNING]
> This script performs **destructive actions**, including renaming system folders and re-registering DLLs.  
> Use with caution and ensure you have backups or snapshots before running.

## What It Does



1. **Stops Windows Update Services**

- Stops `wuauserv`, `cryptsvc`, and `bits` services to allow component reset.

2. **Renames Critical Folders**

- Renames `SoftwareDistribution` and `Catroot2` folders to `.old` to clear cached update data.

3. **Re-registers Core DLLs**

- Iterates through a list of Windows Update–related DLLs and re-registers them using `regsvr32`.

4. **Restarts Services**

- Restarts the previously stopped services to restore update functionality.


## Prerequisites

- Must be run as **Administrator**.
- PowerShell 5.1 or higher.


## How to Execute

1. Download the file:  
https://github.com/Azure/azure-support-scripts/blob/master/RunCommand/Windows/Windows_WU_ResetWUServicingStack/Windows_WU_ResetWUServicingStack.ps1


From an elevated PowerShell window, navigate to the download directory and run:

```
Set-ExecutionPolicy Bypass -Force
.\\Windows_WU_ResetWUServicingStack.ps1
```

## Script Output

The script outputs progress messages in a color-coded format:

| Symbol | Color  | Meaning                                      |
|--------|--------|---------------------------------------------|
| ✅     | Green  | Completed successfully                      |
| ⚠️     | Yellow | Warning or skipped action (e.g., DLL not found) |
| ❌     | Red    | Error during execution                      |


## Optional Post-Reset Checks

After running the script, you can verify update history and servicing state:

```
dism /online /get-packages /format:table
Get-HotFix
```

## Liability
As described in the ......\\LICENSE.txt, these scripts are provided as-is with no warranty or liability associated with their use.

# Provide Feedback
We value your input. If you encounter problems or have suggestions, please file an issue in the https://github.com/Azure/azure-support-scripts/issues section of the project.