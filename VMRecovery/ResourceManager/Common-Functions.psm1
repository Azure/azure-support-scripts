param(
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
    [string]$FailureReason
)
{
    $scriptResult = [ordered]@{
        'result' = $scriptSucceeded # set to $true for success, else populate with the terminal error
        'restoreScriptCommand' = $restoreScriptCommand # set this to the command they should run the restore the problem VM
        'rescueScriptCommand' = $rescueScriptCommand # since it may be useful to also have the exact syntax that was used for New-AzureRMRescueVM.ps1
        'failureReason' = $FailureReason #If the script fails, this will contain the reason for failure
    }
    $scriptResult = New-Object -TypeName PSObject -Property $scriptResult
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
        $StorageAccountKey = (AzureRmStorageAccountKey -StorageAccountName $storageAccountName -resourceGroupName $resourceGroupName)[1].Value
        $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey -ErrorAction Stop
        $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | where-object {$_.ICloudBlob.IsSnapshot -and $_.SnapshotTime -ne $null -and $_.Name -eq $osDiskvhd} -ErrorAction Stop
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

        <##Deleting the backedupovhd
        $backupOSDiskVhd = "backup$osDiskvhd" 
        $osFixDiskblob = Get-AzureStorageAccount -StorageAccountName $storageAccountName | 
        Get-AzureStorageContainer | where {$_.Name -eq $ContainerName} | Get-AzureStorageBlob | where {$_.Name -eq $backupOSDiskVhd -and $_.ICloudBlob.IsSnapshot -ne $true} -ErrorAction Stop
        if ($osFixDiskblob)
        {
            write-log "`nWould you like to delete the backed up VHD ==> $($backupOSDiskVhd) (Y/N) ?" 
            if ((read-host) -eq 'Y')
            {
                $osFixDiskblob.ICloudBlob.Delete()
                Write-Host "backupOSDiskVhd has been deleted"
            }
        }#>
    }
    catch
    {
        write-log "Exception Message: $($_.Exception.Message)" -color red
        write-log "Error in Line Number: $($_.Exception.Line) => $($MyInvocation.MyCommand.Name)" -color red
        return $false
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
        return null
    } 
    else
    {
        write-log "[Success] Problem VM $($vm.Name) OS disk VHD URI: $osDiskVhdUri" -color green
    }

    $osDiskvhd = $osDiskVhdUri.split('/')[-1]
    $storageAccountName = $vm.StorageProfile.OsDisk.Vhd.Uri.Split('//')[2].Split('.')[0]
    #$fixedosdiskvhd = "fixedos$osDiskvhd" 
    $toBeFixedosDiskVhd = $null
    try
    {
        $StorageAccountRg = Get-AzureRmStorageAccount | where {$_.StorageAccountName -eq $storageAccountName} | Select-Object -ExpandProperty ResourceGroupName
        if (-not $StorageAccountRg)
        {
            write-log "[Error] Unable to determine resource group for storage account $storageAccountName" -color red
            return null
        } 
        $StorageAccountKey = (Get-AzureRmStorageAccountKey -Name $storageAccountName -ResourceGroupName $StorageAccountRg).Value[1] 
        $ContainerName = $osDiskVhdUri.Split('/')[3]

        # Connect to storage account
        $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey 
        $VMblob = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -ne $true}
        if (-not $VMblob)
        {
            write-log "[Error] Unable to find OS disk VHD blob for $osDiskvhd" -color red
            return null
        }

        # Create snapshot of the problem VM's OS disk
        write-log "[Running] Creating snapshot of OS disk for problem VM $($vm.Name)"
        $snap = $VMblob.ICloudBlob.CreateSnapshot()
        if ($snap)
        {
            write-log "[Success] Created snapshot of OS disk for problem VM $($vm.Name)" -color green
        }
        else
        {
            write-log "[Information] Unable to create snapshot of OS disk for problem VM $($vm.Name). Will attempt to use an existing snapshot which may be stale." -color cyan
        }

        write-log "[Running] Copying snapshot" 
        # Save array of all snapshots
        $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | sort @{expression="SnapshotTime";Descending=$true} | where-object {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -and $_.SnapshotTime -ne $null} 

        # Copy the latest snapshot of the OS Disk to the same storage account prefixing with 
        if ($VMsnaps.Count -gt 0)
        {   
            #$toBeFixedosDiskVhd = "fixedos$osDiskvhd" 
            $toBeFixedosDiskVhd = $prefix + "fixedos" +  $osDiskvhd
            $status = Start-AzureStorageBlobCopy -CloudBlob $VMsnaps[0].ICloudBlob -Context $Ctx -DestContext $Ctx -DestContainer $ContainerName -DestBlob $toBeFixedosDiskVhd -ConcurrentTaskCount 10 -Force
            #$status | Get-AzureStorageBlobCopyState            
            $osFixDiskblob = Get-AzureRMStorageAccount -Name $storageAccountName -ResourceGroupName $StorageAccountRg | 
            Get-AzureStorageContainer | where {$_.Name -eq $ContainerName} | Get-AzureStorageBlob | where {$_.Name -eq $toBeFixedosDiskVhd -and $_.ICloudBlob.IsSnapshot -ne $true}
            $copiedOSDiskUri =$osFixDiskblob.ICloudBlob.Uri.AbsoluteUri
            write-log "[Success] Copied snapshot to $copiedOSDiskUri" -color green
            return $copiedOSDiskUri
        }
        else
        {
           write-log "[Error] Snapshot copy failed." -color red
        }
    }
    catch
    {
        $message = "[Error] Snapshot creation or copy failed"
        write-log $message -Color Red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)" -logOnly
        throw  
        return $null
    }

    return $copiedOSDiskUri
}

