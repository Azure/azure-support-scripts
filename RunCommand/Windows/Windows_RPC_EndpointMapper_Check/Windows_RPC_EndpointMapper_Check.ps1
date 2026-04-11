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

Write-Output '=== Windows RPC Endpoint Mapper Check ==='
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
  # Probe: RPC Endpoint Mapper service
  $rpc = Get-Service RpcSs -ErrorAction SilentlyContinue
  $_s = if(!$rpc -or $rpc.Status -ne "Running"){'FAIL'}elseif($rpc -and $rpc.Status -eq "Running"){'OK'}else{'WARN'}
  Add-Row 'RPC Endpoint Mapper service' $_s ("Status=$(if($rpc){$rpc.Status}else{'NotFound'})")

  # Probe: DCOM Launch service
  $dcom = Get-Service DcomLaunch -ErrorAction SilentlyContinue
  $_s = if(!$dcom -or $dcom.Status -ne "Running"){'FAIL'}elseif($dcom -and $dcom.Status -eq "Running"){'OK'}else{'WARN'}
  Add-Row 'DCOM Launch service' $_s ("Status=$(if($dcom){$dcom.Status}else{'NotFound'})")

  # Probe: RPC port range (135 listening)
  $p135 = Get-NetTCPConnection -LocalPort 135 -State Listen -ErrorAction SilentlyContinue; $p135Ok = @($p135).Count -gt 0
  $_s = if(!$p135Ok){'FAIL'}elseif($p135Ok){'OK'}else{'WARN'}
  Add-Row 'RPC port range (135 listening)' $_s ("Port135=$p135Ok")

  # Probe: RPC dynamic port range
  $rpcRange = netsh int ipv4 show dynamicport tcp 2>&1; $rpcPorts = if($rpcRange -match "Number of Ports.*:\s*(\d+)"){[int]$Matches[1]}else{0}
  $_s = if($rpcPorts -ge 16384){'OK'}elseif($rpcPorts -lt 16384){'WARN'}else{'FAIL'}
  Add-Row 'RPC dynamic port range' $_s ("DynPorts=$rpcPorts")

  # Probe: RPC errors in System log (7d)
  $rpcErr = Get-WinEvent -FilterHashtable @{LogName="System";Id=1753,1722;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 10 -ErrorAction SilentlyContinue; $rpcErrCount = @($rpcErr).Count
  $_s = if($rpcErrCount -eq 0){'OK'}elseif($rpcErrCount -le 3){'WARN'}else{'FAIL'}
  Add-Row 'RPC errors in System log (7d)' $_s ("RPCErrors=$rpcErrCount")

  # Probe: WMI repository healthy
  $wmi = winmgmt /verifyrepository 2>&1; $wmiOk = $wmi -match "consistent"
  $_s = if($wmiOk){'OK'}elseif(!$wmiOk){'WARN'}else{'FAIL'}
  Add-Row 'WMI repository healthy' $_s ("WMI=$wmi")

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

