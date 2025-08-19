# Reset RDP Certificate

## Overview
This RunCommand script clears the existing **Remote Desktop Protocol (RDP) security certificate bindings** from the Windows registry and resets encryption settings.  
It is typically used when RDP connections fail due to certificate corruption, expired bindings, or misconfigured encryption policies.

## What the Script Does
- Removes the registry value `SSLCertificateSHA1Hash` from:
  - `HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp`  
  - `HKLM:\SYSTEM\ControlSet001\Control\Terminal Server\WinStations\RDP-Tcp`  
  - `HKLM:\SYSTEM\ControlSet002\Control\Terminal Server\WinStations\RDP-Tcp`  
- Resets RDP security settings:  
  - `MinEncryptionLevel = 1` → Sets minimum encryption to **Client Compatible**.  
  - `SecurityLayer = 0` → Forces RDP Security Layer (disables TLS/SSL).  
- Restarts the **Remote Desktop Services (TermService)** to apply changes.

## Important Notes

- **Security Risk**: Resetting encryption and security layer weakens RDP protection by disabling TLS. This should only be done for troubleshooting.  
- **Certificates Regenerated**: On restart, RDP will automatically generate a new self-signed certificate if none is present.  
- **Service Restart**: Restarting the **TermService** temporarily disconnects all active RDP sessions.  
- **Post-Troubleshooting**: Reconfigure stronger encryption and TLS once connectivity issues are resolved.  

## Usage

1. Run the script using **Azure VM RunCommand** or another remote execution method.  
2. Allow the **TermService** to restart and rebind a new certificate.  
3. Attempt a new RDP connection to confirm certificate reset.  

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
