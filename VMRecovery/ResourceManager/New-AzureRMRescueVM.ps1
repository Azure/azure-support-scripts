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

    $scriptResult = .\New-AzureRMRescueVM.ps1 -resourceGroupName sujtemp -VmName sujnortheurope -subscriptionId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

.EXAMPLE
    Examples with optional parametersm in this example it will create the rescue VM with RedHat installed

    $scriptResult = .\New-AzureRMRescueVM.ps1 -VmName ubuntu -resourceGroupName portalLin -subscriptionId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx -Publisher RedHat -Offer RHEL -Sku 7.3 -Version 7.3.2017090723 -prefix rescuered 

.EXAMPLE
    $scriptResult = .\New-AzureRMRescueVM.ps1 -resourceGroupName sujtemp -VmName sujnortheurope -subscriptionId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex2"

.EXAMPLE
    Example for managed disk VM:

    $scriptResult =  .\New-AzureRMRescueVM.ps1 -resourceGroupName recoveryVMRg -VmName recovmtestmg -subscriptionId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex1" 

.EXAMPLE
    Example for managed disk VM

    $scriptResult = .\New-AzureRMRescueVM.ps1 -resourceGroupName recoveryVMRg -VmName recovmtestmg  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex2" 

.EXAMPLE
    Example for marketplace image with Plan

    $scriptResult = .\New-AzureRMRescueVM.ps1 -resourceGroupName recoverytest -VmName datasciencevm  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex17" -AllowManagedVM

.EXAMPLE 
    Using a VM created from a custom image:

    $scriptResult =  .\New-AzureRMRescueVM.ps1 -resourceGroupName testvmrecovery2 -VmName win2016custom  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex18"

.EXAMPLE 
    Using a VM Unmanaged Windows VM

    $scriptResult =  .\New-AzureRMRescueVM.ps1 -resourceGroupName testvmrecovery2 -VmName sujUNManagedvm  -UserName "sujasd" -Password "XPa55w0rrd12345" -prefix "rescuex48"

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

$script:scriptStartTime = (get-date).ToUniversalTime()
$timestamp = get-date $script:scriptStartTime -f yyyyMMddHHmmss
$scriptPath = split-path -path $MyInvocation.MyCommand.Path -parent
$scriptName = (split-path -path $MyInvocation.MyCommand.Path -leaf).Split('.')[0]
$logFile = "$scriptPath\$($scriptName)_$($vmName)_$($timestamp).log"
$restoreCommandFile = "Restore_" + $vmName + ".ps1"
set-location $scriptPath
$commonFunctionsModule = "$scriptPath\Common-Functions.psm1"

#Import-Module Common-Functions -ArgumentList $logFile -ErrorAction Stop 
if (get-module Common-Functions) 
{
    remove-module -name Common-Functions
}   
import-module -Name $commonFunctionsModule -ArgumentList $logFile -ErrorAction Stop 
write-log "Log file: $logFile"
write-log $MyInvocation.Line -logOnly

#Checks to see if AzureRM is available
if (-not (get-module -ListAvailable -name 'AzureRM.Profile') -and (-not $env:ACC_CLOUD)) 
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
    write-log "[Running] Getting authentication context"
    $authContext = Get-AzureRmContext
    if (-not $authContext.Subscription.Id)
    {        
        $message = "[Error] Unable to determine subscription ID. Run the script again using -SubscriptionID to specify the subscription ID." 
        write-log $message -color red
        $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
        return $scriptResult
    }
}
else
{
    #Set the context to the correct subscription ID
    write-log "[Running] Setting context to subscriptionId $subscriptionId"
    $authContext = Set-AzureRmContext -SubscriptionId $subscriptionId
    write-log $authContext -logOnly
    if (-not $authContext.Subscription.Id)
    {
        $message = "[Error] Unable to set context to subscription ID $subscriptionId. Run Login-AzureRMAccount and then try the script again." 
        write-log $message -color red
        $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
        return $scriptResult
    }
}
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

# Step 1 Get VM object
write-log "[Running] Get-AzureRmVM -resourceGroupName $resourceGroupName -Name $vmName"
try
{
    $vm = Get-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction Stop -WarningAction SilentlyContinue
}
catch 
{
    $message = "[Error] Problem VM $vmName not found in resource group $resourceGroupName in subscription $subscriptionId. Verify the vmName, resourceGroupName, and subscriptionId and run the script again."
    write-log $message -color red
    write-log "Exception Type: $($_.Exception.GetType().FullName)" -logOnly
    write-log "Exception Message: $($_.Exception.Message)" -logOnly
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}
write-log "`$vm: $vm" -logOnly

if (-not (SupportedVM -vm $vm -AllowManagedVM $AllowManagedVM)) 
{  
    $message = "[Error] Problem VM $($vm.name) is not supported."
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}

write-log "[Success] Found problem VM $($vm.Name)" -color green

if ($vm.StorageProfile.OsDisk.ManagedDisk)
{
    $managedVM = $true
}
else
{
    $managedVM = $false
}