function WriteRestoreCommands (
    [string]$resourceGroupName,
    [string]$vmName,
    [string]$problemvmOsDiskUri,
    [string]$problemvmOsDiskManagedDiskID,
    [bool]$managedVM
)
{    
    write-log "`nYou can use the following commands to revert VM $vmName to its original state, instead of using the copy of its OS disk:`n" -noTimeStamp
    write-log "`$problemvm = Get-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName" -noTimeStamp
    write-log "Stop-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName" -noTimeStamp
    if (-not $managedVM)
    {
        write-log "`$problemvm.StorageProfile.OsDisk.Vhd.Uri = $problemvmOsDiskUri" -noTimeStamp
        write-log "Update-AzureRmVM -ResourceGroupName $resourceGroupName -VM `$problemvm" -noTimeStamp
        write-log "Start-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName" -noTimeStamp
    }
    else
    {
        write-log "Set-AzureRmVMOSDisk -vm `$problemvm -ManagedDiskId $problemvmOsDiskManagedDiskID -CreateOption FromImage" -noTimeStamp
        write-log "Update-AzureRmVM -ResourceGroupName $resourceGroupName -VM `$problemvm" -noTimeStamp
        write-log "Start-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName" -noTimeStamp
    }
}

function SupportedVM(
    [Object[]]$vm,
    [bool] $AllowManagedVM
)
{
    if (-not $vm)
    {
        write-log "[Error] Unable to find VM. Verify the VM name and resource group name." -color red
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
                $ImageObj = (get-azurermvmimage -Location $vm.Location -PublisherName $vm.StorageProfile.ImageReference.Publisher -Offer $vm.StorageProfile.ImageReference.Offer -Skus $vm.StorageProfile.ImageReference.sku)[-1]
                if (-not $ImageObj)
                {
                    write-log "[Error] This VM was created from a marketplace image with Plan information, but the marketplace image is no longer published, so if this VM were removed, it would not be possible to recreate it from the existing disk." -color red
                    return $false
                }
            }
        }
    }
    catch
    {
        write-log "[Error] This VM was created from a marketplace image with Plan information, but the marketplace image is no longer published, so if this VM were removed, it would not be possible to recreate it from the existing disk." -color red
        return $false
    }

    <#if ($vm.StorageProfile.OsDisk.OsType -ne "Windows")
    {
        write-log "VM ==> $($vm.Name) is not a Windows VM, and is currently not supported by this script, cannot continue exiting." -color Red
        return $false
    } #>   
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
            write-log "[Error] Unable to determine OS disk name for VM $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($vmSize))
        {
            write-log "[Error] Unable to determine VM size for VM $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($osType))
        {
            write-log "[Error] Unable to determine OS type for VM $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($location))
        {
            write-log "[Error] Unable to determine location of VM $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($networkInterfaceName))
        {
            write-log "[Error] Unable to determine network interface name for VM $($vm.name)" -color red
            return null
        }
        $rescueOSDiskName = "$prefix$osDiskName"
        if (-not $managedVM)
        {
            $osDiskVhdUri = $vm.StorageProfile.OsDisk.Vhd.Uri
            $storageAccountName = $vm.StorageProfile.OsDisk.Vhd.Uri.Split('//')[2].Split('.')[0]
            $rescueosDiskVhduri = $osDiskVhdUri.Replace($osDiskName,$rescueOSDiskName)
        }

        $rescueVM = New-AzureRmVMConfig -VMName $rescueVMName -VMSize $vmSize -WarningAction SilentlyContinue
        $rescuenetworkInterfaceName = "$prefix$networkInterfaceName"
        $nic1 = Get-AzureRmNetworkInterface -resourceGroupName $resourceGroupName | where-object {$_.Name -eq $networkInterfaceName}
        $nic1Id = $nic1.Id
        $rescuenic1Id = $nic1Id.Replace($networkInterfaceName,$rescuenetworkInterfaceName)
        $rescueVM = Add-AzureRmVMNetworkInterface -VM $rescueVM -Id $rescuenic1Id -WarningAction SilentlyContinue
        $rescueVM.NetworkProfile.NetworkInterfaces[0].Primary = $true
        #$rescueVM = Set-AzureRmVMOSDisk -VM $rescueVM -VhdUri $rescueosDiskVhduri -name $rescueOSDiskName -CreateOption attach -Windows              
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
        $rg = Get-AzureRmResourceGroup -Name $rescueResourceGroupName -Location $location -ErrorAction SilentlyContinue
        if ($rg)
        {
            write-log "`n[Error] Resource group $rescueResourceGroupName already exists. `nIt looks like you may be rerunning the script without actually deleting the resource group that was created from the previous execution or you may already have a resource group by that same name. `nPlease either delete the resource group ==> $rescueResourceGroupName) if you no longer need it or rerun the script again by adding the parameter '-prefix' and specify a new prefix  to make a new resource group" -color red
            return $null
        }
        else
        {
            write-log "[Running] Creating resource group $rescueResourceGroupName for rescue VM $rescueVMName"
            New-AzureRmResourceGroup -Name $rescueResourceGroupName -Location $location
            write-log "[Success] Created resource group $rescueResourceGroupName for rescue VM $rescueVMName" -color green
        }

        # Create storage account if it's a managed disk VM
        if (-not $managedVM)
        {
            write-log "[Running] Creating storage account $rescueStorageName for rescue VM $rescueVMName"
            $rescueStorageAccount = New-AzureRmStorageAccount -ResourceGroupName $rescueResourceGroupName -Name $rescueStorageName -Type $rescueStorageType -Location $location
            write-log "[Success] Created storage account $rescueStorageName for rescue VM $rescueVMName" -color green
        }

        # Network
        #write-log "Allocating a new PublicIP ==> $rescueInterfaceName" 
        $rescuePip = New-AzureRmPublicIpAddress -Name $rescueInterfaceName -ResourceGroupName $rescueResourceGroupName -Location $location -AllocationMethod Dynamic -WarningAction SilentlyContinue
        #write-log "Allocated  PublicIP ==> $rescueInterfaceName" -color Green

        write-log "[Running] Creating subnet config for subnet $rescueSubnet1Name"
        $rescueSubnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name $rescueSubnet1Name -AddressPrefix $rescueVNetSubnetAddressPrefix
        write-log "[Success] Created subnet config for subnet $rescueSubnet1Name" -color green

        write-log "[Running] Creating virtual network $rescueVNetName"
        $rescueVNet = New-AzureRmVirtualNetwork -Name $rescueVNetName -ResourceGroupName $rescueResourceGroupName -Location $location -AddressPrefix $rescueVNetAddressPrefix -Subnet $rescueSubnetConfig -WarningAction SilentlyContinue
        write-log "[Success] Created virtual network $rescueVNetName" -color green

        write-log "[Running] Creating network interface $rescueInterfaceName"
        $rescueInterface = New-AzureRmNetworkInterface -Name $rescueInterfaceName -ResourceGroupName $rescueResourceGroupName -Location $location -SubnetId $rescueVNet.Subnets[0].Id -PublicIpAddressId $rescuePIp.Id -WarningAction SilentlyContinue
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
   
        $rescueVM = New-AzureRmVMConfig -VMName $rescueVMName -VMSize $rescueVMSize -WarningAction SilentlyContinue
        if ($osType -eq 'Windows')
        {
            $rescueVM = Set-AzureRmVMOperatingSystem -VM $rescueVM -Windows -ComputerName $rescueComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate -WarningAction SilentlyContinue
            # Use Windows Server 2016 with GUI as some may prefer a GUI for troubleshooting/mitigating the problem VM's OS disk
            # If desired, a different image can be used for the rescue VM by specifying -publisher/-offer/-sku as script parameters.
            $ImageObj = (get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter')[-1]
        }
        else
        {
            $rescueVM = Set-AzureRmVMOperatingSystem -VM $rescueVM -Linux -ComputerName $rescueComputerName -Credential $Credential -WarningAction SilentlyContinue
            # Use Ubuntu 16.04-LTS as it is a commonly used distro in Azure.
            # If desired, a different image can be used for the rescue VM by specifying -publisher/-offer/-sku as script parameters.
            $ImageObj = (get-azurermvmimage -Location $location -PublisherName 'Canonical' -Offer 'UbuntuServer' -Skus '16.04-LTS')[-1]
        }

        if (-not $sku)
        {
            #$sku = $vm.StorageProfile.ImageReference.sku 
            $sku = $ImageObj.Skus
        }
        if (-not $offer)
        {
            #$offer =$vm.StorageProfile.ImageReference.Offer
            $offer  = $ImageObj.Offer
        }
        if (-not $version)
        {
            #$Version = $vm.StorageProfile.ImageReference.Version
            #$Version = """$Version"""
            $version = $ImageObj.Version
        }
        if (-not $Publisher)
        {
            #$Publisher = $vm.StorageProfile.ImageReference.Publisher
            $Publisher = $ImageObj.PublisherName
        }
        $rescueVM = Set-AzureRmVMSourceImage -VM $rescueVM -PublisherName $Publisher -Offer $offer -Skus $sku -Version $Version -WarningAction SilentlyContinue
        $rescueVM = Add-AzureRmVMNetworkInterface -VM $rescueVM -Id $rescueInterface.Id -WarningAction SilentlyContinue

        #$rescueVM = Set-AzureRmVMOSDisk -VM $rescueVM -Name $rescueOSDiskName -VhdUri $rescueOSDiskUri -CreateOption FromImage
        if ($managedVM)
        {
            #$rescueVM = Set-AzureRmVMOSDisk -VM $rescueVM -ManagedDiskId $disk.Id -CreateOption FromImage
            $rescueVM = Set-AzureRmVMOSDisk -VM $rescueVM -Name $rescueOSDiskName -CreateOption FromImage -WarningAction SilentlyContinue
        }
        else
        {
            $rescueOSDiskUri = $rescueStorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $rescueOSDiskName + ".vhd"
            $rescueVM = Set-AzureRmVMOSDisk -VM $rescueVM -Name $rescueOSDiskName -VhdUri $rescueOSDiskUri -CreateOption FromImage -WarningAction SilentlyContinue
        }

        <#if ($ostype -eq "Linux")
        {
            $sshPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
            $rescueVM = Add-AzureRmVMSshPublicKey -VM $rescueVM -KeyData $sshPublicKey -Path "/home/azureuser/.ssh/authorized_keys"
        }#>

        ## Create the VM in Azure
        write-log "[Running] Creating rescue VM $rescueVMName in resource group $rescueResourceGroupName"
        $created = New-AzureRmVM -ResourceGroupName $rescueResourceGroupName -Location $location -VM $rescueVM -ErrorAction Stop -WarningAction SilentlyContinue
        write-log "[Success] Created rescue VM $rescueVMName in resource group $rescueResourceGroupName" -color green
       
        return $created
    }
    catch
    {
        $message = "[Error] Unable to create the rescue VM"
        write-log $message -color red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)"
        throw
        return null
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
    #write-log "[Running] Get-AzureRmVM -ResourceGroupName $rescueResourceGroupName -Name $rescueVMName" 
    $rescueVM = Get-AzureRmVM -resourceGroupName $rescueResourceGroupName -Name $rescueVMName -WarningAction SilentlyContinue
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
            Add-AzureRmVMDataDisk -VM $rescueVM -Name $diskName -CreateOption Attach -ManagedDiskId $managedDiskID -Lun 0
        }
        else
        {
          Add-AzureRmVMDataDisk -VM $rescueVM -Name $diskName -Caching None -CreateOption Attach -DiskSizeInGB $osDiskSize -Lun 0 -VhdUri $osDiskVHDToBeRepaired
        }
        Update-AzureRmVM -resourceGroupName $rescueResourceGroupName -VM $rescueVM 
        write-log "[Success] Attached problem VM's OS disk as a data disk on rescue VM $rescueVMName" -color green
    }
    catch
    {
         $returnVal = $false
         write-log "[Error] Unable to attach OS disk - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
         write-log "Exception Message: $($_.Exception.Message)" -logOnly
         throw
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
    $stopped = Stop-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName -Force
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
            $error | sort -descending | % {write-log ('Line:' + $_.InvocationInfo.ScriptLineNumber + ' Char:' + $_.InvocationInfo.OffsetInLine + ' ' + $_.Exception.ErrorRecord) -logOnly}
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

Export-ModuleMember -Function write-log
Export-ModuleMember -Function SnapshotAndCopyOSDisk
Export-ModuleMember -Function CreateRescueVM
Export-ModuleMember -Function StopTargetVM
Export-ModuleMember -Function AttachOsDisktoRescueVM
Export-ModuleMember -Function SupportedVM
Export-ModuleMember -Function WriteRestoreCommands
Export-ModuleMember -Function Get-ValidLength
Export-ModuleMember -Function DeleteSnapShotAndVhd
Export-ModuleMember -Function Get-ScriptResultObject