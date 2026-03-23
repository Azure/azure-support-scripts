    <#

.SYNOPSIS

    Detects Secure Boot certificate update status for fleet-wide monitoring.
.DESCRIPTION

    This detection script collects Secure Boot status, certificate update registry values,

    and device information. It displays a color-coded report with clear next steps.
    Compatible with Intune Remediations, GPO-based collection, and other management tools.

    No remediation script is needed - this is monitoring only.
    Exit 0 = "Without issue"  (certificates updated)

    Exit 1 = "With issue"     (certificates not updated - informational only)
.EXAMPLE

    # Run the status check

    .\Detect-SecureBootCertUpdateStatus.ps1
.NOTES

    Registry paths per https://aka.ms/securebootplaybook:

      HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot

      HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR

    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,

    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE

    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER

    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,

    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE

    SOFTWARE.

.CHANGELOG

    v1.0 - 2026-03-18

      - Added color-coded console output for all key status values

      - Added banner header with playbook reference link

      - Added section headers (Device Information, Secure Boot Status, Certificate Update

        Status, Device Attributes, Event Log Analysis, System Information, Update Delivery)

      - Added AvailableUpdates bitmask decoding (DB, DBX, KEK, PK, Boot Manager, Firmware,

        UEFI CA 2023, Signing Policy flags)

      - Added plain-English descriptions for all Secure Boot event IDs (1795-1808)

      - Added event timestamp display for the latest event

      - Added explanatory messages for SecureBootEnabled, UEFICA2023Status, and error states

      - Added Secure-Boot-Update scheduled task last run time check

      - Added summary section with overall PASS/ACTION NEEDED status and specific findings

      - Event descriptions colored by severity (Green=success, Cyan=info, Yellow=warning, Red=error)

    v1.1 - 2026-03-18

      - Removed JSON output and OutputPath parameter (script is now console-report only)

      - Replaced generic summary with prioritized NEXT STEPS section

      - Next steps are context-aware: reboot, enable Secure Boot, re-enable scheduled task,

        known firmware issue guidance, OEM contact for firmware/KEK, Windows Update fallback

      - Includes specific commands (e.g., schtasks /Change) where applicable

    v1.2 - 2026-03-18

      - Fixed PASS summary to still recommend reboot when Event 1800 is present,

        even if the UEFI CA 2023 certificate is already installed

    v1.3 - 2026-03-18

      - Fixed Event 1800 (reboot pending) check to run regardless of update status.

        Previously it was inside the error-analysis block which was skipped when

        UEFICA2023Status=Updated, so reboot-pending was never detected on updated devices.

    v1.4 - 2026-03-18

      - Updated AvailableUpdates bitmask decoding to match playbook documentation:

        0x4 (KEK 2K CA 2023), 0x40 (UEFI CA 2023 into DB), 0x80 (Revoke PCA 2011/DBX),

        0x100 (Boot Managers), 0x200 (SVN into DBX)

      - Added detection of 0x5944 (Deploy ALL) combined value with explanatory note

    v1.5 - 2026-03-18

      - Fixed reboot-pending detection: now based on the LATEST TPM-WMI event only,

        not historical Event 1800 count. If Event 1808 (success) is newer than 1800,

        the reboot already completed and no action is needed.

      - Scoped event log query to ProviderName='TPM-WMI' for accuracy.

#>

# Download URL: https://aka.ms/getsecureboot -> "Deployment and Monitoring Samples"

# Note: This script runs on endpoints to collect Secure Boot status data.

# =============================================================================
# Banner
# =============================================================================
Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  Secure Boot Certificate Update Status Check" -ForegroundColor Cyan
Write-Host "  Reference: https://aka.ms/securebootplaybook" -ForegroundColor DarkGray
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Data Collection
# =============================================================================
Write-Host "--- Device Information ---" -ForegroundColor White
# 1. HostName

# PS Version: All | Admin: No | System Requirements: None

try {

    $hostname = $env:COMPUTERNAME

    if ([string]::IsNullOrEmpty($hostname)) {

        Write-Warning "Hostname could not be determined"

        $hostname = "Unknown"

    }

    Write-Host "Hostname: $hostname"

} catch {

    Write-Warning "Error retrieving hostname: $_"

    $hostname = "Error"

    Write-Host "Hostname: $hostname"

}
# 2. CollectionTime

# PS Version: All | Admin: No | System Requirements: None

try {

    $collectionTime = Get-Date

    if ($null -eq $collectionTime) {

        Write-Warning "Could not retrieve current date/time"

        $collectionTime = "Unknown"

    }

    Write-Host "Collection Time: $collectionTime"

} catch {

    Write-Warning "Error retrieving date/time: $_"

    $collectionTime = "Error"

    Write-Host "Collection Time: $collectionTime"

}

Write-Host ""
Write-Host "--- Secure Boot Status ---" -ForegroundColor White
# Registry: Secure Boot Main Key (3 values)
# 3. SecureBootEnabled

# PS Version: 3.0+ | Admin: May be required | System Requirements: UEFI/Secure Boot capable system

