<#
.SYNOPSIS
   Find known issues on Windows Azure VM
.DESCRIPTION
   Find-AzureVmKnownIssuesWindows helps to detect known issues that may be blocking network connectivity to a Windows Azure VM (script designed to be used on Azure VM Serial Console feature)
.NOTES
   Find-AzureVmKnownIssuesWindows was tested only on Windows Servers 2012 R2 and Windows Server 2016. There are plans to include other Windows versions.
.EXAMPLE
   Find-AzureVmKnownIssuesWindows
#>
[CmdletBinding()]



<# RDP settings #>
# get Current is necessary because Serial Console only shows limited lines
$Current = (Get-ItemProperty HKLM:\SYSTEM\Select -Name Current).Current
if ($null -eq $Current)
{
    $Current = 1 # default
}

$RDPSettings = [pscustomobject]@{
    'fDenyTSConnections' = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' | Select-Object fDenyTSConnections).fDenyTSConnections
    'PortNumber' = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' | Select-Object PortNumber).PortNumber
    'LanAdapter' = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' | Select-Object LanAdapter).LanAdapter
}

# if fDenyTSConnections is not 0 then RDP is not enabled
if ($RDPSettings.fDenyTSConnections)
{
    Write-Host ("`nWARN | Deny RDP Connections`n   RDP is set to deny connections, current value of 'fDenyTSConnections' is '{0}'`n   Run the following commands to fix this problem: (copy & paste line by line)`n >`n  `$reg='HKLM:\System\ControlSet00$Current\Control\Terminal Server'`n  Set-ItemProperty -Path `$reg -Name 'fDenyTSConnections' -Value 0`n" -f $RDPSettings.fDenyTSConnections) -ForegroundColor Yellow
}

# if PortNumber is not 3389 then RDP is not using the default port
if ($RDPSettings.PortNumber -ne 3389)
{
    Write-Host ("`nWARN | RDP is not using default port`n   Remote Desktop is set use '{0}' port, the default RDP port is '3389'`n   Run the following commands to fix this problem: (copy & paste line by line)`n >`n  `$reg='HKLM:\SYSTEM\ControlSet00$Current\Control\Terminal Server\WinStations\RDP-Tcp'`n  Set-ItemProperty -Path `$reg -Name 'PortNumber' -Value 3389`n  Restart-Service TermService -Force`n" -f $RDPSettings.PortNumber) -ForegroundColor Yellow
}

# if LanAdapter is not 0 then RDP is accepting connections only for a specific network card (not recommended on Azure)
if ($RDPSettings.LanAdapter -ne 0)
{
    Write-Host ("`nWARN | RDP is listening on a specific NIC `n   Remote Desktop is listening on NIC '{0}', by default RDP listen on all NICs`n   Run the following commands to fix this problem: (copy & paste line by line)`n >`n  `$reg='HKLM:\SYSTEM\ControlSet00$Current\Control\Terminal Server\WinStations\RDP-Tcp'`n  Set-ItemProperty -Path `$reg -Name 'LanAdapter' -Value 0`n  Restart-Service TermService -Force`n" -f $RDPSettings.LanAdapter) -ForegroundColor Yellow
}
<# / RDP settings #>




<# Network #>
# Network card - disabled nic
# https://blogs.technet.microsoft.com/heyscriptingguy/2014/01/15/using-powershell-to-find-connected-network-adapters/
Add-Type -TypeDefinition @"
   public enum nicStatus
   {
      Disconnected,
      Connecting,
      Connected,
      Disconnecting,
      HardwareNotPresent,
      HardwareDisabled,
      HardwareMalfunction,
      MediaDisconnected,
      Authenticating,
      AuthenticationSucceeded,
      AuthenticationFailed,
      InvalidAddress,
      CredentialsRequired
   }
