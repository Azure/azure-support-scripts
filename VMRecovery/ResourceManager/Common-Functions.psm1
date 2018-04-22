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
        #Deleting the snapshot
        if ($VMsnaps.Count -gt 0)
        {
            write-log "`nDo you want to delete snapshot $($VMsnaps[$VMsnaps.Count - 1].Name) taken at $($VMsnaps[$VMsnaps.Count - 1].SnapshotTime) (Y/N)?"
            if ((read-host) -eq 'Y')
            {
                $VMsnaps[$VMsnaps.Count - 1].ICloudBlob.Delete()
                Write-Host "Successfully deleted snapshot $($VMsnaps[$VMsnaps.Count - 1].Name)"
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

function SnapshotAndCopyOSDisk  (
    [Object[]]$vm,
    [string] $resourceGroupName,
    [string] $prefix
)
{
    write-log "Creating snapshot"
    $osDiskVhdUri = $vm.StorageProfile.OsDisk.Vhd.Uri
    if (-not $osDiskVhdUri)
    {
        write-log "Unable to determine VHD uri for VM $($vm.Name)" -color red
        return null
    } 
    $osDiskvhd = $osDiskVhdUri.split('/')[-1]
    $storageAccountName = $vm.StorageProfile.OsDisk.Vhd.Uri.Split('//')[2].Split('.')[0]
    #$fixedosdiskvhd = "fixedos$osDiskvhd" 
    $ToBefixedosdiskvhd = $null
    try
    {
        $StorageAccountRg = Get-AzureRmStorageAccount | where {$_.StorageAccountName -eq $storageAccountName} | Select-Object -ExpandProperty ResourceGroupName
        if (-not $StorageAccountRg)
        {
            write-log "Unable to determine resource group for storage account $storageAccountName" -color red
            return null
        } 
        $StorageAccountKey = (Get-AzureRmStorageAccountKey -Name $storageAccountName -ResourceGroupName $StorageAccountRg).Value[1] 
        $ContainerName = $osDiskVhdUri.Split('/')[3]

        #Connect to the storage account
        $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey 
        $VMblob = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -ne $true}
        if (-not $VMblob)
        {
            write-log "Could not find OS disk VHD blob for $osDiskvhd" -color red
            return null
        }

        #Create a snapshot of the OS Disk
        write-log "Creating snapshot" 
        $snap = $VMblob.ICloudBlob.CreateSnapshot()
        if ($snap)
        {
            write-log "Successfully created snapshot" -color green
        }
        else
        {
            write-log "It was not able to create a snapshot but will proceed to find a snapshot, and so the snapshot may be stale" -color cyan
        }

        write-log "Copying snapshot" 
        #Save array of all snapshots
        $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | sort @{expression="SnapshotTime";Descending=$true} | where-object {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -and $_.SnapshotTime -ne $null} 

        #Copies the LatestSnapshot of the OS Disk to the same storage account prefixing with 
        if ($VMsnaps.Count -gt 0)
        {   
            #$ToBefixedosdiskvhd = "fixedos$osDiskvhd" 
            $ToBefixedosdiskvhd = $prefix + "fixedos" +  $osDiskvhd
            $status = Start-AzureStorageBlobCopy -CloudBlob $VMsnaps[0].ICloudBlob -Context $Ctx -DestContext $Ctx -DestContainer $ContainerName -DestBlob $ToBefixedosdiskvhd -ConcurrentTaskCount 10 -Force
            #$status | Get-AzureStorageBlobCopyState            
            $osFixDiskblob = Get-AzureRMStorageAccount -Name $storageAccountName -ResourceGroupName $StorageAccountRg | 
            Get-AzureStorageContainer | where {$_.Name -eq $ContainerName} | Get-AzureStorageBlob | where {$_.Name -eq $ToBefixedosdiskvhd -and $_.ICloudBlob.IsSnapshot -ne $true}
            $copiedOSDiskUri =$osFixDiskblob.ICloudBlob.Uri.AbsoluteUri
            write-log "Successfully copied snapshot to $copiedOSDiskUri" -color green
            return $copiedOSDiskUri
        }
        else
        {
           write-log "Snapshot copy failed." -color red
        }
    }
    catch
    {
        $message = "The operation to create and copy snapshot failed"
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
    write-log "Swapping OS disk for $vmName"
    write-log "Commands to restore the VM back to its original state" -logonly
    write-log "Note: If for any reason you decide to restore the VM back to its orginal problem state, you may run the following commands`n"
    write-log "`$problemvm = Get-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName"
    write-log "Stop-AzureRmVM -ResourceGroupName `"$resourceGroupName`" -Name `"$vmName`""
    if (-not $managedVM)
    {
        write-log "`$problemvm.StorageProfile.OsDisk.Vhd.Uri = $problemvmOsDiskUri"
        write-log "Update-AzureRmVM -ResourceGroupName $resourceGroupName -VM `$problemvm"
        write-log "Start-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName"
    }
    else
    {
        write-log "Set-AzureRmVMOSDisk -vm `$problemvm -ManagedDiskId $problemvmOsDiskManagedDiskID -CreateOption FromImage"
        write-log "Update-AzureRmVM -ResourceGroupName $resourceGroupName -VM `$problemvm"
        write-log "Start-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName"
    }
}

function SupportedVM(
    [Object[]]$vm,
    [bool] $AllowManagedVM
)
{
    if (-not $vm)
    {
        write-log "Unable to find the VM. Verify the VM name and resource group name." -color red
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
                $ImageObj =(get-azurermvmimage -Location $vm.Location -PublisherName $vm.StorageProfile.ImageReference.Publisher -Offer $vm.StorageProfile.ImageReference.Offer -Skus $vm.StorageProfile.ImageReference.sku)[-1]
                if (-not $ImageObj)
                {
                    write-log "This VM was created from a marketplace image with Plan information, but the marketplace image is no longer published, so if this VM were removed, it would not be possible to recreate it from the existing disk." -color red
                    return $false
                }
            }
        }
    }
    catch
    {
        write-log "This VM was created from a marketplace image with Plan information, but the marketplace image is no longer published, so if this VM were removed, it would not be possible to recreate it from the existing disk." -color red
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
        write-log "Initiating the process to create the rescue VM"
        
        if ($vm.StorageProfile.OsDisk.ManagedDisk) {$managedVM = $true} else {$managedVM = $false}

        $osDiskName  = $vm.StorageProfile.OsDisk.Name
        $vmSize = $vm.HardwareProfile.VmSize
        $osType = $vm.StorageProfile.OsDisk.OsType
        $location = $vm.Location
        $networkInterfaceName = $vm.NetworkProfile.NetworkInterfaces[0].Id.split('/')[-1]
        $MaxStorageAccountNameLength = 24
        if ([string]::IsNullOrWhitespace($osDiskName))
        {
            write-log "Unable to determine OS disk name for VM $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($vmSize))
        {
            write-log "Unable to determine VM size for VM $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($osType))
        {
            write-log "Unable to determine OS type for VM $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($location))
        {
            write-log "Unable to determine location of VM $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($networkInterfaceName))
        {
            write-log "Unable to determine network interface name for VM $($vm.name)" -color red
            return null
        }
        $rescueOSDiskName = "$prefix$osDiskName"
        if (-not $managedVM)
        {
            $osDiskVhdUri = $vm.StorageProfile.OsDisk.Vhd.Uri
            $storageAccountName = $vm.StorageProfile.OsDisk.Vhd.Uri.Split('//')[2].Split('.')[0]
            $rescueosDiskVhduri = $osDiskVhdUri.Replace($osDiskName,$rescueOSDiskName)
        }

        $rescuevm = New-AzureRmVMConfig -VMName $rescueVMName -VMSize $vmSize -WarningAction SilentlyContinue
        $rescuenetworkInterfaceName = "$prefix$networkInterfaceName"
        $nic1 = Get-AzureRmNetworkInterface -resourceGroupName $resourceGroupName | where-object {$_.Name -eq $networkInterfaceName}
        $nic1Id = $nic1.Id
        $rescuenic1Id = $nic1Id.Replace($networkInterfaceName,$rescuenetworkInterfaceName)
        $rescuevm = Add-AzureRmVMNetworkInterface -VM $rescuevm -Id $rescuenic1Id -WarningAction SilentlyContinue
        $rescuevm.NetworkProfile.NetworkInterfaces[0].Primary = $true
        #$rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -VhdUri $rescueosDiskVhduri -name $rescueOSDiskName -CreateOption attach -Windows              
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
        $rg = Get-AzureRmResourceGroup -Name $rescueResourceGroupName -Location $Location -ErrorAction SilentlyContinue
        if ($rg)
        {
            write-log "`nResource group $rescueResourceGroupName already exists. `nIt looks like you may be rerunning the script without actually deleting the resource group that was created from the previous execution or you may already have a resource group by that same name. `nPlease either delete the resource group ==> $rescueResourceGroupName) if you no longer need it or rerun the script again by adding the parameter '-prefix' and specify a new prefix  to make a new resource group" -color red
            return $null
        }
        else
        {
            write-log "Creating resource group $rescueResourceGroupName for rescue VM $rescueVMName"
            New-AzureRmResourceGroup -Name $rescueResourceGroupName -Location $Location
            write-log "Successfully created resource group $rescueResourceGroupName" -color green
        }

        # Create the storage account if it's a managed disk VM
        if (-not $managedVM)
        {
            write-log "Creating storage account $rescueStorageName"
            $rescueStorageAccount = New-AzureRmStorageAccount -ResourceGroupName $rescueResourceGroupName -Name $rescueStorageName -Type $rescueStorageType -Location $Location
            write-log "Successfully created storage account $rescueStorageName" -color green
        }

        # Network
        #write-log "Allocating a new PublicIP ==> $rescueInterfaceName" 
        $rescuePip = New-AzureRmPublicIpAddress -Name $rescueInterfaceName -ResourceGroupName $rescueResourceGroupName -Location $Location -AllocationMethod Dynamic -WarningAction SilentlyContinue
        #write-log "Allocated  PublicIP ==> $rescueInterfaceName" -color Green

        write-log "Creating subnet config for subnet $rescueSubnet1Name"
        $rescueSubnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name $rescueSubnet1Name -AddressPrefix $rescueVNetSubnetAddressPrefix
        write-log "Successfully created subnet config for subnet $rescueSubnet1Name" -color green

        write-log "Creating virtual network $rescueVNetName"
        $rescueVNet = New-AzureRmVirtualNetwork -Name $rescueVNetName -ResourceGroupName $rescueResourceGroupName -Location $Location -AddressPrefix $rescueVNetAddressPrefix -Subnet $rescueSubnetConfig -WarningAction SilentlyContinue
        write-log "Successfully created virtual network $rescueVNetName" -color green

        write-log "Creating network interface $rescueInterfaceName"
        $rescueInterface = New-AzureRmNetworkInterface -Name $rescueInterfaceName -ResourceGroupName $rescueResourceGroupName -Location $Location -SubnetId $rescueVNet.Subnets[0].Id -PublicIpAddressId $rescuePIp.Id -WarningAction SilentlyContinue
        write-log "Successfully created network interface $rescueInterfaceName" -color green
    
        ## Setup local VM object
        if (-not $Credential)
        {
            write-log "Enter user name and password for the rescue VM that will be created." -color darkcyan
            $Credential = Get-Credential -Message "Enter username and password for the rescue VM that will be created."
        }
   
        $rescuevm = New-AzureRmVMConfig -VMName $rescueVMName -VMSize $rescueVMSize -WarningAction SilentlyContinue
        if ($osType -eq 'Windows')
        {
            $rescuevm = Set-AzureRmVMOperatingSystem -VM $rescuevm -Windows -ComputerName $rescueComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate -WarningAction SilentlyContinue
            #get the latest" version of 2016 image with a GUI
            $ImageObj =(get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter')[-1]
        }
        else
        {
            $rescuevm = Set-AzureRmVMOperatingSystem -VM $rescuevm -Linux -ComputerName $rescueComputerName -Credential $Credential -WarningAction SilentlyContinue
            #$ImageObj = (get-azurermvmimage -Location westus -PublisherName 'Canonical' -Offer 'UbuntuServer' -Skus '16.04-LTS')[-1]
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
        $rescuevm = Set-AzureRmVMSourceImage -VM $rescuevm -PublisherName $Publisher -Offer $offer -Skus $sku -Version $Version -WarningAction SilentlyContinue
        $rescuevm = Add-AzureRmVMNetworkInterface -VM $rescuevm -Id $rescueInterface.Id -WarningAction SilentlyContinue

        #$rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -Name $rescueOSDiskName -VhdUri $rescueOSDiskUri -CreateOption FromImage
        if ($managedVM)
        {
            #$rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -ManagedDiskId $disk.Id -CreateOption FromImage
            $rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -Name $rescueOSDiskName -CreateOption FromImage -WarningAction SilentlyContinue
        }
        else
        {
            $rescueOSDiskUri = $rescueStorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $rescueOSDiskName + ".vhd"
            $rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -Name $rescueOSDiskName -VhdUri $rescueOSDiskUri -CreateOption FromImage -WarningAction SilentlyContinue
        }

        <#if ($ostype -eq "Linux")
        {
            $sshPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
            $rescuevm = Add-AzureRmVMSshPublicKey -VM $rescuevm -KeyData $sshPublicKey -Path "/home/azureuser/.ssh/authorized_keys"
        }#>

        ## Create the VM in Azure
        write-log "Creating rescue VM $($rescuevm.Name) in resource group $rescueResourceGroupName"
        $created = New-AzureRmVM -ResourceGroupName $rescueResourceGroupName -Location $Location -VM $rescuevm -ErrorAction Stop -WarningAction SilentlyContinue
        write-log "Successfully created rescue VM $rescueVMName in resource group $rescueResourceGroupName" -color green
       
        return $created
    }
    catch
    {
        $message = "Unable to create the rescue VM"
        write-log $message -color red
        write-log "$message - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        write-log "Exception Message: $($_.Exception.Message)"
        throw
        return null
    }    
}

function AttachOsDisktoRescueVM(
    [string]$rescueResourceGroupName,
    [string]$rescueVMName,
    [string]$osDiskVHDToBeRepaired,
    [string]$diskName,
    [string]$osDiskSize,
    [string]$managedDiskID
)
{
    $returnVal = $true
    write-log "Running Get-AzureRmVM -ResourceGroupName `"$rescueResourceGroupName`" -Name `"$rescueVMName`"" 
    $rescuevm = Get-AzureRmVM -resourceGroupName $rescueResourceGroupName -Name $rescueVMName -WarningAction SilentlyContinue
    if (-not $rescuevm)
    {
        write-log "Rescue VM $rescueVMName not found" -Color Red
        return $false
    }
    write-log "Attaching OS disk to rescue VM $rescueVMName"
    try
    {
        if ($managedDiskID) 
        {
           Add-AzureRmVMDataDisk -VM $rescueVm -Name $diskName -CreateOption Attach -ManagedDiskId $managedDiskID -Lun 0
        }
        else
        {
          Add-AzureRmVMDataDisk -VM $rescueVm -Name $diskName -Caching None -CreateOption Attach -DiskSizeInGB $osDiskSize -Lun 0 -VhdUri $osDiskVHDToBeRepaired
        }
        Update-AzureRmVM -resourceGroupName $rescueResourceGroupName -VM $rescuevm 
        write-log "Successfully attached OS disk as a data disk on rescue VM $rescueVMName" -color green
    }
    catch
    {
         $returnVal = $false
         write-log "Unable to attach OS disk - Exception Type: $($_.Exception.GetType().FullName)" -logOnly
         write-log "Exception Message: $($_.Exception.Message)" -logOnly
         throw
    }
    return $returnVal
}

function StopTargetVM(
    [String]$resourceGroupName,
    [String]$vmName
)
{
    write-log "Stopping VM $vmName"
    $stopped = Stop-AzureRmVM -ResourceGroupName $resourceGroupName -Name $vmName -Force
    if ($stopped)
    {
        write-log "Successfully stopped VM $vmName" -color green
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
    [string]$status1,    
    [string]$color = 'White',
    [switch]$logOnly
    )    

    if ($logOnly)
    {
        $timestamp = ('[' + (get-date (get-date).ToUniversalTime() -Format yyyy-MM-ddTHH:mm:ssZ) + '] ')
        (($timestamp + $status1 + $status2) | Out-String).Trim() | Out-File $logFile -Append 
    }
    else
    {
        $timestamp = ('[' + (get-date (get-date).ToLocalTime() -Format 'yyyy-MM-dd HH:mm:ss') + '] ')
        Write-Host $timestamp -NoNewline 

        Write-Host $status1 -ForegroundColor $color
        $timestamp = ('[' + (get-date (get-date).ToUniversalTime() -Format yyyy-MM-ddTHH:mm:ssZ) + '] ')
        (($timestamp + $status1 + $status2) | Out-String).Trim() | Out-File $logFile -Append
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