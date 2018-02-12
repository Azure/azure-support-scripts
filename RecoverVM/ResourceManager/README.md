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

# Supported VM Types

The VM recovery scripts are supported for use with Azure VMs created using the Resource Manager deployment model. Both Linux and Windows guests are supported. Only unmanaged disk VMs are supported. Support for managed disk VMs is planned but not currently implemented.

## When would you use the script?

If VM in Azure does not boot. Typically in this scenario VM screenshot from [boot diagnostics](https://azure.microsoft.com/en-us/blog/boot-diagnostics-for-virtual-machines-v2/) does not show login screen but a boot issue.

## Execution guidance
### PowerShell - Cloud Shell
1. Open [Azure Cloud Shell](https://docs.microsoft.com/en-us/azure/cloud-shell/overview) and switch from **Bash** to **PowerShell**. 

2. From the **`PS Azure:\>`** prompt type **`c:`** then **`<ENTER>`**.

3. Download the files into your cloud shell storage by running:

**`git clone https://github.com/azure/azure-support-scripts.git c:\azure-support-scripts`**

4. Switch into the the folder by running:

**`cd c:\azure-support-scripts\RecoverVM\ResourceManager`**

5. Run the following command to attach the OS disk of the problem VM to a rescue VM:

**`.\New-AzureRMRescueVM.ps1 -ResourceGroup <ResourceGroup> -VmName <vmName> -SubID <subscriptionId>`**

To double-check the resource group name and VM name, you can run **`Get-AzureRmVM`**. To double-check the subscription ID you can run **`Get-AzureRmSubscription`**.

6. When it completes, it will return the command to use later to restore the problem VM.

7. Connect to the rescue VM and resolve the issue with the OS disk of the problem VM.

8. Run Restore-AzureRMOriginalVM.ps1 with the syntax shown in the output from New-AzureRMRescueVM.ps1

### Powershell - Local
- The script must be executed in two phases
- Phase 1  From Powershell Execute => Get-Help New-AzureRMRescueVM #For details
            **`.\New-AzureRMRescueVM -ResourceGroup <ResourceGroup> -VmName <-VmName> -SubID <subscriptionId>`**
- Fix OS Disk issue
           in addition to any other additional manual steps (To be provided by support)
- Phase 2 - From Powershell Execute =>  Get-Help Restore-AzureRMOriginalVM.PS1 #For details
            `.\Restore-AzureRMOriginalVM.PS1  -ResourceGroup <ResourceGroup> -VmName <-VmName> -SubID <SUBID> -FixedOsDiskUri <FixedOsDiskUri>` This will be provided in the console output plus Log after executing first step>
            After the OS Disk has been recovered, execute the Restore-AzureRMOriginalVM.PS1
## Version of Rescue VM
- For Windows Rescue VM is created with the latest version of 2016 image(GUI)
- For Linux   Rescue VM is created with the latest version of Canonical.UbuntuServer.16.04-LTS.latest

## To get help on the scripts and its parameters run the following

**`get-help .\New-AzureRMRescueVM.ps1`**
**`get-help .\Restore-AzureRMOriginalVM.ps1`**

