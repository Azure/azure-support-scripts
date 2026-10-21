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

Write-Output '=== Windows Event Forwarding (WEF) Health ==='
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
  # Probe: Windows Event Collector service
  $wecsvc = Get-Service Wecsvc -ErrorAction SilentlyContinue
  $_s = if($wecsvc -and $wecsvc.Status -eq "Running"){'OK'}elseif(!$wecsvc -or $wecsvc.Status -ne "Running"){'WARN'}else{'FAIL'}
  Add-Row 'Windows Event Collector service' $_s ("Status=$(if($wecsvc){$wecsvc.Status}else{'NotFound'})")

  # Probe: WinRM service running
  $winrm = Get-Service WinRM -ErrorAction SilentlyContinue
  $_s = if(!$winrm -or $winrm.Status -ne "Running"){'FAIL'}elseif($winrm -and $winrm.Status -eq "Running"){'OK'}else{'WARN'}
  Add-Row 'WinRM service running' $_s ("Status=$(if($winrm){$winrm.Status}else{'NotFound'})")

  # Probe: Event subscriptions configured
  $wecutil = wecutil es 2>&1; $subCount = if($LASTEXITCODE -eq 0){ @($wecutil | Where-Object { $_.Trim() }).Count } else { 0 }
  $_s = if($subCount -gt 0){'OK'}elseif($subCount -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'Event subscriptions configured' $_s ("Subscriptions=$subCount")

  # Probe: ForwardedEvents log exists
  $fe = Get-WinEvent -ListLog ForwardedEvents -ErrorAction SilentlyContinue
  $_s = if($fe -ne $null){'OK'}elseif($fe -eq $null){'WARN'}else{'FAIL'}
  Add-Row 'ForwardedEvents log exists' $_s ("$(if($fe){`"MaxSizeMB=$([math]::Round($fe.MaximumSizeInBytes/1MB,0))`"}else{'Log missing'})")

  # Probe: WinRM listener configured
  $listener = winrm enumerate winrm/config/listener 2>&1; $lisOk = $listener -match "Transport"
  $_s = if($lisOk){'OK'}elseif(!$lisOk){'WARN'}else{'FAIL'}
  Add-Row 'WinRM listener configured' $_s ("$(if($lisOk){'Listener active'}else{'No listener'})")

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

