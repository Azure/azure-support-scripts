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

Write-Output '=== Windows Task Scheduler Health ==='
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
  # Probe: Task Scheduler service
  $ts = Get-Service Schedule -ErrorAction SilentlyContinue
  $_s = if(!$ts -or $ts.Status -ne "Running"){'FAIL'}elseif($ts -and $ts.Status -eq "Running"){'OK'}else{'WARN'}
  Add-Row 'Task Scheduler service' $_s ("Status=$(if($ts){$ts.Status}else{'NotFound'})")

  # Probe: Failed scheduled tasks
  $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne "Disabled" }; $failTasks = @($tasks | Where-Object { (Get-ScheduledTaskInfo $_.TaskName -ErrorAction SilentlyContinue).LastTaskResult -ne 0 -and (Get-ScheduledTaskInfo $_.TaskName -ErrorAction SilentlyContinue).LastTaskResult -ne 267009 } | Select-Object -First 10).Count
  $_s = if($failTasks -eq 0){'OK'}elseif($failTasks -le 5){'WARN'}else{'FAIL'}
  Add-Row 'Failed scheduled tasks' $_s ("FailedTasks=$failTasks")

  # Probe: Task Scheduler event errors (7d)
  $tsEvt = Get-WinEvent -FilterHashtable @{LogName="Microsoft-Windows-TaskScheduler/Operational";Level=2;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 10 -ErrorAction SilentlyContinue; $tsErr = @($tsEvt).Count
  $_s = if($tsErr -eq 0){'OK'}elseif($tsErr -le 5){'WARN'}else{'FAIL'}
  Add-Row 'Task Scheduler event errors (7d)' $_s ("SchedErrors=$tsErr")

  # Probe: Task registration count
  $regTasks = @($tasks).Count
  $_s = if($regTasks -lt 300){'OK'}elseif($regTasks -ge 300){'WARN'}else{'FAIL'}
  Add-Row 'Task registration count' $_s ("ActiveTasks=$regTasks")

  # Probe: Task queue latency (any running)
  $running = @($tasks | Where-Object State -eq "Running").Count
  $_s = if($running -lt 10){'OK'}elseif($running -ge 10){'WARN'}else{'FAIL'}
  Add-Row 'Task queue latency (any running)' $_s ("RunningNow=$running")

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

