param (
    $location = 'westus',
    [switch]$csv = $false,
    [switch]$xlsx = $false
)

$start = Get-Date

$extensions = New-Object System.Collections.ArrayList


try 
{
  Get-AzSubscription *> null
}
catch 
{
  Connect-AzAccount
}

$publishers = ( Get-AzVMImagePublisher -Location $location ).PublisherName

$publishers | ForEach-Object {
	
    $publisher = $_

    $publisherExtensions = Get-AzVMExtensionImageType -Location $location -PublisherName $publisher	
    
	if (($publisherExtensions | Measure-Object ).count -gt 0)
	{
		$publisherExtensions | ForEach-Object {

			$publisherExtension = $_.Type
			$publisherExtensionVersions = Get-AzVMExtensionImage -Location $location -PublisherName $publisher -Type $publisherExtension            

			if (($publisherExtensionVersions | Measure-Object ).count -gt 0)
			{
				$publisherExtensionVersions | ForEach-Object {

					$publisherExtensionVersion = $_
                    [void]$extensions.Add($publisherExtensionVersion)                    
                    Write-Host "PublisherName: $($publisherExtensionVersion.PublisherName) Type: $($publisherExtensionVersion.Type) Version: $($publisherExtensionVersion.Version)"
				}
			}
		}
	}
}

$numExtensionsByPublishers = New-Object System.Collections.ArrayList

$extensions.PublisherName | Sort-Object -Unique | ForEach-Object {
	$publisher = $_
	$numPublisherExtensions = ($extensions | Where-Object {$_.PublisherName -eq $publisher}).count
	$numExtensionsByPublisher = [pscustomobject]@{
		PublisherName = $publisher
		Extensions = $numPublisherExtensions
	}
	[void]$numExtensionsByPublishers.Add($numExtensionsByPublisher)
}
	
$numPublishers      = $publishers.count 
$numTotalExtensions = $extensions.count

"Total Publishers: $numPublishers"	
"Total Extensions: $numTotalExtensions"	

$numExtensionsByPublishers | Sort-Object Extensions -Descending | format-table -AutoSize

if ($csv)
{
	$output = '.\extensions.csv'
	$extensions | Select-Object PublisherName,Type,Version,id | Export-Csv -path $output -NoTypeInformation
    "CSV output: $((get-childitem $output).fullname)`n"
}

if ($xlsx)
{
    if (get-command Export-Excel -ErrorAction SilentlyContinue)
    {
	    $output = '.\extensions.xlsx'
	    $extensions | Select-Object PublisherName,Type,Version,id | Export-Excel $output -AutoSize
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
