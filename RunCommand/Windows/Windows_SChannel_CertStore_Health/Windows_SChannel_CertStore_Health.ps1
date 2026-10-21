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

Write-Output '=== Windows SChannel & CertStore Health ==='
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
  # Probe: TLS 1.2 enabled (client)
  $tls12c = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" -Name "Enabled" -ErrorAction SilentlyContinue; $tls12cVal = if($tls12c){$tls12c.Enabled}else{1}
  $_s = if($tls12cVal -eq 0){'FAIL'}elseif($tls12cVal -ne 0){'OK'}else{'WARN'}
  Add-Row 'TLS 1.2 enabled (client)' $_s ("TLS1.2Client=$(if($tls12cVal -ne 0){'Enabled'}else{'Disabled'})")

  # Probe: TLS 1.2 enabled (server)
  $tls12s = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" -Name "Enabled" -ErrorAction SilentlyContinue; $tls12sVal = if($tls12s){$tls12s.Enabled}else{1}
  $_s = if($tls12sVal -eq 0){'FAIL'}elseif($tls12sVal -ne 0){'OK'}else{'WARN'}
  Add-Row 'TLS 1.2 enabled (server)' $_s ("TLS1.2Server=$(if($tls12sVal -ne 0){'Enabled'}else{'Disabled'})")

  # Probe: SSL 3.0 disabled
  $ssl3 = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server" -Name "Enabled" -ErrorAction SilentlyContinue; $ssl3Val = if($ssl3){$ssl3.Enabled}else{0}
  $_s = if($ssl3Val -eq 0){'OK'}elseif($ssl3Val -ne 0){'WARN'}else{'FAIL'}
  Add-Row 'SSL 3.0 disabled' $_s ("SSL3=$(if($ssl3Val -eq 0){'Disabled'}else{'Enabled'})")

  # Probe: Personal cert store populated
  $certs = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue; $certCount = @($certs).Count
  $_s = if($certCount -ge 1){'OK'}elseif($certCount -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'Personal cert store populated' $_s ("PersonalCerts=$certCount")

  # Probe: Root CA store accessible
  $roots = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue; $rootCount = @($roots).Count
  $_s = if($rootCount -ge 10){'OK'}elseif($rootCount -lt 10){'WARN'}else{'FAIL'}
  Add-Row 'Root CA store accessible' $_s ("RootCAs=$rootCount")

  # Probe: Expired certs in Personal store
  $expired = @($certs | Where-Object { $_.NotAfter -lt (Get-Date) }).Count
  $_s = if($expired -eq 0){'OK'}elseif($expired -gt 0){'WARN'}else{'FAIL'}
  Add-Row 'Expired certs in Personal store' $_s ("Expired=$expired")

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

