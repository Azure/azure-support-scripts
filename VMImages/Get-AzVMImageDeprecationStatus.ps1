# https://aka.ms/DeprecatedImagesFAQ
param(
    [string]$resourceGroupName = '*',
    [string]$name = '*',
    [switch]$all,
    [Int16]$displayLimit = 20
)

$scriptStartTime = Get-Date
$scriptFullName = $MyInvocation.MyCommand.Path
$scriptPath = Split-Path -Path $scriptFullName
$scriptName = Split-Path -Path $scriptFullName -Leaf
$scriptBaseName = $scriptName.Split('.')[0]

$instances = New-Object System.Collections.Generic.List[Object]

$scalesets = Get-AzVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $name -ErrorAction SilentlyContinue
$scalesets | ForEach-Object {$instances.Add($_)}

$vms = Get-AzVM -ResourceGroupName $resourceGroupName -Name $name -ErrorAction SilentlyContinue
$vms | ForEach-Object {$instances.Add($_)}

foreach ($instance in $instances)
{
    if ([string]::IsNullOrEmpty($instance.VirtualMachineProfile))
    {
        if (([string]::IsNullOrEmpty($instance.VirtualMachineScaleSet)))
        {
            $instance | Add-Member -MemberType NoteProperty -Name 'Type' -Value 'VM' -Force
        }
        else
        {
            $instance | Add-Member -MemberType NoteProperty -Name 'Type' -Value 'VMSS Instance' -Force
        }
    }
    else
    {
        $instance | Add-Member -MemberType NoteProperty -Name 'Type' -Value 'VMSS' -Force
    }
}

$vmssCount = $instances | Where-Object {$_.Type -eq 'VMSS'} | Measure-Object | Select-Object -ExpandProperty Count
$vmssInstanceCount = $instances | Where-Object {$_.Type -eq 'VMSS Instance'} | Measure-Object | Select-Object -ExpandProperty Count
$vmInstanceCount = $instances | Where-Object {$_.Type -eq 'VM'} | Measure-Object | Select-Object -ExpandProperty Count
$totalInstanceCount = $vmssInstanceCount + $vmInstanceCount
Write-Output "Total Instances $totalInstanceCount VMSS $vmssCount VMSS Instances $vmssInstanceCount VM Instances $vmInstanceCount"

foreach ($instance in $instances)
{
    if ($instance.Type -eq 'VM')
    {
        $instance | Add-Member -MemberType NoteProperty -Name ImageReference -Value $instance.StorageProfile.ImageReference -Force
    }
    elseif ($instance.Type -eq 'VMSS')
    {
        $instance | Add-Member -MemberType NoteProperty -Name ImageReference -Value $instance.VirtualMachineProfile.StorageProfile.ImageReference -Force
    }

    $location = $instance.Location
    $publisher = $instance.ImageReference.Publisher
    $offer = $instance.ImageReference.Offer
    $sku = $instance.ImageReference.Sku
    $version = $instance.ImageReference.Version
    $exactVersion = $instance.ImageReference.ExactVersion
    if ([string]::IsNullOrEmpty($exactVersion))
    {
        $exactVersion = $version
    }

    if ($publisher -and $offer -and $sku -and $exactVersion)
    {
        $imageUrn = "$($publisher):$($offer):$($sku):$($exactVersion)"
        $imageUrn = $imageUrn.ToLower()
        $instance.ImageReference | Add-Member -MemberType NoteProperty -Name ImageUrn -Value $imageUrn -Force -ErrorAction SilentlyContinue
        Write-Output "$($instance.Name.PadRight(15,'.')) $($instance.ImageReference.ImageUrn)"
        Remove-Variable -Name image,imageState,getAzVmImageError -Force -ErrorAction SilentlyContinue
        $image = Get-AzVMImage -Location $location -PublisherName $publisher -Offer $offer -Skus $sku -Version $exactVersion -ErrorVariable getAzVmImageError -ErrorAction SilentlyContinue
        if ($image -and $image.ImageDeprecationStatus)
        {
            $instance | Add-Member -MemberType NoteProperty -Name ImageDeprecationStatus -Value $image.ImageDeprecationStatus -Force -ErrorAction SilentlyContinue
        }
        elseif ($getAzVmImageError)
        {
            $getAzVmImageErrorCode = $getAzVmImageError.Exception.GetBaseException().Response.Content | ConvertFrom-Json | Select-Object -ExpandProperty error | Select-Object -ExpandProperty code
            if ($getAzVmImageErrorCode -and $getAzVmImageErrorCode -eq 'ImageVersionDeprecated')
            {
                $imageState = 'Deprecated'
                $instance | Add-Member -MemberType NoteProperty -Name ImageDeprecationStatus -Value ([PSCustomObject]@{ImageState = $imageState}) -Force -ErrorAction SilentlyContinue
            }
        }

        if ($instance.ImageDeprecationStatus.ScheduledDeprecationTime)
        {
            $scheduledDeprecationTimeISO8601 = Get-Date $instance.ImageDeprecationStatus.ScheduledDeprecationTime -Format 'yyyy-MM-ddTHH:mm:ssZ'
            $instance.ImageDeprecationStatus | Add-Member -MemberType NoteProperty -Name ScheduledDeprecationTime -Value $scheduledDeprecationTimeISO8601 -Force -ErrorAction SilentlyContinue
        }
    }
}
$global:dbgInstances = $instances

