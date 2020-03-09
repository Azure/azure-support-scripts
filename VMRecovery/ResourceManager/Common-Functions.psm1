﻿param(
    [parameter(Position=0,Mandatory=$true)]
    [string] $logFile
)

function Get-ValidLength (
    [string] $InputString,
    [int] $Maxlength
)
{
    if (-not $InputString)
    {
        return $null
    }
    if ($InputString.Length -gt $Maxlength)
    {
        return $InputString.Substring(0,$Maxlength)
    } 
    else
    {
        return $InputString
    }
}

function Get-ScriptResultObject
(
    [bool]$scriptSucceeded,
    [string]$restoreScriptCommand,
    [string]$rescueScriptCommand,
    [string]$cleanupScript,
    [string]$restoreOriginalStateScript,
    [string]$FailureReason,
    [string]$scriptVersion,
    [string]$RunId
)
{
    $scriptResult = [ordered]@{
        'result' = $scriptSucceeded # set to $true for success, else populate with the terminal error
        'restoreScriptCommand' = $restoreScriptCommand # set this to the command they should run the restore the problem VM
        'rescueScriptCommand' = $rescueScriptCommand # since it may be useful to also have the exact syntax that was used for New-AzRescueVM.ps1
        'failureReason' = $FailureReason #If the script fails, this will contain the reason for failure
        'cleanupScript' = $cleanupScript
        'restoreOriginalStateScript' = $restoreOriginalStateScript
    }
    $scriptResult = New-Object -TypeName PSObject -Property $scriptResult
    If ($FailureReason)
    {
        $EventName = "Error"
        LogToAppInsight -EventName $EventName -scriptname $MyInvocation.CommandOrigin  -Command $MyInvocation.InvocationName -Message $FailureReason -Scriptversion $scriptVersion -RunID $RunId
    }
    
    return $scriptResult
}

function DeleteSnapShotAndVhd
(
    [string] $osDiskVhdUri,
    [string] $resourceGroupName
)
{
    try
    {
        $osDiskvhd = $osDiskVhdUri.split('/')[-1]
        $storageAccountName = $osDiskVhdUri.Split('//')[2].Split('.')[0]
        $ContainerName = $osDiskVhdUri.Split('/')[3]
        $StorageAccountKey = (Get-AzStorageAccountKey -StorageAccountName $storageAccountName -resourceGroupName $resourceGroupName)[1].Value
        $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey -ErrorAction Stop
        $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where-Object {$_.ICloudBlob.IsSnapshot -and $null -ne $_.SnapshotTime -and $_.Name -eq $osDiskvhd} -ErrorAction Stop
        # Delete snapshot
        if ($VMsnaps.Count -gt 0)
        {
            write-log "`nDo you want to delete snapshot $($VMsnaps[$VMsnaps.Count - 1].Name) taken at $($VMsnaps[$VMsnaps.Count - 1].SnapshotTime) (Y/N)?"
            if ((read-host) -eq 'Y')
            {
                write-host "[Running] Deleting snapshot $($VMsnaps[$VMsnaps.Count - 1].Name)"
                $VMsnaps[$VMsnaps.Count - 1].ICloudBlob.Delete()
                write-host "[Success] Deleted snapshot $($VMsnaps[$VMsnaps.Count - 1].Name)" -ForegroundColor green
            }
        }

    }
    catch
    {
        write-log "Exception Message: $($_.Exception.Message)" -color red
        write-log "Error in Line Number: $($_.Exception.Line) => $($MyInvocation.MyCommand.Name)" -color red
        return $false
    }
}

function GetStorageConnection
(
    [string] $storageAccountName
)
{
    write-log "[Running] Getting the storage connection info for Storage $($storageAccountName)"
    try
    {    
        $StorageAccountRg = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName} | Select-Object -ExpandProperty ResourceGroupName
        if (-not $StorageAccountRg)
        {
            write-log "[Error] Unable to determine resource group for storage account $storageAccountName" -color red
            return $null
        } 
        $StorageAccountKey = (Get-AzStorageAccountKey -Name $storageAccountName -ResourceGroupName $StorageAccountRg).Value[1] 
        $ContainerName = $osDiskVhdUri.Split('/')[3]

        # Connect to storage account
        $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey 
        write-log "[Success] Gathered the connection info for Storage $($storageAccountName)" -color green
        Return $ctx
    }
    catch
    {
        $message = "[Error] Unable to detremine the storage connection"
        write-log $message -Color Red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)" -logOnly
        return $null
    }      
}



