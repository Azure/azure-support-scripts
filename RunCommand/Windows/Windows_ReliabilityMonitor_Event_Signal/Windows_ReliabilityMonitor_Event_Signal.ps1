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

Write-Output '=== Windows Reliability Monitor Event Signal ==='
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
  # Probe: Application failures (7d)
  $af = Get-WinEvent -FilterHashtable @{LogName="Application";Id=1000;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 20 -ErrorAction SilentlyContinue; $afCount = @($af).Count
  $_s = if($afCount -eq 0){'OK'}elseif($afCount -le 5){'WARN'}else{'FAIL'}
  Add-Row 'Application failures (7d)' $_s ("AppCrashes=$afCount")

  # Probe: Application hangs (7d)
  $ah = Get-WinEvent -FilterHashtable @{LogName="Application";Id=1002;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 20 -ErrorAction SilentlyContinue; $ahCount = @($ah).Count
  $_s = if($ahCount -eq 0){'OK'}elseif($ahCount -le 3){'WARN'}else{'FAIL'}
  Add-Row 'Application hangs (7d)' $_s ("AppHangs=$ahCount")

  # Probe: Windows failures/BSODs (30d)
  $wf = Get-WinEvent -FilterHashtable @{LogName="System";Id=1001;ProviderName="Microsoft-Windows-WER-SystemErrorReporting";StartTime=(Get-Date).AddDays(-30)} -MaxEvents 10 -ErrorAction SilentlyContinue; $wfCount = @($wf).Count
  $_s = if($wfCount -gt 2){'FAIL'}elseif($wfCount -eq 0){'OK'}else{'WARN'}
  Add-Row 'Windows failures/BSODs (30d)' $_s ("SystemCrashes=$wfCount")

  # Probe: Service termination events (7d)
  $st = Get-WinEvent -FilterHashtable @{LogName="System";Id=7034;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 20 -ErrorAction SilentlyContinue; $stCount = @($st).Count
  $_s = if($stCount -eq 0){'OK'}elseif($stCount -le 5){'WARN'}else{'FAIL'}
  Add-Row 'Service termination events (7d)' $_s ("SvcTerminations=$stCount")

  # Probe: Disk errors (7d)
  $de = Get-WinEvent -FilterHashtable @{LogName="System";Id=7,11,51;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 10 -ErrorAction SilentlyContinue; $deCount = @($de).Count
  $_s = if($deCount -gt 3){'FAIL'}elseif($deCount -eq 0){'OK'}else{'WARN'}
  Add-Row 'Disk errors (7d)' $_s ("DiskErrors=$deCount")

  # Probe: Unexpected shutdown events (14d)
  $us = Get-WinEvent -FilterHashtable @{LogName="System";Id=6008;StartTime=(Get-Date).AddDays(-14)} -MaxEvents 10 -ErrorAction SilentlyContinue; $usCount = @($us).Count
  $_s = if($usCount -eq 0){'OK'}elseif($usCount -le 2){'WARN'}else{'FAIL'}
  Add-Row 'Unexpected shutdown events (14d)' $_s ("UnexpectedShutdowns=$usCount")

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

