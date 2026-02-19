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

    For more details, see: https://aka.ms/AzVmFirewallValidation

.SYNOPSIS
    Validates Windows Firewall configuration and checks connectivity to Azure service endpoints.

.DESCRIPTION
    This script performs the following checks:
    - Verifies Windows Firewall service status
    - Checks firewall profile states (Domain, Private, Public)
    - Validates RDP (3389), WinRM (5985/5986), SMB (445), HTTP/HTTPS port accessibility
    - Tests connectivity to comprehensive Azure endpoints including:
      * Infrastructure: IMDS, WireServer, KMS, Time Sync
      * Management: ARM, Azure Portal
      * Identity: Azure AD/Entra ID, Microsoft Graph
      * Storage: Blob, File, Table, Queue
      * Monitoring: Azure Monitor, Log Analytics, Application Insights
      * Backup: Azure Backup, Site Recovery
      * Security: Key Vault, Defender
      * Updates: Windows Update, WSUS
      * Certificates: DigiCert, Microsoft CRL/OCSP
      * DevOps: Azure DevOps, NuGet
      * Containers: ACR, MCR
    - Checks PerfInsights storage account connectivity if configured
    - Identifies blocking rules for Azure infrastructure IPs
    - Provides remediation guidance for detected issues

.PARAMETER MockConfig
    Path to a JSON file with mock test results for local/unit testing.
    When provided, skips admin check and all live queries — uses mock data instead.
    See mock_config_sample.json for the expected schema.

.NOTES
    Requires administrator privileges (unless -MockConfig is used).
    Tested on Windows Server 2016+.

.EXAMPLE
    Run as administrator:
    PS> .\Windows_Firewall_Rules_Validation.ps1

.EXAMPLE
    Run locally with mock data (set $MockConfig at top of script):
    $MockConfig = '.\mock_config_sample.json'
#>
# Set $MockConfig to the path of the mock JSON file.
# Set $isMock to $true for local testing, $false for live (Run Command) mode.
$MockConfig = '.\mock_config_sample.json'
$isMock = $false

# ---- Safety checks -----------------------------------------------------------
if (-not $isMock) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Please run this script as Administrator." -ForegroundColor Red
        exit 1
    }
}

# ---- Load mock data if provided ----------------------------------------------
$mock = $null
if ($isMock) {
    if (-not (Test-Path $MockConfig)) {
        Write-Host "Mock config not found: $MockConfig" -ForegroundColor Red; exit 1
    }
    $mock = Get-Content $MockConfig -Raw | ConvertFrom-Json
    Write-Host "** MOCK MODE - using $MockConfig **" -ForegroundColor Yellow
}

# ---- Helper Functions --------------------------------------------------------
$tFmt = "{0,-52} {1}"
function Write-OK   { param([string]$Msg) Write-Host ($tFmt -f $Msg, "OK")   -ForegroundColor Green }
function Write-FAIL { param([string]$Msg) Write-Host ($tFmt -f $Msg, "FAIL") -ForegroundColor Red }
function Write-WARN { param([string]$Msg) Write-Host ($tFmt -f $Msg, "WARN") -ForegroundColor Yellow }
function Write-Sec  { param([string]$S) Write-Host "-- $S --" -ForegroundColor Cyan }

# ---- Main Logic --------------------------------------------------------------
$issues = @()
$passCount = 0
$failCount = 0

Write-Host "=== Firewall and Endpoint Validation ===" -ForegroundColor Cyan
Write-Host ($tFmt -f "Check","Status") -ForegroundColor DarkGray
Write-Host ($tFmt -f ("-"*52),("-"*6)) -ForegroundColor DarkGray

# --- Firewall Service ---
if ($isMock) {
    $fwStatus = $mock.FirewallService
} else {
    $svc = Get-Service -Name MpsSvc -ErrorAction SilentlyContinue
    $fwStatus = if ($svc) { $svc.Status.ToString() } else { "NotFound" }
}
if ($fwStatus -eq 'Running') {
    Write-OK "Firewall Service: Running"; $passCount++
} else {
    Write-FAIL "Firewall Service: $fwStatus"; $failCount++
    $issues += "Firewall svc $fwStatus"
}

