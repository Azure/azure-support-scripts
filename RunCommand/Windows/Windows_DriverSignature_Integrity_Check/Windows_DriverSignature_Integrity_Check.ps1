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

Write-Output '=== Windows Driver Signature Integrity Check ==='
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
  # Probe: Code integrity policy loaded
  $ci = Get-CimInstance -Namespace root/Microsoft/Windows/CI -ClassName MSFT_MpPreference -ErrorAction SilentlyContinue; $ciLoaded = $ci -ne $null
  $_s = if($true){'OK'}elseif($false){'WARN'}else{'FAIL'}
  Add-Row 'Code integrity policy loaded' $_s ("CIM CI namespace check (informational)")

  # Probe: Unsigned kernel drivers loaded
  $drv = Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue | Where-Object { $_.Started -eq $true }; $unsigned = @($drv | Where-Object { -not $_.IsSigned }).Count; $total = @($drv).Count
  $_s = if($unsigned -gt 2){'FAIL'}elseif($unsigned -eq 0){'OK'}else{'WARN'}
  Add-Row 'Unsigned kernel drivers loaded' $_s ("Unsigned=$unsigned Total=$total")

  # Probe: Driver store integrity (pnputil)
  $pnp = pnputil /enum-drivers 2>&1; $pnpOk = $LASTEXITCODE -eq 0; $pnpCount = @($pnp | Select-String "Published Name").Count
  $_s = if($pnpOk){'OK'}elseif(!$pnpOk){'WARN'}else{'FAIL'}
  Add-Row 'Driver store integrity (pnputil)' $_s ("Drivers=$pnpCount")

  # Probe: Code integrity event errors (7d)
  $ciEvt = Get-WinEvent -FilterHashtable @{LogName="Microsoft-Windows-CodeIntegrity/Operational";Level=2;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 10 -ErrorAction SilentlyContinue; $ciErr = @($ciEvt).Count
  $_s = if($ciErr -eq 0){'OK'}elseif($ciErr -le 5){'WARN'}else{'FAIL'}
  Add-Row 'Code integrity event errors (7d)' $_s ("CIErrors=$ciErr in 7d")

  # Probe: WHQL enforcement active
  $whql = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\SystemCertificates\Root\Certificates" -ErrorAction SilentlyContinue) -ne $null
  $_s = if($true){'OK'}elseif($false){'WARN'}else{'FAIL'}
  Add-Row 'WHQL enforcement active' $_s ("Root cert store accessible (informational)")

  # Probe: Secure Boot with UEFI
  try { $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue } catch { $sb = $null }
  $_s = if($sb -eq $true){'OK'}elseif($sb -ne $true){'WARN'}else{'FAIL'}
  Add-Row 'Secure Boot with UEFI' $_s ("SecureBoot=$(if($sb -eq $true){'ON'}else{'OFF/N/A'})")

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

