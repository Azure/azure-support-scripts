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

Write-Output '=== Windows Group Policy Processing Health ==='
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
  $gpsvc = Get-Service gpsvc -ErrorAction SilentlyContinue
  Add-Row 'GPSvc service running' $(if($gpsvc -and $gpsvc.Status -eq 'Running'){'OK'}else{'FAIL'}) ''
  $ev = Get-WinEvent -LogName 'Microsoft-Windows-GroupPolicy/Operational' -MaxEvents 50 -ErrorAction SilentlyContinue
  Add-Row 'GroupPolicy operational log readable' $(if($ev){'OK'}else{'WARN'}) ''
  $errs = @($ev | Where-Object LevelDisplayName -in @('Error','Critical')).Count
  Add-Row 'Recent GP errors below threshold' $(if($errs -gt 5){'WARN'}else{'OK'}) "Errors=$errs"
  $netlogon = Test-Path '\\localhost\NETLOGON'
  Add-Row 'NETLOGON path accessible' $(if($netlogon){'OK'}else{'WARN'}) ''
  $sysvol = Test-Path '\\localhost\SYSVOL'
  Add-Row 'SYSVOL path accessible' $(if($sysvol){'OK'}else{'WARN'}) ''
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
