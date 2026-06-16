[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OfflineWindowsRoot,

    [Parameter(Mandatory = $false)]
    [string]$Disk,

    [Parameter(Mandatory = $false)]
    [string]$TssPath,

    [Parameter(Mandatory = $false)]
    [string]$TssCollectLog,

    [Parameter(Mandatory = $false)]
    [string[]]$TssArguments,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeRegistryHives,

    [Parameter(Mandatory = $false)]
    [switch]$ZipOutput,

    [Parameter(Mandatory = $false)]
    [switch]$NoAcceptEula,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$msDataRoot = "C:\MS_DATA"
$outputRoot = Join-Path $msDataRoot "TSS_PERF_OFFLINE"

function Ensure-DiskReady {
    param(
        [int]$DiskNumber
    )

    $targetDisk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
    if (-not $targetDisk) {
        throw "Disk number '$DiskNumber' was not found."
    }

    if ($targetDisk.OperationalStatus -eq 'Offline' -or $targetDisk.IsOffline) {
        Write-Host "[disk] Bringing disk $DiskNumber online" -ForegroundColor Yellow
        try {
            Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction Stop
            Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction Stop
        }
        catch {
            if ($_ -match 'Access Denied|40001') {
                throw "Access denied bringing disk $DiskNumber online. The disk may be in use by another process or VM."
            }
            throw "Failed to bring disk $DiskNumber online: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 2
        $targetDisk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
    }
    elseif ($targetDisk.IsReadOnly) {
        Write-Host "[disk] Clearing read-only on disk $DiskNumber" -ForegroundColor Yellow
        try {
            Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction Stop
        }
        catch {
            if ($_ -match 'Access Denied|40001') {
                throw "Access denied clearing read-only on disk $DiskNumber. The disk may be in use by another process or VM."
            }
            throw "Failed to clear read-only flag on disk ${DiskNumber}: $($_.Exception.Message)"
        }
        $targetDisk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
    }

    if (-not $targetDisk -or $targetDisk.IsOffline -or $targetDisk.IsReadOnly) {
        throw "Disk $DiskNumber is not ready (offline or read-only) after remediation attempt."
    }
}

function Resolve-OfflineWindowsRoot {
    param(
        [string]$RequestedPath,
        [string]$DiskSpecifier
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath) -and -not [string]::IsNullOrWhiteSpace($DiskSpecifier)) {
        throw "Use either -OfflineWindowsRoot or -Disk, not both."
    }

    if (-not [string]::IsNullOrWhiteSpace($DiskSpecifier)) {
        $normalizedDisk = $DiskSpecifier.Trim().ToUpperInvariant()

        if ($normalizedDisk -match "^\d+$") {
            $diskNumber = [int]$normalizedDisk
            Ensure-DiskReady -DiskNumber $diskNumber

            $volumes = @(Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue |
                Get-Volume -ErrorAction SilentlyContinue |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.DriveLetter) })

            if ($volumes.Count -eq 0) {
                throw "Disk number '$diskNumber' has no mounted volume with a drive letter."
            }

            $candidates = @()
            foreach ($volume in $volumes) {
                $candidate = "$($volume.DriveLetter):\Windows"
                if (Test-Path -LiteralPath (Join-Path $candidate "System32\config\SYSTEM")) {
                    $candidates += $candidate.TrimEnd("\\")
                }
            }

            if ($candidates.Count -eq 0) {
                throw "Disk number '$diskNumber' does not contain a Windows OS volume (missing Windows\\System32\\config\\SYSTEM)."
            }

            if ($candidates.Count -gt 1) {
                Write-Warning "Multiple Windows roots found on disk ${diskNumber}: $($candidates -join ', '). Using: $($candidates[0])"
            }

            return $candidates[0]
        }

        if ($normalizedDisk -match "^[A-Z]$") {
            $normalizedDisk = "${normalizedDisk}:"
        }
        elseif ($normalizedDisk -match "^[A-Z]:\\$") {
            $normalizedDisk = $normalizedDisk.Substring(0, 2)
        }

        if ($normalizedDisk -notmatch "^[A-Z]:$") {
            throw "-Disk must be a disk number (for example '2') or drive letter like 'E', 'E:' or 'E:\\'. Provided: $DiskSpecifier"
        }

        $driveLetter = $normalizedDisk.Substring(0, 1)
        $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $partition) {
            throw "Drive '$normalizedDisk' was not found."
        }
        Ensure-DiskReady -DiskNumber $partition.DiskNumber

        $diskRoot = "$normalizedDisk\\"
        $candidate = Join-Path $diskRoot "Windows"

        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "The specified disk does not contain a Windows folder: $candidate"
        }

        if (-not (Test-Path -LiteralPath (Join-Path $candidate "System32\config\SYSTEM"))) {
            throw "Disk '$normalizedDisk' does not appear to be a Windows OS disk (missing System32\\config\\SYSTEM under $candidate)."
        }

        return $candidate.TrimEnd("\\")
    }

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $normalized = $RequestedPath.TrimEnd("\\")
        if (-not (Test-Path -LiteralPath $normalized)) {
            throw "OfflineWindowsRoot path does not exist: $normalized"
        }

        if (-not (Test-Path -LiteralPath (Join-Path $normalized "System32\config\SYSTEM"))) {
            throw "Path does not look like a Windows directory (missing System32\\config\\SYSTEM): $normalized"
        }

        return $normalized
    }