write-log "[Running] Getting OsType for problem VM $vmName"
if ($vm.StorageProfile.OsDisk.OsType -eq 'Windows') 
{
    $windowsVM = $true
}
else 
{   
    $windowsVM = $false
}
write-log "[Success] Problem VM $vmName OsType is $($vm.StorageProfile.OsDisk.OsType)" -color green

# Collect user name and password if they weren't specified at the command line
if ($Password -and $UserName) 
{
    write-log "Rescue VM will use the user name and password specified with the -username and -password parameters."
    $secPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $secPassword
}
else
{
    $message = "[Running] Waiting on username and password to be entered at credential prompt. These will be the username and password to logon to the new rescue VM that will be created."
    write-log $message
    $Cred = Get-Credential -Message "Enter username and password to use for the new rescue VM that will be created"
    if ($Cred)
    {
        write-log "[Success] Credential prompt returned" -color green        
    }
}

# Step 2 Stop problem VM
$stopped = StopTargetVM -resourceGroupName $resourceGroupName -VmName $vmName
write-log "`$stopped: $stopped" -logOnly
if (-not $stopped) 
{
    $message = "[Error] Unable to stop problem VM $vmName"
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
    $osDiskVHDToBeRepaired = $prefix + "fixedosdisk" + $OrignalosDiskName
    $OriginalProblemOSManagedDiskID = $vm.StorageProfile.OsDisk.ManagedDisk.Id
}

if (-not $osDiskVHDToBeRepaired)
{
    $message = "[Error] Unable to snapshot and copy the problem VM's OS disk." 
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message
    return $scriptResult
}
$osDiskVHDToBeRepaired = $osDiskVHDToBeRepaired.Replace("`r`n","")
write-log "`$osDiskVHDToBeRepaired: $osDiskVHDToBeRepaired" -logOnly

# Step 4 Create rescue VM
$rescueVMName = "$prefix$vmName"
$rescueResourceGroupName = "$prefix$resourceGroupName"
$removeRescueRgScript = "Remove_Rescue_RG_" + $rescueResourceGroupName + ".ps1"
CreateRemoveRescueRgScript -rescueResourceGroupName $rescueResourceGroupName -removeRescueRgScript $removeRescueRgScript -scriptonly -subscriptionId $subscriptionId
$removeRescueRgScriptPath = (get-childitem $removeRescueRgScript).FullName
$rescueVM = CreateRescueVM -vm $vm -resourceGroupName $resourceGroupName -rescueVMName $rescueVMName -rescueResourceGroupName $rescueResourceGroupName -prefix $prefix -Sku $sku -Offer $offer -Publisher $Publisher -Version $Version -Credential $cred 
write-log "`$rescueVM: $rescueVM" -logOnly
if (-not $rescueVM)
{
    $message = "[Error] Unable to create the Rescue VM, cannot proceed. You can use the following command to remove the rescue Resourcegroup $($rescueResourceGroupName) that was created as part of running this script OR execute the PowerShell script .\$($removeRescueRgScript) :`n" 
    write-log $message -color red
    CreateRemoveRescueRgScript -rescueResourceGroupName $rescueResourceGroupName -removeRescueRgScript $removeRescueRgScript -commandOnly -subscriptionId $subscriptionId
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message -cleanupScript $removeRescueRgScript
    return $scriptResult
}

#Step 5 #Get a reference to the rescue VM Object
write-log "[Running] Get-AzureRmVM -resourceGroupName $rescueResourceGroupName -Name $rescueVMName"
$rescueVM = Get-AzureRmVM -resourceGroupName $rescueResourceGroupName -Name $rescueVMName -WarningAction SilentlyContinue
if (-not $rescueVM)
{
    $message = "[Error] Rescue VM $rescueVMName not found." 
    write-log $message -color red
    $scriptResult = Get-ScriptResultObject -scriptSucceeded $false -rescueScriptCommand $MyInvocation.Line -FailureReason $message -cleanupScript $removeRescueRgScript
    return $scriptResult
}
else
{
    write-log "[Success] Found rescue VM $rescueVMName" -color green
}