$rgName = @{Name = 'RG'; Expression = {$_.ResourceGroupName}}
$imageState = @{Name = 'ImageState'; Expression = {$_.ImageDeprecationStatus.ImageState}}
$scheduledDeprecationTime = @{Name = 'ScheduledDeprecationTime'; Expression = {$_.ImageDeprecationStatus.ScheduledDeprecationTime}}
$alternativeOption = @{Name = 'AlternativeOption'; Expression = {$_.ImageDeprecationStatus.AlternativeOption}}
$imageUrn = @{Name = 'ImageUrn'; Expression = {$_.ImageReference.ImageUrn}}
$instancesWithCalculatedProperties = $instances | Select-Object Type,Name,$rgName,$imageState,$scheduledDeprecationTime,$imageUrn,$alternativeOption | Sort-Object ScheduledDeprecationTime
$instancesWithCalculatedProperties = $instancesWithCalculatedProperties | Where-Object {$_.Type -ne 'VMSS Instance'}
$instancesWithCalculatedPropertiesCount = $instancesWithCalculatedProperties | Measure-Object | Select-Object -ExpandProperty Count
$global:dbgInstancesWithCalculatedProperties = $instancesWithCalculatedProperties

$imageStateActiveInstances = $instancesWithCalculatedProperties | Where-Object ImageState -eq 'Active'
$imageStateActiveInstancesCount = $imageStateActiveInstances | Measure-Object | Select-Object -ExpandProperty Count

$imageStateDeprecatedInstances = $instancesWithCalculatedProperties | Where-Object ImageState -eq 'Deprecated'
$imageStateDeprecatedInstancesCount = $imageStateDeprecatedInstances | Measure-Object | Select-Object -ExpandProperty Count

$imageStateScheduledForDeprecationInstances = $instancesWithCalculatedProperties | Where-Object ImageState -eq 'ScheduledForDeprecation'
$imageStateScheduledForDeprecationInstancesCount = $imageStateScheduledForDeprecationInstances | Measure-Object | Select-Object -ExpandProperty Count

Write-Output "`n$imageStateActiveInstancesCount of $instancesWithCalculatedPropertiesCount instances were created from images where ImageState is Active"
Write-Output "$imageStateDeprecatedInstancesCount of $instancesWithCalculatedPropertiesCount instances were created from images where ImageState is Deprecated"
Write-Output "$imageStateScheduledForDeprecationInstancesCount of $instancesWithCalculatedPropertiesCount instances were created from images where ImageState is ScheduledForDeprecation"

