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

Write-Output '=== Windows BitLocker KeyProtector Audit ==='
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
  # Probe: BitLocker volume protection status
  $bv = Get-CimInstance -Namespace "root\CIMV2\Security\MicrosoftVolumeEncryption" -ClassName Win32_EncryptableVolume -ErrorAction SilentlyContinue | Where-Object DriveLetter -eq "C:"; $pstat = if($bv){ $bv.ProtectionStatus } else { -1 }
  $_s = if($pstat -eq 0 -or $pstat -eq -1){'FAIL'}elseif($pstat -eq 1){'OK'}else{'WARN'}
  Add-Row 'BitLocker volume protection status' $_s ("Protection=$pstat (1=On 0=Off)")

  # Probe: Key protector count (C:)
  $kp = if($bv){ try{ ($bv | Invoke-CimMethod -MethodName GetKeyProtectors -ErrorAction SilentlyContinue).VolumeKeyProtectorID } catch { @() } } else { @() }; $kpCount = @($kp).Count
  $_s = if($kpCount -ge 2){'OK'}elseif($kpCount -eq 1){'WARN'}else{'FAIL'}
  Add-Row 'Key protector count (C:)' $_s ("Protectors=$kpCount")

  # Probe: Recovery password protector present
  $rpType = if($bv){ try{ ($bv | Invoke-CimMethod -MethodName GetKeyProtectors -Arguments @{KeyProtectorType=3} -ErrorAction SilentlyContinue).VolumeKeyProtectorID } catch { @() } } else { @() }
  $_s = if(@($rpType).Count -gt 0){'OK'}elseif(@($rpType).Count -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'Recovery password protector present' $_s ("RecoveryPwd=$(if(@($rpType).Count -gt 0){`"present`"}else{`"missing`"})")

  # Probe: TPM protector present
  $tpmP = if($bv){ try{ ($bv | Invoke-CimMethod -MethodName GetKeyProtectors -Arguments @{KeyProtectorType=1} -ErrorAction SilentlyContinue).VolumeKeyProtectorID } catch { @() } } else { @() }
  $_s = if(@($tpmP).Count -gt 0){'OK'}elseif(@($tpmP).Count -eq 0){'WARN'}else{'FAIL'}
  Add-Row 'TPM protector present' $_s ("TPM=$(if(@($tpmP).Count -gt 0){`"present`"}else{`"none`"})")

  # Probe: Encryption method strength
  $em = if($bv){ try{ ($bv | Invoke-CimMethod -MethodName GetEncryptionMethod -ErrorAction SilentlyContinue).EncryptionMethod } catch { 0 } } else { 0 }
  $_s = if($em -ge 4){'OK'}elseif($em -gt 0 -and $em -lt 4){'WARN'}else{'FAIL'}
  Add-Row 'Encryption method strength' $_s ("Method=$em (4+=XTS-AES-128+)")

  # Probe: Conversion status (fully encrypted)
  $cs = if($bv){ try{ ($bv | Invoke-CimMethod -MethodName GetConversionStatus -ErrorAction SilentlyContinue).ConversionStatus } catch { -1 } } else { -1 }
  $_s = if($cs -eq 1){'OK'}elseif($cs -eq 2 -or $cs -eq 3){'WARN'}else{'FAIL'}
  Add-Row 'Conversion status (fully encrypted)' $_s ("Status=$cs (1=FullyEncrypted)")

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

