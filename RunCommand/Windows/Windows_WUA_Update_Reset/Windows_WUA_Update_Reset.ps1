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

# ---- Helpers -----------------------------------------------------------------
$Summary = [ordered]@{
    Services = [ordered]@{
        Stopped      = New-Object System.Collections.Generic.List[string]
        AlreadyStop  = New-Object System.Collections.Generic.List[string]
        StopFailed   = New-Object System.Collections.Generic.List[string]
        Started      = New-Object System.Collections.Generic.List[string]
        AlreadyStart = New-Object System.Collections.Generic.List[string]
        StartFailed  = New-Object System.Collections.Generic.List[string]
    }
    Renamed      = New-Object System.Collections.Generic.List[string]
    RenameFailed = New-Object System.Collections.Generic.List[string]
    DllRegistered = New-Object System.Collections.Generic.List[string]
    DllMissing    = New-Object System.Collections.Generic.List[string]
    DllFailed     = New-Object System.Collections.Generic.List[string]
    LogPath       = $LogPath
}

function Write-Info  ($msg){ Write-Host $msg -ForegroundColor Cyan }
function Write-Warn  ($msg){ Write-Host $msg -ForegroundColor DarkYellow }
function Write-Ok    ($msg){ Write-Host $msg -ForegroundColor Green }
function Write-Err   ($msg){ Write-Host $msg -ForegroundColor Red }

function Stop-ServiceSafe {
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Warn "Service $Name not found (skipping)"; $Summary.Services.StopFailed.Add("$Name (not found)"); return }
    if ($svc.Status -eq 'Stopped') { Write-Info "Service $Name already stopped"; $Summary.Services.AlreadyStop.Add($Name); return }
    try {
        Stop-Service -Name $Name -Force -ErrorAction Stop
        Write-Ok "Stopped $Name"
        $Summary.Services.Stopped.Add($Name)
    } catch {
        Write-Err "Failed to stop $Name : $($_.Exception.Message)"
        $Summary.Services.StopFailed.Add($Name)
    }
}

function Start-ServiceSafe {
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Warn "Service $Name not found (skipping)"; $Summary.Services.StartFailed.Add("$Name (not found)"); return }
    if ($svc.Status -eq 'Running') { Write-Info "Service $Name already running"; $Summary.Services.AlreadyStart.Add($Name); return }
    try {
        Start-Service -Name $Name -ErrorAction Stop
        Write-Ok "Started $Name"
        $Summary.Services.Started.Add($Name)
    } catch {
        Write-Err "Failed to start $Name : $($_.Exception.Message)"
        $Summary.Services.StartFailed.Add($Name)
    }
}

function Rename-WithTimestamp {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { Write-Warn "Path not found; skipping: $Path"; $Summary.RenameFailed.Add("$Path (not found)"); return }
    $parent = Split-Path -Parent $Path
    $leaf   = Split-Path -Leaf   $Path
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $newName = "$leaf.old_$stamp"
    try {
        Rename-Item -Path $Path -NewName $newName -ErrorAction Stop
        $fullNew = Join-Path $parent $newName
        Write-Ok "Renamed: $Path -> $fullNew"
        $Summary.Renamed.Add($fullNew)
    } catch {
        Write-Err "Failed to rename $Path : $($_.Exception.Message)"
        $Summary.RenameFailed.Add($Path)
    }
}

# ---- Main --------------------------------------------------------------------
$ErrorActionPreference = 'Stop'

Write-Host "Stopping Windows Update related services..." -ForegroundColor Yellow
'wuauserv','cryptsvc','bits' | ForEach-Object { Stop-ServiceSafe -Name $_ }

Write-Host "Renaming SoftwareDistribution and Catroot2 folders..." -ForegroundColor Yellow
Rename-WithTimestamp -Path (Join-Path $env:SystemRoot 'SoftwareDistribution')
Rename-WithTimestamp -Path (Join-Path $env:SystemRoot 'System32\catroot2')

