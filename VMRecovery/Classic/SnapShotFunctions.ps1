function TakeSnapshotofOSDisk (
    [string] $storageAccountName , 
    [string] $StorageAccountKey,
    [string] $ContainerName,
    [string]$osDiskvhd
     
    )
{
    try
    {
        $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName -ErrorAction Stop

        if ( ! $vm ) 
        {
            return
        }
        #As per PR taking a snapshot of the OS disk first.
        $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey 
        $VMblob = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where-Object {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -ne $true} -ErrorAction Stop

        #Create a snapshot of the OS Disk
        Write-host "Running CreateSnapshot operation" 
        $snap = $VMblob.ICloudBlob.CreateSnapshot() 
        if ($snap)
        {
            Write-host "Successfully completed CreateSnapshot operation" -ForegroundColor Green
        }

        Write-host "Initiating Copy proccess of Snapshot" 
        #Save array of all snapshots
        $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Sort-Object @{expression="SnapshotTime";Descending=$true} | Where-Object {$_.Name -eq $osDiskvhd -and $_.ICloudBlob.IsSnapshot -and $null -ne $_.SnapshotTime } 

        #Copies the LatestSnapshot of the OS Disk as a backup prior to making any changes to the OS Disk to the same storage account and prefixing with Backup
        if ($VMsnaps.Count -gt 0)
        {   
            $backupOSDiskVhd = "backup$osDiskvhd" 
            $status = Start-AzureStorageBlobCopy -CloudBlob $VMsnaps[0].ICloudBlob -Context $Ctx -DestContext $Ctx -DestContainer $ContainerName -DestBlob $backupOSDiskVhd -ConcurrentTaskCount 10 -Force -ErrorAction Stop
            #$status | Get-AzureStorageBlobCopyState            
            $osFixDiskblob = Get-AzureStorageAccount -StorageAccountName $storageAccountName | 
            Get-AzureStorageContainer | Where-Object {$_.Name -eq $ContainerName} | Get-AzureStorageBlob | Where-Object {$_.Name -eq $backupOSDiskVhd -and $_.ICloudBlob.IsSnapshot -ne $true} -ErrorAction Stop
            $copiedOSDiskUri =$osFixDiskblob.ICloudBlob.Uri.AbsoluteUri
            Write-host "Took a snapshot of the OS Disk and copied it to  to $copiedOSDiskUri" -ForegroundColor Green
            return $copiedOSDiskUri
        }
        else
        {
            Write-host "Snapshot copy was unsuccessful" -ForegroundColor Red       
        }
    }
    catch
    {
        write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
        Write-host "Error in Line# : $($_.Exception.Line) =>  $($MyInvocation.MyCommand.Name)" -ForegroundColor Red
        return $false
    }
}

function DeleteSnapShotAndVhd
(
    [string] $storageAccountName , 
    [string] $osDiskvhd,     
    [string] $ContainerName

    )
{
    try
    {
        $StorageAccountKey = (Get-AzureStorageKey -StorageAccountName $storageAccountName).Secondary 
        $Ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey -ErrorAction Stop
        $VMsnaps = Get-AzureStorageBlob –Context $Ctx -Container $ContainerName | Where-Object {$_.ICloudBlob.IsSnapshot -and $null -ne $_.SnapshotTime -and $_.Name -eq $osDiskvhd }  -ErrorAction Stop
        #Deleting the snapshot
        if ($VMsnaps.Count -gt 0)
        {
            Write-Host "`nWould you like to delete the snapshot ==> $($VMsnaps[$VMsnaps.Count - 1].Name) that was taken at $($VMsnaps[$VMsnaps.Count - 1].SnapshotTime) (Y/N) ?" 
            if ((read-host) -eq 'Y')
            {
                $VMsnaps[$VMsnaps.Count - 1].ICloudBlob.Delete()
                Write-Host "Snapshot has been deleted"
            }
        }
        #Deleting the backedupovhd
        $backupOSDiskVhd = "backup$osDiskvhd" 
        $osFixDiskblob = Get-AzureStorageAccount -StorageAccountName $storageAccountName | 
            Get-AzureStorageContainer | Where-Object {$_.Name -eq $ContainerName} | Get-AzureStorageBlob | Where-Object {$_.Name -eq $backupOSDiskVhd -and $_.ICloudBlob.IsSnapshot -ne $true} -ErrorAction Stop
        if ($osFixDiskblob)
        {
            Write-Host "`nWould you like to delete the backed up VHD ==> $($backupOSDiskVhd) (Y/N) ?" 
            if ((read-host) -eq 'Y')
            {
                $osFixDiskblob.ICloudBlob.Delete()
                Write-Host "backupOSDiskVhd has been deleted"
            }
        }
    }
    catch
    {
        write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
        Write-host "Error in Line# : $($_.Exception.Line) =>  $($MyInvocation.MyCommand.Name)" -ForegroundColor Red
        return $false
    }
}