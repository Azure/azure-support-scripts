# VM assist

VM assist (Windows version) is a PowerShell script intended to be used to diagnose issues with the Azure Windows VM Guest Agent in addition to other issues related to the general health of the VM. This includes various information about the system such as firewall rules, running services, running drivers, installed software, NIC settings, and installed software, and installed Windows Updates.

Output of the checks can be viewed in the PowerShell window the script is ran in. Additionally running VM assist generates a detailed .htm report showing the results of each check it performs and suggests mitigations for issues it finds.

# Prerequisites

 - Windows Server 2012 R2 and later versions of Windows
 - Windows Powershell 4.0+ and PowerShell 6.0+

# Usage

## Automatic download and run (recommended)
RDP into the VM and from an elevated PowerShell window run the following to download and run the script: 
```powershell
Set-ExecutionPolicy Bypass -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
(Invoke-WebRequest -Uri https://aka.ms/vmassist -OutFile vmassist.ps1) | .\vmassist.ps1
```

## Manual download and run
Download:
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri https://aka.ms/vmassist -OutFile vmassist.ps1
```

Run the script:
```powershell
Set-ExecutionPolicy Bypass -Force
.\vmassist.ps1
```

# Analyzing output

The script will run a series of checks to analyze the health of the VM Guest Agent and check for various known configurations that could cause issues. Each check will either pass or fail in the PowerShell window. 

Once completed, it will also generate a log file and an html report:
 - C:\logs\vmassist_*.log
 - C:\logs\vmassist_*.htm

The .log file will have a copy of the results that are displayed in the PowerShell window for later reference.

The .htm file is a report that shows all of the checks and findings along with information on how to mitigate any issues it found. It will also have additional information about the OS and the VM that can further assist in troubleshooting any issues that are found.

If you open a support request, please include both of the above files to aid your support representative in helping you.


