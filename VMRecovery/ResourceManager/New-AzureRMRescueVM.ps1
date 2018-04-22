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
    
.PARAMETER VmName
    This is a mandatory Parameter, Name of the problem VM that needs to be recovered.

.PARAMETER ResourceGroupName
    This is a mandatory Parameter, Name of the resource group the problem VM belongs to.

.PARAMETER SubscriptionId
    Optional Parameter, SubscriptionID the VM belongs to.

.PARAMETER showErrors
    Optional Parameter. By default it is set to true, so it displays all errors thrown by PowerShell in the console, if set to False it runs in silentMode. 

.PARAMETER prefix
    Optional Parameter. By default the new Rescue VM and its resources are all created under a resource group named same as the original resource group name with a prefix of 'rescue', however the prefix can be changed to a different value to override the default 'rescue'

.PARAMETER UserName
    Optional Parameter. Allows to pass in the user name of the rescue VM during its creation, by default during case creation it will prompt

.PARAMETER Password
    Optional Parameter. Allows to pass in the password of the rescue VM during its creation, by default t will prompt for password during its creation

.PARAMETER AllowManagedVM
    Optional Parameter. This allows the script to support Managed VM's also, however prior to that the SubscriptionID needs to be whitelisted to be able to use the OS Disk Swap feature for managed VM's.

.PARAMETER Sku
    Optional Parameter. Allows to pass in the SKU of the preferred image of the OS for the Rescue VM

.PARAMETER Offer
    Optional Parameter. Allows to pass in the Offer of the preferred image of the OS for the Rescue VM

.PARAMETER Publisher
    Optional Parameter. Allows to pass in the Publisher of the preferred image of the OS for the Rescue VM

.PARAMETER Version
    Optional Parameter. Allows to pass in the Version of the preferred image of the OS for the Rescue VM

.EXAMPLE
    Example using all the mandatory fields:

    $scriptResult = .\New-AzureRMRescueVM.ps1 -resourceGroupName sujtemp -VmName sujnortheurope -subscriptionId d7eaa135-abdf-4aaf-8868-2002dfeea60c

.EXAMPLE
    Examples with optional parametersm in this example it will create the rescue VM with RedHat installed

    $scriptResult = .\New-AzureRMRescueVM.ps1 -VmName ubuntu -resourceGroupName portalLin -subscriptionId d7eaa135-abdf-4aaf-8868-2002dfeea60c -Publisher RedHat -Offer RHEL -Sku 7.3 -Version 7.3.2017090723 -prefix rescuered 

.EXAMPLE
    $scriptResult = .\New-AzureRMRescueVM.ps1 -resourceGroupName sujtemp -VmName sujnortheurope -subscriptionId d7eaa135-abdf-4aaf-8868-2002dfeea60c -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex2"

.EXAMPLE
    Example for managed disk VM:

    $scriptResult =  .\New-AzureRMRescueVM.ps1 -resourceGroupName testsujmg -VmName sujmanagedvm -subscriptionId d7eaa135-abdf-4aaf-8868-2002dfeea60c -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex17" -AllowManagedVM   

.EXAMPLE
    Example for managed disk VM

    $scriptResult = .\New-AzureRMRescueVM.ps1 -resourceGroupName testsujmg -VmName sujmanagedvm  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex17" -AllowManagedVM   

.EXAMPLE
    Example for marketplace image with Plan

    $scriptResult = .\New-AzureRMRescueVM.ps1 -resourceGroupName recoverytest -VmName datasciencevm  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex17" -AllowManagedVM

.EXAMPLE 
    Using a VM created from a custom image:

    $scriptResult =  .\New-AzureRMRescueVM.ps1 -resourceGroupName testvmrecovery2 -VmName win2016custom  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex18"

.NOTES
    Name: New-AzureRMRescueVM.ps1

    To get help on the below script run get-help .\New-AzureRMRescueVM.ps1

    Author: Sujasd
#>

