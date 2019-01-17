<#
.SYNOPSIS

    Creates VMs using AzureRM cmdlets:

    1. Creates 1 VM each from the commonly used Marketplace images for Windows and Linux (default if no params passed)
    2. -linux creates a single Linux VM (Ubuntu 18.04 LTS)
    3. -windows creates a single Windows VM (Windows Server 2016)
    4. -linuxVMsonly creates 1 VM each from the commonly used Linux marketplace images
    5. -windowsVMsonly creates 1 VM each from the commonly used Windows marketplace images
    6.

    - -

    Or creates a single Windows VM, or a single Linux VM, or a s

    TODO: Have -confirm show what will be created and prompt to continue or not
    TODO: Allow enabling auto-shutdown policy
    TODO: Allow enabling backup
    TODO: Output summary of what was created at the end

.DESCRIPTION

    Script defaults:

    - VMs are created in the same resource group. Use -useSingleResourceGroup:$false to instead have them created each in their own resource group.
    - VMs are created in the same storage account. Use -useSingleStorageAccount:$false to instead have them created each in their own storage account.
    - VMs are created with unmanaged disks. Use -useManagedDisk to use managed disks instead.
    - Standard_A1_v2 is the size used by default. Use -vmSize to specify a different size. To view available sizes run Get-AzureRmVMSize -Location <location>.
    - Names for the VMs, resource groups, and storage accounts is handled automatically by the script and there is currently no parameter to control that.

    The script creates one VM from each of the following images:

    MicrosoftWindowsServer.WindowsServerSemiAnnual.Datacenter-Core-1803-with-Containers-smalldisk
    MicrosoftWindowsServer.WindowsServer.2016-Datacenter-smalldisk
    MicrosoftWindowsServer.WindowsServer.2012-R2-Datacenter-smalldisk
    MicrosoftWindowsServer.WindowsServer.2012-Datacenter-smalldisk
    MicrosoftWindowsServer.WindowsServer.2008-R2-SP1-smalldisk
    MicrosoftWindowsDesktop.Windows-10.RS3-Pro
    MicrosoftVisualStudio.Windows.Win7-SP1-Ent-N-x64
    MicrosoftVisualStudio.Windows.Win81-Ent-N-x64

    new -resourceGroupName test -vmName rs1 -publisher MicrosoftWindowsServer -offer WindowsServer -skus 2016-Datacenter-smalldisk

    Canonical.UbuntuServer.18.04-LTS
    CoreOS.CoreOS.Stable
    credativ.Debian.9
    OpenLogic.CentOS.7.4
    Oracle.Oracle-Linux.7.4
    RedHat.RHEL.7.3
    SUSE.SLES.12-SP3
    SUSE.openSUSE-Leap.42.3

.PARAMETER userName
Username to be used for guest OS admin account.

.PARAMETER password
Password to be used for guest OS admin account.

.PARAMETER location
Azure region where you want the VMs to be created.

.PARAMETER useManagedDisk
Specified that VMs be created with managed disks instead of unmanaged. Unmanaged is the script default.

.PARAMETER vmSize
VM size to use when creating the VMs. Script default is Standard_A1_v2.

Get-AzureRmVMSize shows available sizes, for example:

Get-AzureRmVMSize -Location westcentralus

.PARAMETER storageAccountType
Specifies the type of storage account to create. Script default is Standard_LRS. If using a premium storage VM size, specify Premium_LRS instead.

.PARAMETER useSingleResourceGroup
Specifies that the VMs be created all in the same resource group, which is the script default. To have each VM created in a different resource group, use -useSingleResourceGroup:$false

.PARAMETER useSingleStorageAccount
Specifies that the VMs be created all in the same storage account, which is the script default. To have each VM created in a different storage account, use -useSingleStorageAccount:$false

.PARAMETER enableEMS
Will use CustomScriptExtension to enable EMS in the VM and restart the VM for the setting to take effect.

.PARAMETER attachRescueDisk
Copies a small "rescue disk" containing support scripts into the boot diagnostics storage account and attaches it as a data disk to the first available LUN.

.PARAMETER rescueDiskUri
    URI to the rescue VHD

.PARAMETER linux
    Just create a single Linux VM

.PARAMETER windows
    Just create a single Windows VM

.PARAMETER linuxVMsOnly
    Only create Linux VMs.

.PARAMETER windowsVMsOnly
    Only create Windows VMs.

