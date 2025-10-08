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
        # Check alternate store (e.g., LocalMachine\Root)
        $altStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
        $altStore.Open("ReadOnly")
        $foundInAltStore = $altStore.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
        $altStore.Close()
        if ($foundInAltStore) {
            # Warn if certificate exists in alternate store
            Write-Host "Warning: Certificate found in LocalMachine\Root. It may be in the incorrect store." -ForegroundColor Yellow
        } else {
            # Original behavior if not found anywhere
            Write-Host "Please refer to the following link to download missing certificates:" -ForegroundColor Yellow
            Write-Host "https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details?tabs=certificate-authority-chains" -ForegroundColor Yellow
            Write-Host "https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service" -ForegroundColor Yellow
        }
    } else {
        # Certificate chain built successfully
        Write-Host "No missing certificate has been found." -ForegroundColor Green
    }
} catch {
    Write-Host "Unable to connect to the metadata server: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please refer to the following link for details about IMDS endpoint connection:" -ForegroundColor Yellow
    Write-Host "https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service" -ForegroundColor Yellow
}
 