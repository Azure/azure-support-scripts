$RDPTCPpath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp'
$TSpath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
$msg = 'Set Computer Configuration\Policies\Administrative Templates: Policy definitions\Windows Components\Remote Desktop Services\Remote Desktop Session Host\'
$domainJoined = (gwmi win32_computersystem).partofdomain
if ($domainJoined) {
  Write-Host Domain: (gwmi win32_computersystem).Domain
} else {
  Write-Host Not domain joined
  Set-ItemProperty -Path $RDPTCPpath -name LanAdapter -Value 0
}

function ReadReg()
{
  Param($Path,$Name,$Expected,$Text)
  $Value=(Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
  Write-Host ($Path+'\'+$Name+': '+$Value)
  if (!($Expected -eq $null) -and !($Expected -eq $Value)) {
    if ($domainJoined) {
      if (!($Value -eq $null)) {
        Write-Host ($msg+$Text)
      }
    } else {
      Write-Host Reset value to expected: $Expected
      Set-ItemProperty -Path $Path -Name $Name -Value $Expected -ErrorAction SilentlyContinue
    }
  }
}

ReadReg -Path $RDPTCPpath -Name PortNumber
ReadReg -Path $TSpath -Name fDenyTSConnections -Text 'Connections\Allow users to connect remotely by using Remote Desktop Services'

$t = 'Connections\Configure keep-alive connection interval'
ReadReg -Path $TSpath -Name KeepAliveEnable -Expected 1 -Text $t
ReadReg -Path $TSpath -Name KeepAliveInterval -Expected 1 -Text $t
ReadReg -Path $TSpath -Name KeepAliveTimeout -Expected 1 -Text $t

$t = 'Connections\Automatic reconnection'
ReadReg -Path $TSpath -Name fDisableAutoReconnect -Expected 0 -Text $t
ReadReg -Path $RDPTCPpath -Name fInheritReconnectSame -Expected 1 -Text $t
ReadReg -Path $RDPTCPpath -Name fReconnectSame -Expected 1 -Text $t

ReadReg -Path $RDPTCPpath -Name fInheritMaxSessionTime -Expected 1 -Text 'Session Time Limits\Set time limit for active Remote Desktop Session Services sessions'

$t = 'Session Time Limits\Set time limit for disconnected sessions'
ReadReg -Path $RDPTCPpath -Name fInheritMaxDisconnectionTime -Expected 1 -Text $t
ReadReg -Path $RDPTCPpath -Name MaxDisconnectionTime -Expected 0 -Text $t

ReadReg -Path $RDPTCPpath -Name MaxConnectionTime -Expected 0 -Text 'Session Time Limits\End session when time limits are reached'

$t = 'Session Time Limits\Set time limit for active but idle Remote Desktop Services sessions'
ReadReg -Path $RDPTCPpath -Name fInheritMaxIdleTime -Expected 1 -Text $t
ReadReg -Path $RDPTCPpath -Name MaxIdleTime -Expected 0 -Text $t

ReadReg -Path $RDPTCPpath -Name MaxInstanceCount -Expected 4294967295 -Text 'Connections\Limit number of connections'

ReadReg -Path $RDPTCPpath -Name LanAdapter -Expected 0 -Text 'TermSrv Defaults\Listen on all LAN Adapters'
ReadReg -Path $RDPTCPpath -Name TSServerDrainMode -Expected 0 -Text 'TermSrv Defaults\Disable drain mode'
ReadReg -Path $RDPTCPpath -Name fQueryUserConfigFromLocalMachine -Expected 1 -Text 'TermServ Defaults\Load user config locally'