# --- Firewall Profiles ---
if ($isMock) {
    $profileData = $mock.FirewallProfiles
} else {
    try {
        $profileData = Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Enabled = [bool]$_.Enabled
                DefaultInboundAction = $_.DefaultInboundAction.ToString()
                DefaultOutboundAction = $_.DefaultOutboundAction.ToString()
            }
        }
    } catch {
        Write-FAIL "Profiles: $($_.Exception.Message)"; $failCount++
        $issues += "Cannot read profiles"
        $profileData = @()
    }
}
foreach ($p in $profileData) {
    $s = if ($p.Enabled) { "On" } else { "Off" }
    $line = "$($p.Name):$s In=$($p.DefaultInboundAction) Out=$($p.DefaultOutboundAction)"
    if ($p.DefaultOutboundAction -eq 'Block') {
        Write-WARN $line; $issues += "$($p.Name) blocks outbound"
    } else { Write-OK $line }
}

# --- Critical Ports ---
Write-Sec "Ports"
$criticalPorts = @(
    @{ N = "RDP";   P = 3389 }, @{ N = "WinRM";  P = 5985 },
    @{ N = "WinRM-S"; P = 5986 }, @{ N = "SMB"; P = 445 },
    @{ N = "HTTP";  P = 80 },  @{ N = "HTTPS"; P = 443 }
)
foreach ($pi in $criticalPorts) {
    if ($isMock) {
        # Mock: look up port result from config — "Allow", "Block", or "NoRule"
        $portResult = "NoRule"
        $mockPort = $mock.PortRules | Where-Object { $_.Port -eq $pi.P }
        if ($mockPort) { $portResult = $mockPort.Result }
        switch ($portResult) {
            'Block'  { Write-FAIL "$($pi.N)/$($pi.P)"; $failCount++; $issues += "$($pi.N)/$($pi.P) blocked" }
            'Allow'  { Write-OK "$($pi.N)/$($pi.P)"; $passCount++ }
            default  { Write-WARN "$($pi.N)/$($pi.P) no rule" }
        }
    } else {
        $block = Get-NetFirewallRule -ErrorAction SilentlyContinue |
            Where-Object { $_.Enabled -and $_.Action -eq 'Block' -and $_.Direction -eq 'Inbound' } |
            Where-Object {
                $pf = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
                $pf.LocalPort -eq $pi.P -or $pf.LocalPort -eq 'Any'
            }
        $allow = Get-NetFirewallRule -ErrorAction SilentlyContinue |
            Where-Object { $_.Enabled -and $_.Action -eq 'Allow' -and $_.Direction -eq 'Inbound' } |
            Where-Object {
                $pf = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
                $pf.LocalPort -eq $pi.P -or $pf.LocalPort -eq 'Any'
            }
        if ($block) {
            Write-FAIL "$($pi.N)/$($pi.P)"; $failCount++
            $issues += "$($pi.N)/$($pi.P) blocked"
        } elseif ($allow) {
            Write-OK "$($pi.N)/$($pi.P)"; $passCount++
        } else {
            Write-WARN "$($pi.N)/$($pi.P) no rule"
        }
    }
}