try {

    $secureBootEnabled = Confirm-SecureBootUEFI -ErrorAction Stop

    if ($secureBootEnabled) {

        Write-Host "Secure Boot Enabled: $secureBootEnabled" -ForegroundColor Green

    } else {

        Write-Host "Secure Boot Enabled: $secureBootEnabled" -ForegroundColor Red

        Write-Host "  -> Secure Boot must be enabled for the certificate update to apply." -ForegroundColor Yellow

    }

} catch {

    Write-Warning "Unable to determine Secure Boot status via cmdlet: $_"

    # Try registry fallback

    try {

        $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name UEFISecureBootEnabled -ErrorAction Stop

        $secureBootEnabled = [bool]$regValue.UEFISecureBootEnabled

        if ($secureBootEnabled) {

            Write-Host "Secure Boot Enabled: $secureBootEnabled" -ForegroundColor Green

        } else {

            Write-Host "Secure Boot Enabled: $secureBootEnabled" -ForegroundColor Red

            Write-Host "  -> Secure Boot must be enabled for the certificate update to apply." -ForegroundColor Yellow

        }

    } catch {

        Write-Warning "Unable to determine Secure Boot status via registry. System may not support UEFI/Secure Boot."

        $secureBootEnabled = $null

        Write-Host "Secure Boot Enabled: Not Available" -ForegroundColor Yellow

        Write-Host "  -> Could not determine Secure Boot status. System may not support UEFI." -ForegroundColor DarkGray

    }

}
# 4. HighConfidenceOptOut

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot" -Name HighConfidenceOptOut -ErrorAction Stop

    $highConfidenceOptOut = $regValue.HighConfidenceOptOut

    Write-Host "High Confidence Opt Out: $highConfidenceOptOut"

} catch {

    # HighConfidenceOptOut is optional - not present on most systems

    $highConfidenceOptOut = $null

    Write-Host "High Confidence Opt Out: Not Set"

}
# 4b. MicrosoftUpdateManagedOptIn

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot" -Name MicrosoftUpdateManagedOptIn -ErrorAction Stop

    $microsoftUpdateManagedOptIn = $regValue.MicrosoftUpdateManagedOptIn

    Write-Host "Microsoft Update Managed Opt In: $microsoftUpdateManagedOptIn"

} catch {

    # MicrosoftUpdateManagedOptIn is optional - not present on most systems

    $microsoftUpdateManagedOptIn = $null

    Write-Host "Microsoft Update Managed Opt In: Not Set"

}
# 5. AvailableUpdates

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot" -Name AvailableUpdates -ErrorAction Stop

    $availableUpdates = $regValue.AvailableUpdates

    if ($null -ne $availableUpdates) {

        # Convert to hexadecimal format

        $availableUpdatesHex = "0x{0:X}" -f $availableUpdates

        Write-Host "Available Updates: $availableUpdatesHex"

        # Check for well-known combined value first

        if ($availableUpdates -eq 0x5944) {

            Write-Host "  -> Deploy ALL certificates and Boot Manager (0x5944)" -ForegroundColor Cyan

            Write-Host "     This is the recommended configuration for manual deployment." -ForegroundColor DarkGray

        }

        # Decode the bitmask into human-readable flags

        $updateFlags = @()

        if ($availableUpdates -band 0x4)   { $updateFlags += '0x4    - Add Microsoft Corporation KEK 2K CA 2023 certificate into KEK' }

        if ($availableUpdates -band 0x40)  { $updateFlags += '0x40   - Add Windows UEFI CA 2023 certificate into DB' }

        if ($availableUpdates -band 0x80)  { $updateFlags += '0x80   - Revoke PCA 2011 Certificate (update DBX)' }

        if ($availableUpdates -band 0x100) { $updateFlags += '0x100  - Update the Boot Managers' }

        if ($availableUpdates -band 0x200) { $updateFlags += '0x200  - Update SVN value into DBX' }

        if ($updateFlags.Count -gt 0) {

            foreach ($flag in $updateFlags) {

                Write-Host "  -> $flag" -ForegroundColor DarkGray

            }

        } else {

            Write-Host "  -> No recognized update flags set" -ForegroundColor DarkGray

        }

    } else {

        Write-Host "Available Updates: Not Available"

    }

} catch {

    Write-Warning "AvailableUpdates registry key not found or inaccessible"

    $availableUpdates = $null

    Write-Host "Available Updates: Not Available"

}
# 5b. AvailableUpdatesPolicy (GPO-controlled persistent value)

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot" -Name AvailableUpdatesPolicy -ErrorAction Stop

    $availableUpdatesPolicy = $regValue.AvailableUpdatesPolicy

    if ($null -ne $availableUpdatesPolicy) {

        # Convert to hexadecimal format

        $availableUpdatesPolicyHex = "0x{0:X}" -f $availableUpdatesPolicy

        Write-Host "Available Updates Policy: $availableUpdatesPolicyHex"

    } else {

        Write-Host "Available Updates Policy: Not Set"

    }

} catch {

    # AvailableUpdatesPolicy is optional - only set when GPO is applied

    $availableUpdatesPolicy = $null

    Write-Host "Available Updates Policy: Not Set"

}

