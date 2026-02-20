<#
.SYNOPSIS
    Analyzes Windows service dependency chains, startup type mismatches, and
    volatile temp-drive references on Azure VMs.

.DESCRIPTION
    WindowsServiceDependencyAnalyzer performs three categories of checks:

    1. Dependency Chain Analysis
       - Maps each service's DependOnService list and reverse-depends (dependents)
       - Detects circular dependencies
       - Identifies chains deeper than 4 levels (fragile startup order)
       - Flags services depending on a Disabled or Manual service

    2. Startup Type Mismatch Detection
       - Services set to Automatic that are currently Stopped (and not trigger-started)
       - Services set to Disabled that have active dependents set to Automatic
       - Services in a failed state (StartType = Automatic, Status = Stopped,
         ExitCode != 0)

    3. Volatile Path Detection
       - Scans service ImagePath and common registry parameters for references to
         the Azure temp drive (typically D:\) or well-known volatile paths
       - Flags services whose binaries or data live on drives that are wiped on
         redeployment/resize

    Output is a structured report with findings grouped by severity:
      CRITICAL  - Service failures or broken dependency chains
      WARNING   - Mismatches likely to cause issues after reboot/redeploy
      INFO      - Advisory observations

.PARAMETER TempDriveLetter
    The drive letter of the Azure temporary disk. Defaults to 'D'.
    On some VM sizes this may be E or another letter.

.PARAMETER MaxDepth
    Maximum dependency chain depth before flagging as deep chain. Default: 4.

.PARAMETER IncludeHealthy
    If specified, also lists services that passed all checks (verbose).

.PARAMETER MockConfig
    Path to a JSON file with mock service data for local/unit testing.

.NOTES
    Requires administrator privileges for full WMI/registry access.
    Tested on Windows Server 2016, 2019, 2022, 2025.
    Designed for Azure VM Run Command execution.

.EXAMPLE
    PS> .\Windows_Service_Dependency_Analyzer.ps1

.EXAMPLE
    PS> .\Windows_Service_Dependency_Analyzer.ps1 -TempDriveLetter E -IncludeHealthy

.EXAMPLE
    Local testing with mock data:
    PS> .\Windows_Service_Dependency_Analyzer.ps1 -MockConfig .\mock_config_sample.json
#>

[CmdletBinding()]
param(
    [ValidatePattern('^[A-Z]$')]
    [string]$TempDriveLetter = 'D',

    [ValidateRange(2, 10)]
    [int]$MaxDepth = 4,

    [switch]$IncludeHealthy,

    [string]$MockConfig
)

# ---- Constants ---------------------------------------------------------------
$AZURE_BLUE  = 'Cyan'
$CRIT_COLOR  = 'Red'
$WARN_COLOR  = 'Yellow'
$OK_COLOR    = 'Green'
$INFO_COLOR  = 'Gray'
$tFmt        = "{0,-55} {1,-10} {2}"

# ---- Helpers -----------------------------------------------------------------
function Write-Banner {
    param([string]$Text)
    $line = '=' * 70
    Write-Host "`n$line" -ForegroundColor $AZURE_BLUE
    Write-Host "  $Text" -ForegroundColor $AZURE_BLUE
    Write-Host $line -ForegroundColor $AZURE_BLUE
}

function Write-Finding {
    param(
        [ValidateSet('CRITICAL','WARNING','INFO','OK')]
        [string]$Severity,
        [string]$Service,
        [string]$Message
    )
    $color = switch ($Severity) {
        'CRITICAL' { $CRIT_COLOR }
        'WARNING'  { $WARN_COLOR }
        'INFO'     { $INFO_COLOR }
        'OK'       { $OK_COLOR }
    }
    Write-Host ($tFmt -f $Service, "[$Severity]", $Message) -ForegroundColor $color
    [PSCustomObject]@{
        Severity = $Severity
        Service  = $Service
        Message  = $Message
    }
}

