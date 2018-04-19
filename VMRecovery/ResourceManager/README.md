# WARNING: This preliminary release of the VM recovery scripts should only be used with the assistance of a Microsoft support engineer when working on a support incident.

# Overview
If an Azure VM is inaccessible it may be necessary to attach the OS disk to another Azure VM in order to perform recovery steps. The VM recovery scripts automate the recovery steps below.

1. Stops the problem VM
2. Takes a snapshot of the problem VM's OS disk
3. Creates a new temporary VM ("rescue VM")
4. Attaches the problem VM's OS disk as a data disk on the rescue VM
5. You can then connect to the rescue VM to investigate and mitigates issues with the problem VM's OS disk
6. Detaches the data disk from rescue VM
7. Performs a disk swap to swap the problem VM's OS disk from the rescue VM back to the problem VM
8. Removes the resources that were created for the rescue VM

# Supported VM Types

This version of the VM recovery script is for use with Azure VMs created using the Resource Manager deployment model. It supports both Linx and Windows VMs. It supports both managed and unmanaged disk VMs. For VMs created using the Classic deployment model, use the version located under \Classic instead of \ResourceManager.

## When would you use the script?

If VM in Azure does not boot. Typically in this scenario VM screenshot from [boot diagnostics](https://azure.microsoft.com/en-us/blog/boot-diagnostics-for-virtual-machines-v2/) does not show login screen but a boot issue.

## Usage
### PowerShell - Cloud Shell
1. Launch PowerShell in Azure Cloud Shell 

   <a href="https://shell.azure.com/powershell" target="_blank"><img border="0" alt="Launch Cloud Shell" src="https://shell.azure.com/images/launchcloudshell@2x.png"></a>

2. If it is your first time connecting to Azure Cloud Shell, select **`PowerShell (Windows)`** when you see **`Welcome to Azure Cloud Shell`**. 

3. If you then see **`You have no storage mounted`**, select the subscription where the VM you are troubleshooting resides, then select **`Create storage`**.

4. From the **`PS Azure:\>`** prompt type **`cd C:\`** then **`<ENTER>`**.

5. Run the following command to download the scripts. Git is preinstalled in Cloud Shell. You do not need to install it separately.
```PowerShell
git clone https://github.com/Azure/azure-support-scripts c:\azure-support-scripts
```
6. Switch into the folder by running:
```PowerShell
cd C:\azure-support-scripts\VMRecovery\ResourceManager
```
7. Run the following command to attach the OS disk of the problem VM to a rescue VM:
```PowerShell
.\New-AzureRMRescueVM.ps1 -ResourceGroup <ResourceGroup> -VmName <vmName> -SubID <subscriptionId>
```
To double-check the resource group name and VM name, you can run **`Get-AzureRmVM`**. To double-check the subscription ID you can run **`Get-AzureRmSubscription`**.

8. When it completes, it will return the command to use later to restore the problem VM.

9. Connect to the rescue VM and resolve the issue with the OS disk of the problem VM.

10. Run Restore-AzureRMOriginalVM.ps1 with the syntax shown in the output from New-AzureRMRescueVM.ps1

### PowerShell - Local
- The script must be executed in two phases
- Phase 1  From Powershell Execute => Get-Help New-AzureRMRescueVM #For details
            **`.\New-AzureRMRescueVM -ResourceGroup <ResourceGroup> -VmName <-VmName> -SubID <subscriptionId>`**
- Fix OS Disk issue
           in addition to any other additional manual steps (To be provided by support)
- Phase 2 - From Powershell Execute =>  Get-Help Restore-AzureRMOriginalVM.PS1 #For details
            `.\Restore-AzureRMOriginalVM.PS1  -ResourceGroup <ResourceGroup> -VmName <-VmName> -SubID <SUBID> -FixedOsDiskUri <FixedOsDiskUri>` This will be provided in the console output plus Log after executing first step>
            After the OS Disk has been recovered, execute the Restore-AzureRMOriginalVM.PS1
## Version of Rescue VM
- For Windows, the rescue VM is created from the Windows Server 2016 version 1607 build 14393 marketplace image that includes the Desktop Experience.
- For Linux, the rescue VM is created from the Canonical Ubuntu Server 16.04 LTS marketplace image.

## To get help on the scripts and its parameters run the following

**`get-help .\New-AzureRMRescueVM.ps1`**
**`get-help .\Restore-AzureRMOriginalVM.ps1`**

