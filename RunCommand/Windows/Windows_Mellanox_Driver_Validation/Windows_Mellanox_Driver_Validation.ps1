<#
.SYNOPSIS
    Windows_Mellanox_Driver_Validation.ps1 - Validates Mellanox mlx5 network adapter
    driver versions on Azure Windows VMs.

.DESCRIPTION
    This script detects installed Mellanox (NVIDIA) network adapters, retrieves their
    driver versions, and checks the Windows Event Log for recent bugcheck events
    associated with DRIVER_IRQL_NOT_LESS_OR_EQUAL (0x000000D1) — a common signature
    of outdated Mellanox mlx5 driver issues on Azure Windows VMs.

    Outputs a diagnostic summary suitable for use with the Azure portal RunCommand
    feature or direct execution on the VM by a support engineer.

.NOTES
    Related TSG: Mellanox mlx5 Driver Crash – Outdated Driver (Windows)
    https://dev.azure.com/Supportability/AzureIaaSVM/_wiki/wikis/AzureIaaSVM/2539440/

    Version: 1.0
    Author:  azure-support-scripts contributors

.LINK
    https://github.com/Azure/azure-support-scripts/tree/master/RunCommand/Windows/Windows_Mellanox_Driver_Validation
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

#region --- Helpers ---

function Write-SectionHeader {
    param ([string]$Title)
    $bar = '=' * 60
    Write-Output ""
    Write-Output $bar
    Write-Output "  $Title"
    Write-Output $bar
}

function Write-Result {
    param (
        [ValidateSet('PASS','FAIL','WARN','INFO')][string]$Status,
        [string]$Message
    )
    Write-Output "  [$Status] $Message"
}

#endregion

#region --- Script start ---

Write-Output "Windows Mellanox Driver Validation"
Write-Output "Run Date : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
Write-Output "Computer : $env:COMPUTERNAME"

#endregion

#region --- [1] Detect Mellanox / NVIDIA ConnectX adapters ---

Write-SectionHeader "1. Mellanox / NVIDIA Network Adapter Detection"

$mellanoxAdapters = @()

# Query PnP devices matching Mellanox or NVIDIA ConnectX families
$pnpDevices = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Mellanox|ConnectX|mlx5|NVIDIA.*Ethernet' }

if (-not $pnpDevices) {
    Write-Result INFO "No Mellanox / NVIDIA ConnectX network adapters detected on this VM."
    Write-Output ""
    Write-Output "  This script targets VMs with Mellanox mlx5-family adapters."
    Write-Output "  If you expected one, confirm the VM SKU (e.g. HB, HC, ND, NDv2, HBv3)."
}
else {
    foreach ($dev in $pnpDevices) {
        Write-Result INFO "Found: $($dev.FriendlyName) | Status: $($dev.Status) | InstanceId: $($dev.InstanceId)"
        $mellanoxAdapters += $dev
    }
}

#endregion

#region --- [2] Driver Version Check ---

Write-SectionHeader "2. Driver Version Details"

if ($mellanoxAdapters.Count -eq 0) {
    Write-Result INFO "Skipped — no Mellanox adapters found."
}
else {
    # Pull signed driver info from WMI for each adapter
    $allDrivers = Get-WmiObject Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceName -match 'Mellanox|ConnectX|mlx5|NVIDIA.*Ethernet' }

    if (-not $allDrivers) {
        Write-Result WARN "Could not retrieve driver details via Win32_PnPSignedDriver. Adapter(s) present but driver data unavailable."
    }
    else {
        foreach ($drv in $allDrivers) {
            Write-Output ""
            Write-Output "  Device      : $($drv.DeviceName)"
            Write-Output "  Driver Desc : $($drv.Description)"
            Write-Output "  Version     : $($drv.DriverVersion)"
            Write-Output "  Driver Date : $($drv.DriverDate)"
            Write-Output "  Provider    : $($drv.DriverProviderName)"
            Write-Output "  INF File    : $($drv.InfName)"

            # Parse driver date for age check (format: yyyyMMdd000000.000000+000)
            if ($drv.DriverDate -match '^(\d{4})(\d{2})(\d{2})') {
                $drvDate = [datetime]::ParseExact("$($Matches[1])-$($Matches[2])-$($Matches[3])", 'yyyy-MM-dd', $null)
                $ageDays = ([datetime]::UtcNow - $drvDate).Days
                $ageYears = [math]::Round($ageDays / 365, 1)

                if ($ageDays -gt 730) {
                    Write-Result WARN "Driver is $ageYears years old ($ageDays days). Review against TSG minimum supported version."
                }
                elseif ($ageDays -gt 365) {
                    Write-Result WARN "Driver is $ageYears years old. Confirm version meets TSG requirements."
                }
                else {
                    Write-Result PASS "Driver age: $ageDays days ($ageYears years). Appears recent."
                }
            }
            else {
                Write-Result INFO "Driver date format not parseable: $($drv.DriverDate)"
            }
        }
    }

    Write-Output ""
    Write-Output "  ACTION REQUIRED: Compare the above version against the minimum supported"
    Write-Output "  version documented in the TSG before proceeding."
}

