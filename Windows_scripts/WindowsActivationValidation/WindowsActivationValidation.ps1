try {
    # Check if the VM is using an Azure edition image
    $WindowsEdition = (Get-ComputerInfo).OsName
    $isAzureEdition = $WindowsEdition -match "Azure"

    if ($isAzureEdition) {
        # Check IMDS endpoint connectivity
        $attestedDoc = Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri http://169.254.169.254/metadata/attested/document?api-version=2018-10-01
        $signature = [System.Convert]::FromBase64String($attestedDoc.signature)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]($signature)
        $chain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain

        Write-Host "Connection to IMDS endpoint was successful." -ForegroundColor Green

        if (-not $chain.Build($cert)) {
            Write-Host "Certificate not found: '$($cert.Issuer)'" -ForegroundColor Red
            Write-Host "Please refer to the following link to download missing certificates:" -ForegroundColor Yellow
            Write-Host "https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details?tabs=certificate-authority-chains" -ForegroundColor Yellow
        } else {
            Write-Host "No missing certificate has been found." -ForegroundColor Green
        }
    }

    # Fetch the actual Key Management Service (KMS) endpoint from the registry
    $kmsRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
    $kmsEndpoint = (Get-ItemProperty -Path $kmsRegistryPath -Name KeyManagementServiceName -ErrorAction SilentlyContinue).KeyManagementServiceName

    if (-not $kmsEndpoint) {
        Write-Host "Unable to retrieve KMS endpoint from registry. Using default Azure KMS endpoint." -ForegroundColor Yellow
        $kmsEndpoint = "azkms.core.windows.net"  # Changed default endpoint
    }

    # Perform a TCP test connection to the actual KMS endpoint
    $port = 1688
    $tcpConnection = Test-NetConnection -ComputerName $kmsEndpoint -Port $port -InformationLevel Detailed
    Write-Host "TCP Test Connection to KMS endpoint ($kmsEndpoint):`n$($tcpConnection | Format-List | Out-String)" -ForegroundColor Cyan

    # Check if the KMS endpoint is not the default Azure KMS server
    if ($kmsEndpoint -ne "azkms.core.windows.net") {
        Write-Host "The Operating System is not using the default Azure KMS endpoint." -ForegroundColor Yellow
    }

    # Check Windows Activation Status
    $licenseStatus = (Get-CimInstance SoftwareLicensingProduct -ComputerName $env:computername | Where-Object { $_.Name -like "*Windows*" }).LicenseStatus

    if ($licenseStatus -eq 0) {
        Write-Host "Windows is Activated." -ForegroundColor Green
    } elseif ($licenseStatus -eq 1) {
        Write-Host "Windows is Not Activated." -ForegroundColor Red
    } else {
        Write-Host "Unable to determine Windows activation status." -ForegroundColor Yellow
    }

} catch {
    Write-Host "Unable to connect to the metadata server: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please refer to the following link for details about IMDS endpoint connection:" -ForegroundColor Yellow
    Write-Host "https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service" -ForegroundColor Yellow
}