$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match "^[A-Z]:\\$" }
$candidates = New-Object System.Collections.Generic.List[string]
$localWindows = (Resolve-Path -LiteralPath $env:windir).Path

foreach ($drive in $drives) {
    $candidate = Join-Path $drive.Root "Windows"
    if ($candidate -ieq $localWindows) {
        continue
    }

    $systemHive = Join-Path $candidate "System32\config\SYSTEM"
    if (Test-Path -LiteralPath $systemHive) {
        $candidates.Add($candidate) | Out-Null
    }
}

if ($candidates.Count -eq 0) {
    throw "No offline Windows installation was auto-detected (local Windows is ignored). Provide -OfflineWindowsRoot explicitly."
}

if ($candidates.Count -gt 1) {
    $first = $candidates[0]
    Write-Warning "Multiple offline Windows roots detected: $($candidates -join ', '). Using: $first"
    return $first
}

return $candidates[0]
}

function Copy-IfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Host "[skip] Missing: $Source" -ForegroundColor DarkYellow
        return
    }

    $destParent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destParent)) {
        New-Item -Path $destParent -ItemType Directory -Force | Out-Null
    }

    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force -ErrorAction Stop
        Write-Host "[copy] $Source -> $Destination" -ForegroundColor DarkCyan
    }
    catch {
        Write-Warning "[skip] Failed to copy $Source. Reason: $($_.Exception.Message)"
    }
}

function Run-OptionalTss {
    param(
        [string]$Path,
        [string[]]$Arguments,
        [switch]$AutoAcceptEula
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "TSS script not found: $Path"
    }

    $tokens = @()
    if ($Arguments) {
        foreach ($arg in $Arguments) {
            if (-not [string]::IsNullOrWhiteSpace($arg)) {
                $tokens += $arg.Trim()
            }
        }
    }

    if ($AutoAcceptEula -and -not ($tokens -contains "-AcceptEula")) {
        $tokens += "-AcceptEula"
    }

    # Parse the flat token list into a parameter hashtable so TSS is invoked by
    # named parameters. Array splatting (& $Path @array) does NOT reliably
    # resolve TSS's parameter sets and raises AmbiguousParameterSet; hashtable
    # splatting binds parameters by name exactly like an interactive command
    # line and resolves the parameter set correctly.
    $tssParams = [ordered]@{}
    $i = 0
    while ($i -lt $tokens.Count) {
        $tok = $tokens[$i]
        if ($tok -like "-*") {
            $name = $tok.TrimStart("-")
            if (($i + 1) -lt $tokens.Count -and ($tokens[$i + 1] -notlike "-*")) {
                $tssParams[$name] = $tokens[$i + 1]
                $i += 2
            }
            else {
                $tssParams[$name] = $true
                $i += 1
            }
        }
        else {
            $i += 1
        }
    }

    Write-Host ("[tss] Starting TSS: {0} {1}" -f $Path, ($tokens -join " ")) -ForegroundColor Yellow
    & $Path @tssParams
    Write-Host "[tss] Completed TSS collection." -ForegroundColor Green
}

$resolvedWindowsRoot = Resolve-OfflineWindowsRoot -RequestedPath $OfflineWindowsRoot -DiskSpecifier $Disk
$offlineRoot = Split-Path -Parent $resolvedWindowsRoot
$offlineRoot = if ([string]::IsNullOrWhiteSpace($offlineRoot)) { Split-Path -Qualifier $resolvedWindowsRoot } else { $offlineRoot }
$timeStamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"

if (-not (Test-Path -LiteralPath $msDataRoot)) {
    New-Item -Path $msDataRoot -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $outputRoot)) {
    New-Item -Path $outputRoot -ItemType Directory -Force | Out-Null
}

$outputFolder = Join-Path $outputRoot "offline-tss-wrapper-$timeStamp"

if ((Test-Path -LiteralPath $outputFolder) -and -not $Force) {
    throw "Output folder already exists: $outputFolder. Use -Force to overwrite."
}

