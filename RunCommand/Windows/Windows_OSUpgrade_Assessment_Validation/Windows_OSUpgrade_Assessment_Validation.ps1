# Windows In-Place Upgrade Assessment Script
# Last Updated: 2025-08-07
# Description: Checks Windows version, server upgrade paths, and Azure VM security features for upgrade readiness.

# --- Helper Functions ---
function Get-AzureSecurityProfile {
    try {
        $computeMetadata = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/instance/compute?api-version=2023-07-01" -Headers @{Metadata='true'} -Method Get -UseBasicParsing
        return $computeMetadata.securityProfile
    } catch {
        return $null
    }
}

function Test-FeatureEnabled {
    param(
        $trustedLaunchEnabled, $secureBootEnabled, $vtpmEnabled
    )
    $notEnabled = @()
    if (-not $trustedLaunchEnabled) { $notEnabled += 'Trusted Launch' }
    if (-not $secureBootEnabled) { $notEnabled += 'Secure Boot' }
    if (-not $vtpmEnabled) { $notEnabled += 'Virtual TPM' }
    return $notEnabled
}

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
    'Windows Server 2025' = 'No direct upgrade path available. Consider redeploying a new VM.'
    'Windows Server 2022 Datacenter Azure Edition' = 'No direct upgrade path available. Consider redeploying a new VM';
    'Windows Server 2025 Datacenter Azure Edition' = 'No direct upgrade path available. Consider redeploying a new VM';
}

# --- Product Name and Server Check ---
$windowsProductName = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName
$isServer = $windowsProductName -like "Windows Server*"
$messages = @()

# --- Hardware Checks ---
$disk = Get-PSDrive -Name C
$totalMemoryBytes = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
$totalMemoryGB = [math]::Round($totalMemoryBytes / 1GB, 2)
if ($windowsMajorVersion -eq 10 -or $windowsMajorVersion -eq 11) {
    $biosVersion = (Get-WmiObject -Class Win32_BIOS).SMBIOSBIOSVersion
}

# --- AVD Detection and Informational Message ---
if ($windowsProductName -match 'Virtual Desktop' -or $windowsProductName -match 'multi-session') {
    $messages += ""
    $messages += "The VM is running $windowsProductName version. If the VM is running in an Azure Virtual Desktop (AVD) environment: Session hosts in a pooled host pool aren't supported for in-place upgrade. Session hosts in a personal host pool are supported for in-place upgrade."
}

# --- Disk Space Message ---
if ($disk.Free -lt 64GB) {
    $messages += ""
    $messages += "In Place Upgrade requires a minimum of 64 GB of system disk space. Please consider extending the disk space."
    $diskCheckFailed = $true
} else {
    $diskCheckFailed = $false
}

# --- Physical Memory Message ---
if ($totalMemoryGB -lt 4) {
    $memoryCheckFailed = $true
} else {
    $memoryCheckFailed = $false
}

