<# 
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

    For more details, see: https://learn.microsoft.com/troubleshoot/windows-server/identity/machine-account-duplicate-sid

.SYNOPSIS
    Detects duplicate SID indicators in netsetup.log on Windows systems.

.DESCRIPTION
    This script performs the following checks:
    - Locates the netsetup.log file in the Windows debug folder
    - Searches for patterns indicating duplicate SID or machine account issues
    - Provides a summary and relevant Microsoft documentation links

.NOTES
    Requires access to %SystemRoot%\debug\netsetup.log.

.EXAMPLE
    Run as administrator:
    PS> .\Windows_DuplicateSID_Validation.ps1
#>

# Get the Windows directory dynamically
$windowsDir = $env:SystemRoot
$logPath = Join-Path $windowsDir "debug\netsetup.log"
 
# Verify the log file exists
if (-Not (Test-Path $logPath)) {
    Write-Host "netsetup.log not found at $logPath"
    exit
}
 
# Define regex patterns
$patterns = @(
    "(NetpGetComputerObjectDn).*\(Account already exists\)",
    "(NetpManageMachineAccountWithSid: NetUserAdd).*\(failed: 0x8b0\)"
)
 
# Read the log file and search for matches
$logContent = Get-Content -Path $logPath
$issueDetected = $false
 
foreach ($pattern in $patterns) {
    $matches = $logContent | Select-String -Pattern $pattern
    if ($matches) {
        Write-Host "`nPattern Found: $pattern"
        $matches | ForEach-Object { Write-Host $_.Line }
        $issueDetected = $true
    } else {
        Write-Host "`nPattern Not Found: $pattern"
    }
}
 
# Summarize if any issue detected
if ($issueDetected) {
    Write-Host "`nSummary: Duplicate SID or machine account issue detected in netsetup.log."
    Write-Host "Refer to Microsoft documentation for resolution:"
    Write-Host "https://learn.microsoft.com/troubleshoot/windows-server/identity/machine-account-duplicate-sid"
} else {
    Write-Host "`nSummary: No duplicate SID indicators found."
}