param(
        [Parameter(mandatory=$true)]
        [String]$vmName,

        [Parameter(mandatory=$true)]
        [String]$ResourceGroupName,

        [Parameter(mandatory=$false)]
        [String]$subscriptionId,

        [Parameter(mandatory=$false)]
        [String]$Password,

        [Parameter(mandatory=$false)]
        [String]$UserName,

        [Parameter(mandatory=$false)]
        [Bool]$showErrors=$true,

        [Parameter(mandatory=$false)]
        [String]$prefix = 'rescue',

        [Parameter(mandatory=$false)]
        [String]$Sku,

        [Parameter(mandatory=$false)]
        [String]$Offer,

        [Parameter(mandatory=$false)]
        [String]$Publisher,

        [Parameter(mandatory=$false)]
        [String]$Version,

        [switch]$AllowManagedVM = $true
     )

$Error.Clear()
if (-not $showErrors) {
    $ErrorActionPreference = 'SilentlyContinue'
}

$script:scriptStartTime = (Get-Date).ToUniversalTime()
$logFile = $env:TEMP + "\" + $vmName + "_" + (Get-Date $script:scriptStartTime -f yyyyMMddHHmmss) + ".log"
$RestoreCommandFile = "Restore_" + $vmName + ".ps1"
# Get running path
$RunPath = split-path -parent $MyInvocation.MyCommand.Source
cd $RunPath
$CommonFunctions = $runPath+"\Common-Functions.psm1"

#Import-Module Common-Functions -ArgumentList $logFile -ErrorAction Stop 
if (Get-Module Common-Functions) {remove-module -name Common-Functions}   
import-module -Name $CommonFunctions  -ArgumentList $logFile -ErrorAction Stop 
write-log "Log file: $logFile"
write-log $MyInvocation.Line -logOnly

#Checks to see if AzureRM is available
if (-not (get-module -ListAvailable -name 'AzureRM.Profile')) 
{
    $message = "Azure PowerShell not installed. Either install Azure PowerShell from https://docs.microsoft.com/en-us/powershell/azure/install-azurerm-ps or use Cloud Shell PowerShell at https://shell.azure.com/powershell" 
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}

if (-not (Get-AzureRmContext).Account)
{
    $null = Login-AzureRmAccount
}

if (-not $subscriptionId)
{    
    $subscriptionId = (Get-AzureRmContext).Subscription.Id 
    if (-not $subscriptionId)
    {
        $message = "Unable to determine subscription ID. Run the script again using -SubscriptionID to specify the subscription ID." 
        write-log $message -color red
        $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
        return $scriptResult
    }
}
else
{
    #Set the context to the correct subscription ID
    write-log "Setting the context to subscriptionId $subscriptionId" 
    $subContext= Set-AzureRmContext -SubscriptionId $subscriptionId
    write-log $subContext -logOnly
    if ($subContext -eq $null) 
    {
        $message = "Unable to set context to subscription ID $subscriptionId. Run Login-AzureRMAccount and then try the script again." 
        write-log $message -color red
        $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
        return $scriptResult
    }
}
write-log "subscriptionId: $subscriptionId"

#Step 1 Get the VM Object
write-log "Running Get-AzureRmVM -resourceGroupName $resourceGroupName -Name $vmName" 
try
{
    $vm = Get-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction Stop -WarningAction SilentlyContinue
}
catch 
{
    $message = "VM $vmName not found in resource group $resourceGroupName in subscription $subscriptionId. Make sure you are specifying the correct resourceGroupName, vmName, and subscriptionId for the problem VM."
    write-log $message -color red
    write-log "Exception Type: $($_.Exception.GetType().FullName)" -logOnly
    write-log "Exception Message: $($_.Exception.Message)" -logOnly
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}
write-log "`$vm: $vm" -logOnly

if (-not (SupportedVM -vm $vm -AllowManagedVM $AllowManagedVM)) 
{  
    $message = "VM $($vm.name) is not supported."
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}

write-log "Found VM $($vm.Name)" -color green

if ($vm.StorageProfile.OsDisk.ManagedDisk)
{
    $managedVM = $true
}
else
{
    $managedVM = $false
}

