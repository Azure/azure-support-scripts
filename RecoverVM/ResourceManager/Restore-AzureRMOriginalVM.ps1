<#
.SYNOPSIS
    This Script is executed after the OS Disk is fixed in the rescue VM, this script recovers the VM by performing an OS disk swap.

.DESCRIPTION
    This script automates the recovery process after the OS Disk Issue has been fixed.
    This script automates the following steps 
	-Detach the OS disk that was attached as a data disk to the rescue VM
	-Disk Swap  OS Disk of the Problem VM with the fixed OS Disk Uri
    -Start the VM
    -Delete all the resources that were created for the rescue VM

.PARAMETER VmName
    This is a mandatory Parameter, Name of the VM that needs to be recovered.

.PARAMETER ResourceGroup
    This is a mandatory Parameter, Name of the ResourceGroup the VM belongs to.

.PARAMETER SubID
    This is a mandatory Parameter, SubscriptionID - the VM belongs to.

.PARAMETER FixedOsDiskUri
    This is a mandatory Parameter, This would be the uri of the fixedOSDisk, this information will be provided after the successful execution of CreateARMRescueVM.

.PARAMETER prefix
    Optional Parameter. By default the new Rescue VM and its resources are all created under a ResourceGroup named same as the orginal resourceGroup name with a prefix of 'rescue', however the prefix can be changed to a different value to overide the default 'rescue'

.PARAMETER diskName
    Optional Parameter. This is always passed for a Managed VM, diskname of the attached data disk so that it can be removed from RescueVM

.PARAMETER snapshotName
    Optional Parameter. This is always passed for a Managed VM, passes the Snapshotname so that the scripty can allow it to delete it.

.PARAMETER OriginalosDiskVhdUri
    Optional Parameter. This is always passed for a non Managed VM, this is so that scripty can allow to delete the snapshot

.PARAMETER managedVM
    This is a mandatory Parameter, this indicates if the VM is a Managed or a non-ManagedVM



.EXAMPLE
    .\Restore-AzureRMOriginalVM.ps1 -ResourceGroup "testsujmg" -VmName "sujmanagedvm" -SubID "d7eaa135-abdf-4aaf-8868-2002dfeea60c" -diskName "rescuexm001fixedosrescuex001fixedossujmanagedvm_OsDisk_1_6bee8dc1d09d42f9b6d7954" -snapshotName "rescuexm001fixedosSnaprescuex001fixedossujmanagedvm_OsDisk_1_6bee8dc1d09d42f9b6d" -prefix "rescuexm001" -managedVM $True

.EXAMPLE 
    .\Restore-AzureRMOriginalVM.ps1 -ResourceGroup "sujtemp" -VmName "sujnortheurope" -SubID "d7eaa135-abdf-4aaf-8868-2002dfeea60c" -FixedOsDiskUri "https://sujtemp6422.blob.core.windows.net/vhds/rescuexU001fixedosrescuexUnARMfixedosrescuex51fixedosrescuex48fixedosrescuex47fixedosrescuex2fixedosrescuefixedosrescue02fixedossujnortheurope.vhd" -OriginalosDiskVhdUri "https://sujtemp6422.blob.core.windows.net/vhds/rescuexUnARMfixedosrescuex51fixedosrescuex48fixedosrescuex47fixedosrescuex2fixedosrescuefixedosrescue02fixedossujnortheurope.vhd"  -prefix "rescuexU001" -managedVM $False

.NOTES
    Name: Restore-AzureRMOriginalVM.ps1

    Author: Sujasd
#>

Param(
        [Parameter(mandatory=$true)]
        [String]$VmName,

        [Parameter(mandatory=$true)]
        [String]$ResourceGroup,

        [Parameter(mandatory=$true)]
        [String]$SubID,

        [Parameter(mandatory=$false)]
        [String]$FixedOsDiskUri,

        [Parameter(mandatory=$false)]
        [String]$diskName,

        [Parameter(mandatory=$false)]
        [String]$prefix = "rescue",

        [Parameter(mandatory=$true)]
        [bool]$managedVM,

        [Parameter(mandatory=$false)]
        [String]$snapshotName,

        [Parameter(mandatory=$false)]
        [String] $OriginalosDiskVhdUri
     )


$Error.Clear()

