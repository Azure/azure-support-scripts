# Remote Desktop (RDP) Settings Check and Configuration

## Overview
This RunCommand script inspects and configures **Remote Desktop Services (RDP)** related registry settings on an Azure Virtual Machine.  
It ensures that key RDP policies align with expected values. If the VM is **domain joined**, it outputs discrepancies for Group Policy correction.  
If the VM is **not domain joined**, it resets non-compliant registry values directly.

## What the Script Does
- Determines whether the VM is domain joined.  
  - If domain joined → Reports mismatches (requires Group Policy adjustment).  
  - If not domain joined → Resets registry keys to expected defaults.  
- Checks and validates settings such as:
  - RDP port number  
  - Remote Desktop connection allowance  
  - Keep-alive intervals  
  - Automatic reconnection  
  - Session time limits  
  - Connection limits  
  - Listening adapters and drain mode  

  ## Important Notes

- **Domain vs Non-Domain Behavior**:  
  - On **domain-joined VMs**, settings are reported but not enforced (must be fixed via Group Policy).  
  - On **non-domain-joined VMs**, settings are reset directly.  

- **Security Impact**: RDP settings affect how and when remote connections are allowed. Misconfiguration may expose the VM to unwanted access.  
- **Policy Alignment**: Ensures consistency between registry configuration and RDP Group Policy settings.  
- **Troubleshooting Aid**: Helps identify misaligned RDP policies that may cause session, timeout, or reconnection issues.  

## Usage

1. Run the script using **Azure VM RunCommand** or another remote execution method.  
2. Review the output in the Azure portal or shell window:  
   - If **domain joined** → Apply necessary fixes in **Group Policy**.  
   - If **not domain joined** → The script resets registry values automatically.  
3. Verify **Remote Desktop connectivity** and session behavior as required.  

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