New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null

Write-Host "Offline Windows root : $resolvedWindowsRoot" -ForegroundColor Green
Write-Host "Offline disk root    : $offlineRoot" -ForegroundColor Green
Write-Host "MS_DATA root         : $msDataRoot" -ForegroundColor Green
Write-Host "Output root          : $outputRoot" -ForegroundColor Green
Write-Host "Output folder        : $outputFolder" -ForegroundColor Green

# Collect a practical offline bundle aligned with Windows Update / DnD troubleshooting.
$pathsToCollect = @(
    @{ Rel = "Windows\System32\winevt\Logs"; Dest = "offline\winevt\Logs" },
    @{ Rel = "Windows\Logs\CBS"; Dest = "offline\Windows\Logs\CBS" },
    @{ Rel = "Windows\Logs\DISM"; Dest = "offline\Windows\Logs\DISM" },
    @{ Rel = "Windows\Panther"; Dest = "offline\Windows\Panther" },
    @{ Rel = "Windows\INF\setupapi.dev.log"; Dest = "offline\Windows\INF\setupapi.dev.log" },
    @{ Rel = "Windows\INF\setupapi.setup.log"; Dest = "offline\Windows\INF\setupapi.setup.log" },
    @{ Rel = "Windows\SoftwareDistribution\ReportingEvents.log"; Dest = "offline\Windows\SoftwareDistribution\ReportingEvents.log" },
    @{ Rel = "Windows\System32\catroot2"; Dest = "offline\Windows\System32\catroot2" },
    @{ Rel = "Windows\Minidump"; Dest = "offline\Windows\Minidump" },
    @{ Rel = "Windows\MEMORY.DMP"; Dest = "offline\Windows\MEMORY.DMP" },
    @{ Rel = "ProgramData\USOShared\Logs"; Dest = "offline\ProgramData\USOShared\Logs" }
)

foreach ($item in $pathsToCollect) {
    $sourcePath = Join-Path $offlineRoot $item.Rel
    $destPath = Join-Path $outputFolder $item.Dest
    Copy-IfPresent -Source $sourcePath -Destination $destPath
}

if ($IncludeRegistryHives) {
    $hiveFolder = Join-Path $resolvedWindowsRoot "System32\config"
    $hives = @("SYSTEM", "SOFTWARE", "SAM", "SECURITY", "DEFAULT", "COMPONENTS")
    foreach ($hive in $hives) {
        $sourceHive = Join-Path $hiveFolder $hive
        $destHive = Join-Path $outputFolder ("offline\registry\{0}" -f $hive)
        Copy-IfPresent -Source $sourceHive -Destination $destHive
    }
}

if ([string]::IsNullOrWhiteSpace($TssPath)) {
    $candidate = Join-Path $PSScriptRoot "TSS\TSS.ps1"
    Write-Host "[tss] -TssPath not provided. Checking default path: $candidate" -ForegroundColor Yellow

    if (Test-Path -LiteralPath $candidate) {
        $TssPath = (Resolve-Path $candidate).Path
        Write-Host "[tss] Found default TSS script: $TssPath" -ForegroundColor Green
    }
    else {
        Write-Host "[tss] Default TSS script was not found: $candidate" -ForegroundColor Red
        Write-Host "[tss] Expected layout:" -ForegroundColor Yellow
        Write-Host "       $PSScriptRoot" -ForegroundColor Yellow
        Write-Host "       $PSScriptRoot\TSS\TSS.ps1" -ForegroundColor Yellow
        Write-Host "[tss] Action: unzip the TSS folder in the same directory as this wrapper, or provide -TssPath explicitly." -ForegroundColor Yellow
        throw "-TssPath was not provided and wrapper-local default was not found: $candidate"
    }
}

$effectiveTssArgs = @()
if ($TssArguments -and $TssArguments.Count -gt 0) {
    $effectiveTssArgs = $TssArguments
}
elseif (-not [string]::IsNullOrWhiteSpace($TssCollectLog)) {
    $effectiveTssArgs = @("-CollectLog", $TssCollectLog)
}
else {
    $effectiveTssArgs = @("-SDP", "Setup")
}

Run-OptionalTss -Path $TssPath -Arguments $effectiveTssArgs -AutoAcceptEula:(-not $NoAcceptEula)

if ($ZipOutput) {
    $zipPath = "$outputFolder.zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $outputFolder "*") -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "Zip created: $zipPath" -ForegroundColor Green
}

Write-Host "Offline rescue collection complete." -ForegroundColor Green
Write-Host "Data location: $outputRoot" -ForegroundColor Green
Write-Host "Bundle path: $outputFolder" -ForegroundColor Green
