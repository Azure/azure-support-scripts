<#
.SYNOPSIS
    This script is executed after the OS Disk is fixed in the rescue VM, this script recovers the VM by performing an OS disk swap.

.DESCRIPTION
    This script automates the recovery process after the OS Disk Issue has been fixed.
    This script automates the following steps 
	-Detach the OS disk that was attached as a data disk to the rescue VM
	-Disk Swap  OS Disk of the Problem VM with the fixed OS Disk Uri
    -Start the VM
    -Delete all the resources that were created for the rescue VM

.PARAMETER VmName
    This is a mandatory Parameter, Name of the VM that needs to be recovered.

.PARAMETER resourceGroupName
    This is a mandatory Parameter, Name of the resource group the VM belongs to.

.PARAMETER SubscriptionId
    This is a mandatory Parameter, SubscriptionID - the VM belongs to.

.PARAMETER FixedOsDiskUri
    This is a mandatory Parameter, This would be the uri of the fixedOSDisk, this information will be provided after the successful execution of CreateARMRescueVM.

.PARAMETER prefix
    Optional Parameter. By default the new Rescue VM and its resources are all created under a resource group named same as the original resource group name with a prefix of 'rescue', however the prefix can be changed to a different value to override the default 'rescue'

.PARAMETER diskName
    Optional Parameter. This is always passed for a Managed VM, diskname of the attached data disk so that it can be removed from RescueVM

.PARAMETER OriginalosDiskVhdUri
    Optional Parameter. This is always passed for a non Managed VM, this is so that scripty can allow to delete the snapshot

.PARAMETER OriginalProblemOSManagedDiskID
    Optional Parameter. This is always passed for a Managed VM, this is so that script has a refernce to the original Disk ID so if need be it has a way to swap back to its original oS Disk

.EXAMPLE
    .\Restore-AzureRMOriginalVM.ps1 -resourceGroupName "testsujmg" -VmName "sujmanagedvm" -subscriptionId "d7eaa135-abdf-4aaf-8868-2002dfeea60c" -diskName "rescuexm001fixedosrescuex001fixedossujmanagedvm_OsDisk_1_6bee8dc1d09d42f9b6d7954"  -prefix "rescuexm001" 

.EXAMPLE 
    .\Restore-AzureRMOriginalVM.ps1 -resourceGroupName "sujtemp" -VmName "sujnortheurope" -subscriptionId "d7eaa135-abdf-4aaf-8868-2002dfeea60c" -FixedOsDiskUri "https://sujtemp6422.blob.core.windows.net/vhds/rescuexU001fixedosrescuexUnARMfixedosrescuex51fixedosrescuex48fixedosrescuex47fixedosrescuex2fixedosrescuefixedosrescue02fixedossujnortheurope.vhd" -OriginalosDiskVhdUri "https://sujtemp6422.blob.core.windows.net/vhds/rescuexUnARMfixedosrescuex51fixedosrescuex48fixedosrescuex47fixedosrescuex2fixedosrescuefixedosrescue02fixedossujnortheurope.vhd"  -prefix "rescuexU001" 

.NOTES
    Name: Restore-AzureRMOriginalVM.ps1

    Author: Sujasd
#>

param(
    [Parameter(mandatory=$true)]
    [String]$VmName,

    [Parameter(mandatory=$true)]
    [String]$ResourceGroupName,

    [Parameter(mandatory=$true)]
    [String]$subscriptionId,

    [Parameter(mandatory=$false)]
    [String]$FixedOsDiskUri,

    [Parameter(mandatory=$false)]
    [String]$diskName,

    [Parameter(mandatory=$false)]
    [String]$prefix = 'rescue',

    [Parameter(mandatory=$false)]
    [String]$OriginalosDiskVhdUri,

    [Parameter(mandatory=$false)]
    [String]$OriginalProblemOSManagedDiskID
)

$Error.Clear()

if (-not $showErrors) {
    $ErrorActionPreference = 'SilentlyContinue'
}

$script:scriptStartTime = (get-date).ToUniversalTime()
$timestamp = get-date $script:scriptStartTime -f yyyyMMddHHmmss
$scriptPath = split-path -path $MyInvocation.MyCommand.Path -parent
$scriptName = (split-path -path $MyInvocation.MyCommand.Path -leaf).Split('.')[0]
$logFile = "$scriptPath\$($scriptName)_$($vmName)_$($timestamp).log"
$restoreOriginalStateFile = "Restore_" + $vmName + "_OriginalState.ps1"
set-location $scriptPath
$commonFunctionsModule = "$scriptPath\Common-Functions.psm1"

if (Get-Module Common-Functions)
{
    remove-module -name Common-Functions
}
import-module -Name $commonFunctionsModule -ArgumentList $logFile -ErrorAction Stop