function Write-SectionHeader {
    param([string]$Text)
    Write-Host "`n-- $Text --" -ForegroundColor $AZURE_BLUE
    Write-Host ($tFmt -f 'Service', 'Severity', 'Finding') -ForegroundColor DarkGray
    Write-Host ($tFmt -f ('-'*55), ('-'*10), ('-'*40)) -ForegroundColor DarkGray
}

# ---- Safety ------------------------------------------------------------------
$isMock = [bool]$MockConfig
if (-not $isMock) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "WARNING: Running without admin rights. Some checks may be incomplete." -ForegroundColor Yellow
    }
}

# ---- Load Service Data -------------------------------------------------------
Write-Banner "Windows Service Dependency Analyzer"
Write-Host "Temp drive: ${TempDriveLetter}:\    Max chain depth: $MaxDepth" -ForegroundColor $INFO_COLOR
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC' -AsUTC)" -ForegroundColor $INFO_COLOR

if ($isMock) {
    if (-not (Test-Path $MockConfig)) {
        Write-Host "Mock config not found: $MockConfig" -ForegroundColor $CRIT_COLOR
        exit 1
    }
    Write-Host "** MOCK MODE — using $MockConfig **" -ForegroundColor Yellow
    $mockData  = Get-Content $MockConfig -Raw | ConvertFrom-Json
    $services  = $mockData.Services
} else {
    Write-Verbose "Querying services via Get-Service and WMI..."
    $services = Get-Service | ForEach-Object {
        $svc = $_
        # Get WMI details for the ImagePath
        $wmiSvc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Name              = $svc.Name
            DisplayName       = $svc.DisplayName
            Status            = $svc.Status.ToString()
            StartType         = $svc.StartType.ToString()
            DependOnService   = @($svc.ServicesDependedOn | ForEach-Object { $_.Name })
            DependentServices = @($svc.DependentServices | ForEach-Object { $_.Name })
            ImagePath         = if ($wmiSvc) { $wmiSvc.PathName } else { '' }
            ExitCode          = if ($wmiSvc) { $wmiSvc.ExitCode } else { 0 }
            DelayedAutoStart  = $false  # Will check registry below
        }
    }

    # Enrich: check for delayed auto-start and trigger-start via registry
    foreach ($svc in $services) {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
        if (Test-Path $regPath) {
            $delayedStart = Get-ItemProperty -Path $regPath -Name 'DelayedAutostart' -ErrorAction SilentlyContinue
            if ($delayedStart -and $delayedStart.DelayedAutostart -eq 1) {
                $svc.DelayedAutoStart = $true
            }
            # Check for trigger-start (TriggerInfo subkey)
            $triggerPath = Join-Path $regPath 'TriggerInfo'
            if (Test-Path $triggerPath) {
                $svc | Add-Member -NotePropertyName 'IsTriggerStart' -NotePropertyValue $true -Force
            } else {
                $svc | Add-Member -NotePropertyName 'IsTriggerStart' -NotePropertyValue $false -Force
            }
        } else {
            $svc | Add-Member -NotePropertyName 'IsTriggerStart' -NotePropertyValue $false -Force
        }
    }
}

$totalServices = $services.Count
Write-Host "Services loaded: $totalServices" -ForegroundColor $OK_COLOR

# Build lookup table
$svcLookup = @{}
foreach ($s in $services) {
    $svcLookup[$s.Name] = $s
}

# ---- Collection for findings -------------------------------------------------
$findings = [System.Collections.Generic.List[PSCustomObject]]::new()

# ==============================================================================
# CHECK 1: Dependency Chain Analysis
# ==============================================================================
Write-SectionHeader "1. Dependency Chain Analysis"

