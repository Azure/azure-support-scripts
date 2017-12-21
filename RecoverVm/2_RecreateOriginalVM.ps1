#.\RecoverVM.ps1 -ServiceName testvip-d7zzhcnb -VMName testvip
#cd E:\git\github\RecoverVm
Param(
    [Parameter(Mandatory=$true)][string]$ServiceName ,
    [Parameter(Mandatory=$true)][string]$RecoVMName,
    [Parameter(Mandatory=$false)][string]$storageAccountName,
    [Parameter(Mandatory=$false)][string]$osDiskvhd,
    [Parameter(Mandatory=$false)][string] $ContainerName
)

$Sub = Get-AzureSubscription -Current
if ( ! $Sub ) 
{
    Write-Output "no current subscription set - please run add-azureaccount + select-azuresubscription -current first for the subscription containing your target vm!"
    return
}

#. $PSScriptRoot\AttachOsDiskAsDataDiskToRecoveryVm.ps1 
. $PSScriptRoot\RecreateVmFromVhd.ps1 
. $PSScriptRoot\SnapShotFunctions.ps1 


RecreateVmFromVhd $ServiceName $RecoVMName $true 

if ($storageAccountName -and $osDiskvhd -and$ContainerName)
{
    DeleteSnapShotAndVhd -storageAccountName $storageAccountName -osDiskvhd $osDiskvhd -ContainerName $ContainerName
}
