<# 
NOTE: Cleanup may take time depending on the number of ghosted NICs detected.
    - Up to 30 minutes if ~600 ghosted NICs are found.
    - Up to 60+ minutes if over 1000 ghosted NICs are found.

Disclaimer:
    The sample scripts are not supported under any Microsoft standard support program or service.
    The sample scripts are provided AS IS without warranty of any kind.
    Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability
    or of fitness for a particular purpose.
    The entire risk arising out of the use or performance of the sample scripts and documentation remains with you.
    In no event shall Microsoft, its authors, or anyone else involved in the creation, production,
    or delivery of the scripts be liable for any damages whatsoever (including, without limitation,
    damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss)
    arising out of the use of or inability to use the sample scripts or documentation,
    even if Microsoft has been advised of the possibility of such damages.

.SYNOPSIS
    Detects ghosted (disconnected) and valid network interface cards (NICs) on Windows.
    Version: 1.0 (Modified by Copilot for enhanced messaging)

.DESCRIPTION
    This script scans the Windows registry for network adapters on PCI and VMBUS buses,
    compares them with currently active network adapters, and identifies ghosted NICs.
    Useful for troubleshooting network issues or cleaning up old NICs.

.NOTES
    Requires administrator privileges.
    Tested on Windows Server 2016+.

.EXAMPLE
    Run as administrator:
    PS> .\Windows_GhostedNIC_Detection.ps1
#>

# ---- Safety checks -----------------------------------------------------------
function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Please run this script as Administrator." -ForegroundColor Red
        exit 1
    }
}
Assert-Admin

Write-Host "`r`nInitializing NIC scan..." -ForegroundColor Cyan
Write-Host "NOTE: Cleanup may take time depending on the number of ghosted NICs detected."
Write-Host "      - Up to 30 minutes if ~600 ghosted NICs are found."
Write-Host "      - Up to 60+ minutes if over 1000 ghosted NICs are found.`r`n" -ForegroundColor Yellow

# Get all current network adapter PnP IDs
Write-Host "Collecting all current network adapter PnPDeviceIDs..." -ForegroundColor White
$AllAdaptersPnPIDs = (Get-NetAdapter).PnpDeviceID
$global:FoundGhostNICs = 0
$global:FoundValidNICs = 0

Function ScanRegistryForNICs($BusName) {
    $RootPath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\"
    $RegistryPath = "$($RootPath.Replace("HKEY_LOCAL_MACHINE\","HKLM:\"))$($BusName)"
    Write-Host "`r`nScanning $BusName devices in registry..." -ForegroundColor Cyan

    Try {
        If (Test-Path -Path $RegistryPath) {
            $Items = Get-ChildItem $RegistryPath -Depth 0
            $i = 0
            $Total = $Items.Count

            $Items | ForEach-Object {
                $i++
                Write-Progress -Activity "Scanning $BusName registry entries" -Status "Processing $i of $Total" -PercentComplete (($i / $Total) * 100)

                $Bus = $_
                $BusPath = $Bus.Name.ToString().Replace("HKEY_LOCAL_MACHINE\","HKLM:\")

                Get-ChildItem $BusPath -Depth 0 | ForEach-Object {
                    $Bus = $_
                    $BusPath = $Bus.Name.ToString().Replace("HKEY_LOCAL_MACHINE\","HKLM:\")
                    $BusRelativeName = $Bus.Name.ToString().Replace($RootPath,"")

                    Try { $ServiceType = (Get-ItemProperty -Path $BusPath -Name Service -ErrorAction SilentlyContinue).Service } Catch { $ServiceType = $null }
                    Try { $DeviceDesc = (Get-ItemProperty -Path $BusPath -Name DeviceDesc -ErrorAction SilentlyContinue).DeviceDesc } Catch { $DeviceDesc = $null }
                    Try { $DevIndex = (Get-ItemProperty -Path "$BusPath\Device Parameters" -Name InstanceIndex -ErrorAction SilentlyContinue).InstanceIndex } Catch { $DevIndex = $null }

                    If ($DeviceDesc) {
                        Try {
                            $Split = $DeviceDesc -split ";"
                            $DeviceDescription = $Split[1]
                            If ($DevIndex -and $DevIndex -ne 1) {
                                $DeviceDescription += " #$($DevIndex)"
                            }
                        } Catch {
                            $DeviceDescription = "Unknown Device"
                        }
                    } Else {
                        $DeviceDescription = "Unknown Device"
                    }

                    If ($ServiceType -in ("netvsc", "mlx5", "mlx4_bus")) {
                        $MatchesPnpID = $AllAdaptersPnPIDs | Where-Object { $_ -eq $BusRelativeName }
                        If ($MatchesPnpID) {
                            $global:FoundValidNICs++
                            Write-Host "Valid NIC: $($DeviceDescription)" -ForegroundColor Green
                        } Else {
                            $global:FoundGhostNICs++
                            Write-Host "Ghosted NIC: $($DeviceDescription)" -ForegroundColor Yellow
                        }
                    }
                }
            }
        } Else {
            Write-Host "Registry path $($RegistryPath) not found, skipping..." -ForegroundColor DarkGray
        }
    } Catch {
        Write-Error "Error while scanning registry: $_"
    }
}

ScanRegistryForNICs("PCI")
ScanRegistryForNICs("VMBUS")

Write-Host "`r`nScan complete. Summary:" -ForegroundColor Cyan
Write-Host "Found ghosted NIC(s): $($FoundGhostNICs)" -ForegroundColor Red
Write-Host "Found valid NIC(s): $($FoundValidNICs)" -ForegroundColor Green
Write-Host "`r`nEstimated cleanup time guidance:" -ForegroundColor Cyan
Write-Host " - ~30 mins for ~600 ghosted NICs" -ForegroundColor Yellow
Write-Host " - ~60+ mins for >1000 ghosted NICs`r`n" -ForegroundColor Yellow

Write-Host "`r`nGhosted NIC Removal script on GitHub:`r`nhttps://aka.ms/AzVmGhostedNicCleanup" -ForegroundColor Cyan
Write-Host "`r`nAdditional Information: https://aka.ms/AzVmGhostedNicDetect" -ForegroundColor Cyan
Write-Host "`r`nScript completed successfully." -ForegroundColor Cyan