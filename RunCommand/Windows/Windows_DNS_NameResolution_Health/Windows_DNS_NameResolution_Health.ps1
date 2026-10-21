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

Write-Output '=== Windows DNS Name Resolution Health ==='
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
  $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses.Count -gt 0 }
  Add-Row 'DNS servers configured' $(if($dns){'OK'}else{'FAIL'}) $(if($dns){"NICs=$(@($dns).Count)"}else{'No DNS servers'})
  $sys = Resolve-DnsName -Name 'microsoft.com' -Type A -ErrorAction SilentlyContinue
  Add-Row 'Public DNS resolution works' $(if($sys){'OK'}else{'WARN'}) ''
  $md = Resolve-DnsName -Name '169.254.169.254.nip.io' -Type A -ErrorAction SilentlyContinue
  Add-Row 'Metadata alias resolves' $(if($md){'OK'}else{'WARN'}) ''
  $suffix = Get-DnsClientGlobalSetting -ErrorAction SilentlyContinue
  Add-Row 'DNS suffix search list present' $(if($suffix.SuffixSearchList){'OK'}else{'WARN'}) ''
  $hosts = Select-String -Path "$env:windir\System32\drivers\etc\hosts" -Pattern 'microsoft.com|azure.com' -SimpleMatch -ErrorAction SilentlyContinue
  Add-Row 'Hosts overrides absent' $(if($hosts){'WARN'}else{'OK'}) ''
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
