
# Azure VM Attested Metadata Verification Script

This PowerShell script is used to verify the attestation signature provided by the Azure Instance Metadata Service (IMDS). It helps ensure that the certificate used in the attestation is valid and trusted by attempting to build a certificate chain. This can be useful in verifying the integrity and authenticity of an Azure VM's identity.

## Features

- Fetches attested metadata from the Azure Instance Metadata Service.
- Extracts and decodes the signature.
- Attempts to build a certificate chain for verification.
- Warns if any certificates in the chain are missing and provides a link to Microsoft’s documentation.

## Prerequisites

- PowerShell 5.1 or later (earlier versions may not support `-NoProxy`).
- Must be executed within an Azure VM (as it accesses the instance metadata endpoint).

## Usage

Run the script in PowerShell **within an Azure VM**:

```powershell
Invoke-WebRequest -Uri https://github.com/Azure/azure-support-scripts/blob/master/IMDSCertCheck/IMDSCertCheck.ps1 -OutFile IMDSCertCheck.ps1
Set-ExecutionPolicy Bypass -Force
.\IMDSCertCheck.ps1
```

## Troubleshooting

If you see the message:

```
Certificate not found: 'CN=Microsoft Azure XXXX, ...'
Please refer to the following link to download missing certificates:
https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details?tabs=certificate-authority-chains
```

Visit the provided Microsoft documentation to download and install the necessary root/intermediate certificates.

## References

- [Azure Instance Metadata Service](https://learn.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service)
- [Azure Certificate Authority Details](https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details)

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
