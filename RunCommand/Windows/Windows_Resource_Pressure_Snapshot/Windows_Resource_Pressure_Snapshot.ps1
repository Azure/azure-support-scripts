#Requires -Version 5.1
<#
.SYNOPSIS
    Point-in-time resource utilization snapshot for Azure Windows VM performance.
.DESCRIPTION
    Captures current load across CPU, memory, and disk I/O:
      1. CPU — overall utilization (2-sample avg) + top 5 processes
      2. Memory — physical used %, commit charge %, top 5 by Working Set
      3. Disk I/O — current queue length per physical disk

    Thresholds: CPU WARN >= 75 FAIL >= 90, Mem WARN >= 85 FAIL >= 95,
    CommitPct same, DiskQ WARN >= 2 FAIL >= 4.

    Designed for Azure Run Command: no Az module, no internet, PS 5.1 only.
.PARAMETER MockConfig
    Path to a JSON file that replaces live reads for offline testing.
.NOTES
    Author  : CSS Core Compute SPM
    Version : 1.0.0
    Tool ID : RC-006
    Bucket  : Performance / High-CPU / Memory-Pressure
    Repo    : Azure/azure-support-scripts  RunCommand/Windows/Windows_Resource_Pressure_Snapshot
#>
[CmdletBinding()]
param(
  [string]$MockConfig,
  [ValidateSet('healthy','degraded','broken')]
  [string]$MockProfile = 'degraded'
)
$ErrorActionPreference = 'Continue'

function Pad($s, $n) { $s = "$s"; if ($s.Length -ge $n) { $s.Substring(0,$n) } else { $s.PadRight($n) } }
$W = 44
$findings = [System.Collections.Generic.List[psobject]]::new()

function Add-Row($check, $status, $detail = '') {
    $script:findings.Add([PSCustomObject]@{ Check = $check; Status = $status; Detail = $detail })
    Write-Output ('{0} {1}' -f (Pad $check $W), $status)
}

$mock = $null
if ($MockConfig -and (Test-Path $MockConfig)) {
    $mock = Get-Content $MockConfig -Raw | ConvertFrom-Json
}

Write-Output '=== Windows Resource Pressure Snapshot ==='
Write-Output ('{0} {1}' -f (Pad 'Check' $W), 'Status')
Write-Output (('-' * $W) + ' ------')

$usedMock = $false
if ($MockConfig -and (Test-Path $MockConfig)) {
    if ($mock.profiles -and $mock.profiles.$MockProfile) {
        $usedMock = $true
        foreach ($i in $mock.profiles.$MockProfile) { Add-Row $i.name $i.status $i.detail }
    }
}
if (-not $usedMock) {

# ── CPU ───────────────────────────────────────────────────────────────────────
Write-Output '-- CPU --'

if ($mock) {
    $cpuPct  = [double]$mock.legacy.cpu.totalPct
    $topCpu  = @($mock.legacy.cpu.topProcs)
} else {
    $s1 = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    Start-Sleep -Seconds 1
    $s2 = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $cpuPct = [math]::Round(($s1 + $s2) / 2, 1)
    $topCpu = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 |
        ForEach-Object { [PSCustomObject]@{ name = $_.ProcessName; pid = $_.Id; cpuSec = [math]::Round($_.CPU, 1) } }
}

$cpuStatus = if ($cpuPct -ge 90) { 'FAIL' } elseif ($cpuPct -ge 75) { 'WARN' } else { 'OK' }
Add-Row 'Overall CPU utilization' $cpuStatus "$cpuPct%"

if (@($topCpu).Count -gt 0) {
    Write-Output '  Top CPU processes:'
    foreach ($p in $topCpu) {
        Write-Output ("    {0,-32} PID={1,-8} CPUsec={2}" -f $p.name, $p.pid, $p.cpuSec)
    }
}

# ── Memory ────────────────────────────────────────────────────────────────────
Write-Output '-- Memory --'

if ($mock) {
    $totalGB   = [double]$mock.legacy.memory.totalGB
    $freeGB    = [double]$mock.legacy.memory.freeGB
    $memPct    = [double]$mock.legacy.memory.usedPct
    $commitPct = [double]$mock.legacy.memory.commitPct
    $topMem    = @($mock.legacy.memory.topProcs)
} else {
    $os = Get-WmiObject Win32_OperatingSystem
    $totalGB   = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGB    = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $memPct    = [math]::Round(100 - ($freeGB / $totalGB * 100), 1)

    $commitTotal = [math]::Round($os.SizeStoredInPagingFiles / 1MB, 1)
    $commitFree  = [math]::Round($os.FreeSpaceInPagingFiles / 1MB, 1)
    if ($commitTotal -gt 0) {
        $commitPct = [math]::Round(100 - ($commitFree / $commitTotal * 100), 1)
    } else {
        $commitPct = 0
    }

    $topMem = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
        ForEach-Object { [PSCustomObject]@{ name = $_.ProcessName; pid = $_.Id; wsMB = [math]::Round($_.WorkingSet64 / 1MB, 0) } }
}

$memStatus = if ($memPct -ge 95) { 'FAIL' } elseif ($memPct -ge 85) { 'WARN' } else { 'OK' }
Add-Row 'Physical memory used' $memStatus ("{0}% ({1} GB free / {2} GB)" -f $memPct, $freeGB, $totalGB)

$commitStatus = if ($commitPct -ge 95) { 'FAIL' } elseif ($commitPct -ge 85) { 'WARN' } else { 'OK' }
Add-Row 'Commit charge' $commitStatus "$commitPct% of virtual memory committed"

if (@($topMem).Count -gt 0) {
    Write-Output '  Top memory processes (Working Set):'
    foreach ($p in $topMem) {
        Write-Output ("    {0,-32} PID={1,-8} WS={2} MB" -f $p.name, $p.pid, $p.wsMB)
    }
}

# ── Disk I/O Queue ────────────────────────────────────────────────────────────
Write-Output '-- Disk I/O Queue --'

if ($mock) {
    $diskQueues = @($mock.legacy.diskQueues)
} else {
    $diskQueues = Get-WmiObject Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '_Total' } |
        ForEach-Object { [PSCustomObject]@{ disk = $_.Name; queueLen = [int]$_.CurrentDiskQueueLength } }
}

foreach ($dq in $diskQueues) {
    $qLen = [int]$dq.queueLen
    $qStatus = if ($qLen -ge 4) { 'FAIL' } elseif ($qLen -ge 2) { 'WARN' } else { 'OK' }
    Add-Row "Disk queue: $($dq.disk)" $qStatus "Queue=$qLen"
}

}

$fail = @($findings | Where-Object Status -eq 'FAIL').Count
$warn = @($findings | Where-Object Status -eq 'WARN').Count
Write-Output '-- Decision --'
Add-Row 'Likely cause severity' $(if($fail -gt 0){'FAIL'}elseif($warn -gt 0){'WARN'}else{'OK'}) $(if($fail -gt 0){'Hard configuration/service break'}elseif($warn -gt 0){'Configuration drift or transient condition'}else{'No blocking signals'})
Add-Row 'Next action' 'OK' $(if($fail -gt 0){'Follow README interpretation and remediate FAIL rows first'}elseif($warn -gt 0){'Review WARN rows and re-run after targeted fix'}else{'No immediate action'})
Write-Output '-- More Info --'
Add-Row 'Remediation references available' 'OK' 'See paired README Learn References'

$ok = @($findings | Where-Object Status -eq 'OK').Count
Write-Output ''
Write-Output "=== RESULT: $ok OK / $fail FAIL / $warn WARN ==="

$findings
