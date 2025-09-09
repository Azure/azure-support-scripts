# ifconfig (Linux RunCommand)

## Overview
This Azure VM RunCommand script runs the **`ifconfig`** command on a Linux virtual machine.  
It displays detailed configuration information for all available network interfaces.

## What the Script Does
- Executes the `ifconfig` command with optional arguments.  
- Returns details about network interfaces, including:  
  - Interface name (e.g., `eth0`, `lo`)  
  - IPv4 and IPv6 addresses  
  - Subnet mask  
  - Broadcast address  
  - MAC address  
  - RX/TX packet statistics  

## Important Notes

- **Diagnostics Only**: This command outputs configuration details but does not change network settings.  
- **Deprecation Notice**: On some Linux distributions, `ifconfig` is deprecated in favor of `ip addr show`. Ensure `ifconfig` is installed (`net-tools` package).  
- **Security Consideration**: Output may include private IPs and MAC addresses — handle logs carefully.  
- **Use Cases**: Helpful for diagnosing DNS resolution, IP conflicts, or verifying VM NIC configuration.  

## Usage

1. Run the command using **Azure VM RunCommand** or SSH.  
2. Optionally pass arguments (e.g., `ifconfig eth0`) using the **arguments** parameter.  
3. Review the output to troubleshoot or document network configuration.  

## Liability
As described in the [MIT license](LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
