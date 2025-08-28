# Enable Windows Update

## Overview
This RunCommand script configures registry settings to **re-enable automatic Windows Updates** on an Azure Virtual Machine.  
It ensures the required registry paths exist and applies update policies to allow automatic download and installation.

## What the Script Does
- Ensures the registry path exists:  
  `HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU`  
  - Sets `NoAutoUpdate = 0` → Enables automatic updates  
  - Sets `AUOptions = 4` → Automatically download and install updates  

- Configures scheduled maintenance settings under:  
  `HKLM:\Software\Policies\Microsoft\Windows\Task Scheduler\Maintenance`  
  - `Activation Boundary = 2000-01-01T01:00:00`  
  - `Randomized = 1`  
  - `Random Delay = PT4H`  

## Important Notes

- **Security Best Practice**: Keeping Windows Update enabled ensures your VM receives critical security patches.  
- **Automatic Updates**: The configuration enables full automatic download and installation of updates.  
- **Maintenance Settings**: Updates may install during scheduled maintenance windows, with randomized delays applied to avoid resource contention.  
- **Manual Control**: You can still manually check for and install updates via **Windows Update**.  

## Usage

1. Run the script using **Azure VM RunCommand** or another remote execution method.  
2. Confirm the registry values under:  
   - `HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU`  
   - `HKLM\Software\Policies\Microsoft\Windows\Task Scheduler\Maintenance`  
3. Verify automatic update settings in the **Windows Update** control panel.  

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