if (-not (Get-AzureRmContext).Account)
{
    Login-AzureRmAccount
}
write-log "Log file: $logFile"
write-log $MyInvocation.Line -logOnly
#Set the context to the correct subscription ID
write-log "[Running] Setting authentication context to subscriptionId $subscriptionId"
$authContext = Set-AzureRmContext -Subscription $subscriptionId
if (-not $authContext.Subscription.Id)
{
    $message = "[Error] Unable to set context to subscriptionId $subscriptionId. Run Login-AzureRMAccount and then run the script again."
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}
else
{
    $subscriptionId = $authContext.Subscription.Id
    $subscriptionName = $authcontext.Subscription.Name
    $accountId = $authContext.Account.Id
    $accountType = $authContext.Account.Type
    $tenantId = $authContext.tenant.Id
    $environmentName = $authContext.Environment.Name
    write-log "[Success] Using subscriptionId: $subscriptionId, subscriptionName: $subscriptionName" -color green
    write-log "AccountId: $accountId" -logOnly
    write-log "AccountType: $accountType" -logOnly
    write-log "TenantId: $tenantId" -logOnly
    write-log "Environment: $environmentName" -logOnly
}

$rescueVMName = "$prefix$vmName"
$rescueResourceGroupName = "$prefix$resourceGroupName"

#Creates a script that allows to delete the rescue resource grop that was created as part of this operation.
$removeRescueRgScript = "Remove_Rescue_RG_" + $rescueResourceGroupName + ".ps1"
$removeRescueRgScriptPath = (get-childitem $removeRescueRgScript).FullName

CreateRemoveRescueRgScript -rescueResourceGroupName $rescueResourceGroupName -removeRescueRgScript $removeRescueRgScript -scriptonly -subscriptionId $subscriptionId


# Step 1 Get VM object
write-log "[Running] Get-AzureRmVM -resourceGroupName $resourceGroupName -Name $vmName"
$vm = Get-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName -WarningAction SilentlyContinue
if (-not $vm)
{
    $message = "[Error] Unable to find VM $vmName. Verify the vmName, resourceGroupName, and subscriptionId and run the script again."
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}
write-log "[Success] Found problem VM $($vm.Name)" -color green

if ($vm.StorageProfile.OsDisk.OsType -eq 'Windows')
{
    $windowsVM = $true
}
else
{
    $windowsVM = $false
}

$rescueVMName = "$prefix$vmName"
$rescueResourceGroupName = "$prefix$resourceGroupName"

#Step 2 Get rescue VM Object
write-log "[Running] Get-AzureRmVM -ResourceGroupName $rescueResourceGroupName -Name $rescueVMName"
$rescuevm = Get-AzureRmVM -ResourceGroupName $rescueResourceGroupName -Name $rescueVMName -WarningAction SilentlyContinue
if (-not $rescuevm)
{
    $message = "[Error] Rescue VM $rescueVMName not found. Verify the VM name and resource group name."
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}
write-log "[Success] Found rescue VM $rescueVMName" -color green

# Check if managed VM
if ($rescuevm.StorageProfile.DataDisks[0].ManagedDisk)
{
   $managedVM = $true
}
elseif ($rescuevm.StorageProfile.DataDisks[0].Vhd)
{
   $managedVM = $false
}

#Step 3 -Removing the DataDisk from Rescue VM
$FixedOsDiskUri  = $FixedOsDiskUri.Replace("`r`n","")
if (-not $managedVM)
{
    $diskname = ($FixedOsDiskUri.Split('/')[-1]).split('.')[0]
}
$diskname = $diskname.Replace("`r`n","")
write-log "Disk name: $diskName" -logonly
if ($rescuevm.StorageProfile.DataDisks.Count -gt 0)
{
  if ($managedVM) 
  {
    $problemvmOsDiskManagedDiskID = $rescuevm.StorageProfile.DataDisks[0].ManagedDisk.id
  }
}
else
{
    $message = "[Error] Unable to find the data disk on rescue VM $rescueVMName."
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}
write-log "[Running] Removing data disk from rescue VM $rescueVMName"
try
{
    $null = Remove-AzureRmVMDataDisk -VM $rescuevm -Name $diskName -ErrorAction Stop -WarningAction SilentlyContinue
    $null = Update-AzureRmVM -ResourceGroupName $rescueResourceGroupName -VM $rescuevm -ErrorAction stop
    write-log "[Success] Removing data disk from rescue VM $rescueVMName" -color green
}
catch
{
    $message = "[Error] Unable to remove data disk from rescue VM."
    write-log $message -color red
    write-log "$message - $($_.Exception.GetType().FullName)" -logOnly
    write-log "Exception Message: $($_.Exception.Message)" -logOnly
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "$message. To delete the resource group you may delete that by executing the PowerShell script .\$removeRescueRgScript " -cleanupscript $removeRescueRgScript
    return $scriptResult
}