if ($all)
{
    if ($instancesWithCalculatedPropertiesCount -gt $displayLimit)
    {
        Write-Output "`nShowing $displayLimit of $instancesWithCalculatedPropertiesCount instances regardless of image deprecation status (use -displayLimit to show more):"
    }
    else
    {
        Write-Output "`nShowing all instances regardless of image deprecation status:"
    }
    $table = $instancesWithCalculatedProperties | Select-Object -First $displayLimit | Format-Table Type,Name,RG,ImageState,ScheduledDeprecationTime,ImageUrn -AutoSize | Out-String -Width 4096
}
else
{
    if ($imageStateScheduledForDeprecationInstancesCount -gt $displayLimit)
    {
        Write-Output "`nShowing $displayLimit of $imageStateScheduledForDeprecationInstancesCount instances created from images scheduled for deprecation (use -displayLimit to show more, use -all to show all VMs regardless of image deprecation status):"
    }
    else
    {
        Write-Output "`nShowing instances created from images scheduled for deprecation (use -all to show all VMs regardless of image deprecation status):"
    }
    $table = $imageStateScheduledForDeprecationInstances | Select-Object -First $displayLimit | Format-Table Type,Name,RG,ScheduledDeprecationTime,ImageUrn -AutoSize | Out-String -Width 4096
}
$table = "`n$($table.Trim())`n"
Write-Output $table

if ($imageStateScheduledForDeprecationInstancesCount -ge 1 -or ($all -and [string]::IsNullOrEmpty($vms) -eq $false))
{
    $context = Get-AzContext
    $subscriptionId = $context.Subscription.Id

    $fileName = $scriptBaseName
    if ([string]::IsNullOrEmpty($subscriptionId) -eq $false)
    {
        $fileName = [System.String]::Concat($fileName, "-$subscriptionId")
    }
    if ([string]::IsNullOrEmpty($PSBoundParameters['resourceGroupName']) -eq $false)
    {
        $fileName = [System.String]::Concat($fileName, "-$($PSBoundParameters['resourceGroupName'])")
    }
    if ([string]::IsNullOrEmpty($PSBoundParameters['name']) -eq $false)
    {
        $fileName = [System.String]::Concat($fileName, "-$($PSBoundParameters['name'])")
    }

    if (Test-Path -Path $env:HOME -ErrorAction SilentlyContinue)
    {
        $path = $env:HOME
    }
    else
    {
        $path = $PWD
    }

    $csvPath = "$path\$fileName.csv"
    $jsonPath = "$path\$fileName.json"
    $txtPath = "$path\$fileName.txt"
    $zipPath = "$path\imagestate.zip"

    if ($all)
    {
        $instances | Export-Csv -Path $csvPath
        $instances | ConvertTo-Json -Depth 99 | Out-File -FilePath $jsonPath
    }
    else
    {
        $imageStateScheduledForDeprecationInstances | Export-Csv -Path $csvPath
        $imageStateScheduledForDeprecationInstances | ConvertTo-Json -Depth 99 | Out-File -FilePath $jsonPath
    }
    $table | Out-File -FilePath $txtPath

    Write-Output "Writing output to $path`n"

    if (Test-Path -Path $csvPath -PathType Leaf)
    {
        Write-Output " CSV: $csvPath"
        Get-ChildItem -Path $csvPath | Compress-Archive -DestinationPath $zipPath -Update
    }
    if (Test-Path -Path $jsonPath -PathType Leaf)
    {
        Write-Output "JSON: $jsonPath"
        Get-ChildItem -Path $jsonPath | Compress-Archive -DestinationPath $zipPath -Update
    }
    if (Test-Path -Path $csvPath -PathType Leaf)
    {
        Write-Output " TXT: $txtPath"
        Get-ChildItem -Path $txtPath | Compress-Archive -DestinationPath $zipPath -Update
    }
    if (Test-Path -Path $zipPath -PathType Leaf)
    {
        $zipName = Split-Path -Path $zipPath -Leaf
        Write-Output "`n ZIP: $zipPath"
        if ($env:AZD_IN_CLOUDSHELL)
        {
            Write-Output "`nTo download '$zipName' from cloud shell, select 'Manage Files', 'Download', then enter '$zipName' in the required field, then click 'Download'"
        }
    }
}

$scriptTimespan = New-TimeSpan -Start $scriptStartTime -End (Get-Date)
$scriptSeconds = [Math]::Round($scriptTimespan.TotalSeconds, 1)
Write-Output "`n$($scriptSeconds)s"
