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

Write-Output '=== Windows NIC Advanced Properties Baseline ==='
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
  # Probe: RSS (Receive Side Scaling) enabled
  $adv = Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue; $rss = Get-NetAdapterRss -ErrorAction SilentlyContinue | Select-Object -First 1; $rssOn = if($rss){$rss.Enabled}else{$null}
  $_s = if($rssOn -eq $true){'OK'}elseif($rssOn -ne $true){'WARN'}else{'FAIL'}
  Add-Row 'RSS (Receive Side Scaling) enabled' $_s ("RSS=$rssOn")

  # Probe: Checksum offload enabled
  $cso = $adv | Where-Object { $_.DisplayName -match "Checksum Offload" -and $_.DisplayValue -ne "Disabled" } | Select-Object -First 1; $csoOn = $cso -ne $null
  $_s = if($csoOn){'OK'}elseif(!$csoOn){'WARN'}else{'FAIL'}
  Add-Row 'Checksum offload enabled' $_s ("ChecksumOffload=$(if($cso){$cso.DisplayValue}else{'not found'})")

  # Probe: Large Send Offload v2 (LSOv2)
  $lso = $adv | Where-Object { $_.DisplayName -match "Large Send Offload V2" -and $_.DisplayValue -ne "Disabled" } | Select-Object -First 1; $lsoOn = $lso -ne $null
  $_s = if($lsoOn){'OK'}elseif(!$lsoOn){'WARN'}else{'FAIL'}
  Add-Row 'Large Send Offload v2 (LSOv2)' $_s ("LSOv2=$(if($lso){$lso.DisplayValue}else{'not found'})")

  # Probe: VMQ (Virtual Machine Queue)
  $vmq = Get-NetAdapterVmq -ErrorAction SilentlyContinue | Select-Object -First 1; $vmqOn = if($vmq){$vmq.Enabled}else{$null}
  $_s = if($true){'OK'}elseif($false){'WARN'}else{'FAIL'}
  Add-Row 'VMQ (Virtual Machine Queue)' $_s ("VMQ=$(if($vmq){$vmq.Enabled}else{'N/A'}) (informational)")

  # Probe: Jumbo Frame not set (Azure default)
  $jumbo = $adv | Where-Object { $_.DisplayName -match "Jumbo" } | Select-Object -First 1; $jumboDefault = if($jumbo){$jumbo.DisplayValue -match "Disabled|1514"}else{$true}
  $_s = if($jumboDefault){'OK'}elseif(!$jumboDefault){'WARN'}else{'FAIL'}
  Add-Row 'Jumbo Frame not set (Azure default)' $_s ("JumboFrame=$(if($jumbo){$jumbo.DisplayValue}else{'default'})")

  # Probe: Speed and duplex auto-negotiation
  $sd = $adv | Where-Object { $_.DisplayName -match "Speed.*Duplex" } | Select-Object -First 1; $autoNeg = if($sd){$sd.DisplayValue -match "Auto"}else{$true}
  $_s = if($autoNeg){'OK'}elseif(!$autoNeg){'WARN'}else{'FAIL'}
  Add-Row 'Speed and duplex auto-negotiation' $_s ("SpeedDuplex=$(if($sd){$sd.DisplayValue}else{'auto (default)'})")

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