Write-Host ""
Write-Host "--- Certificate Update Status ---" -ForegroundColor White
# Registry: Servicing Key (3 values)
# 6. UEFICA2023Status

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing" -Name UEFICA2023Status -ErrorAction Stop

    $uefica2023Status = $regValue.UEFICA2023Status

    if ($uefica2023Status -eq 'Updated') {

        Write-Host "Windows UEFI CA 2023 Status: $uefica2023Status" -ForegroundColor Green

        Write-Host "  -> The new UEFI CA 2023 certificate has been successfully installed." -ForegroundColor DarkGray

    } elseif ($uefica2023Status -eq 'OptedOut') {

        Write-Host "Windows UEFI CA 2023 Status: $uefica2023Status" -ForegroundColor Yellow

        Write-Host "  -> This device has been opted out of the certificate update." -ForegroundColor DarkGray

    } else {

        Write-Host "Windows UEFI CA 2023 Status: $uefica2023Status" -ForegroundColor Yellow

        Write-Host "  -> The certificate update has not completed yet." -ForegroundColor DarkGray

    }

} catch {

    Write-Warning "Windows UEFI CA 2023 Status registry key not found or inaccessible"

    $uefica2023Status = $null

    Write-Host "Windows UEFI CA 2023 Status: Not Available" -ForegroundColor Yellow

    Write-Host "  -> Registry key not found. The servicing stack update may not be installed yet." -ForegroundColor DarkGray

}
# 7. UEFICA2023Error

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing" -Name UEFICA2023Error -ErrorAction Stop

    $uefica2023Error = $regValue.UEFICA2023Error

    Write-Host "UEFI CA 2023 Error: $uefica2023Error" -ForegroundColor Red

    Write-Host "  -> An error was recorded during the certificate update process." -ForegroundColor Yellow

} catch {

    # UEFICA2023Error only exists if there was an error - absence is good

    $uefica2023Error = $null

    Write-Host "UEFI CA 2023 Error: None" -ForegroundColor Green

}
# 8. UEFICA2023ErrorEvent

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing" -Name UEFICA2023ErrorEvent -ErrorAction Stop

    $uefica2023ErrorEvent = $regValue.UEFICA2023ErrorEvent

    Write-Host "UEFI CA 2023 Error Event: $uefica2023ErrorEvent"

} catch {

    $uefica2023ErrorEvent = $null

    Write-Host "UEFI CA 2023 Error Event: Not Available"

}
Write-Host ""

Write-Host "--- Device Attributes ---" -ForegroundColor White

# Registry: Device Attributes (7 values: 9-15)
# 9. OEMManufacturerName

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\DeviceAttributes" -Name OEMManufacturerName -ErrorAction Stop

    $oemManufacturerName = $regValue.OEMManufacturerName

    if ([string]::IsNullOrEmpty($oemManufacturerName)) {

        Write-Warning "OEMManufacturerName is empty"

        $oemManufacturerName = "Unknown"

    }

    Write-Host "OEM Manufacturer Name: $oemManufacturerName"

} catch {

    Write-Warning "OEMManufacturerName registry key not found or inaccessible"

    $oemManufacturerName = $null

    Write-Host "OEM Manufacturer Name: Not Available"

}
# 10. OEMModelSystemFamily

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\DeviceAttributes" -Name OEMModelSystemFamily -ErrorAction Stop

    $oemModelSystemFamily = $regValue.OEMModelSystemFamily

    if ([string]::IsNullOrEmpty($oemModelSystemFamily)) {

        Write-Warning "OEMModelSystemFamily is empty"

        $oemModelSystemFamily = "Unknown"

    }

    Write-Host "OEM Model System Family: $oemModelSystemFamily"

} catch {

    Write-Warning "OEMModelSystemFamily registry key not found or inaccessible"

    $oemModelSystemFamily = $null

    Write-Host "OEM Model System Family: Not Available"

}
# 11. OEMModelNumber

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\DeviceAttributes" -Name OEMModelNumber -ErrorAction Stop

    $oemModelNumber = $regValue.OEMModelNumber

    if ([string]::IsNullOrEmpty($oemModelNumber)) {

        Write-Warning "OEMModelNumber is empty"

        $oemModelNumber = "Unknown"

    }

    Write-Host "OEM Model Number: $oemModelNumber"

} catch {

    Write-Warning "OEMModelNumber registry key not found or inaccessible"

    $oemModelNumber = $null

    Write-Host "OEM Model Number: Not Available"

}
# 12. FirmwareVersion

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\DeviceAttributes" -Name FirmwareVersion -ErrorAction Stop

    $firmwareVersion = $regValue.FirmwareVersion

    if ([string]::IsNullOrEmpty($firmwareVersion)) {

        Write-Warning "FirmwareVersion is empty"

        $firmwareVersion = "Unknown"

    }

    Write-Host "Firmware Version: $firmwareVersion"

} catch {

    Write-Warning "FirmwareVersion registry key not found or inaccessible"

    $firmwareVersion = $null

    Write-Host "Firmware Version: Not Available"

}
# 13. FirmwareReleaseDate

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\DeviceAttributes" -Name FirmwareReleaseDate -ErrorAction Stop

    $firmwareReleaseDate = $regValue.FirmwareReleaseDate

    if ([string]::IsNullOrEmpty($firmwareReleaseDate)) {

        Write-Warning "FirmwareReleaseDate is empty"

        $firmwareReleaseDate = "Unknown"

    }

    Write-Host "Firmware Release Date: $firmwareReleaseDate"

} catch {

    Write-Warning "FirmwareReleaseDate registry key not found or inaccessible"

    $firmwareReleaseDate = $null

    Write-Host "Firmware Release Date: Not Available"

}
# 14. OSArchitecture

# PS Version: All | Admin: No | System Requirements: None

try {

    $osArchitecture = $env:PROCESSOR_ARCHITECTURE

    if ([string]::IsNullOrEmpty($osArchitecture)) {

        # Try registry fallback

        $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\DeviceAttributes" -Name OSArchitecture -ErrorAction Stop

        $osArchitecture = $regValue.OSArchitecture

    }

    if ([string]::IsNullOrEmpty($osArchitecture)) {

        Write-Warning "OSArchitecture could not be determined"

        $osArchitecture = "Unknown"

    }

    Write-Host "OS Architecture: $osArchitecture"

} catch {

    Write-Warning "Error retrieving OSArchitecture: $_"

    $osArchitecture = "Unknown"

    Write-Host "OS Architecture: $osArchitecture"

}
# 15. CanAttemptUpdateAfter (FILETIME)

# PS Version: All | Admin: May be required | System Requirements: None

