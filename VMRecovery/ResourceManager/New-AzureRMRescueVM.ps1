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

.PARAMETER ResourceGroup
    This is a mandatory Parameter, Name of the ResourceGroup the problem VM belongs to.

.PARAMETER SubID
    Optional Parameter, SubscriptionID - the VM belongs to.
.PARAMETER showErrors
    Optional Parameter. By default it is set to true, so it displays all errors thrown by PowerShell in the console, if set to False it runs in silentMode. 

.PARAMETER prefix
    Optional Parameter. By default the new Rescue VM and its resources are all created under a ResourceGroup named same as the original resourceGroup name with a prefix of 'rescue', however the prefix can be changed to a different value to override the default 'rescue'

.PARAMETER UserName
    Optional Parameter. Allows to pass in the UserName  of the Rescue VM during its creation, by default during case creation it will prompt

.PARAMETER Password
    Optional Parameter. Allows to pass in the Password of the Rescue VM during its creation, by default t will prompt for password during its creation

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
    $scriptResult = .\New-AzureRMRescueVM.ps1 -ResourceGroup sujtemp -VmName sujnortheurope -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c ## <==Is an example is with all the mandatory fields
.EXAMPLE
    $scriptResult =  .\New-AzureRMRescueVM.ps1 -VmName ubuntu -ResourceGroup portalLin -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c -Publisher RedHat -Offer RHEL -Sku 7.3 -Version 7.3.2017090723 -prefix rescuered #--Examples with optional parametersm in this example it will create the rescue VM with RedHat installed
.EXAMPLE
    $scriptResult = .\New-AzureRMRescueVM.ps1 -ResourceGroup sujtemp -VmName sujnortheurope -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex2"
.EXAMPLE
    $scriptResult =  .\New-AzureRMRescueVM.ps1 -ResourceGroup testsujmg -VmName sujmanagedvm -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex17" -AllowManagedVM   #--Example for Managed VM
.EXAMPLE
    $scriptResult = .\New-AzureRMRescueVM.ps1 -ResourceGroup testsujmg -VmName sujmanagedvm  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex17" -AllowManagedVM   #--Example for Managed VM
.EXAMPLE (test with a Market place image with a Plan Object)
    $scriptResult = .\New-AzureRMRescueVM.ps1 -ResourceGroup recoverytest -VmName datasciencevm  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex17" -AllowManagedVM
.EXAMPLE (Using a Cutsom Image VM)
    $scriptResult =  .\New-AzureRMRescueVM.ps1 -ResourceGroup testvmrecovery2 -VmName win2016custom  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex18"



.NOTES
    Name: CreateCRPRescueVM.ps1

    Author: Sujasd