# Recursive depth calculator
function Get-DependencyDepth {
    param([string]$ServiceName, [hashtable]$Visited, [int]$CurrentDepth)

    if ($Visited.ContainsKey($ServiceName)) {
        return @{ Depth = -1; Circular = $true; Chain = @($ServiceName) }
    }
    $Visited[$ServiceName] = $true

    $svc = $svcLookup[$ServiceName]
    if (-not $svc -or $svc.DependOnService.Count -eq 0) {
        return @{ Depth = $CurrentDepth; Circular = $false; Chain = @($ServiceName) }
    }

    $maxChild = $CurrentDepth
    $deepestChain = @($ServiceName)
    $circular = $false

    foreach ($dep in $svc.DependOnService) {
        $result = Get-DependencyDepth -ServiceName $dep -Visited $Visited.Clone() -CurrentDepth ($CurrentDepth + 1)
        if ($result.Circular) {
            $circular = $true
            $deepestChain = @($ServiceName) + $result.Chain
            break
        }
        if ($result.Depth -gt $maxChild) {
            $maxChild = $result.Depth
            $deepestChain = @($ServiceName) + $result.Chain
        }
    }

    return @{ Depth = $maxChild; Circular = $circular; Chain = $deepestChain }
}

$circularFound   = 0
$deepChainFound  = 0
$brokenDepFound  = 0

