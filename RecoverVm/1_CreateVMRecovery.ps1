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


$results = AttachOsDiskAsDataDiskToRecoveryVm $ServiceName $VMName
$recoVM = $results[$results.count -1]

write-host ('='*47)
write-host "Next Steps"
write-host ('='*47)
write-host "RDP into the $($recoVM.RoleName) and take all the necessary steps to fix the OS Disk that is attached as the datadisk"
Write-Host "After the OS Disk has been fixed run the following script to Recreate the VM with the fixed OS Disk"
write-host ".\2_RecreateOriginalVM.ps1 -ServiceName $ServiceName -RecoVMName $($recoVM.RoleName)"


#As per discussion with Ram, this step will be manually run
#RunRepairDataDiskFromRecoveryVm $ServiceName ($recoVM.RoleName)