# --- Endpoint Connectivity ---
Write-Sec "Endpoints"
$ep = @(
    # Infrastructure (Critical)
    @{ N="IMDS";           H="169.254.169.254";  P=80;   C="Infra" }
    @{ N="WireServer";     H="168.63.129.16";    P=80;   C="Infra" }
    @{ N="KMS";            H="azkms.core.windows.net"; P=1688; C="Infra" }
    @{ N="KMS-Alt";        H="kms.core.windows.net";   P=1688; C="Infra" }
    @{ N="Time";           H="time.windows.com";        P=123;  C="Infra" }
    # Management
    @{ N="ARM";            H="management.azure.com";       P=443; C="Mgmt" }
    @{ N="ARM-Classic";    H="management.core.windows.net"; P=443; C="Mgmt" }
    @{ N="Portal";         H="portal.azure.com";           P=443; C="Mgmt" }
    # Identity
    @{ N="AAD";            H="login.microsoftonline.com"; P=443; C="Identity" }
    @{ N="Graph";          H="graph.microsoft.com";       P=443; C="Identity" }
    @{ N="AAD-Legacy";     H="graph.windows.net";         P=443; C="Identity" }
    @{ N="AAD-USGov";      H="login.microsoftonline.us";  P=443; C="Identity" }
    # Storage
    @{ N="Blob";           H="blob.core.windows.net";  P=443; C="Storage" }
    @{ N="File";           H="file.core.windows.net";  P=443; C="Storage" }
    @{ N="Table";          H="table.core.windows.net"; P=443; C="Storage" }
    @{ N="Queue";          H="queue.core.windows.net"; P=443; C="Storage" }
    # Monitoring
    @{ N="Monitor";        H="monitor.azure.com";                P=443; C="Monitor" }
    @{ N="LogAnalytics";   H="ods.opinsights.azure.com";        P=443; C="Monitor" }
    @{ N="LogAnalyticsCfg"; H="oms.opinsights.azure.com";       P=443; C="Monitor" }
    @{ N="AppInsights";    H="dc.applicationinsights.azure.com"; P=443; C="Monitor" }
    @{ N="AppInsights-L";  H="dc.services.visualstudio.com";    P=443; C="Monitor" }
    # Backup
    @{ N="Backup";         H="backup.windowsazure.com";                  P=443; C="Backup" }
    @{ N="SiteRecovery";   H="hypervrecoverymanager.windowsazure.com";   P=443; C="Backup" }
    # Security
    @{ N="KeyVault";       H="vault.azure.net";        P=443; C="Security" }
    @{ N="SecurityCtr";    H="security.azure.com";     P=443; C="Security" }
    @{ N="Defender";       H="wdcp.microsoft.com";     P=443; C="Security" }
    @{ N="DefenderATP";    H="wdcpalt.microsoft.com";  P=443; C="Security" }
    # Updates
    @{ N="WinUpdate";      H="windowsupdate.microsoft.com";  P=443; C="Updates" }
    @{ N="WinUpdate-Alt";  H="update.microsoft.com";         P=443; C="Updates" }
    @{ N="WSUS";           H="download.windowsupdate.com";   P=443; C="Updates" }
    # Certificates
    @{ N="DigiCert-AIA";   H="cacerts.digicert.com";    P=80; C="Certs" }
    @{ N="DigiCert-CRL";   H="crl3.digicert.com";       P=80; C="Certs" }
    @{ N="DigiCert-OCSP";  H="ocsp.digicert.com";       P=80; C="Certs" }
    @{ N="MS-CRL";         H="crl.microsoft.com";       P=80; C="Certs" }
    @{ N="MS-OCSP";        H="oneocsp.microsoft.com";   P=80; C="Certs" }
    @{ N="MS-PKI";         H="www.microsoft.com";       P=80; C="Certs" }
    # DevOps
    @{ N="DevOps";         H="dev.azure.com";                  P=443; C="DevOps" }
    @{ N="NuGet";          H="api.nuget.org";                  P=443; C="DevOps" }
    @{ N="VSMarket";       H="marketplace.visualstudio.com";   P=443; C="DevOps" }
    # Containers
    @{ N="ACR";            H="azurecr.io";           P=443; C="Containers" }
    @{ N="MCR";            H="mcr.microsoft.com";    P=443; C="Containers" }
)

# Build a lookup of mock endpoint results: "host:port" -> true/false
$mockEpLookup = @{}
if ($isMock -and $mock.Endpoints) {
    foreach ($me in $mock.Endpoints) { $mockEpLookup["$($me.Host):$($me.Port)"] = $me.Pass }
}

foreach ($e in $ep) {
    $key = "$($e.H):$($e.P)"
    if ($isMock) {
        $passed = if ($mockEpLookup.ContainsKey($key)) { $mockEpLookup[$key] } else { $true }
    } else {
        $passed = $false
        try {
            $r = Test-NetConnection -ComputerName $e.H -Port $e.P -WarningAction SilentlyContinue -ErrorAction Stop
            $passed = $r.TcpTestSucceeded
        } catch { }
    }
    if ($passed) {
        Write-OK "$($e.N) $key"; $passCount++
    } else {
        Write-FAIL "$($e.N) $key"; $failCount++
        $issues += "$($e.N) $key"
    }
}

