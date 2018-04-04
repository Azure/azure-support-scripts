# WARNING: This preliminary release of the VM recovery scripts should only be used with the assistance of a Microsoft support engineer when working on a support incident.

# Overview

If an Azure VM is inaccessible it may be necessary to attach the OS disk to another Azure VM in order to perform recovery steps. The VM recovery scripts automate the recovery steps below.

- Delete the VM but keep the disks.
- Attach the OS disk to another Azure VM as a data disk.
- Logon to that VM and fix the disk manually.
- Detach the disk and recreate the original VM using the recovered OS disk.

# Supported VM Types

The VM recovery scripts are supported for use with Azure VMs created with the Classic deployment model. Both Linux and Windows guests are supported.

# Scenarios

## When would you use the script?
If a Windows VM in Azure does not boot. Typically in this scenario VM screenshot from [boot diagnostics] (https://azure.microsoft.com/en-us/blog/boot-diagnostics-for-virtual-machines-v2/) does not show login screen but a boot issue.

### Execution guidance 
- download and extract the entire project folder https://github.com/Azure/azure-support-scripts/archive/master.zip to c:\azscripts\ (or custom)
- Or pull it using git client github-windows://openRepo/https://github.com/Azure/azure-support-scripts
- Open Azure Powershell and and execute
 

```PowerShell
Step 1 c:\azscripts\RecoverVM\Classic\New-AzureRescueVM.ps1 MYCLOUDSERVICENAME MYVMNAME
Step 2 Log to the Recovery VM created in step 1 fix OSDisk issues and follow instruction to run
Step 3 c:\azscripts\RecoverVM\Classic\Restore-AzureOriginalVM MYCLOUDSERVICENAME <NameofRecoveryVM that was created in step 1>
```


- Follow the instructions and be patient (it may take between 15mins and multiple hours [if disk repair takes long])

## Parameters or input
- hosting service name (cloud service name)
- VM name

## Supported Platforms / Dependencies
 - current version of Azure PowerShell (Tested with 5.1.14393)
 


