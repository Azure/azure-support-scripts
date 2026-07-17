[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$OfflineWindowsRoot,

    [Parameter(Mandatory = $false)]
    [string]$Disk,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeCredentialHives,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeComponentsHive,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSoftwareDistribution,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeMemoryDump,

    [Parameter(Mandatory = $false)]
    [switch]$ZipOutput,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $msDataRoot = "C:\MS_DATA"
    $outputRoot = Join-Path $msDataRoot "TSS_PERF_OFFLINE"
}
else {
    $outputRoot = $OutputPath
}

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
        [string]$Destination,

        [Parameter(Mandatory = $false)]
        [string]$Activity = "Collecting offline files",

        [Parameter(Mandatory = $false)]
        [int]$ProgressId = 1
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Host "[skip] Missing: $Source" -ForegroundColor DarkYellow
        $script:manifestEntries += @{
            Source = $Source
            Destination = $Destination
            Status = "Missing"
            SizeBytes = 0
            SHA256 = "N/A"
        }
        return
    }

    # Calculate size for progress reporting
    $sourceItem = Get-Item -LiteralPath $Source -ErrorAction SilentlyContinue
    $sizeBytes = 0
    $sizeMB = 0

    if ($sourceItem) {
        if ($sourceItem.PSIsContainer) {
            $sizeBytes = (Get-ChildItem -LiteralPath $Source -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        }
        else {
            $sizeBytes = $sourceItem.Length
        }
        $sizeMB = [math]::Round($sizeBytes / 1MB, 2)
    }

    $destParent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destParent)) {
        New-Item -Path $destParent -ItemType Directory -Force | Out-Null
    }

    $sourceName = Split-Path -Leaf $Source
    $status = if ($sizeMB -gt 0) { "Copying $sourceName ($sizeMB MB)" } else { "Copying $sourceName" }

    Write-Progress -Id $ProgressId -Activity $Activity -Status $status -PercentComplete -1

    if ($PSCmdlet.ShouldProcess($Source, "Copy to $Destination")) {
        try {
            Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force -ErrorAction Stop -WhatIf:$WhatIfPreference
            Write-Host "[copy] $Source -> $Destination ($sizeMB MB)" -ForegroundColor DarkCyan

            $hash = Get-FileHashSafe -Path $Destination
            $script:manifestEntries += @{
                Source = $Source
                Destination = $Destination
                Status = "Copied"
                SizeBytes = $sizeBytes
                SHA256 = $hash
            }
        }
        catch {
            Write-Warning "[skip] Failed to copy $Source. Reason: $($_.Exception.Message)"
            $script:manifestEntries += @{
                Source = $Source
                Destination = $Destination
                Status = "Failed: $($_.Exception.Message)"
                SizeBytes = $sizeBytes
                SHA256 = "N/A"
            }
        }
        finally {
            Write-Progress -Id $ProgressId -Activity $Activity -Completed
        }
    }
    else {
        Write-Host "[whatif] Would copy: $Source -> $Destination ($sizeMB MB)" -ForegroundColor Yellow
        $script:manifestEntries += @{
            Source = $Source
            Destination = $Destination
            Status = "WhatIf"
            SizeBytes = $sizeBytes
            SHA256 = "N/A"
        }
        Write-Progress -Id $ProgressId -Activity $Activity -Completed
    }
}

function Test-FreeSpace {
    param(
        [string]$Path,
        [long]$RequiredBytes
    )

    $volume = Get-Volume -FilePath $Path -ErrorAction SilentlyContinue
    if (-not $volume) {
        Write-Warning "Could not determine free space for $Path"
        return $true  # Proceed anyway if we can't check
    }

    $freeBytes = $volume.SizeRemaining
    if ($freeBytes -lt $RequiredBytes) {
        $requiredGB = [math]::Round($RequiredBytes / 1GB, 2)
        $freeGB = [math]::Round($freeBytes / 1GB, 2)
        throw "Insufficient disk space. Required: ${requiredGB} GB, Available: ${freeGB} GB on $($volume.DriveLetter):"
    }

    return $true
}

