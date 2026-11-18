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

Write-Output '=== Windows SFC & DISM Health Signal ==='
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
  # Probe: CBS log integrity marker
  $cbs = Get-Content "$env:SystemRoot\Logs\CBS\CBS.log" -Tail 200 -ErrorAction SilentlyContinue; $corruptLines = @($cbs | Where-Object { $_ -match "corrupt|Cannot repair" }).Count
  $_s = if($corruptLines -eq 0){'OK'}elseif($corruptLines -le 3){'WARN'}else{'FAIL'}
  Add-Row 'CBS log integrity marker' $_s ("CorruptSignals=$corruptLines")

  # Probe: SFC last run result in CBS log
  $sfcResult = @($cbs | Where-Object { $_ -match "Verify complete|no integrity violations|could not perform" }) | Select-Object -Last 1; $sfcOk = $sfcResult -match "no integrity violations|Verify complete"
  $_s = if($sfcOk){'OK'}elseif(!$sfcOk){'WARN'}else{'FAIL'}
  Add-Row 'SFC last run result in CBS log' $_s ("SFC=$(if($sfcResult){$sfcResult.Trim().Substring(0,[math]::Min(60,$sfcResult.Trim().Length))}else{'no recent scan'})")

  # Probe: Component store health (WinSxS)
  $winsxs = Get-ChildItem "$env:SystemRoot\WinSxS" -Directory -ErrorAction SilentlyContinue | Measure-Object; $sxsCount = $winsxs.Count
  $_s = if($sxsCount -gt 0 -and $sxsCount -lt 30000){'OK'}elseif($sxsCount -ge 30000){'WARN'}else{'FAIL'}
  Add-Row 'Component store health (WinSxS)' $_s ("WinSxSFolders=$sxsCount")

  # Probe: Pending component changes
  $pend = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
  $_s = if(!$pend){'OK'}elseif($pend){'WARN'}else{'FAIL'}
  Add-Row 'Pending component changes' $_s ("RebootPending=$pend")

  # Probe: TrustedInstaller service
  $ti = Get-Service TrustedInstaller -ErrorAction SilentlyContinue
  $_s = if($ti -ne $null){'OK'}elseif($ti -eq $null){'WARN'}else{'FAIL'}
  Add-Row 'TrustedInstaller service' $_s ("Status=$(if($ti){$ti.Status}else{'NotFound'})")

  # Probe: DISM image health (registry hint)
  $health = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing" -Name "RepairNeeded" -ErrorAction SilentlyContinue; $needsRepair = if($health){$health.RepairNeeded}else{0}
  $_s = if($needsRepair -ne 0){'FAIL'}elseif($needsRepair -eq 0){'OK'}else{'WARN'}
  Add-Row 'DISM image health (registry hint)' $_s ("RepairNeeded=$needsRepair")

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