try {

    $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\DeviceAttributes" -Name CanAttemptUpdateAfter -ErrorAction Stop

    $canAttemptUpdateAfter = $regValue.CanAttemptUpdateAfter

    # Convert FILETIME to UTC DateTime - registry stores as REG_BINARY (byte[]) or REG_QWORD (long)

    if ($null -ne $canAttemptUpdateAfter) {

        try {

            if ($canAttemptUpdateAfter -is [byte[]]) {

                $fileTime = [BitConverter]::ToInt64($canAttemptUpdateAfter, 0)

                $canAttemptUpdateAfter = [DateTime]::FromFileTime($fileTime).ToUniversalTime()

            } elseif ($canAttemptUpdateAfter -is [long]) {

                $canAttemptUpdateAfter = [DateTime]::FromFileTime($canAttemptUpdateAfter).ToUniversalTime()

            }

        } catch {

            Write-Warning "Could not convert CanAttemptUpdateAfter FILETIME to DateTime"

        }

    }

    Write-Host "Can Attempt Update After: $canAttemptUpdateAfter"

} catch {

    Write-Warning "CanAttemptUpdateAfter registry key not found or inaccessible"

    $canAttemptUpdateAfter = $null

    Write-Host "Can Attempt Update After: Not Available"

}

Write-Host ""
Write-Host "--- Event Log Analysis ---" -ForegroundColor White
# Event Logs: System Log (10 values: 16-25)
# 16-25. Event Log queries

# Event IDs:

#   1801 - Update initiated, reboot required

#   1808 - Update completed successfully

#   1795 - Firmware returned error (capture error code)

#   1796 - Error logged with error code (capture code)

#   1800 - Reboot needed (NOT an error - update will proceed after reboot)

#   1802 - Known firmware issue blocked update (capture KI_<number> from SkipReason)

#   1803 - Matching KEK update not found (OEM needs to supply PK signed KEK)

# PS Version: 3.0+ | Admin: May be required for System log | System Requirements: None

# Event ID descriptions for user-friendly output

$eventDescriptions = @{

    1795 = 'Firmware returned an error during the Secure Boot certificate update'

    1796 = 'An error code was logged during the Secure Boot update process'

    1800 = 'A reboot is required to complete the Secure Boot certificate update (this is normal - NOT an error)'

    1801 = 'Secure Boot certificate update has been initiated and a reboot is required to apply it'

    1802 = 'A known firmware issue is preventing the Secure Boot certificate update on this device'

    1803 = 'A matching KEK update was not found - the OEM needs to supply a PK-signed KEK for this device'

    1808 = 'Secure Boot certificate update completed successfully'

}

