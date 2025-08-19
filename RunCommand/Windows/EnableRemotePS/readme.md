# Enable PowerShell Remoting over HTTPS

## Overview
This RunCommand script configures **PowerShell Remoting (WinRM)** on a Windows VM, secured with HTTPS.  
It enables remote management, creates a self-signed certificate, and updates the firewall to allow inbound WinRM connections.

## What the Script Does
- Runs `Enable-PSRemoting -Force` to configure WinRM service defaults.  
- Creates a new firewall rule to allow inbound HTTPS traffic on **port 5986**.  
- Generates a self-signed certificate for the VM hostname.  
- Configures a WinRM listener bound to the self-signed certificate.  

## Important Notes

- **Security Consideration**: This script creates a self-signed certificate, which is not trusted by default. For production, replace with a certificate from a trusted CA.  
- **Firewall Rules**: Opens port **5986 (HTTPS)** for inbound WinRM traffic across all profiles. Ensure NSG or perimeter firewall rules also allow traffic.  
- **Remote Management**: Once enabled, remote systems can use PowerShell remoting with HTTPS (e.g., `Enter-PSSession -ComputerName <vm> -UseSSL`).  
- **Credentials Required**: Users must authenticate with valid local or domain credentials.  

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt, these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
