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

Write-Output '=== Windows Startup Delay Analyzer ==='
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
  # Probe: Last boot time
  $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime; $uptimeH = [math]::Round(((Get-Date) - $boot).TotalHours, 1)
  $_s = if($true){'OK'}elseif($false){'WARN'}else{'FAIL'}
  Add-Row 'Last boot time' $_s ("Boot=$boot Uptime=$($uptimeH)h")

  # Probe: Boot duration (Kernel+User init)
  $bootEvt = Get-WinEvent -FilterHashtable @{LogName="Microsoft-Windows-Diagnostics-Performance/Operational";Id=100} -MaxEvents 1 -ErrorAction SilentlyContinue; $bootMs = if($bootEvt){ ($bootEvt.Properties | Where-Object { $_.Value -is [int64] } | Select-Object -First 1).Value } else { -1 }; $bootSec = if($bootMs -gt 0){[math]::Round($bootMs/1000,0)}else{-1}
  $_s = if($bootSec -lt 60 -and $bootSec -ge 0){'OK'}elseif($bootSec -ge 60 -and $bootSec -lt 180){'WARN'}else{'FAIL'}
  Add-Row 'Boot duration (Kernel+User init)' $_s ("BootSec=$bootSec")

  # Probe: Logon delay events
  $logon = Get-WinEvent -FilterHashtable @{LogName="Microsoft-Windows-Diagnostics-Performance/Operational";Id=101} -MaxEvents 5 -ErrorAction SilentlyContinue; $logonCount = @($logon).Count
  $_s = if($logonCount -eq 0){'OK'}elseif($logonCount -le 3){'WARN'}else{'FAIL'}
  Add-Row 'Logon delay events' $_s ("LogonDelayEvents=$logonCount")

  # Probe: Auto-start program delays
  $startupApps = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue; $startCount = @($startupApps).Count
  $_s = if($startCount -lt 15){'OK'}elseif($startCount -ge 15){'WARN'}else{'FAIL'}
  Add-Row 'Auto-start program delays' $_s ("StartupApps=$startCount")

  # Probe: GroupPolicy processing time
  $gpEvt = Get-WinEvent -FilterHashtable @{LogName="Microsoft-Windows-GroupPolicy/Operational";Id=8001} -MaxEvents 1 -ErrorAction SilentlyContinue; $gpMs = if($gpEvt){ ($gpEvt.Properties | Select-Object -Index 2).Value } else { -1 }
  $_s = if($gpMs -lt 30000 -and $gpMs -ge 0){'OK'}elseif($gpMs -ge 30000){'WARN'}else{'FAIL'}
  Add-Row 'GroupPolicy processing time' $_s ("GPApplyMs=$gpMs")

  # Probe: Pending reboot state
  $reboot = (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
  $_s = if(!$reboot){'OK'}elseif($reboot){'WARN'}else{'FAIL'}
  Add-Row 'Pending reboot state' $_s ("RebootPending=$reboot")

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