function CopyBlob
(
    [string]$CopyType,
    [string]$sourceBlobUri,
    [string]$ContainerName,
    [string]$toBeFixedosDiskVhd,
    [object]$CloudBlob,
    [string]$StorageAccountRg,
    [object]$Ctx

)
{ 
    Try
    {
        if ($CopyType -eq 'OsDisk')
        {
            write-log "[Running] Making a copy of the OS Disk $osDiskvhd" 
            $status = Start-AzureStorageBlobCopy -srcUri $sourceBlobUri -SrcContext $ctx -DestContainer $ContainerName -DestBlob $toBeFixedosDiskVhd -ConcurrentTaskCount 10 -Force
            write-log "[Success] Copied current OSDisk $osDiskvhd as $toBeFixedosDiskVhd" -color green
        }
        else
        {
            write-log "[Running] Copying snapshot" 
            $status = Start-AzureStorageBlobCopy -CloudBlob $CloudBlob -Context $Ctx -DestContext $Ctx -DestContainer $ContainerName -DestBlob $toBeFixedosDiskVhd -ConcurrentTaskCount 10 -Force
            write-log "[Success] Copied snapshot to $copiedOSDiskUri" -color green
    
        }
        $osFixDiskblob = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $StorageAccountRg | 
        Get-AzureStorageContainer | Where-Object {$_.Name -eq $ContainerName} | Get-AzureStorageBlob | Where-Object {$_.Name -eq $toBeFixedosDiskVhd -and $_.ICloudBlob.IsSnapshot -ne $true}
        $copiedOSDiskUri =$osFixDiskblob.ICloudBlob.Uri.AbsoluteUri
        write-Log "[Information] Disk copied URI: $copiedOSDiskUri" 
        return $copiedOSDiskUri
    }
    Catch
    {
        $message = "[Error] CopyBlob : Failed"
        write-log $message -Color Red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)" -logOnly
        return $null
    }

}

function CreateSnapshot
(
    [string]$ContainerName,
    [string]$osDiskvhd,
    [string]$vmName,
    [object]$Ctx
)
{
    $VMblob = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where-Object {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -ne $true}
        
    if (-not $VMblob)
    {
        write-log "[Error] Unable to find OS disk VHD blob for $osDiskvhd" -color red
        return 
    }

    # Create snapshot of the problem VM's OS disk
    write-log "[Running] Creating snapshot of OS disk for problem VM $($vmName)"
    try
    {
        $snap = $VMblob.ICloudBlob.CreateSnapshot()
        if ($snap)
        {
            write-log "[Success] Created snapshot of OS disk for problem VM $($vmName)" -color green
        }
        return $snap
    }
    catch
    {
       $message = "[Error] Snapshot creation or copy failed"
        write-log $message -Color Red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)" -logOnly
        return 
    }
}


