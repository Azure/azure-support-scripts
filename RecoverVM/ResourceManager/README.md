# WARNING: This preliminary release of the VM recovery scripts should only be used with the assistance of a Microsoft support engineer when working on a support incident.

# Overview
If an Azure VM is inaccessible it may be necessary to attach the OS disk to another Azure VM in order to perform recovery steps. The VM recovery scripts automate the recovery steps below.

- Stop VM
- Take a snapshot of the OS Disk
- Create a Temporary Rescue VM
- Attach the OS Disk to the Rescue VM
- RDP to RescueVM
- From the Rescue VM and fix the disks manually.
- Detach the Data disk from Rescue VM
- Perform Disk Swap to point the OsDisk.Vhd.Uri to the recovered OS Disk Uri
- Finally Remove all the resources that were created for the Rescue VM

## Current version supports 
    Microsoft.Compute/virtualMachines (Non-Managed VM's)
    Supports Windows OS

## Scenarios

## When would you use the script?

If VM in Azure does not boot. Typically in this scenario VM screenshot from [boot diagnostics](https://azure.microsoft.com/en-us/blog/boot-diagnostics-for-virtual-machines-v2/) does not show login screen but a boot issue.

## Execution guidance
### CloudShell - PowerShell
- Start Azure Cloudshell for more info https://docs.microsoft.com/en-us/azure/cloud-shell/overview
- From the cloudshell prompt ==> Type c:
- Download the files run ==>  git clone https://github.com/azure-support-scripts.git c:\azure-support-scripts
- cd c:\azure-support-scripts\RecoverVM\ResourceManager
- Run .\New-AzureRMRescueVM.ps1 -ResourceGroup <ResourceGroup> -VmName <vmName> -SubID <subscriptionId>
- When it completes, it will return the command to use later to restore the problem VM.
- Connect to the rescue VM and resolve the issue with the OS disk of the problem VM.
- Run Restore-AzureRMOriginalVM.ps1 with the syntax shown in the output from New-AzureRMRescueVM.ps1

### Powershell
- The script must be executed in two phases
- Phase 1  From Powershell Execute => Get-Help New-AzureRMRescueVM #For details
            New-AzureRMRescueVM -ResourceGroup <ResourceGroup> -VmName <-VmName> -SubID <SUBID>
- Fix OS Disk issue            
            in addition to any other additional manual steps (To be provided by support)
- Phase 2 - From Powershell Execute =>  Get-Help Restore-AzureRMOriginalVM.PS1 #For details
            Restore-AzureRMOriginalVM.PS1  -ResourceGroup <ResourceGroup> -VmName <-VmName> -SubID <SUBID> -FixedOsDiskUri <FixedOsDiskUri-This will be provided in the console output plus Log after executing first step>
            After the OS Disk has been recovered, execute the Restore-AzureRMOriginalVM.PS1
## Version of Rescue VM
- For Windows Rescue VM is created with the latest version of 2016 image(GUI)
- For Linux   Rescue VM is created with the latest version of Canonical.UbuntuServer.16.04-LTS.latest

Follow the instructions and be patient (it may take between 15mins to an hour)

## Parameters or input
- ResourceGroup Name of the Problem VM
- VM name of the problem VM
- Subscription ID

## To get help on the scripts and its parameters run the following
- get-help .\New-AzureRMRescueVM.ps1
- get-help .\Restore-AzureRMOriginalVM.ps1

