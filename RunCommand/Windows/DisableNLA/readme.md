# Disable Network Level Authentication (NLA) for RDP

## Overview
This RunCommand script disables **Network Level Authentication (NLA)** on an Azure Virtual Machine.  
NLA requires users to authenticate before establishing a remote desktop session.  
Disabling NLA may be necessary when troubleshooting RDP connectivity or when older clients need access.

## What the Script Does
- Updates the Windows Registry to disable NLA:
  - **Registry Path:** `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp`
  - **Property:** `UserAuthentication`
  - **Value:** `0` (Disabled)

- Outputs a status message during configuration.
- Reminds the administrator that **a VM restart is required** for changes to take effect.

## Important Notes

- **Security Risk**: Disabling NLA lowers security because users can connect to the RDP service without pre-authentication. This should only be done for troubleshooting or compatibility reasons.  
- **Restart Required**: The VM must be restarted before the setting takes effect.  
- **Re-enable NLA**: To re-enable, set the same registry key `UserAuthentication` back to `1`.  

## Usage

1. Run the script using **Azure VM RunCommand** or another remote execution method.  
2. Restart the VM.  
3. Verify RDP connectivity without NLA.  

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
