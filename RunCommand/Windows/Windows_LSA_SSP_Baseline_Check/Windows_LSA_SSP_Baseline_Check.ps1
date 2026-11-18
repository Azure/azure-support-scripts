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

Write-Output '=== Windows LSA SSP Baseline Check ==='
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
  # Probe: LSA RunAsPPL protection
  $ppl = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue; $pplVal = if($ppl){$ppl.RunAsPPL}else{0}
  $_s = if($pplVal -eq 1){'OK'}elseif($pplVal -ne 1){'WARN'}else{'FAIL'}
  Add-Row 'LSA RunAsPPL protection' $_s ("RunAsPPL=$pplVal")

  # Probe: Credential Guard status
  $cg = Get-CimInstance -Namespace root/Microsoft/Windows/DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue; $cgOn = if($cg){ $cg.SecurityServicesRunning -contains 1 }else{ $false }
  $_s = if($cgOn){'OK'}elseif(!$cgOn){'WARN'}else{'FAIL'}
  Add-Row 'Credential Guard status' $_s ("CredGuard=$cgOn")

  # Probe: Security packages registered
  $sp = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "Security Packages" -ErrorAction SilentlyContinue)."Security Packages"; $spCount = @($sp).Count
  $_s = if($spCount -ge 1){'OK'}elseif($spCount -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'Security packages registered' $_s ("Packages=$(@($sp) -join `",`")")

  # Probe: No unauthorized SSPs loaded
  $ssp = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\OSConfig" -Name "Security Packages" -ErrorAction SilentlyContinue)."Security Packages"; $knownSSPs = @("","kerberos","msv1_0","schannel","wdigest","tspkg","pku2u","cloudAP"); $unk = @($ssp | Where-Object { $_ -and $_ -notin $knownSSPs }).Count
  $_s = if($unk -gt 0){'FAIL'}elseif($unk -eq 0){'OK'}else{'WARN'}
  Add-Row 'No unauthorized SSPs loaded' $_s ("UnknownSSPs=$unk")

  # Probe: LSASS audit mode
  $audit = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe" -Name "AuditLevel" -ErrorAction SilentlyContinue; $auditVal = if($audit){$audit.AuditLevel}else{0}
  $_s = if($auditVal -ge 8){'OK'}elseif($auditVal -lt 8){'WARN'}else{'FAIL'}
  Add-Row 'LSASS audit mode' $_s ("AuditLevel=$auditVal")

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

