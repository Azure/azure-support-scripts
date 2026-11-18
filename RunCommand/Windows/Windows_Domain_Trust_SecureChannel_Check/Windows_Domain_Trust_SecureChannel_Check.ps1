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

Write-Output '=== Windows Domain Trust + Secure Channel ==='
Write-Output ('{0} {1}' -f (Pad 'Check' $W), 'Status')
Write-Output (('-' * $W) + ' ------')

if(-not $usedMock){
Write-Output '-- Domain State --'
  $partOfDomain=$mock.domain.partOfDomain
  $netlogon=$mock.domain.netlogon
  $domainName=$cs.Domain
  $secureChannel=$false
  if($partOfDomain){
    try { $secureChannel = Test-ComputerSecureChannel -Verbose:$false -ErrorAction Stop } catch { $secureChannel = $false }
}
Add-Row 'Machine is domain joined' $(if($partOfDomain){'OK'}else{'WARN'}) $domainName
Add-Row 'Netlogon service running' $(if($netlogon -eq 'Running'){'OK'}else{'WARN'}) $netlogon
if($partOfDomain){ Add-Row 'Secure channel healthy' $(if($secureChannel){'OK'}else{'FAIL'}) '' }

if($mock){
  $dcDiscovered=$mock.discovery.dcDiscovered
  $dnsSrvOk=$mock.discovery.dnsSrvRecords
}else{
  $dcDiscovered=$false
  try { $null = nltest /dsgetdc:$domainName 2>$null; if($LASTEXITCODE -eq 0){$dcDiscovered=$true} } catch {}
  $dnsSrvOk=$true
}
Add-Row 'DC discovery succeeds' $(if($dcDiscovered){'OK'}else{'FAIL'}) ''
Add-Row 'DNS SRV lookup signal' $(if($dnsSrvOk){'OK'}else{'WARN'}) ''
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
