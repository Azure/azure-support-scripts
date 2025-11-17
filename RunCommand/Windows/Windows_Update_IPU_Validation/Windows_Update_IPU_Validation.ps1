param(
    [Parameter(Mandatory = $false)]
    [int]$StartDays = 30  # Default is 30 days if not provided
)

# Display description on screen
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "This script scans CBS logs for known Windows servicing error" -ForegroundColor Cyan
Write-Host "codes that may require an In-Place Upgrade (IPU) or repair." -ForegroundColor Cyan
Write-Host "It counts occurrences of each error code and provides a" -ForegroundColor Cyan
Write-Host "summary at the end. If any errors are found, a remediation" -ForegroundColor Cyan
Write-Host "link to Microsoft documentation is displayed." -ForegroundColor Cyan
Write-Host "Reference: https://aka.ms/AzVmIPUValidation" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------`n" -ForegroundColor Cyan

<#
    Reset Windows Update Components with Logging & Summary
    ------------------------------------------------------
    - Stops: wuauserv, cryptsvc, bits
    - Renames: %SystemRoot%\SoftwareDistribution, %SystemRoot%\System32\catroot2 (timestamped)
    - Re-registers core update-related DLLs (skips any not present)
    - Restarts services
    - Summary at the end
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

# ---- Main Logic --------------------------------------------------------------

# Calculate the date X days from now
$StartDate = (Get-Date).AddDays(-$StartDays)
Write-Host "Start date: $StartDate" -ForegroundColor Cyan
Write-Host "`nScanning for errors, please wait..." -ForegroundColor Yellow

# Define categorized error codes
$errors = @{
    "Critical" = @{
        "0x800F0831" = "CBS_E_STORE_CORRUPTION"
        "0x800F081F" = "CBS_E_SOURCE_MISSING"
        "0x800F0900" = "CBS_E_XML_PARSER_FAILURE"
        "0x800F0830" = "CBS_E_IMAGE_UNSERVICEABLE"
        "0x800F0911" = "CBS_E_SOURCE_MODIFIED"
        "0x800F0985" = "PSFX_E_APPLY_REVERSE_DELTA_FAILED"
        "0x800F0986" = "PSFX_E_APPLY_FORWARD_DELTA_FAILED"
        "0x800F0987" = "PSFX_E_NULL_DELTA_HYDRATION_FAILED"
        "0x800F0989" = "PSFX_E_REVERSE_DELTA_MISSING"
        "0x800F0982" = "PSFX_E_MATCHING_COMPONENT_NOT_FOUND"
        "0x800F0984" = "PSFX_E_MATCHING_BINARY_MISSING"
        "0x800F0988" = "PSFX_E_INVALID_DELTA_COMBINATION"
        "0x800F0991" = "PSFX_E_MISSING_PAYLOAD_FILE"
        "0x800F0805" = "CBS_E_INVALID_PACKAGE"
    }
    "High" = @{
        "0x80073701" = "ERROR_SXS_ASSEMBLY_MISSING"
        "0x800736B3" = "ERROR_SXS_ASSEMBLY_NOT_FOUND"
        "0x800F080D" = "CBS_E_MANIFEST_INVALID_ITEM"
        "0x80071AB1" = "ERROR_LOG_GROWTH_FAILED"
    }
    "Medium" = @{
        "0x8007371B" = "ERROR_SXS_TRANSACTION_CLOSURE_INCOMPLETE"
        "0x800F0905" = "CBS_E_NO_ACTIVE_EDITION"
        "0x800F0904" = "CBS_E_MORE_THAN_ONE_ACTIVE_EDITION"
        "0x80242016" = "WU_E_UH_POSTREBOOTUNEXPECTEDSTATE"
    }
    "Low" = @{
        "0x800F0922" = "CBS_E_INSTALLERS_FAILED"
    }
}

# Initialize counters
$errorCount = 0
$errorSummary = @{}

# Get all log files including .zip
$logFiles = Get-ChildItem "C:\Windows\Logs\CBS\" -Recurse -Include *.log, *.zip

foreach ($file in $logFiles) {
    if ($file.LastWriteTime -ge $StartDate) {
        if ($file.Extension -eq ".zip") {
            $tempDir = Join-Path $env:TEMP "CBSZipExtract"
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Expand-Archive $file.FullName -DestinationPath $tempDir -Force
            $logContents = Get-ChildItem $tempDir -Recurse -Include *.log | Get-Content
        } else {
            $logContents = Get-Content $file.FullName
        }

        foreach ($severity in $errors.Keys) {
            foreach ($code in $errors[$severity].Keys) {
                $matches = $logContents | Select-String $code
                if ($matches) {
                    $errorCount += $matches.Count
                    if ($errorSummary.ContainsKey($code)) {
                        $errorSummary[$code] += $matches.Count
                    } else {
                        $errorSummary[$code] = $matches.Count
                    }
                }
            }
        }

        if ($file.Extension -eq ".zip") {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Show summary
Write-Host "`nTotal Errors Found in last $StartDays days: $errorCount" -ForegroundColor Magenta

if ($errorCount -gt 0) {
    Write-Host "`nError Breakdown:" -ForegroundColor Cyan
    foreach ($code in $errorSummary.Keys) {
        Write-Host "$code : $($errorSummary[$code]) occurrences" -ForegroundColor Yellow
    }
    Write-Host "`nFor remediation guidance, visit: https://aka.ms/AzVmIPUValidation" -ForegroundColor Green
} else {
    Write-Host "No matching errors found in the scanned logs." -ForegroundColor Gray
}

Write-Host "`r`nAdditional Information: https://aka.ms/AzVmIPUValidation" -ForegroundColor Cyan
Write-Host "`r`nScript completed successfully." -ForegroundColor Cyan
