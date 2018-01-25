function AttachOsDiskAsDataDiskToRecoveryVm   (
    [string] $ServiceName , 
    [string] $VName ,    
    [string] $RecoveryAdmin = 'recoveryAdmin',
    [string] $RecoveryPW = [guid]::NewGuid().ToString()
    )
{
    $RecoveryVMName = 'RC' + $(get-date -f yyMMddHHmm)    

    #get defect vm object and export cfg to disk (temp)
    try
    {
        $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName -ErrorAction Stop
    }
    catch
    {
        write-host "Specified VM ==> $vm was not found in the cloud service ==> $ServiceName, possibly it no longer exist" -ForegroundColor Red
        write-host  "Exception Message: $($_.Exception.Message)"
        return $null
    }
    $osDiskvhd = $vm.VM.OSVirtualHardDisk.MediaLink.AbsolutePath.split('/')[-1]
    $osDiskVhdUri = $vm.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri
    $location = (Get-AzureService -ServiceName $ServiceName).Location

    Try
    {
        #https://github.com/Azure/azure-powershell/pull/2050 bug
        #export vm cfg to temp dir for later exact recreation (disk,net settings)
        $VMExportPath = $env:TEMP + '\' + $vm.VM.OSVirtualHardDisk.DiskName + '.xml'

        $vm | Export-AzureVM -Path $VMExportPath -ErrorAction Stop
        Write-Host 'Original VM Configuration written to ' $VMExportPath 

        Write-host 'Creating VM (may take a few minutes)'
    
        #get storage account name from current os disk url
        $SAName = $vm.VM.OSVirtualHardDisk.MediaLink.Authority.Split(".")[0] 

        #set current sa to be os disk sa -> will create reco vhd on same sa
        $Sub = Get-AzureSubscription -Current -ErrorAction stop
        Set-AzureSubscription -CurrentStorageAccountName $SAName -SubscriptionId $sub.SubscriptionId -ErrorAction Stop
    
        if ( $vm.VM.OSVirtualHardDisk.OS -eq 'Windows' )
        {
            #$RecoveryImage =  Get-AzureVMImage |where ImageFamily -eq 'Windows Server 2012 R2 Datacenter'  | sort PublishedDate -Descending | select  -First 1 
            $RecoveryImage =  Get-AzureVMImage |where ImageFamily -eq 'Windows Server 2016 Datacenter'  | sort PublishedDate -Descending | select  -First 1
            write-host "Running New-AzureQuickVM -Windows -WaitForBoot -ServiceName `"$ServiceName`" -Name `"$RecoveryVMName`" -InstanceSize $($vm.InstanceSize) -AdminUsername `"$RecoveryAdmin`" -Password `"$RecoveryPW`" -ImageName $($RecoveryImage.ImageName) -EnableWinRMHttp -ErrorAction stop -WarningAction SilentlyContinue"
            $recoveryVM = New-AzureQuickVM -Windows -WaitForBoot -ServiceName $ServiceName -Name $RecoveryVMName -InstanceSize $vm.InstanceSize -AdminUsername $RecoveryAdmin -Password $RecoveryPW -ImageName $RecoveryImage.ImageName -EnableWinRMHttp -ErrorAction stop -WarningAction SilentlyContinue
        }
        else
        {
            #$ImageObj = (get-azurermvmimage -Location $location -PublisherName 'Canonical' -Offer 'UbuntuServer' -Skus '16.04-LTS')[-1]
            $RecoveryImage =  Get-AzureVMImage |where ImageFamily -eq 'Ubuntu Server 16.04 LTS'  | sort PublishedDate -Descending | select  -First 1
            Write-host "Running New-AzureQuickVM -Linux -WaitForBoot -ServiceName `"$ServiceName`" -Name `"$RecoveryVMName`" -InstanceSize $($vm.InstanceSize) -LinuxUser `"$RecoveryAdmin`" -Password `"$RecoveryPW`" -ImageName $($RecoveryImage.ImageName) -ErrorAction stop -WarningAction SilentlyContinue"
            $recoveryVM = New-AzureQuickVM -Linux -WaitForBoot -ServiceName $ServiceName -Name $RecoveryVMName -InstanceSize $vm.InstanceSize -LinuxUser $RecoveryAdmin -Password $RecoveryPW -ImageName $RecoveryImage.ImageName -ErrorAction stop -WarningAction SilentlyContinue
        }
        $recoveryVM = Get-AzureVM -ServiceName $ServiceName -Name $RecoveryVMName 
        #Before removing faulty VM checks to see if the recovery VM was created.
        if (-not $recoveryVM)
        {
            write-host "Recovery VM was not created" -ForegroundColor Red
            return
        }
        Write-Host 'Recovery VM' $RecoveryVMName 'was created with credentials' $RecoveryAdmin $RecoveryPW 
    }
    catch
    {
        Write-Host "Unable to create the Rescue VM $($RecoveryVMName), plese see the error below" -ForegroundColor Red
        write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
        Write-host "Error in Line# : $($_.Exception.Line) =>  $($MyInvocation.MyCommand.Name)" -ForegroundColor Red
        return $null
    }

    Write-host 'Removing faulty vm and attaching its os disk as data disk to recovery vm'
    #create new recovery in size of the defect vm (will create premium storage vm if needed)
    #once the recovery vm has booted in the same cloud service (to prevent VIP loss) we get rid of the defect vm (but keep disks)
    write-host "Script will now remove the $VMName, however it has captured the VM properties here $($VMExportPath) file, this file could be used to recreate the VM as long as $($osDiskVhdUri) is not attached to any other VM" 
    Remove-AzureVm -ServiceName $ServiceName -Name $VMName 


    Write-Output "Waiting for the disk  to be released" + $vm.VM.OSVirtualHardDisk.DiskName
    do
    {
        Start-Sleep -Seconds 15 | Out-Null
    }while ( (get-azuredisk $vm.VM.OSVirtualHardDisk.DiskName | select -ExpandProperty AttachedTo ) -ne $null)

    #than we try to add the, if it fails we provide suggestion as to how to restore back to its original state. 
    $recoveryVM = Get-AzureVM -ServiceName $ServiceName -Name $RecoveryVMName
    try 
    {
        $recoveryVM | Add-AzureDataDisk -Import -DiskName $vm.VM.OSVirtualHardDisk.DiskName  -LUN 0 -ErrorAction Stop | Update-AzureVM -ErrorAction Stop
    }
    catch
    {
       write-host "Failed to attach the OS disk as a Datadisk, you should still be able to use the os disk $($osDiskVhdUri) and the $($VMExportPath) file to restore the VM back to its original state" -ForegroundColor red
       write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
       Write-host "`n`nRun the following to restore the VM back to its original state`n" -ForegroundColor Yellow
       Write-host "`nRun the following two statements to restore the VM back to its original state`n" -ForegroundColor Yellow
       Write-host "`$origvm = Import-AzureVM -Path `"$VMExportPath`"" 
       Write-host "New-AzureVM -ServiceName `"$ServiceName`" -VMs `$origvm -Location `"$location`" -WaitForBoot"
       return $null
    }
        

    return $recoveryVM.VM
}