function Get-FileHashSafe {
    param(
        [string]$Path
    )

    try {
        $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop
        return $hash.Hash
    }
    catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

$script:manifestEntries = @()

$resolvedWindowsRoot = Resolve-OfflineWindowsRoot -RequestedPath $OfflineWindowsRoot -DiskSpecifier $Disk
$offlineRoot = Split-Path -Parent $resolvedWindowsRoot
$offlineRoot = if ([string]::IsNullOrWhiteSpace($offlineRoot)) { Split-Path -Qualifier $resolvedWindowsRoot } else { $offlineRoot }
$timeStamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"

# Create MS_DATA root folder (if using default path)
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    if (-not (Test-Path -LiteralPath $msDataRoot)) {
        New-Item -Path $msDataRoot -ItemType Directory -Force | Out-Null
    }
}

# Create output root folder (default C:\MS_DATA\TSS_PERF_OFFLINE or custom path)
if (-not (Test-Path -LiteralPath $outputRoot)) {
    New-Item -Path $outputRoot -ItemType Directory -Force | Out-Null
}

$outputFolder = Join-Path $outputRoot "tssofflinelogcollector-$timeStamp"

if ((Test-Path -LiteralPath $outputFolder) -and -not $Force) {
    throw "Output folder already exists: $outputFolder. Use -Force to overwrite."
}

New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null

# Start transcript for this run
$transcriptPath = Join-Path $outputFolder "tssofflinelogcollector-transcript.log"
Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null

Write-Host "Offline Windows root : $resolvedWindowsRoot" -ForegroundColor Green
Write-Host "Offline disk root    : $offlineRoot" -ForegroundColor Green
Write-Host "Output root          : $outputRoot" -ForegroundColor Green
Write-Host "Output folder        : $outputFolder" -ForegroundColor Green
Write-Host "Transcript           : $transcriptPath" -ForegroundColor Green

# Collect a practical offline bundle aligned with Windows Update / DnD troubleshooting.
# Comprehensive offline collection aligned with TSS.ps1 DND_SetupReport / SDP Setup
$pathsToCollect = @(
    # Event logs
    @{ Rel = "Windows\System32\winevt\Logs"; Dest = "offline\winevt\Logs"; Activity = "Event logs" },

    # Windows Update and servicing logs
    @{ Rel = "Windows\Logs\CBS"; Dest = "offline\Windows\Logs\CBS"; Activity = "CBS logs" },
    @{ Rel = "Windows\Logs\DISM"; Dest = "offline\Windows\Logs\DISM"; Activity = "DISM logs" },
    @{ Rel = "Windows\Logs\WindowsUpdate"; Dest = "offline\Windows\Logs\WindowsUpdate"; Activity = "Windows Update logs" },
    @{ Rel = "Windows\WindowsUpdate.log"; Dest = "offline\Windows\WindowsUpdate.log"; Activity = "WindowsUpdate.log (legacy)" },
    @{ Rel = "Windows\WinSxS\pending.xml"; Dest = "offline\Windows\WinSxS\pending.xml"; Activity = "WinSxS pending" },
    @{ Rel = "Windows\WinSxS\poqexec.log"; Dest = "offline\Windows\WinSxS\poqexec.log"; Activity = "WinSxS poqexec" },
    @{ Rel = "Windows\servicing\Sessions"; Dest = "offline\Windows\servicing\Sessions"; Activity = "Servicing sessions" },
    @{ Rel = "ProgramData\USOShared\Logs"; Dest = "offline\ProgramData\USOShared\Logs"; Activity = "USO shared logs" },
    @{ Rel = "ProgramData\USOPrivate\UpdateStore"; Dest = "offline\ProgramData\USOPrivate\UpdateStore"; Activity = "USO private store" },

    # Setup and upgrade logs
    @{ Rel = "Windows\Panther"; Dest = "offline\Windows\Panther"; Activity = "Panther setup logs" },
    @{ Rel = "$Windows.~BT\Sources\Panther"; Dest = "offline\Windows.~BT\Sources\Panther"; Activity = "Setup source Panther" },
    @{ Rel = "Windows\System32\Sysprep\Panther"; Dest = "offline\Windows\System32\Sysprep\Panther"; Activity = "Sysprep Panther" },

    # INF and driver installation logs
    @{ Rel = "Windows\INF"; Dest = "offline\Windows\INF"; Activity = "INF and setupapi logs" },
    @{ Rel = "Windows\System32\DriverStore\FileRepository"; Dest = "offline\Windows\System32\DriverStore\FileRepository"; Activity = "Driver store repository" },

    # Certificate and crypto
    @{ Rel = "Windows\System32\catroot2"; Dest = "offline\Windows\System32\catroot2"; Activity = "Catroot2 catalog" },

    # Windows Error Reporting
    @{ Rel = "ProgramData\Microsoft\Windows\WER"; Dest = "offline\ProgramData\Microsoft\Windows\WER"; Activity = "Windows Error Reporting" },

    # Crash dumps
    @{ Rel = "Windows\Minidump"; Dest = "offline\Windows\Minidump"; Activity = "Minidumps" },
    @{ Rel = "Windows\LiveKernelReports"; Dest = "offline\Windows\LiveKernelReports"; Activity = "Live kernel reports" },

    # System logs and diagnostics
    @{ Rel = "Windows\System32\LogFiles"; Dest = "offline\Windows\System32\LogFiles"; Activity = "System32 LogFiles" },
    @{ Rel = "Windows\Performance\WinSAT"; Dest = "offline\Windows\Performance\WinSAT"; Activity = "WinSAT performance" },
    @{ Rel = "Windows\Temp"; Dest = "offline\Windows\Temp"; Activity = "Windows Temp" },

    # Activation and licensing
    @{ Rel = "Windows\System32\spp\store"; Dest = "offline\Windows\System32\spp\store"; Activity = "Software Protection Platform" },

    # Windows Defender (if present)
    @{ Rel = "ProgramData\Microsoft\Windows Defender\Support"; Dest = "offline\ProgramData\Microsoft\Windows Defender\Support"; Activity = "Windows Defender logs" },

    # Task Scheduler logs
    @{ Rel = "Windows\System32\Tasks"; Dest = "offline\Windows\System32\Tasks"; Activity = "Scheduled tasks" },
    @{ Rel = "Windows\Tasks"; Dest = "offline\Windows\Tasks"; Activity = "Legacy tasks" },

    # Network and firewall (static config)
    @{ Rel = "Windows\System32\LogFiles\Firewall"; Dest = "offline\Windows\System32\LogFiles\Firewall"; Activity = "Firewall logs" },

    # Additional servicing and component store
    @{ Rel = "Windows\Logs\MoSetup"; Dest = "offline\Windows\Logs\MoSetup"; Activity = "Modern Setup logs" },
    @{ Rel = "Windows\Logs\DPX"; Dest = "offline\Windows\Logs\DPX"; Activity = "Device setup logs" }
)