# --- Main Logic ---
if ($isServer) {
    if (-not $diskCheckFailed -and -not $memoryCheckFailed) {
        foreach ($serverVersion in $serverUpgradeMatrix.Keys) {
            if ($windowsProductName -like "$serverVersion*") {
                $messages += ""
                $messages += "The VM is running $windowsProductName. The supported upgrade options are: $($serverUpgradeMatrix[$serverVersion])."
                $messages += ""
                $messages += "Please refer to the official documentation for more details: https://learn.microsoft.com/en-us/azure/virtual-machines/windows-in-place-upgrade"
                break
            }
        }
    }
} else {
    if (($windowsMajorVersion -ne 10) -and ($windowsMajorVersion -ne 11)) {
        $messages += "The VM is running Windows $windowsMajorVersion"
    }
    # --- Windows 10 Upgrade Readiness ---
    if ($windowsMajorVersion -eq 10) {
        if ($biosVersion -match 'UEFI') {
            $securityProfile = Get-AzureSecurityProfile
            if ($null -eq $securityProfile) {
                $messages += ""
                $messages += 'Error retrieving Azure metadata. Ensure the script is running on an Azure VM with access to instance metadata.'
            } else {
                $trustedLaunchEnabled = $securityProfile.securityType -eq 'TrustedLaunch'
                $secureBootEnabledBool = [System.Convert]::ToBoolean($securityProfile.secureBootEnabled)
                $vtpmEnabledBool = [System.Convert]::ToBoolean($securityProfile.virtualTpmEnabled)
                $notEnabled = Test-FeatureEnabled $trustedLaunchEnabled $secureBootEnabledBool $vtpmEnabledBool
                if ($notEnabled.Count -gt 0) {
                    $messages += ""
                    $messages += ("FAILED: {0} is not enabled." -f ($notEnabled -join ', '))
                } else {
                    $messages += ""
                    $messages += 'PASSED: The VM has Trusted Launch, Secure Boot and Virtual TPM enabled.'
                    $messages += ""
                    $messages += "The VM is running Windows 10 Gen2. you may upgrade it to Windows 11 via feature update, or using Windows 11 Installation Assistant. Confirm the upgrade eligibility using the PC Health Check App."
                    $messages += ""
                    $messages += 'PC Health Check App: https://support.microsoft.com/en-us/windows/how-to-use-the-pc-health-check-app-9c8abd9b-03ba-4e67-81ef-36f37caa7844'
                    $messages += 'Windows 11 Installation Assistant: https://www.microsoft.com/software-download/windows11'
                }
            }
        } else {
            $messages += ""
            $messages += 'FAILED: The VM is running Windows 10 Gen1. Upgrade to Windows 11 is only supported for Gen2 VMs'
        }
    }
    # --- Windows 11 Upgrade Readiness ---
    if ($windowsMajorVersion -eq 11) {
        $windowsVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ReleaseId
        $versionNumber = [int]($windowsVersion -replace '\D', '')
        if ($versionNumber -le 21) {
            $securityProfile = Get-AzureSecurityProfile
            if ($null -eq $securityProfile) {
                $messages += ""
                $messages += 'Error retrieving Azure metadata. Ensure the script is running on an Azure VM with access to instance metadata.'
            } else {
                $trustedLaunchEnabled = $securityProfile.securityType -eq 'TrustedLaunch'
                if ($trustedLaunchEnabled) {
                    $messages += ""
                    $messages += 'PASSED: The Windows is eligible for upgrading to Windows 11 22H2 and above.'
                } else {
                    $messages += ""
                    $messages += 'FAILED: Upgrading Windows 11 to 22H2 and above requires Trusted Launch to be enabled.'
                }
            }
        } else {
            $messages += ""
            $messages += 'The system is already running Windows 11 22H2 or above.'
        }
    }
}

# --- Checklist Output ---
$checklist = @()
$checklist += "Windows Version: $windowsProductName"
$checklist += ""

# Disk Space Check
if ($disk.Free -ge 64GB) {
    $checklist += "[Passed] Disk Space (Free: $([math]::Round($disk.Free/1GB,2)) GB)"
} else {
    $checklist += "[Failed] Disk Space (Free: $([math]::Round($disk.Free/1GB,2)) GB; Required: 64 GB)"
}

# Physical Memory Check
if ($totalMemoryGB -ge 4) {
    $checklist += "[Passed] Physical Memory (Total: $totalMemoryGB GB)"
} else {
    $checklist += "[Failed] Physical Memory (Total: $totalMemoryGB GB; Required: 4 GB)"
}

if ($isServer) {
    # Windows Server: Only disk space and memory
} elseif ($windowsMajorVersion -eq 10 -or $windowsMajorVersion -eq 11) {
    $vmGen = if ($biosVersion -match 'UEFI') { 'Gen2' } else { 'Gen1' }
    if ($vmGen -eq 'Gen2') {
        $checklist += "[Passed] VM Generation: Gen2"
    } else {
        $checklist += "[Failed] VM Generation: Gen2 required for upgrade"
    }
    $securityProfile = Get-AzureSecurityProfile
    if ($null -eq $securityProfile) {
        $checklist += "[Failed] Unable to retrieve Azure metadata. Ensure the script is running on an Azure VM with access to instance metadata."
        $checklist += "IMDS Errors and debugging: https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service?tabs=windows#errors-and-debugging"
    } else {
        $trustedLaunchEnabled = $securityProfile.securityType -eq 'TrustedLaunch'
        $secureBootEnabledBool = [System.Convert]::ToBoolean($securityProfile.secureBootEnabled)
        $vtpmEnabledBool = [System.Convert]::ToBoolean($securityProfile.virtualTpmEnabled)
        if ($trustedLaunchEnabled) {
            $checklist += "[Passed] Trusted Launch"
        } else {
            $checklist += "[Failed] Trusted Launch"
        }
        if ($secureBootEnabledBool) {
            $checklist += "[Passed] Secure Boot"
        } else {
            $checklist += "[Failed] Secure Boot"
        }
        if ($vtpmEnabledBool) {
            $checklist += "[Passed] TPM Enabled"
        } else {
            $checklist += "[Failed] TPM Enabled"
        }
    }
}

# Output checklist first, then messages
$checklist | ForEach-Object { Write-Output $_ }
$messages | ForEach-Object { Write-Output $_ }
