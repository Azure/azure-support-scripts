try {
    # Get the signature
    # Powershell 5.1 does not include -NoProxy
    $attestedDoc = Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri http://169.254.169.254/metadata/attested/document?api-version=2018-10-01

    # Decode the signature
    $signature = [System.Convert]::FromBase64String($attestedDoc.signature)

    # Get certificate chain
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]($signature)
    $chain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain

    if (-not $chain.Build($cert)) {
       # Print the Subject of issuer only if certificate is missing
       Write-Host "Certificate not found: '$($cert.Issuer)'" -ForegroundColor Red
       Write-Host "Please refer to the following link to download missing certificates:" -ForegroundColor Yellow
       Write-Host "https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details?tabs=certificate-authority-chains" -ForegroundColor Yellow
       Write-Host "https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service" -ForegroundColor Yellow
    } else {
       # Output a confirmation message if no certificates are missing
       Write-Host "No missing certificate has been found." -ForegroundColor Green
    }
} catch {
    Write-Host "Unable to connect to the metadata server: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please refer to the following link for details about IMDS endpoint connection:" -ForegroundColor Yellow
    Write-Host "https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service" -ForegroundColor Yellow
}
