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

Write-Output '=== Windows Power Plan Throttling Check ==='
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
  # Probe: Active power plan
  $plan = powercfg /getactivescheme 2>&1; $planName = if($plan -match ":(.+)\((.+)\)"){$Matches[2].Trim()} else {"unknown"}; $isHP = $planName -match "High Performance"
  $_s = if($isHP){'OK'}elseif(!$isHP){'WARN'}else{'FAIL'}
  Add-Row 'Active power plan' $_s ("Plan=$planName")

  # Probe: Processor max state = 100%
  $pmax = powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 2>&1; $maxVal = if($pmax -match "Current AC.*:\s*0x([0-9a-f]+)"){[int]"0x$($Matches[1])"}else{100}
  $_s = if($maxVal -lt 100){'FAIL'}elseif($maxVal -eq 100){'OK'}else{'WARN'}
  Add-Row 'Processor max state = 100%' $_s ("MaxProcessor=$maxVal%25")

  # Probe: Processor min state reasonable
  $pmin = powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 2>&1; $minVal = if($pmin -match "Current AC.*:\s*0x([0-9a-f]+)"){[int]"0x$($Matches[1])"}else{5}
  $_s = if($minVal -le 10){'OK'}elseif($minVal -gt 10){'WARN'}else{'FAIL'}
  Add-Row 'Processor min state reasonable' $_s ("MinProcessor=$minVal%25")

  # Probe: Hard disk timeout (not 0)
  $hd = powercfg /query SCHEME_CURRENT SUB_DISK DISKIDLE 2>&1; $hdVal = if($hd -match "Current AC.*:\s*0x([0-9a-f]+)"){[int]"0x$($Matches[1])"}else{0}
  $_s = if($hdVal -eq 0 -or $hdVal -ge 1200){'OK'}elseif($hdVal -gt 0 -and $hdVal -lt 1200){'WARN'}else{'FAIL'}
  Add-Row 'Hard disk timeout (not 0)' $_s ("DiskTimeout=$hdVal sec")

  # Probe: USB selective suspend disabled
  $usb = powercfg /query SCHEME_CURRENT 2b6965c-629a500f 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 2>&1; $usbVal = if($usb -match "Current AC.*:\s*0x([0-9a-f]+)"){[int]"0x$($Matches[1])"}else{-1}
  $_s = if($usbVal -eq 0){'OK'}elseif($usbVal -ne 0){'WARN'}else{'FAIL'}
  Add-Row 'USB selective suspend disabled' $_s ("USBSuspend=$usbVal")

  # Probe: Sleep/Hibernate disabled for server
  $sleep = powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>&1; $sleepVal = if($sleep -match "Current AC.*:\s*0x([0-9a-f]+)"){[int]"0x$($Matches[1])"}else{0}
  $_s = if($sleepVal -eq 0){'OK'}elseif($sleepVal -gt 0){'WARN'}else{'FAIL'}
  Add-Row 'Sleep/Hibernate disabled for server' $_s ("SleepTimeout=$sleepVal sec")

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

