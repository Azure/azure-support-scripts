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

Write-Output '=== Windows NTFS Integrity Check ==='
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
  $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveType -eq 'Fixed'
  Add-Row 'Fixed volumes detected' $(if($vols){'OK'}else{'FAIL'}) "Count=$(@($vols).Count)"
  $dirty=0
  foreach($v in $vols){ $q=(fsutil dirty query ($v.DriveLetter + ':') 2>$null); if($q -match 'is Dirty'){ $dirty++ } }
  Add-Row 'Dirty volumes count' $(if($dirty -gt 0){'WARN'}else{'OK'}) "Dirty=$dirty"
  $chk = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\BootExecute'
  Add-Row 'BootExecute key present' $(if($chk){'OK'}else{'WARN'}) ''
  $ev = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='disk'; StartTime=(Get-Date).AddHours(-24)} -ErrorAction SilentlyContinue).Count
  Add-Row 'Recent disk errors below threshold' $(if($ev -gt 20){'WARN'}else{'OK'}) "DiskEvents=$ev"
  $c = $vols | Where-Object DriveLetter -eq 'C'
  Add-Row 'OS volume C exists' $(if($c){'OK'}else{'FAIL'}) ''
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
