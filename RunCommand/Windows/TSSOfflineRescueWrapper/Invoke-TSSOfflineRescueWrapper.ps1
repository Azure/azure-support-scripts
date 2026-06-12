[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OfflineWindowsRoot,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = "C:\MS_DATA\OfflineTSSWrapper",

    [Parameter(Mandatory = $false)]
    [string]$TssPath,

    [Parameter(Mandatory = $false)]
    [string]$TssCollectLog = "DND_SetupReport",

    [Parameter(Mandatory = $false)]
    [string[]]$TssArguments,

    [Parameter(Mandatory = $false)]
    [switch]$RunTssOnRescueVm,

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

function Resolve-OfflineWindowsRoot {
    param(
        [string]$RequestedPath
    )

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

    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    Write-Host "[copy] $Source -> $Destination" -ForegroundColor DarkCyan
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

    $invokeArgs = New-Object System.Collections.Generic.List[string]
    if ($Arguments) {
        foreach ($arg in $Arguments) {
            if (-not [string]::IsNullOrWhiteSpace($arg)) {
                $invokeArgs.Add($arg) | Out-Null
            }
        }
    }

    if ($AutoAcceptEula -and -not ($invokeArgs -contains "-AcceptEula")) {
        $invokeArgs.Add("-AcceptEula") | Out-Null
    }

$invokeArgsArray = $invokeArgs.ToArray()
Write-Host ("[tss] Starting TSS: {0} {1}" -f $Path, ($invokeArgsArray -join " ")) -ForegroundColor Yellow
& $Path @invokeArgsArray
Write-Host "[tss] Completed TSS collection." -ForegroundColor Green
}

$resolvedWindowsRoot = Resolve-OfflineWindowsRoot -RequestedPath $OfflineWindowsRoot
$offlineRoot = Split-Path -Parent $resolvedWindowsRoot
$offlineRoot = if ([string]::IsNullOrWhiteSpace($offlineRoot)) { Split-Path -Qualifier $resolvedWindowsRoot } else { $offlineRoot }
$timeStamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
}

$outputFolder = Join-Path $OutputRoot "offline-tss-wrapper-$timeStamp"

if ((Test-Path -LiteralPath $outputFolder) -and -not $Force) {
    throw "Output folder already exists: $outputFolder. Use -Force to overwrite."
}

New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null

Write-Host "Offline Windows root : $resolvedWindowsRoot" -ForegroundColor Green
Write-Host "Offline disk root    : $offlineRoot" -ForegroundColor Green
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

if ($RunTssOnRescueVm) {
    if ([string]::IsNullOrWhiteSpace($TssPath)) {
        $candidate = Join-Path $PSScriptRoot "..\TSS\TSS.ps1"
        if (Test-Path -LiteralPath $candidate) {
            $TssPath = (Resolve-Path $candidate).Path
        }
        else {
            throw "-RunTssOnRescueVm was set, but -TssPath was not provided and default candidate was not found: $candidate"
        }
    }

    $effectiveTssArgs = @()
    if ($TssArguments -and $TssArguments.Count -gt 0) {
        $effectiveTssArgs = $TssArguments
    }
    else {
        $effectiveTssArgs = @("-CollectLog", $TssCollectLog)
    }

    Run-OptionalTss -Path $TssPath -Arguments $effectiveTssArgs -AutoAcceptEula:(-not $NoAcceptEula)
}

if ($ZipOutput) {
    $zipPath = "$outputFolder.zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $outputFolder "*") -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "Zip created: $zipPath" -ForegroundColor Green
}

Write-Host "Offline rescue collection complete." -ForegroundColor Green
Write-Host "Bundle path: $outputFolder" -ForegroundColor Green
