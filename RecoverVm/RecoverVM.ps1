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

$TakeSnapshot=read-host
#if ((read-host) -eq 'Y')
if ($TakeSnapshot -eq 'Y')
{
    Write-host "Acknowledging request for taking a snapshot" -ForegroundColor yellow
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName
    $storageAccountName = $vm.VM.OSVirtualHardDisk.MediaLink.Authority.Split(".")[0]
    $StorageAccountKey = (Get-AzureStorageKey -StorageAccountName $storageAccountName).Secondary
    $ContainerName = $vm.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri.Split('/')[3]
    $osDiskvhd = $vm.VM.OSVirtualHardDisk.MediaLink.AbsolutePath.split('/')[-1]
    $Copiedvhduri = TakeSnapshotofOSDisk $storageAccountName $StorageAccountKey $ContainerName $osDiskvhd
}

$results = AttachOsDiskAsDataDiskToRecoveryVm $ServiceName $VMName
$recoVM = $results[$results.count -1]

RunRepairDataDiskFromRecoveryVm $ServiceName ($recoVM.RoleName)
RecreateVmFromVhd $ServiceName $recoVM.RoleName $true 
if ($TakeSnapshot -eq 'Y')
{
    DeleteSnapShotAndVhd -storageAccountName $storageAccountName -osDiskvhd $osDiskvhd -ContainerName $ContainerName
}












