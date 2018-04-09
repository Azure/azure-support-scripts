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
1. Download and extract the entire project folder https://github.com/Azure/azure-support-scripts/archive/master.zip to c:\azscripts\ (or custom)
2. Or pull it using git client github-windows://openRepo/https://github.com/Azure/azure-support-scripts
3. Open Azure Powershell and and execute. 
```PowerShell
Step 1 c:\azscripts\RecoverVM\Classic\New-AzureRescueVM.ps1 MYCLOUDSERVICENAME MYVMNAME
Step 2 Log to the Recovery VM created in step 1 fix OSDisk issues and follow instruction to run
Step 3 c:\azscripts\RecoverVM\Classic\Restore-AzureOriginalVM MYCLOUDSERVICENAME <NameofRecoveryVM that was created in step 1>
```
4. Follow the instructions in the script output.

## Parameters or input
- Cloud service name
- VM name

## Supported platforms/dependencies
 - Azure PowerShell 5.1.14393 or later.
