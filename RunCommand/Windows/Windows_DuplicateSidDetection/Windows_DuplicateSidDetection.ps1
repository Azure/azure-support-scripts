# Detect duplicate SID indicators in netsetup.log using dynamic Windows folder path
# Author: Enterprise Copilot
 
# Get the Windows directory dynamically
# $windowsDir = $env:SystemRoot
# $logPath = Join-Path $windowsDir "debug\netsetup.log"

# Hacklocal
$windowsDir = $env:SystemRoot
$logPath = ".\netsetup.log"
 
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
    Write-Host "https://learn.microsoft.com/en-us/troubleshoot/windows-server/identity/machine-account-duplicate-sid"
} else {
    Write-Host "`nSummary: No duplicate SID indicators found."
}