#Overview
Occasionally Azure IaaS VMs (Microsoft.Compute/virtualMachines) may not start because there is something wrong with the operating system (OS) disk preventing it from booting up correctly.
In such cases it is a common practice to recover the problem VM by performing the following steps:
	-Stop VM
	-Take a snapshot of the OS Disk
	-Create a Temporary Rescue VM
	-Attach the OS Disk to the Rescue VM
	-RDP to RescueVM
	-Run the script https://github.com/sebdau/azpstools/blob/master/FixDisk/TS_RecoveryWorker2.ps1 as an elevated administrator from the recovery VM and perform other manual steps
	-Detach the Data disk from Rescue VM
	-Perform Disk Swap to point the OsDisk.Vhd.Uri to the recovered OS Disk Uri
        -Finally Remove all the resources that were created for the Rescue VM

#Current version supports 
    Microsoft.Compute/virtualMachines (Non-Managed VM's)
    Supports Windows OS

# Scenarios

##  When would you use the script?
If a Windows VM in Azure does not boot. Typically in this scenario VM screenshot from [boot diagnostics] (https://azure.microsoft.com/en-us/blog/boot-diagnostics-for-virtual-machines-v2/) 
does not show login screen but a boot issue.

# Execution guidance
The script must be executed in two phases
  Phase 1 - From Powershell Execute => Get-Help CreateCRPRescueVM.ps1 #For details
            CreateCRPRescueVM   - CreateCRPRescueVM  -ResourceGroup <ResourceGroup> -VmName <-VmName> -SubID <SUBID>
            Creates the Rescue VM, with the OS Disk Attached as a data disk to the Rescue VM
            After the OS Disk has been fixed by running  the script https://github.com/sebdau/azpstools/blob/master/FixDisk/TS_RecoveryWorker2.ps1 as an elevated administrator from the recovery VM 
            in addition to any other additional manual steps (To be provided by support)
  Phase 2 - From Powershell Execute =>  Get-Help RecoverCRPVM.PS1 #For details
            RecoverCRPVM.PS1 - CreateCRPRescueVM  -ResourceGroup <ResourceGroup> -VmName <-VmName> -SubID <SUBID> -FixedOsDiskUri <FixedOsDiskUri-This will be provided in the console output plus Log after executing first step>
            After the OS Disk has been recoveerd, execute the RecoverCRPVM.PS1

#For Windows Rescue VM is created with the latest version of 2016 image(GUI)
#For Linux   Rescue VM is created with the latest version of Canonical.UbuntuServer.16.04-LTS.latest

- follow the instructions and be patient (it may take between 15mins to an hour)

## Parameters or input
- ResourceGroup Name
- VM name
-Subscription ID

#To get help on the scripts and its parameters run the following
-get-help .\CreateCRPRescueVM.ps1
-get-help .\RecoverCRPVM.ps1

