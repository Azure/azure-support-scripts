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

Write-Output '=== Windows Domain Join Readiness ==='
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
  # Probe: Computer domain membership
  $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue; $isDomain = $cs.PartOfDomain
  $_s = if($isDomain -eq $true){'OK'}elseif($isDomain -ne $true){'WARN'}else{'FAIL'}
  Add-Row 'Computer domain membership' $_s ("Domain=$(if($cs){$cs.Domain}else{'unknown'})")

  # Probe: DNS suffix configured
  $dns = (Get-DnsClientGlobalSetting -ErrorAction SilentlyContinue).SuffixSearchList; $hasSuffix = @($dns).Count -gt 0
  $_s = if($hasSuffix){'OK'}elseif(!$hasSuffix){'WARN'}else{'FAIL'}
  Add-Row 'DNS suffix configured' $_s ("Suffixes=$(@($dns).Count)")

  # Probe: Domain controller reachable
  $dc = nltest /dsgetdc: 2>&1; $dcOk = $LASTEXITCODE -eq 0
  $_s = if($isDomain -eq $true -and !$dcOk){'FAIL'}elseif($dcOk){'OK'}else{'WARN'}
  Add-Row 'Domain controller reachable' $_s ("$(if($dcOk){'DC found'}else{'DC unreachable'})")

  # Probe: Secure channel healthy
  $sc = nltest /sc_verify:$($cs.Domain) 2>&1; $scOk = $LASTEXITCODE -eq 0
  $_s = if($isDomain -eq $true -and !$scOk){'FAIL'}elseif($scOk){'OK'}else{'WARN'}
  Add-Row 'Secure channel healthy' $_s ("$(if($scOk){'Verified'}else{'Broken or N/A'})")

  # Probe: Netlogon service running
  $nl = Get-Service Netlogon -ErrorAction SilentlyContinue
  $_s = if($nl -and $nl.Status -eq "Running"){'OK'}elseif(!$nl -or $nl.Status -ne "Running"){'WARN'}else{'FAIL'}
  Add-Row 'Netlogon service running' $_s ("Status=$(if($nl){$nl.Status}else{'NotFound'})")

  # Probe: Computer account password age
  $pwdAge = try { ((Get-Date) - (Get-ADComputer $env:COMPUTERNAME -Properties PasswordLastSet -ErrorAction SilentlyContinue).PasswordLastSet).Days } catch { -1 }
  $_s = if($pwdAge -ge 0 -and $pwdAge -le 30){'OK'}elseif($pwdAge -gt 30){'WARN'}else{'FAIL'}
  Add-Row 'Computer account password age' $_s ("PwdAgeDays=$pwdAge")

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