.EXAMPLE
    New.ps1 -location westus2 -userName craig -password $password

    Creates the VMs in westus2 using the specified username and password.

    New.ps1 -location westeurope -userName craig -password $password

    Creates the VMs in westeurope using the specified username and password.
#>

param(
    [string]$resourceGroupName = "rg$(get-date (get-date).ToUniversalTime() -f MMddhhmmss)",
    [string]$vmName,
    [string]$vmSize = 'Standard_D2s_v3', #'Standard_DS1_v2', #'Standard_A1_v2',
    [switch]$useManagedDisk = $true,
    [string]$location = 'westus2',
    [switch]$disableBginfoExtension = $true,
    [switch]$useSingleResourceGroup = $true,
    [switch]$useSingleStorageAccount = $true,
    [switch]$windows,
    [switch]$linux,
    [switch]$linuxVMsOnly,
    [switch]$windowsVMsOnly,
    [switch]$noga,
    [switch]$trackLatency,
    [switch]$configureWinRM,
    [switch]$attachRescueDisk,
    [string]$rescueDiskUri = 'https://rescuesa1.blob.core.windows.net/vhds/rescue.vhd',
    [string]$userName = 'craig',
    [string]$password = $password,
    [string]$storageAccountType = 'Standard_LRS',
    [switch]$enableEMS,
    [string]$shareName = 'rescue',
    [switch]$createWin7andWin8,
    [switch]$useDateInVMName,
    [string]$imageName,
    [string]$publisherName,
    [string]$offer,
    [string]$skus,
    [string]$version,
    [switch]$wait
)

