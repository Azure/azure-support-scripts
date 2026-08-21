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

Write-Output '=== Windows Boot Policy Drift Check ==='
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
  # Probe: BCD store accessible
  $bcd = bcdedit /enum "{bootmgr}" 2>&1; $bcdOk = $LASTEXITCODE -eq 0
  $_s = if(!$bcdOk){'FAIL'}elseif($bcdOk){'OK'}else{'WARN'}
  Add-Row 'BCD store accessible' $_s ("")

  # Probe: Default boot entry points to Windows
  $def = bcdedit /enum "{default}" 2>&1 | Select-String "osdevice"; $defOk = $def -match "partition="
  $_s = if(!$defOk){'FAIL'}elseif($defOk){'OK'}else{'WARN'}
  Add-Row 'Default boot entry points to Windows' $_s ("$def")

  # Probe: Secure Boot state
  try { $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue } catch { $sb = $null }
  $_s = if($sb -eq $true){'OK'}elseif($sb -ne $true){'WARN'}else{'FAIL'}
  Add-Row 'Secure Boot state' $_s ("SecureBoot=$(if($sb -eq $true){'ON'}elseif($sb -eq $false){'OFF'}else{'N/A'})")

  # Probe: Boot status policy (ignore failures)
  $bsp = bcdedit /enum "{default}" 2>&1 | Select-String "bootstatuspolicy"; $bspOk = $bsp -match "IgnoreAllFailures"
  $_s = if($bspOk){'OK'}elseif(!$bspOk){'WARN'}else{'FAIL'}
  Add-Row 'Boot status policy (ignore failures)' $_s ("$(if($bsp){$bsp.ToString().Trim()}else{'default'})")

  # Probe: Recovery sequence configured
  $rec = bcdedit /enum "{default}" 2>&1 | Select-String "recoverysequence"; $recOk = $rec -ne $null
  $_s = if($recOk){'OK'}elseif(!$recOk){'WARN'}else{'FAIL'}
  Add-Row 'Recovery sequence configured' $_s ("$(if($rec){'present'}else{'absent'})")

  # Probe: Integrity checks enabled
  $ic = bcdedit /enum "{default}" 2>&1 | Select-String "nointegritychecks"; $icOk = $ic -eq $null -or $ic -match "No"
  $_s = if(!$icOk){'FAIL'}elseif($icOk){'OK'}else{'WARN'}
  Add-Row 'Integrity checks enabled' $_s ("$(if($ic){$ic.ToString().Trim()}else{'not set (default=on)'})")

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

