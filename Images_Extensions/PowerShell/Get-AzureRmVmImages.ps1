param (
    $location = 'westus',
    [switch]$csv = $false,
    [switch]$xlsx = $false
)

$start = Get-Date

$images = New-Object System.Collections.ArrayList


try 
{
  Get-AzureRmSubscription *> null
}
catch 
{
  Login-AzureRmAccount
}

$publishers = ( Get-AzureRmVMImagePublisher -Location $location ).PublisherName

$publishers | foreach {
	
	$publisher = $_
	$offers = ( Get-AzureRmVMImageOffer -Location $location -PublisherName $publisher ).Offer

	if (($offers | measure ).count -gt 0)
	{
		$offers | foreach {

			$offer = $_
			$skus = (Get-AzureRmVMImageSku -Location $location -PublisherName $publisher -Offer $offer).Skus

			if (($skus | measure ).count -gt 0)
			{
				$skus | foreach {

					$sku = $_
					$versions = (get-azurermvmimage -Location $location -PublisherName $publisher -Offer $offer -Skus $sku).Version

					if (($versions | measure ).count -gt 0)
					{
						$versions | foreach {

							$version = $_
							$image = Get-AzureRmVMImage -Location $location -PublisherName $publisher -Offer $offer -Skus $sku -Version $version							
							[void]$images.Add($image)
							"PublisherName: $($image.PublisherName) Offer: $($image.offer) Sku: $($image.sku) Version: $($image.version)"
						}
					}
				}
			}
		}
	}
}

$numImagesByPublishers = New-Object System.Collections.ArrayList

$images.publishername | sort -Unique | foreach {
	$publisher = $_
	$numPublisherImages = ($images | where {$_.PublisherName -eq $publisher}).count
	$numMarketplacePublisherImages = ($images | where {$_.PurchasePlan -ne $null -and $_.PublisherName -eq $publisher}).count
	$numPlatformPublisherImages = ($images | where {$_.PurchasePlan -eq $null -and $_.PublisherName -eq $publisher}).count
	$numImagesByPublisher = [pscustomobject]@{
		PublisherName = $publisher
		TotalImages = $numPublisherImages
		MarketplaceImages = $numMarketplacePublisherImages
		PlatformImages    = $numPlatformPublisherImages
	}
	[void]$numImagesByPublishers.Add($numImagesByPublisher)
}
	
$numPublishers               = $publishers.count 
$numMarketplaceImages        = ($images | where {$_.PurchasePlan -ne $null}).count
$numMarketplaceImagesLinux   = ($images | where {$_.PurchasePlan -ne $null -and $_.OSDiskImage.OperatingSystem -eq 'Linux'}).count
$numMarketplaceImagesWindows = ($images | where {$_.PurchasePlan -ne $null -and $_.OSDiskImage.OperatingSystem -eq 'Windows'}).count
$numPlatformImages           = ($images | where {$_.PurchasePlan -eq $null}).count
$numPlatformImagesLinux      = ($images | where {$_.PurchasePlan -eq $null -and $_.OSDiskImage.OperatingSystem -eq 'Linux'}).count
$numPlatformImagesWindows    = ($images | where {$_.PurchasePlan -eq $null -and $_.OSDiskImage.OperatingSystem -eq 'Windows'}).count
$numTotalImages              = $images.count
$numTotalLinuxImages         = ($images | where {$_.OSDiskImage.OperatingSystem -eq 'Linux'}).count
$numTotalWindowsImages       = ($images | where {$_.OSDiskImage.OperatingSystem -eq 'Windows'}).count

"Total Images ................... $numTotalImages"
"  Total Linux Images ........... $numTotalLinuxImages"
"  Total Windows Images ......... $numTotalWindowsImages"
"Marketplace Images ............. $numMarketplaceImages"	
"  Linux Marketplace Images ..... $numMarketplaceImagesLinux"
"  Windows Marketplace Images ... $numMarketplaceImagesWindows"
"Platform Images ................ $numPlatformImages"
"  Linux Platform Images ........ $numPlatformImagesLinux"
"  Windows Platform Images ...... $numPlatformImagesWindows"

"`nTotal Publishers: $numPublishers"

$numImagesByPublishers | sort TotalImages -Descending | Format-Table -AutoSize

if ($csv)
{
	$output = '.\images.csv'
	$images | select PublisherName,Offer,Skus,Version,Name,@{Name='OSDiskImage';Expression={$_.OSDiskImage | convertto-json}},@{Name='PurchasePlan';Expression={$_.PurchasePlan | convertto-json}},@{Name='DataDiskImages';Expression={$_.DataDiskImages | convertto-json}},Id,Location,FilterExpression | Export-Csv -path $output -NoTypeInformation
    "CSV output: $((get-childitem $output).fullname)`n"
}

if ($xlsx)
{
    if (get-command Export-Excel -ErrorAction SilentlyContinue)
    {
	    $output = '.\images.xlsx'
	    $images | select PublisherName,Offer,Skus,Version,Name,@{Name='OSDiskImage';Expression={$_.OSDiskImage | convertto-json}},@{Name='PurchasePlan';Expression={$_.PurchasePlan | convertto-json}},@{Name='DataDiskImages';Expression={$_.DataDiskImages | convertto-json}},Id,Location,FilterExpression | Export-Excel $output -AutoSize
        "XLSX output: $((get-childitem $output).fullname)`n"
    }
    else
    {
        if ($host.version.Major -ge 5)
        {
            Write-Host "Export-Excel cmdlet not found. To install, run: `n`nInstall-Module -Name ImportExcel`n" -ForegroundColor Cyan
            Write-Host "For more information see https://github.com/dfinke/ImportExcel`n" -ForegroundColor Cyan
        }
        else
        {
            Write-Host "Export-Excel cmdlet not found. To install, run:`n`niex (new-object System.Net.WebClient).DownloadString('https://raw.github.com/dfinke/ImportExcel/master/Install.ps1')`n" -ForegroundColor Cyan
            Write-Host "For more information see https://github.com/dfinke/ImportExcel`n" -ForegroundColor Cyan
        }
    }
}

$end = Get-Date
$duration = New-Timespan -Start $start -End $end
Write-Host ('Script Duration: ' +  ('{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f $duration))
