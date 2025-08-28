Write-Host Clear security certificates. Removes SSLCertificateSHA1Hash from the registry.
$name = 'SSLCertificateSHA1Hash'
$path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
Set-ItemProperty -Path $path -Name 'MinEncryptionLevel' -Value 1
Set-ItemProperty -Path $path -Name 'SecurityLayer' -Value 0
Remove-ItemProperty -Path 'HKLM:\SYSTEM\ControlSet001\Control\Terminal Server\WinStations\RDP-Tcp' -Name $name -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SYSTEM\ControlSet002\Control\Terminal Server\WinStations\RDP-Tcp' -Name $name -ErrorAction SilentlyContinue
Write-Host Restart the service
restart-service TermService -force
