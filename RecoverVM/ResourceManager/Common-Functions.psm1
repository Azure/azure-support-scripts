param(
    [parameter(Position=0,Mandatory=$true)]
        [string] $LogFile
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
    [bool] $scriptSucceeded ,
    [string] $restoreScriptCommand,
    [string] $rescueScriptCommand,
    [string] $FailureReason
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
    [string] $ResourceGroup
 )
{
    try
    {
        $osDiskvhd = $osDiskVhdUri.split('/')[-1]
        $storageAccountName = $osDiskVhdUri.Split('//')[2].Split('.')[0]
        $ContainerName = $osDiskVhdUri.Split('/')[3]

        $StorageAccountKey = (AzureRmStorageAccountKey -StorageAccountName $storageAccountName -ResourceGroupName $ResourceGroup)[1].Value
        $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey -ErrorAction Stop
        $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where-Object {$_.ICloudBlob.IsSnapshot -and $_.SnapshotTime -ne $null -and $_.Name -eq $osDiskvhd }  -ErrorAction Stop
        #Deleting the snapshot
        if ($VMsnaps.Count -gt 0)
        {
            Write-log "`nWould you like to delete the snapshot ==> $($VMsnaps[$VMsnaps.Count - 1].Name) that was taken at $($VMsnaps[$VMsnaps.Count - 1].SnapshotTime) (Y/N) ?" 
            if ((read-host) -eq 'Y')
            {
                $VMsnaps[$VMsnaps.Count - 1].ICloudBlob.Delete()
                Write-Host "Snapshot has been deleted"
            }
        }

        <##Deleting the backedupovhd
        $backupOSDiskVhd = "backup$osDiskvhd" 
        $osFixDiskblob = Get-AzureStorageAccount -StorageAccountName $storageAccountName | 
        Get-AzureStorageContainer | where {$_.Name -eq $ContainerName} | Get-AzureStorageBlob | where {$_.Name -eq $backupOSDiskVhd -and $_.ICloudBlob.IsSnapshot -ne $true} -ErrorAction Stop
        if ($osFixDiskblob)
        {
            Write-log "`nWould you like to delete the backed up VHD ==> $($backupOSDiskVhd) (Y/N) ?" 
            if ((read-host) -eq 'Y')
            {
                $osFixDiskblob.ICloudBlob.Delete()
                Write-Host "backupOSDiskVhd has been deleted"
            }
        }#>
    }
    catch
    {
        write-log "Exception Message: $($_.Exception.Message)" -Color Red
        Write-log "Error in Line# : $($_.Exception.Line) =>  $($MyInvocation.MyCommand.Name)" -Color Red
        return $false
    }
}

function SnapshotAndCopyOSDisk  (
    [Object[]]$vm,
    [string] $ResourceGroup,
    [string] $prefix
    )
{

    Write-Log "Initiating the snapshot process"  
    $osDiskVhdUri = $vm.StorageProfile.OsDisk.Vhd.Uri
    if (-not $osDiskVhdUri)
    {
        write-log "Unable to determine the VHD Uri for the vm ==> $($vm.Name)" -color red
        return null
    } 
    $osDiskvhd = $osDiskVhdUri.split('/')[-1]
    $storageAccountName = $vm.StorageProfile.OsDisk.Vhd.Uri.Split('//')[2].Split('.')[0]
    #$fixedosdiskvhd = "fixedos$osDiskvhd" 
    $ToBefixedosdiskvhd = $null
    Try
    {
        $StorageAccountRg = Get-AzureRmStorageAccount | where {$_.StorageAccountName -eq $storageAccountName} | Select-Object -ExpandProperty ResourceGroupName
        if (-not $StorageAccountRg)
        {
            write-log "Unable to determine the Storage Account resource Group for Storage Account Name ==> $($storageAccountName)" -color red
            return null
        } 
        $StorageAccountKey = (Get-AzureRmStorageAccountKey -Name $storageAccountName -ResourceGroupName $StorageAccountRg).Value[1] 
        $ContainerName = $osDiskVhdUri.Split('/')[3]

        #Connect to the storage account
        $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey 
        $VMblob = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -ne $true}
        if (-not $VMblob)
        {
            write-log "Unable to pull the osDiskvhd info for  ==> $($osDiskvhd)" -color red
            return null
        }


        #Create a snapshot of the OS Disk
        Write-Log "Running CreateSnapshot operation" 
        $snap = $VMblob.ICloudBlob.CreateSnapshot()
        if ($snap)
        {
            Write-Log "Successfully completed CreateSnapshot operation" -Color Green
        }
        else
        {
            write-log "It was not able to create a snapshot but will proceed to find a snapshot, and so the snapshot may be stale" -color cyan
        }


        Write-Log "Initiating Copy proccess of Snapshot" 
        #Save array of all snapshots
        $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | sort @{expression="SnapshotTime";Descending=$true} | Where-Object {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -and $_.SnapshotTime -ne $null } 

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
            Write-Log "Successfully copied the Snapshot to $copiedOSDiskUri" -Color Green
            return $copiedOSDiskUri
        }
        else
        {
           Write-Log "Snapshot copy was unsuccessfull" -Color Red       
        }
    }
    Catch
    {
        Write-Log "The operation to create and copy snapshot failed" -Color Red
        Write-Log "The operation to create and copy snapshot failed -  Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        Write-Log "Exception Message: $($_.Exception.Message)" -logOnly
        throw  
        return $null
    }

    Return $copiedOSDiskUri
    
}

