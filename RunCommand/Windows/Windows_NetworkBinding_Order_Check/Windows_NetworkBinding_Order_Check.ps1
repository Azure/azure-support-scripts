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

Write-Output '=== Windows Network Binding Order Check ==='
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
  # Probe: Primary NIC interface metric
  $primary = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionState -eq "Connected" } | Sort-Object InterfaceMetric | Select-Object -First 1; $metric = if($primary){$primary.InterfaceMetric}else{9999}
  $_s = if($metric -lt 50){'OK'}elseif($metric -ge 50){'WARN'}else{'FAIL'}
  Add-Row 'Primary NIC interface metric' $_s ("PrimaryMetric=$metric Iface=$(if($primary){$primary.InterfaceAlias}else{'none'})")

  # Probe: No duplicate interface metrics
  $metrics = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionState -eq "Connected" }; $dupMetrics = @($metrics | Group-Object InterfaceMetric | Where-Object Count -gt 1).Count
  $_s = if($dupMetrics -eq 0){'OK'}elseif($dupMetrics -gt 0){'WARN'}else{'FAIL'}
  Add-Row 'No duplicate interface metrics' $_s ("DuplicateMetrics=$dupMetrics")

  # Probe: DNS client NIC registration order
  $dnsNics = Get-DnsClient -ErrorAction SilentlyContinue | Where-Object { $_.RegisterThisConnectionsAddress -eq $true }; $regCount = @($dnsNics).Count
  $_s = if($regCount -ge 1){'OK'}elseif($regCount -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'DNS client NIC registration order' $_s ("RegisteredNICs=$regCount")

  # Probe: Primary adapter binding complete
  $bound = Get-NetAdapterBinding -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true -and $_.ComponentId -eq "ms_tcpip" }; $boundCount = @($bound).Count
  $_s = if($boundCount -ge 1){'OK'}elseif($boundCount -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'Primary adapter binding complete' $_s ("TCPIPBound=$boundCount")

  # Probe: ISATAP/Teredo not preferred
  $isatap = Get-NetIPInterface -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -match "isatap|Teredo" -and $_.ConnectionState -eq "Connected" }; $tunnelActive = @($isatap).Count
  $_s = if($tunnelActive -eq 0){'OK'}elseif($tunnelActive -gt 0){'WARN'}else{'FAIL'}
  Add-Row 'ISATAP/Teredo not preferred' $_s ("TunnelIfaces=$tunnelActive")

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