function attach-rescuedisk
{
    <#
    .SYNOPSIS
        Copies and attaches a rescue VHD to a VM.

    .DESCRIPTION
        Copies a rescue VHD into the boot diagnostics storage account.
        For managed disk VMs it creates a managed disk from the copied VHD, then attaches the managed disk to the VM
        For unmanaged disk VMs it attaches the VHD from the boot diagnostics storage account.

    .EXAMPLE
        attach-rescuedisk -resourceGroupName $resourceGroupName -vmName $vmName

    .PARAMETER resourceGroupName
        Resource group name of the VM where you  want to attach the rescue VHD

    .PARAMETER vmName
        Name of VM to attach the rescue VHD

    .PARAMETER rescueDiskUri
        URI to the rescue VHD

    .PARAMETER useManagedDisk
        Creates a managed disk from the copied VHD.

    .PARAMETER accountType
        For managed disk VMs, this is the type of storage account to use for the managed disk that will be created from the rescue VHD.
        StandardLRS and PremiumLRS or the accepted values. Script defaults to StandardLRS
    #>
    param(
        [string]$vmName,
        $storageAccount,
        [string]$rescueDiskUri,
        [switch]$useManagedDisk,
        [string]$accountType = 'StandardLRS'
    )

    $storageAccountKey = ($storageAccount | Get-AzureRmStorageAccountKey )[0].Value
    $storageContext = New-AzureStorageContext -StorageAccountName $storageAccount.storageAccountName -StorageAccountKey $storageAccountKey
    $containerName = $rescueDiskUri.Split('/')[-2]
    if(!(Get-AzureStorageContainer -Context $storageContext -Name $containerName -ErrorAction SilentlyContinue))
    {
        $container = New-AzureStorageContainer -Context $storageContext -Name $containerName
    }

    show-progress "Copying rescue disk VHD into storage account $($storageAccount.storageAccountName)"
    $rescueDiskBlobName = $rescueDiskUri.Split('/')[-1]
    $rescueDiskCopyDiskName = "$($rescueDiskBlobName.Split('.')[0])$vmName"
    $rescueDiskCopyBlobName = "$rescueDiskCopyDiskName.vhd"
    $blobCopyStartTime = get-date
    $rescueDiskBlobCopy = Start-AzureStorageBlobCopy -AbsoluteUri $rescueDiskUri -DestContainer $containerName -DestBlob $rescueDiskCopyBlobName -DestContext $storageContext -force
    $rescueDiskBlobCopyUri = $rescueDiskBlobCopy.ICloudBlob.Uri
    $rescueDiskBlobCopyStatus = (Get-AzureStorageBlobCopyState -CloudBlob $rescueDiskBlobCopy.ICloudBlob -Context $storageContext -WaitForComplete -ServerTimeoutPerRequest 60).Status

    <#
    $timeout = 60
    do {
        $secondsInterval = 5
        start-sleep -Seconds $secondsInterval
        $secondsElapsed += $secondsInterval
        $rescueDiskBlobCopyStatus = (Get-AzureStorageBlobCopyState -CloudBlob $rescueDiskBlobCopy.ICloudBlob -Context $storageContext).Status
    } until (($rescueDiskBlobCopyStatus -eq 'Success') -or ($secondsElapsed -ge $timeout))
    #>

    if ($rescueDiskBlobCopyStatus -eq 'Success')
    {
        $blobCopyDuration = [Math]::Round((new-timespan -start $blobCopyStartTime -end (get-date)).TotalSeconds,2)
        show-progress "Rescue disk copied to $rescueDiskBlobCopyUri"
        show-progress "Rescue disk copy completed in $blobCopyDuration seconds"
    }
    else
    {
        show-progress "Copied failed: $rescueDiskBlobCopyStatus"
        exit
    }

    if($useManagedDisk)
    {
        show-progress "Creating managed disk from copied rescue disk VHD"
        $managedDiskConfig = New-AzureRmDiskConfig -AccountType $accountType -Location $location -CreateOption Import -StorageAccountId $storageAccount.Id -SourceUri $rescueDiskBlobCopyUri
        $managedDisk = New-AzureRmDisk -Disk $managedDiskConfig -ResourceGroupName $resourceGroupName -DiskName $rescueDiskCopyDiskName
        show-progress "Created managed disk $($managedDisk.Name)"
        return $managedDisk
    }
    else
    {
        return $rescueDiskBlobCopyUri.AbsoluteUri
    }
}
function Get-VMName
{
    param(
        [string]$skus,
        [string]$offer
    )

    $vmNamePrefix = ''

    switch -regex ($skus)
    {
        'UbuntuServer' {$vmNamePrefix = 'ubuntu'}
        'CoreOS' {$vmNamePrefix = 'coreos'}
        'Debian' {$vmNamePrefix = 'debian'}
        'CentOS' {$vmNamePrefix = 'centos'}
        'RHEL' {$vmNamePrefix = 'rhel'}
        'SLES' {$vmNamePrefix = 'sles'}
        'openSUSE-Leap' {$vmNamePrefix = 'opensuse'}
        'Oracle-Linux' {$vmNamePrefix = 'oraclelinux'}
        'Datacenter-Core-1709' {$vmNamePrefix = 'rs3'}
        'Datacenter-Core-1803' {$vmNamePrefix = 'rs4'}
        '2019-datacenter' {$vmNamePrefix = 'rs5'}
        '2016-Datacenter' {$vmNamePrefix = 'rs1'}
        '2012-R2-Datacenter' {$vmNamePrefix = 'r212'}
        '2012-Datacenter' {$vmNamePrefix = 'ws12'}
        '2008-R2' {$vmNamePrefix = 'r208'}
        'RS4-Pro' {$vmNamePrefix = 'rs4c'}
        'RS3-Pro' {$vmNamePrefix = 'rs3c'}
        'RS2-Pro' {$vmNamePrefix = 'rs2c'}
        'Win7' {$vmNamePrefix = 'win7'}
        'Win81' {$vmNamePrefix = 'win81'}
        'Windows-10' {$vmNamePrefix = 'win10'}
    }

    # Some Linux sku names are the same between distros, e.g. 7.4 is a sku for both CentOS and Oracle-Linux, so use offer instead
    switch -regex ($offer)
    {
        'UbuntuServer' {$vmNamePrefix = 'ubuntu'}
        'CoreOS' {$vmNamePrefix = 'coreos'}
        'Debian' {$vmNamePrefix = 'debian'}
        'CentOS' {$vmNamePrefix = 'centos'}
        'RHEL' {$vmNamePrefix = 'rhel'}
        'SLES' {$vmNamePrefix = 'sles'}
        'openSUSE-Leap' {$vmNamePrefix = 'opensuse'}
        'Oracle-Linux' {$vmNamePrefix = 'oraclelinux'}
    }

    if($vmNamePrefix -eq ''){$vmNamePrefix = 'vm'}

    #if (!$vmName -or $useDateInVMName)
    if ($useDateInVMName)
    {
        $vmName = "$($vmNamePrefix)$(get-date (get-date).ToUniversalTime() -f MMddhhmmss)"
    }
    else
    {
        $vmName = $vmNamePrefix
    }

    return $vmName
}