try {

    # Query all relevant Secure Boot event IDs from TPM-WMI provider

    $allEventIds = @(1795, 1796, 1800, 1801, 1802, 1803, 1808)

    $events = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-TPM-WMI'; ID=$allEventIds} -MaxEvents 50 -ErrorAction Stop)
    if ($events.Count -eq 0) {

        Write-Warning "No Secure Boot events found in System log"

        $latestEventId = $null

        $bucketId = $null

        $confidence = $null

        $skipReasonKnownIssue = $null

        $event1801Count = 0

        $event1808Count = 0

        $event1795Count = 0

        $event1795ErrorCode = $null

        $event1796Count = 0

        $event1796ErrorCode = $null

        $event1800Count = 0

        $rebootPending = $false

        $event1802Count = 0

        $knownIssueId = $null

        $event1803Count = 0

        $missingKEK = $false

        Write-Host "Latest Event ID: Not Available"

        Write-Host "Bucket ID: Not Available"

        Write-Host "Confidence: Not Available"

        Write-Host "Event 1801 Count: 0"

        Write-Host "Event 1808 Count: 0"

    } else {

        # 16. LatestEventId

        $latestEvent = $events | Sort-Object TimeCreated -Descending | Select-Object -First 1

        if ($null -eq $latestEvent) {

            Write-Warning "Could not determine latest event"

            $latestEventId = $null

            Write-Host "Latest Event ID: Not Available"

        } else {

            $latestEventId = $latestEvent.Id

            $latestEventDesc = $eventDescriptions[$latestEventId]

            # Color-code by severity: green for success, cyan for informational, yellow for warning, red for error

            switch ($latestEventId) {

                1808 { $evtColor = 'Green' }

                1800 { $evtColor = 'Cyan' }

                1801 { $evtColor = 'Cyan' }

                1802 { $evtColor = 'Yellow' }

                1803 { $evtColor = 'Yellow' }

                { $_ -in @(1795, 1796) } { $evtColor = 'Red' }

                default { $evtColor = 'White' }

            }

            Write-Host "Latest Event ID: $latestEventId - $latestEventDesc" -ForegroundColor $evtColor

            Write-Host "  (Event Time: $($latestEvent.TimeCreated.ToUniversalTime().ToString('o')))" -ForegroundColor DarkGray

        }
        # 17. BucketID - Extracted from Event 1801/1808

        if ($null -ne $latestEvent -and $null -ne $latestEvent.Message) {

            if ($latestEvent.Message -match 'BucketId:\s*(.+)') {

                $bucketId = $matches[1].Trim()

                Write-Host "Bucket ID: $bucketId"

            } else {

                Write-Warning "BucketId not found in event message"

                $bucketId = $null

                Write-Host "Bucket ID: Not Found in Event"

            }

        } else {

            Write-Warning "Latest event or message is null, cannot extract BucketId"

            $bucketId = $null

            Write-Host "Bucket ID: Not Available"

        }
        # 18. Confidence - Extracted from Event 1801/1808

        if ($null -ne $latestEvent -and $null -ne $latestEvent.Message) {

            if ($latestEvent.Message -match 'BucketConfidenceLevel:\s*(.+)') {

                $confidence = $matches[1].Trim()

                Write-Host "Confidence: $confidence"

            } else {

                Write-Warning "Confidence level not found in event message"

                $confidence = $null

                Write-Host "Confidence: Not Found in Event"

            }

        } else {

            Write-Warning "Latest event or message is null, cannot extract Confidence"

            $confidence = $null

            Write-Host "Confidence: Not Available"

        }
        # 18b. SkipReason - Extract KI_<number> from SkipReason in the same event as BucketId

        # This captures Known Issue IDs that appear alongside BucketId/Confidence (not just Event 1802)

        $skipReasonKnownIssue = $null

        if ($null -ne $latestEvent -and $null -ne $latestEvent.Message) {

            if ($latestEvent.Message -match 'SkipReason:\s*(KI_\d+)') {

                $skipReasonKnownIssue = $matches[1]

                Write-Host "SkipReason Known Issue: $skipReasonKnownIssue" -ForegroundColor Yellow

            }

        }
        # 19. Event1801Count

        $event1801Array = @($events | Where-Object {$_.Id -eq 1801})

        $event1801Count = $event1801Array.Count

        Write-Host "Event 1801 Count: $event1801Count"
        # 20. Event1808Count

        $event1808Array = @($events | Where-Object {$_.Id -eq 1808})

        $event1808Count = $event1808Array.Count

        Write-Host "Event 1808 Count: $event1808Count"



        # Initialize error event variables

        $event1795Count = 0

        $event1795ErrorCode = $null

        $event1796Count = 0

        $event1796ErrorCode = $null

        $event1800Count = 0

        $rebootPending = $false

        $event1802Count = 0

        $knownIssueId = $null

        $event1803Count = 0

        $missingKEK = $false

        # Check if a reboot is pending based on the LATEST event (not historical)
        # If 1808 (success) came after 1800/1801, the reboot already happened

        $event1800Array = @($events | Where-Object {$_.Id -eq 1800})

        $event1800Count = $event1800Array.Count

        $rebootPending = $latestEventId -in @(1800, 1801)

        if ($rebootPending) {

            Write-Host "Event $latestEventId (Reboot Pending): A reboot is still required" -ForegroundColor Cyan

        } elseif ($event1800Count -gt 0) {

            Write-Host "Event 1800 Count: $event1800Count (resolved - latest event is $latestEventId)" -ForegroundColor DarkGray

        }

        # Only check for error events if update is NOT complete

        # Skip error analysis if: 1808 is latest event OR UEFICA2023Status is "Updated"

        $updateComplete = ($latestEventId -eq 1808) -or ($uefica2023Status -eq "Updated")



        if (-not $updateComplete) {

            Write-Host "Update not complete - checking for error events..." -ForegroundColor Yellow



            # 21. Event1795 - Firmware Error (capture error code)

            $event1795Array = @($events | Where-Object {$_.Id -eq 1795})

            $event1795Count = $event1795Array.Count

            if ($event1795Count -gt 0) {

                $latestEvent1795 = $event1795Array | Sort-Object TimeCreated -Descending | Select-Object -First 1

                if ($latestEvent1795.Message -match '(?:error|code|status)[:\s]*(?:0x)?([0-9A-Fa-f]{8}|[0-9A-Fa-f]+)') {

                    $event1795ErrorCode = $matches[1]

                }

                Write-Host "Event 1795 (Firmware Error) Count: $event1795Count" $(if ($event1795ErrorCode) { "Code: $event1795ErrorCode" }) -ForegroundColor Red

                Write-Host "  -> $($eventDescriptions[1795])" -ForegroundColor DarkGray

                Write-Host "  -> This typically means the device firmware rejected the update. A firmware update from the OEM may be required." -ForegroundColor Yellow

            }



            # 22. Event1796 - Error Code Logged (capture error code)

            $event1796Array = @($events | Where-Object {$_.Id -eq 1796})

            $event1796Count = $event1796Array.Count

            if ($event1796Count -gt 0) {

                $latestEvent1796 = $event1796Array | Sort-Object TimeCreated -Descending | Select-Object -First 1

                if ($latestEvent1796.Message -match '(?:error|code|status)[:\s]*(?:0x)?([0-9A-Fa-f]{8}|[0-9A-Fa-f]+)') {

                    $event1796ErrorCode = $matches[1]

                }

                Write-Host "Event 1796 (Error Logged) Count: $event1796Count" $(if ($event1796ErrorCode) { "Code: $event1796ErrorCode" }) -ForegroundColor Red

                Write-Host "  -> $($eventDescriptions[1796])" -ForegroundColor DarkGray

            }



            # 24. Event1802 - Known Firmware Issue (capture KI_<number> from SkipReason)

            $event1802Array = @($events | Where-Object {$_.Id -eq 1802})

            $event1802Count = $event1802Array.Count

            if ($event1802Count -gt 0) {

                $latestEvent1802 = $event1802Array | Sort-Object TimeCreated -Descending | Select-Object -First 1

                if ($latestEvent1802.Message -match 'SkipReason:\s*(KI_\d+)') {

                    $knownIssueId = $matches[1]

                }

                Write-Host "Event 1802 (Known Firmware Issue) Count: $event1802Count" $(if ($knownIssueId) { "KI: $knownIssueId" }) -ForegroundColor Yellow

                Write-Host "  -> $($eventDescriptions[1802])" -ForegroundColor DarkGray

                if ($knownIssueId) {

                    Write-Host "  -> Known Issue ID: $knownIssueId - check https://aka.ms/securebootplaybook for details on this issue." -ForegroundColor Yellow

                }

            }



            # 25. Event1803 - Missing KEK Update (OEM needs to supply PK signed KEK)

            $event1803Array = @($events | Where-Object {$_.Id -eq 1803})

            $event1803Count = $event1803Array.Count

            $missingKEK = $event1803Count -gt 0

            if ($missingKEK) {

                Write-Host "Event 1803 (Missing KEK): OEM needs to supply PK signed KEK" -ForegroundColor Yellow

            }

        } else {

            Write-Host "Update complete (Event 1808 or Status=Updated) - skipping error analysis" -ForegroundColor Green

        }

    }

} catch {

    Write-Warning "Error retrieving event logs. May require administrator privileges: $_"

    $latestEventId = $null

    $bucketId = $null

    $confidence = $null

    $skipReasonKnownIssue = $null

    $event1801Count = 0

    $event1808Count = 0

    $event1795Count = 0

    $event1795ErrorCode = $null

    $event1796Count = 0

    $event1796ErrorCode = $null

    $event1800Count = 0

    $rebootPending = $false

    $event1802Count = 0

    $knownIssueId = $null

    $event1803Count = 0

    $missingKEK = $false

    Write-Host "Latest Event ID: Error"

    Write-Host "Bucket ID: Error"

    Write-Host "Confidence: Error"

    Write-Host "Event 1801 Count: 0"

    Write-Host "Event 1808 Count: 0"

}

