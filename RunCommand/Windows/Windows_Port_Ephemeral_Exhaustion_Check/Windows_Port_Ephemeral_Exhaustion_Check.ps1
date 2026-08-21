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

Write-Output '=== Windows Port Ephemeral Exhaustion Check ==='
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
  # Probe: Dynamic port range size
  $range = netsh int ipv4 show dynamicport tcp 2>&1; $startPort = [int]($range | Select-String "Start Port" | ForEach-Object { ($_ -split ":")[1].Trim() }); $numPorts = [int]($range | Select-String "Number of Ports" | ForEach-Object { ($_ -split ":")[1].Trim() })
  $_s = if($numPorts -ge 16384){'OK'}elseif($numPorts -lt 16384){'WARN'}else{'FAIL'}
  Add-Row 'Dynamic port range size' $_s ("Start=$startPort Count=$numPorts")

  # Probe: Current TCP connections count
  $conns = (Get-NetTCPConnection -ErrorAction SilentlyContinue | Measure-Object).Count
  $_s = if($conns -lt 10000){'OK'}elseif($conns -lt 30000){'WARN'}else{'FAIL'}
  Add-Row 'Current TCP connections count' $_s ("TCPConns=$conns")

  # Probe: TIME_WAIT connection count
  $tw = @(Get-NetTCPConnection -State TimeWait -ErrorAction SilentlyContinue).Count
  $_s = if($tw -lt 5000){'OK'}elseif($tw -lt 15000){'WARN'}else{'FAIL'}
  Add-Row 'TIME_WAIT connection count' $_s ("TimeWait=$tw")

  # Probe: Ephemeral port usage ratio
  $eph = @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -ge $startPort }).Count; $ratio = if($numPorts -gt 0){[math]::Round(($eph/$numPorts)*100,1)}else{0}
  $_s = if($ratio -lt 60){'OK'}elseif($ratio -lt 85){'WARN'}else{'FAIL'}
  Add-Row 'Ephemeral port usage ratio' $_s ("EphUsed=$eph Ratio=$ratio%25")

  # Probe: MaxUserPort registry override
  $mup = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "MaxUserPort" -ErrorAction SilentlyContinue; $mupVal = if($mup){$mup.MaxUserPort}else{0}
  $_s = if($mupVal -eq 0 -or $mupVal -ge 32768){'OK'}elseif($mupVal -gt 0 -and $mupVal -lt 32768){'WARN'}else{'FAIL'}
  Add-Row 'MaxUserPort registry override' $_s ("MaxUserPort=$(if($mupVal){$mupVal}else{'default'})")

  # Probe: TcpTimedWaitDelay tuned
  $twd = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "TcpTimedWaitDelay" -ErrorAction SilentlyContinue; $twdVal = if($twd){$twd.TcpTimedWaitDelay}else{240}
  $_s = if($twdVal -le 60){'OK'}elseif($twdVal -gt 60){'WARN'}else{'FAIL'}
  Add-Row 'TcpTimedWaitDelay tuned' $_s ("TWDelay=$twdVal sec")

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