function show-progress()
{
    param(
        [string]$text,
        [string]$prefix = 'timespan'
    )

    if ($prefix -eq 'timespan' -and $startTime)
    {
        $timespan = new-timespan -Start $startTime -End (get-date)
        #$timespanString = '[{0:hh}:{0:mm}:{0:ss}.{0:ff}]' -f $timespan
        $timespanString = '[{0:mm}:{0:ss}]' -f $timespan
        write-host $timespanString -nonewline -ForegroundColor White
        write-host " $text"
    }
    elseif ($prefix -eq 'both' -and $startTime)
    {
        $timestamp = get-date -format "yyyy-MM-dd hh:mm:ss"
        $timespan = new-timespan -Start $startTime -End (get-date)
        #$timespanString = "$($timestamp) $('[{0:hh}:{0:mm}:{0:ss}.{0:ff}]' -f $timespan)"
        $timespanString = "$($timestamp) $('[{0:mm}:{0:ss}]' -f $timespan)"
        write-host $timespanString -nonewline -ForegroundColor White
        write-host " $text"
    }
    else
    {
        $timestamp = get-date -format "yyyy-MM-dd hh:mm:ss"
        write-host $timestamp -nonewline -ForegroundColor Cyan
        write-host " $text"
    }
}

$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
$PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'

if ($location -eq 'francesouth'){exit}

$startTime = get-date
$uniqueString = "$(-join ((97..122) | get-random -Count 8 | % {[char]$_}))$(get-date ($startTime).ToUniversalTime() -f MMddhhmmss)"
$context = get-azurermcontext
if ($context.Name)
{
    $subscriptionId = $context.Subscription.Id
    show-progress "subscriptionName: $($context.Subscription.Name) subscriptionId: $($context.Subscription.Id)"
}
else
{
    connect-azurermaccount
}

if ($host.version.major -eq 6)
{
    $moduleName = 'Az.Compute'
}
else
{
    $moduleName = 'AzureRM.Compute'
}

$ofs = ' '
$moduleVersion = (get-module -Name $moduleName -ListAvailable)[0].Version.ToString()
show-progress "$moduleName $moduleVersion"

$vmdetails = New-Object System.Collections.ArrayList
$images = @()

if ($imageName -and $imageName.Contains('.'))
{
    $publisherName = $imageName.Split('.')[0]
    $offer = $imageName.Split('.')[1]
    $skus = $imageName.Split('.')[2]
    $version = $imageName.Split('.')[3]
}

if ($publisherName -and $offer -and $skus)
{
    show-progress "Getting latest VM image version information"

    $userSpecifiedImage = $false

    if ($publisherName -and $offer -and $skus)
    {
        if ($publisherName -eq 'MicrosoftWindowsServer' -or $publisherName -eq 'MicrosoftWindowsDesktop' -or $publisherName -eq 'MicrosoftVisualStudio')
        {
            $windows = $true
            #$userSpecifiedImage = $true # used for deciding to add Plan info later on in script
        }
        elseif ($publisherName -eq 'Canonical' -or $publisherName -eq 'credativ' -or $publisherName -eq 'OpenLogic' -or $publisherName -eq 'Oracle' -or $publisherName -eq 'RedHat' -or $publisherName -eq 'SUSE')
        {
            $linux = $true
            #$userSpecifiedImage = $true # used for deciding to add Plan info later on in script
        }
        else
        {
            show-progress "Use -linux or -windows when specifying pub/offer/sku since there is no programmatic way to know the OS type from just the pub/offer/sku"
            exit
        }
    }
}
elseif ($imageName)
{
    $customImage = get-azurermimage | where Name -eq $imageName
    if ($customImage)
    {
        if ($customImage.Location -eq $location)
        {
            show-progress "Using image $imageName"
            $images += $customImage
        }
        else
        {
            show-progress "Image $imageName is in $($customImage.Location) but location specified for VM is $location"
            exit
        }
    }
    else
    {
        show-progress "Image not found: $imageName"
        exit
    }
}

