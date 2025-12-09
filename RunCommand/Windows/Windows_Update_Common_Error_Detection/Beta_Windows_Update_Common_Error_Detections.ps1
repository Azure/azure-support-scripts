
param(
    [Parameter(Mandatory = $false)]
    [int]$StartDays = 30  # Default is 30 days if not provided
)

# Display description on screen
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "This script scans CBS logs for known Windows update errors" -ForegroundColor Cyan
Write-Host "It counts occurrences of each error code and provides a" -ForegroundColor Cyan
Write-Host "summary at the end. If any errors are found and a remediation exists, " -ForegroundColor Cyan
Write-Host "a link to Microsoft documentation is displayed." -ForegroundColor Cyan

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

# Define error codes
$errors = @{
    "Errors Found" = @{
        
"0x80070002" = "ERROR_FILE_NOT_FOUND"
"0x80070490" = "ERROR_NOT_FOUND"
"0x800F0805" = "CBS_E_INVALID_PACKAGE"
"0x80004005" = "E_FAIL"
"0x80070422" = "ERROR_SERVICE_DISABLED"
"0x80010108" = "RPC_E_DISCONNECTED"
"0x8007045B" = "ERROR_SHUTDOWN_IN_PROGRESS"
"0x8007000D" = "ERROR_INVALID_DATA"
"0x80070020" = "ERROR_SHARING_VIOLATION"
"0x80070005" = "ERROR_ACCESS_DENIED"
"0x800F081F" = "CBS_E_SOURCE_MISSING"
"0x80004004" = "E_ABORT"
"0x800F0831" = "CBS_E_STORE_CORRUPTION"
"0x800F0906" = "CBS_E_DOWNLOAD_FAILURE"
"0x8000FFFF" = "E_UNEXPECTED"
"0x80073712" = "ERROR_SXS_COMPONENT_STORE_CORRUPT"
"0x80040154" = "REGDB_E_CLASSNOTREG"
"0x800F0983" = "PSFX_E_MATCHING_COMPONENT_MISSING"
"0x80070BC9" = "ERROR_FAIL_REBOOT_REQUIRED"
"0x800706BA" = "RPC_S_SERVER_UNAVAILABLE"
"0x80070057" = "ERROR_INVALID_PARAMETER"
"0x80070003" = "ERROR_PATH_NOT_FOUND"
"0x800F0922" = "CBS_E_INSTALLERS_FAILED"
"0x8024002E" = "WU_E_UNEXPECTED"
"0x80073701" = "ERROR_SXS_ASSEMBLY_MISSING"
"0x8007007E" = "ERROR_MOD_NOT_FOUND"
"0x800736B3" = "ERROR_SXS_ASSEMBLY_NOT_FOUND"
"0x80070643" = "ERROR_INSTALL_FAILURE"
"0x800F0823" = "CBS_E_NEW_SERVICING_STACK_REQUIRED"
"0x800706BE" = "RPC_S_CALL_FAILED"
"0x8007000E" = "ERROR_OUTOFMEMORY"
"0x80080005" = "CO_E_SERVER_EXEC_FAILURE"
"0x800F0991" = "PSFX_E_MISSING_PAYLOAD_FILE"
"0x800F0905" = "CBS_E_INVALID_XML"
"0x80070013" = "ERROR_WRITE_PROTECT"
"0x80072F8F" = "ERROR_INTERNET_SECURE_FAILURE"
"0x800719E4" = "ERROR_CLUSTER_NODE_ALREADY_UP"
"0x800706C6" = "RPC_S_CALL_FAILED_DNE"
"0x80240438" = "WU_E_PT_HTTP_STATUS_REQUEST_TIMEOUT"
"0x800F0982" = "PSFX_E_MATCHING_COMPONENT_NOT_FOUND"
"0x8024001E" = "WU_E_SERVICE_STOP"
"0x800F0920" = "CBS_E_INVALID_DRIVE"
"D0000017"    = "STATUS_NO_MEMORY"
"0x8024401C" = "WU_E_PT_HTTP_STATUS_REQUEST_TIMEOUT"
"0x80070070" = "ERROR_DISK_FULL"
"0x800F0986" = "PSFX_E_APPLY_FORWARD_DELTA_FAILED"
"0x80072EE2" = "ERROR_INTERNET_TIMEOUT"
"0x800705AF" = "ERROR_NO_SYSTEM_RESOURCES"
"0x8024402C" = "WU_E_PT_HTTP_STATUS_BAD_REQUEST"
"0x800F0900" = "CBS_E_XML_PARSER_FAILURE"
"0x8007007B" = "ERROR_INVALID_NAME"
"0x800F0902" = "CBS_E_XML_PARSER_FAILURE"
"0x8024500C" = "WU_E_PT_SOAPCLIENT_SEND"
"0x80070776" = "ERROR_INVALID_GROUP"
"0x800F0819" = "CBS_E_INVALID_DRIVE"
"0x80240008" = "WU_E_ITEMNOTFOUND"
"0x80070008" = "ERROR_NOT_ENOUGH_MEMORY"
"0x800701D9" = "ERROR_CLUSTER_INVALID_NODE"
"0x800703FB" = "ERROR_INVALID_OPERATION"
"0x80244007" = "WU_E_PT_HTTP_STATUS_DENIED"
"0x800F0985" = "PSFX_E_APPLY_REVERSE_DELTA_FAILED"
"0x800705B4" = "ERROR_TIMEOUT"
"0x800F080D" = "CBS_E_MANIFEST_INVALID"
"0x800F0988" = "PSFX_E_INVALID_DELTA_COMBINATION"
"0x80244022" = "WU_E_PT_HTTP_STATUS_SERVICE_UNAVAIL"
"0x800705AA" = "ERROR_NO_SYSTEM_RESOURCES"
"0x80244017" = "WU_E_PT_HTTP_STATUS_NOT_FOUND"
"0x80004002" = "E_NOINTERFACE"
"0x800F080A" = "CBS_E_REQUIRES_ELEVATION"

        }
}

