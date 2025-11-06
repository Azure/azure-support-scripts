# Windows Duplicate SID Validation

## Overview
`Windows_DuplicateSID_Detection.ps1` is a PowerShell script that scans the **netsetup.log** file on a Windows system to detect indicators of **duplicate Security Identifier (SID)** or machine account conflicts. These issues typically occur when a computer account already exists in Active Directory or when a SID mismatch prevents domain join operations.

## Features

- Reads the `netsetup.log` file to identify patterns that indicate:
  - **Account already exists** errors.
  - **NetUserAdd failed: 0x8b0** (commonly linked to SID conflicts).
- Summarizes whether a duplicate SID or machine account issue was detected.
- Provides a reference link to official Microsoft documentation for troubleshooting.

## Prerequisites

- PowerShell 5.1 or later
- Must be executed within an Azure VM 

## Usage

Run the script in PowerShell **within an Azure VM**:

```powershell
Set-ExecutionPolicy Bypass -Force
.\ Windows_DuplicateSID_Detection.ps1
```

## Troubleshooting

Visit the provided Microsoft documentation to remediate. 

## References

- [Windows Duplicate SID issue](https://learn.microsoft.com/troubleshoot/windows-server/identity/machine-account-duplicate-sid)

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues