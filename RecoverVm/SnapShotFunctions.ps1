function TakeSnapshotofOSDisk (
    [string] $storageAccountName , 
    [string] $StorageAccountKey,
    [string] $ContainerName,
    [string]$osDiskvhd
     
    )
{
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName

    if ( ! $vm ) 
    {
        return
    }
    #As per PR taking a snapshot of the OS disk first.
    #$storageAccountName = $vm.VM.OSVirtualHardDisk.MediaLink.Authority.Split(".")[0]
    #$StorageAccountKey = (Get-AzureStorageKey -StorageAccountName $storageAccountName).Secondary
    #$ContainerName = $vm.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri.Split('/')[3]
    #$osDiskvhd = $vm.VM.OSVirtualHardDisk.MediaLink.AbsolutePath.split('/')[-1]

    $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey 
    $VMblob = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -ne $true}

    #Create a snapshot of the OS Disk
    Write-host "Running CreateSnapshot operation" -Color Yellow
    $snap = $VMblob.ICloudBlob.CreateSnapshot()
    if ($snap)
    {
        Write-host "Successfully completed CreateSnapshot operation" -Color Green
    }

    Write-host "Initiating Copy proccess of Snapshot" -Color Yellow
    #Save array of all snapshots
    $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where-Object {$_.ICloudBlob.IsSnapshot -and $_.SnapshotTime -ne $null } 

    #Copies the LatestSnapshot of the OS Disk as a backup prior to making any changes to the OS Disk to the same storage account and prefixing with Backup
    if ($VMsnaps.Count -gt 0)
    {   
        $backupOSDiskVhd = "backup$osDiskvhd" 
        $status = Start-AzureStorageBlobCopy -CloudBlob $VMsnaps[$VMsnaps.Count - 1].ICloudBlob -Context $Ctx -DestContext $Ctx -DestContainer $ContainerName -DestBlob $backupOSDiskVhd -ConcurrentTaskCount 10 -Force
        #$status | Get-AzureStorageBlobCopyState            
        $osFixDiskblob = Get-AzureStorageAccount -StorageAccountName $storageAccountName | 
        Get-AzureStorageContainer | where {$_.Name -eq $ContainerName} | Get-AzureStorageBlob | where {$_.Name -eq $backupOSDiskVhd -and $_.ICloudBlob.IsSnapshot -ne $true}
        $copiedOSDiskUri =$osFixDiskblob.ICloudBlob.Uri.AbsoluteUri
        Write-host "Took a snapshot of the OS Disk and copied it to  to $copiedOSDiskUri" -Color Green
        return $copiedOSDiskUri
    }
    else
    {
        Write-host "Snapshot copy was unsuccessfull" -Color Red       
    }
}

function DeleteSnapShotAndVhd
(
    [string] $storageAccountName , 
    [string] $osDiskvhd,     
    [string] $ContainerName

    )
{
    $StorageAccountKey = (Get-AzureStorageKey -StorageAccountName $storageAccountName).Secondary
    $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey
    $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where-Object {$_.ICloudBlob.IsSnapshot -and $_.SnapshotTime -ne $null -and $_.Name -eq $osDiskvhd }  
    #Deleting the snapshot
    if ($VMsnaps.Count -gt 0)
    {
        Write-Host "`nWould you like to delete the snapshot ==> $($VMsnaps[$VMsnaps.Count - 1].Name) that was taken at $($VMsnaps[$VMsnaps.Count - 1].SnapshotTime) ?" -ForegroundColor Yellow
        if ((read-host) -eq 'Y')
        {
            $VMsnaps[$VMsnaps.Count - 1].ICloudBlob.Delete()
            Write-Host "Snapshot has been deleted"
        }
    }
    #Deleting the backedupovhd
    $backupOSDiskVhd = "backup$osDiskvhd" 
    $osFixDiskblob = Get-AzureStorageAccount -StorageAccountName $storageAccountName | 
        Get-AzureStorageContainer | where {$_.Name -eq $ContainerName} | Get-AzureStorageBlob | where {$_.Name -eq $backupOSDiskVhd -and $_.ICloudBlob.IsSnapshot -ne $true}
    if ($osFixDiskblob)
    {
        Write-Host "`nWould you like to delete the backed up VHD ==> $($backupOSDiskVhd)  ?" -ForegroundColor Yellow
        if ((read-host) -eq 'Y')
        {
            $osFixDiskblob.ICloudBlob.Delete()
            Write-Host "backupOSDiskVhd has been deleted"
        }
    }
    
}