if (-not $showErrors) {
    $ErrorActionPreference = 'SilentlyContinue'
}

$script:scriptStartTime = (Get-Date).ToUniversalTime()
$LogFile = $env:TEMP + "\DiskSwap" + $VmName + "_" + ( Get-Date $script:scriptStartTime -f yyyyMMddHHmmss ) + ".log"  
# Get running path
$RunPath = split-path -parent $MyInvocation.MyCommand.Source
cd $RunPath
$CommonFunctions = $runPath+"\Common-Functions.psm1"

$CommonFunctions = $runPath+"\Common-Functions.psm1"

if (Get-Module Common-Functions) {remove-module -name Common-Functions}   
Import-Module -Name $CommonFunctions  -ArgumentList $LogFile -ErrorAction Stop 


if (-not (Get-AzureRmContext).Account)
{
    Login-AzureRmAccount
}
write-log "Info: Log is being written to ==> $LogFile" 
Write-Log  $MyInvocation.Line -logOnly
#Set the context to the correct subid
Write-Log "Setting the context to SubID $SubID" 
$subContext= Set-AzureRmContext -Subscription $SubID
if ($subContext -eq $null) 
{
    Write-Log "Unable to set the Context for the given subId ==> $SubID, Please make sure you first  run the command ==> Login-AzureRMAccount" -Color Red
    return
}

#Step 1 Get the VM Object
Write-Log "Running Get-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -Name `"$VmName`"" 
$vm = Get-AzureRmVM -ResourceGroupName $ResourceGroup -Name $VmName 
if (-not $vm)
{
    Write-Log "Unable to find the VM `"$VmName`",  cannot proceed, please verify the VM name and the resource group name." -Color Red
    return
}
Write-Log "Successfully got the VM Object info for ==> $($vm.Name)" -Color Green

if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") {$windowsVM= $true} else {$windowsVM= $false}

$rescueVMNname = "$prefix$Vmname"
$RescueResourceGroup = "$prefix$ResourceGroup"