write-log "VM $vmName OsType is $($vm.StorageProfile.OsDisk.OsType)"
if ($vm.StorageProfile.OsDisk.OsType -eq 'Windows') 
{
    $windowsVM = $true
}
else 
{   
    $windowsVM = $false
}

#collecting user name and Password if not passed
if ($Password -and $UserName) 
{
    $secPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $secPassword
 }
 else
 {
    $message = "Enter username and password to use for the new rescue VM that will be created."
    write-log $message
    $Cred = Get-Credential -Message $message
 }

#Step 2 Stop VM
$stopped = StopTargetVM -resourceGroupName $resourceGroupName -VmName $vmName
write-log "`$stopped: $stopped" -logOnly
if (-not $stopped) 
{
    $message = "Unable to stop VM $vmName"
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}

#Step 3 SnapshotAndCopyOSDisk only for Non-ManagedVM's.
$OriginalosDiskVhdUri = $vm.StorageProfile.OsDisk.Vhd.Uri
$OrignalosDiskName = $vm.StorageProfile.OsDisk.Name 
if (-not $managedVM)
{
    $osDiskVHDToBeRepaired = SnapshotAndCopyOSDisk -vm $vm -prefix $prefix -resourceGroupName $resourceGroupName  
}
else
{ 
    $osDiskVHDToBeRepaired = $prefix+ "fixedosdisk" + $OrignalosDiskName
}

if (-not $osDiskVHDToBeRepaired)
{
    $message = "Unable to snapshot and copy the problem VM's OS disk." 
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}
$osDiskVHDToBeRepaired = $osDiskVHDToBeRepaired.Replace("`r`n","")
write-log "`$osDiskVHDToBeRepaired: $osDiskVHDToBeRepaired" -logOnly

#Step 4 Create Rescue VM
$rescueVMName = "$prefix$vmName"
$rescueResourceGroupName = "$prefix$resourceGroupName"
$rescueVm = CreateRescueVM -vm $vm -resourceGroupName $resourceGroupName -rescueVMName $rescueVMName -rescueResourceGroupName $rescueResourceGroupName -prefix $prefix -Sku $sku -Offer $offer -Publisher $Publisher -Version $Version -Credential $cred 
write-log "`$rescueVM: $rescueVm" -logOnly
if (-not $rescuevm)
{
    $message = "Unable to create the Rescue VM, cannot proceed."
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}

#Step 5 #Get a reference to the rescue VM Object
write-log "Running Get-AzureRmVM -resourceGroupName $rescueResourceGroupName -Name $rescueVMName"
$rescuevm = Get-AzureRmVM -resourceGroupName $rescueResourceGroupName -Name $rescueVMName -WarningAction SilentlyContinue
if (-not $rescuevm)
{
    $message = "Rescue VM $rescueVMName not found." 
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}

#Step 6  Attach the OS Disk as data disk to the rescue VM
#$attached = AttachOsDisktoRescueVM -rescueVMName $rescueVMName -rescueResourceGroupName $rescueResourceGroupName -osDiskVHDToBeRepaired $osDiskToBeRepaired
#creates a dataDisk off of the copied snapshot of the OSDisk
if ($managedVM)
{
    #$storageType= "PremiumLRS"
    #For ManagedVM SnapshotAndCopyOSDisk returns the snapshotname
    $storageType = 'StandardLRS'
    $snapshotname = $osDiskVHDToBeRepaired
    $ToBeFixedManagedOsDisk = $prefix + "fixedos" + $vm.StorageProfile.OsDisk.Name 
    $olddisk = Get-AzureRmDisk -resourceGroupName $resourceGroupName -DiskName $OrignalosDiskName -WarningAction SilentlyContinue
    $location = $olddisk.Location
    $diskconfig = New-AzureRmDiskConfig -AccountType $storageType -Location $location -SourceResourceId $olddisk.Id -CreateOption Copy -WarningAction SilentlyContinue
    $ToBeFixedManagedOsDisk = Get-ValidLength -InputString $ToBeFixedManagedOsDisk -Maxlength 80
    $disk = New-AzureRmDisk -Disk $diskConfig -resourceGroupName $resourceGroupName -DiskName $ToBeFixedManagedOsDisk -WarningAction SilentlyContinue
    $diskName = $ToBeFixedManagedOsDisk
    $managedDiskID = $disk.Id
}
else
{
    $diskName = ($osDiskVHDToBeRepaired.Split('/')[-1]).split('.')[0] 
    $diskName = Get-ValidLength -InputString $diskName -Maxlength 80
    $osDiskSize = $vm.StorageProfile.OsDisk.DiskSizeGB
    if (-not $osDiskSize)
    {
       $osDiskSize = 127    
       write-log "Could not determine the OS disk size for VM $vmName. Will use 127GB when attaching it to the rescue VM as a data disk." 
    }
}
$attached = AttachOsDisktoRescueVM -rescueVMName $rescueVMName -rescueResourceGroupName $rescueResourceGroupName -osDiskVHDToBeRepaired $osDiskVHDToBeRepaired -diskName $diskName -osDiskSize $osDiskSize -managedDiskID $managedDiskID