function WriteRestoreCommands (
    [string] $ResourceGroup,
    [string] $VmName,
    [string] $problemvmOsDiskUri,
    [string] $problemvmOsDiskManagedDiskID,
    [bool] $managedVM
    )
{
    Write-Log "Disk Swapping the OS Disk, to point to the fixed OS Disk for VM ==>  $VmName" 
    Write-Log "================================================================" 
    write-log "Commands to restore the VM back to its original state" -logonly
    Write-Log "================================================================" 
    Write-Log "Note: If for any reason you decide to restore the VM back to its orginal problem state, you may run the following commands`n"
    Write-Log "`$problemvm = Get-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -Name `"$VmName`"" 
    Write-Log "Stop-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -Name `"$VmName`""
    if (-not $managedVM)
    {
        Write-Log "`$problemvm.StorageProfile.OsDisk.Vhd.Uri = `"$($problemvmOsDiskUri)`""
        Write-Log "Update-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -VM `$problemvm"
        Write-Log "Start-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -Name `"$VmName`""
        Write-Log "`n================================================================" 
    }
    else
    {
        Write-Log "Set-AzureRmVMOSDisk -vm `$problemvm -ManagedDiskId `"$problemvmOsDiskManagedDiskID`" -CreateOption FromImage"
        Write-Log "Update-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -VM `$problemvm"
        Write-Log "Start-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -Name `"$VmName`""
        Write-Log "`n================================================================" 
    }
}

function SupportedVM([Object[]]$vm,
                     [bool] $AllowManagedVM)
{
    if (-not $vm)
    {
        Write-Log "Unable to find the VM,  cannot proceed, please verify the VM name and the resource group name." -Color Red
        return $false
    }
     
    if (($vm.StorageProfile.OsDisk.ManagedDisk) -and (-not $AllowManagedVM)) 
    {
        Write-log "VM ==> $($vm.Name) is a Managed VM, and is currently not supported by this script, cannot continue exiting." -color Red
        Return $false
    }

    #Checks to see if the Image exist, if not it returns false as disk swap does not works unless the imgage is available.
    Try
    {
        if ($vm.StorageProfile.OsDisk.CreateOption -eq "FromImage")
        {
            $ImageObj =(get-azurermvmimage -Location $vm.Location -PublisherName $vm.StorageProfile.ImageReference.Publisher -Offer $vm.StorageProfile.ImageReference.Offer -Skus $vm.StorageProfile.ImageReference.sku)[-1]
            if (-not $ImageObj)
            {
                Write-Log "Artifact: VMImage was not found,script can't be used you may hit the same error if you manually try to perform the same steps as well." -color red
                return $false
            }
        }
    }
    catch
    {
        Write-Log "Artifact: VMImage was not found,script can't be used you may hit the same error if you manually try to perform the same steps as well." -color red
        return $false
    }

    <#if ($vm.StorageProfile.OsDisk.OsType -ne "Windows")
    {
        Write-log "VM ==> $($vm.Name) is not a Windows VM, and is currently not supported by this script, cannot continue exiting." -color Red
        return $false
    } #>   
    return $true
}

