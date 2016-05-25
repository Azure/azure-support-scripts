function RunRepairDataDiskFromRecoveryVm  (
    [string] $ServiceName,
    [string] $RecoVmName,
    [string] $GuestRecoveryScriptUri = 'https://raw.githubusercontent.com/sebdau/azpstools/master/FixDisk/TS_RecoveryWorker2.ps1',
    [string] $GuestRecoveryScript= "TS_RecoveryWorker2.ps1"
    )
{
    Add-Type -AssemblyName System.Web

    $VM = get-azurevm $ServiceName  $RecoVmName

    if ( $VM.VM.OSVirtualHardDisk.OS -eq "Windows")
    {     

        $temp = $vm | Set-AzureVMCustomScriptExtension -FileUri $GuestRecoveryScriptUri  -Run $GuestRecoveryScript | Update-AzureVM 
        
        $lastOutput =""

        do
        {            
            $VM = get-azurevm $ServiceName  $RecoVmName
            $csStatus = $vm.ResourceExtensionStatusList | where HandlerName -EQ 'Microsoft.Compute.CustomScriptExtension' | select -ExpandProperty ExtensionSettingStatus
            if ( $csStatus.Status -eq  'Error' )
            {
                Write-Error ($csStatus.SubStatusList | where Name -EQ 'StdErr' | select -ExpandProperty FormattedMessage | select -ExpandProperty Message)                
                $exit = $true
            }
            elseif ( ($csStatus.Status -eq 'Ready') -or ($csStatus.Status -eq 'Success'))
            {
                $exit = $true    
                Write-Output "Custom script execution completed"                            
            }
            else
            {        
                $exit = $false                       
                Write-Output "Custom script executing - next update in 15 secs"
                Start-Sleep -Seconds 15 | Out-Null                
            }          
            
            $outMsg = $csStatus.SubStatusList | where Name -EQ 'StdOut' | select -ExpandProperty FormattedMessage | select -ExpandProperty Message
            $outMsg = [System.Web.HttpUtility]::HtmlDecode($outMsg)
            $outMsg = $outMsg -replace "\\n","`n"
            if ( $outMsg -ne $lastOutput)
            {                
                Write-Output $outMsg
                $lastOutput = $outMsg
            }

        }until ($exit)
    }
    else
    {
        Write-Host "Linux guest os recovery scripting not enabled yet"
        Write-Host "Please ssh into the recovery vm yourself and fix the attached data disk: see step 22..."
        Write-host "https://blogs.msdn.microsoft.com/mast/2014/11/20/recover-azure-vm-by-attaching-os-disk-to-another-azure-vm/"
        Read-Host -Prompt "press any key once done to continue with recreation"
    }
}

RunRepairDataDiskFromRecoveryVm sebdau-sdp3 RC1605031631