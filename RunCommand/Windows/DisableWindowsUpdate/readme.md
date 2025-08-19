# Disable Windows Update

## Overview
This RunCommand script configures registry settings to disable **automatic Windows Updates** on an Azure Virtual Machine.  
It creates the required registry path (if missing) and applies update policies that prevent automatic update installation.

## What the Script Does
- Ensures the registry path exists:
  - **Path:** `HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU`
- Sets the following values:
  - `NoAutoUpdate = 1` → Disables automatic updates  
  - `AUOptions = 3` → Allows downloads but requires user/admin approval before installing  


## Important Notes

- **Security Risk**: Disabling automatic updates may leave the VM vulnerable to security risks. Ensure you have a patch management process in place before applying this configuration.  
- **Manual Updates**: After applying this script, updates must be installed manually via **Windows Update** or other patching tools.  
- **Re-enable Automatic Updates**: To re-enable automatic updates, set `NoAutoUpdate = 0` and configure `AUOptions` as desired.  

## Usage

1. Run the script using **Azure VM RunCommand** or another remote execution method.  
2. Confirm the registry values under:  `HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU`  
3. Verify update settings in the **Windows Update** control panel.  

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
