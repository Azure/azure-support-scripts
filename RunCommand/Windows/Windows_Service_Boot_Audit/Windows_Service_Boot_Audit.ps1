#Requires -Version 5.1
<#
.SYNOPSIS
    Audits critical service start types and boot configuration.
.DESCRIPTION
    Checks guest configuration critical for VM boot and service health:
      1. Critical Services — 10 key services: start type not Disabled, required Running
      2. SafeBoot — VM is NOT running in safeboot mode
      3. BCDEdit — no non-standard recovery sequence active
      4. EventLog — System and Application channels accessible

    Designed for Azure Run Command: no Az module, no internet, PS 5.1 only.
.PARAMETER MockConfig
    Path to a JSON file that replaces live reads for offline testing.
.NOTES
    Author  : CSS Core Compute SPM
    Version : 1.0.0
    Tool ID : RC-002
    Bucket  : VM-Responding / OS-Service-Failures / Unexpected-Restarts
    Repo    : Azure/azure-support-scripts  RunCommand/Windows/Windows_Service_Boot_Audit
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

Write-Output '=== Windows Service & Boot Audit ==='
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

# ── Critical Services ─────────────────────────────────────────────────────────
Write-Output '-- Critical Services (Start Type + Running) --'

$svcMap = [ordered]@{
    RpcSs              = 'RPC (RpcSs)'
    EventLog           = 'Windows Event Log'
    TermService        = 'Remote Desktop Service'
    Dnscache           = 'DNS Client (Dnscache)'
    LanmanWorkstation  = 'Workstation'
    Netlogon           = 'Netlogon'
    DHCP               = 'DHCP Client'
    BFE                = 'Base Filtering Engine (BFE)'
    CryptSvc           = 'Cryptographic Services'
    wuauserv           = 'Windows Update (wuauserv)'
}

foreach ($key in $svcMap.Keys) {
    if ($mock) {
        $startType = [int]$mock.legacy.services.$key.startType
        $running   = $mock.legacy.services.$key.running -eq $true
    } else {
        $svc = Get-Service -Name $key -ErrorAction SilentlyContinue
        if ($svc) {
            $running   = $svc.Status -eq 'Running'
            $regPath   = "HKLM:\SYSTEM\CurrentControlSet\Services\$key"
            $startType = [int](Get-ItemProperty $regPath -Name 'Start' -ErrorAction SilentlyContinue).Start
        } else {
            $running   = $false
            $startType = -1
        }
    }

    $stLabel = switch ($startType) { 0 { 'Boot' } 1 { 'System' } 2 { 'Auto' } 3 { 'Manual' } 4 { 'Disabled' } default { 'Unknown' } }

    if ($startType -eq 4) {
        Add-Row $svcMap[$key] 'FAIL' "Disabled"
    } elseif (-not $running -and $startType -le 2) {
        Add-Row $svcMap[$key] 'FAIL' "Not running (Start=$stLabel)"
    } elseif (-not $running) {
        Add-Row $svcMap[$key] 'WARN' "Not running (Start=$stLabel)"
    } else {
        Add-Row $svcMap[$key] 'OK' $stLabel
    }
}

# ── Boot Configuration ────────────────────────────────────────────────────────
Write-Output '-- Boot Configuration --'

if ($mock) {
    $safeBootActive = $mock.legacy.boot.safeBootActive -eq $true
    $safeBootType   = [int]$mock.legacy.boot.safeBootType
    $recoveryMode   = $mock.legacy.boot.recoveryMode -eq $true
} else {
    $sbKey = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Option' -Name 'OptionValue' -ErrorAction SilentlyContinue
    $safeBootActive = $null -ne $sbKey
    $safeBootType   = if ($sbKey) { [int]$sbKey.OptionValue } else { 0 }

    $bcdOut = bcdedit /enum '{current}' 2>$null | Out-String
    $recoveryMode = $bcdOut -match 'recoveryenabled\s+Yes'
}

$sbLabel = switch ($safeBootType) { 0 { 'Normal' } 1 { 'Minimal' } 2 { 'Network' } 3 { 'DsRepair' } default { 'Unknown' } }
Add-Row 'SafeBoot NOT active (normal boot)' (if (-not $safeBootActive) { 'OK' } else { 'FAIL' }) (if ($safeBootActive) { "Type=$sbLabel" } else { '' })
Add-Row 'Boot recovery sequence (recoveryenabled)' (if (-not $recoveryMode) { 'OK' } else { 'WARN' }) ''

# ── EventLog Health ───────────────────────────────────────────────────────────
Write-Output '-- EventLog Health --'

if ($mock) {
    $sysOk = $mock.legacy.eventlog.systemOk -eq $true
    $appOk = $mock.legacy.eventlog.applicationOk -eq $true
} else {
    $sysOk = $false; $appOk = $false
    try { $null = Get-WinEvent -LogName System -MaxEvents 1 -ErrorAction Stop; $sysOk = $true } catch {}
    try { $null = Get-WinEvent -LogName Application -MaxEvents 1 -ErrorAction Stop; $appOk = $true } catch {}
}

Add-Row 'System event log accessible' (if ($sysOk) { 'OK' } else { 'FAIL' }) ''
Add-Row 'Application event log accessible' (if ($appOk) { 'OK' } else { 'FAIL' }) ''

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
