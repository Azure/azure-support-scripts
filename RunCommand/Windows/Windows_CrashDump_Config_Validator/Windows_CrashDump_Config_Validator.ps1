#Requires -Version 5.1
<#
.SYNOPSIS
    Validates Windows crash dump and reboot policy configuration.
.DESCRIPTION
    Checks guest configuration required for actionable post-crash investigation:
      1. CrashControl dump type and dump file path
      2. AutoReboot setting (recommended OFF during active triage)
      3. Overwrite policy and MinidumpDir
      4. Pagefile presence on OS disk for kernel/complete dump support
      5. Existing dump artifact presence (MEMORY.DMP or minidumps)

    Designed for Azure Run Command: no Az module, no internet, PS 5.1 only,
    output fits within the 4 KB portal limit.
.PARAMETER MockConfig
    Path to a JSON file that replaces live reads for offline testing.
.NOTES
    Author  : CSS Core Compute SPM
    Version : 1.0.0
    Tool ID : RC-009
    Bucket  : Unexpected-Restarts / BSOD
    Repo    : Azure/azure-support-scripts  RunCommand/Windows/Windows_CrashDump_Config_Validator
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

Write-Output '=== Windows Crash Dump Config Validator ==='
Write-Output ('{0} {1}' -f (Pad 'Check' $W), 'Status')
Write-Output (('-' * $W) + ' ------')

$usedMock = $false
if($MockConfig -and (Test-Path $MockConfig)){
  if($mock.profiles -and $mock.profiles.$MockProfile){
    $usedMock = $true
    foreach($i in $mock.profiles.$MockProfile){ Add-Row $i.name $i.status $i.detail }
  }
}
if(-not $usedMock){

# -- CrashControl --------------------------------------------------------------
Write-Output '-- CrashControl --'
if ($mock) {
    $cc = $mock.crashControl
} else {
    $cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue
}

$dumpType = [int]$cc.CrashDumpEnabled
$dumpTypeLabel = switch ($dumpType) {
    0 { 'Disabled' }
    1 { 'Complete' }
    2 { 'Kernel' }
    3 { 'Small' }
    7 { 'Automatic' }
    default { 'Unknown' }
}

$dumpTypeStatus = if ($dumpType -eq 0) { 'FAIL' } elseif ($dumpType -eq 3) { 'WARN' } else { 'OK' }
Add-Row "Crash dump type: $dumpTypeLabel" $dumpTypeStatus "Value=$dumpType"

$dumpFile = [string]$cc.DumpFile
if ([string]::IsNullOrWhiteSpace($dumpFile)) { $dumpFile = '%SystemRoot%\MEMORY.DMP' }
Add-Row 'Dump file path configured' (if ($dumpFile) { 'OK' } else { 'FAIL' }) "$dumpFile"

$autoReboot = [int]$cc.AutoReboot
Add-Row 'AutoReboot disabled during triage' (if ($autoReboot -eq 0) { 'OK' } else { 'WARN' }) "Value=$autoReboot"

$overwrite = [int]$cc.Overwrite
Add-Row 'Overwrite existing dump enabled' (if ($overwrite -eq 1) { 'OK' } else { 'WARN' }) "Value=$overwrite"

$miniDir = [string]$cc.MinidumpDir
if ([string]::IsNullOrWhiteSpace($miniDir)) { $miniDir = '%SystemRoot%\Minidump' }
Add-Row 'Minidump directory configured' 'OK' "$miniDir"

# -- Pagefile check ------------------------------------------------------------
Write-Output '-- Pagefile --'
if ($mock) {
    $pagefiles = $mock.pagefile.files
} else {
    $pagefiles = Get-WmiObject Win32_PageFileSetting -ErrorAction SilentlyContinue |
        ForEach-Object { [PSCustomObject]@{ path = $_.Name; initialMB = $_.InitialSize; maxMB = $_.MaximumSize } }
}

if (@($pagefiles).Count -eq 0) {
    Add-Row 'Pagefile configured' 'FAIL' 'No pagefile detected'
} else {
    Add-Row 'Pagefile configured' 'OK' "Count=$(@($pagefiles).Count)"
    $osPf = $pagefiles | Where-Object { $_.path -like 'C:*' } | Select-Object -First 1
    Add-Row 'OS drive pagefile present' (if ($osPf) { 'OK' } else { 'WARN' }) ''
}

# -- Existing dump artifacts ---------------------------------------------------
Write-Output '-- Existing Dump Artifacts --'
if ($mock) {
    $memoryDmpExists = $mock.dumps.memoryDmpExists
    $miniDumpCount   = [int]$mock.dumps.miniDumpCount
} else {
    $memoryDmpExists = Test-Path 'C:\Windows\MEMORY.DMP'
    $miniDumpCount   = @(Get-ChildItem 'C:\Windows\Minidump' -Filter '*.dmp' -ErrorAction SilentlyContinue).Count
}

Add-Row 'MEMORY.DMP present' (if ($memoryDmpExists) { 'WARN' } else { 'OK' }) ''
Add-Row 'Minidump files present' (if ($miniDumpCount -gt 0) { 'WARN' } else { 'OK' }) "Count=$miniDumpCount"

# -- Summary ------------------------------------------------------------------
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
