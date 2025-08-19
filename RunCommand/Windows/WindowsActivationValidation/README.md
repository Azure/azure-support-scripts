# Windows activation validation

This PowerShell script is designed to assist with diagnosing Windows licensing and connectivity issues on Azure virtual machines (VMs). It performs a series of checks to verify:


## What It Does

1. **WinRM Service Check**  
   - Ensures the `WinRM` service is running.
   - Attempts to start the service if it's not already running.

2. **Azure Edition Detection**  
   - Detects if the machine is using an **Azure edition** of Windows.
   - Verifies connectivity to the **Azure Instance Metadata Service (IMDS)**.
   - Checks for any missing root certificates in the attestation document.

3. **KMS Endpoint Validation**  
   - Retrieves the configured KMS endpoint from the Windows registry.
   - Falls back to the default Azure KMS endpoint if none is found.
   - Tests TCP connectivity to the KMS endpoint on port `1688`.

4. **Windows Activation Check & Attempt**  
   - Checks current activation status.
   - If not activated, attempts to activate using `slmgr.vbs`.
   - Parses and displays activation error codes with direct links to Microsoft troubleshooting documentation.


# Prerequisites

 - PowerShell 5.1 or higher

# Usage

## Manual download and run
Download:
```powershell
Invoke-WebRequest -Uri https://github.com/Azure/azure-support-scripts/blob/master/Windows_scripts/WindowsActivationValidation/WindowsActivationValidation.ps1 -OutFile WindowsActivationValidation.ps1
```
Run the script:
```powershell
Set-ExecutionPolicy Bypass -Force
.\WindowsActivationValidation.ps1
```
## Download from browser
 1. Download the file ```xxxx.ps1``` [from a web browser.](https://github.com/Azure/azure-support-scripts/blob/master/Windows_scripts/WindowsActivationValidation/WindowsActivationValidation.ps1)
 1. From an elevated PowerShell window, ensure you're in the same directory that you downloaded the script to, then run the following to run the script:
 ```powershell
Set-ExecutionPolicy Bypass -Force
.\WindowsActivationValidation.ps1
```

# Analyzing output

## 🧪 Script Output

The script provides detailed output using color-coded messages in the PowerShell console:

| Symbol | Color        | Meaning                                                                 |
|--------|--------------|-------------------------------------------------------------------------|
| ✅     | **Green**     | Successful operations (e.g., connection established, activation valid)   |
| ⚠️     | **Yellow**    | Warnings or non-critical issues (e.g., non-default KMS endpoint, certificates) |
| ❌     | **Red**       | Errors or failures (e.g., certificate chain issues, activation failure, IMDS not reachable) |


If you open a support request, please include both of the above files to aid your support representative in helping you.

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues

