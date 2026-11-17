# Run from a WORKING machine (Azure rescue VM or Hyper-V host) that has the broken VM's OS disk attached as an offline data disk. Do NOT run on the broken VM.
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$OfflineWindowsRoot,

    [Parameter(Mandatory = $false)]
    [string]$Disk,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeComponentsHive,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSoftwareDistribution,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeWindowsTemp,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDriverStore,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeMemoryDump,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBootPartition,

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

function Get-SafeFileNameComponent {
    # Sanitizes a string for use in a file/folder name, falling back when empty or unusable.
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,

        [string]$Fallback = "UnknownMachine"
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $Fallback
    }

    $invalidChars = [regex]::Escape(([System.IO.Path]::GetInvalidFileNameChars() -join ''))
    $sanitized = [regex]::Replace($Name.Trim(), "[$invalidChars\s]", '-').Trim('-')

    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        return $Fallback
    }

    return $sanitized
}

function Get-OfflineComputerName {
    # Reads ComputerName from the offline SYSTEM hive via a short-lived reg.exe load/unload.
    param(
        [Parameter(Mandatory = $true)]
        [string]$HiveFolder
    )

    $systemHivePath = Join-Path $HiveFolder "SYSTEM"
    if (-not (Test-Path -LiteralPath $systemHivePath)) {
        Write-Warning "[machine-name] SYSTEM hive not found at $systemHivePath."
        return $null
    }

    $tempHiveKey = "TSSOfflineHive_{0}" -f ([guid]::NewGuid().ToString("N"))
    $loaded = $false

    # Load a scratch copy (hive + transaction logs) so reg load / log replay never modifies the
    # offline evidence hive. This also keeps a dirty or corrupt hive intact for the real collection.
    $scratchDir = Join-Path ([System.IO.Path]::GetTempPath()) $tempHiveKey

    try {
        New-Item -Path $scratchDir -ItemType Directory -Force -WhatIf:$false | Out-Null
        foreach ($suffix in @("", ".LOG", ".LOG1", ".LOG2")) {
            $sourceFile = Join-Path $HiveFolder "SYSTEM$suffix"
            if (Test-Path -LiteralPath $sourceFile) {
                Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $scratchDir "SYSTEM$suffix") -Force -ErrorAction SilentlyContinue -WhatIf:$false
            }
        }

        $systemHivePath = Join-Path $scratchDir "SYSTEM"
        if (-not (Test-Path -LiteralPath $systemHivePath)) {
            Write-Warning "[machine-name] Could not stage a scratch copy of the SYSTEM hive."
            return $null
        }

        $loadOutput = & reg.exe load "HKLM\$tempHiveKey" "$systemHivePath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "[machine-name] Failed to load offline SYSTEM hive: $loadOutput"
            return $null
        }
        $loaded = $true

        $selectKey = "Registry::HKEY_LOCAL_MACHINE\$tempHiveKey\Select"
        $currentId = (Get-ItemProperty -LiteralPath $selectKey -Name "Current" -ErrorAction Stop).Current
        $controlSet = "ControlSet{0:D3}" -f $currentId

        $computerNameKey = "Registry::HKEY_LOCAL_MACHINE\$tempHiveKey\$controlSet\Control\ComputerName\ComputerName"
        $name = (Get-ItemProperty -LiteralPath $computerNameKey -Name "ComputerName" -ErrorAction Stop).ComputerName

        if ([string]::IsNullOrWhiteSpace($name)) {
            return $null
        }

        return $name.Trim()
    }
    catch {
        Write-Warning "[machine-name] Could not read computer name from offline SYSTEM hive: $($_.Exception.Message)"
        return $null
    }
    finally {
        if ($loaded) {
            # Release any lingering handles before unload to avoid "hive in use" failures.
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds 300
            $unloadOutput = & reg.exe unload "HKLM\$tempHiveKey" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "[machine-name] Failed to unload temporary hive HKLM\$tempHiveKey : $unloadOutput"
            }
        }

        if (Test-Path -LiteralPath $scratchDir) {
            Remove-Item -LiteralPath $scratchDir -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false
        }
    }
}

function Get-PartitionForPath {
    # Resolves the partition that actually holds $Path by volume identity, so a disk mounted at a
    # folder (for example C:\OfflineMount) is not confused with the host disk that owns the C: letter.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $volume = Get-Volume -FilePath $Path -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $volume -or [string]::IsNullOrWhiteSpace($volume.UniqueId)) {
        return $null
    }

    return Get-Partition -ErrorAction SilentlyContinue |
        Where-Object { @($_.AccessPaths) -contains $volume.UniqueId } |
        Select-Object -First 1
}

function Get-PartitionReadRoot {
    # Returns a readable root for a partition: drive letter, then volume GUID path, then (last resort)
    # a temporary drive letter that the caller must remove via the TempMounts list.
    param(
        [Parameter(Mandatory = $true)]
        $Partition,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$TempMounts
    )

    if ($Partition.DriveLetter) {
        return "$($Partition.DriveLetter):\"
    }

    foreach ($accessPath in @($Partition.AccessPaths)) {
        if ($accessPath -match '^\\\\\?\\Volume\{[0-9a-fA-F-]+\}\\$' -and (Test-Path -LiteralPath $accessPath -ErrorAction SilentlyContinue)) {
            return $accessPath
        }
    }

    try {
        Add-PartitionAccessPath -DiskNumber $Partition.DiskNumber -PartitionNumber $Partition.PartitionNumber -AssignDriveLetter -ErrorAction Stop
        $refreshed = Get-Partition -DiskNumber $Partition.DiskNumber -PartitionNumber $Partition.PartitionNumber -ErrorAction Stop
        if ($refreshed.DriveLetter) {
            [void]$TempMounts.Add($refreshed)
            Write-Host "[boot] Temporarily mounted partition $($Partition.PartitionNumber) as $($refreshed.DriveLetter):" -ForegroundColor DarkCyan
            return "$($refreshed.DriveLetter):\"
        }
    }
    catch {
        Write-Warning "[boot] Could not mount partition $($Partition.PartitionNumber) on disk $($Partition.DiskNumber): $($_.Exception.Message)"
    }

    return $null
}

function Add-GeneratedManifestEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $item = Get-Item -LiteralPath $Destination -ErrorAction SilentlyContinue
    $script:manifestEntries += @{
        Source = $Source
        Destination = $Destination
        Status = "Generated"
        SizeBytes = if ($item) { $item.Length } else { 0 }
        SHA256 = Get-FileHashSafe -Path $Destination
    }
}

