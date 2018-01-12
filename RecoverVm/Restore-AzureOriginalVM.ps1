<#
.SYNOPSIS
    This script is recreateds the original VM with the Fixed OS Dishk VHD

.DESCRIPTION
    This script automates the creation of the orinal VM, by recreating it using the fixed OS Disk VHD.
	-Detaches the disk from the rescue VM
	-Creates the Original VM using the fixed OS Disk
    -Parameter list for this is provided after the successfull completion of .\CreateClassicRescueVM.ps1

.PARAMETER ServiceName
    This is a mandatory Parameter, Name of the cloud service of the problem  VM belong

.PARAMETER VMName
    This is a mandatory Parameter, Name of the problem VM

.EXAMPLE
    .\Restore-AzureOriginalVM.ps1 -ServiceName hackathonvm6614 -RecoVMName RC1801110602 -storageAccountName sujnoavsetwe4433 -osDiskvhd hackathonvm-os-5685.vhd -ContainerName vhds

.NOTES
    Name: Restore-AzureOriginalVM.ps1

    Author: Sujasd
#>

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
