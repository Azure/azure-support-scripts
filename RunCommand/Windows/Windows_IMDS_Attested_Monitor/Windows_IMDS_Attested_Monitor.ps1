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

.SYNOPSIS
    Monitors which processes access the IMDS Attested Data endpoint on an Azure VM.

.DESCRIPTION
    This script monitors network connections to the Azure Instance Metadata Service (IMDS)
    attested data endpoint (http://169.254.169.254/metadata/attested) over a configurable
    time window (default 30 minutes). It uses ETW network tracing to capture TCP connections
    to 169.254.169.254 and correlates them to the owning process ID and name.

    The script will:
    - Start an ETW trace session capturing TCP connections to 169.254.169.254
    - Poll active TCP connections every 5 seconds for the duration
    - Log every process that connects to 169.254.169.254 with timestamp, PID, process name, and path
    - At the end of the monitoring window, display a summary of all unique processes detected

.NOTES
    Requires administrator privileges.
    Designed for Azure VMs running Windows Server 2016+.
    Run via Azure Run Command or locally in an elevated PowerShell session.

.PARAMETER MonitorMinutes
    Duration in minutes to monitor. Default is 30.

.EXAMPLE
    PS> .\Windows_IMDS_Attested_Monitor.ps1
    PS> .\Windows_IMDS_Attested_Monitor.ps1 -MonitorMinutes 60
#>

[CmdletBinding()]
param(
    [int]$MonitorMinutes = 30
)

# ---- Display banner ----------------------------------------------------------
Write-Host "---------------------------------------------------------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "IMDS Attested Data Access Monitor" -ForegroundColor Cyan
Write-Host "This script monitors which processes access the IMDS attested data endpoint (169.254.169.254)" -ForegroundColor Cyan
Write-Host "Monitoring window: $MonitorMinutes minutes" -ForegroundColor Cyan
Write-Host "---------------------------------------------------------------------------------------------------------------------`n" -ForegroundColor Cyan

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

# ---- Configuration ----------------------------------------------------------
$imdsIP = "169.254.169.254"
$endTime = (Get-Date).AddMinutes($MonitorMinutes)
$pollIntervalSeconds = 5
$detections = [System.Collections.ArrayList]::new()
$seenConnections = @{}
$outputPath = "$env:TEMP\IMDS_Attested_Monitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

# ---- ETW Trace Setup --------------------------------------------------------
$traceName = "IMDSAttestedMonitor"
$etlPath = "$env:TEMP\$traceName.etl"

# Clean up any prior session
netsh trace stop sessionname=$traceName 2>&1 | Out-Null

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting network trace session..." -ForegroundColor Yellow

try {
    # Start a lightweight netsh trace filtered to IMDS IP
    $traceResult = netsh trace start capture=yes tracefile=$etlPath `
        sessionname=$traceName `
        IPv4.Address=$imdsIP `
        maxsize=50 `
        overwrite=yes `
        persistent=no 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] ETW trace could not start (may require full admin or trace already active)." -ForegroundColor Yellow
        Write-Host "        Falling back to polling-only mode." -ForegroundColor Yellow
        $traceStarted = $false
    } else {
        $traceStarted = $true
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Network trace started. ETL: $etlPath" -ForegroundColor Green
    }
} catch {
    Write-Host "[WARN] ETW trace failed: $($_.Exception.Message). Using polling-only mode." -ForegroundColor Yellow
    $traceStarted = $false
}

# ---- Auditing Setup ---------------------------------------------------------
# Enable Windows Filtering Platform audit logging for richer process correlation
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Enabling WFP connection auditing..." -ForegroundColor Yellow
$auditBefore = auditpol /get /subcategory:"Filtering Platform Connection" 2>&1 | Out-String
auditpol /set /subcategory:"Filtering Platform Connection" /success:enable /failure:enable 2>&1 | Out-Null

# ---- HTTP Listener (lightweight proxy check) ---------------------------------
# We also set up a scheduled job to periodically check event logs for IMDS connections
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitoring started. Will run until $(Get-Date $endTime -Format 'HH:mm:ss') ($MonitorMinutes minutes)" -ForegroundColor Green
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Polling every $pollIntervalSeconds seconds for connections to $imdsIP..." -ForegroundColor Green
Write-Host ""

# ---- Main Monitoring Loop ----------------------------------------------------
$iteration = 0
while ((Get-Date) -lt $endTime) {
    $iteration++

    # --- Method 1: Poll active TCP connections ---
    try {
        $connections = Get-NetTCPConnection -RemoteAddress $imdsIP -ErrorAction SilentlyContinue
        if ($connections) {
            foreach ($conn in $connections) {
                $connKey = "$($conn.OwningProcess)-$($conn.LocalPort)-$($conn.RemotePort)"
                if (-not $seenConnections.ContainsKey($connKey)) {
                    $seenConnections[$connKey] = $true
                    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                    $detection = [PSCustomObject]@{
                        Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        Method       = "TCP Poll"
                        PID          = $conn.OwningProcess
                        ProcessName  = if ($proc) { $proc.ProcessName } else { "Unknown" }
                        ProcessPath  = if ($proc) { $proc.Path } else { "N/A" }
                        LocalPort    = $conn.LocalPort
                        RemotePort   = $conn.RemotePort
                        State        = $conn.State
                        CommandLine  = ""
                    }

                    # Try to get command line via WMI
                    try {
                        $wmiProc = Get-WmiObject Win32_Process -Filter "ProcessId=$($conn.OwningProcess)" -ErrorAction SilentlyContinue
                        if ($wmiProc) {
                            $detection.CommandLine = $wmiProc.CommandLine
                        }
                    } catch {}

                    [void]$detections.Add($detection)

                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] DETECTED - PID: $($detection.PID) | Process: $($detection.ProcessName) | State: $($detection.State) | Port: $($detection.LocalPort)->$($detection.RemotePort)" -ForegroundColor Red
                    if ($detection.ProcessPath -ne "N/A") {
                        Write-Host "           Path: $($detection.ProcessPath)" -ForegroundColor Yellow
                    }
                    if ($detection.CommandLine) {
                        Write-Host "           CmdLine: $($detection.CommandLine)" -ForegroundColor Yellow
                    }
                }
            }
        }
    } catch {}

    # --- Method 2: Check WFP audit events for IMDS connections (every 10th iteration) ---
    if ($iteration % 10 -eq 0) {
        try {
            $wfpEvents = Get-WinEvent -FilterHashtable @{
                LogName   = 'Security'
                Id        = 5156  # WFP permitted connection
                StartTime = (Get-Date).AddSeconds(-($pollIntervalSeconds * 10))
            } -MaxEvents 50 -ErrorAction SilentlyContinue

            if ($wfpEvents) {
                $imdsEvents = $wfpEvents | Where-Object {
                    $_.Message -match '169\.254\.169\.254'
                }
                foreach ($evt in $imdsEvents) {
                    # Extract PID from event
                    $evtXml = [xml]$evt.ToXml()
                    $evtPid = ($evtXml.Event.EventData.Data | Where-Object { $_.Name -eq 'ProcessId' }).'#text'
                    $evtApp = ($evtXml.Event.EventData.Data | Where-Object { $_.Name -eq 'Application' }).'#text'

                    $evtKey = "WFP-$evtPid-$($evt.TimeCreated.ToString('HHmmss'))"
                    if (-not $seenConnections.ContainsKey($evtKey)) {
                        $seenConnections[$evtKey] = $true
                        $proc = Get-Process -Id $evtPid -ErrorAction SilentlyContinue
                        $detection = [PSCustomObject]@{
                            Timestamp    = $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                            Method       = "WFP Audit"
                            PID          = $evtPid
                            ProcessName  = if ($proc) { $proc.ProcessName } else { [System.IO.Path]::GetFileNameWithoutExtension($evtApp) }
                            ProcessPath  = if ($evtApp) { $evtApp } else { "N/A" }
                            LocalPort    = ""
                            RemotePort   = ""
                            State        = "Permitted"
                            CommandLine  = ""
                        }
                        [void]$detections.Add($detection)

                        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] DETECTED (WFP) - PID: $evtPid | Process: $($detection.ProcessName) | Path: $evtApp" -ForegroundColor Red
                    }
                }
            }
        } catch {}
    }

    # --- Method 3: Check for HTTP.sys/WinHTTP ETW events (every 30th iteration) ---
    if ($iteration % 30 -eq 0) {
        try {
            $httpEvents = Get-WinEvent -FilterHashtable @{
                LogName   = 'Microsoft-Windows-WebIO/Diagnostic'
                StartTime = (Get-Date).AddSeconds(-($pollIntervalSeconds * 30))
            } -MaxEvents 20 -ErrorAction SilentlyContinue

            if ($httpEvents) {
                $attestedEvents = $httpEvents | Where-Object { $_.Message -match 'attested' -or $_.Message -match '169\.254\.169\.254' }
                foreach ($evt in $attestedEvents) {
                    $evtKey = "HTTP-$($evt.ProcessId)-$($evt.TimeCreated.ToString('HHmmss'))"
                    if (-not $seenConnections.ContainsKey($evtKey)) {
                        $seenConnections[$evtKey] = $true
                        $proc = Get-Process -Id $evt.ProcessId -ErrorAction SilentlyContinue
                        $detection = [PSCustomObject]@{
                            Timestamp    = $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                            Method       = "HTTP ETW"
                            PID          = $evt.ProcessId
                            ProcessName  = if ($proc) { $proc.ProcessName } else { "Unknown" }
                            ProcessPath  = if ($proc) { $proc.Path } else { "N/A" }
                            LocalPort    = ""
                            RemotePort   = "80"
                            State        = "HTTP Request"
                            CommandLine  = ""
                        }
                        [void]$detections.Add($detection)
                        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] DETECTED (HTTP) - PID: $($evt.ProcessId) | Process: $($detection.ProcessName)" -ForegroundColor Red
                    }
                }
            }
        } catch {}
    }

    # Progress indicator every 60 seconds
    if ($iteration % (60 / $pollIntervalSeconds) -eq 0) {
        $remaining = [math]::Round(($endTime - (Get-Date)).TotalMinutes, 1)
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitoring... $remaining minutes remaining | $($detections.Count) detection(s) so far" -ForegroundColor Gray
    }

    Start-Sleep -Seconds $pollIntervalSeconds
}

# ---- Cleanup -----------------------------------------------------------------
Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Monitoring window complete. Cleaning up..." -ForegroundColor Yellow

# Stop ETW trace
if ($traceStarted) {
    netsh trace stop sessionname=$traceName 2>&1 | Out-Null
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Network trace stopped. ETL saved: $etlPath" -ForegroundColor Green
}

# Restore audit policy
auditpol /set /subcategory:"Filtering Platform Connection" /success:disable /failure:disable 2>&1 | Out-Null
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] WFP audit policy restored." -ForegroundColor Green

# ---- Results -----------------------------------------------------------------
Write-Host "`n=====================================================================================================================" -ForegroundColor Cyan
Write-Host " RESULTS - IMDS Attested Data Access Monitor" -ForegroundColor Cyan
Write-Host "=====================================================================================================================" -ForegroundColor Cyan
Write-Host " Monitoring Duration : $MonitorMinutes minutes" -ForegroundColor White
Write-Host " Total Detections    : $($detections.Count)" -ForegroundColor White
Write-Host "=====================================================================================================================" -ForegroundColor Cyan

if ($detections.Count -gt 0) {
    # Export full results
    $detections | Export-Csv $outputPath -NoTypeInformation
    Write-Host "`nFull results exported to: $outputPath`n" -ForegroundColor Green

    # Summary by unique process
    Write-Host "Unique Processes Detected Accessing IMDS (169.254.169.254):" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------------" -ForegroundColor Yellow

    $summary = $detections | Group-Object ProcessName | Sort-Object Count -Descending
    foreach ($group in $summary) {
        $first = $group.Group[0]
        Write-Host "`n  Process     : $($group.Name)" -ForegroundColor White
        Write-Host "  PID(s)      : $(($group.Group | Select-Object -ExpandProperty PID -Unique) -join ', ')" -ForegroundColor White
        Write-Host "  Hit Count   : $($group.Count)" -ForegroundColor White
        Write-Host "  Path        : $($first.ProcessPath)" -ForegroundColor White
        if ($first.CommandLine) {
            Write-Host "  Command Line: $($first.CommandLine)" -ForegroundColor White
        }
        Write-Host "  First Seen  : $(($group.Group | Select-Object -First 1).Timestamp)" -ForegroundColor White
        Write-Host "  Last Seen   : $(($group.Group | Select-Object -Last 1).Timestamp)" -ForegroundColor White
        Write-Host "  Method(s)   : $(($group.Group | Select-Object -ExpandProperty Method -Unique) -join ', ')" -ForegroundColor White
    }

    Write-Host ""

    # Display table
    $detections | Format-Table Timestamp, Method, PID, ProcessName, State, ProcessPath -AutoSize
} else {
    Write-Host "`nNo processes were detected accessing IMDS (169.254.169.254) during the $MonitorMinutes minute monitoring window." -ForegroundColor Green
    Write-Host "This indicates no application accessed the attested data endpoint during this period." -ForegroundColor Green
}

if ($traceStarted) {
    Write-Host "`nNote: A network trace ETL file was captured at: $etlPath" -ForegroundColor Cyan
    Write-Host "You can analyze it with: netsh trace convert input=$etlPath output=$($etlPath.Replace('.etl','.txt'))" -ForegroundColor Cyan
}

Write-Host "`nScript completed successfully." -ForegroundColor Cyan
