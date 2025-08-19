# Enable Built-in Administrator Account

## Overview
This RunCommand script enables the **built-in Windows Administrator account** on an Azure Virtual Machine.  
It detects whether the account (SID ending with `-500`) is disabled and re-enables it if necessary.

## What the Script Does
- Queries the local accounts to find the built-in Administrator account (`SID = S-1-5-21-*-500`).  
- If the account is **disabled**, the script enables it.  
- If the account is already **enabled**, it outputs a status message.

## Important Notes

- **Security Risk**: The built-in Administrator account is a common attack target. Enabling it may increase exposure to brute-force or privilege escalation attacks.  
- **Password Management**: Ensure the Administrator account has a strong, unique password before enabling.  
- **Audit Logs**: Monitor login activity for the built-in Administrator account after enabling.  
- **Disable if not needed**: Once troubleshooting or administrative tasks are complete, consider disabling the account again.  

## Usage

1. Run the script using **Azure VM RunCommand** or another remote execution method.  
2. Verify that the **Administrator** account is enabled in **Computer Management → Local Users and Groups**.  
3. Log in with the configured Administrator credentials if needed.  

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