write-log "`$attached: $attached" -logonly
if (-not $attached)
{
    write-log "Unable to attach disk $osDiskToBeRepaired as a data disk to rescue VM $rescueVMName" -color red
    return
}

#Step 7 Start the VM
write-log "Starting rescue VM: $($rescueVm.Name)"
$started = Start-AzureRmVM -resourceGroupName $rescueResourceGroupName -Name $rescuevm.Name 
write-log "`$started: $started" -logOnly
if ($started)
{
   write-log "Successfully started rescue VM $($rescueVm.Name)" -color green
}

#Step 8 Automatically start up the RDP Connection
#Manual Fixing of the oS Disk
if ($windowsVM)
{
    write-log "Opening RDP file for rescue VM $($rescuevm.Name)"
    Get-AzureRmRemoteDesktopFile -resourceGroupName $rescueResourceGroupName -Name $rescuevm.Name -Launch
}

#Log basic info into the log file.
write-log "Rescue VM name: $($rescueVm.Name)"
write-log "Rescue VM resource group name: $rescueResourceGroupName"
write-log "Data disk name attached to rescue VM: $diskName"
if ($managedVM)
{
    write-log "Managed disk ID of data disk: $managedDiskID"
}
else
{
    write-log "ResourceUri of fixed OS disk: $osDiskVHDToBeRepaired"
}

write-log "Next Steps: RDP to rescue VM $($rescueVm.Name). After fixing the OS disk, run Restore-AzureRMOriginalVM.ps1 to swap the disk back to the problem VM:"
if ($managedVM)
{
    #$restoreScriptCommand = ".\Restore-AzureRMOriginalVM.ps1 -resourceGroupName `"$resourceGroupName`" -VmName `"$vmName`" -subscriptionId `"$subscriptionId`" -diskName `"$diskname`" -snapshotName `"$snapshotname`" -prefix `"$prefix`""
    $restoreScriptCommand = ".\Restore-AzureRMOriginalVM.ps1 -resourceGroupName $resourceGroupName -VmName $vmName -subscriptionId $subscriptionId -diskName $diskname -prefix $prefix"
}
else
{
    $restoreScriptCommand = ".\Restore-AzureRMOriginalVM.ps1 -resourceGroupName $resourceGroupName -VmName $vmName -subscriptionId $subscriptionId -FixedOsDiskUri $osDiskVHDToBeRepaired -OriginalosDiskVhdUri $OriginalosDiskVhdUri -prefix $prefix"
}
$restoreScriptCommand | set-content $RestoreCommandFile 
$restoreScriptCommand = ".\" + $RestoreCommandFile.Split('\')[-1]
write-log $restoreScriptCommand
$scriptResult = Get-ScriptResultObject -scriptSucceeded $true -restoreScriptCommand $restoreScriptCommand -rescueScriptCommand $MyInvocation.Line

<###### End of script tasks ######>
$script:scriptEndTime = (get-date).ToUniversalTime()
$script:scriptDuration = new-timespan -Start $script:scriptStartTime -End $script:scriptEndTime
write-log ('Script Duration: ' + ('{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f $script:scriptDuration)) -color cyan

invoke-item $logFile

return $scriptResult