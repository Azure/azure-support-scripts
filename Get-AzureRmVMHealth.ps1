param(
    [string]$resourceGroupName,
    [string]$name,
    [string]$path,
    [switch]$openJsonFile = $true
)

function Get-JsonFromSerialLog ($serialLogFilePath)
{    
    $serialLogFileName = split-path -Path $serialLogFilePath -Leaf
    $jsonFileName = "$($serialLogFileName.SubString(0,$serialLogFileName.Length-4)).json"
    $jsonFilePath = "$env:TEMP\$jsonFileName"
    $serialLog = get-content -Path $serialLogFilePath
    for ($i = ($serialLog.count); $i -ne 0; $i--) {
        if ($serialLog[$i] -match 'Microsoft Azure VM Health Report - End') 
        {
            $jsonString = $serialLog[$i-1]        
            try
            {
                $json = $jsonString | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            catch
            {
                write-verbose "ConvertFrom-Json failed, will try next entry"
                $i--
            }
            if ($json) {break}
        }
    }
    
    if ($json){$json | ConvertTo-Json -Depth 99 | out-file $jsonFilePath}
    if (test-path $jsonFilePath)
    {
        get-content $jsonFilePath
        "VM Health JSON: $jsonFilePath"
        if ($openJsonFile)
        {
            invoke-item $jsonFilePath
        }
    }
    else 
    {
        write-host "No VM Health Report entries found."
    }
}

if ($resourceGroupName -and $name)
{
    $vm = get-azurermvm -ResourceGroupName $resourceGroupName -Name $name -ErrorAction Stop
    $vmstatus = $vm | get-azurermvm -status -ErrorAction Stop

    if ($vm.DiagnosticsProfile.Bootdiagnostics.Enabled)
    {
        if ($vmstatus.bootdiagnostics.ConsoleScreenshotBlobUri)
        {
            $consoleScreenshotBlobUri = $vmstatus.bootdiagnostics.ConsoleScreenshotBlobUri
        }
        else
        {
            "ConsoleScreenshotBlobUri property not populated"
            exit
        }
    }
    else
    {
        "Bootdiagnostics: $($vm.DiagnosticsProfile.Bootdiagnostics.Enabled)"
        exit
    }

    $storageAccountName = $consoleScreenshotBlobUri.split('/')[2].split('.')[0]
    $storageContainer = $consoleScreenshotBlobUri.split('/')[3]
    #TODO If boot diag storage account can reside in a different RG than the VM's RG, need a different way to get the RG of the boot diag storage account
    $storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey (Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName)[0].Value
    $blobs = get-azurestorageblob -Container $storageContainer -Context $storageContext
    $log = $blobs | where {$_.Name.EndsWith('.serialconsole.log')} | select -first 1    
    $log | Get-AzureStorageBlobContent -Destination $env:TEMP -Force | Out-Null
    $logFilePath = "$env:TEMP\$($log.Name)"
    Get-JsonFromSerialLog $logFilePath
    "serial log:     $logFilePath"    
}
elseif ($path)
{
    if (test-path $path)
    {
        Get-JsonFromSerialLog $path
    }
    else 
    {
        Write-Error "File not found: $path"    
        exit
    }
}
else 
{
    write-error "Use -resourceGroupName and -name to download the log, or -path to parse output from log already downloaded."
    exit
}
