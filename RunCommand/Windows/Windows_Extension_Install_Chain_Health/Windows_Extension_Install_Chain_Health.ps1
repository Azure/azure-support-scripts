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

Write-Output '=== Windows Extension Install Chain Health ==='
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
  # Probe: VM Agent service running
  $ga = Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue
  $_s = if(!$ga -or $ga.Status -ne "Running"){'FAIL'}elseif($ga -and $ga.Status -eq "Running"){'OK'}else{'WARN'}
  Add-Row 'VM Agent service running' $_s ("Status=$(if($ga){$ga.Status}else{'NotFound'})")

  # Probe: RdAgent service running
  $rd = Get-Service RdAgent -ErrorAction SilentlyContinue
  $_s = if(!$rd -or $rd.Status -ne "Running"){'FAIL'}elseif($rd -and $rd.Status -eq "Running"){'OK'}else{'WARN'}
  Add-Row 'RdAgent service running' $_s ("Status=$(if($rd){$rd.Status}else{'NotFound'})")

  # Probe: Extension handler registry entries
  $hRoot = "HKLM:\SOFTWARE\Microsoft\Windows Azure\HandlerState"; $handlers = if(Test-Path $hRoot){ @(Get-ChildItem $hRoot -ErrorAction SilentlyContinue).Count } else { 0 }
  $_s = if($handlers -gt 0){'OK'}elseif($handlers -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'Extension handler registry entries' $_s ("Handlers=$handlers")

  # Probe: Extension config folder accessible
  $extCfg = Test-Path "C:\Packages\Plugins"
  $_s = if($extCfg){'OK'}elseif(!$extCfg){'WARN'}else{'FAIL'}
  Add-Row 'Extension config folder accessible' $_s ("C:\Packages\Plugins exists=$extCfg")

  # Probe: WireServer connectivity (168.63.129.16)
  $ws = Test-NetConnection -ComputerName 168.63.129.16 -Port 80 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue; $wsOk = $ws.TcpTestSucceeded
  $_s = if(!$wsOk){'FAIL'}elseif($wsOk){'OK'}else{'WARN'}
  Add-Row 'WireServer connectivity (168.63.129.16)' $_s ("WireServer=$wsOk")

  # Probe: Agent log recent errors
  $agLog = "C:\WindowsAzure\Logs\WaAppAgent.log"; $errs = if(Test-Path $agLog){ @(Get-Content $agLog -Tail 50 -ErrorAction SilentlyContinue | Where-Object { $_ -match "ERROR" }).Count } else { -1 }
  $_s = if($errs -eq 0){'OK'}elseif($errs -le 5){'WARN'}else{'FAIL'}
  Add-Row 'Agent log recent errors' $_s ("RecentErrors=$errs")

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

