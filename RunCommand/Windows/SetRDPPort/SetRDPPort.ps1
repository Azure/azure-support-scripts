param($RDPPort=3389)

$TSPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$RDPTCPpath = $TSPath + '\Winstations\RDP-Tcp'
Set-ItemProperty -Path $TSPath -name 'fDenyTSConnections' -Value 0

# RDP port
$portNumber = (Get-ItemProperty -Path $RDPTCPpath -Name 'PortNumber').PortNumber
Write-Host Get RDP PortNumber: $portNumber
if (!($portNumber -eq $RDPPort))
{
  Write-Host Setting RDP PortNumber to $RDPPort
  Set-ItemProperty -Path $RDPTCPpath -name 'PortNumber' -Value $RDPPort
  Restart-Service TermService -force
}

#Setup firewall rules
if ($RDPPort -eq 3389)
{
  netsh advfirewall firewall set rule group="remote desktop" new Enable=Yes
} 
else
{
  $systemroot = get-content env:systemroot
  netsh advfirewall firewall add rule name="Remote Desktop - Custom Port" dir=in program=$systemroot\system32\svchost.exe service=termservice action=allow protocol=TCP localport=$RDPPort enable=yes
}
