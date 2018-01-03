<#
.SYNOPSIS
    Creates a Rescue VM and attaches the OS Disk of the problem VM to this intermediate working rescue VM to fix the OS Disk issue of the problem VM.

.DESCRIPTION
    Occasionally Azure IaaS VMs (Microsoft.Compute/virtualMachines) may not start because there is something wrong with the operating system (OS) disk preventing it from booting up correctly.
    In such cases it is a common practice to recover the problem VM by performing the following steps. These are the steps that are performed by the script.
	-Stops the problem VM
	-Take a snapshot of the OS Disk
	-Create a Temporary Rescue VM
	-Attach the OS Disk to the Rescue VM
    -Starts the Rescue VM
	-RDPs to RescueVM (For Windows)

.PARAMETER VmName
    This is a mandatory Parameter, Name of the VM that needs to be recovered.

.PARAMETER ResourceGroup
    This is a mandatory Parameter, Name of the ResourceGroup the VM belongs to.

.PARAMETER SubID
    This is a mandatory Parameter, SubscriptionID - the VM belongs to.

.PARAMETER prefix
    Optional Parameter. By default the new Rescue VM and its resources are all created under a ResourceGroup named same as the orginal resourceGroup name with a prefix of 'rescue', however the prefix can be changed to a different value to overide the default 'resuce'

.PARAMETER Sku
    Optional Parameter. Allows to pass in the SKU of the preferred image of the OS for the Rescue VM

.PARAMETER Offer
    Optional Parameter. Allows to pass in the Offer of the preferred image of the OS for the Rescue VM

.PARAMETER Publisher
    Optional Parameter. Allows to pass in the Publisher of the preferred image of the OS for the Rescue VM

.PARAMETER Version
    Optional Parameter. Allows to pass in the Version of the preferred image of the OS for the Rescue VM

.EXAMPLE
    .\CreateCRPRescueVM.ps1 -ResourceGroup sujtemp -VmName sujnortheurope -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c ## <==Is an example is with all the mandatory fields
.EXAMPLE
    .\CreateCRPRescueVM.ps1 -VmName ubuntu -ResourceGroup rescueportalLin -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c -Publisher RedHat -Offer RHEL -Sku 7.3 -Version 7.3.2017090723 -prefix rescuered <==Examples with optional parametersm in this example it will create the rescue VM with RedHat installed

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

        [Parameter(mandatory=$true)]
        [String]$SubID,

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
        [String]$Version
     )

#windows
#Sample Execution (Unmanaged)          ==> .\CreateCRPRescueVM.ps1 -ResourceGroup sujtemp -VmName sujnortheurope -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c
#Sample execution (managed) Windows VM ==> .\CreateCRPRescueVM.ps1 -VmName SujasManagedVM -ResourceGroup rescueMgSujasRG -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c --Current Version NOT SUPPORTED
#                                      ==> .\CreateCRPRescueVM.ps1 -ResourceGroup rescueMgScriptSujas -VmName SujasWinManagedVM -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c

#Linux
#Linux VM                             ==> .\CreateCRPRescueVM.ps1 -VmName myLinuxVM -ResourceGroup sujwithavsetwe -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c  --Current Version NOT SUPPORTED
#                                     ==> .\CreateCRPRescueVM.ps1 -ResourceGroup rescueportalLin -VmName ubuntu -SubID d7eaa135-abdf-4aaf-8868-2002dfeea60c
#/subscriptions/d7eaa135-abdf-4aaf-8868-2002dfeea60c/resourceGroups/rescueportalLin/providers/Microsoft.Compute/virtualMachines/ubuntu
$Error.Clear()
cls
if (-not $showErrors) {
    $ErrorActionPreference = 'SilentlyContinue'
}

$script:scriptStartTime = (Get-Date).ToUniversalTime()
$LogFile = $env:TEMP + "\" + $VmName + "_" + ( Get-Date $script:scriptStartTime -f yyyyMMddHHmmss ) + ".log"  
# Get running path
$RunPath = split-path -parent $MyInvocation.MyCommand.Source
cd $RunPath
$CommonFunctions = $runPath+"\Common-Functions.psm1"

#Import-Module Common-Functions -ArgumentList $LogFile -ErrorAction Stop 
if (Get-Module Common-Functions) {remove-module -name Common-Functions}   
Import-Module -Name $CommonFunctions  -ArgumentList $LogFile -ErrorAction Stop 
write-log "Info: Log is being written to ==> $LogFile" 



if (-not (Get-AzureRmContext).Account)
{
    Login-AzureRmAccount
}

#Set the context to the correct subid
Write-Log "Setting the context to SubID $SubID" -color Yellow
$subContext= Set-AzureRmContext -Subscription $SubID
write-log $subContext -logOnly
if ($subContext -eq $null) 
{
    Write-Log "Unable to set the Context for the given subId ==> $SubID, Please make sure you first  run the command ==> Login-AzureRMAccount" -Color Red
    return
}


#Step 1 Get the VM Object
Write-Log "Running Get-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -Name `"$VmName`"" -Color Yellow
$vm = Get-AzureRmVM -ResourceGroupName $ResourceGroup -Name $VmName 
write-log "`"$vm`" => $($vm)" -logOnly

if (-not (SupportedVM -vm $vm)) { return }
Write-Log "Successfully got the VM Object info for $($vm.Name)" -Color Green
if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") 
{
    write-log "Detected 'Windows' as the OSType for $Vmname"      
    $windowsVM= $true
}
else 
{   
    write-log "Detected 'Linux' as the OSType for $Vmname" 
    $windowsVM= $false
}

