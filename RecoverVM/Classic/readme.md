# Overview
Occasionally Azure IaaS VMs may not start because there is something wrong with the operating system (OS) disk preventing it from booting up correctly.
In such cases it is a common practice to recover the problem VM by performing the following steps:

- Delete the VM (but keep the disks)
- Attach the disk(s) to another bootable VM as a Data Disk
- Fix the disk manually.
- Detach the disk and recreate the original VM using the recovered operating system disk

> the full details on this recovery process are explained in this blog post:
> https://blogs.msdn.microsoft.com/mast/2014/11/20/recover-azure-vm-by-attaching-os-disk-to-another-azure-vm/

# Current version supports
- Classic VM Microsoft.ClassicCompute/virtualMachines
- Windows 2008 R2 - 2012 R2

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
 


