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

Write-Output '=== Windows Storage Spaces Health ==='
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
  # Probe: Storage Spaces subsystem
  $ss = Get-StorageSubSystem -ErrorAction SilentlyContinue | Select-Object -First 1; $ssOk = $ss -ne $null
  $_s = if($ssOk){'OK'}elseif(!$ssOk){'WARN'}else{'FAIL'}
  Add-Row 'Storage Spaces subsystem' $_s ("Subsystem=$(if($ss){$ss.FriendlyName}else{'Not found'})")

  # Probe: Storage pool health
  $pool = Get-StoragePool -IsPrimordial $false -ErrorAction SilentlyContinue; $poolCount = @($pool).Count; $unhealthy = @($pool | Where-Object HealthStatus -ne "Healthy").Count
  $_s = if($unhealthy -gt 0){'FAIL'}elseif($unhealthy -eq 0){'OK'}else{'WARN'}
  Add-Row 'Storage pool health' $_s ("Pools=$poolCount Unhealthy=$unhealthy")

  # Probe: Virtual disk health
  $vd = Get-VirtualDisk -ErrorAction SilentlyContinue; $vdUnhealthy = @($vd | Where-Object HealthStatus -ne "Healthy").Count
  $_s = if($vdUnhealthy -gt 0){'FAIL'}elseif($vdUnhealthy -eq 0){'OK'}else{'WARN'}
  Add-Row 'Virtual disk health' $_s ("VDisks=$(@($vd).Count) Unhealthy=$vdUnhealthy")

  # Probe: Physical disk health
  $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue; $pdWarn = @($pd | Where-Object HealthStatus -ne "Healthy").Count; $pdTotal = @($pd).Count
  $_s = if($pdWarn -eq 0){'OK'}elseif($pdWarn -gt 0){'WARN'}else{'FAIL'}
  Add-Row 'Physical disk health' $_s ("PhysDisks=$pdTotal Unhealthy=$pdWarn")

  # Probe: Storage Spaces Direct (S2D) state
  $s2d = Get-ClusterS2D -ErrorAction SilentlyContinue; $s2dOk = if($s2d){$s2d.State -eq "Enabled"}else{$null}
  $_s = if($s2dOk -eq $true -or $s2dOk -eq $null){'OK'}elseif($s2dOk -eq $false){'WARN'}else{'FAIL'}
  Add-Row 'Storage Spaces Direct (S2D) state' $_s ("S2D=$(if($s2dOk -eq $null){'N/A (not clustered)'}else{$s2d.State})")

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

