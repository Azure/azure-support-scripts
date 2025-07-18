# Windows In-Place Upgrade Assessment Script
# Author: Bowen Zhang
# Last Updated: 2025-05-16
# Description: Checks Windows version, server upgrade paths, and Azure VM security features for upgrade readiness.

# --- OS Version Detection ---
$winVer = [System.Environment]::OSVersion.Version
if ($winVer.Major -eq 10) {
    if ($winVer.Build -ge 22000) {
        $windowsMajorVersion = 11
    } else {
        $windowsMajorVersion = 10
    }
} else {
    $windowsMajorVersion = $winVer.Major
}

# --- Server Upgrade Matrix ---
$serverUpgradeMatrix = @{
    'Windows Server 2008' = 'Windows Server 2012';
    'Windows Server 2008 R2' = 'Windows Server 2012';
    'Windows Server 2012' = 'Windows Server 2016';
    'Windows Server 2012 R2' = 'Windows Server 2016, Windows Server 2019, or Windows Server 2025';
    'Windows Server 2016' = 'Windows Server 2019, Windows Server 2022, or Windows Server 2025';
    'Windows Server 2019' = 'Windows Server 2022 or Windows Server 2025';
    'Windows Server 2022' = 'Windows Server 2025';
    'Windows Server 2022 Datacenter Azure Edition' = 'No direct upgrade path available. Consider redeploying a new VM.';
    'Windows Server 2025 Datacenter Azure Edition' = 'No direct upgrade path available. Consider redeploying a new VM.';
}

# --- Product Name and Server Check ---
$windowsProductName = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName
$isServer = $windowsProductName -like "Windows Server*"
$messages = @()

# --- Disk Space Check ---
$disk = Get-PSDrive -Name C
if ($disk.Free -lt 64GB) {
    $messages += "In Place Upgrade requires a minimum of 64 GB of system disk space. Please consider extending the disk space."
}

if ($isServer) {
    # --- Server Upgrade Path Output ---
    foreach ($serverVersion in $serverUpgradeMatrix.Keys) {
        if ($windowsProductName -like "$serverVersion*") {
            $messages += "The VM is running $serverVersion. The supported upgrade options are: $($serverUpgradeMatrix[$serverVersion])."
            $messages += ""
            $messages += "Please refer to the official documentation for more details: https://learn.microsoft.com/en-us/azure/virtual-machines/windows-in-place-upgrade"
            break
        }
    }
} else {
    # Only add a generic message for non-Windows 10/11
    if (($windowsMajorVersion -ne 10) -and ($windowsMajorVersion -ne 11)) {
        $messages += "The VM is running Windows $windowsMajorVersion"
    }

    # --- Windows 10 Upgrade Readiness ---
    if ($windowsMajorVersion -eq 10) {
        $biosVersion = (Get-WmiObject -Class Win32_BIOS).SMBIOSBIOSVersion
        if ($biosVersion -match 'UEFI') {
            try {
                # Query Azure VM Metadata (single call for all checks)
                $computeMetadata = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/compute?api-version=2023-07-01" -Headers @{Metadata='true'} -Method Get -UseBasicParsing
                $secureBootEnabled = $computeMetadata.securityProfile.secureBootEnabled
                $vtpmEnabled = $computeMetadata.securityProfile.virtualTpmEnabled
                $securityType = $computeMetadata.securityProfile.securityType
                $trustedLaunchEnabled = $securityType -eq 'TrustedLaunch'

                # Convert string to boolean for robust checks
                $secureBootEnabledBool = [System.Convert]::ToBoolean($secureBootEnabled)
                $vtpmEnabledBool = [System.Convert]::ToBoolean($vtpmEnabled)

                # Collect missing features
                $notEnabled = @()
                if (-not $trustedLaunchEnabled) { $notEnabled += 'Trusted Launch' }
                if (-not $secureBootEnabledBool) { $notEnabled += 'Secure Boot' }
                if (-not $vtpmEnabledBool) { $notEnabled += 'Virtual TPM' }
                if ($notEnabled.Count -gt 0) {
                    $messages += ""
                    $messages += ("FAILED: {0} is not enabled." -f ($notEnabled -join ', '))
                    $messages += ""
                    $messages += "The VM is running Windows 10 Gen2. you may upgrade it to Windows 11 via feature update, or using Windows 11 Installation Assistant. Confirm the upgrade eligibility using the PC Health Check App."
                } elseif ($trustedLaunchEnabled -and $secureBootEnabledBool -and $vtpmEnabledBool) {
                    $messages += ""
                    $messages += 'PASSED: The VM has Trusted Launch, Secure Boot and Virtual TPM enabled.'
                    $messages += ""
                    $messages += "The VM is running Windows 10 Gen2. you may upgrade it to Windows 11 via feature update, or using Windows 11 Installation Assistant. Confirm the upgrade eligibility using the PC Health Check App."
                }
            } catch {
                $messages += 'Error retrieving Azure metadata. Ensure the script is running on an Azure VM with access to instance metadata.'
            }
            $messages += ""
            $messages += 'PC Health Check App: https://support.microsoft.com/en-us/windows/how-to-use-the-pc-health-check-app-9c8abd9b-03ba-4e67-81ef-36f37caa7844'
            $messages += 'Windows 11 Installation Assistant: https://www.microsoft.com/en-us/software-download/windows11'
        } else {
            $messages += 'FAILED: The VM is running Windows 10 Gen1. Upgrade to Windows 11 is only supported for Gen2 VMs'
        }
    }
    # --- Windows 11 Upgrade Readiness ---
    if ($windowsMajorVersion -eq 11) {
        $windowsVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ReleaseId
        $versionNumber = [int]($windowsVersion -replace '\\D', '')
        if ($versionNumber -le 21) {
            try {
                $computeMetadata = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/compute?api-version=2023-07-01" -Headers @{Metadata='true'} -Method Get -UseBasicParsing
                $securityType = $computeMetadata.securityProfile.securityType
                $trustedLaunchEnabled = $securityType -eq 'TrustedLaunch'
                if ($trustedLaunchEnabled) {
                    $messages += 'PASSED: The Windows is eligible for upgrading to Windows 11 22H2 and above.'
                } else {
                    $messages += 'FAILED: Upgrading Windows 11 to 22H2 and above requires Trusted Launch to be enabled.'
                }
            } catch {
                $messages += 'Error retrieving Azure metadata. Ensure the script is running on an Azure VM with access to instance metadata.'
            }
        } else {
            $messages += 'The system is already running Windows 11 22H2 or above.'
        }
    }
}

# --- Output Results ---
$messages | ForEach-Object { Write-Output $_ }