function Copy-BootConfiguration {
    # Collects boot-chain evidence that lives outside the Windows folder: BCD stores on the
    # EFI/System/active partition, a decoded BCD enumeration, and the disk/partition layout.
    param(
        [Parameter(Mandatory = $true)]
        [string]$OsRoot,

        [Parameter(Mandatory = $true)]
        [string]$OutputFolder
    )

    $result = @{ BcdStoresFound = 0; DiskNumber = $null }

    if ($WhatIfPreference) {
        Write-Host "[whatif] Would collect BCD stores and disk layout from the offline disk's boot partitions" -ForegroundColor Yellow
        return $result
    }

    $osPartition = Get-PartitionForPath -Path $OsRoot
    if ($null -eq $osPartition) {
        Write-Warning "[boot] Could not map $OsRoot to a partition; skipping BCD/disk layout collection."
        return $result
    }
    $diskNumber = [int]$osPartition.DiskNumber
    $result.DiskNumber = $diskNumber

    $bootDest = Join-Path $OutputFolder "offline\boot"
    New-Item -Path $bootDest -ItemType Directory -Force | Out-Null

    $partitions = @(Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue)

    $layoutPath = Join-Path $bootDest "disk-layout.txt"
    try {
        $layout = @()
        $layout += "=== Get-Disk ==="
        $layout += (Get-Disk -Number $diskNumber -ErrorAction Stop | Format-List Number, FriendlyName, PartitionStyle, Size, LogicalSectorSize, PhysicalSectorSize, OperationalStatus, IsOffline, IsReadOnly | Out-String)
        $layout += "=== Get-Partition ==="
        $layout += ($partitions | Format-Table PartitionNumber, DriveLetter, Type, GptType, MbrType, IsActive, IsSystem, IsBoot, IsHidden, Offset, Size -AutoSize | Out-String -Width 250)
        $layout += "=== Get-Volume (partitions with a volume) ==="
        $layout += ($partitions | Get-Volume -ErrorAction SilentlyContinue | Format-Table DriveLetter, FileSystem, FileSystemLabel, HealthStatus, Size, SizeRemaining -AutoSize | Out-String -Width 250)
        $layout | Out-File -LiteralPath $layoutPath -Encoding UTF8 -Force
        Add-GeneratedManifestEntry -Source "Get-Disk/Get-Partition/Get-Volume (disk $diskNumber)" -Destination $layoutPath
        Write-Host "[boot] Disk layout saved: $layoutPath" -ForegroundColor DarkCyan
    }
    catch {
        Write-Warning "[boot] Could not capture disk layout: $($_.Exception.Message)"
    }

    if ($SkipBootPartition) {
        Write-Host "[boot] -SkipBootPartition specified; BCD stores will not be collected." -ForegroundColor DarkYellow
        return $result
    }

    $espGptType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
    $candidates = @($partitions | Where-Object {
            $_.IsSystem -or $_.IsActive -or $_.GptType -eq $espGptType -or $_.PartitionNumber -eq $osPartition.PartitionNumber
        })

    if ($candidates.Count -eq 0) {
        Write-Warning "[boot] No boot-candidate partitions found on disk $diskNumber."
        return $result
    }

    $tempMounts = New-Object System.Collections.ArrayList
    $bcdLocations = @("EFI\Microsoft\Boot", "Boot")
    $bcdedit = Join-Path $env:SystemRoot "System32\bcdedit.exe"

    try {
        foreach ($partition in $candidates) {
            $root = Get-PartitionReadRoot -Partition $partition -TempMounts $tempMounts
            if (-not $root) {
                Write-Host "[boot] Partition $($partition.PartitionNumber) is not readable; skipping." -ForegroundColor DarkYellow
                continue
            }

            foreach ($location in $bcdLocations) {
                $bcdDir = Join-Path $root $location
                if (-not (Test-Path -LiteralPath $bcdDir -ErrorAction SilentlyContinue)) {
                    continue
                }

                $bcdFiles = @(Get-ChildItem -LiteralPath $bcdDir -Filter "BCD*" -File -Force -ErrorAction SilentlyContinue)
                if ($bcdFiles.Count -eq 0) {
                    continue
                }

                $partitionDest = Join-Path $bootDest ("partition{0}\{1}" -f $partition.PartitionNumber, $location)
                foreach ($bcdFile in $bcdFiles) {
                    Copy-IfPresent -Source $bcdFile.FullName -Destination (Join-Path $partitionDest $bcdFile.Name) -Activity "BCD: $($bcdFile.Name)" -ProgressId 1
                }

                $mainBcd = $bcdFiles | Where-Object { $_.Name -eq "BCD" } | Select-Object -First 1
                if (-not $mainBcd) {
                    continue
                }
                $result.BcdStoresFound++

                # Decode a scratch copy so bcdedit can never touch the evidence copy or the offline original.
                if (-not (Test-Path -LiteralPath $bcdedit)) {
                    Write-Warning "[boot] bcdedit.exe not found; BCD enumeration skipped."
                    continue
                }

                $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("TSSOfflineBcd_{0}" -f ([guid]::NewGuid().ToString("N")))
                $previousPreference = $ErrorActionPreference
                try {
                    New-Item -Path $scratch -ItemType Directory -Force | Out-Null
                    foreach ($bcdFile in $bcdFiles) {
                        Copy-Item -LiteralPath $bcdFile.FullName -Destination (Join-Path $scratch $bcdFile.Name) -Force -ErrorAction SilentlyContinue
                    }

                    $ErrorActionPreference = "Continue"
                    $enumOutput = & $bcdedit /store (Join-Path $scratch "BCD") /enum all /v 2>&1 | Out-String
                    $enumExit = $LASTEXITCODE
                    $ErrorActionPreference = $previousPreference

                    $enumPath = Join-Path $partitionDest "BCD-enum.txt"
                    if (-not (Test-Path -LiteralPath $partitionDest)) {
                        New-Item -Path $partitionDest -ItemType Directory -Force | Out-Null
                    }
                    $header = "# bcdedit /store <copy of $($mainBcd.FullName)> /enum all /v (exit code $enumExit)`r`n"
                    ($header + $enumOutput) | Out-File -LiteralPath $enumPath -Encoding UTF8 -Force
                    Add-GeneratedManifestEntry -Source $mainBcd.FullName -Destination $enumPath
                    Write-Host "[boot] BCD enumeration saved: $enumPath" -ForegroundColor DarkCyan
                }
                catch {
                    Write-Warning "[boot] BCD enumeration failed for $($mainBcd.FullName): $($_.Exception.Message)"
                }
                finally {
                    $ErrorActionPreference = $previousPreference
                    if (Test-Path -LiteralPath $scratch) {
                        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
    finally {
        foreach ($mount in $tempMounts) {
            try {
                Remove-PartitionAccessPath -DiskNumber $mount.DiskNumber -PartitionNumber $mount.PartitionNumber -AccessPath "$($mount.DriveLetter):\" -ErrorAction Stop
                Write-Host "[boot] Removed temporary drive letter $($mount.DriveLetter):" -ForegroundColor DarkCyan
            }
            catch {
                Write-Warning "[boot] Could not remove temporary drive letter $($mount.DriveLetter): $($_.Exception.Message)"
            }
        }
    }

    if ($result.BcdStoresFound -eq 0) {
        Write-Warning "[boot] No BCD store found on disk $diskNumber. A missing BCD is itself a likely no-boot cause."
    }

    return $result
}

function Write-BootBinaryInventory {
    # Inventories boot-critical binaries (version/size/timestamp) to expose missing, zero-byte, or
    # mismatched files after an interrupted update without copying the binaries themselves.
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsRoot,

        [Parameter(Mandatory = $true)]
        [string]$OutputFolder
    )

    if ($WhatIfPreference) {
        Write-Host "[whatif] Would write boot binary inventory" -ForegroundColor Yellow
        return
    }

    $relativePaths = @(
        "System32\winload.exe", "System32\winload.efi", "System32\winresume.exe", "System32\winresume.efi",
        "System32\ntoskrnl.exe", "System32\hal.dll", "System32\ci.dll", "System32\kdcom.dll", "System32\config\SYSTEM",
        "System32\drivers\ntfs.sys", "System32\drivers\partmgr.sys", "System32\drivers\disk.sys",
        "System32\drivers\storvsc.sys", "System32\drivers\vmbus.sys", "System32\drivers\stornvme.sys",
        "System32\drivers\acpi.sys", "System32\drivers\msisadrv.sys", "System32\drivers\pci.sys"
    )

    $rows = foreach ($relative in $relativePaths) {
        $fullPath = Join-Path $WindowsRoot $relative
        $item = Get-Item -LiteralPath $fullPath -ErrorAction SilentlyContinue
        if ($item) {
            $version = $null
            try { $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($item.FullName).FileVersion } catch { }
            [pscustomobject]@{
                File = "Windows\$relative"
                Present = $true
                SizeBytes = $item.Length
                LastWriteUtc = $item.LastWriteTimeUtc.ToString("yyyy-MM-dd HH:mm:ss")
                FileVersion = $version
                Note = if ($item.Length -eq 0) { "ZERO-BYTE FILE" } else { "" }
            }
        }
        else {
            [pscustomobject]@{
                File = "Windows\$relative"; Present = $false; SizeBytes = 0; LastWriteUtc = ""; FileVersion = ""; Note = "MISSING"
            }
        }
    }

    $bootDest = Join-Path $OutputFolder "offline\boot"
    New-Item -Path $bootDest -ItemType Directory -Force | Out-Null
    $inventoryPath = Join-Path $bootDest "boot-binaries.txt"
    $rows | Format-Table -AutoSize | Out-String -Width 250 | Out-File -LiteralPath $inventoryPath -Encoding UTF8 -Force
    Add-GeneratedManifestEntry -Source "Boot binary inventory ($WindowsRoot)" -Destination $inventoryPath
    Write-Host "[boot] Boot binary inventory saved: $inventoryPath" -ForegroundColor DarkCyan
}

$script:manifestEntries = @()

$resolvedWindowsRoot = Resolve-OfflineWindowsRoot -RequestedPath $OfflineWindowsRoot -DiskSpecifier $Disk
$offlineRoot = Split-Path -Parent $resolvedWindowsRoot
$offlineRoot = if ([string]::IsNullOrWhiteSpace($offlineRoot)) { Split-Path -Qualifier $resolvedWindowsRoot } else { $offlineRoot }
$timeStamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"

# Identify the offline machine from its SYSTEM hive so output is named per-VM
$hiveFolder = Join-Path $resolvedWindowsRoot "System32\config"
$offlineComputerName = Get-OfflineComputerName -HiveFolder $hiveFolder
$safeMachineName = Get-SafeFileNameComponent -Name $offlineComputerName
if ($offlineComputerName) {
    Write-Host "[machine-name] Offline computer name: $offlineComputerName" -ForegroundColor Green
}
else {
    Write-Host "[machine-name] Offline computer name not available; using '$safeMachineName' in output naming." -ForegroundColor DarkYellow
}

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

$outputFolder = Join-Path $outputRoot "tssofflinelogcollector-$safeMachineName-$timeStamp"

if ((Test-Path -LiteralPath $outputFolder) -and -not $Force) {
    throw "Output folder already exists: $outputFolder. Use -Force to overwrite."
}

New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null

# Start transcript for this run
$transcriptPath = Join-Path $outputFolder "tssofflinelogcollector-transcript.log"
Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null

Write-Host "Offline Windows root : $resolvedWindowsRoot" -ForegroundColor Green
Write-Host "Offline disk root    : $offlineRoot" -ForegroundColor Green
Write-Host "Offline machine name : $offlineComputerName" -ForegroundColor Green
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
    @{ Rel = '$Windows.~BT\Sources\Panther'; Dest = "offline\Windows.~BT\Sources\Panther"; Activity = "Setup source Panther" },
    @{ Rel = '$Windows.~BT\Sources\Rollback'; Dest = "offline\Windows.~BT\Sources\Rollback"; Activity = "Setup rollback logs" },
    @{ Rel = "Windows\System32\Sysprep\Panther"; Dest = "offline\Windows\System32\Sysprep\Panther"; Activity = "Sysprep Panther" },

    # INF and driver installation logs
    @{ Rel = "Windows\INF"; Dest = "offline\Windows\INF"; Activity = "INF and setupapi logs" },

    # Certificate and crypto
    @{ Rel = "Windows\System32\catroot2"; Dest = "offline\Windows\System32\catroot2"; Activity = "Catroot2 catalog" },

    # Windows Error Reporting
    @{ Rel = "ProgramData\Microsoft\Windows\WER"; Dest = "offline\ProgramData\Microsoft\Windows\WER"; Activity = "Windows Error Reporting" },

    # Crash dumps
    @{ Rel = "Windows\Minidump"; Dest = "offline\Windows\Minidump"; Activity = "Minidumps" },
    @{ Rel = "Windows\LiveKernelReports"; Dest = "offline\Windows\LiveKernelReports"; Activity = "Live kernel reports" },

    # Boot diagnostics (SrtTrail.txt and boot-time ETL autologger traces are under System32\LogFiles below)
    @{ Rel = "Windows\bootstat.dat"; Dest = "offline\Windows\bootstat.dat"; Activity = "Boot status data" },
    @{ Rel = "Windows\ntbtlog.txt"; Dest = "offline\Windows\ntbtlog.txt"; Activity = "Boot log (ntbtlog)" },
    @{ Rel = "Windows\System32\config\RegBack\SYSTEM"; Dest = "offline\Windows\System32\config\RegBack\SYSTEM"; Activity = "SYSTEM registry backup (RegBack)" },
    @{ Rel = "Windows\System32\config\RegBack\SOFTWARE"; Dest = "offline\Windows\System32\config\RegBack\SOFTWARE"; Activity = "SOFTWARE registry backup (RegBack)" },
    @{ Rel = "Windows\System32\config\SYSTEM.LOG"; Dest = "offline\registry\SYSTEM.LOG"; Activity = "SYSTEM hive log" },
    @{ Rel = "Windows\System32\config\SYSTEM.LOG1"; Dest = "offline\registry\SYSTEM.LOG1"; Activity = "SYSTEM hive log 1" },
    @{ Rel = "Windows\System32\config\SYSTEM.LOG2"; Dest = "offline\registry\SYSTEM.LOG2"; Activity = "SYSTEM hive log 2" },
    @{ Rel = "Windows\System32\config\SOFTWARE.LOG"; Dest = "offline\registry\SOFTWARE.LOG"; Activity = "SOFTWARE hive log" },
    @{ Rel = "Windows\System32\config\SOFTWARE.LOG1"; Dest = "offline\registry\SOFTWARE.LOG1"; Activity = "SOFTWARE hive log 1" },
    @{ Rel = "Windows\System32\config\SOFTWARE.LOG2"; Dest = "offline\registry\SOFTWARE.LOG2"; Activity = "SOFTWARE hive log 2" },

    # System logs and diagnostics
    @{ Rel = "Windows\System32\LogFiles"; Dest = "offline\Windows\System32\LogFiles"; Activity = "System32 LogFiles" },
    @{ Rel = "Windows\Performance\WinSAT"; Dest = "offline\Windows\Performance\WinSAT"; Activity = "WinSAT performance" },

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

# No-boot evidence: BCD stores, disk layout, and boot-critical binary inventory
$bootResult = Copy-BootConfiguration -OsRoot $offlineRoot -OutputFolder $outputFolder
Write-BootBinaryInventory -WindowsRoot $resolvedWindowsRoot -OutputFolder $outputFolder

# SoftwareDistribution — opt-in only (contains large update-download payloads; can be several hundred MB)
if ($IncludeSoftwareDistribution) {
    $sdPath = Join-Path $offlineRoot "Windows\SoftwareDistribution"
    $destPath = Join-Path $outputFolder "offline\Windows\SoftwareDistribution"
    Copy-IfPresent -Source $sdPath -Destination $destPath -Activity "SoftwareDistribution" -ProgressId 1
}

if ($IncludeWindowsTemp) {
    $tempPath = Join-Path $offlineRoot "Windows\Temp"
    $destPath = Join-Path $outputFolder "offline\Windows\Temp"
    Copy-IfPresent -Source $tempPath -Destination $destPath -Activity "Windows Temp" -ProgressId 1
}

if ($IncludeDriverStore) {
    $driverStorePath = Join-Path $offlineRoot "Windows\System32\DriverStore\FileRepository"
    $destPath = Join-Path $outputFolder "offline\Windows\System32\DriverStore\FileRepository"
    Copy-IfPresent -Source $driverStorePath -Destination $destPath -Activity "Driver store repository" -ProgressId 1
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
# $hiveFolder was already resolved above for offline machine-name detection

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

# Generate manifest
Write-Host "[manifest] Generating collection manifest..." -ForegroundColor Cyan
$manifestPath = Join-Path $outputFolder "manifest.json"
$manifest = @{
    CollectionTime = (Get-Date).ToUniversalTime().ToString("o")
    OfflineWindowsRoot = $resolvedWindowsRoot
    OfflineDiskRoot = $offlineRoot
    OfflineComputerName = $offlineComputerName
    OutputFolder = $outputFolder
    Parameters = @{
        IncludeComponentsHive = $IncludeComponentsHive.IsPresent
        IncludeSoftwareDistribution = $IncludeSoftwareDistribution.IsPresent
        IncludeWindowsTemp = $IncludeWindowsTemp.IsPresent
        IncludeDriverStore = $IncludeDriverStore.IsPresent
        IncludeMemoryDump = $IncludeMemoryDump.IsPresent
        SkipBootPartition = $SkipBootPartition.IsPresent
    }
    BootConfiguration = @{
        DiskNumber = $bootResult.DiskNumber
        BcdStoresFound = $bootResult.BcdStoresFound
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
