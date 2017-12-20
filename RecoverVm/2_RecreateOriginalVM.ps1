#.\RecoverVM.ps1 -ServiceName testvip-d7zzhcnb -VMName testvip
#cd E:\git\github\RecoverVm
Param(
    [Parameter(Mandatory=$true)][string]$ServiceName ,
    [Parameter(Mandatory=$true)][string]$RecoVMName 
)

$Sub = Get-AzureSubscription -Current
if ( ! $Sub ) 
{
    Write-Output "no current subscription set - please run add-azureaccount + select-azuresubscription -current first for the subscription containing your target vm!"
    return
}

#. $PSScriptRoot\AttachOsDiskAsDataDiskToRecoveryVm.ps1 
. $PSScriptRoot\RecreateVmFromVhd.ps1 
#. $PSScriptRoot\RunRepairDataDiskFromRecoveryVm.ps1 


#$results = AttachOsDiskAsDataDiskToRecoveryVm $ServiceName $VMName
#$recoVM = $results[$results.count -1]



#As per discussion with Ram, this step will be manually run
#RunRepairDataDiskFromRecoveryVm $ServiceName ($recoVM.RoleName)


RecreateVmFromVhd $ServiceName $RecoVMName $true
