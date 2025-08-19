try {
    # Ensure WinRM service is running
    $winrmService = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    if ($winrmService -and $winrmService.Status -ne 'Running') {
        Write-Host "WinRM service is not running. Attempting to start WinRM..." -ForegroundColor Yellow
        try {
            Start-Service -Name WinRM
            Write-Host "WinRM service started successfully." -ForegroundColor Green
        } catch {
            Write-Host "Failed to start WinRM service: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
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
    $licenseStatus = (Get-CimInstance SoftwareLicensingProduct -ComputerName $env:computername | Where-Object { $_.Name -like "*Windows*" -and $_.PartialProductKey })[0].LicenseStatus

    if ($licenseStatus -eq 1) {
        Write-Host "Windows is Activated." -ForegroundColor Green
    } else {
        Write-Host "Windows is not activated or activation status is undetermined. Attempting activation..." -ForegroundColor Yellow
        $activationResult = cscript.exe C:\Windows\System32\slmgr.vbs /ato 2>&1
        if ($activationResult -match "Product activated successfully") {
            Write-Host "Product activated successfully." -ForegroundColor Green
        } elseif ($activationResult -match "Error:") {
            $errorLine = $activationResult | Select-String -Pattern "Error:" | Select-Object -First 1
            $errorCode = $errorLine -replace '.*Error:\s*', ''
            Write-Host ""
            Write-Host "Activation failed. Error code: $errorCode" -ForegroundColor Red
            Write-Host ""
            $errorCodeTrimmed = $errorCode.Trim()
            $knownError = $false
            if ($errorCodeTrimmed -like '*0xC004F074*') {
                Write-Host "Troubleshoot Link: https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-activation-error-0xc004f074" -ForegroundColor Yellow
                $knownError = $true
            }
            if ($errorCodeTrimmed -like '*0xC004FD01*') {
                Write-Host "Troubleshoot Link: https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-activation-error-0xc004fd01-0xc004fd02" -ForegroundColor Yellow
                $knownError = $true
            }
            if ($errorCodeTrimmed -like '*0xC004FD02*') {
                Write-Host "Troubleshoot Link: https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-activation-error-0xc004fd01-0xc004fd02" -ForegroundColor Yellow
                $knownError = $true
            }
            if ($errorCodeTrimmed -like '*0xC004F06C*') {
                Write-Host "Troubleshoot Link: https://learn.microsoft.com/troubleshoot/windows-server/licensing-and-activation/error-0xc004f06c-activate-windows" -ForegroundColor Yellow
                $knownError = $true
            }
            if ($errorCodeTrimmed -like '*0xC004E015*') {
                Write-Host "Troubleshoot Link: https://learn.microsoft.com/troubleshoot/windows-server/installing-updates-features-roles/error-0xc004e015-sl-e-eul-consumption-failed-activate-windows" -ForegroundColor Yellow
                $knownError = $true
            }
            if ($errorCodeTrimmed -like '*0x800705B4*') {
                Write-Host "Troubleshoot Link: https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/windows-vm-activation-error-0x800705b4" -ForegroundColor Yellow
                $knownError = $true
            }
            if ($errorCodeTrimmed -like '*0x80070005*') {
                Write-Host "Troubleshoot Link: https://learn.microsoft.com/troubleshoot/windows-server/installing-updates-features-roles/error-0x80070005-access-denied" -ForegroundColor Yellow
                $knownError = $true
            }
            if (-not $knownError) {
                Write-Host "Troubleshoot Link: https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-activation-problems" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Activation command executed. Please verify activation status again." -ForegroundColor Yellow
        }
    }

} catch {
    Write-Host "Unable to connect to the metadata server: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please refer to the following link for details about IMDS endpoint connection:" -ForegroundColor Yellow
    Write-Host "https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service" -ForegroundColor Yellow
}
