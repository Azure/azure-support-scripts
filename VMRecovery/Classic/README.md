# WARNING: This preliminary release of the VM recovery scripts should only be used with the assistance of a Microsoft support engineer when working on a support incident.

# Overview

If an Azure VM is inaccessible it may be necessary to attach the OS disk to another Azure VM in order to perform recovery steps. The VM recovery scripts automate the recovery steps below.

- Delete the VM but keep the disks.
- Attach the OS disk to another Azure VM as a data disk.
- Logon to that VM and fix the disk manually.
- Detach the disk and recreate the original VM using the recovered OS disk.

# Supported VM Types

This version of the VM recovery script is for for use with Azure VMs created using Classic deployment model. Both Linux and Windows guests are supported. For VMs created using the Resource Manager deployment model, use the version located under \ResourceManager instead of \Classic.

# Scenarios

## When would you use the script?
If a Windows VM in Azure does not boot. Typically in this scenario VM screenshot from [boot diagnostics] (https://azure.microsoft.com/en-us/blog/boot-diagnostics-for-virtual-machines-v2/) does not show login screen but a boot issue.

### Execution guidance 
1. Download and extract the azure-support-scripts repo to a local folder:

   https://github.com/Azure/azure-support-scripts/archive/master.zip  
   
   Or if you have the Git client installed you can use the following command:
```PowerShell
   git clone https://github.com/Azure/azure-support-scripts <local folder>
```
2. Launch Azure Powershell and and execute. 
```PowerShell
.\New-AzureRescueVM.ps1 <cloud service name> <vm name>
```
3. Log on to the rescue VM created by the script to fix the problem VM's OS disk.

4. To recreate the problem VM, run:
```PowerShell
.\Restore-AzureOriginalVM <cloud service name> <rescue vm name>
```

## Parameters or input
- Cloud service name
- VM name

## Supported platforms/dependencies
 - Azure PowerShell 5.1.14393 or later.