#Step 6 Attach problem VM's OS disk as a data disk to the rescue VM
#$attached = AttachOsDisktoRescueVM -rescueVMName $rescueVMName -rescueResourceGroupName $rescueResourceGroupName -osDiskVHDToBeRepaired $osDiskToBeRepaired
#creates a dataDisk off of the copied snapshot of the OSDisk
if ($managedVM)
{
    #For ManagedVM SnapshotAndCopyOSDisk returns the snapshotname
    $storageType = 'StandardLRS'
    $AzurePsVersion=Get-Module AzureRM -ListAvailable
    #checks to See Powershell version, or of its running from Cloudshell )
    if (($AzurePsVersion -and $AzurePsVersion.Version.Major -ge 6) -or (RanfromCloudshell))
    {
        $storageType = 'Standard_LRS'
    }
    
    $snapshotName = $osDiskVHDToBeRepaired
    $ToBeFixedManagedOsDisk = $prefix + "fixedos" + $vm.StorageProfile.OsDisk.Name 
    $oldDisk = Get-AzureRmDisk -resourceGroupName $resourceGroupName -DiskName $OrignalosDiskName -WarningAction SilentlyContinue
    $location = $oldDisk.Location
    $diskConfig = New-AzureRmDiskConfig -AccountType $storageType -Location $location -SourceResourceId $oldDisk.Id -CreateOption Copy -WarningAction SilentlyContinue
    $toBeFixedManagedOsDisk = Get-ValidLength -InputString $toBeFixedManagedOsDisk -Maxlength 80
    $disk = New-AzureRmDisk -Disk $diskConfig -resourceGroupName $resourceGroupName -DiskName $toBeFixedManagedOsDisk -WarningAction SilentlyContinue
    $diskName = $toBeFixedManagedOsDisk
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
       write-log "Unable to determine OS disk size for problem VM $vmName. Will use 127GB when attaching it to the rescue VM as a data disk." 
    }
}
$attached = AttachOsDisktoRescueVM -rescueVMName $rescueVMName -rescueResourceGroupName $rescueResourceGroupName -osDiskVHDToBeRepaired $osDiskVHDToBeRepaired -diskName $diskName -osDiskSize $osDiskSize -managedDiskID $managedDiskID

write-log "`$attached: $attached" -logonly
if (-not $attached)
{
    write-log "[Error] Unable to attach disk $osDiskToBeRepaired as a data disk to rescue VM $rescueVMName" -color red
    return
}

#Step 7 Start the VM
write-log "[Running] Starting rescue VM $($rescueVm.Name)"
$started = Start-AzureRmVM -resourceGroupName $rescueResourceGroupName -Name $rescuevm.Name
write-log "`$started: $started" -logOnly
if ($started)
{
   write-log "[Success] Started rescue VM $($rescueVm.Name)" -color green
}

#Step 8 Automatically start up the RDP Connection, if is a windows VM and did not run from cloudshell
#Manual Fixing of the oS Disk
if ($windowsVM -and -not (RanFromCloudShell))
{
    write-log "[Running] Getting RDP file for rescue VM $($rescuevm.Name)"
    Get-AzureRmRemoteDesktopFile -resourceGroupName $rescueResourceGroupName -Name $rescuevm.Name -Launch 
}

$script:scriptEndTime = (get-date).ToUniversalTime()
$script:scriptDuration = new-timespan -Start $script:scriptStartTime -End $script:scriptEndTime
write-log "Script duration: $('{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f $script:scriptDuration)"
write-log "Log file: $logFile"

# Log summary information
write-log "`nRescue VM name: $($rescueVm.Name)" -notimestamp
write-log "Rescue VM resource group name: $rescueResourceGroupName" -notimestamp
write-log "Data disk name: $diskName" -notimestamp
if ($managedVM)
{
    write-log "Data disk ID: $managedDiskID" -notimestamp
}
else
{
    write-log "ResourceUri of fixed OS disk: $osDiskVHDToBeRepaired" -notimestamp
}

if ($managedVM)
{
    $restoreScriptCommand = ".\Restore-AzureRMOriginalVM.ps1 -resourceGroupName $resourceGroupName -VmName $vmName -subscriptionId $subscriptionId -diskName $diskname -prefix $prefix -OriginalProblemOSManagedDiskID $OriginalProblemOSManagedDiskID -OriginalDiskName $OrignalosDiskName" 
}
else
{
    $restoreScriptCommand = ".\Restore-AzureRMOriginalVM.ps1 -resourceGroupName $resourceGroupName -VmName $vmName -subscriptionId $subscriptionId -FixedOsDiskUri $osDiskVHDToBeRepaired -OriginalosDiskVhdUri $OriginalosDiskVhdUri -prefix $prefix"
}
$restoreScriptCommand | set-content $restoreCommandFile 
$restoreScriptCommand = ".\" + $restoreCommandFile.Split('\')[-1]
$restoreScriptPath = (get-childitem $restoreScriptCommand).FullName

write-log "`nNext Steps:`n" -notimestamp
write-log "1. RDP to the rescue VM $($rescueVm.Name) to resolve issues with the problem VM's OS disk which is now attached to the rescue VM as a data disk." -notimestamp
write-log "2. After fixing the problem VM's OS disk, run the following script to swap the disk back to the problem VM:`n" -notimestamp
write-log "   $restoreScriptPath`n" -notimestamp

write-log "`n[Information] If you decide not to proceed further and would like to delete all the resources created thus far, you may delete the resource group $rescueResourceGroupName, by executing the script $removeRescueRgScriptPath" -noTimeStamp -color cyan
write-log "`n $removeRescueRgScript" -notimestamp 


$scriptResult = Get-ScriptResultObject -scriptSucceeded $true -restoreScriptCommand $restoreScriptCommand -rescueScriptCommand $MyInvocation.Line -cleanupScript $removeRescueRgScript 

#invoke-item $logFile
#return $scriptResult