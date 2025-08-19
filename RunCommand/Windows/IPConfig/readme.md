# Run ipconfig /all

## Overview
This RunCommand script executes the **`ipconfig /all`** command on an Azure Virtual Machine.  
It provides a detailed view of the system’s network configuration, useful for troubleshooting connectivity or verifying settings.

## What the Script Does
- Runs the command:
  ```powershell
  ipconfig /all

## Displays detailed information about all network adapters, including:

- Hostname  
- DNS suffix  
- IP addresses (IPv4/IPv6)  
- Subnet mask  
- Default gateway  
- DHCP status  
- DNS servers  
- MAC addresses  

## Important Notes

- **Diagnostics Only**: This script collects and displays network configuration details but does not change any settings.  
- **Security Consideration**: Output may contain sensitive details such as IP addresses and DNS servers — handle logs carefully.  
- **Use Cases**: Helpful for diagnosing RDP connectivity, DNS resolution issues, and verifying network adapter configuration.  

## Usage

1. Run the script using **Azure VM RunCommand** or another remote execution method.  
2. Review the output in the **Azure portal** or **command line** for network details.  
3. Use results for troubleshooting or documenting VM network configuration.  

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
