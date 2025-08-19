Write-Output 'Configuring registry to disable Network Level Authentication (NLA).'
$path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Set-ItemProperty -Path $path -Name UserAuthentication -Type DWord -Value 0
Write-Output 'Restart the VM for the change to take effect.'
