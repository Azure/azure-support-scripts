try {
    # Get the attested document from IMDS
    $attestedDoc = Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri http://169.254.169.254/metadata/attested/document?api-version=2018-10-01
    
    # Decode the signature
    $signature = [System.Convert]::FromBase64String($attestedDoc.signature)
    
    # Create certificate object from signature
    $cert = $signature
    
    # Build the chain from the default store
    $chain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
    if (-not $chain.Build($cert)) {
        # Certificate not found in the default store
        Write-Host "Certificate not found in default store: '$($cert.Issuer)'" -ForegroundColor Red

        # Check alternate store (LocalMachine\Root)
        $altStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
        $altStore.Open("ReadOnly")
        $foundInAltStore = $altStore.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
        $altStore.Close()

        if ($foundInAltStore) {
            Write-Host "Warning: Certificate found in LocalMachine\Root. It may be in the incorrect store." -ForegroundColor Yellow
        } else {
            Write-Host "Please refer to the following link to download missing certificates:" -ForegroundColor Yellow
            Write-Host "https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details?tabs=certificate-authority-chains" -ForegroundColor Yellow
            Write-Host "https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No missing certificate has been found." -ForegroundColor Green
    }

    # --- TCP Connectivity Check Section ---
    Write-Host "`nPerforming TCP Port 80 Connectivity Check..." -ForegroundColor Cyan

    $tcpTargets = @{
        "AIA"  = @(
            "cacerts.digicert.com",
            "cacerts.digicert.cn",
            "cacerts.geotrust.com",
            "caissuers.microsoft.com",
            "www.microsoft.com"
        )
        "CRL"  = @(
            "crl3.digicert.com",
            "crl4.digicert.com",
            "crl.digicert.cn",
            "www.microsoft.com"
        )
        "OCSP" = @(
            "ocsp.digicert.com",
            "ocsp.digicert.cn",
            "oneocsp.microsoft.com"
        )
    }

    foreach ($category in $tcpTargets.Keys) {
        Write-Host "`nChecking $category endpoints..." -ForegroundColor Magenta
        foreach ($targetHost in $tcpTargets[$category]) {
            try {
                $result = Test-NetConnection -ComputerName $targetHost -Port 80 -WarningAction SilentlyContinue
                if ($result.TcpTestSucceeded) {
                    Write-Host "  [+] $targetHost : Port 80 reachable" -ForegroundColor Green
                } else {
                    Write-Host "  [-] $targetHost : Port 80 unreachable" -ForegroundColor Red
                }
            } catch {
                Write-Host "  [!] Error testing $targetHost : $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

} catch {
    Write-Host "Unable to connect to the metadata server: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please refer to the following link for details about IMDS endpoint connection:" -ForegroundColor Yellow
    Write-Host "https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service" -ForegroundColor Yellow
}