#Step 2 Get the Rescue VM Object
Write-Log "Running Get-AzureRmVM -ResourceGroupName `"$RescueResourceGroup `" -Name `"$rescueVMNname`"" 
$rescuevm = Get-AzureRmVM -ResourceGroupName $RescueResourceGroup -Name $rescueVMNname
if (-not $rescuevm)
{
    Write-Log "Unable to find the VM `"$rescueVMNname`",  cannot proceed, please verify the VM name and the resource group name." -Color Red
    return
}
Write-Log "Successfully got the VM Object info for the Rescue VM ==>  $rescueVMNname" -Color Green

#Step 3 -Removing the DataDisk from Rescue VM
$FixedOsDiskUri  = $FixedOsDiskUri.Replace("`r`n","")
if (-not $managedVM)
{
    $diskname = ($FixedOsDiskUri.Split('/')[-1]).split('.')[0]
}
$diskname=$diskname.Replace("`r`n","")
#$diskName = ($FixedOsDiskUri.Split('/')[-1]).split('.')[0]
write-log "Disk Name ==> $($diskName)" -logonly
if ($rescuevm.StorageProfile.DataDisks.Count -gt 0 )
{
  if ($managedVM) 
  {
    $problemvmOsDiskManagedDiskID = $rescuevm.StorageProfile.DataDisks[0].ManagedDisk.id
  }
}
else
{
    write-log "Unable to find the data disk in the Rescue VM ==> $rescueVMNname, cannot proceed with the restore process." -color red
    return
}
Write-Log "Removing the Data disk from the Rescue VM ==>  $rescueVMNname" 
try
{
    Remove-AzureRmVMDataDisk -VM $rescuevm -Name $diskName -ErrorAction Stop
    Update-AzureRmVM -ResourceGroupName $RescueResourceGroup -VM $rescuevm -ErrorAction stop
    Write-Log "Successfully removed the Data disk from the Rescue VM ==>  $rescueVMNname" -Color Green
}
Catch
{
    Write-Log "The operation to remove the data disk from rescue VM failed." -Color Red
    Write-Log "The operation to remove the data disk from rescue VM failed.: $($_.Exception.GetType().FullName)" -logOnly
    Write-Log "Exception Message: $($_.Exception.Message)" -logOnly
    WriteRestoreCommands -ResourceGroup $ResourceGroup -VmName $VmName -problemvmOsDiskUri $vm.StorageProfile.OsDisk.Vhd.Uri  -problemvmOsDiskManagedDiskID $rescuevm.StorageProfile.DataDisks[0].ManagedDisk.id -managedVM $managedVM
    return $null
}

#Stop the VM before performing the disk swap.
Write-Log "Stopping the VM ==> $VmName"  

$stopped = StopTargetVM -ResourceGroup $ResourceGroup -VmName $VmName
write-log "`"$stopped`" ==> $($stopped)" -logOnly
if (-not $stopped) 
{
   write-log   "$($Stopped)" -logonly
   Write-Log "Unable to stop the  VM ==> $VmName successfully, try manully stopping the VM from portal" -Color Red
   Return
}


#Step 4 -Disk Swapping the OS Disk to point to the fixed OSDisk Uri/updating ManagedDiskID
Write-Log "Performing the disk swap, swapping the OS disk with the fixed Data disk from the Rescue VM ==>  $rescueVMNname" 
if (-not $managedVM)
{
    $problemvmOsDiskUri=$vm.StorageProfile.OsDisk.Vhd.Uri 
    WriteRestoreCommands -ResourceGroup $ResourceGroup -VmName $VmName -problemvmOsDiskUri $problemvmOsDiskUri  -problemvmOsDiskManagedDiskID $null -managedVM $managedVM
    $vm.StorageProfile.OsDisk.Vhd.Uri = $FixedOsDiskUri 
    Update-AzureRmVM -ResourceGroupName $ResourceGroup -VM $vm 
    Write-Log "Successfully Disk Swapped the OS Disk,  for VM ==>  $VmName" 

}
else
{
    WriteRestoreCommands -ResourceGroup $ResourceGroup -VmName $VmName -problemvmOsDiskUri $null  -problemvmOsDiskManagedDiskID $problemvmOsDiskManagedDiskID -managedVM $managedVM
    set-AzureRmVMOSDisk -vm $vm -ManagedDiskId $problemvmOsDiskManagedDiskID -CreateOption FromImage
    Update-AzureRmVM -ResourceGroupName $ResourceGroup -VM $vm 
    Write-Log "Successfully Disk Swapped the OS Disk,  for VM ==>  $VmName" 
}


#Step 5 -Start the VM
Write-Log "Starting the VM ==> $VmName"  
$started= Start-AzureRmVM -ResourceGroupName $ResourceGroup -Name $VmName
if ($Started)
{
   Write-Log "Successfully started the  VM ==> $VmName" -Color Green
}
else
{
   Write-Log "Unable to  start the  VM ==> $VmName, Please try it manually and RDP into it" -Color red
   return
}

#Step 5 Open a RDP Connection to the VM
if ($windowsVM)
{
    Write-log "Opening the RDP file to connect to the  VM ==> $VmName" 
    Get-AzureRmRemoteDesktopFile -ResourceGroupName $ResourceGroup -Name $VmName -Launch
}

#Step 6 Clean up
Write-Host "`nWere you able to successfully recover the VM ==> $VmName and are you ready to delete all the rescue reources that were created under the Resource Group $RescueResourceGroup (Y/N)?" -ForegroundColor Yellow
if ((read-host) -eq 'Y' )
{
    Write-Log "Acknowledged deleting the rescource group ==> $RescueResourceGroup" -color Cyan
    Remove-AzureRmResourceGroup -Name $RescueResourceGroup -Force
}
else
{
    Write-Log "Did not acknowledge deleting the rescource group ==> $RescueResourceGroup" -color Cyan
}

if ($managedVM)
{
    Write-log "`nWould you like to delete the snapshot ==> $Snapshotname that was taken (Y/N)?"
    if ((read-host) -eq 'Y' )
    {
        write-log "Acknowledged deleting the snapshot ==> $Snapshotname" -color Cyan
        Remove-AzureRmSnapshot -SnapshotName $snapshotName -ResourceGroupName $ResourceGroup -Force 
    }
}
else
{
    DeleteSnapShotAndVhd -osDiskVhdUri $OriginalosDiskVhdUri -ResourceGroup $ResourceGroup
}


Invoke-Item $LogFile