Write-Host "Re-registering DLLs..." -ForegroundColor Yellow
$dlls = @(
    'atl.dll','urlmon.dll','mshtml.dll','shdocvw.dll','browseui.dll',
    'jscript.dll','vbscript.dll','scrrun.dll','msxml.dll','msxml3.dll',
    'msxml6.dll','actxprxy.dll','softpub.dll','wintrust.dll','dssenh.dll',
    'rsaenh.dll','gpkcsp.dll','sccbase.dll','slbcsp.dll','cryptdlg.dll',
    'oleaut32.dll','ole32.dll','shell32.dll','initpki.dll','wuapi.dll',
    'wuaueng.dll','wuaueng1.dll','wucltui.dll','wups.dll','wups2.dll',
    'wuweb.dll','qmgr.dll','qmgrprxy.dll','wucltux.dll','muweb.dll',
    'wuwebv.dll','wudriver.dll'
)

foreach ($dll in $dlls) {
    $fullPath = Join-Path "$env:SystemRoot\System32" $dll
    if (-not (Test-Path $fullPath)) {
        Write-Warn "Skipping $dll (not found on this OS)"
        $Summary.DllMissing.Add($dll)
        continue
    }
    try {
        $p = Start-Process -FilePath "$env:SystemRoot\System32\regsvr32.exe" `
                           -ArgumentList "/s `"$fullPath`"" `
                           -PassThru -Wait -WindowStyle Hidden
        if ($p.ExitCode -eq 0) {
            Write-Info "Registered $dll"
            $Summary.DllRegistered.Add($dll)
        } else {
            Write-Err "regsvr32 returned exit code $($p.ExitCode) for $dll"
            $Summary.DllFailed.Add($dll)
        }
    } catch {
        Write-Err "Failed to register $dll : $($_.Exception.Message)"
        $Summary.DllFailed.Add($dll)
    }
}

Write-Host "Restarting services..." -ForegroundColor Yellow
'wuauserv','cryptsvc','bits' | ForEach-Object { Start-ServiceSafe -Name $_ }

# ---- Summary -----------------------------------------------------------------
Write-Host "`n==================== SUMMARY ====================" -ForegroundColor Magenta
Write-Host ("Services stopped        : {0}" -f ($Summary.Services.Stopped -join ', '))
if ($Summary.Services.AlreadyStop.Count -gt 0) {
    Write-Host ("Already stopped         : {0}" -f ($Summary.Services.AlreadyStop -join ', '))
}
if ($Summary.Services.StopFailed.Count -gt 0) {
    Write-Err  ("Stop failed             : {0}" -f ($Summary.Services.StopFailed -join ', '))
}
Write-Host ("Services started        : {0}" -f ($Summary.Services.Started -join ', '))
if ($Summary.Services.AlreadyStart.Count -gt 0) {
    Write-Host ("Already running         : {0}" -f ($Summary.Services.AlreadyStart -join ', '))
}
if ($Summary.Services.StartFailed.Count -gt 0) {
    Write-Err  ("Start failed            : {0}" -f ($Summary.Services.StartFailed -join ', '))
}
Write-Host ("Folders renamed         : {0}" -f ($(if($Summary.Renamed.Count){$Summary.Renamed -join '; '}else{'None'})))
if ($Summary.RenameFailed.Count -gt 0) {
    Write-Err  ("Rename failed           : {0}" -f ($Summary.RenameFailed -join '; '))
}
Write-Host ("DLLs registered (ok)    : {0}" -f $Summary.DllRegistered.Count)
Write-Host ("DLLs missing (skipped)  : {0}" -f $Summary.DllMissing.Count)
if ($Summary.DllFailed.Count -gt 0) {
    Write-Err  ("DLLs failed             : {0}" -f ($Summary.DllFailed -join ', '))
}
Write-Host "=================================================" -ForegroundColor Magenta

Write-Host "`nProcess complete. Windows Update components reset." -ForegroundColor Green
Write-Host "`nOptional: To check update history, run:" -ForegroundColor Magenta
Write-Host "  dism /online /get-packages /format:table" -ForegroundColor White
Write-Host "  Get-HotFix" -ForegroundColor White

Write-Host "`r`nAdditional Information: https://aka.ms/AzVMWindowsUpdateReset" -ForegroundColor Cyan
Write-Host "`r`nScript completed successfully." -ForegroundColor Cyan