if (!$customImage)
{
    $windowsImages = @()
    $linuxImages = @()

    #Windows
    if (!$linuxVMsOnly)
    {
        if (!$linux)
        {
            if ($publisherName -and $offer -and $skus)
            {
                if ($version)
                {
                    $windowsImages += get-azurermvmimage -Location $location -PublisherName $publisherName -Offer $offer -Skus $skus -Version $version
                }
                else
                {
                    $windowsImages += (get-azurermvmimage -Location $location -PublisherName $publisherName -Offer $offer -Skus $skus)[-1]
                }
            }
            else
            {
                $windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter-smalldisk')[-1]
            }
        }

        if (!$windows -and !$linux -and !$imageName)
        {
            $windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServerSemiAnnual' -Skus 'Datacenter-Core-1803-with-Containers-smalldisk')[-1]
            $windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter-smalldisk')[-1]
            $windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2012-R2-Datacenter-smalldisk')[-1]
            $windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2012-Datacenter-smalldisk')[-1]
            $windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2008-R2-SP1-smalldisk')[-1]
            $windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftWindowsDesktop' -Offer 'Windows-10' -Skus 'rs5-pro')[-1]
        }

        if ($createWin7andWin8)
        {
            $windowsImages = @()
            $windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftVisualStudio' -Offer 'Windows' -Skus 'Win7-SP1-Ent-N-x64')[-1]
            $windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftVisualStudio' -Offer 'Windows' -Skus 'Win81-Ent-N-x64')[-1]
            #$windowsImages += (get-azurermvmimage -Location $location -PublisherName 'MicrosoftVisualStudio' -Offer 'Windows' -Skus 'Windows-10-N-x64')[-1]
            if($windowsImages.Count -ne 2)
            {
                show-progress "No MicrosoftVisualStudio client images found. Make sure you are using an MSDN subscription"
            }
        }

        # Add OSType because there are Windows vs. Linux specific inputs needed for provisioning
        $windowsImages | foreach {$_ | Add-Member -MemberType NoteProperty -Name 'OsType' -Value 'Windows' -Force}
    }

    #Linux
    if (!$windowsVMsOnly)
    {
        if (!$windows)
        {
            if ($publisherName -and $offer -and $skus)
            {
                if ($version)
                {
                    $linuxImages += get-azurermvmimage -Location $location -PublisherName $publisherName -Offer $offer -Skus $skus -version $version
                }
                else
                {
                    $linuxImages += (get-azurermvmimage -Location $location -PublisherName $publisherName -Offer $offer -Skus $skus)[-1]
                }
            }
            else
            {
                $linuxImages += (get-azurermvmimage -Location $location -PublisherName 'Canonical' -Offer 'UbuntuServer' -Skus '18.04-LTS')[-1]
            }
        }

        if (!$windows -and !$linux -and !$imageName)
        {
            $linuxImages += (get-azurermvmimage -Location $location -PublisherName 'CoreOS' -Offer 'CoreOS' -Skus 'Stable')[-1]
            $linuxImages += (get-azurermvmimage -Location $location -PublisherName 'credativ' -Offer 'Debian' -Skus '9')[-1]
            $linuxImages += (get-azurermvmimage -Location $location -PublisherName 'OpenLogic' -Offer 'CentOS' -Skus '7.4')[-1]
            $linuxImages += (get-azurermvmimage -Location $location -PublisherName 'Oracle' -Offer 'Oracle-Linux' -Skus '7.4')[-1]
            $linuxImages += (get-azurermvmimage -Location $location -PublisherName 'RedHat' -Offer 'RHEL' -Skus '7.3')[-1]
            $linuxImages += (get-azurermvmimage -Location $location -PublisherName 'SUSE' -Offer 'SLES' -Skus '12-SP3')[-1]
            $linuxImages += (get-azurermvmimage -Location $location -PublisherName 'SUSE' -Offer 'openSUSE-Leap' -Skus '42.3')[-1]
        }
    }

    # Add OSType because there are Windows vs. Linux specific inputs needed for provisioning
    $linuxImages | foreach {$_ | Add-Member -MemberType NoteProperty -Name 'OsType' -Value 'Linux' -Force}

    $images += $windowsImages
    $images += $linuxImages

    show-progress "Creating VM(s) from the following images:"
    $images | foreach {show-progress "$($_.PublisherName).$($_.Offer).$($_.Skus).$($_.Version)"}
}

if ($useSingleResourceGroup)
{
    $resourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
    if ($resourceGroup)
    {
        show-progress "Using existing resource group $($resourceGroup.resourceGroupName)"
    }
    else
    {
        show-progress "Creating $location RG $resourceGroupName"
        $resourceGroup = New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
    }
}

