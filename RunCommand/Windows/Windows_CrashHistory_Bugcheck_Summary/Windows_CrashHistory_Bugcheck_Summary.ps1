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

Write-Output '=== Windows Crash History Bugcheck Summary ==='
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
  # Probe: System dump file exists
  $dmp = Test-Path "$env:SystemRoot\MEMORY.DMP"
  $_s = if($dmp){'OK'}elseif(!$dmp){'WARN'}else{'FAIL'}
  Add-Row 'System dump file exists' $_s ("$env:SystemRoot\MEMORY.DMP")

  # Probe: Minidump directory populated
  $md = Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -ErrorAction SilentlyContinue; $mdCount = @($md).Count
  $_s = if($mdCount -eq 0){'OK'}elseif($mdCount -gt 0){'WARN'}else{'FAIL'}
  Add-Row 'Minidump directory populated' $_s ("Minidumps=$mdCount")

  # Probe: BugCheck events in System log (30d)
  $bc = Get-WinEvent -FilterHashtable @{LogName="System";Id=1001;ProviderName="Microsoft-Windows-WER-SystemErrorReporting";StartTime=(Get-Date).AddDays(-30)} -MaxEvents 10 -ErrorAction SilentlyContinue; $bcCount = @($bc).Count
  $_s = if($bcCount -eq 0){'OK'}elseif($bcCount -le 2){'WARN'}else{'FAIL'}
  Add-Row 'BugCheck events in System log (30d)' $_s ("Events=$bcCount in last 30d")

  # Probe: Unexpected shutdown events (30d)
  $us = Get-WinEvent -FilterHashtable @{LogName="System";Id=6008;StartTime=(Get-Date).AddDays(-30)} -MaxEvents 10 -ErrorAction SilentlyContinue; $usCount = @($us).Count
  $_s = if($usCount -eq 0){'OK'}elseif($usCount -le 3){'WARN'}else{'FAIL'}
  Add-Row 'Unexpected shutdown events (30d)' $_s ("Events=$usCount")

  # Probe: Page file configuration adequate
  $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue; $pfSize = if($pf){$pf.AllocatedBaseSize}else{0}
  $_s = if($pfSize -ge 1024){'OK'}elseif($pfSize -lt 1024 -and $pfSize -gt 0){'WARN'}else{'FAIL'}
  Add-Row 'Page file configuration adequate' $_s ("PageFileMB=$pfSize")

  # Probe: CrashControl registry settings
  $cc = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -ErrorAction SilentlyContinue; $dumpType = if($cc){$cc.CrashDumpEnabled}else{-1}
  $_s = if($dumpType -ge 1){'OK'}elseif($dumpType -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'CrashControl registry settings' $_s ("DumpType=$dumpType (1=Complete 2=Kernel 3=Small)")

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

