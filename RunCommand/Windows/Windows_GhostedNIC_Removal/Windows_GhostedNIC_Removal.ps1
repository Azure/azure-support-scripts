<# 
Disclaimer
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
    identifies ghosted (disconnected) NICs, and will remove them up from the registry.
    It uses SYSTEM privileges to remove registry keys and runs pnpclean to clean up device entries.
    Useful for troubleshooting or cleaning up old NICs.

.NOTES
    Requires administrator privileges.
    Tested on Windows Server 2016+.

.EXAMPLE
    Run as administrator:
    PS> .\Windows_GhostedNIC_Removal_time.ps1
#>

If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

Write-Host "Collecting all current network adapter PnPDeviceIDs..."
$AllAdaptersPnPIDs = (Get-NetAdapter).PnpDeviceID
$global:FoundGhostNICs = 0
$global:FoundValidNICs = 0
$global:GhostedNICsToDelete = @()

Function ExecuteAsSystem($cmd) {
    Try {
        $taskName = "TempSystemTask_$([guid]::NewGuid().ToString())"
        $TaskArgs = '-NoProfile -WindowStyle Hidden -Command "###cmd###"'
        $TaskArgs = $TaskArgs -replace '###cmd###',$cmd
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $TaskArgs
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal | Out-Null
        Start-ScheduledTask -TaskName $taskName

        While ((Get-ScheduledTask -TaskName $taskName).State -eq "Running" -Or (Get-ScheduledTaskInfo -TaskName $taskName).LastRunTime -notmatch (Get-Date).ToString("yyyy")) {
            Start-Sleep -Seconds 1
        }

        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
    } Catch {
        Write-Error "Failed to execute command as SYSTEM: $_"
    }
}

Function ScanRegistryForNICs($BusName) {
    $RootPath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\"
    $RegistryPath = "$($RootPath.Replace("HKEY_LOCAL_MACHINE\","HKLM:\"))$($BusName)"

    Try {
        If (Test-Path -Path $RegistryPath) {
            Get-ChildItem $RegistryPath -Depth 0 | ForEach-Object {
                $Bus = $_
                $BusPath = $Bus.Name.ToString().Replace("HKEY_LOCAL_MACHINE\","HKLM:\")

                Get-ChildItem $BusPath -Depth 0 | ForEach-Object {
                    $Bus = $_
                    $BusPath = $Bus.Name.ToString().Replace("HKEY_LOCAL_MACHINE\","HKLM:\")
                    $BusRelativeName = $Bus.Name.ToString().Replace($RootPath,"")

                    Try { $ServiceType = (Get-ItemProperty -Path $BusPath -Name Service -ErrorAction SilentlyContinue).Service } Catch { $ServiceType = $null }
                    Try { $DeviceDesc = (Get-ItemProperty -Path $BusPath -Name DeviceDesc -ErrorAction SilentlyContinue).DeviceDesc } Catch { $DeviceDesc = $null }
                    Try { $DevIndex = (Get-ItemProperty -Path $($BusPath + "\Device Parameters") -Name InstanceIndex -ErrorAction SilentlyContinue).InstanceIndex } Catch { $DevIndex = $null }

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
                            $global:GhostedNICsToDelete += $BusPath
                            Write-Host "Ghosted NIC: $($DeviceDescription)" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
    } Catch {
        Write-Error "Error while scanning registry: $_"
    }
}

Function CheckRootKeys() {
    Write-Host "Checking for empty root keys in registry..."
    $EmptyRootKeysToDelete = @()

    Try {
        $GhostedNICsToDelete | ForEach-Object {
            $ParentKey = Split-Path -Path $_ -Parent
            If (Test-Path -Path $ParentKey) {
                If ((Get-ChildItem $ParentKey -Depth 0 | Measure-Object).Count -eq 0) {
                    If (-Not $EmptyRootKeysToDelete.Contains($ParentKey)) {
                        $EmptyRootKeysToDelete += $ParentKey
                    }
                }
            }
        }
    } Catch {
        Write-Error "Error while checking root keys: $_"
    }

    $EmptyRootKeysToDelete | ForEach-Object {
        If (Test-Path -Path $_) {
            Write-Host "Deleting empty root key $($_)..."
            ExecuteAsSystem "Remove-Item -Path '$($_)' -Recurse -Confirm:`$false -Force"
        }
    }
}

Function DeleteGhostedNICs() {
    Write-Host "Cleaning ghosted NIC(s) using pnpclean..."

    Try {
        Invoke-Command {c:\windows\system32\RUNDLL32.exe c:\windows\system32\pnpclean.dll,RunDLL_PnpClean /Devices /Maxclean}
        Start-Sleep -Seconds 10

        $GhostedNICsToDelete | ForEach-Object {
            If (Test-Path -Path $_) {
                Write-Host "Deleting registry key for ghosted NIC: $($_)..."
                ExecuteAsSystem "Remove-Item -Path '$($_)' -Recurse -Confirm:`$false -Force"
            }
        }
    } Catch {
        Write-Error "Error while deleting ghosted NICs: $_"
    }

    CheckRootKeys
}

ScanRegistryForNICs("PCI")
ScanRegistryForNICs("VMBUS")

Write-Host "`r`n"
Write-Host "Found ghosted NIC(s): $($FoundGhostNICs)" -ForegroundColor Red
Write-Host "Found valid NIC(s): $($FoundValidNICs)" -ForegroundColor Green

If ($FoundGhostNICs -gt 0) {
    Write-Host "`r`n"
    Write-Host "NOTE: Cleanup may take time depending on the number of ghosted NICs detected." -ForegroundColor Yellow
    Write-Host " - Up to 30 minutes if ~600 ghosted NICs are found." -ForegroundColor Yellow
    Write-Host " - Up to 60+ minutes if over 1000 ghosted NICs are found." -ForegroundColor Yellow
    Write-Host "`r`n"

    $CleanEntries = Read-Host "Should we clean ghosted NIC(s)? (Y/N)"
    Write-Host "`r`n"

    Switch($CleanEntries.ToLower()) {
        { $_ -in "y","yes" } {
            DeleteGhostedNICs
        }
        { $_ -in "n","no" } { 
            Write-Host "No changes made."
        }
        default { 
            Write-Host "Invalid answer. (Y/N)"
            return
        }
    }
}

Write-Host "`r`nScript completed successfully." -ForegroundColor Cyan