$itemCount = 0
$totalItems = $pathsToCollect.Count

foreach ($item in $pathsToCollect) {
    $itemCount++
    $sourcePath = Join-Path $offlineRoot $item.Rel
    $destPath = Join-Path $outputFolder $item.Dest
    $activity = if ($item.Activity) { $item.Activity } else { "Offline files" }

    Write-Progress -Id 0 -Activity "Collecting offline diagnostics" -Status "($itemCount of $totalItems) $activity" -PercentComplete (($itemCount / $totalItems) * 100)
    Copy-IfPresent -Source $sourcePath -Destination $destPath -Activity $activity -ProgressId 1
}

Write-Progress -Id 0 -Activity "Collecting offline diagnostics" -Completed

# SoftwareDistribution — opt-in only (contains large update-download payloads; can be several hundred MB)
if ($IncludeSoftwareDistribution) {
    $sdPath = Join-Path $offlineRoot "Windows\SoftwareDistribution"
    $destPath = Join-Path $outputFolder "offline\Windows\SoftwareDistribution"
    Copy-IfPresent -Source $sdPath -Destination $destPath -Activity "SoftwareDistribution" -ProgressId 1
}

# MEMORY.DMP — opt-in only (large + may contain in-memory secrets)
if ($IncludeMemoryDump) {
    $dumpPath = Join-Path $offlineRoot "Windows\MEMORY.DMP"
    if (Test-Path -LiteralPath $dumpPath) {
        $dumpItem = Get-Item -LiteralPath $dumpPath
        $dumpSizeGB = [math]::Round($dumpItem.Length / 1GB, 2)

        Write-Warning "⚠️  MEMORY DUMP: Collecting MEMORY.DMP ($dumpSizeGB GB)"
        Write-Warning "    This file is large and may contain in-memory secrets (credentials, encryption keys)."
        Write-Warning "    Only include if explicitly required for crash analysis."

        $destPath = Join-Path $outputFolder "offline\Windows\MEMORY.DMP"
        Copy-IfPresent -Source $dumpPath -Destination $destPath -Activity "Memory dump ($dumpSizeGB GB)" -ProgressId 1
    }
    else {
        Write-Host "[skip] MEMORY.DMP not found (expected if no crash occurred)" -ForegroundColor DarkYellow
    }
}

