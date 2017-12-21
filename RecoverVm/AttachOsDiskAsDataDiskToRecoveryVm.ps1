function AttachOsDiskAsDataDiskToRecoveryVm   (
    [string] $ServiceName , 
    [string] $VName ,    
    [string] $RecoveryAdmin = 'recoveryAdmin',
    [string] $RecoveryPW = [guid]::NewGuid().ToString()
    )
{
    $RecoveryVMName = 'RC' + $(get-date -f yyMMddHHmm)    

    #get defect vm object and export cfg to disk (temp)
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName

    if ( ! $vm ) 
    {
        return
    }

    #https://github.com/Azure/azure-powershell/pull/2050 bug
    #export vm cfg to temp dir for later exact recreation (disk,net settings)
    $VMExportPath = $env:TEMP + '\' + $vm.VM.OSVirtualHardDisk.DiskName + '.xml'

    $vm | Export-AzureVM -Path $VMExportPath
    Write-Host 'Original VM Configuration written to ' $VMExportPath -ForegroundColor Yellow

    Write-host 'Creating VM (may take a few minutes)'
    
    #get storage account name from current os disk url
    $SAName = $vm.VM.OSVirtualHardDisk.MediaLink.Authority.Split(".")[0]   

    #set current sa to be os disk sa -> will create reco vhd on same sa
    $Sub = Get-AzureSubscription -Current 
    Set-AzureSubscription -CurrentStorageAccountName $SAName -SubscriptionId $sub.SubscriptionId
    
    if ( $vm.VM.OSVirtualHardDisk.OS -eq 'Windows' )
    {
        $RecoveryImage =  Get-AzureVMImage |where ImageFamily -eq 'Windows Server 2012 R2 Datacenter'  | sort PublishedDate -Descending | select  -First 1
        $recoveryVM = New-AzureQuickVM -Windows -WaitForBoot -ServiceName $ServiceName -Name $RecoveryVMName -InstanceSize $vm.InstanceSize -AdminUsername $RecoveryAdmin -Password $RecoveryPW -ImageName $RecoveryImage.ImageName -EnableWinRMHttp
    }
    else
    {
        $RecoveryImage =  Get-AzureVMImage |where ImageFamily -eq 'Ubuntu Server 14.04 LTS'  | sort PublishedDate -Descending | select  -First 1
        $recoveryVM = New-AzureQuickVM -Windows $false -WaitForBoot -ServiceName $ServiceName -Name $RecoveryVMName -InstanceSize $vm.InstanceSize -AdminUsername $RecoveryAdmin -Password $RecoveryPW -ImageName $RecoveryImage.ImageName -EnableWinRMHttp
    }
    Write-Host 'Recovery VM' $RecoveryVMName 'was created with credentials' $RecoveryAdmin $RecoveryPW 

    Write-host 'Removing faulty vm and attaching its os disk as data disk to recovery vm'
    #create new recovery in size of the defect vm (will create premium storage vm if needed)
    #once the recovery vm has booted in the same cloud service (to prevent VIP loss) we get rid of the defect vm (but keep disks)
    Remove-AzureVm -ServiceName $ServiceName -Name $VMName 

    Write-Output "Waiting for the disk  to be released" + $vm.VM.OSVirtualHardDisk.DiskName
    do
    {
        Start-Sleep -Seconds 15 | Out-Null
    }while ( (get-azuredisk $vm.VM.OSVirtualHardDisk.DiskName | select -ExpandProperty AttachedTo ) -ne $null)

    #than we try to add the 
    $recoveryVM = Get-AzureVM -ServiceName $ServiceName -Name $RecoveryVMName
    $recoveryVM | Add-AzureDataDisk -Import -DiskName $vm.VM.OSVirtualHardDisk.DiskName  -LUN 0 | Update-AzureVM 
        

    return $recoveryVM.VM
}