"@
$nics = @(Get-CimInstance -ClassName win32_networkadapter -Filter 'PhysicalAdapter=True' | Select-Object DeviceID, netconnectionid, name, InterfaceIndex, netconnectionstatus, AdapterType, AdapterTypeId, MACAddress, netEnabled, PhysicalAdapter)
if ($nics.Count -eq 0)
{
    $link = 'http://aka.ms/azurevmrdp'
    Write-Host ("`nWARN | No NIC`n   No network adapter detected`n   Access the following link to learn how to fix this problem:`n   {0}`n" -f $link) -ForegroundColor Yellow
}
elseif ($nics.Count -eq 1)
{
    # if netconnectionstatus not Connected = Nic is disabled
    if ($nics[0].netconnectionstatus -ne [nicStatus]::Connected)
    { 
        Write-Host ("`nWARN | Disabled NIC`n   Network card {0} is not connected, current status is '{1}'`n   Run the following command to fix this problem:`n >`n  Enable-NetAdapter -name `"{0}`"`n" -f $nics[0].netconnectionid, [nicStatus][int]$nics[0].netconnectionstatus) -ForegroundColor Yellow
    }
    else
    {
        # Nic IP details
        $NicConfig = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter ('Index={0}' -f $nics[0].DeviceID) | Select-Object DHCPEnabled, DHCPServer, IPEnabled, IPAddress, DNSServerSearchOrder
        if ($NicConfig.DHCPEnabled -ne 'True')
        {
            Write-Host ("`nWARN | Disabled DHCP NIC`n   DHCP is not enabled at network card {0}`n   This is only expected on VMs using multiple IPs per NIC`n   Run the following command to fix this problem:`n >`n  (gwmi Win32_NetworkAdapterConfiguration -Filter 'Index={1}').EnableDHCP()`n" -f $nics[0].netconnectionid, $nics[0].DeviceID) -ForegroundColor Yellow
        }

        # Nic IPv4 detail
        $NicIPv4 = Get-NetAdapterBinding -Name ('{0}' -f $nics[0].netconnectionid) -ComponentID ms_tcpip
        if (!$NicIPv4.Enabled)
        {
            Write-Host ("`nWARN | Disabled IPv4 NIC`n   IPv4 is not enabled at network card {0}`n   Run the following command to fix this problem:`n >`n  Enable-NetAdapterBinding -Name '{0}' -ComponentID ms_tcpip`n" -f $nics[0].netconnectionid) -ForegroundColor Yellow
        }
    }
}
<# / Network #>


<# Services #>
$services = Get-Service -Name @('dhcp', 'TermService')
foreach ($service in $services)
{
    # get services
    if ($service)
    {
        # if service is disable
        if ($service.StartType -eq 'Disabled')
        {
            switch ($service.Name)
            {
                'dhcp' {$DefaultStartType = 'Automatic' }
                'TermService' {$DefaultStartType = 'Manual' }
                default {$DefaultStartType = 'Manual' }
            }
            Write-Host ("`nWARN | Service's start type is disabled`n   The start type of service {0} is disabled on this VM`n   Run the following commands to set the service to {1} and start it:`n   (please, copy & paste line by line)`n >`n  Set-Service -Name {0} -StartupType {1}`n  Start-Service -Name '{0}'`n" -f $service.Name, $DefaultStartType) -ForegroundColor Yellow
        }
        else
        {
            # if service is not running
            if ($service.Status -ne 'Running')
            {
                Write-Host ("`nWARN | Service {0} NOT running`n   Service {0} is {1} on this VM`n   Run the following command to start this service:`n >`n  Start-Service -Name '{0}'`n" -f $service.Name, $service.State) -ForegroundColor Yellow
            }
        }
    }
}
<# / Services #>


<# TransparentInstaller.log #>
if (Test-Path C:\WindowsAzure\Logs\TransparentInstaller.log)
{
    $TransparentInstaller = Get-Content C:\WindowsAzure\Logs\TransparentInstaller.log

    <# TransparentInstaller.log - Proxy preventing WireServer connection #>
    # https://blogs.msdn.microsoft.com/mast/2015/05/18/what-is-the-ip-address-168-63-129-16/
    $ScenarioProxyWireServer = [pscustomobject]@{
        'Pattern1' = 'Exception while fetching supported versions from HostGAPlugin: System.Net.WebException: Unable to connect to the remote server.* (?<ip>\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}):(?<port>\d*)$'
        'Pattern2' = 'failed with System.Net.WebException: An exception occurred during a WebClient request. ---> System.NotSupportedException: The ServicePointManager does not support proxies with the https scheme.'
        'Description' = "`nWARN | Internet Proxy`n   We detected that the Agent is faling to contact WireServer (168.63.129.16)`n   IP {0} is set as a proxy in Internet Settings`n   Access the following link to learn how to fix this problem:`n   {1}`n"
        'Link' = 'http://aka.ms/azurevmrdp'
    }

    $TransparentInstaller[-100..-1] | ForEach-Object { if (($_ -match $ScenarioProxyWireServer.Pattern1) -or ($_ -match $ScenarioProxyWireServer.Pattern2)) {
            # If IP is not WireServer IP then probably it is a proxy
            #$ScenarioProxyWireServer.Proxy = '{0}:{1}' -f $Matches.ip, $Matches.port
            $null = New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS
            $ProxySettings = Get-ItemProperty 'HKU:\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Internet Settings\' | Select-Object ProxyEnable, ProxyServer
            Remove-PSDrive -Name HKU
            if ($ProxySettings.ProxyEnable)
            {
                Write-Host ($ScenarioProxyWireServer.Description -f $ProxySettings.ProxyServer, $ScenarioProxyWireServer.Link) -ForegroundColor Yellow
                continue
            }
        }
    } 
    <# / TransparentInstaller.log - Proxy preventing WireServer connection #>
}
<# / TransparentInstaller.log #>
