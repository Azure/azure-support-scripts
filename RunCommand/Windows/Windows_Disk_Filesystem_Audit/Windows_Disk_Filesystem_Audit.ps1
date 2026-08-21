#Requires -Version 5.1
<#
.SYNOPSIS
    Audits disk capacity and filesystem health on a running Azure Windows VM.
.DESCRIPTION
    Checks the most common disk-related issues:
      1. Drive free space — WARN <15%, FAIL <5%
      2. Pagefile configuration and size
      3. Temp drive (D:) presence and free space
      4. Filesystem dirty bit (chkdsk pending)

    Designed for Azure Run Command: no Az module, no internet, PS 5.1 only,
    output fits within the 4 KB portal limit.
.PARAMETER MockConfig
    Path to a JSON file that replaces live system reads for offline testing.
.NOTES
    Author  : CSS Core Compute SPM
    Version : 1.0.0
    Tool ID : RC-005
    Bucket  : Disk / Unexpected-Restarts / Performance
    Repo    : Azure/azure-support-scripts  RunCommand/Windows/Windows_Disk_Filesystem_Audit
#>
[CmdletBinding()]
param(
  [string]$MockConfig,
  [ValidateSet('healthy','degraded','broken')]
  [string]$MockProfile = 'degraded'
)
$ErrorActionPreference = 'Continue'

# ── helpers ───────────────────────────────────────────────────────────────────
function Pad($s, $n) { $s = "$s"; if ($s.Length -ge $n) { $s.Substring(0,$n) } else { $s.PadRight($n) } }
$W = 44
$findings = [System.Collections.Generic.List[psobject]]::new()

function Add-Row($check, $status, $detail = '') {
    $script:findings.Add([PSCustomObject]@{ Check = $check; Status = $status; Detail = $detail })
    Write-Output ('{0} {1}' -f (Pad $check $W), $status)
}

# ── mock vs live ──────────────────────────────────────────────────────────────
$mock = $null
if ($MockConfig -and (Test-Path $MockConfig)) {
    $mock = Get-Content $MockConfig -Raw | ConvertFrom-Json
}

# ── header ────────────────────────────────────────────────────────────────────
Write-Output '=== Windows Disk & Filesystem Audit ==='
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

# -- Drive Free Space ---------------------------------------------------------
Write-Output '-- Drive Free Space --'
if ($mock) {
    $drives = $mock.legacy.drives
} else {
    $drives = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
        ForEach-Object {
            [PSCustomObject]@{
                letter  = $_.DeviceID
                freeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
                totalGB = [math]::Round($_.Size / 1GB, 1)
                pctFree = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
                label   = $_.VolumeName
            }
        }
}

foreach ($drv in $drives) {
    $pct = [double]$drv.pctFree
    $st  = if ($pct -lt 5) { 'FAIL' } elseif ($pct -lt 15) { 'WARN' } else { 'OK' }
    Add-Row "$($drv.letter) Free space ($($drv.freeGB) GB / $($drv.totalGB) GB)" $st ''
}

# -- Pagefile Configuration ---------------------------------------------------
Write-Output '-- Pagefile Configuration --'
if ($mock) {
    $pfAuto  = [bool]$mock.legacy.pagefile.autoManaged
    $pfFiles = $mock.legacy.pagefile.files
} else {
    $cs = Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue
    $pfAuto = [bool]$cs.AutomaticManagedPagefile
    $pfFiles = Get-WmiObject Win32_PageFileSetting -ErrorAction SilentlyContinue |
        ForEach-Object { [PSCustomObject]@{ path = $_.Name; initialMB = $_.InitialSize; maxMB = $_.MaximumSize } }
}

$pfMode = if ($pfAuto) { 'Auto-managed' } else { 'Custom' }
Add-Row "Pagefile mode: $pfMode" 'OK' ''

if ($pfFiles) {
    foreach ($pf in $pfFiles) {
        Add-Row "Pagefile: $($pf.path)" 'OK' ''
    }
} elseif (-not $pfAuto) {
    Add-Row 'Pagefile present' 'WARN' 'No pagefile configured and not auto-managed'
}

# -- Temp Drive (D:) ---------------------------------------------------------
Write-Output '-- Temp Drive (D:) --'
if ($mock) {
    $tempExists = [bool]$mock.legacy.tempDrive.exists
    $tempFreeGB = [double]$mock.legacy.tempDrive.freeGB
    $tempTotalGB = [double]$mock.legacy.tempDrive.totalGB
    $tempPct    = [double]$mock.legacy.tempDrive.pctFree
} else {
    $tempVol = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='D:'" -ErrorAction SilentlyContinue
    $tempExists = ($null -ne $tempVol)
    if ($tempExists) {
        $tempFreeGB  = [math]::Round($tempVol.FreeSpace / 1GB, 1)
        $tempTotalGB = [math]::Round($tempVol.Size / 1GB, 1)
        $tempPct = if ($tempVol.Size -gt 0) { [math]::Round(($tempVol.FreeSpace / $tempVol.Size) * 100, 1) } else { 0 }
    }
}

if (-not $tempExists) {
    Add-Row 'Temp drive D: present' 'WARN' 'No temp drive — VM size may not include local disk'
} else {
    $tSt = if ($tempPct -lt 5) { 'FAIL' } elseif ($tempPct -lt 15) { 'WARN' } else { 'OK' }
    Add-Row "D: Free space ($tempFreeGB GB / $tempTotalGB GB)" $tSt ''
}

# -- Filesystem Dirty Bit -----------------------------------------------------
Write-Output '-- Filesystem Dirty Bit --'
if ($mock) {
    $dirtyDrives = $mock.legacy.dirtyDrives
} else {
    $dirtyDrives = @()
    $allVolumes  = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    foreach ($vol in $allVolumes) {
        $fsutil = & fsutil dirty query "$($vol.DeviceID)" 2>$null
        if ($fsutil -match 'is Dirty') { $dirtyDrives += $vol.DeviceID }
    }
}

if (@($dirtyDrives).Count -eq 0) {
    Add-Row 'No volumes flagged dirty' 'OK' ''
} else {
    foreach ($d in $dirtyDrives) {
        Add-Row "Volume $d dirty bit set" 'WARN' 'chkdsk scheduled on next reboot'
    }
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
