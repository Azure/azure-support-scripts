# Overview
Occasionally Azure IaaS VMs may not start because there is something wrong with the operating system (OS) disk preventing it from booting up correctly.
In such cases it is a common practice to recover the problem VM by performing the following steps:

- Delete the VM (but keep the disks)
- Attach the disk(s) to another bootable VM as a Data Disk
- Run the script https://github.com/azure/azpstools/blob/master/FixDisk/TS_RecoveryWorker2.ps1 as an elevated administrator from the recovery VM
- Detach the disk and recreate the original VM using the recovered operating system disk

> the full details on this recovery process are explained in this blog post:
> https://blogs.msdn.microsoft.com/mast/2014/11/20/recover-azure-vm-by-attaching-os-disk-to-another-azure-vm/

# Current version supports
- run chkdsk do fix file system corruptions
- run sfc to replace invalid system files
- reconfigure boot configuration (bcdedit) (supports multi partion layouts)
- collect a list of invalid system files that were not recovered and writes it to c:\WindowsAzure\Logs\ChkDsk-SysReg.log on the recovery VM

# Scenarios

##  When would you use the script?
If a Windows VM in Azure does not boot. Typically in this scenario VM screenshot from [boot diagnostics] (https://azure.microsoft.com/en-us/blog/boot-diagnostics-for-virtual-machines-v2/) does not show login screen but a boot issue.

# Execution guidance
The script must be executed with elevated previleges from a working Windows VM that has a data disk attached.  

## Parameters or input
- NONE

# Supported Platforms / Dependencies
The VM running the recovery script must:
- be running Windows 2008 - 2012R2
- have PowerShell installed