#>
# To get Help on the below scrip run Get-Help .\CreateCRPRescueVM.ps1 -
Param(
        [Parameter(mandatory=$true)]
        [String]$VmName,

        [Parameter(mandatory=$true)]
        [String]$ResourceGroup,

        [Parameter(mandatory=$false)]
        [String]$SubID,

        [Parameter(mandatory=$false)]
        [String]$Password,

        [Parameter(mandatory=$false)]
        [String]$UserName,

        [Parameter(mandatory=$false)]
        [Bool]$showErrors=$true,

        [Parameter(mandatory=$false)]
        [String]$prefix = "rescue",

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
$LogFile = $env:TEMP + "\" + $VmName + "_" + ( Get-Date $script:scriptStartTime -f yyyyMMddHHmmss ) + ".log"  
$RestoreCommandFile = "Restore_" + $VmName + ".ps1"
# Get running path
$RunPath = split-path -parent $MyInvocation.MyCommand.Source
cd $RunPath
$CommonFunctions = $runPath+"\Common-Functions.psm1"


#Import-Module Common-Functions -ArgumentList $LogFile -ErrorAction Stop 
if (Get-Module Common-Functions) {remove-module -name Common-Functions}   
Import-Module -Name $CommonFunctions  -ArgumentList $LogFile -ErrorAction Stop 
write-log "Info: Log is being written to ==> $LogFile" 
Write-Log  $MyInvocation.Line -logOnly

#Checks to see if AzureRM is available
if (-not (get-module -ListAvailable -name "AzureRM.Profile")) 
{
    write-log "Cannot proceed, Please install Azure PowerShell from (https://docs.microsoft.com/en-us/powershell/azure/install-azurerm-ps) or use Cloud Shell (https://shell.azure.com/" -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "Cannot proceed, Please install Azure PowerShell from (https://docs.microsoft.com/en-us/powershell/azure/install-azurerm-ps) or use Cloud Shell (https://shell.azure.com/"
    return $scriptResult

} 

if (-not (Get-AzureRmContext).Account)
{
    $null = Login-AzureRmAccount
}

if (-not $SubID)
{    
    $SubID = (Get-AzureRmContext).Subscription.Id 
    if (-not $SubID)
    {
        Write-Log "Unable to determine the  $SubID, Please run the script and provide the subscriptionID with -SubscriptionID switch." -Color Red
        $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "Unable to determine the  $SubID, Please run the scipt and provide the subscriptionID with -SubscriptionID switch."
        return $scriptResult
    }
}
else
{
    #Set the context to the correct subid
    Write-Log "Setting the context to SubID $SubID" 
    $subContext= Set-AzureRmContext -SubscriptionId $SubID
    write-log $subContext -logOnly
    if ($subContext -eq $null) 
    {
        Write-Log "Unable to set the Context for the given subId ==> $SubID, Please make sure you first  run the command ==> Login-AzureRMAccount" -Color Red
        $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "Unable to set the Context for the given subId ==> $SubID, Please make sure you first  run the command ==> Login-AzureRMAccount"
        return $scriptResult
    }
}
Write-log "Current SubscriptionID ==> $SubID" 



#Step 1 Get the VM Object
Write-Log "Running Get-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -Name `"$VmName`"" 
try
{
    $vm = Get-AzureRmVM -ResourceGroupName $ResourceGroup -Name $VmName -ErrorAction Stop -WarningAction SilentlyContinue
}
catch 
{
    write-Log "Specified VM ==> $VmName was not found in the Resource Group ==> $ResourceGroup and in Subscription ==> $SubID, please make sure you are providing the correct SubId/RG/VmName of the problem VM" -color red
    Write-Log "Exception Type: $($_.Exception.GetType().FullName)" -logOnly
    Write-Log "Exception Message: $($_.Exception.Message)" -logOnly
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "Specified VM ==> $VmName was not found in the Resource Group ==> $ResourceGroup, please make sure you are the SubId/RG/VmName of the problem VM"
    return $scriptResult
}
write-log "`"$vm`" => $($vm)" -logOnly

if (-not (SupportedVM -vm $vm -AllowManagedVM $AllowManagedVM)) 
{  
    write-log "This VM ==> $($vm.name) is not supported, exiting" -Color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "This VM ==> $($vm.name) is not supported, exiting"
    return $scriptResult
}
Write-Log "Successfully got the VM Object info for $($vm.Name)" -Color Green
if ($vm.StorageProfile.OsDisk.ManagedDisk) {$managedVM = $true} else {$managedVM = $false}
if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") 
{
    write-log "Detected 'Windows' as the OS Type for $Vmname"      
    $windowsVM= $true
}
else 
{   
    write-log "Detected 'Linux' as the OS Type for $Vmname" 
    $windowsVM= $false
}

#collecting user name and Password if not passed
if ($Password -and $UserName) 
{
    $secPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $secPassword
 }
 else
 {
    Write-Log "Please enter the UserName and Password for the new rescue VM that is being created " 
    $Cred = Get-Credential -Message "Enter a username and password for the Rescue virtual machine."
 }

#Step 2 Stop VM
$stopped = StopTargetVM -ResourceGroup $ResourceGroup -VmName $VmName
write-log "`"$stopped`" ==> $($stopped)" -logOnly
if (-not $stopped) 
{
    Write-Log "Unable to stop the VM ==> $($VmName)" -Color Red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "Unable to stop the VM ==> $($VmName)"
    return $scriptResult
}


#Step 3 SnapshotAndCopyOSDisk only for Non-ManagedVM's.
$OriginalosDiskVhdUri = $vm.StorageProfile.OsDisk.Vhd.Uri
$OrignalosDiskName = $vm.StorageProfile.OsDisk.Name 
if (-not $managedVM)
{
    $osDiskVHDToBeRepaired = SnapshotAndCopyOSDisk -vm $vm -prefix $prefix -ResourceGroup $ResourceGroup  
}
else
{ 
    $osDiskVHDToBeRepaired = $prefix+ "fixedosdisk" + $OrignalosDiskName
}

if (-not $osDiskVHDToBeRepaired)
{
    Write-Log "Unable to snapshot and copy the OS Disk to be repaired, cannot proceed" -Color Red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "Unable to snapshot and copy the OS Disk to be repaired, cannot proceed"
    return $scriptResult
}
$osDiskVHDToBeRepaired = $osDiskVHDToBeRepaired.Replace("`r`n","")
write-log "`"$osDiskVHDToBeRepaired`" => $($osDiskVHDToBeRepaired)" -logOnly


#Step 4 Create Rescue VM
$rescueVMNname = "$prefix$Vmname"
$RescueResourceGroup = "$prefix$ResourceGroup"
$rescueVm = CreateRescueVM -vm $vm -ResourceGroup $ResourceGroup  -rescueVMNname $rescueVMNname -RescueResourceGroup $RescueResourceGroup -prefix $prefix -Sku $sku -Offer $offer -Publisher $Publisher -Version $Version -Credential $cred 
Write-Log "$reccueVM ==> $($rescueVm)" -logOnly
if (-not $rescuevm)
{
    Write-Log "Unable to create the Rescue VM, cannot proceed." -Color Red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "Unable to create the Rescue VM, cannot proceed."
    return $scriptResult
}


#Step 5 #Get a reference to the rescue VM Object
Write-Log "Running Get-AzureRmVM -ResourceGroupName `"$RescueResourceGroup`" -Name `"rescueVMNname`"" 
$rescuevm = Get-AzureRmVM -ResourceGroupName $RescueResourceGroup -Name $rescueVMNname -WarningAction SilentlyContinue
if (-not $rescuevm)
{
    Write-Log "RescueVM ==>  $rescueVMNname cannot be found, Cannot proceed" -Color Red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason "RescueVM ==>  $rescueVMNname cannot be found, Cannot proceed"
    return $scriptResult
}

#Step 6  Attach the OS Disk as data disk to the rescue VM
#$attached = AttachOsDisktoRescueVM -rescueVMNname $rescueVMNname -RescueResourceGroup $RescueResourceGroup -osDiskVHDToBeRepaired $osDiskToBeRepaired
#creates a dataDisk off of the copied snapshot of the OSDisk
if ($managedVM)
{
    #$storageType= "PremiumLRS"
    #For ManagedVM SnapshotAndCopyOSDisk returns the snapshotname
    $storageType= "StandardLRS"
    $snapshotname = $osDiskVHDToBeRepaired
    $ToBeFixedManagedOsDisk = $prefix + "fixedos" + $vm.StorageProfile.OsDisk.Name 
    $olddisk = Get-AzureRmDisk -ResourceGroupName $ResourceGroup -DiskName $OrignalosDiskName 
    $location = $olddisk.Location
    $diskconfig = New-AzureRmDiskConfig -AccountType $storageType -Location $location -SourceResourceId $olddisk.Id -CreateOption Copy
    $ToBeFixedManagedOsDisk = Get-ValidLength -InputString $ToBeFixedManagedOsDisk -Maxlength 80
    $disk = New-AzureRmDisk -Disk $diskConfig -ResourceGroupName $resourceGroup -DiskName $ToBeFixedManagedOsDisk
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
       $osDiskSize= 127    
       Write-Log "Unable to retrieve the OSDiskSze for VM $VMname, so instead using 127 when attaching it to the datadisk" 
    }
}
$attached = AttachOsDisktoRescueVM -rescueVMNname $rescueVMNname -RescueResourceGroup $RescueResourceGroup -osDiskVHDToBeRepaired $osDiskVHDToBeRepaired -diskName $diskName -osDiskSize $osDiskSize -managedDiskID $managedDiskID

