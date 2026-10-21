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

Write-Output '=== Windows RDP Certificate Binding Check ==='
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
  $rdp='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
  $thumb=(Get-ItemProperty $rdp -Name SSLCertificateSHA1Hash -ErrorAction SilentlyContinue).SSLCertificateSHA1Hash
  Add-Row 'RDP certificate thumbprint configured' $(if($thumb){'OK'}else{'WARN'}) ''
  $store = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumb }
  Add-Row 'Bound certificate present in LM\\My' $(if($thumb -and $store){'OK'}elseif($thumb){'FAIL'}else{'WARN'}) ''
  $exp = if($store){$store.NotAfter -gt (Get-Date).AddDays(14)}else{$false}
  Add-Row 'Bound certificate not near expiry' $(if($store){if($exp){'OK'}else{'WARN'}}else{'WARN'}) ''
  $nla=(Get-ItemProperty $rdp -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
  Add-Row 'NLA setting readable' $(if($null -ne $nla){'OK'}else{'WARN'}) ''
  $listen = ((netstat -an) -match ':3389\s+.*LISTENING').Count -gt 0
  Add-Row 'RDP port 3389 listening' $(if($listen){'OK'}else{'FAIL'}) ''
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
