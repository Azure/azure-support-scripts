# Windows activation validation

Windows activation validation is a PowerShell script intended to be used to diagnose issues with the Azure Windows VM and activation issues. This includes various information about the system such as firewall rules, running services, running drivers, installed software, NIC settings, and installed software, and installed Windows Updates.

Output of the checks can be viewed in the PowerShell window the script is ran in. 

# Prerequisites

 - Windows Server 2012 R2 and later versions of Windows
 - Windows Powershell 4.0+ and PowerShell 6.0+

# Usage

## Automatic download and run (recommended)
RDP into the VM and from an elevated PowerShell window run the following to download and run the script: 
```powershell
Set-ExecutionPolicy Bypass -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
(Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/azure-support-scripts/master/xxxx.ps1 -OutFile vmassist.ps1) | .\vmassist.ps1
```

## Manual download and run
Download:
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/azure-support-scripts/master/xxxx.ps1 -OutFile vmassist.ps1
```
Run the script:
```powershell
Set-ExecutionPolicy Bypass -Force
.\xxxx.ps1
```
## Download from browser
 1. Download the file ```xxxx.ps1``` [from a web browser.](https://github.com/Azure/azure-support-scripts/blob/master/xxxxx.ps1)
 1. From an elevated PowerShell window, ensure you're in the same directory that you downloaded the script to, then run the following to run the script:
 ```powershell
Set-ExecutionPolicy Bypass -Force
.\xxxxx.ps1
```

# Analyzing output

The script will run a series of checks to analyze the health of the VM Guest Agent and check for various known configurations that could cause issues. Each check will either pass or fail in the PowerShell window. 

xxxxxx

If you open a support request, please include both of the above files to aid your support representative in helping you.
