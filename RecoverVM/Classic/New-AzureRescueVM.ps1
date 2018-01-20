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

.PARAMETER NoSnapshot
    This is an optional Parameter, by specifying NoSnapshot the script does not take a snapshot of the OS Disk

.EXAMPLE
    .\New-AzureRescueVM.ps1 -VMName hackathonvm -ServiceName hackathonvm6614
    .\New-AzureRescueVM.ps1 -VMName hackathonvm -ServiceName hackathonvm6614 -NoSnapShot
    .\New-AzureRescueVM.ps1 -ServiceName testredhat1 -VMName classiclinuxvm

.NOTES
    Name: New-AzureRescueVM.ps1

    Author: Sujasd
#>
Param(
    [Parameter(Mandatory=$true)][string]$ServiceName ,
    [Parameter(Mandatory=$true)][string]$VMName,
    [switch] $NoSnapshot  
)

$Sub = Get-AzureSubscription -Current
if ( ! $Sub ) 
{
    Write-Output "no current subscription set - please run add-azureaccount + select-azuresubscription -current first for the subscription containing your target vm!"
    return
}

. $PSScriptRoot\AttachOsDiskAsDataDiskToRecoveryVm.ps1 
. $PSScriptRoot\RecreateVmFromVhd.ps1 
. $PSScriptRoot\SnapShotFunctions.ps1 


try
{
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName -ErrorAction Stop
}
catch
{
    write-host "Specified VM ==> $vm was not found in the cloud service ==> $ServiceName, please make sure you are providing the correct Service/vm Name of the problem VM" -ForegroundColor Red
    write-host  "Exception Message: $($_.Exception.Message)"
    return
}
if (-not $vm)
{
    write-host "Specified VM ==> $vm was not found in the cloud service ==> $ServiceName, please make sure you are providing the correct Service/vm Name of the problem VM" -ForegroundColor Red
    return
}


if (-not $NoSnapshot)
{
    try
    {
        Write-host "Looks like -NoSnapshot was not specifed so will proceed to take a snapshot of the OS Disk" 
        Write-host "Stopping the VM first"
        Stop-AzureVM -ServiceName $ServiceName -VM $vm -StayProvisioned -ErrorAction stop
        if (-not $vm.VM.OSVirtualHardDisk.MediaLink.Authority) 
        {
            write-host "Unable to determine the Medialink of the $vm" -ForegroundColor red 
        }
        else
        {    
            $storageAccountName = $vm.VM.OSVirtualHardDisk.MediaLink.Authority.Split(".")[0]
            $StorageAccountKey = (Get-AzureStorageKey -StorageAccountName $storageAccountName).Secondary
            $ContainerName = $vm.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri.Split('/')[3]
            $osDiskvhd = $vm.VM.OSVirtualHardDisk.MediaLink.AbsolutePath.split('/')[-1]
            $Copiedvhduri = TakeSnapshotofOSDisk $storageAccountName $StorageAccountKey $ContainerName $osDiskvhd
        }
    }
    catch
    {
        Write-Host "Unable to take snapshot, plese see the error below" -ForegroundColor Red
        write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
        Write-host "Error in Line# : $($_.Exception.Line) =>  $($MyInvocation.MyCommand.Name)" -ForegroundColor Red
        return $null
    }
}



$results = AttachOsDiskAsDataDiskToRecoveryVm $ServiceName $VMName
if (-not $results)
{
    write-host "Unable to proceed further" -ForegroundColor Red
    return
}
$recoVM = $results[$results.count -1]
if (-not $recoVM)
{
    write-host "Unable to proceed further" -ForegroundColor Red
    return
}


write-host ('='*47)
write-host "Next Steps"
write-host ('='*47)
write-host "RDP into the $($recoVM.RoleName) and take all the necessary steps to fix the OS Disk that is attached as the datadisk"
Write-Host "After the OS Disk has been fixed run the following script to Recreate the VM with the fixed OS Disk"
if ($NoSnapshot)
{
    write-host ".\Restore-AzureOriginalVM.ps1 -ServiceName $ServiceName -RecoVMName $($recoVM.RoleName)"    
}
else
{
    write-host ".\Restore-AzureOriginalVM.ps1 -ServiceName $ServiceName -RecoVMName $($recoVM.RoleName) -storageAccountName $storageAccountName -osDiskvhd $osDiskvhd -ContainerName $ContainerName"
}