Write-Host ""
Write-Host "--- System Information ---" -ForegroundColor White
# WMI/CIM Queries (5 values)
# 26. OSVersion

# PS Version: 3.0+ (use Get-WmiObject for 2.0) | Admin: No | System Requirements: None

try {

    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop

    if ($null -eq $osInfo -or [string]::IsNullOrEmpty($osInfo.Version)) {

        Write-Warning "Could not retrieve OS version"

        $osVersion = "Unknown"

    } else {

        $osVersion = $osInfo.Version

    }

    Write-Host "OS Version: $osVersion"

} catch {

    # CIM may fail in some environments - use fallback

    $osVersion = [System.Environment]::OSVersion.Version.ToString()

    if ([string]::IsNullOrEmpty($osVersion)) { $osVersion = "Unknown" }

    Write-Host "OS Version: $osVersion"

}
# 27. LastBootTime

# PS Version: 3.0+ (use Get-WmiObject for 2.0) | Admin: No | System Requirements: None

try {

    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop

    if ($null -eq $osInfo -or $null -eq $osInfo.LastBootUpTime) {

        Write-Warning "Could not retrieve last boot time"

        $lastBootTime = $null

        Write-Host "Last Boot Time: Not Available"

    } else {

        $lastBootTime = $osInfo.LastBootUpTime

        Write-Host "Last Boot Time: $lastBootTime"

    }

} catch {

    # CIM may fail in some environments - use fallback

    try {

        $lastBootTime = (Get-Process -Id 0 -ErrorAction SilentlyContinue).StartTime

    } catch {

        $lastBootTime = $null

    }

    if ($lastBootTime) { Write-Host "Last Boot Time: $lastBootTime" } else { Write-Host "Last Boot Time: Not Available" }

}
# 28. BaseBoardManufacturer

# PS Version: 3.0+ (use Get-WmiObject for 2.0) | Admin: No | System Requirements: None

try {

    $baseBoard = Get-CimInstance Win32_BaseBoard -ErrorAction Stop

    if ($null -eq $baseBoard -or [string]::IsNullOrEmpty($baseBoard.Manufacturer)) {

        Write-Warning "Could not retrieve baseboard manufacturer"

        $baseBoardManufacturer = "Unknown"

    } else {

        $baseBoardManufacturer = $baseBoard.Manufacturer

    }

    Write-Host "Baseboard Manufacturer: $baseBoardManufacturer"

} catch {

    # CIM may fail - baseboard info is supplementary

    $baseBoardManufacturer = "Unknown"

    Write-Host "Baseboard Manufacturer: $baseBoardManufacturer"

}
# 29. BaseBoardProduct

# PS Version: 3.0+ (use Get-WmiObject for 2.0) | Admin: No | System Requirements: None

try {

    $baseBoard = Get-CimInstance Win32_BaseBoard -ErrorAction Stop

    if ($null -eq $baseBoard -or [string]::IsNullOrEmpty($baseBoard.Product)) {

        Write-Warning "Could not retrieve baseboard product"

        $baseBoardProduct = "Unknown"

    } else {

        $baseBoardProduct = $baseBoard.Product

    }

    Write-Host "Baseboard Product: $baseBoardProduct"

} catch {

    # CIM may fail - baseboard info is supplementary

    $baseBoardProduct = "Unknown"

    Write-Host "Baseboard Product: $baseBoardProduct"

}
Write-Host ""

Write-Host "--- Update Delivery Mechanisms ---" -ForegroundColor White

# 30. SecureBootTaskEnabled

# PS Version: All | Admin: No | System Requirements: Scheduled Task exists

# Checks if the Secure-Boot-Update scheduled task is enabled

$secureBootTaskEnabled = $null

$secureBootTaskStatus = "Unknown"

$secureBootTaskLastRun = $null

