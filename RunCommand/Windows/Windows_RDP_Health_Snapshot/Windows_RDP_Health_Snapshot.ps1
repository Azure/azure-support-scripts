#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnoses RDP connectivity blockers on a running Azure Windows VM.
.DESCRIPTION
    Checks the five most common in-guest causes of RDP failure:
      1. Critical service state (TermService, Netlogon, Dnscache, etc.)
      2. fDenyTSConnections registry flag
      3. NLA / SecurityLayer setting
      4. Windows Firewall inbound rule for port 3389
      5. RDP listener state (current active connections / listen port)

    Designed for Azure Run Command: no Az module, no internet access,
    PowerShell 5.1 only, output fits within the 4 KB portal limit.
.PARAMETER MockConfig
    Path to a JSON file that replaces live system reads for offline testing.
.NOTES
    Author  : CSS Core Compute SPM
    Version : 1.0.0
    Tool ID : RC-001
    Bucket  : VM-Responding / Cant-RDP-SSH
    Repo    : Azure/azure-support-scripts  RunCommand/Windows/Windows_RDP_Health_Snapshot
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
Write-Output '=== Windows RDP Health Snapshot ==='
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

# -- Services -----------------------------------------------------------------
Write-Output '-- Services --'
$svcNames = @('TermService','Netlogon','Dnscache','LanmanWorkstation','LSM','BFE')
$svcLabels = @{
    TermService='Remote Desktop Service (TermService)'; Netlogon='Netlogon';
    Dnscache='DNS Client (Dnscache)'; LanmanWorkstation='Workstation (LanmanWorkstation)';
    LSM='Local Session Manager (LSM)'; BFE='Base Filtering Engine (BFE/Firewall)'
}
foreach ($sn in $svcNames) {
    if ($mock) {
        $st = $mock.legacy.services.$sn
    } else {
        $svc = Get-Service $sn -ErrorAction SilentlyContinue
        $st = if ($svc) { $svc.Status.ToString() } else { 'NotFound' }
    }
    $status = if ($st -eq 'Running') { 'OK' } else { 'FAIL' }
    Add-Row $svcLabels[$sn] $status $st
}

# -- Registry -----------------------------------------------------------------
Write-Output '-- Registry --'
if ($mock) {
    $fDeny = [int]$mock.legacy.registry.fDenyTSConnections
    $secLayer = [int]$mock.legacy.registry.SecurityLayer
} else {
    $fDeny = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
    $secLayer = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name SecurityLayer -ErrorAction SilentlyContinue).SecurityLayer
}
Add-Row ('fDenyTSConnections = {0} ({1})' -f $fDeny, (if ($fDeny -eq 0) { 'RDP allowed' } else { 'RDP BLOCKED' })) (if ($fDeny -eq 0) { 'OK' } else { 'FAIL' }) ''
$nlaLabel = switch ($secLayer) { 0 { 'RDP' } 1 { 'Negotiate' } 2 { 'NLA/SSL' } default { 'Unknown' } }
Add-Row "NLA SecurityLayer: $nlaLabel" 'OK' ''

# -- Windows Firewall ---------------------------------------------------------
Write-Output '-- Windows Firewall --'
if ($mock) {
    $rdpRule = [bool]$mock.legacy.firewall.rdpRuleEnabled
    $bfeRun  = [bool]$mock.legacy.firewall.bfeRunning
} else {
    $rdpRule = $false
    try {
        $rules = Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue |
                 Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' }
        $rdpRule = (@($rules).Count -gt 0)
    } catch { }
    $bfeSvc = Get-Service BFE -ErrorAction SilentlyContinue
    $bfeRun = ($bfeSvc -and $bfeSvc.Status -eq 'Running')
}
Add-Row 'RDP inbound rule enabled (port 3389)' (if ($rdpRule) { 'OK' } else { 'FAIL' }) ''
Add-Row 'BFE running (firewall enforcement)' (if ($bfeRun) { 'OK' } else { 'FAIL' }) ''

# -- RDP Listener -------------------------------------------------------------
Write-Output '-- RDP Listener --'
if ($mock) {
    $listening = [bool]$mock.legacy.listener.port3389Listening
} else {
    $listening = $false
    $tcp = netstat -an 2>$null | Select-String ':3389\s+.*LISTENING'
    if ($tcp) { $listening = $true }
}
Add-Row 'Port 3389 in LISTENING state' (if ($listening) { 'OK' } else { 'FAIL' }) ''

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
