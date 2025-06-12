# Windows activation validation

This PowerShell script is designed to assist with diagnosing Windows licensing and connectivity issues on Azure virtual machines (VMs). It performs a series of checks to verify:

- Whether the system is running an Azure-specific Windows edition
- Connectivity to the Azure Instance Metadata Service (IMDS)
- Presence and validity of attested certificates
- The configured Key Management Service (KMS) endpoint
- TCP connectivity to the KMS server
- Windows activation status

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
