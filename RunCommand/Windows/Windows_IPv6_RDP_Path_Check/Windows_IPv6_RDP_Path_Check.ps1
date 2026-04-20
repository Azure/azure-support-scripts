#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$MockConfig,
  [ValidateSet('healthy','degraded','broken')]
  [string]$MockProfile = 'degraded'
)
$ErrorActionPreference='Continue'
function Pad($s,$n){$s="$s";if($s.Length -ge $n){$s.Substring(0,$n)}else{$s.PadRight($n)}}
$W=44
$rows=New-Object System.Collections.Generic.List[object]
function Add-Row($c,$s,$d=''){ $rows.Add([PSCustomObject]@{Check=$c;Status=$s;Detail=$d}); Write-Output ('{0} {1}' -f (Pad $c $W), $s) }

Write-Output '=== Windows IPv6 RDP Path Check ==='
Write-Output ('{0} {1}' -f (Pad 'Check' $W), 'Status')
Write-Output (('-' * $W) + ' ------')

$usedMock = $false
if($MockConfig -and (Test-Path $MockConfig)){
  $mock = Get-Content $MockConfig -Raw | ConvertFrom-Json
  if($mock.profiles -and $mock.profiles.$MockProfile){
    $usedMock = $true
    foreach($i in $mock.profiles.$MockProfile){ Add-Row $i.name $i.status $i.detail }
  }
}

if(-not $usedMock){
  # Probe: IPv6 enabled on primary NIC
  $nic = Get-NetAdapterBinding -ComponentId ms_tcpip6 -ErrorAction SilentlyContinue | Select-Object -First 1; $v6 = if($nic){$nic.Enabled}else{$null}
  $_s = if($v6 -eq $true){'OK'}elseif($v6 -eq $false){'WARN'}else{'FAIL'}
  Add-Row 'IPv6 enabled on primary NIC' $_s ("IPv6Enabled=$v6")

  # Probe: IPv6 addresses assigned
  $v6addr = Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "fe80*" }; $v6Count = @($v6addr).Count
  $_s = if($v6Count -ge 0){'OK'}elseif($false){'WARN'}else{'FAIL'}
  Add-Row 'IPv6 addresses assigned' $_s ("GlobalIPv6=$v6Count (informational)")

  # Probe: RDP listener address binding
  $rdpBind = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "LanAdapter" -ErrorAction SilentlyContinue; $lanAdp = if($rdpBind){$rdpBind.LanAdapter}else{-1}
  $_s = if($lanAdp -eq 0){'OK'}elseif($lanAdp -ne 0 -and $lanAdp -ne -1){'WARN'}else{'FAIL'}
  Add-Row 'RDP listener address binding' $_s ("LanAdapter=$lanAdp (0=all NICs)")

  # Probe: RDP firewall rule for IPv6
  $fw6 = Get-NetFirewallRule -DisplayName "*Remote Desktop*" -ErrorAction SilentlyContinue | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue | Where-Object { $_.RemoteAddress -eq "Any" }; $fwOk = @($fw6).Count -gt 0
  $_s = if($fwOk){'OK'}elseif(!$fwOk){'WARN'}else{'FAIL'}
  Add-Row 'RDP firewall rule for IPv6' $_s ("RDPv6FW=$fwOk")

  # Probe: Dual-stack DNS resolution works
  $v6dns = Resolve-DnsName -Name "microsoft.com" -Type AAAA -ErrorAction SilentlyContinue; $v6dnsOk = @($v6dns).Count -gt 0
  $_s = if($v6dnsOk){'OK'}elseif(!$v6dnsOk){'WARN'}else{'FAIL'}
  Add-Row 'Dual-stack DNS resolution works' $_s ("AAAARecords=$(@($v6dns).Count)")

  # Probe: Teredo/ISATAP transition disabled
  $teredo = Get-NetTeredoConfiguration -ErrorAction SilentlyContinue; $tDisabled = if($teredo){$teredo.Type -eq "Disabled"}else{$true}
  $_s = if($tDisabled){'OK'}elseif(!$tDisabled){'WARN'}else{'FAIL'}
  Add-Row 'Teredo/ISATAP transition disabled' $_s ("Teredo=$(if($teredo){$teredo.Type}else{'N/A'})")

}

$fail=@($rows|Where-Object Status -eq 'FAIL').Count
$warn=@($rows|Where-Object Status -eq 'WARN').Count
Write-Output '-- Decision --'
Add-Row 'Likely cause severity' $(if($fail -gt 0){'FAIL'}elseif($warn -gt 0){'WARN'}else{'OK'}) $(if($fail -gt 0){'Hard configuration/service break'}elseif($warn -gt 0){'Configuration drift or transient condition'}else{'No blocking signals'})
Add-Row 'Next action' 'OK' $(if($fail -gt 0){'Follow README interpretation and remediate FAIL rows first'}elseif($warn -gt 0){'Review WARN rows and re-run after targeted fix'}else{'No immediate action'})
Write-Output '-- More Info --'
Add-Row 'Remediation references available' 'OK' 'See paired README Learn References'

$ok=@($rows|Where-Object Status -eq 'OK').Count
Write-Output ''
Write-Output "=== RESULT: $ok OK / $fail FAIL / $warn WARN ==="
$rows

