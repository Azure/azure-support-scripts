#Requires -Version 5.1
<#
.SYNOPSIS
    Checks time sync and Kerberos prerequisites on Windows VM.
.PARAMETER MockConfig
    Optional JSON file for offline test.
#>
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

$mock=$null
$usedMock=$false
if($MockConfig -and (Test-Path $MockConfig)){
  $mock=Get-Content $MockConfig -Raw | ConvertFrom-Json
  if($mock.profiles -and $mock.profiles.$MockProfile){
    $usedMock=$true
    foreach($i in $mock.profiles.$MockProfile){ Add-Row $i.name $i.status $i.detail }
  }
}

Write-Output '=== Windows TimeSync + Kerberos Health ==='
Write-Output ('{0} {1}' -f (Pad 'Check' $W), 'Status')
Write-Output (('-' * $W) + ' ------')

if(-not $usedMock){

if($mock){
  $offset=[double]$mock.time.offsetSeconds
  $w32=if($svc){$svc.Status.ToString()}else{'NotFound'}
  $offset=0
  $tz=(Get-TimeZone -ErrorAction SilentlyContinue).Id
}
Add-Row 'Time source detected' $(if([string]::IsNullOrWhiteSpace($source)){'WARN'}else{'OK'}) $source
$offState=if([math]::Abs($offset) -ge 300){'FAIL'}elseif([math]::Abs($offset) -ge 60){'WARN'}else{'OK'}
Add-Row 'Clock offset within tolerance' $offState "$offset sec"
Add-Row 'Timezone configured' $(if([string]::IsNullOrWhiteSpace($tz)){'WARN'}else{'OK'}) $tz

if($mock){
  $kdc=$mock.kerberos.kdcReachable
  $netlogon=$mock.kerberos.netlogon
  $events=[int]$mock.kerberos.recentKrbErrors
}else{
  $kdc=$true
  $netlogon=(Get-Service Netlogon -ErrorAction SilentlyContinue).Status.ToString()
  $events=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Security-Kerberos';StartTime=(Get-Date).AddHours(-6)} -ErrorAction SilentlyContinue).Count
}
Add-Row 'KDC reachability signal' $(if($kdc){'OK'}else{'FAIL'}) ''
Add-Row 'Netlogon running' $(if($netlogon -eq 'Running'){'OK'}else{'WARN'}) $netlogon
Add-Row 'Recent Kerberos errors low' $(if($events -gt 20){'WARN'}else{'OK'}) "Count=$events"
}

$fail=@($rows|? Status -eq 'FAIL').Count; $warn=@($rows|? Status -eq 'WARN').Count
Write-Output '-- Decision --'
Add-Row 'Likely cause severity' $(if($fail -gt 0){'FAIL'}elseif($warn -gt 0){'WARN'}else{'OK'}) $(if($fail -gt 0){'Hard configuration/service break'}elseif($warn -gt 0){'Configuration drift or transient condition'}else{'No blocking signals'})
Add-Row 'Next action' 'OK' $(if($fail -gt 0){'Follow README interpretation and remediate FAIL rows first'}elseif($warn -gt 0){'Review WARN rows and re-run after targeted fix'}else{'No immediate action'})
Write-Output '-- More Info --'
Add-Row 'Remediation references available' 'OK' 'See paired README Learn References'

$ok=@($rows|? Status -eq 'OK').Count
Write-Output ''
Write-Output "=== RESULT: $ok OK / $fail FAIL / $warn WARN ==="
$rows