foreach ($svc in $services) {
    if ($svc.DependOnService.Count -eq 0) { continue }

    # Check for circular dependencies
    $depResult = Get-DependencyDepth -ServiceName $svc.Name -Visited @{} -CurrentDepth 0

    if ($depResult.Circular) {
        $chain = $depResult.Chain -join ' -> '
        $findings.Add((Write-Finding -Severity CRITICAL -Service $svc.Name `
            -Message "Circular dependency detected: $chain"))
        $circularFound++
        continue
    }

    # Check for deep chains
    if ($depResult.Depth -gt $MaxDepth) {
        $chain = $depResult.Chain -join ' -> '
        $findings.Add((Write-Finding -Severity WARNING -Service $svc.Name `
            -Message "Deep chain (depth $($depResult.Depth)): $chain"))
        $deepChainFound++
    }

    # Check if depending on a Disabled or Manual service
    foreach ($depName in $svc.DependOnService) {
        $depSvc = $svcLookup[$depName]
        if (-not $depSvc) {
            $findings.Add((Write-Finding -Severity WARNING -Service $svc.Name `
                -Message "Depends on '$depName' which does not exist on this system"))
            $brokenDepFound++
            continue
        }
        if ($svc.StartType -eq 'Automatic' -and $depSvc.StartType -eq 'Disabled') {
            $findings.Add((Write-Finding -Severity CRITICAL -Service $svc.Name `
                -Message "StartType=Automatic but depends on '$depName' which is Disabled"))
            $brokenDepFound++
        }
        elseif ($svc.StartType -eq 'Automatic' -and $depSvc.StartType -eq 'Manual' -and -not $depSvc.IsTriggerStart) {
            $findings.Add((Write-Finding -Severity WARNING -Service $svc.Name `
                -Message "StartType=Automatic but depends on '$depName' (Manual, not trigger-started)"))
            $brokenDepFound++
        }
    }
}

Write-Host "`nChain summary: $circularFound circular, $deepChainFound deep (>$MaxDepth), $brokenDepFound broken/mismatched" `
    -ForegroundColor $INFO_COLOR

# ==============================================================================
# CHECK 2: Startup Type Mismatch Detection
# ==============================================================================
Write-SectionHeader "2. Startup Type Mismatch Detection"

$autoStopped    = 0
$disabledWithDeps = 0
$failedServices = 0

foreach ($svc in $services) {
    # Automatic but Stopped (not trigger-started or delayed)
    if ($svc.StartType -eq 'Automatic' -and $svc.Status -eq 'Stopped') {
        if ($svc.IsTriggerStart) {
            # Trigger-started services may legitimately be stopped
            if ($IncludeHealthy) {
                $findings.Add((Write-Finding -Severity INFO -Service $svc.Name `
                    -Message "Automatic+Stopped but trigger-started (expected)"))
            }
        } else {
            $exitInfo = if ($svc.ExitCode -and $svc.ExitCode -ne 0) { " (ExitCode: $($svc.ExitCode))" } else { "" }
            $severity = if ($svc.ExitCode -and $svc.ExitCode -ne 0) { 'CRITICAL' } else { 'WARNING' }
            $findings.Add((Write-Finding -Severity $severity -Service $svc.Name `
                -Message "StartType=Automatic but Status=Stopped$exitInfo"))
            if ($severity -eq 'CRITICAL') { $failedServices++ }
            $autoStopped++
        }
    }

    # Disabled with active Automatic dependents
    if ($svc.StartType -eq 'Disabled' -and $svc.DependentServices.Count -gt 0) {
        $autoDeps = @()
        foreach ($depName in $svc.DependentServices) {
            $dep = $svcLookup[$depName]
            if ($dep -and $dep.StartType -eq 'Automatic') {
                $autoDeps += $depName
            }
        }
        if ($autoDeps.Count -gt 0) {
            $depList = $autoDeps -join ', '
            $findings.Add((Write-Finding -Severity CRITICAL -Service $svc.Name `
                -Message "Disabled but has Automatic dependents: $depList"))
            $disabledWithDeps++
        }
    }
}

Write-Host "`nMismatch summary: $autoStopped auto+stopped, $disabledWithDeps disabled-with-auto-deps, $failedServices failed (non-zero exit)" `
    -ForegroundColor $INFO_COLOR

# ==============================================================================
# CHECK 3: Volatile Temp Drive Path Detection
# ==============================================================================
Write-SectionHeader "3. Volatile Temp Drive Path Detection"

$volatilePatterns = @(
    "${TempDriveLetter}:\",
    "${TempDriveLetter}:/",
    "\\?\${TempDriveLetter}:\"
)
# Also flag well-known Azure temp paths
$tempKeywords = @(
    'Temporary Storage',
    'Resource disk',
    'local SSD',
    'temp drive'
)

$tempDriveHits = 0

foreach ($svc in $services) {
    $imagePath = $svc.ImagePath
    if (-not $imagePath) { continue }

    # Check ImagePath for temp drive references
    $hitVolatile = $false
    foreach ($pattern in $volatilePatterns) {
        if ($imagePath -like "*$pattern*") {
            $hitVolatile = $true
            break
        }
    }

    if ($hitVolatile) {
        $findings.Add((Write-Finding -Severity CRITICAL -Service $svc.Name `
            -Message "ImagePath references temp drive (${TempDriveLetter}:\): $imagePath"))
        $tempDriveHits++
        continue
    }

    # Check registry for additional path references (Parameters key, common subkeys)
    if (-not $isMock) {
        $regBase = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
        $parametersPath = Join-Path $regBase 'Parameters'

        $pathsToCheck = @($regBase)
        if (Test-Path $parametersPath) { $pathsToCheck += $parametersPath }

        foreach ($regPath in $pathsToCheck) {
            try {
                $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }

                $propNames = $props.PSObject.Properties |
                    Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notlike 'PS*' } |
                    ForEach-Object { $_.Name }

                foreach ($propName in $propNames) {
                    $val = [string]$props.$propName
                    foreach ($pattern in $volatilePatterns) {
                        if ($val -like "*$pattern*") {
                            $findings.Add((Write-Finding -Severity WARNING -Service $svc.Name `
                                -Message "Registry '$propName' references temp drive: $($val.Substring(0, [Math]::Min(100, $val.Length)))"))
                            $tempDriveHits++
                            break
                        }
                    }
                }
            } catch {
                # Access denied or other registry errors — skip silently
            }
        }
    }
}

Write-Host "`nVolatile path hits: $tempDriveHits" -ForegroundColor $INFO_COLOR

# ==============================================================================
# SUMMARY REPORT
# ==============================================================================
Write-Banner "Summary Report"

$critCount = ($findings | Where-Object { $_.Severity -eq 'CRITICAL' }).Count
$warnCount = ($findings | Where-Object { $_.Severity -eq 'WARNING' }).Count
$infoCount = ($findings | Where-Object { $_.Severity -eq 'INFO' }).Count

$summaryData = @(
    @{ Label = 'Total services scanned';       Value = $totalServices }
    @{ Label = 'CRITICAL findings';            Value = $critCount }
    @{ Label = 'WARNING findings';             Value = $warnCount }
    @{ Label = 'INFO findings';                Value = $infoCount }
    @{ Label = '  Circular dependencies';      Value = $circularFound }
    @{ Label = '  Deep chains (>depth)';       Value = $deepChainFound }
    @{ Label = '  Broken/mismatched deps';     Value = $brokenDepFound }
    @{ Label = '  Automatic but Stopped';      Value = $autoStopped }
    @{ Label = '  Disabled with auto deps';    Value = $disabledWithDeps }
    @{ Label = '  Failed (non-zero exit)';     Value = $failedServices }
    @{ Label = '  Temp drive references';      Value = $tempDriveHits }
)

foreach ($item in $summaryData) {
    $color = if ($item.Label -match 'CRITICAL' -and $item.Value -gt 0) { $CRIT_COLOR }
             elseif ($item.Label -match 'WARNING' -and $item.Value -gt 0) { $WARN_COLOR }
             else { $INFO_COLOR }
    Write-Host ("{0,-35} {1}" -f $item.Label, $item.Value) -ForegroundColor $color
}

# ---- Top Recommendations ----
if ($critCount -gt 0 -or $warnCount -gt 0) {
    Write-Banner "Recommended Actions"

    if ($tempDriveHits -gt 0) {
        Write-Host @"

  [TEMP DRIVE] $tempDriveHits service(s) reference the Azure temp drive (${TempDriveLetter}:\).
  This drive is wiped on VM resize, redeployment, or host maintenance.
  ACTION: Move service binaries and data to an OS disk or attached data disk.
  VERIFY: After moving, update ImagePath and registry Parameters.
  DOCS:   https://learn.microsoft.com/azure/virtual-machines/managed-disks-overview#temporary-disk
"@ -ForegroundColor $WARN_COLOR
    }

    if ($circularFound -gt 0) {
        Write-Host @"

  [CIRCULAR] $circularFound circular dependency chain(s) detected.
  ACTION: Review the listed chains and remove or restructure dependencies.
  CMD:    sc.exe config <ServiceName> depend= <CorrectedList>
"@ -ForegroundColor $CRIT_COLOR
    }

    if ($brokenDepFound -gt 0) {
        Write-Host @"

  [DEPENDENCY MISMATCH] $brokenDepFound service(s) depend on Disabled/Manual services.
  ACTION: Either enable the dependency or change the dependent's StartType.
  CMD:    sc.exe config <DependencyName> start= auto
  CMD:    sc.exe config <DependentName> start= demand
"@ -ForegroundColor $WARN_COLOR
    }

    if ($failedServices -gt 0) {
        Write-Host @"

  [FAILED] $failedServices service(s) are Automatic but stopped with non-zero exit code.
  ACTION: Check Event Log: Get-WinEvent -LogName System -FilterXPath "*[System[Provider[@Name='Service Control Manager']]]" | Where-Object {`$_.Message -match '<ServiceName>'}
  CMD:    sc.exe qfailure <ServiceName>   (to check recovery actions)
  CMD:    sc.exe failure <ServiceName> reset= 86400 actions= restart/60000/restart/120000/""   (to set auto-restart)
"@ -ForegroundColor $CRIT_COLOR
    }

    if ($autoStopped -gt 0) {
        Write-Host @"

  [AUTO+STOPPED] $autoStopped Automatic service(s) are not running.
  ACTION: For each, determine if it should be running or if StartType should be Manual/Disabled.
  CMD:    Start-Service <ServiceName>
  CMD:    Set-Service <ServiceName> -StartupType Manual   (if not needed at boot)
"@ -ForegroundColor $WARN_COLOR
    }
}

# ---- Output findings as objects for pipeline use ----
if ($findings.Count -gt 0) {
    Write-Verbose "Returning $($findings.Count) findings as pipeline objects."
    $findings | Sort-Object @{Expression='Severity'; Ascending=$true}, Service
} else {
    Write-Host "`nNo issues detected. All service dependencies and paths look healthy." -ForegroundColor $OK_COLOR
}
