#Requires -Version 5.1
<#
.SYNOPSIS
    Validates guest network configuration and IMDS reachability on an Azure Windows VM.
.DESCRIPTION
    Checks the most common in-guest network misconfigurations impacting VM management:
      1. NIC operational state and DHCP/static assignment
      2. DNS server configuration sanity
      3. Default route and gateway presence
      4. Reachability to WireServer (168.63.129.16)
      5. Reachability and response from IMDS endpoint (169.254.169.254)

    Designed for Azure Run Command: no Az module, no internet, PS 5.1 only,
    output fits within the 4 KB portal limit.
.PARAMETER MockConfig
    Path to a JSON file that replaces live system reads for offline testing.
.NOTES
    Author  : CSS Core Compute SPM
    Version : 1.0.0
    Tool ID : RC-007
    Bucket  : Network / Cant-RDP-SSH / AGEX
    Repo    : Azure/azure-support-scripts  RunCommand/Windows/Windows_Network_IMDS_Reachability
#>
[CmdletBinding()]
param(
  [string]$MockConfig,
  [ValidateSet('healthy','degraded','broken')]
  [string]$MockProfile = 'degraded'
)
$ErrorActionPreference = 'Continue'

function Pad($s, $n) { $s = "$s"; if ($s.Length -ge $n) { $s.Substring(0,$n) } else { $s.PadRight($n) } }
$W = 44
$findings = [System.Collections.Generic.List[psobject]]::new()

function Add-Row($check, $status, $detail = '') {
    $script:findings.Add([PSCustomObject]@{ Check = $check; Status = $status; Detail = $detail })
    Write-Output ('{0} {1}' -f (Pad $check $W), $status)
}

$mock = $null
if ($MockConfig -and (Test-Path $MockConfig)) {
    $mock = Get-Content $MockConfig -Raw | ConvertFrom-Json
}

Write-Output '=== Windows Network + IMDS Reachability ==='
Write-Output ('{0} {1}' -f (Pad 'Check' $W), 'Status')
Write-Output (('-' * $W) + ' ------')


$usedMock = $false
if($MockConfig -and (Test-Path $MockConfig)){
  if($mock.profiles -and $mock.profiles.$MockProfile){
    $usedMock = $true
    foreach($i in $mock.profiles.$MockProfile){ Add-Row $i.name $i.status $i.detail }
  }
}
if(-not $usedMock){

# -- NICs ---------------------------------------------------------------------
Write-Output '-- NIC Configuration --'
if ($mock) {
    $nics = $mock.nics
} else {
    $nics = Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.IPEnabled -eq $true } |
        ForEach-Object {
            [PSCustomObject]@{
                description = $_.Description
                dhcpEnabled = $_.DHCPEnabled
                ipAddress   = @($_.IPAddress)[0]
                dnsServers  = @($_.DNSServerSearchOrder)
                gateway     = @($_.DefaultIPGateway)[0]
            }
        }
}

if (@($nics).Count -eq 0) {
    Add-Row 'IP-enabled NIC present' 'FAIL' 'No IP-enabled adapters found'
} else {
    Add-Row 'IP-enabled NIC present' 'OK' "Count=$(@($nics).Count)"
    foreach ($nic in $nics | Select-Object -First 2) {
        $dhcpLabel = if ($nic.dhcpEnabled) { 'DHCP' } else { 'Static' }
        Add-Row "NIC: $($nic.description)" 'OK' "$dhcpLabel IP=$($nic.ipAddress)"

        $dnsCount = @($nic.dnsServers).Count
        $dnsStatus = if ($dnsCount -eq 0) { 'FAIL' } elseif ($dnsCount -gt 4) { 'WARN' } else { 'OK' }
        Add-Row "DNS servers configured" $dnsStatus "Count=$dnsCount"

        $gwStatus = if ([string]::IsNullOrEmpty($nic.gateway)) { 'FAIL' } else { 'OK' }
        Add-Row "Default gateway present" $gwStatus "$($nic.gateway)"
    }
}

# -- Routing ------------------------------------------------------------------
Write-Output '-- Routing --'
if ($mock) {
    $hasDefaultRoute = $mock.route.hasDefaultRoute
} else {
    $routes = Get-WmiObject Win32_IP4RouteTable -ErrorAction SilentlyContinue |
        Where-Object { $_.Destination -eq '0.0.0.0' -and $_.Mask -eq '0.0.0.0' }
    $hasDefaultRoute = (@($routes).Count -gt 0)
}
Add-Row 'Default route 0.0.0.0/0 exists' (if ($hasDefaultRoute) { 'OK' } else { 'FAIL' }) ''

# -- WireServer ---------------------------------------------------------------
Write-Output '-- Azure Fabric Endpoint --'
if ($mock) {
    $wireServer = $mock.fabric.wireServerReachable
} else {
    $wireServer = $false
    try {
        $wireServer = Test-NetConnection 168.63.129.16 -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue
    } catch {
        $ping = Test-Connection 168.63.129.16 -Count 1 -Quiet -ErrorAction SilentlyContinue
        $wireServer = [bool]$ping
    }
}
Add-Row 'WireServer 168.63.129.16 reachable' (if ($wireServer) { 'OK' } else { 'FAIL' }) ''

# -- IMDS ---------------------------------------------------------------------
Write-Output '-- IMDS Endpoint --'
if ($mock) {
    $imdsReachable = $mock.imds.reachable
    $imdsHttp200   = $mock.imds.http200
} else {
    $imdsReachable = $false
    $imdsHttp200   = $false
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Method GET -TimeoutSec 5 `
            -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' `
            -Headers @{ Metadata = 'true' } -ErrorAction Stop
        $imdsReachable = $true
        $imdsHttp200   = ($resp.StatusCode -eq 200)
    } catch {
        try {
            $tcp = Test-NetConnection 169.254.169.254 -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue
            $imdsReachable = [bool]$tcp
        } catch { $imdsReachable = $false }
    }
}

Add-Row 'IMDS TCP endpoint reachable' (if ($imdsReachable) { 'OK' } else { 'FAIL' }) ''
Add-Row 'IMDS metadata response HTTP 200' (if ($imdsHttp200) { 'OK' } elseif ($imdsReachable) { 'WARN' } else { 'FAIL' }) ''

}

$fail = @($findings | Where-Object Status -eq 'FAIL').Count
$warn = @($findings | Where-Object Status -eq 'WARN').Count
Write-Output '-- Decision --'
Add-Row 'Likely cause severity' $(if($fail -gt 0){'FAIL'}elseif($warn -gt 0){'WARN'}else{'OK'}) $(if($fail -gt 0){'Hard configuration/service break'}elseif($warn -gt 0){'Configuration drift or transient condition'}else{'No blocking signals'})
Add-Row 'Next action' 'OK' $(if($fail -gt 0){'Follow README interpretation and remediate FAIL rows first'}elseif($warn -gt 0){'Review WARN rows and re-run after targeted fix'}else{'No immediate action'})
Write-Output '-- More Info --'
Add-Row 'Remediation references available' 'OK' 'See paired README Learn References'

$ok = @($findings | Where-Object Status -eq 'OK').Count
Write-Output ''
Write-Output "=== RESULT: $ok OK / $fail FAIL / $warn WARN ==="

$findings
