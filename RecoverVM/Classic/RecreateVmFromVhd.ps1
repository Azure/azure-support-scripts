function RecreateVmFromVhd (
    [string] $ServiceName,
    [string] $RecoVmName,
    [bool] $DeleteRecoVM
    )
{
    
    $attachedVm = Get-AzureVM -ServiceName $ServiceName -Name $RecoVmName
    $location = (Get-AzureService -ServiceName $ServiceName).Location
    if ( $attachedVm.VM.DataVirtualHardDisks.Count -eq 0 )
    {
        Write-Error "No data disk attached to recover vm $RecoVmName unable to proceed!"
        return
    }

    $OSDisk = $attachedVm.VM.DataVirtualHardDisks[0]

    #get storage account name from current data disk url
    $SAName =  $OSDisk.MediaLink.Authority.Split(".")[0]

    #set current sa to be os disk sa -> will create reco vhd on same sa
    $Sub = Get-AzureSubscription -Current 
    Set-AzureSubscription -CurrentStorageAccountName $SAName -SubscriptionId $sub.SubscriptionId
    
    #detach the data disk     
    $attachedVm | Remove-AzureDataDisk -LUN 0 | Update-AzureVM
    Start-Sleep -Seconds 45
    
    #import vm cfg from temp dir for later exact recreation (disk,net settings)
    $VMExportPath = $env:TEMP + '\' + $OSDisk.DiskName  + '.xml'

    try
    {

        if ( Test-Path -Path $VMExportPath  )  
        {
            $vm = Import-AzureVM   -Path $VMExportPath    
        }
        else
        {
          throw 'no vm export found ... using defaults'   
        }

    }
    catch
    {     
        #default values only used when vm export path can not be imported as vm
        $VMSize = $vm.VM.RoleSize
        $PublicRdpPort = 3389
        $SubNetNames = '' #"PubSubnet","PrivSubnet" #leave empty if not required
        $DataDiskNames = $null #'vm-disk-data-1'. 'vm-disk-data-1' #leave empty if not required
        #try to re-extract vm name from disk name flowing convention svcname-vm-name-os-date (need 2nd item of "-"split or 1st if custom)
        $DiskNameParts = $OSDisk.DiskName.Split("-")
        if ( $DiskNameParts.Count > 1 )
        {
            $VMName = $DiskNameParts[1]
        }
        else
        {
            $VMName = $DiskNameParts[0]
        }        
        ###################################################################################################################

        #prepare the 
        $vm = New-AzureVMConfig -Name $VMName -InstanceSize $VMSize -DiskName $OSDiskName

        #Attached the data disks to the new VM (not executed by default)
        foreach ($dataDiskName in $DataDiskNames)
        {    
            $vm | Add-AzureDataDisk -DiskName $DataDiskName
        } 

        # Edit this if you want to add more custimization to the new VM
        $vm | Add-AzureEndpoint -Protocol tcp -LocalPort 3389 -PublicPort $PublicRdpPort -Name 'Rdp'
        if ( ! [string]::IsNullOrEmpty($SubNetNames ))
        {
            $vm | Set-AzureSubnet $SubNetNames
        }
    }

    New-AzureVM -ServiceName $ServiceName -VMs $vm -Location $location -WaitForBoot
    if ( $attachedVm )
    {        
        if ( $DeleteRecoVM)
        {
            Remove-AzureVM -ServiceName $ServiceName -Name $RecoVmName -DeleteVHD
        }
    }
}

