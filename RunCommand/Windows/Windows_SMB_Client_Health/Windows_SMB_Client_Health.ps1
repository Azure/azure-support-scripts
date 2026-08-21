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

Write-Output '=== Windows SMB Client Health ==='
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
  # Probe: LanmanWorkstation service
  $lw = Get-Service LanmanWorkstation -ErrorAction SilentlyContinue
  $_s = if(!$lw -or $lw.Status -ne "Running"){'FAIL'}elseif($lw -and $lw.Status -eq "Running"){'OK'}else{'WARN'}
  Add-Row 'LanmanWorkstation service' $_s ("Status=$(if($lw){$lw.Status}else{'NotFound'})")

  # Probe: SMB signing required (client)
  $sign = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "RequireSecuritySignature" -ErrorAction SilentlyContinue; $signVal = if($sign){$sign.RequireSecuritySignature}else{0}
  $_s = if($signVal -eq 1){'OK'}elseif($signVal -ne 1){'WARN'}else{'FAIL'}
  Add-Row 'SMB signing required (client)' $_s ("SigningRequired=$signVal")

  # Probe: SMBv1 protocol disabled
  $v1 = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "DependOnService" -ErrorAction SilentlyContinue; $v1On = if($v1){ $v1.DependOnService -contains "MRxSmb10" }else{$false}; $v1Drv = Get-Service mrxsmb10 -ErrorAction SilentlyContinue; $v1Active = $v1Drv -and $v1Drv.Status -eq "Running"
  $_s = if($v1Active){'FAIL'}elseif(!$v1Active){'OK'}else{'WARN'}
  Add-Row 'SMBv1 protocol disabled' $_s ("SMBv1Active=$v1Active")

  # Probe: SMB connections active
  $smbConn = Get-SmbConnection -ErrorAction SilentlyContinue; $smbCount = @($smbConn).Count
  $_s = if($true){'OK'}elseif($false){'WARN'}else{'FAIL'}
  Add-Row 'SMB connections active' $_s ("ActiveConns=$smbCount (informational)")

  # Probe: Multichannel enabled
  $mc = Get-SmbClientConfiguration -ErrorAction SilentlyContinue | Select-Object -ExpandProperty EnableMultiChannel -ErrorAction SilentlyContinue
  $_s = if($mc -eq $true){'OK'}elseif($mc -ne $true){'WARN'}else{'FAIL'}
  Add-Row 'Multichannel enabled' $_s ("Multichannel=$mc")

  # Probe: File sharing firewall rules
  $smFw = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue | Where-Object Enabled -eq True; $smFwCount = @($smFw).Count
  $_s = if($smFwCount -gt 0){'OK'}elseif($smFwCount -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'File sharing firewall rules' $_s ("FWRulesEnabled=$smFwCount")

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

