#Requires -Version 5.1
<#
.SYNOPSIS
    Reports BitLocker and Azure Disk Encryption (ADE) state across all volumes.
.DESCRIPTION
    Checks encryption configuration critical for disk and boot diagnostics:
      1. BitLocker volumes — protection status + conversion state per drive
      2. ADE extension — handler registry state (Ready/NotReady/Unresponsive)
      3. ADE settings — registry presence + OS drive encryption state

    Designed for Azure Run Command: no Az module, no internet, PS 5.1 only.
.PARAMETER MockConfig
    Path to a JSON file that replaces live reads for offline testing.
.NOTES
    Author  : CSS Core Compute SPM
    Version : 1.0.0
    Tool ID : RC-008
    Bucket  : Azure-Encryption / Cant-RDP-SSH / Disk
    Repo    : Azure/azure-support-scripts  RunCommand/Windows/Windows_Encryption_State_Check
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

Write-Output '=== Windows Encryption State Check ==='
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

# ── BitLocker Volume Status ───────────────────────────────────────────────────
Write-Output '-- BitLocker Volume Status --'

if ($mock) {
    $blVolumes = @($mock.legacy.bitlocker.volumes)
} else {
    $blVolumes = @()
    try {
        $blVols = Get-WmiObject -Namespace 'ROOT\CIMV2\Security\MicrosoftVolumeEncryption' -Class Win32_EncryptableVolume -ErrorAction Stop
        foreach ($v in $blVols) {
            $drive = $v.DriveLetter
            if (-not $drive) { continue }
            $protStatus = [int]$v.ProtectionStatus
            $convStatus = [int]$v.ConversionStatus
            $protCount  = 0
            try { $protCount = @($v.GetKeyProtectors(0).VolumeKeyProtectorID).Count } catch {}
            $blVolumes += [PSCustomObject]@{
                drive            = $drive
                protectionStatus = $protStatus
                conversionStatus = $convStatus
                protectorCount   = $protCount
            }
        }
    } catch {
        # BitLocker WMI namespace not available
    }
}

if (@($blVolumes).Count -eq 0) {
    Add-Row 'BitLocker volumes detected' 'OK' 'No encrypted volumes found'
} else {
    foreach ($vol in $blVolumes) {
        $protLabel = switch ([int]$vol.protectionStatus) { 0 { 'Off' } 1 { 'Protected' } 2 { 'Unknown' } default { 'Unknown' } }
        $convLabel = switch ([int]$vol.conversionStatus) { 0 { 'FullyDecrypted' } 1 { 'FullyEncrypted' } 2 { 'EncryptionInProgress' } 3 { 'DecryptionInProgress' } default { 'Unknown' } }
        $blStatus = if ([int]$vol.protectionStatus -eq 0) { 'OK' } else { 'WARN' }
        if ([int]$vol.conversionStatus -in 2, 3) { $blStatus = 'WARN' }
        Add-Row "$($vol.drive) Encryption: $protLabel" $blStatus "Conv=$convLabel"
    }
}

# ── Azure Disk Encryption Extension ──────────────────────────────────────────
Write-Output '-- Azure Disk Encryption (ADE) Extension --'

if ($mock) {
    $adeHandlers = @($mock.legacy.ade.handlers)
} else {
    $adeHandlers = @()
    $extBase = 'HKLM:\SOFTWARE\Microsoft\Windows Azure\HandlerState'
    if (Test-Path $extBase) {
        $adeHandlers = Get-ChildItem $extBase -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match 'AzureDiskEncryption' } |
            ForEach-Object {
                $n = $_.PSChildName
                $s = (Get-ItemProperty $_.PSPath -Name 'State' -ErrorAction SilentlyContinue).State
                $q = (Get-ItemProperty $_.PSPath -Name 'SequenceNumber' -ErrorAction SilentlyContinue).SequenceNumber
                [PSCustomObject]@{ name = $n; status = if ($s) { $s } else { 'Unknown' }; seqNo = "$q" }
            }
    }
}

if (@($adeHandlers).Count -eq 0) {
    Add-Row 'ADE extension installed' 'OK' 'Not present — VM not using ADE'
} else {
    foreach ($h in $adeHandlers) {
        $hName = "ADE: $($h.name)"
        $hStat = if ($h.status -eq 'Ready') { 'OK' } elseif ($h.status -eq 'NotReady' -or $h.status -eq 'Installing') { 'WARN' } else { 'FAIL' }
        Add-Row $hName $hStat "Seq=$($h.seqNo) State=$($h.status)"
    }
}

# ── ADE Encryption Settings ──────────────────────────────────────────────────
Write-Output '-- ADE Encryption Settings --'

if ($mock) {
    $adePresent      = $mock.legacy.ade.settingsPresent -eq $true
    $osDiskEncrypted = $mock.legacy.ade.osDiskEncrypted -eq $true
} else {
    $adeRegKey = 'HKLM:\SOFTWARE\Microsoft\Azure Security\AzureDiskEncryption'
    $adePresent = Test-Path $adeRegKey
    $osDiskEncrypted = $false
    if ($adePresent) {
        $adeSettings = Get-ItemProperty $adeRegKey -ErrorAction SilentlyContinue
        $osDiskEncrypted = $adeSettings -and ($adeSettings.OsDiskEncrypted -eq 'True' -or $adeSettings.EncryptionOperation -match 'Encrypt')
    }
}

Add-Row 'ADE settings registry present' (if ($adePresent) { 'WARN' } else { 'OK' }) (if ($adePresent) { 'ADE was or is active on this VM' } else { '' })
if ($adePresent) {
    Add-Row 'OS drive (C:) encrypted by ADE' (if ($osDiskEncrypted) { 'WARN' } else { 'OK' }) ''
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