try {

    $taskOutput = schtasks.exe /Query /TN "\Microsoft\Windows\PI\Secure-Boot-Update" /FO CSV 2>&1

    if ($LASTEXITCODE -eq 0) {

        $taskData = $taskOutput | ConvertFrom-Csv

        if ($taskData) {

            $secureBootTaskStatus = $taskData.Status

            $secureBootTaskEnabled = ($taskData.Status -eq 'Ready' -or $taskData.Status -eq 'Running')

        }

    } else {

        $secureBootTaskStatus = "NotFound"

        $secureBootTaskEnabled = $false

    }

    # Get last run time via verbose query

    $taskVerbose = schtasks.exe /Query /TN "\Microsoft\Windows\PI\Secure-Boot-Update" /FO CSV /V 2>&1

    if ($LASTEXITCODE -eq 0) {

        $taskVerboseData = $taskVerbose | ConvertFrom-Csv

        if ($taskVerboseData -and $taskVerboseData.'Last Run Time') {

            $lastRunStr = $taskVerboseData.'Last Run Time'

            if ($lastRunStr -eq 'N/A' -or $lastRunStr -eq '11/30/1999 12:00:00 AM') {

                $secureBootTaskLastRun = "Never"

            } else {

                try {

                    $secureBootTaskLastRun = [datetime]::Parse($lastRunStr).ToUniversalTime().ToString("o")

                } catch {

                    $secureBootTaskLastRun = $lastRunStr

                }

            }

        }

    }

    if ($secureBootTaskEnabled -eq $false) {

        Write-Host "SecureBoot Update Task: $secureBootTaskStatus (Enabled: $secureBootTaskEnabled)" -ForegroundColor Yellow

    } else {

        Write-Host "SecureBoot Update Task: $secureBootTaskStatus (Enabled: $secureBootTaskEnabled)" -ForegroundColor Green

    }

    Write-Host "SecureBoot Update Task Last Run: $secureBootTaskLastRun"

} catch {

    $secureBootTaskStatus = "Error"

    $secureBootTaskEnabled = $false

    $secureBootTaskLastRun = $null

    Write-Host "SecureBoot Update Task: Error checking - $_" -ForegroundColor Red

}
# 31. WinCS Key Status (F33E0C8E002 - Secure Boot Certificate Update)

# PS Version: All | Admin: Yes (for query) | System Requirements: WinCsFlags.exe

$wincsKeyApplied = $null

$wincsKeyStatus = "Unknown"

try {

    # Check common locations for WinCsFlags.exe

    $wincsFlagsPath = $null

    $possiblePaths = @(

        "$env:SystemRoot\System32\WinCsFlags.exe",

        "$env:SystemRoot\SysWOW64\WinCsFlags.exe"

    )

    foreach ($p in $possiblePaths) {

        if (Test-Path $p) { $wincsFlagsPath = $p; break }

    }



    if ($wincsFlagsPath) {

        # Query specific key - requires admin rights

        $queryOutput = & $wincsFlagsPath /query --key F33E0C8E002 2>&1

        $queryOutputStr = $queryOutput -join "`n"



        if ($LASTEXITCODE -eq 0) {

            # Check if key is applied (look for "Active Configuration" or similar indicator)

            if ($queryOutputStr -match "Active Configuration.*:.*enabled" -or $queryOutputStr -match "Configuration.*applied") {

                $wincsKeyApplied = $true

                $wincsKeyStatus = "Applied"

                Write-Host "WinCS Key F33E0C8E002: Applied" -ForegroundColor Green

            } elseif ($queryOutputStr -match "not found|No configuration") {

                $wincsKeyApplied = $false

                $wincsKeyStatus = "NotApplied"

                Write-Host "WinCS Key F33E0C8E002: Not Applied" -ForegroundColor Yellow

            } else {

                # Key exists - check output for state

                $wincsKeyApplied = $true

                $wincsKeyStatus = "Applied"

                Write-Host "WinCS Key F33E0C8E002: Applied" -ForegroundColor Green

            }

        } else {

            # Check for specific error messages

            if ($queryOutputStr -match "Access denied|administrator") {

                $wincsKeyStatus = "AccessDenied"

                Write-Host "WinCS Key F33E0C8E002: Access denied (run as admin)" -ForegroundColor DarkGray

            } elseif ($queryOutputStr -match "not found|No configuration") {

                $wincsKeyApplied = $false

                $wincsKeyStatus = "NotApplied"

                Write-Host "WinCS Key F33E0C8E002: Not Applied" -ForegroundColor Yellow

            } else {

                $wincsKeyStatus = "QueryFailed"

                Write-Host "WinCS Key F33E0C8E002: Query failed" -ForegroundColor Red

            }

        }

    } else {

        $wincsKeyStatus = "WinCsFlagsNotFound"

        Write-Host "WinCS Key F33E0C8E002: WinCsFlags.exe not found" -ForegroundColor Gray

    }

} catch {

    $wincsKeyStatus = "Error"

    Write-Host "WinCS Key F33E0C8E002: Error checking - $_" -ForegroundColor Red

}
# =============================================================================
# Summary & Next Steps
# =============================================================================
Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