# --- PerfInsights Storage Account ---
Write-Sec "PerfInsights"
$perfInsightsFound = $false
if ($isMock) {
    if ($mock.PerfInsights -and $mock.PerfInsights.StorageAccountName) {
        $perfInsightsFound = $true
        $saEndpoint = "$($mock.PerfInsights.StorageAccountName).blob.core.windows.net"
        $saPass = if ($null -ne $mock.PerfInsights.Pass) { $mock.PerfInsights.Pass } else { $true }
        if ($saPass) {
            Write-OK "PerfInsights SA ${saEndpoint}:443"; $passCount++
        } else {
            Write-FAIL "PerfInsights SA ${saEndpoint}:443"; $failCount++
            $issues += "PerfInsights SA ${saEndpoint}:443"
        }
    }
} else {
    $perfDiagPath = "C:\Packages\Plugins\Microsoft.Azure.Performance.Diagnostics.AzurePerformanceDiagnostics"
    if (Test-Path $perfDiagPath) {
        $latest = Get-ChildItem -Path $perfDiagPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { try { [void][version]$_.Name; $true } catch { $false } } |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        if ($latest) {
            $settingsDir = Join-Path $latest.FullName "RuntimeSettings"
            if (-not (Test-Path $settingsDir)) {
                $settingsDir = Join-Path $perfDiagPath "RuntimeSettings"
            }
            $settingsFiles = Get-ChildItem -Path $settingsDir -Filter "*.settings" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($settingsFiles) {
                try {
                    $json = Get-Content $settingsFiles.FullName -Raw | ConvertFrom-Json
                    $storageAcct = $null
                    if ($json.runtimeSettings) {
                        $storageAcct = $json.runtimeSettings[0].handlerSettings.publicSettings.StorageAccountName
                    } elseif ($json.StorageAccountName) {
                        $storageAcct = $json.StorageAccountName
                    }
                    if ($storageAcct) {
                        $perfInsightsFound = $true
                        $saEndpoint = "$storageAcct.blob.core.windows.net"
                        try {
                            $r = Test-NetConnection -ComputerName $saEndpoint -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop
                            if ($r.TcpTestSucceeded) {
                                Write-OK "PerfInsights SA ${saEndpoint}:443"; $passCount++
                            } else {
                                Write-FAIL "PerfInsights SA ${saEndpoint}:443"; $failCount++
                                $issues += "PerfInsights SA ${saEndpoint}:443"
                            }
                        } catch {
                            Write-FAIL "PerfInsights SA ${saEndpoint}:443"; $failCount++
                            $issues += "PerfInsights SA ${saEndpoint}:443"
                        }
                    }
                } catch {
                    Write-WARN "PerfInsights: could not parse settings"
                }
            }
        }
    }
}
if (-not $perfInsightsFound) { Write-OK "PerfInsights: not configured (skipped)" }

# --- WSUS Configuration ---
Write-Sec "WSUS"
$wsusConfigured = $false
if ($isMock) {
    if ($mock.WSUS -and $mock.WSUS.WUServer) {
        $wsusConfigured = $true
        $wuServer = $mock.WSUS.WUServer
        $wuUri = [System.Uri]$wuServer
        $wuHost = $wuUri.Host
        $wuPort = if ($wuUri.Port -gt 0) { $wuUri.Port } else { 443 }
        $wuPass = if ($null -ne $mock.WSUS.Pass) { $mock.WSUS.Pass } else { $true }
        Write-OK "WSUS configured: $wuServer"; $passCount++
        if ($wuPass) {
            Write-OK "WSUS reachable: ${wuHost}:${wuPort}"; $passCount++
        } else {
            Write-FAIL "WSUS reachable: ${wuHost}:${wuPort}"; $failCount++
            $issues += "WSUS server unreachable: ${wuHost}:${wuPort}"
        }
    }
} else {
    $wuRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (Test-Path $wuRegPath) {
        $wuServer = (Get-ItemProperty -Path $wuRegPath -Name WUServer -ErrorAction SilentlyContinue).WUServer
        if ($wuServer) {
            $wsusConfigured = $true
            Write-OK "WSUS configured: $wuServer"; $passCount++
            # Parse host from URL (e.g. http://wsus.contoso.com:8530)
            try {
                $wuUri = [System.Uri]$wuServer
                $wuHost = $wuUri.Host
                $wuPort = if ($wuUri.Port -gt 0) { $wuUri.Port } else { 443 }
                $r = Test-NetConnection -ComputerName $wuHost -Port $wuPort -WarningAction SilentlyContinue -ErrorAction Stop
                if ($r.TcpTestSucceeded) {
                    Write-OK "WSUS reachable: ${wuHost}:${wuPort}"; $passCount++
                } else {
                    Write-FAIL "WSUS reachable: ${wuHost}:${wuPort}"; $failCount++
                    $issues += "WSUS server unreachable: ${wuHost}:${wuPort}"
                }
            } catch {
                Write-FAIL "WSUS reachable: $wuServer"; $failCount++
                $issues += "WSUS server unreachable: $wuServer"
            }
        }
    }
}
if (-not $wsusConfigured) { Write-OK "WSUS: not configured (using Windows Update)" }

