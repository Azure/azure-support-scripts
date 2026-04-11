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

Write-Output '=== Windows Route Table Anomaly Check ==='
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
  # Probe: Default gateway configured
  $gw = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne "0.0.0.0" }; $gwCount = @($gw).Count
  $_s = if($gwCount -eq 0){'FAIL'}elseif($gwCount -ge 1){'OK'}else{'WARN'}
  Add-Row 'Default gateway configured' $_s ("DefaultGateways=$gwCount $(if($gw){$gw[0].NextHop})")

  # Probe: Single default route (no split)
  $_s = if($gwCount -eq 1){'OK'}elseif($gwCount -gt 1){'WARN'}else{'FAIL'}
  Add-Row 'Single default route (no split)' $_s ("Routes=$gwCount (1=normal)")

  # Probe: IMDS route 169.254.169.254
  $imds = Get-NetRoute -DestinationPrefix "169.254.169.254/32" -ErrorAction SilentlyContinue; $imdsOk = @($imds).Count -gt 0
  $_s = if($imdsOk){'OK'}elseif(!$imdsOk){'WARN'}else{'FAIL'}
  Add-Row 'IMDS route 169.254.169.254' $_s ("IMDSRoute=$imdsOk")

  # Probe: Persistent routes count
  $persist = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object { $_.Protocol -eq "NetMgmt" }; $persistCount = @($persist).Count
  $_s = if($persistCount -le 10){'OK'}elseif($persistCount -gt 10){'WARN'}else{'FAIL'}
  Add-Row 'Persistent routes count' $_s ("PersistentRoutes=$persistCount")

  # Probe: WireServer route (168.63.129.16)
  $ws = Get-NetRoute -DestinationPrefix "168.63.129.16/32" -ErrorAction SilentlyContinue; $wsOk = @($ws).Count -gt 0
  $_s = if($wsOk){'OK'}elseif(!$wsOk){'WARN'}else{'FAIL'}
  Add-Row 'WireServer route (168.63.129.16)' $_s ("WireServerRoute=$wsOk")

  # Probe: No blackhole routes (unreachable)
  $bh = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Unreachable" -or $_.NextHop -eq "0.0.0.0" -and $_.DestinationPrefix -ne "0.0.0.0/0" -and $_.DestinationPrefix -ne "255.255.255.255/32" }; $bhCount = @($bh).Count
  $_s = if($bhCount -le 5){'OK'}elseif($bhCount -gt 5){'WARN'}else{'FAIL'}
  Add-Row 'No blackhole routes (unreachable)' $_s ("SuspectRoutes=$bhCount")

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