function SnapshotAndCopyOSDisk 
(
    [Object[]]$vm,
    [string] $resourceGroupName,
    [string] $prefix
)
{
    write-log "[Running] Getting OS disk VHD URI for problem VM $($vm.Name)"
    $osDiskVhdUri = $vm.StorageProfile.OsDisk.Vhd.Uri
    if (-not $osDiskVhdUri)
    {
        write-log "[Error] Unable to determine OS disk VHD URI for problem VM $($vm.Name)" -color red
        return
    } 
    else
    {
        write-log "[Success] Problem VM $($vm.Name) OS disk VHD URI: $osDiskVhdUri" -color green
    }

    $osDiskvhd = $osDiskVhdUri.split('/')[-1]
    $storageAccountName = $vm.StorageProfile.OsDisk.Vhd.Uri.Split('/')[2].Split('.')[0]
    $toBeFixedosDiskVhd = $prefix + "fixedos" +  $osDiskvhd
    $ContainerName = $osDiskVhdUri.Split('/')[3]
    $ctx = GetStorageConnection -storageAccountName $storageAccountName
    if (-not $ctx) {return }    
    $StorageAccountRg = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName} | Select-Object -ExpandProperty ResourceGroupName    
    if (-not $StorageAccountRg)
    {
        write-log "[Error] Unable to determine the resource group of the storage account $($storageAccountName)" -color red
        return 
    }
    try
    {
        $snap = CreateSnapshot -ContainerName $ContainerName -osDiskvhd $osDiskvhd -vmName $vm.Name -Ctx $ctx
        if (-not $snap)
        {
            write-log "[Information] Unable to create snapshot of OS disk for problem VM $($vm.Name). It will instead make a copy of the current OS Disk: $osDiskvhd" -color cyan
            $copiedOSDiskUri = CopyBlob -CopyType 'OsDisk' -sourceBlobUri $osDiskVhdUri -ContainerName $ContainerName -toBeFixedosDiskVhd $toBeFixedosDiskVhd -StorageAccountRg $StorageAccountRg -Ctx $ctx
            return $copiedOSDiskUri
        }
        else
        {
            # Save array of all snapshots
            $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Sort-Object @{expression="SnapshotTime";Descending=$true} | Where-Object {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -and $null -ne $_.SnapshotTime} 
            if ($VMsnaps.Count -gt 0)
            {
                $copiedOSDiskUri = CopyBlob -CopyType 'PageBlob' -CloudBlob $VMsnaps[0].ICloudBlob -ContainerName $ContainerName -toBeFixedosDiskVhd $toBeFixedosDiskVhd -StorageAccountRg $StorageAccountRg -Ctx $ctx
                return $copiedOSDiskUri
            }
            else
            {
                write-log "[Error] Snapshot copy failed." -color red
            }
        }

    }
    catch
    {
        $message = "[Error] Snapshot creation or copy failed"
        write-log $message -Color Red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)" -logOnly
        return $null
    }
    return $copiedOSDiskUri
}

function RanfromCloudshell()
{
    if ($env:ACC_CLOUD)
    {
        Return $true
    }
    else
    {
        Return $false
    }
}

function CreateRemoveRescueRgScript(
    [string]$rescueResourceGroupName,
    [string]$removeRescueRgScript,
    [string]$subscriptionId,
    [switch]$scriptonly,
    [switch]$commandOnly             
)
{
    $step0="# Step 0: Logs-in to Azure" 
    $loginCmd = "Connect-AzAccount"
    $step1 ="# Step 1: Setting the context to SubscriptionID :$subscriptionId " 
    $setSubIdCmd = "`$authContext = Set-AzContext -Subscription $subscriptionId"
    $step2="# Step 1: Removing the rescue resource Group $rescueResourceGroupName" 
    $removeRescueRgCmd = "`$result = Remove-AzResourceGroup -Name $rescueResourceGroupName"

    if (-not $scriptonly) 
    {
         
        write-log "$removeRescueRgCmd" -noTimeStamp
    }
    try
    {
        if (-not $commandOnly)
        {
            ("############################################################################" | Out-String).Trim() | out-file $removeRescueRgScript -Force 
            ("# List of steps to remove the rescue resource group $rescueResourceGroupName" | Out-String).Trim() | out-file $removeRescueRgScript -Append
            ("############################################################################" | Out-String).Trim() | out-file $removeRescueRgScript -Append
            ("$step0" | Out-String).Trim() | out-file $removeRescueRgScript -Append 
            ("$loginCmd" | Out-String).Trim() | out-file $removeRescueRgScript -Append
            ("$step1" | Out-String).Trim() | out-file $removeRescueRgScript -Append 
            ("$setSubIdCmd" | Out-String).Trim() | out-file $removeRescueRgScript -Append 
            ("$step2" | Out-String).Trim() | out-file $removeRescueRgScript -Append 
            ("$removeRescueRgCmd" | Out-String).Trim() | out-file $removeRescueRgScript -Append 
        }
    }
    catch
    {
        $message = "[Error] creating the $removeRescueRgScript"
        write-log $message -color red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)"
        return 
    }
    return 
}

