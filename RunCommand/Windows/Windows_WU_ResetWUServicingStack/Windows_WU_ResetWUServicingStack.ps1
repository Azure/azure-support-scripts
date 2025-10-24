# Requires running as Administrator
 
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
 