# Determine overall status
$isUpdated = ($secureBootEnabled -eq $true) -and ($uefica2023Status -eq 'Updated')
if ($isUpdated) {
    Write-Host "  [PASS] Secure Boot certificate update is COMPLETE." -ForegroundColor Green
    Write-Host "         Secure Boot is enabled and the UEFI CA 2023 certificate is installed." -ForegroundColor Green
    Write-Host ""
    if ($rebootPending) {
        Write-Host "  NEXT STEP: Reboot this device. The certificate is installed, but a reboot" -ForegroundColor Cyan
        Write-Host "             is still required to finalize remaining Secure Boot updates." -ForegroundColor Cyan
    } else {
        Write-Host "  NEXT STEP: No action required. This device is up to date." -ForegroundColor Green
    }
} else {
    Write-Host "  [ACTION NEEDED] Secure Boot certificate update is NOT complete." -ForegroundColor Red
    Write-Host ""

    # Show findings
    if ($secureBootEnabled -ne $true) {
        Write-Host "  * Secure Boot is not enabled (required for the update)." -ForegroundColor Yellow
    }
    if ($uefica2023Status -ne 'Updated') {
        $statusDisplay = if ($uefica2023Status) { $uefica2023Status } else { 'Not Available' }
        Write-Host "  * UEFI CA 2023 certificate status: $statusDisplay" -ForegroundColor Yellow
    }
    if ($rebootPending) {
        Write-Host "  * A reboot is pending - the update should complete after rebooting." -ForegroundColor Cyan
    }
    if ($null -ne $uefica2023Error) {
        Write-Host "  * An error was recorded during the update (Error: $uefica2023Error)." -ForegroundColor Red
    }
    if ($missingKEK) {
        Write-Host "  * The OEM needs to provide a PK-signed KEK update for this device." -ForegroundColor Yellow
    }
    if ($knownIssueId) {
        Write-Host "  * A known firmware issue ($knownIssueId) is blocking the update." -ForegroundColor Yellow
    }
    if ($secureBootTaskEnabled -eq $false -and $secureBootTaskStatus -ne 'NotFound') {
        Write-Host "  * The Secure-Boot-Update scheduled task is disabled." -ForegroundColor Yellow
    }
    if ($event1795Count -gt 0) {
        Write-Host "  * Firmware errors detected ($event1795Count occurrences)." -ForegroundColor Yellow
    }

    # -------------------------------------------------------------------------
    # Next Steps - prioritized by most likely resolution
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "  NEXT STEPS:" -ForegroundColor White
    Write-Host "  -----------" -ForegroundColor White

    $stepNum = 1

    # Reboot pending is the simplest fix
    if ($rebootPending) {
        Write-Host "  $stepNum. Reboot this device. The update has been staged and will complete" -ForegroundColor Cyan
        Write-Host "     after a restart." -ForegroundColor Cyan
        $stepNum++
    }

    # Secure Boot not enabled
    if ($secureBootEnabled -ne $true) {
        Write-Host "  $stepNum. Enable Secure Boot in the UEFI/BIOS firmware settings." -ForegroundColor Yellow
        Write-Host "     The certificate update requires Secure Boot to be active." -ForegroundColor DarkGray
        $stepNum++
    }

    # Scheduled task disabled
    if ($secureBootTaskEnabled -eq $false -and $secureBootTaskStatus -ne 'NotFound') {
        Write-Host "  $stepNum. Re-enable the Secure Boot Update scheduled task:" -ForegroundColor Yellow
        Write-Host "     schtasks.exe /Change /TN `"\Microsoft\Windows\PI\Secure-Boot-Update`" /Enable" -ForegroundColor White
        $stepNum++
    }

    # Known firmware issue
    if ($knownIssueId) {
        Write-Host "  $stepNum. This device has a known firmware issue ($knownIssueId)." -ForegroundColor Yellow
        Write-Host "     Check https://aka.ms/securebootplaybook for details and OEM guidance." -ForegroundColor DarkGray
        $stepNum++
    }

    # Firmware errors
    if ($event1795Count -gt 0) {
        Write-Host "  $stepNum. The device firmware rejected the update ($event1795Count error(s))." -ForegroundColor Yellow
        Write-Host "     Contact your device manufacturer (OEM) for a firmware/BIOS update that" -ForegroundColor DarkGray
        Write-Host "     supports the UEFI CA 2023 certificate." -ForegroundColor DarkGray
        $stepNum++
    }

    # Missing KEK
    if ($missingKEK) {
        Write-Host "  $stepNum. The OEM must supply a PK-signed KEK update for this device model." -ForegroundColor Yellow
        Write-Host "     Contact $oemManufacturerName support and reference the Secure Boot" -ForegroundColor DarkGray
        Write-Host "     certificate update requirements." -ForegroundColor DarkGray
        $stepNum++
    }

    # Update error recorded
    if ($null -ne $uefica2023Error -and -not $rebootPending -and $event1795Count -eq 0 -and -not $missingKEK -and -not $knownIssueId) {
        Write-Host "  $stepNum. An error ($uefica2023Error) was logged. Try running Windows Update" -ForegroundColor Yellow
        Write-Host "     to install the latest servicing stack and Secure Boot updates, then reboot." -ForegroundColor DarkGray
        $stepNum++
    }

    # No events or status at all - update not yet deployed
    if ($null -eq $latestEventId -and $null -eq $uefica2023Status -and $secureBootEnabled -eq $true) {
        Write-Host "  $stepNum. The Secure Boot certificate update does not appear to be deployed yet." -ForegroundColor Yellow
        Write-Host "     Run Windows Update to check for available updates, or verify that the" -ForegroundColor DarkGray
        Write-Host "     update has been approved in your management tool (WSUS/Intune/SCCM)." -ForegroundColor DarkGray
        $stepNum++
    }

    # Catch-all if nothing specific was identified
    if ($stepNum -eq 1) {
        Write-Host "  1. Run Windows Update to install the latest Secure Boot certificate updates." -ForegroundColor Yellow
        Write-Host "  2. Reboot the device after updates are installed." -ForegroundColor Yellow
        Write-Host "  3. Run this script again to verify the update completed." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "  For more information: https://aka.ms/securebootplaybook" -ForegroundColor DarkGray
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

# Exit code: "Updated" is the success value per the playbook

if ($secureBootEnabled -and $uefica2023Status -eq "Updated") {

    exit 0  # Without issue

} else {

    exit 1  # With issue

}
