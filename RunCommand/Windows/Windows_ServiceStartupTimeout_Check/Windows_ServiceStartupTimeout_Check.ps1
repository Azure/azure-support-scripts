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

Write-Output '=== Windows Service Startup Timeout Check ==='
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
  # Probe: ServicesPipeTimeout value
  $spt = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "ServicesPipeTimeout" -ErrorAction SilentlyContinue; $sptVal = if($spt){$spt.ServicesPipeTimeout}else{30000}
  $_s = if($sptVal -ge 30000 -and $sptVal -le 120000){'OK'}elseif($sptVal -gt 120000 -or $sptVal -lt 30000){'WARN'}else{'FAIL'}
  Add-Row 'ServicesPipeTimeout value' $_s ("Timeout=$sptVal ms")

  # Probe: Auto-start services failed
  $auto = Get-Service | Where-Object { $_.StartType -eq "Automatic" -and $_.Status -ne "Running" } -ErrorAction SilentlyContinue; $failedAuto = @($auto).Count
  $_s = if($failedAuto -eq 0){'OK'}elseif($failedAuto -le 3){'WARN'}else{'FAIL'}
  Add-Row 'Auto-start services failed' $_s ("FailedAutoStart=$failedAuto")

  # Probe: Service Control Manager errors (7d)
  $scm = Get-WinEvent -FilterHashtable @{LogName="System";Id=7000,7011,7022,7023,7024;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 20 -ErrorAction SilentlyContinue; $scmCount = @($scm).Count
  $_s = if($scmCount -eq 0){'OK'}elseif($scmCount -le 5){'WARN'}else{'FAIL'}
  Add-Row 'Service Control Manager errors (7d)' $_s ("SCMErrors=$scmCount")

  # Probe: Service timeout events (7011)
  $to = Get-WinEvent -FilterHashtable @{LogName="System";Id=7011;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 10 -ErrorAction SilentlyContinue; $toCount = @($to).Count
  $_s = if($toCount -gt 2){'FAIL'}elseif($toCount -eq 0){'OK'}else{'WARN'}
  Add-Row 'Service timeout events (7011)' $_s ("TimeoutEvents=$toCount")

  # Probe: Critical services running
  $crit = @("W32Time","Dhcp","Dnscache","LanmanWorkstation","LanmanServer"); $down = @($crit | ForEach-Object { Get-Service $_ -ErrorAction SilentlyContinue } | Where-Object { $_.Status -ne "Running" }).Count
  $_s = if($down -gt 0){'FAIL'}elseif($down -eq 0){'OK'}else{'WARN'}
  Add-Row 'Critical services running' $_s ("CriticalDown=$down")

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