#Step 2 Stop VM
$stopped = StopTargetVM -ResourceGroup $ResourceGroup -VmName $VmName
write-log "`"$stopped`" ==> $($stopped)" -logOnly
if (-not $stopped) 
{
    Write-Log "Unable to stop the VM" -Color Red
    Return
}


#Step 3 SnapshotAndCopyOSDisk  
$osDiskVHDToBeRepaired = SnapshotAndCopyOSDisk -vm $vm -prefix $prefix
write-log "`"$osDiskVHDToBeRepaired`" => $($osDiskVHDToBeRepaired)" -logOnly
if (-not $osDiskVHDToBeRepaired)
{
    Write-Log "Unable to snapshot and copy the OS Disk to be repaired, cannot proceed" -Color Red
    Return
}

#Step 4 Create Rescue VM
$Vmname = $vm.Name
$rescueVMNname = "$prefix$Vmname"
$RescueResourceGroup = "$prefix$ResourceGroup"
$rescueVm = CreateRescueVM -vm $vm -ResourceGroup $ResourceGroup  -rescueVMNname $rescueVMNname -RescueResourceGroup $RescueResourceGroup -prefix $prefix -Sku $sku -Offer $offer -Publisher $Publisher -Version $Version 
Write-Log "$reccueVM ==> $($reccueVM)" -logOnly
if (-not $rescuevm)
{
    Write-Log "Unable to create the Rescue VM, cannot proceed" -Color Red
    Return
}


#Step 5 #Get a reference to the rescue VM Object
Write-Log "Running Get-AzureRmVM -ResourceGroupName `"$RescueResourceGroup`" -Name `"rescueVMNname`"" -Color Yellow
$rescuevm = Get-AzureRmVM -ResourceGroupName $RescueResourceGroup -Name $rescueVMNname
if (-not $rescuevm)
{
    Write-Log "RescueVM ==>  $rescueVMNname cannot be found, Cannot proceed" -Color Red
    return
}

#Step 6  Attach the OS Disk as data disk to the rescue VM
#$attached = AttachOsDisktoRescueVM -rescueVMNname $rescueVMNname -RescueResourceGroup $RescueResourceGroup -osDiskVHDToBeRepaired $osDiskToBeRepaired
#creates a dataDisk off of the copied snapshot of the OSDisk
if ($vm.StorageProfile.OsDisk.ManagedDisk)
{
    $storageType= "PremiumLRS"
    $snapshot = Get-AzureRmSnapshot -ResourceGroupName $resourceGroup -SnapshotName $osDiskVHDToBeRepaired
    $diskConfig = New-AzureRmDiskConfig -AccountType $storageType -Location $snapshot[$snapshot.Count - 1].Location -SourceResourceId $snapshot[$snapshot.Count - 1].Id -CreateOption Copy
    $disk = New-AzureRmDisk -Disk $diskConfig -ResourceGroupName $resourceGroup -DiskName $osDiskVHDToBeRepaired
    $VHDNameShort = $osDiskVHDToBeRepaired
    $managedDiskID = $disk.Id
}
else
{
    $VHDNameShort = ($osDiskVHDToBeRepaired.Split('/')[-1]).split('.')[0] 
    $osDiskSize = $vm.StorageProfile.OsDisk.DiskSizeGB
    if (-not $osDiskSize)
    {
       $osDiskSize= 127    
       Write-Log "Unable to retrieve the OSDiskSze for VM $VMname, so instead using 127 when attaching it to the datadisk" -color Yellow
    }
}
$attached = AttachOsDisktoRescueVM -rescueVMNname $rescueVMNname -RescueResourceGroup $RescueResourceGroup -osDiskVHDToBeRepaired $osDiskVHDToBeRepaired -VHDNameShort $VHDNameShort -osDiskSize $osDiskSize -managedDiskID $managedDiskID

write-log "`"$attached`" ==> $($attached)" -logonly
if (-not $attached)
{
    Write-Log "Unable to attach the disk ==> $osDiskToBeRepaired as data disk to Rescue VM==> $rescueVMNname,  cannot proceed" -Color Red
    Return
}

#Step 7 Start the VM
Write-Log "Starting the Rescue VM ==> $rescueVm.Name" -Color Yellow
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
write-log "Data Disk Name that was attached to RescueVM  ==> $VHDNameShort"
write-log "Fixed OS Disk's ResourceUri                   ==> $osDiskVHDToBeRepaired"

Write-Log "================================================================"
Write-Log "================================================================"
write-log "Next Steps"
Write-Log "================================================================"
Write-Log "================================================================"
write-log "RDP into the rescue VM ==> $($rescueVm.Name) "
write-log "Fix the OS Disk -Consider running the script https://github.com/sebdau/azpstools/blob/master/FixDisk/TS_RecoveryWorker2.ps1 as an elevated administrator from the rescue VM ==> $($rescueVm.Name) and in addition to that it may need additional manual steps to be performed (More instructions to come from Microsoft Support) "
write-log "After fixing the OS Disk run the RecoverVM script to Recover the VM as follows:"
write-log ".\RecoverCRPVM.ps1 -ResourceGroup `"$ResourceGroup`" -VmName `"$VmName`" -SubID `"$SubID`" -FixedOsDiskUri `"$osDiskVHDToBeRepaired`" -prefix `"$prefix`""

<###### End of script tasks ######>
$script:scriptEndTime = (Get-Date).ToUniversalTime()
$script:scriptDuration = New-Timespan -Start $script:scriptStartTime -End $script:scriptEndTime
Write-Log ('Script Duration: ' +  ('{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f $script:scriptDuration)) -color Cyan

Invoke-Item $LogFile


