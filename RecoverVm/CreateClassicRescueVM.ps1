<#
.SYNOPSIS
    Creates a Rescue VM and attaches the OS Disk of the problem VM to this intermediate rescue VM.

.DESCRIPTION
    This script automates the creation of Rescue VM to enable fixing of OS disk issues related to a problem VM.
    In such cases it is a common practice to recover the problem VM by performing the following steps. These are the steps that are performed by the script.
	-Stops the problem VM
	-Take a snapshot of the OS Disk
	-Create a Temporary Rescue VM
	-Attach the OS Disk to the Rescue VM
    -Starts the Rescue VM
	-RDPs to RescueVM (For Windows)

.PARAMETER ServiceName
    This is a mandatory Parameter, Name of the cloud service of the problem  VM belong

.PARAMETER VMName
    This is a mandatory Parameter, Name of the problem VM

.EXAMPLE
    .\CreateClassicRescueVM.ps1 -VMName hackathonvm -ServiceName hackathonvm6614

.NOTES
    Name: CreateClassicRescueVM.ps1

    Author: Sujasd
#>
Param(
    [Parameter(Mandatory=$true)][string]$ServiceName ,
    [Parameter(Mandatory=$true)][string]$VMName 
)

$Sub = Get-AzureSubscription -Current
if ( ! $Sub ) 
{
    Write-Output "no current subscription set - please run add-azureaccount + select-azuresubscription -current first for the subscription containing your target vm!"
    return
}

. $PSScriptRoot\AttachOsDiskAsDataDiskToRecoveryVm.ps1 
. $PSScriptRoot\RecreateVmFromVhd.ps1 
. $PSScriptRoot\RunRepairDataDiskFromRecoveryVm.ps1 
. $PSScriptRoot\SnapShotFunctions.ps1 

Write-Host "`nWould you like to take a snapshot of the OSDisk first?" 
$TakeSnapshot=read-host
#if ((read-host) -eq 'Y')
if ($TakeSnapshot -eq 'Y')
{
    Write-host "Acknowledging request for taking a snapshot" 
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName
    $storageAccountName = $vm.VM.OSVirtualHardDisk.MediaLink.Authority.Split(".")[0]
    $StorageAccountKey = (Get-AzureStorageKey -StorageAccountName $storageAccountName).Secondary
    $ContainerName = $vm.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri.Split('/')[3]
    $osDiskvhd = $vm.VM.OSVirtualHardDisk.MediaLink.AbsolutePath.split('/')[-1]
    $Copiedvhduri = TakeSnapshotofOSDisk $storageAccountName $StorageAccountKey $ContainerName $osDiskvhd
}



$results = AttachOsDiskAsDataDiskToRecoveryVm $ServiceName $VMName
$recoVM = $results[$results.count -1]

write-host ('='*47)
write-host "Next Steps"
write-host ('='*47)
write-host "RDP into the $($recoVM.RoleName) and take all the necessary steps to fix the OS Disk that is attached as the datadisk"
Write-Host "After the OS Disk has been fixed run the following script to Recreate the VM with the fixed OS Disk"
if ($TakeSnapshot -eq 'Y')
{
    write-host ".\RecoverClassicOriginalVM.ps1 -ServiceName $ServiceName -RecoVMName $($recoVM.RoleName) -storageAccountName $storageAccountName -osDiskvhd $osDiskvhd -ContainerName $ContainerName"
}
else
{
    write-host ".\RecoverClassicOriginalVM.ps1 -ServiceName $ServiceName -RecoVMName $($recoVM.RoleName)"
}













