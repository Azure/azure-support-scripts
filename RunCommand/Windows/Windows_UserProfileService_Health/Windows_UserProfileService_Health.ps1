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

Write-Output '=== Windows User Profile Service Health ==='
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
  # Probe: Profile Service running
  $prof = Get-Service ProfSvc -ErrorAction SilentlyContinue
  $_s = if(!$prof -or $prof.Status -ne "Running"){'FAIL'}elseif($prof -and $prof.Status -eq "Running"){'OK'}else{'WARN'}
  Add-Row 'Profile Service running' $_s ("Status=$(if($prof){$prof.Status}else{'NotFound'})")

  # Probe: Profile list registry entries
  $pl = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" -ErrorAction SilentlyContinue; $plCount = @($pl).Count
  $_s = if($plCount -ge 2){'OK'}elseif($plCount -lt 2){'WARN'}else{'FAIL'}
  Add-Row 'Profile list registry entries' $_s ("Profiles=$plCount")

  # Probe: Temporary profiles present
  $tmp = @($pl | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } | Where-Object { $_.ProfileImagePath -match "TEMP" }).Count
  $_s = if($tmp -gt 0){'FAIL'}elseif($tmp -eq 0){'OK'}else{'WARN'}
  Add-Row 'Temporary profiles present' $_s ("TempProfiles=$tmp")

  # Probe: Profile size on C: (Users folder)
  $usersSize = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object { (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } | Measure-Object -Sum; $usersMB = [math]::Round($usersSize.Sum / 1MB, 0)
  $_s = if($usersMB -lt 10000){'OK'}elseif($usersMB -ge 10000){'WARN'}else{'FAIL'}
  Add-Row 'Profile size on C: (Users folder)' $_s ("UsersMB=$usersMB")

  # Probe: Profile load errors (7d)
  $profErr = Get-WinEvent -FilterHashtable @{LogName="Application";Id=1511,1515,1500;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 10 -ErrorAction SilentlyContinue; $profErrCount = @($profErr).Count
  $_s = if($profErrCount -eq 0){'OK'}elseif($profErrCount -le 3){'WARN'}else{'FAIL'}
  Add-Row 'Profile load errors (7d)' $_s ("ProfileErrors=$profErrCount")

  # Probe: Default profile intact
  $defProf = Test-Path "C:\Users\Default\NTUSER.DAT"
  $_s = if(!$defProf){'FAIL'}elseif($defProf){'OK'}else{'WARN'}
  Add-Row 'Default profile intact' $_s ("DefaultProfile=$defProf")

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

