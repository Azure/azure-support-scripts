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
$mock=$null
$usedMock=$false
if($MockConfig -and (Test-Path $MockConfig)){
  $mock=Get-Content $MockConfig -Raw | ConvertFrom-Json
  if($mock.profiles -and $mock.profiles.$MockProfile){
    $usedMock=$true
    foreach($i in $mock.profiles.$MockProfile){ Add-Row $i.name $i.status $i.detail }
  }
}

Write-Output '=== Windows TLS + RDP Compatibility Audit ==='
Write-Output ('{0} {1}' -f (Pad 'Check' $W), 'Status')
Write-Output (('-' * $W) + ' ------')

if(-not $usedMock){
Write-Output '-- RDP Core --'
  $nla=[int]$mock.rdp.userAuthentication
}else{
  $portListen=((& netstat -an 2>$null) -match ':3389\s+.*LISTENING').Count -gt 0
Add-Row 'RDP 3389 listening' $(if($portListen){'OK'}else{'FAIL'}) ''
Add-Row 'NLA setting present' $(if($null -ne $nla){'OK'}else{'WARN'}) "UserAuthentication=$nla"
Add-Row 'SecurityLayer valid (0/1/2)' $(if($sec -in 0,1,2){'OK'}else{'WARN'}) "SecurityLayer=$sec"
Write-Output '-- TLS Protocols --'
if($mock){
  $tls12Server=[bool]$mock.tls.tls12ServerEnabled
  $tls10Server=[bool]$mock.tls.tls10ServerEnabled
}else{
  $k10='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'
  $tls12Server=((Get-ItemProperty $k12 -Name Enabled -ErrorAction SilentlyContinue).Enabled -eq 1)
  $tls10Server=((Get-ItemProperty $k10 -Name Enabled -ErrorAction SilentlyContinue).Enabled -eq 1)
}
Add-Row 'TLS 1.2 server enabled' $(if($tls12Server){'OK'}else{'FAIL'}) ''
Add-Row 'TLS 1.0 server enabled' $(if($tls10Server){'WARN'}else{'OK'}) 'Warn when legacy protocol enabled'
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