# Map error codes to Microsoft Learn (Windows Update-specific) RCA/mitigation docs
$errorLinks = @{
    "0x80070002" = "https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/troubleshoot-windows-update-download-errors?context=%2Ftroubleshoot%2Fazure%2Fvirtual-machines%2Fwindows%2Fcontext%2Fcontext"
    "0x80070490" = "https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/troubleshoot-windows-update-download-errors?context=%2Ftroubleshoot%2Fazure%2Fvirtual-machines%2Fwindows%2Fcontext%2Fcontext"
    "0x800F0805" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800f0805"
    "0x80004005" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#common-hresult-values"
    "0x80070422" = "https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/troubleshoot-windows-update-download-errors?context=%2Ftroubleshoot%2Fazure%2Fvirtual-machines%2Fwindows%2Fcontext%2Fcontext"
    "0x800F081F" = "https://learn.microsoft.com/en-us/troubleshoot/windows-server/deployment/error-0x800f081f"
    "0x800F0831" = "https://learn.microsoft.com/en-us/troubleshoot/windows-server/deployment/error-0x800f0831"
    "0x800F0906" = "https://learn.microsoft.com/en-us/troubleshoot/windows-server/deployment/error-0x800f0906"
    "0x8000FFFF" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#common-hresult-values"
    "0x80073712" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80073712"
    "0x800F0983" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#psfx-errors"
    "0x80070BC9" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80070bc9"
    "0x800706BA" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#wu_e_endpoint-and-transport-errors"
    "0x80070057" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80070057"
    "0x80070003" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80070003"
    "0x800F0922" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800f0922"
    "0x8024002E" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-client-errors-wu_e"
    "0x80073701" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80073701"
    "0x8007007E" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x8007007e"
    "0x800736B3" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800736b3"
    "0x80070643" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80070643"
    "0x800F0823" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800f0823"
    "0x800706BE" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#wu_e_endpoint-and-transport-errors"
    "0x8007000E" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x8007000e"
    "0x80080005" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#common-hresult-values"
    "0x800F0991" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#psfx-errors"
    "0x800F0905" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800f0905"
    "0x80070013" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80070013"
    "0x80072F8F" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80072f8f"
    "0x800706C6" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#wu_e_endpoint-and-transport-errors"
    "0x80240438" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-agent-errors-wu_e_pt"
    "0x800F0982" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#psfx-errors"
    "0x8024001E" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-client-errors-wu_e"
    "0x800F0920" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800f0920"
    "0x8024401C" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-agent-errors-wu_e_pt"
    "0x80070070" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80070070"
    "0x800F0986" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#psfx-errors"
    "0x80072EE2" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80072ee2"
    "0x800705AF" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800705af"
    "0x8024402C" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-agent-errors-wu_e_pt"
    "0x800F0900" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800f0900"
    "0x8007007B" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x8007007b"
    "0x800F0902" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800f0902"
    "0x8024500C" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-agent-errors-wu_e_pt"
    "0x80240008" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-client-errors-wu_e"
    "0x80070008" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x80070008"
    "0x80244007" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-agent-errors-wu_e_pt"
    "0x800F0985" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#psfx-errors"
    "0x800705B4" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800705b4"
    "0x800F080D" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800f080d"
    "0x800F0988" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#psfx-errors"
    "0x80244022" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-agent-errors-wu_e_pt"
    "0x80244017" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#windows-update-agent-errors-wu_e_pt"
    "0x800F080A" = "https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference#0x800f080a"
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
        $link = if ($errorLinks.ContainsKey($code)) { $errorLinks[$code] } else { $null }
        if ($link) {
            Write-Host "$code : $($errorSummary[$code]) occurrences - $link" -ForegroundColor Yellow
        } else {
            Write-Host "$code : $($errorSummary[$code]) occurrences" -ForegroundColor Yellow
        }
    }
    Write-Host "`nFor remediation guidance, visit: https://aka.ms/AzVmIPUValidation" -ForegroundColor Green
} else {
    Write-Host "No matching errors found in the scanned logs." -ForegroundColor Gray
}

Write-Host "`r`nAdditional Information: https://aka.ms/AzVmIPUValidation" -ForegroundColor Cyan
Write-Host "`r`nScript completed successfully."