write-log "`"$attached`" ==> $($attached)" -logonly
if (-not $attached)
{
    Write-Log "Unable to attach the disk ==> $osDiskToBeRepaired as data disk to Rescue VM==> $rescueVMNname,  cannot proceed" -Color Red
    Return
}

#Step 7 Start the VM
Write-Log "Starting the Rescue VM ==> $rescueVm.Name" 
$started= Start-AzureRmVM -ResourceGroupName $RescueResourceGroup -Name $rescuevm.Name 
write-log "`"$started`" ==> $($started)" -logOnly
if ($Started)
{
   Write-Log "Successfully started the  Rescue VM ==> $($rescueVm.Name)" -Color Green
}


#Step 8 Automatically start up the RDP Connection
#Manual Fixing of the oS Disk
if ($windowsVM)
{
    Write-log "Opening the RDP file to connect to the rescue VM ==> $($rescuevm.Name)" 
    Get-AzureRmRemoteDesktopFile -ResourceGroupName $RescueResourceGroup -Name $rescuevm.Name -Launch
}

#Log basic info into the log file.
Write-Log "================================================================"
Write-Log "================================================================"
Write-Log "Informational only"
Write-Log "================================================================"
Write-Log "================================================================"
write-log "Rescue VM Name                                ==> $($rescueVm.Name)" 
write-log "Rescue VM Name's ResourceGroup                ==> $RescueResourceGroup"
write-log "Data Disk Name that was attached to RescueVM  ==> $diskName"
if ($managedVM)
{
    write-log "Managed Data disk ID ==> $($managedDiskID)"
}
else
{
    write-log "Fixed OS Disk's ResourceUri                   ==> $osDiskVHDToBeRepaired"
}

