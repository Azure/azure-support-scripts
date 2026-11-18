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

Write-Output '=== Windows Defender Health Snapshot ==='
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
  # Probe: Defender service running
  $svc = Get-Service WinDefend -ErrorAction SilentlyContinue
  $_s = if(!$svc -or $svc.Status -ne "Running"){'FAIL'}elseif($svc -and $svc.Status -eq "Running"){'OK'}else{'WARN'}
  Add-Row 'Defender service running' $_s ("Status=$(if($svc){$svc.Status}else{'NotFound'})")

  # Probe: Real-time protection enabled
  $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue; $rtp = if($mp){$mp.RealTimeProtectionEnabled}else{$null}
  $_s = if($rtp -eq $false){'FAIL'}elseif($rtp -eq $true){'OK'}else{'WARN'}
  Add-Row 'Real-time protection enabled' $_s ("RealTime=$rtp")

  # Probe: Antivirus definitions age
  $defAge = if($mp){ ((Get-Date) - $mp.AntivirusSignatureLastUpdated).Days } else { 999 }
  $_s = if($defAge -le 3){'OK'}elseif($defAge -le 7){'WARN'}else{'FAIL'}
  Add-Row 'Antivirus definitions age' $_s ("DefAgeDays=$defAge")

  # Probe: Full scan completed recently
  $lastFull = if($mp -and $mp.FullScanEndTime){ ((Get-Date) - $mp.FullScanEndTime).Days } else { 999 }
  $_s = if($lastFull -le 14){'OK'}elseif($lastFull -le 30){'WARN'}else{'FAIL'}
  Add-Row 'Full scan completed recently' $_s ("LastFullScanDays=$lastFull")

  # Probe: Tamper protection enabled
  $tp = if($mp){$mp.IsTamperProtected}else{$null}
  $_s = if($tp -eq $true){'OK'}elseif($tp -ne $true){'WARN'}else{'FAIL'}
  Add-Row 'Tamper protection enabled' $_s ("Tamper=$tp")

  # Probe: No active threats detected
  $threats = if($mp){$mp.CurrentlyDetectedThreats}else{$null}; $tc = @($threats).Count
  $_s = if($tc -eq 0){'OK'}elseif($tc -gt 0){'WARN'}else{'FAIL'}
  Add-Row 'No active threats detected' $_s ("ActiveThreats=$tc")

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

