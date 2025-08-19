# Set RDP Port

## Overview
This RunCommand script configures the **Remote Desktop Protocol (RDP)** listener port on a Windows VM.  
By default, RDP uses port **3389**, but this script allows customization of the port and automatically updates firewall rules to match.

## What the Script Does
- Ensures RDP connections are enabled by setting `fDenyTSConnections = 0`.  
- Reads the current RDP port from the registry and compares it to the desired port.  
- If the port is different, updates it and restarts the **TermService**.  
- Configures Windows Firewall rules:  
  - If port is **3389**, enables the default **Remote Desktop** firewall group.  
  - If port is **custom**, creates a new firewall rule for the specified port.  

## Important Notes

- **Security Risk**: Changing the RDP port does not eliminate brute-force risk. Always combine with strong passwords, Network Security Groups (NSGs), or Just-In-Time (JIT) access.  
- **Service Restart**: Restarting the **TermService** will briefly disconnect all active RDP sessions.  
- **Firewall Rules**: The script ensures the firewall allows inbound RDP on the new port.  
- **Client Access**: After changing the port, users must specify the custom port when connecting (e.g., `mstsc /v:vmname:port`).  

## Usage

1. Run the script using **Azure VM RunCommand** or another remote execution method.  
2. If using a **custom port**, update your **Azure NSG** or firewall rules to allow the port.  
3. Reconnect using the new port:  
   - Example: `mstsc /v:10.0.0.5:4444`  

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