if ($configureWinRM)
{
    $vaultName = "vault$uniqueString"
    show-progress "Creating key vault to store WinRM cert"
    $vault = New-AzureRmKeyVault -VaultName $vaultName -ResourceGroupName $resourceGroupName -Location $location -EnabledForDeployment -EnabledForTemplateDeployment
    $vaultId = $vault.ResourceId
    show-progress "Vault ID: $vaultId"
    $certName = "winrm$($resourceGroupName.Substring(2))"
    $certFilePath = ".\$certName.pfx"
    $certStore = "My"
    $certPath = "Cert:\CurrentUser\$certStore"
    show-progress "Creating self-signed cert for WinRM"
    $thumbprint = (New-SelfSignedCertificate -DnsName $certName -CertStoreLocation $certPath -KeySpec KeyExchange).Thumbprint
    show-progress "Created: $certPath\$thumbprint"
    $cert = (Get-ChildItem -Path $certPath\$thumbprint)
    $certFile = Export-PfxCertificate -Cert $cert -FilePath ".\$certName.pfx" -Password $passwordSecureString

    $fileName = ".\$certName.pfx"
    $fileContentBytes = Get-Content $fileName -Encoding Byte
    $fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)

$jsonObject = @"
{
"data": "$filecontentencoded",
"dataType" :"pfx",
"password": "$password"
}
"@

    $jsonObjectBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonObject)
    $jsonEncoded = [System.Convert]::ToBase64String($jsonObjectBytes)

    $secretName = $certName
    $secret = ConvertTo-SecureString -String $jsonEncoded -AsPlainText -Force
    $context = get-azurermcontext
    if($context.Account.Type -eq 'ServicePrincipal')
    {
        $servicePrincipalName = $context.Account.Id
        $permissionsToKeys = @('decrypt','encrypt','unwrapKey','wrapKey','verify','sign','get','list','update','create','import','delete','backup','restore','recover','purge')
        $permissionsToSecrets = @('get','list','set','delete','backup','restore','recover','purge')
        show-progress "Updating vault access policy to allow access by currently logged in service principal $servicePrincipalName"
        $policy = Set-AzureRmKeyVaultAccessPolicy -VaultName $vaultName -ServicePrincipalName $servicePrincipalName -PermissionsToKeys $permissionsToKeys -PermissionsToSecrets $permissionsToSecrets
    }
    $certURL = (Set-AzureKeyVaultSecret -VaultName $vaultName -Name $secretName -SecretValue $secret).Id
    show-progress "WinRM cert key vault URL: $certURL"
}

if (($useSingleResourceGroup -and $useSingleStorageAccount) -or $useManagedDisk)
{
    $storageAccountName = "sa$uniqueString"
    show-progress "Creating storage account $storageAccountName"
    $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -Type $storageAccountType -Location $location
    $storageAccountKey = ($storageAccount | Get-AzureRmStorageAccountKey )[0].Value
    $storageContext = New-AzureStorageContext $storageAccountName $storageAccountKey

    if ($attachRescueDisk)
    {
        # Create Azure Files share because it can be useful for getting files in and out of the VM
        $share = New-AzureStorageShare $shareName -Context $storageContext

        # When using one storage account to make all the VMs, doing an initial copy of the rescue disk VHD lets us do the per-VM copies from this copy in the same storage account (so faster)
        $containerName = $rescueDiskUri.Split('/')[-2]
        if(!(Get-AzureStorageContainer -Context $storageContext -Name $containerName -ErrorAction SilentlyContinue))
        {
            $container = New-AzureStorageContainer -Context $storageContext -Name $containerName
        }
        $blobCopyStartTime = get-date
        $destBlob = $rescueDiskUri.Split('/')[-1]
        $rescueDiskBlobCopy = Start-AzureStorageBlobCopy -AbsoluteUri $rescueDiskUri -DestContainer $containerName -DestBlob $destBlob -DestContext $storageContext -force
        $rescueDiskUri = $rescueDiskBlobCopy.ICloudBlob.Uri
        $rescueDiskBlobCopyStatus = (Get-AzureStorageBlobCopyState -CloudBlob $rescueDiskBlobCopy.ICloudBlob -Context $storageContext -WaitForComplete -ServerTimeoutPerRequest 60).Status
        if ($rescueDiskBlobCopyStatus -eq 'Success')
        {
            $blobCopyDuration = [Math]::Round((new-timespan -start $blobCopyStartTime -end (get-date)).TotalSeconds,2)
            show-progress "Rescue disk copied to $rescueDiskBlobCopyUri"
            show-progress "Rescue disk copy completed in $blobCopyDuration seconds"
        }
        else
        {
            show-progress "Copied failed: $rescueDiskBlobCopyStatus"
            exit
        }
        Set-AzureStorageContainerAcl -Name $containerName -Permission Container -Context $storageContext
    }
}