# --- Blocking Rules on Azure IPs ---
Write-Sec "Azure IP Blocks"
if ($isMock) {
    if ($mock.AzureIPBlockRules -and $mock.AzureIPBlockRules.Count -gt 0) {
        foreach ($br in $mock.AzureIPBlockRules) { Write-FAIL $br; $failCount++ }
        $issues += "FW rules block Azure IPs"
    } else {
        Write-OK "No block rules for Azure IPs"; $passCount++
    }
} else {
    $azureIPs = @("169.254.169.254", "168.63.129.16")
    try {
        $blockRules = Get-NetFirewallRule -ErrorAction SilentlyContinue |
            Where-Object { $_.Enabled -and $_.Action -eq 'Block' } |
            ForEach-Object {
                $af = $_ | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
                foreach ($ip in $azureIPs) {
                    if ($af.RemoteAddress -contains $ip -or
                       ($af.RemoteAddress -eq 'Any' -and $_.Direction -eq 'Outbound')) {
                        "$($_.DisplayName) [$($_.Direction)] -> $ip"
                    }
                }
            }
        if ($blockRules) {
            foreach ($br in $blockRules) { Write-FAIL $br; $failCount++ }
            $issues += "FW rules block Azure IPs"
        } else {
            Write-OK "No block rules for Azure IPs"; $passCount++
        }
    } catch { Write-WARN "Could not scan block rules" }
}

# --- WinRM & RDP Rules ---
Write-Sec "WinRM/RDP"
if ($isMock) {
    $winrmCount = if ($null -ne $mock.WinRMAllowRules) { $mock.WinRMAllowRules } else { 0 }
    $rdpCount   = if ($null -ne $mock.RDPAllowRules)   { $mock.RDPAllowRules }   else { 0 }
} else {
    $winrmCount = (Get-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -and $_.Action -eq 'Allow' } | Measure-Object).Count
    $rdpCount = (Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -and $_.Action -eq 'Allow' } | Measure-Object).Count
}
if ($winrmCount -gt 0) { Write-OK "WinRM: $winrmCount allow rule(s)"; $passCount++ }
else { Write-FAIL "WinRM: no allow rules"; $failCount++; $issues += "WinRM no allow rules" }
if ($rdpCount -gt 0) { Write-OK "RDP: $rdpCount allow rule(s)"; $passCount++ }
else { Write-FAIL "RDP: no allow rules"; $failCount++; $issues += "RDP no allow rules" }

# --- Network Routing / ExpressRoute Detection ---
Write-Sec "Routing"
if ($isMock) {
    $ri = $mock.Routing
    if ($ri) {
        $defGw = $ri.DefaultGateway
        $learnedCount = [int]$ri.LearnedRouteCount
        $forcedTunnel = [bool]$ri.ForcedTunneling
    } else {
        $defGw = "10.0.0.1"; $learnedCount = 0; $forcedTunnel = $false
    }
} else {
    $defRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | Select-Object -First 1
    $defGw = if ($defRoute) { $defRoute.NextHop } else { "none" }
    $learnedCount = 0
    $forcedTunnel = $false
    if ($defRoute) {
        $ifIdx = $defRoute.InterfaceIndex
        $learned = Get-NetRoute -InterfaceIndex $ifIdx -ErrorAction SilentlyContinue | Where-Object {
            $_.NextHop -ne "0.0.0.0" -and $_.NextHop -ne "::" -and
            $_.DestinationPrefix -ne "0.0.0.0/0" -and
            $_.DestinationPrefix -ne "255.255.255.255/32" -and
            -not $_.DestinationPrefix.StartsWith("ff") -and
            -not $_.DestinationPrefix.StartsWith("fe80")
        }
        $learnedCount = ($learned | Measure-Object).Count
        $allDef = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue)
        if ($allDef.Count -gt 1) { $forcedTunnel = $true }
    }
}
if ($forcedTunnel) {
    Write-WARN "Forced tunneling detected -- internet via gateway"
    $issues += "Forced tunneling detected"
}
if ($learnedCount -gt 10) {
    Write-WARN "Routing: $learnedCount routes (ExpressRoute/VPN likely)"
    $issues += "ExpressRoute/VPN likely ($learnedCount routes)"
} elseif ($learnedCount -gt 0) {
    Write-OK "Routing: $learnedCount learned routes"; $passCount++
} else {
    Write-OK "Routing: default only (no ExpressRoute/VPN detected)"; $passCount++
}

# --- Summary ---
Write-Host "`n=== RESULT: $passCount OK / $failCount FAIL ===" -ForegroundColor Cyan
if ($failCount -gt 0) {
    Write-Host "Docs: https://learn.microsoft.com/azure/virtual-machines/troubleshooting-guide"
}
Write-Host "Ref: https://aka.ms/AzVmFirewallValidation"
