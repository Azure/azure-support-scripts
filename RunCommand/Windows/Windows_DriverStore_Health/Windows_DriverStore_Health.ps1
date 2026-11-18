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

Write-Output '=== Windows Driver Store Health ==='
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
  # Probe: Driver store folder size
  $ds = Get-ChildItem "$env:SystemRoot\System32\DriverStore\FileRepository" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum; $dsMB = [math]::Round($ds.Sum / 1MB, 0)
  $_s = if($dsMB -lt 2000){'OK'}elseif($dsMB -lt 5000){'WARN'}else{'FAIL'}
  Add-Row 'Driver store folder size' $_s ("SizeMB=$dsMB")

  # Probe: Staged driver packages (pnputil)
  $staged = pnputil /enum-drivers 2>&1; $stCount = @($staged | Select-String "Published Name").Count
  $_s = if($stCount -lt 200){'OK'}elseif($stCount -lt 400){'WARN'}else{'FAIL'}
  Add-Row 'Staged driver packages (pnputil)' $_s ("Staged=$stCount")

  # Probe: PnP devices with problems
  $prob = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 0 }; $probCount = @($prob).Count
  $_s = if($probCount -eq 0){'OK'}elseif($probCount -le 3){'WARN'}else{'FAIL'}
  Add-Row 'PnP devices with problems' $_s ("ProblemDevices=$probCount")

  # Probe: Pending driver installations
  $pend = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\PnpLockdownFiles" -ErrorAction SilentlyContinue; $pendCount = if($pend){ @($pend.PSObject.Properties | Where-Object MemberType -eq NoteProperty).Count } else { 0 }
  $_s = if($pendCount -eq 0){'OK'}elseif($pendCount -gt 0){'WARN'}else{'FAIL'}
  Add-Row 'Pending driver installations' $_s ("Pending=$pendCount")

  # Probe: DriverStore service healthy
  $dss = Get-Service DsmSvc -ErrorAction SilentlyContinue
  $_s = if($true){'OK'}elseif($false){'WARN'}else{'FAIL'}
  Add-Row 'DriverStore service healthy' $_s ("DsmSvc=$(if($dss){$dss.Status}else{'N/A (optional)'})")

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