#endregion

#region --- [3] Bugcheck Event Log Check ---

Write-SectionHeader "3. Bugcheck Event Log — DRIVER_IRQL (0x000000D1)"

$lookbackDays = 30
$since = (Get-Date).AddDays(-$lookbackDays)

# BugCheck events are logged by the kernel under EventID 1001 in Application log (source: Windows Error Reporting)
# and kernel-power EventID 41 in System log. We look for the 0xD1 signature in both.

$bugcheckEvents = @()

# System log — Event 41 (unexpected shutdown / kernel power loss after bugcheck)
$sysEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Id        = 41
    StartTime = $since
} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match '0x000000d1|0xd1|DRIVER_IRQL_NOT_LESS_OR_EQUAL' }

if ($sysEvents) {
    $bugcheckEvents += $sysEvents
}

# Application log — Event 1001 (Windows Error Reporting, captures bugcheck code)
$appEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Application'
    Id        = 1001
    StartTime = $since
} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match '0x000000d1|0xd1|DRIVER_IRQL_NOT_LESS_OR_EQUAL' }

if ($appEvents) {
    $bugcheckEvents += $appEvents
}

if ($bugcheckEvents.Count -eq 0) {
    Write-Result PASS "No DRIVER_IRQL_NOT_LESS_OR_EQUAL (0xD1) bugcheck events found in the last $lookbackDays days."
}
else {
    Write-Result WARN "$($bugcheckEvents.Count) potential bugcheck event(s) found in the last $lookbackDays days."
    Write-Output ""

    foreach ($evt in $bugcheckEvents | Sort-Object TimeCreated -Descending | Select-Object -First 10) {
        Write-Output "  Time    : $($evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-Output "  Log     : $($evt.LogName)"
        Write-Output "  EventID : $($evt.Id)"
        # Trim message to first 200 chars to keep output clean
        $msgPreview = if ($evt.Message.Length -gt 200) { $evt.Message.Substring(0, 200) + '...' } else { $evt.Message }
        Write-Output "  Message : $msgPreview"
        Write-Output ""
    }

    Write-Result WARN "Review these events against the TSG. If 0x000000D1 is confirmed, proceed with driver update workflow."
}

#endregion

#region --- [4] Network Adapter Status Summary ---

Write-SectionHeader "4. Mellanox Adapter Link Status"

if ($mellanoxAdapters.Count -eq 0) {
    Write-Result INFO "Skipped — no Mellanox adapters found."
}
else {
    $netAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -match 'Mellanox|ConnectX|mlx5|NVIDIA.*Ethernet' }

    if (-not $netAdapters) {
        Write-Result WARN "Mellanox PnP device found but no matching Get-NetAdapter entries. Adapter may be in error state."
    }
    else {
        foreach ($nic in $netAdapters) {
            $statusSymbol = if ($nic.Status -eq 'Up') { 'PASS' } else { 'WARN' }
            Write-Result $statusSymbol "NIC: $($nic.Name) | Description: $($nic.InterfaceDescription) | Status: $($nic.Status) | LinkSpeed: $($nic.LinkSpeed)"
        }
    }
}

#endregion

#region --- Summary ---

Write-SectionHeader "SUMMARY"

Write-Output "  Mellanox adapters detected : $($mellanoxAdapters.Count)"

if ($mellanoxAdapters.Count -gt 0) {
    Write-Output ""
    Write-Output "  NEXT STEPS:"
    Write-Output "  1. Confirm driver version against TSG minimum supported version."
    Write-Output "  2. If driver is outdated, follow the TSG update process."
    Write-Output "  3. If 0xD1 bugcheck events were found, correlate timestamp with driver date."
    Write-Output ""
    Write-Output "  TSG Reference:"
    Write-Output "  Mellanox mlx5 Driver Crash - Outdated Driver (Windows)"
    Write-Output "  https://dev.azure.com/Supportability/AzureIaaSVM/_wiki/wikis/AzureIaaSVM/2539440/"
}
else {
    Write-Output ""
    Write-Output "  No Mellanox adapters found. This TSG may not apply to this VM."
    Write-Output "  Verify the VM SKU and network adapter configuration."
}

Write-Output ""
Write-Output "  Script completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"

#endregion
