
<#
DISCLAIMER
    The sample script is provided AS IS without warranty of any kind.
    Microsoft disclaims all implied warranties, including, without limitation,
    any implied warranties of merchantability or fitness for a particular purpose.
    The entire risk arising out of the use or performance of this script remains with you.
    In no event shall Microsoft, its authors, or anyone else involved in the creation,
    production, or delivery of the script be liable for any damages whatsoever
    (including, without limitation, damages for loss of business profits,
    business interruption, loss of business information, or other pecuniary loss)
    arising out of the use of or inability to use the script,
    even if Microsoft has been advised of the possibility of such damages.

.SYNOPSIS
    Resets Windows Update components by stopping services, renaming folders,
    re-registering DLLs, and restarting services.
	Version: 1.0 (Modified by Copilot for enhanced messaging)

.DESCRIPTION
    This script performs a full reset of Windows Update components on Windows systems.
    It stops related services, renames SoftwareDistribution and Catroot2 folders,
    re-registers core DLLs, and restarts services to restore update functionality.
    Useful for troubleshooting update failures.

.NOTES
    Requires administrator privileges.
    Tested on Windows Server 2016 and later, and Windows 10/11.

.EXAMPLE
    Run as administrator:
    PS> .\Reset-WindowsUpdateComponents.ps1
#>

If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

Write-Host "Stopping Windows Update related services..." -ForegroundColor Yellow

Stop-Service -Name wuauserv -Force
Stop-Service -Name cryptsvc -Force
Stop-Service -Name bits -Force
 
Write-Host "Renaming SoftwareDistribution and Catroot2 folders..." -ForegroundColor Yellow

Rename-Item -Path "$env:SystemRoot\SoftwareDistribution" -NewName "SoftwareDistribution.old" -ErrorAction SilentlyContinue
Rename-Item -Path "$env:SystemRoot\System32\catroot2" -NewName "catroot2.old" -ErrorAction SilentlyContinue
 
Write-Host "Re-registering DLLs..." -ForegroundColor Yellow

$dlls = @(
    "atl.dll","urlmon.dll","mshtml.dll","shdocvw.dll","browseui.dll",
    "jscript.dll","vbscript.dll","scrrun.dll","msxml.dll","msxml3.dll",
    "msxml6.dll","actxprxy.dll","softpub.dll","wintrust.dll","dssenh.dll",
    "rsaenh.dll","gpkcsp.dll","sccbase.dll","slbcsp.dll","cryptdlg.dll",
    "oleaut32.dll","ole32.dll","shell32.dll","initpki.dll","wuapi.dll",
    "wuaueng.dll","wuaueng1.dll","wucltui.dll","wups.dll","wups2.dll",
    "wuweb.dll","qmgr.dll","qmgrprxy.dll","wucltux.dll","muweb.dll",
    "wuwebv.dll","wudriver.dll"
)
 
foreach ($dll in $dlls) {
    $fullPath = Join-Path "$env:SystemRoot\System32" $dll
    if (Test-Path $fullPath) {

    Write-Host "Registering $dll..." -ForegroundColor Cyan
& "$env:SystemRoot\System32\regsvr32.exe" /s $fullPath

    } else {

        Write-Host "Skipping $dll (not found on this OS)" -ForegroundColor DarkYellow

    }

}
 
Write-Host "Restarting services..." -ForegroundColor Yellow

Start-Service -Name wuauserv
Start-Service -Name cryptsvc
Start-Service -Name bits
 
Write-Host "Process complete. Windows Update components reset." -ForegroundColor Green
Write-Host "`nOptional: To check update history, run the following commands:" -ForegroundColor Magenta
Write-Host "  dism /online /get-packages /format:table" -ForegroundColor White
Write-Host "  Get-HotFix" -ForegroundColor White
 