$numCreated = 0
$numToCreate = $images.count

$images | foreach {
    $publisherName = $_.publisherName
    $offer = $_.offer
    $skus = $_.skus
    if (!$version)
    {
        $version = 'latest'
    }

    if ($customImage)
    {
        $osType = $customImage.StorageProfile.OsDisk.OsType
    }
    else
    {
        $osType = $_.OsType
    }

    if ($vmName -and ($windows -or $linux))
    {
        show-progress "Using VM name $vmName that was specified at the command-line with -vmName parameter"
    }
    else
    {
        $vmName = Get-VMName -skus $skus -offer $offer
        show-progress "Using VM name $vmName"
    }

    $passwordSecureString = ConvertTo-SecureString -String $password -AsPlainText -Force
    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($userName, $passwordSecureString)
    if ($useSingleResourceGroup -eq $false)
    {
        $resourceGroupName = "rg$uniqueString"
        show-progress "Creating $location RG $resourceGroupName"
        $resourceGroup = New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
    }

    show-progress "Creating subnet $($vmName)-subnet"
    $subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name "$($vmName)-subnet" -AddressPrefix '192.168.1.0/24'
    #TODO: If single RG use single VNET for all VMs
    #TODO: enable auto-shutdown schedule by default
    show-progress "Creating vnet $($vmName)-vnet"
    $vnet = New-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location -Name "$($vmName)-vnet" -AddressPrefix 192.168.0.0/16 -Subnet $subnetConfig -Force
    show-progress "Creating PIP $($vmName)-ip"
    $pip = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroupName -Location $location -Name "$($vmName)-ip" -AllocationMethod Dynamic -IdleTimeoutInMinutes 4 -Force
    $ipAddress = $pip.ipAddress

    if ($osType -eq 'Windows')
    {
        $nsgRuleName = 'allow-rdp'
        $destinationPortRange = '3389'
    }
    else
    {
        $nsgRuleName = 'allow-ssh'
        $destinationPortRange = '22'
    }

    show-progress "Creating NSG $($vmName)-nsg"
    $nsgRule = New-AzureRmNetworkSecurityRuleConfig -Name $nsgRuleName -Protocol 'Tcp' -Direction 'Inbound' -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange $destinationPortRange -Access 'Allow'
    if ($configureWinRM)
    {
        $nsgRule2 = New-AzureRmNetworkSecurityRuleConfig -Name 'allow-winrm' -Protocol 'Tcp' -Direction 'Inbound' -Priority 1010 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange '5986' -Access 'Allow'
        $nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name "$($vmName)-nsg" -SecurityRules $nsgRule,$nsgRule2 -Force
    }
    else
    {
        $nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name "$($vmName)-nsg" -SecurityRules $nsgRule -Force
    }

    show-progress "Creating NIC $($vmName)-nic"
    $nic = New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName -Location $location -Name "$($vmName)-nic" -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id -Force
    $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
    $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $publisherName -Offer $offer -Skus $skus -Version $version
    $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id

    # Tested on AzureRM 6.8.1:
    # GA still gets installed if you specify -ProvisionVMAgent:$false
    # GA still gets installed if you leave off the -ProvisionVMAgent switch entirely
    # ???$vm.OSProfile.WindowsConfiguration.ProvisionVMAgent = $false

    if ($osType -eq 'Windows')
    {
        $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $cred

        if ($noga)
        {
            $vm.OSProfile.WindowsConfiguration.ProvisionVMAgent = $false
        }

        if ($configureWinRM)
        {
            $vm = Set-AzureRmVMOperatingSystem -VM $vm -WinRMHttp -WinRMHttps -WinRMCertificateUrl $certURL
            $vm = Add-AzureRmVMSecret -VM $vm -SourceVaultId $vaultId -CertificateStore $certStore -CertificateUrl $certURL
        }
    }
    else
    {
        $vm = Set-AzureRmVMOperatingSystem -VM $vm -Linux -ComputerName $vmName -Credential $cred
    }

    if ($userSpecifiedImage)
    {
        $vm = set-AzureRmVMPlan -VM $vm -Publisher $publisherName -Product $offer -Name $skus
        Get-AzureRmMarketplaceTerms -Publisher $publisherName -Product $offer -Name $skus | Set-AzureRmMarketplaceTerms -Accept
    }

    if (!$useSingleStorageAccount)
    {
        $storageAccountName = "sa$uniqueString"
        show-progress "Creating storage account $storageAccountName"
        $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -Type $storageAccountType -Location $location
    }
    #$vm = Set-AzureRmVMBootDiagnostics -VM $vm -Enable -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName

    if ($attachRescueDisk)
    {
        if ($useManagedDisk)
        {
            $managedDisk = attach-rescuedisk -vmName $vmName -storageAccount $storageAccount -rescueDiskUri $rescueDiskUri -useManagedDisk
        }
        else
        {
            $rescueDiskBlobCopyUri = attach-rescuedisk -vmName $vmName -storageAccount $storageAccount -rescueDiskUri $rescueDiskUri
            $rescueDiskCopyDiskName = $rescueDiskBlobCopyUri.Split('/')[-1].Replace('.vhd','')
        }
    }

    if ($useManagedDisk)
    {
        if ($attachRescueDisk)
        {
            $vm = Add-AzureRmVMDataDisk -VM $vm -Name $managedDisk.Name -ManagedDiskId $managedDisk.Id -Lun 0 -CreateOption Attach
        }
    }
    else
    {
        $osDiskName = $vmName + 'osdisk'
        $osDiskUri = $storageAccount.PrimaryEndpoints.Blob.ToString() + 'vhds/' + $osDiskName + '.vhd'
        $vm = Set-AzureRmVMOSDisk -VM $vm -Name $OSDiskName -VhdUri $OSDiskUri -CreateOption 'FromImage'
        if ($attachRescueDisk)
        {
            $vm = Add-AzureRmVMDataDisk -VM $vm -Name $rescueDiskCopyDiskName -VhdUri $rescueDiskBlobCopyUri -Lun 0 -CreateOption Attach
        }
    }
    if($useManagedDisk){$diskType = 'managed'}else{$diskType = 'unmanaged'}
    show-progress "Creating $location $vmSize $diskType disk VM $vmName in RG $resourceGroupName from image $($publisherName).$($offer).$($skus).$($version)"
    $vmCreateTime = get-date ((get-date).ToUniversalTime()) -format yyyy-MM-ddTHH:mm:ss
    if ($wait)
    {
        if ($disableBginfoExtension)
        {
            if ($customImage)
            {
                $result = New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm -DisableBginfoExtension -Image $imageName
            }
            else
            {
                $result = New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm -DisableBginfoExtension
            }
        }
        else
        {
            if ($customImage)
            {
                $result = New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm -Image $imageName
            }
            else
            {
                $result = New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm
            }
        }
    }
    else
    {
        if ($disableBginfoExtension)
        {
            if ($customImage)
            {
                $result = New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm -DisableBginfoExtension -Image $imageName -AsJob
            }
            else
            {
                $result = New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm -DisableBginfoExtension -AsJob
            }
        }
        else
        {
            if ($customImage)
            {
                $result = New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm -Image $imageName -AsJob
            }
            else
            {
                $result = New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm -AsJob
            }
        }
    }

    $vmdetail = [ordered]@{
        'ResourceGroupName' = $resourceGroupName
        'Name' = $vmName
        'Location' = $location
        'OsType' = $osType
    }
    $vmdetail = new-object -TypeName PSObject -Property $vmdetail
    [void]$vmdetails.add($vmdetail)
    $numCreated++
    show-progress "$numCreated of $numToCreate VMs created"
}

if ($enableEMS)
{
    $vmdetails | where {$_.OSType -eq 'Windows'} | foreach {
        show-progress "Enabling EMS on $($_.Name)"
        $name = 'EnableEMS'
        $publisher = 'Microsoft.Compute'
        $extensionType = 'CustomScriptExtension'
        $typeHandlerVersion = '1.9'
        $settingString = '{"commandToExecute": "cmd.exe /c bcdedit /ems {current} on && bcdedit /emssettings EMSPORT:1 EMSBAUDRATE:115200 && shutdown /r /t 0 /f "}'
        $result = Set-AzureRmVMExtension -AsJob -ResourceGroupName $_.resourceGroupName -VMName $_.Name -Location $_.Location -Name $name -Publisher $publisher -ExtensionType $extensionType -TypeHandlerVersion $typeHandlerVersion -settingstring $settingString
    }
}

if ($trackLatency)
{
    show-progress "get-kusto.ps1 -scenario VMApiQosEvent -when $vmCreateTime -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -resourceName $vmName"
    get-kusto.ps1 -scenario VMApiQosEvent -when $vmCreateTime -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -resourceName $vmName
}