function CreateRescueVM(
    [Object[]]$vm,
    [Parameter(mandatory=$true)]
    [String]$ResourceGroup,
    [Parameter(mandatory=$true)]
    [String]$rescueVMNname,
    [Parameter(mandatory=$true)]
    [String]$RescueResourceGroup,
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

    Try
    {
        write-log "Initiating the process to create the new Rescue VM" 
        
        if ($vm.StorageProfile.OsDisk.ManagedDisk) {$managedVM = $true} else  {$managedVM = $false}

        $osDiskName  = $vm.StorageProfile.OsDisk.Name
        $vmSize = $vm.HardwareProfile.VmSize
        $osType = $vm.StorageProfile.OsDisk.OsType
        $location = $vm.Location
        $networkInterfaceName = $vm.NetworkProfile.NetworkInterfaces[0].Id.split('/')[-1]
        $MaxStorageAccountNameLength=24
        if ([string]::IsNullOrWhitespace($osDiskName))
        {
            Write-log "Unable to determine the OS DiskName of the $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($vmSize))
        {
            Write-log "Unable to determine the VM Size of the $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($osType))
        {
            Write-log "Unable to determine the osType of the $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($location))
        {
            Write-log "Unable to determine the location of the $($vm.name)" -color red
            return null
        }
        if ([string]::IsNullOrWhitespace($networkInterfaceName))
        {
            Write-log "Unable to determine the networkInterfaceName of the $($vm.name)" -color red
            return null
        }
        $rescueOSDiskName = "$prefix$osDiskName"
        if (-not $managedVM)
        {
            $osDiskVhdUri = $vm.StorageProfile.OsDisk.Vhd.Uri
            $storageAccountName = $vm.StorageProfile.OsDisk.Vhd.Uri.Split('//')[2].Split('.')[0]
            $rescueosDiskVhduri = $osDiskVhdUri.Replace($osDiskName,$rescueOSDiskName)
        }

        $rescuevm = New-AzureRmVMConfig -VMName $rescueVMNname -VMSize $vmSize;
        $rescuenetworkInterfaceName = "$prefix$networkInterfaceName"
        $nic1 = Get-AzureRmNetworkInterface   -ResourceGroupName $ResourceGroup | Where-Object {$_.Name -eq $networkInterfaceName}
        $nic1Id = $nic1.Id
        $rescuenic1Id = $nic1Id.Replace($networkInterfaceName,$rescuenetworkInterfaceName)
        $rescuevm = Add-AzureRmVMNetworkInterface -VM $rescuevm -Id $rescuenic1Id
        $rescuevm.NetworkProfile.NetworkInterfaces[0].Primary = $true
        #$rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -VhdUri $rescueosDiskVhduri -name $rescueOSDiskName -CreateOption attach -Windows              
        $rescueStorageType = "Standard_GRS"
        $rescueStorageName = "$prefix$storageAccountName"
        $rescueStorageName = $rescueStorageName.ToLower()
        $rescueStorageName = Get-ValidLength -InputString $rescueStorageName  -Maxlength $MaxStorageAccountNameLength
        ## Network
        $rescueInterfaceName = $prefix+"interface"
        $rescueSubnet1Name = $prefix + "Subnet"
        $rescueVNetName = $prefix +"VNet"
        $rescueVNetAddressPrefix = "10.0.0.0/16"
        $rescueVNetSubnetAddressPrefix = "10.0.0.0/24"   

        ## Compute
        $rescueComputerName = $prefix+"vm"
        $rescueVMSize = $vmSize #"Standard_A2"
        $rescueOSDiskName = $rescueVMNname + "OSDisk"

        # Resource Group
        #checks to see if ResourceGroup Already exist
        $rg = Get-AzureRmResourceGroup -Name $RescueResourceGroup -Location $Location -ErrorAction SilentlyContinue
        if ($rg)
        {
            Write-log "`nResourceGroup ==> $($RescueResourceGroup) already exists!!! `nIt looks like you may be rerunning the script without actully deleting the resourcegroup that was created from the previous execution or you may already have a resourcegroup by that same name. `nPlease either delete the ResourceGroup ==> $($RescueResourceGroup) if you no longer need it or rerun the script again by adding the parameter '-prefix' and specify a new prefix  to make a new resourcegroup"  -color red
            return $null
        }
        else
        {
            Write-log "Creating a new ResourceGroup ==> $RescueResourceGroup to hold all the temporary Resources" 
            New-AzureRmResourceGroup -Name $RescueResourceGroup -Location $Location
            Write-Log "Successfully created ResourceGroup ==> $RescueResourceGroup" -color Green 
        }

        if (-not $managedVM)  #Creates the storage account only for Managed VM's.
        {
            # Storage
            Write-log "Creating a new StorageAccount ==> $rescueStorageName" 
            $rescueStorageAccount = New-AzureRmStorageAccount -ResourceGroupName $RescueResourceGroup -Name $rescueStorageName -Type $rescueStorageType -Location $Location
            Write-Log "Successfully created StorageAccount ==> $rescueStorageName" -color Green 
        }

        # Network
        #Write-log "Allocating a new PublicIP ==> $rescueInterfaceName" 
        $rescuePIp = New-AzureRmPublicIpAddress -Name $rescueInterfaceName -ResourceGroupName $RescueResourceGroup -Location $Location -AllocationMethod Dynamic -WarningAction SilentlyContinue
        #Write-log "Allocated  PublicIP ==> $rescueInterfaceName" -color Green

        Write-log "Creating a new VirtualNetworkSubnetConfig ==> $rescueSubnet1Name" 
        $rescueSubnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name $rescueSubnet1Name -AddressPrefix $rescueVNetSubnetAddressPrefix
        Write-log "Successfully created VirtualNetworkSubnetConfig ==> $rescueSubnet1Name" -color Green

        Write-log "Creating a new VirtualNetwork ==> $rescueVNetName" 
        $rescueVNet = New-AzureRmVirtualNetwork -Name $rescueVNetName -ResourceGroupName $RescueResourceGroup -Location $Location -AddressPrefix $rescueVNetAddressPrefix -Subnet $rescueSubnetConfig -WarningAction SilentlyContinue
        Write-log "Successfully created VirtualNetwork ==> $rescueVNetName" -color Green

        Write-log "Creating a new NetworkInterface ==> $rescueInterfaceName" 
        $rescueInterface = New-AzureRmNetworkInterface -Name $rescueInterfaceName -ResourceGroupName $RescueResourceGroup -Location $Location -SubnetId $rescueVNet.Subnets[0].Id -PublicIpAddressId $rescuePIp.Id -WarningAction SilentlyContinue
        Write-log "Successfully created NetworkInterface ==> $rescueInterfaceName" -color Green
    
        ## Setup local VM object
        if (-not $Credential)
        {
            Write-Log "Please enter the UserName and Password for the new rescue VM that is being created " -Color DarkCyan
            $Credential = Get-Credential -Message "Enter a username and password for the Rescue virtual machine."
        }
   
        $rescuevm = New-AzureRmVMConfig -VMName $rescueVMNname -VMSize $rescueVMSize
        if ($osType -eq 'Windows')
        {
            $rescuevm = Set-AzureRmVMOperatingSystem -VM $rescuevm -Windows -ComputerName $rescueComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate 
            #get the latest" version of 2016 image with a GUI
            $ImageObj =(get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter')[-1]
        }
        else
        {
            $rescuevm = Set-AzureRmVMOperatingSystem -VM $rescuevm -Linux -ComputerName $rescueComputerName -Credential $Credential 
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
        if (-not $Version)
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
        $rescuevm = Set-AzureRmVMSourceImage -VM $rescuevm -PublisherName $Publisher -Offer $offer -Skus $sku -Version $Version
        $rescuevm = Add-AzureRmVMNetworkInterface -VM $rescuevm -Id $rescueInterface.Id


        #$rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -Name $rescueOSDiskName -VhdUri $rescueOSDiskUri -CreateOption FromImage
        if ($managedVM)
        {
            #$rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -ManagedDiskId $disk.Id -CreateOption FromImage
            $rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -Name $rescueOSDiskName -CreateOption FromImage
        }
        else
        {
            $rescueOSDiskUri = $rescueStorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $rescueOSDiskName + ".vhd"
            $rescuevm = Set-AzureRmVMOSDisk -VM $rescuevm -Name $rescueOSDiskName -VhdUri $rescueOSDiskUri -CreateOption FromImage
        }


        <#if ($ostype -eq "Linux")
        {
            $sshPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
            $rescuevm = Add-AzureRmVMSshPublicKey -VM $rescuevm -KeyData $sshPublicKey -Path "/home/azureuser/.ssh/authorized_keys"
        }#>


        ## Create the VM in Azure
        Write-Log "Creating Resuce VM name ==> $($rescuevm.Name) under ResourceGroup ==> $RescueResourceGroup" 
        $created = New-AzureRmVM -ResourceGroupName $RescueResourceGroup -Location $Location -VM $rescuevm -ErrorAction Stop
        Write-Log "Successfully created Rescue VM ==> $rescueVMNname was created under ResourceGroup==> $RescueResourceGroup" -Color Green 
       
        Return $created
    }
    Catch
    {
        Write-Log "Unable to create the rescue VM successfully" -Color Red
        Write-Log "Unable to create the rescue VM successfully - -  Exception Type: $($_.Exception.GetType().FullName)" -logOnly
        Write-Log "Exception Message: $($_.Exception.Message)" 
        throw
        return null
    }  
    
}

function AttachOsDisktoRescueVM(
[String]$RescueResourceGroup,
[String]$rescueVMNname,
[String]$osDiskVHDToBeRepaired,
[String]$diskName,
[String]$osDiskSize,
[String]$managedDiskID
)
{
    $returnVal = $true
    Write-Log "Running Get-AzureRmVM -ResourceGroupName `"$RescueResourceGroup`" -Name `"rescueVMNname`"" 
    $rescuevm = Get-AzureRmVM -ResourceGroupName $RescueResourceGroup -Name $rescueVMNname
    if (-not $rescuevm)
    {
        Write-Log "RescueVM ==>  $rescueVMNname cannot be found, Cannot proceed" -Color Red
        Return $false
    }
    Write-Log "Attaching the OS Disk to the rescueVM" 
    Try
    {
        if ($managedDiskID) 
        {
           Add-AzureRmVMDataDisk -VM $rescueVm -Name $diskName -CreateOption Attach -ManagedDiskId $managedDiskID -Lun 0
        }
        else
        {
          Add-AzureRmVMDataDisk -VM $rescueVm -Name $diskName -Caching None -CreateOption Attach -DiskSizeInGB $osDiskSize -Lun 0 -VhdUri $osDiskVHDToBeRepaired
        }
        Update-AzureRmVM -ResourceGroupName $RescueResourceGroup -VM $rescuevm 
        Write-Log "Successfully attached the OS Disk as a Data Disk" -Color Green
    }
    Catch
    {
         $returnVal = $false
         Write-Log "Unable to Attach the OSDisk -  Exception Type: $($_.Exception.GetType().FullName)" -logOnly
         Write-Log "Exception Message: $($_.Exception.Message)" -logOnly
         throw
    }
    return $returnVal
}


function StopTargetVM(
    [String]$ResourceGroup,
    [String]$VmName
)
{

    Write-Log "Stopping Azure VM $VmName" 
    $stopped = Stop-AzureRmVM -ResourceGroupName $ResourceGroup -Name $VmName -Force
    if ($stopped)
    {
        Write-Log "Successfully stopped  Azure VM $VmName" -Color Green
        return $true
    }
    else
    {
        if ( $error )
        {    
            Write-Log ('='*47) -logOnly
            Write-Log "errors logged during script execution`n" -noTimestamp -logOnly
            Write-Log ('='*47) -logOnly
            Write-Log "`n" -logOnly
            $error | sort -Descending | % { Write-Log ( 'Line:' + $_.InvocationInfo.ScriptLineNumber + ' Char:' + $_.InvocationInfo.OffsetInLine + ' ' + $_.Exception.ErrorRecord ) -logOnly }    
        }
    }
    return $false
}


Function Write-Log
{
    param(
    [string]$status1,    
    [string]$color = 'White',
    [switch]$logOnly
    )    

    if ($logOnly)
    {
        $timestamp = ('[' + (get-date (get-date).ToUniversalTime() -Format yyyy-MM-ddTHH:mm:ssZ) + '] ')
        (($timestamp + $status1 + $status2) | Out-String).Trim() | Out-File $LogFile -Append 
    }
    else
    {
        $timestamp = ('[' + (get-date (get-date).ToLocalTime() -Format 'yyyy-MM-dd HH:mm:ss') + '] ')
        Write-Host $timestamp -NoNewline 

        Write-Host $status1 -ForegroundColor $color
        $timestamp = ('[' + (get-date (get-date).ToUniversalTime() -Format yyyy-MM-ddTHH:mm:ssZ) + '] ')
        (($timestamp + $status1 + $status2) | Out-String).Trim() | Out-File $LogFile -Append
    }

}

Export-ModuleMember -Function Write-Log
Export-ModuleMember -Function SnapshotAndCopyOSDisk
Export-ModuleMember -Function CreateRescueVM
Export-ModuleMember -Function StopTargetVM
Export-ModuleMember -Function AttachOsDisktoRescueVM
Export-ModuleMember -Function SupportedVM
Export-ModuleMember -Function WriteRestoreCommands
Export-ModuleMember -Function Get-ValidLength
Export-ModuleMember -Function DeleteSnapShotAndVhd
Export-ModuleMember -Function Get-ScriptResultObject
