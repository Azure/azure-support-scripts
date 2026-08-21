#Requires -Version 5.1
<#
.SYNOPSIS
    Full health snapshot of the Azure Guest Agent and installed extension handlers.
.DESCRIPTION
    Checks guest configuration critical for Azure platform communication:
      1. Guest Agent Services — WindowsAzureGuestAgent and RdAgent status + version
      2. Agent Heartbeat — log file freshness (< 5 min threshold)
      3. Extension Handlers — all registered handlers: status and sequence number
      4. Agent Log — last 80 lines of WaAppAgent.log filtered for ERR/WARN

    Designed for Azure Run Command: no Az module, no internet, PS 5.1 only,
    output fits within the 4 KB portal limit.
.PARAMETER MockConfig
    Path to a JSON file that replaces live reads for offline testing.
.NOTES
    Author  : CSS Core Compute SPM
    Version : 1.0.0
    Tool ID : RC-004
    Bucket  : VM-Responding / AGEX / Extension-Failures
    Repo    : Azure/azure-support-scripts  RunCommand/Windows/Windows_VM_Agent_Health_Dump
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

Write-Output '=== Windows VM Agent & Extension Health Dump ==='
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

# ── Section: Guest Agent Services ─────────────────────────────────────────────
Write-Output '-- Guest Agent Services --'

$agentSvcs = @('WindowsAzureGuestAgent', 'RdAgent')
foreach ($svcName in $agentSvcs) {
    if ($mock) {
        $state   = $mock.legacy.agentServices.($svcName).status
        $version = $mock.legacy.agentServices.($svcName).version
    } else {
        $svc   = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        $state = if ($svc) { $svc.Status.ToString() } else { 'NotFound' }

        # Version from file
        $agentExe = @(
            "C:\WindowsAzure\Packages\WaAppAgent.exe",
            "C:\WindowsAzure\GuestAgent_*\WaAppAgent.exe"
        )
        $found = $agentExe | ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
        $version = if ($found) { $found.VersionInfo.FileVersion } else { 'Unknown' }
    }

    $svcStatus = if ($state -eq 'Running') { 'OK' } else { 'FAIL' }
    Add-Row $svcName $svcStatus "v$version $state"
}

# ── Section: Agent Heartbeat ──────────────────────────────────────────────────
Write-Output '-- Agent Heartbeat --'

if ($mock) {
    $hbExists = $mock.legacy.heartbeat.exists
    $hbAge    = [double]$mock.legacy.heartbeat.ageMinutes
} else {
    $logPath  = 'C:\WindowsAzure\Logs\WaAppAgent.log'
    $hbExists = Test-Path $logPath
    if ($hbExists) {
        $hbAge = ((Get-Date) - (Get-Item $logPath).LastWriteTime).TotalMinutes
    } else {
        $hbAge = 999
    }
}

Add-Row 'Agent log file exists' (if ($hbExists) { 'OK' } else { 'FAIL' }) ''
$ageStatus = if (-not $hbExists) { 'FAIL' } elseif ($hbAge -gt 30) { 'FAIL' } elseif ($hbAge -gt 5) { 'WARN' } else { 'OK' }
Add-Row 'Agent log freshness (< 5 min)' $ageStatus ("{0:N1} min" -f $hbAge)

# ── Section: Extension Handlers ───────────────────────────────────────────────
Write-Output '-- Extension Handlers --'

if ($mock) {
    $extensions = @($mock.legacy.extensions)
} else {
    $extBase = 'HKLM:\SOFTWARE\Microsoft\Windows Azure\HandlerState'
    if (Test-Path $extBase) {
        $extensions = Get-ChildItem $extBase -ErrorAction SilentlyContinue | ForEach-Object {
            $n = $_.PSChildName
            $s = (Get-ItemProperty $_.PSPath -Name 'State' -ErrorAction SilentlyContinue).State
            $q = (Get-ItemProperty $_.PSPath -Name 'SequenceNumber' -ErrorAction SilentlyContinue).SequenceNumber
            [PSCustomObject]@{ name = $n; status = if ($s) { $s } else { 'Unknown' }; seqNo = "$q" }
        }
    } else {
        $extensions = @()
    }
}

if (@($extensions).Count -eq 0) {
    Add-Row 'Extension handlers registered' 'WARN' 'No handlers found'
} else {
    foreach ($ext in $extensions) {
        $eName  = "Ext: $($ext.name)"
        $eState = "$($ext.status)"
        $eStat  = if ($eState -eq 'Ready') { 'OK' } elseif ($eState -eq 'NotReady' -or $eState -eq 'Installing') { 'WARN' } else { 'FAIL' }
        Add-Row $eName $eStat "Seq=$($ext.seqNo) State=$eState"
    }
}

# ── Section: Agent Log Errors ─────────────────────────────────────────────────
Write-Output '-- Agent Log (recent ERR/WARN) --'

if ($mock) {
    $logLines = @($mock.legacy.recentLogErrors)
} else {
    $logPath = 'C:\WindowsAzure\Logs\WaAppAgent.log'
    if (Test-Path $logPath) {
        $logLines = Get-Content $logPath -Tail 80 -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match '\[ERROR\]|\[WARN\]|ERROR|WARN' } |
                    Select-Object -Last 5
    } else {
        $logLines = @()
    }
}

if (@($logLines).Count -eq 0) {
    Add-Row 'WaAppAgent.log recent errors' 'OK' 'No ERR/WARN in last 80 lines'
} else {
    Add-Row 'WaAppAgent.log recent errors' 'WARN' "$(@($logLines).Count) issue(s) found"
    $logLines | ForEach-Object { Write-Output "  >> $_" }
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