function CreateRestoreOriginalStateScript (
    [string]$resourceGroupName,
    [string]$vmName,
    [string]$problemvmOriginalOsDiskUri,
    [string]$OriginalProblemOSManagedDiskID,
    [string]$subscriptionId,
    [string]$OriginalDiskname,
    [bool]$managedVM,
    [string]$restoreOriginalStateScript,
    [switch]$scriptonly
)
{    
    $stepSetUplogin="# SetUp : Logs-in to Azure"
    $loginCmd = "Connect-AzAccount"
    $stepSetup ="# SetUp : Setting the context to SubscriptionID :$subscriptionId " 
    $SubIdCmd = "`$authContext = Set-AzContext -Subscription $subscriptionId"
    $step1="# Step 1: Getting the problem vm $vmName object"
    $problemVMCmd = "`$problemvm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName"
    $step2="# Step 2: Stopping the problem vm $vmName"
    $stopAzVMCmd = "Stop-AzVM -ResourceGroupName $resourceGroupName -Name $vmName"
    $step3="# Step 3: Performing a disk swap, swapping the OS Disk to its original OS Disk to put the VM $vmName back to its original state."
    if (-not $managedVM){ $vhdUriCmd = "`$problemvm.StorageProfile.OsDisk.Vhd.Uri = `"$problemvmOriginalOsDiskUri`""}
    else
    {$setAzOsDiskCmd = "Set-AzVMOSDisk -vm `$problemvm -Name `"$OriginalDiskname`" -ManagedDiskId `"$OriginalProblemOSManagedDiskID`" "}
    $step4="# Step 4: Completing the OSDisk swap operation by running Update-AzVM "
    $updateAzCMCmd = "Update-AzVM -ResourceGroupName $resourceGroupName -VM `$problemvm"
    $step5="# Step 5: Starting the problem vm $vmName "
    $startAzVmCmd ="Start-AzVM -ResourceGroupName $resourceGroupName -Name $vmName"

    if (-not $scriptonly)
    {
        write-log "`nYou can use the following commands to revert problem VM $vmName to its original state by swaping the original OS Disk:`n" -noTimeStamp
        write-log "$step1" -noTimeStamp    
        write-log "$problemVMCmd`n" -noTimeStamp    
        write-log "$step2" -noTimeStamp    
        write-log "$stopAzVMCmd`n" -noTimeStamp
        write-log "$step3" -noTimeStamp    
        if (-not $managedVM){write-log "$vhdUriCmd`n" -noTimeStamp}
        else{write-log "$setAzOsDiskCmd`n" -noTimeStamp}       
        write-log "$step4" -noTimeStamp    
        write-log "$updateAzCMCmd`n" -noTimeStamp    
        write-log "$step5" -noTimeStamp    
        write-log "$startAzVmCmd`n" -noTimeStamp
    }
    Try
    {
        ("##################################################################################################################" | Out-String).Trim() | out-file $restoreOriginalStateScript -Force 
        ("# List of steps and cmdlets that can be used to do a OS disk Swap to put the problem VM back to its original state" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("##################################################################################################################" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$stepSetUplogin" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$loginCmd" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$stepSetup" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$SubIdCmd" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$step1" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$problemVMCmd" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$step2" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$stopAzVMCmd" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$step3" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        if (-not $managedVM)
        {
            ("$vhdUriCmd" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        }
        else
        {
            ("$setAzOsDiskCmd" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        }
        ("$step4" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$updateAzCMCmd" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$step5" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append
        ("$startAzVmCmd" | Out-String).Trim() | out-file $restoreOriginalStateScript -Append

    }
    catch
    {
        $message = "[Error] creating the $restoreOriginalStateScript"
        write-log $message -color red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)"
        return 
    }
    return 
}

function SupportedVM(
    [Object[]]$vm,
    [bool] $AllowManagedVM
)
{
    if (-not $vm)
    {
        write-log "[Error] Unable to find VM. Verify the problem VM name and resource group name." -color red
        return $false
    }
     
    if (($vm.StorageProfile.OsDisk.ManagedDisk) -and (-not $AllowManagedVM)) 
    {
        write-log "VM $($vm.Name) is a managed disk VM, and is currently not supported by this script." -color red
        return $false
    }

    # For VMs created from a marketplace image with Plan information, verify the exact image version is still published, else the disk swap will fail.
    try
    {
        if ($vm.Plan)
        {
            # Indicates VM has a Plan
            if($vm.Plan.Publisher)
            {
                $ImageObj = (Get-AzVMimage -Location $vm.Location -PublisherName $vm.StorageProfile.ImageReference.Publisher -Offer $vm.StorageProfile.ImageReference.Offer -Skus $vm.StorageProfile.ImageReference.sku)[-1]
                if (-not $ImageObj)
                {
                    write-log "[Error] This problem VM was created from a marketplace image with Plan information, but the marketplace image is no longer published, so if this VM were removed, it would not be possible to recreate it from the existing disk." -color red
                    return $false
                }
            }
        }
    }
    catch
    {
        $message = "[Error] SupportedVM check Failed."
        write-log $message -color red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)"
        return $false
    }

    return $true
}

function CreateRescueVM(
    [Object[]]$vm,
    [Parameter(mandatory=$true)]
    [String]$resourceGroupName,
    [Parameter(mandatory=$true)]
    [String]$rescueVMName,
    [Parameter(mandatory=$true)]
    [String]$rescueResourceGroupName,
    [String]$prefix = "rescue",
    [Parameter(mandatory=$false)]
    [String]$Sku,
    [Parameter(mandatory=$false)]
    [String]$Offer,
    [Parameter(mandatory=$false)]
    [String]$Publisher,
    [Parameter(mandatory=$false)]
    [String]$Version,
    [Parameter(mandatory=$false)]
    [System.Management.Automation.PSCredential]$Credential
)
{
    try
    {
        write-log "[Running] Initiating the process to create the rescue VM" -logOnly
        
        if ($vm.StorageProfile.OsDisk.ManagedDisk) {$managedVM = $true} else {$managedVM = $false}

        $osDiskName  = $vm.StorageProfile.OsDisk.Name
        $vmSize = $vm.HardwareProfile.VmSize
        $osType = $vm.StorageProfile.OsDisk.OsType
        $location = $vm.Location
        $networkInterfaceName = $vm.NetworkProfile.NetworkInterfaces[0].Id.split('/')[-1]
        $MaxStorageAccountNameLength = 24
        if ([string]::IsNullOrWhitespace($osDiskName))
        {
            write-log "[Error] Unable to determine OS disk name for problem VM $($vm.name)" -color red
            return 
        }
        if ([string]::IsNullOrWhitespace($vmSize))
        {
            write-log "[Error] Unable to determine problem VM size for VM $($vm.name)" -color red
            return
        }
        if ([string]::IsNullOrWhitespace($osType))
        {
            write-log "[Error] Unable to determine OS type for problem VM $($vm.name)" -color red
            return
        }
        if ([string]::IsNullOrWhitespace($location))
        {
            write-log "[Error] Unable to determine location of problem VM $($vm.name)" -color red
            return
        }
        if ([string]::IsNullOrWhitespace($networkInterfaceName))
        {
            write-log "[Error] Unable to determine network interface name for problem VM $($vm.name)" -color red
            return
        }
        $rescueOSDiskName = "$prefix$osDiskName"
        if (-not $managedVM)
        {
            $osDiskVhdUri = $vm.StorageProfile.OsDisk.Vhd.Uri
            $storageAccountName = $vm.StorageProfile.OsDisk.Vhd.Uri.Split('/')[2].Split('.')[0]
            $rescueosDiskVhduri = $osDiskVhdUri.Replace($osDiskName,$rescueOSDiskName)
        }

        $rescueVM = New-AzVMConfig -VMName $rescueVMName -VMSize $vmSize -WarningAction SilentlyContinue
        $rescuenetworkInterfaceName = "$prefix$networkInterfaceName"
        $nic1 = Get-AzNetworkInterface -resourceGroupName $resourceGroupName | Where-Object {$_.Name -eq $networkInterfaceName}
        $nic1Id = $nic1.Id
        $rescuenic1Id = $nic1Id.Replace($networkInterfaceName,$rescuenetworkInterfaceName)
        $rescueVM = Add-AzVMNetworkInterface -VM $rescueVM -Id $rescuenic1Id -WarningAction SilentlyContinue
        $rescueVM.NetworkProfile.NetworkInterfaces[0].Primary = $true
        $rescueStorageType = 'Standard_GRS'
        $rescueStorageName = "$prefix$storageAccountName"
        $rescueStorageName = $rescueStorageName.ToLower()
        $rescueStorageName = Get-ValidLength -InputString $rescueStorageName -Maxlength $MaxStorageAccountNameLength

        # Network
        $rescueInterfaceName = $prefix + "interface"
        $rescueSubnet1Name = $prefix + "Subnet"
        $rescueVNetName = $prefix + "VNet"
        $rescueVNetAddressPrefix = "10.0.0.0/16"
        $rescueVNetSubnetAddressPrefix = "10.0.0.0/24"   

        # Compute
        $rescueComputerName = $prefix + "vm"
        $rescueVMSize = $vmSize #"Standard_A2"
        $rescueOSDiskName = $rescueVMName + "OSDisk"

        # Resource Group
        # Checks if resource group already exists
        $rg = Get-AzResourceGroup -Name $rescueResourceGroupName -Location $location -ErrorAction SilentlyContinue
        if ($rg)
        {
            write-log "`n[Error] Resource group $rescueResourceGroupName already exists." -color red
            return $null
        }
        else
        {
            write-log "[Running] Creating resource group $rescueResourceGroupName for rescue VM $rescueVMName"
            $createrg = New-AzResourceGroup -Name $rescueResourceGroupName -Location $location -ErrorAction Stop
            write-log "[Success] Created resource group $rescueResourceGroupName for rescue VM $rescueVMName" -color green
        }

        # Create storage account if it's a managed disk VM
        if (-not $managedVM)
        {
            write-log "[Running] Creating storage account $rescueStorageName for rescue VM $rescueVMName"
            $rescueStorageAccount = New-AzStorageAccount -ResourceGroupName $rescueResourceGroupName -Name $rescueStorageName -Type $rescueStorageType -Location $location -ErrorAction Stop
            write-log "[Success] Created storage account $rescueStorageName for rescue VM $rescueVMName" -color green
        }

        # Network
        write-log "[Running] Creating publicIpAddress for interfacename $rescueInterfaceName for rescue VM $rescueVMName"
        $rescuePip = New-AzPublicIpAddress -Name $rescueInterfaceName -ResourceGroupName $rescueResourceGroupName -Location $location -AllocationMethod Dynamic -WarningAction SilentlyContinue -ErrorAction Stop
        write-log "[Success] Created publicIpAddress for interfacename $rescueInterfaceName for rescue VM $rescueVMName"

        write-log "[Running] Creating subnet config for subnet $rescueSubnet1Name"
        $rescueSubnetConfig = New-AzVirtualNetworkSubnetConfig -Name $rescueSubnet1Name -AddressPrefix $rescueVNetSubnetAddressPrefix -ErrorAction Stop
        write-log "[Success] Created subnet config for subnet $rescueSubnet1Name" -color green

        write-log "[Running] Creating virtual network $rescueVNetName"
        $rescueVNet = New-AzVirtualNetwork -Name $rescueVNetName -ResourceGroupName $rescueResourceGroupName -Location $location -AddressPrefix $rescueVNetAddressPrefix -Subnet $rescueSubnetConfig -WarningAction SilentlyContinue -ErrorAction Stop
        write-log "[Success] Created virtual network $rescueVNetName" -color green

        write-log "[Running] Creating network interface $rescueInterfaceName"
        $rescueInterface = New-AzNetworkInterface -Name $rescueInterfaceName -ResourceGroupName $rescueResourceGroupName -Location $location -SubnetId $rescueVNet.Subnets[0].Id -PublicIpAddressId $rescuePIp.Id -WarningAction SilentlyContinue -ErrorAction Stop
        write-log "[Success] Created network interface $rescueInterfaceName" -color green
    
        ## Setup local VM object
        if (-not $Credential)
        {
            write-log "Enter user name and password for the rescue VM $rescueVMName that will be created." -color cyan
            $Credential = get-credential -Message "Enter username and password for the rescue VM $rescueVMName that will be created."
            if ($Credential)
            {
                write-log "[Success] Received username and password from credential prompt" -color green        
            }       

        }
   
        $rescueVM = New-AzVMConfig -VMName $rescueVMName -VMSize $rescueVMSize -WarningAction SilentlyContinue -ErrorAction Stop
        if ($osType -eq 'Windows')
        {
            $rescueVM = Set-AzVMOperatingSystem -VM $rescueVM -Windows -ComputerName $rescueComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate -WarningAction SilentlyContinue -ErrorAction Stop
            # Use Windows Server 2016 with GUI as some may prefer a GUI for troubleshooting/mitigating the problem VM's OS disk
            # If desired, a different image can be used for the rescue VM by specifying -publisher/-offer/-sku as script parameters.
            $ImageObj = (Get-AzVMimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter')[-1]
        }
        else
        {
            $rescueVM = Set-AzVMOperatingSystem -VM $rescueVM -Linux -ComputerName $rescueComputerName -Credential $Credential -WarningAction SilentlyContinue -ErrorAction Stop
            # Use Ubuntu 16.04-LTS as it is a commonly used distro in Azure.
            # If desired, a different image can be used for the rescue VM by specifying -publisher/-offer/-sku as script parameters.
            $ImageObj = (Get-AzVMimage -Location $location -PublisherName 'Canonical' -Offer 'UbuntuServer' -Skus '16.04-LTS')[-1]
        }

        if (-not $sku)
        {
            $sku = $ImageObj.Skus
        }
        if (-not $offer)
        {
            $offer  = $ImageObj.Offer
        }
        if (-not $version)
        {
            $version = $ImageObj.Version
        }
        if (-not $Publisher)
        {
            $Publisher = $ImageObj.PublisherName
        }
        $rescueVM = Set-AzVMSourceImage -VM $rescueVM -PublisherName $Publisher -Offer $offer -Skus $sku -Version $Version -WarningAction SilentlyContinue -ErrorAction Stop
        $rescueVM = Add-AzVMNetworkInterface -VM $rescueVM -Id $rescueInterface.Id -WarningAction SilentlyContinue -ErrorAction Stop

        if ($managedVM)
        {
            $rescueVM = Set-AzVMOSDisk -VM $rescueVM -Name $rescueOSDiskName -CreateOption FromImage -WarningAction SilentlyContinue -ErrorAction Stop
        }
        else
        {
            $rescueOSDiskUri = $rescueStorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $rescueOSDiskName + ".vhd"
            $rescueVM = Set-AzVMOSDisk -VM $rescueVM -Name $rescueOSDiskName -VhdUri $rescueOSDiskUri -CreateOption FromImage -WarningAction SilentlyContinue -ErrorAction Stop
        } 
        ## Create the VM in Azure
        write-log "[Running] Creating rescue VM $rescueVMName in resource group $rescueResourceGroupName"
        $created = New-AzVM -ResourceGroupName $rescueResourceGroupName -Location $location -VM $rescueVM -ErrorAction Stop -WarningAction SilentlyContinue
        write-log "[Success] Created rescue VM $rescueVMName in resource group $rescueResourceGroupName" -color green
       
        return $created
    }
    catch
    {
        $message = "[Error] CreateRescueVM Failed."
        write-log $message -color red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)"
        return $null
    }    
}

function AttachOsDisktoRescueVM
(
    [string]$rescueResourceGroupName,
    [string]$rescueVMName,
    [string]$osDiskVHDToBeRepaired,
    [string]$diskName,
    [string]$osDiskSize,
    [string]$managedDiskID
)
{
    $returnVal = $true
    #write-log "[Running] Get-AzVM -ResourceGroupName $rescueResourceGroupName -Name $rescueVMName" 
    $rescueVM = Get-AzVM -resourceGroupName $rescueResourceGroupName -Name $rescueVMName -WarningAction SilentlyContinue
    if (-not $rescueVM)
    {
        write-log "[Error] Rescue VM $rescueVMName not found" -color red
        return $false
    }
    write-log "[Running] Attaching OS disk to rescue VM $rescueVMName"
    try
    {
        if ($managedDiskID) 
        {
            Add-AzVMDataDisk -VM $rescueVM -Name $diskName -CreateOption Attach -ManagedDiskId $managedDiskID -Lun 0
        }
        else
        {
          Add-AzVMDataDisk -VM $rescueVM -Name $diskName -Caching None -CreateOption Attach -DiskSizeInGB $osDiskSize -Lun 0 -VhdUri $osDiskVHDToBeRepaired
        }
        Update-AzVM -resourceGroupName $rescueResourceGroupName -VM $rescueVM 
        write-log "[Success] Attached problem VM's OS disk as a data disk on rescue VM $rescueVMName" -color green
    }
    catch
    {
         $returnVal = $false
         write-log "[Error] Unable to attach OS disk - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
         write-log "Exception Message: $($_.Exception.Message)" -logOnly
         return $false
    }
    return $returnVal
}

function StopTargetVM
(
    [String]$resourceGroupName,
    [String]$vmName
)
{
    write-log "[Running] Stopping VM $vmName"
    $stopped = Stop-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Force
    if ($stopped)
    {
        write-log "[Success] Stopped VM $vmName" -color green
        return $true
    }
    else
    {
        if ($error)
        {    
            write-log ('='*47) -logOnly
            write-log "Errors logged during script execution`n" -noTimestamp -logOnly
            write-log ('='*47) -logOnly
            write-log "`n" -logOnly
            $error | Sort-Object -descending | ForEach-Object {write-log ('Line:' + $_.InvocationInfo.ScriptLineNumber + ' Char:' + $_.InvocationInfo.OffsetInLine + ' ' + $_.Exception.ErrorRecord) -logOnly}
        }
    }
    return $false
}

function write-log
{
    param(
        [string]$text,    
        [string]$color = 'White',
        [switch]$logOnly,
        [switch]$noTimeStamp
        )    

    $timestamp = ('[' + (get-date (get-date).ToUniversalTime() -format "yyyy-MM-dd HH:mm:ssZ") + '] ')

    if ($logOnly -eq $false)
    {
        if ($noTimeStamp)
        {
            write-host $text -foregroundColor $color
        }
        else
        {
            write-host $timestamp -NoNewline
            write-host $text -foregroundColor $color
        }
    }

    if ($noTimeStamp)
    {
        ($text | out-string).Trim() | out-file $logFile -Append
    }
    else
    {
        (($timestamp + $text) | out-string).Trim() | out-file $logFile -Append   
    }        
}

Function Build-PostData
{
    Param(
		[Parameter(Mandatory=$true)]
		[string]$EventName,
        [Parameter(Mandatory=$false)]
        [string]$Scriptname,
        [Parameter(Mandatory=$false)]
        [string]$Command,
        [Parameter(Mandatory=$false)]
        [string]$Scriptversion,
        [Parameter(Mandatory=$false)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [string]$Duration,
        [Parameter(Mandatory=$true)]
        [string]$RunId
	    )
    $InstrumentKey = "7d48ea58-f6fe-4795-844b-ea580b90be26"
    if (RanfromCloudshell){$Environment = "CloudShell"} else {$Environment = "Powershell"}
    $CustomProperties = @{
	"Script Name" = "$scriptname";
	"DeveloperMode" = "false"
    "Time" = [Datetime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss")
    "Message" = $Message
    "Command" = $Command
    "ScriptVersion" = $Scriptversion
    "Environment" = $Environment
    "Duration" = $Duration
    "RunID" = $RunId
    }

	Try {
		Return @{
			name = "Microsoft.ApplicationInsights.Dev.$InstrumentKey.Event";
			time = [Datetime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss");
			iKey = $InstrumentKey;
			data = @{
				baseType = "EventData";
				baseData = @{
					name = $eventName;
					properties = $CustomProperties;
				}
			};
		}
	} Catch {
		Throw $_
	}
}


Function LogToAppInsight
{
    Param(
		[Parameter(Mandatory=$true)]
		[string]$EventName,
        [Parameter(Mandatory=$false)]
        [string]$Scriptname,
        [Parameter(Mandatory=$false)]
        [string]$Command,
        [Parameter(Mandatory=$false)]
        [string]$Scriptversion="1.0.0",
        [Parameter(Mandatory=$false)]
        [string]$Message="None",
        [Parameter(Mandatory=$false)]
        [string]$Duration,
        [string]$RunID
	    )

    Try {
        
        $postData = Build-PostData -EventName $EventName  -Scriptname $Scriptname -Command $Command -Scriptversion $Scriptversion -Message $Message -Duration $Duration -RunId $RunID| ConvertTo-Json -Depth 5   
	    Try {
            write-log "[Running] Posting Telemetry data to AppInsights" 
		    $Response = Invoke-RestMethod -Method POST -Uri "https://dc.services.visualstudio.com/v2/track" -ContentType "application/json" -Body $postData
            write-log "[Success] Request was successfully logged to AppInsights." -color green
	    } Catch {
		    Write-log "[Error] Request fail, Failed to log Telemetry Data to AppInsights" -color Red
		    Write-log $_
	    }
    } Catch {
	    Throw $_
    }
}

Export-ModuleMember -Function write-log
Export-ModuleMember -Function SnapshotAndCopyOSDisk
Export-ModuleMember -Function CreateRescueVM
Export-ModuleMember -Function StopTargetVM
Export-ModuleMember -Function AttachOsDisktoRescueVM
Export-ModuleMember -Function SupportedVM
Export-ModuleMember -Function CreateRestoreOriginalStateScript
Export-ModuleMember -Function Get-ValidLength
Export-ModuleMember -Function DeleteSnapShotAndVhd
Export-ModuleMember -Function Get-ScriptResultObject
Export-ModuleMember -Function CreateRemoveRescueRgScript
Export-ModuleMember -Function RanfromCloudshell
Export-ModuleMember -Function LogToAppInsight