Write-Log "================================================================"
Write-Log "================================================================"
write-log "Next Steps"
Write-Log "================================================================"
Write-Log "================================================================"
write-log "RDP into the rescue VM ==> $($rescueVm.Name) "
write-log "After fixing the OS Disk run the RecoverVM script to Recover the VM as follows:"
if ($managedVM)
{
    #$restoreScriptCommand = ".\Restore-AzureRMOriginalVM.ps1 -ResourceGroup `"$ResourceGroup`" -VmName `"$VmName`" -SubID `"$SubID`" -diskName `"$diskname`" -snapshotName `"$snapshotname`" -prefix `"$prefix`""
    $restoreScriptCommand = ".\Restore-AzureRMOriginalVM.ps1 -ResourceGroup `"$ResourceGroup`" -VmName `"$VmName`" -SubID `"$SubID`" -diskName `"$diskname`"  -prefix `"$prefix`""
}
else
{
    $restoreScriptCommand = ".\Restore-AzureRMOriginalVM.ps1 -ResourceGroup `"$ResourceGroup`" -VmName `"$VmName`" -SubID `"$SubID`" -FixedOsDiskUri `"$osDiskVHDToBeRepaired`" -OriginalosDiskVhdUri `"$OriginalosDiskVhdUri`"  -prefix `"$prefix`""
}
$restoreScriptCommand | Set-Content $RestoreCommandFile 
$restoreScriptCommand = ".\" + $RestoreCommandFile.Split('\')[-1]
write-log $restoreScriptCommand
$scriptResult = Get-ScriptResultObject -scriptSucceeded $true -restoreScriptCommand $($restoreScriptCommand) -rescueScriptCommand $MyInvocation.Line 


<###### End of script tasks ######>
$script:scriptEndTime = (Get-Date).ToUniversalTime()
$script:scriptDuration = New-Timespan -Start $script:scriptStartTime -End $script:scriptEndTime
Write-Log ('Script Duration: ' +  ('{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f $script:scriptDuration)) -color Cyan

Invoke-Item $LogFile

return $scriptResult




