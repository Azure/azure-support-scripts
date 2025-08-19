# Enable Emergency Management Services (EMS)

## Overview
This RunCommand script enables **Emergency Management Services (EMS)** on an Azure Virtual Machine.  
EMS provides out-of-band management and debugging access via a serial port, which can be useful for troubleshooting unresponsive systems.

## What the Script Does
- Enables EMS on the **current boot entry**.  
- Configures EMS settings to use:
  - **Port:** COM1  
  - **Baud Rate:** 115200  

## Important Notes

- **Security Risk**: EMS provides low-level access to the system. Ensure that only trusted administrators have access to the serial console.  
- **Azure Serial Console**: EMS must be enabled for the VM to use Azure’s built-in **Serial Console** for troubleshooting.  
- **Reboot Required**: A VM reboot is required for EMS settings to take effect.  
- **Disable if not needed**: EMS should be disabled when not actively in use to reduce exposure.  

## Usage

1. Run the script using **Azure VM RunCommand** or another remote execution method.  
2. Restart the VM for the EMS configuration to take effect.  
3. Access the VM via the **Azure Serial Console** or other supported tools.  


## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