#Stop the VM before performing the disk swap.
$stopped = StopTargetVM -resourceGroupName $resourceGroupName -VmName $vmName
write-log "`$stopped: $stopped" -logOnly
if (-not $stopped) 
{
    $message = "[Error] Unable to stop problem VM $vmName. Try stopping the VM from the Azure portal."
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}

#Step 4 -Disk Swapping the OS Disk to point to the fixed OSDisk Uri/updating ManagedDiskID
write-log "[Running] Swapping data disk from $rescueVMName to OS disk on problem VM"
if (-not $managedVM)
{
    $problemvmOsDiskUri=$vm.StorageProfile.OsDisk.Vhd.Uri 
    CreateRestoreOriginalStateScript -scriptonly -resourceGroupName $resourceGroupName -VmName $vmName -problemvmOriginalOsDiskUri $problemVMosDiskUri -problemvmOsDiskManagedDiskID $null -managedVM $managedVM -restoreOriginalStateScript $restoreOriginalStateFile -subscriptionId $subscriptionId
    $restoreOriginalStateScriptPath = (get-childitem $restoreOriginalStateFile).FullName
    $vm.StorageProfile.OsDisk.Vhd.Uri = $FixedOsDiskUri 
    $null = Update-AzureRmVM -ResourceGroupName $resourceGroupName -VM $vm 
    write-log "[Success] Swapped OS disk for problem VM $vmName" -color green
}
else
{
    CreateRestoreOriginalStateScript -scriptonly -resourceGroupName $resourceGroupName -VmName $vmName -problemvmOriginalOsDiskUri $null  -OriginalProblemOSManagedDiskID $OriginalProblemOSManagedDiskID -managedVM $managedVM -restoreOriginalStateScript $restoreOriginalStateFile -subscriptionId $subscriptionId
    $restoreOriginalStateScriptPath = (get-childitem $restoreOriginalStateFile).FullName
    $null = set-AzureRmVMOSDisk -vm $vm -ManagedDiskId $problemvmOsDiskManagedDiskID -CreateOption FromImage -WarningAction SilentlyContinue
    $null = Update-AzureRmVM -ResourceGroupName $resourceGroupName -VM $vm 
    write-log "[Success] Swapped OS disk for problem VM $vmName" -color green
}

#Step 5 -Start the VM
write-log "[Running] Starting problem VM $vmName"
$started = Start-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName
if ($started)
{
   write-log "[Success] Started VM $vmName" -color green
}
else
{
    $message = "[Error] Unable to start VM $vmName. Try starting it in the Azure portal."
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}

#Step 5 Launch RDP file to the VM
if ($windowsVM)
{
    write-log "[Running] Opening RDP file for VM $vmName"
    $null = Get-AzureRmRemoteDesktopFile -ResourceGroupName $resourceGroupName -Name $vmName -Launch
}

#Step 6 Clean up rescue resource group (Allows to delete it from script or later, this script is created from the new-AzureRescueVM)
write-log "`nIf you were able to successfully recover problem VM $vmName, and no longer need the resources under resource group $rescueResourceGroupName, you have the option to delete it now or delete later by running the script $removeRescueRgScript." -noTimeStamp
write-log "`n Delete now (Y/N)?" -color cyan -noTimeStamp
if ((read-host) -eq 'Y')
{
    write-log "User chose to delete resource group $rescueResourceGroupName" -color cyan
    write-log "[Running] Deleting resource group $rescueResourceGroupName"
    $result = Remove-AzureRmResourceGroup -Name $rescueResourceGroupName -force
    if ($result)
    {
        write-log "[Success] Deleted resource group $rescueResourceGroupName" -color green
    }
}
else
{  
    write-log "`n[Information] To delete the Rescue Resource Group, you may delete it later by executing the below Powershell script from $removeRescueRgScriptPath :`n" -notimestamp -color cyan  
    write-log "$removeRescueRgScript`n" -notimestamp
}

if (-not $managedVM)
{
    DeleteSnapShotAndVhd -osDiskVhdUri $OriginalosDiskVhdUri -resourceGroupName $resourceGroupName
}

write-log "`n[Information] If you need to switch back to the problem VM in its original state, you may do so by executing the script $restoreOriginalStateScriptPath" -noTimeStamp -color cyan
write-log "`n $restoreOriginalStateFile`n"  -noTimeStamp
$script:scriptEndTime = (get-date).ToUniversalTime()
$script:scriptDuration = new-timespan -Start $script:scriptStartTime -End $script:scriptEndTime
write-log "Script duration: $('{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f $script:scriptDuration)"
write-log "Log file: $logFile"

$scriptResult = Get-ScriptResultObject -scriptSucceeded $true -rescueScriptCommand $MyInvocation.Line -cleanupScript $removeRescueRgScript -restoreOriginalStateScript $restoreOriginalStateFile

#invoke-item $logFile
#return $scriptResult