# Registry hive collection (always included - required for proper troubleshooting)
$hiveFolder = Join-Path $resolvedWindowsRoot "System32\config"

# Core diagnostic hives (safe for support bundles)
$safeHives = @("SYSTEM", "SOFTWARE")

foreach ($hive in $safeHives) {
    $sourceHive = Join-Path $hiveFolder $hive
    $destHive = Join-Path $outputFolder ("offline\registry\{0}" -f $hive)
    Copy-IfPresent -Source $sourceHive -Destination $destHive -Activity "Registry hive: $hive" -ProgressId 1
}

# COMPONENTS hive (opt-in - large servicing-store hive, only needed for deep CBS/servicing analysis)
if ($IncludeComponentsHive) {
    $sourceHive = Join-Path $hiveFolder "COMPONENTS"
    $destHive = Join-Path $outputFolder "offline\registry\COMPONENTS"
    Copy-IfPresent -Source $sourceHive -Destination $destHive -Activity "Registry hive: COMPONENTS" -ProgressId 1
}

# Credential-bearing hives (requires explicit consent)
if ($IncludeCredentialHives) {
    Write-Warning "⚠️  CREDENTIAL HIVES: Collecting SAM, SECURITY, and DEFAULT registry hives."
    Write-Warning "    These hives contain sensitive credential material (password hashes, LSA secrets, DPAPI data)."
    Write-Warning "    Only collect these if explicitly required for your troubleshooting scenario."

    $credentialHives = @("SAM", "SECURITY", "DEFAULT")
    foreach ($hive in $credentialHives) {
        $sourceHive = Join-Path $hiveFolder $hive
        $destHive = Join-Path $outputFolder ("offline\registry\{0}" -f $hive)
        Copy-IfPresent -Source $sourceHive -Destination $destHive -Activity "Credential hive: $hive" -ProgressId 1
    }
}

# Generate manifest
Write-Host "[manifest] Generating collection manifest..." -ForegroundColor Cyan
$manifestPath = Join-Path $outputFolder "manifest.json"
$manifest = @{
    CollectionTime = (Get-Date).ToUniversalTime().ToString("o")
    OfflineWindowsRoot = $resolvedWindowsRoot
    OfflineDiskRoot = $offlineRoot
    OutputFolder = $outputFolder
    Parameters = @{
        IncludeCredentialHives = $IncludeCredentialHives.IsPresent
        IncludeMemoryDump = $IncludeMemoryDump.IsPresent
    }
    Files = $script:manifestEntries
}
$manifest | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $manifestPath -Encoding UTF8 -Force
Write-Host "[manifest] Manifest saved: $manifestPath" -ForegroundColor Green

# Stop transcript before zip/final output
Stop-Transcript | Out-Null

if ($ZipOutput) {
    $zipPath = "$outputFolder.zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $outputFolder "*") -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "Zip created: $zipPath" -ForegroundColor Green
}

# Collection summary
$copiedCount = ($script:manifestEntries | Where-Object { $_.Status -eq "Copied" }).Count
$skippedCount = ($script:manifestEntries | Where-Object { $_.Status -match "^(Missing|Failed)" }).Count
$totalSize = ($script:manifestEntries | Where-Object { $_.Status -eq "Copied" } | ForEach-Object { $_.SizeBytes } | Measure-Object -Sum).Sum
if (-not $totalSize) { $totalSize = 0 }
$totalSizeGB = [math]::Round($totalSize / 1GB, 2)

Write-Host "`nOffline collection complete." -ForegroundColor Green
Write-Host "  Copied  : $copiedCount items ($totalSizeGB GB)" -ForegroundColor Green
Write-Host "  Skipped : $skippedCount items" -ForegroundColor Yellow
Write-Host "  Bundle  : $outputFolder" -ForegroundColor Cyan
Write-Host "  Manifest: $manifestPath" -ForegroundColor Cyan
