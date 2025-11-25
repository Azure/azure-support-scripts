# Display description on screen
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "This script scans TLS and SSL settings and configurations" -ForegroundColor Cyan
Write-Host "summary at the end. If any errors are found, a remediation" -ForegroundColor Cyan
Write-Host "link to Microsoft documentation is displayed." -ForegroundColor Cyan
Write-Host "Reference: https://aka.ms/xxxxxx" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------`n" -ForegroundColor Cyan

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

# ---- Main Logic --------------------------------------------------------------


Write-Host "=== TLS / Schannel Audit ===" -ForegroundColor Cyan

$basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
$protocols = @("SSL 2.0","SSL 3.0","TLS 1.0","TLS 1.1","TLS 1.2","TLS 1.3")

function Get-ProtocolState {
    param(
        [string]$Protocol,
        [ValidateSet("Client","Server")] [string]$Role
    )
    $path = Join-Path $basePath "$Protocol\$Role"
    if (-not (Test-Path $path)) {
        return [pscustomobject]@{
            Protocol = $Protocol; Role = $Role
            Enabled = $null; DisabledByDefault = $null
            EffectiveState = "NotConfigured (OS default)"
        }
    }

    $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    $enabled = $props.Enabled
    $dbd = $props.DisabledByDefault

    $effective =
        if ($enabled -eq 1 -and ($dbd -eq 0 -or $dbd -eq $null)) { "Enabled" }
        elseif ($enabled -eq 0 -or $dbd -eq 1) { "Disabled" }
        else { "Unknown/Partial" }

    [pscustomobject]@{
        Protocol = $Protocol; Role = $Role
        Enabled = $enabled; DisabledByDefault = $dbd
        EffectiveState = $effective
    }
}

Write-Host "`n-- Protocol configuration (Schannel) --" -ForegroundColor Cyan

$protoResults = foreach ($p in $protocols) {
    foreach ($r in @("Client","Server")) {
        Get-ProtocolState -Protocol $p -Role $r
    }
}

$protoResults | Sort-Object Protocol, Role | Format-Table -AutoSize

# Compliance warnings
$bad = $protoResults | Where-Object {
    $_.Protocol -in @("SSL 2.0","SSL 3.0","TLS 1.0","TLS 1.1") -and $_.EffectiveState -eq "Enabled"
}
if ($bad) {
    Write-Host "`nALERT: Deprecated protocols enabled:" -ForegroundColor Red
    Write-Host "`nhttps://learn.microsoft.com/en-us/windows/win32/secauthn/tls-10-11-deprecation-in-windows" -ForegroundColor Red
	$bad | Format-Table Protocol, Role, Enabled, DisabledByDefault, EffectiveState -AutoSize
    Write-Host "MS guidance: TLS 1.0/1.1 retirement and diagnostics." -ForegroundColor Yellow
}
`
# Cipher suites
Write-Host "`n-- Cipher suites (effective order) --" -ForegroundColor Cyan
if (Get-Command Get-TlsCipherSuite -ErrorAction SilentlyContinue) {
    $suites = Get-TlsCipherSuite
    $suites | Select-Object Name, Protocols | Format-Table -AutoSize

    $weakPatterns = "RC4","3DES","DES","NULL","MD5","EXPORT","ANON"
    $weak = $suites | Where-Object { $weakPatterns | ForEach-Object { $_ -and $_ -in $_.Name } }
    if ($weak) {
        Write-Host "`nWARN: Weak cipher suites detected (review necessity):" -ForegroundColor Yellow
        $weak | Select-Object Name, Protocols | Format-Table -AutoSize
    }
} else {
    Write-Host "Get-TlsCipherSuite not available; falling back to policy key only." -ForegroundColor Yellow
}

# Policy override key (if present)
$policyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002"
Write-Host "`n-- Cipher suite policy override --" -ForegroundColor Cyan
if (Test-Path $policyKey) {
    $policy = (Get-ItemProperty -Path $policyKey).Functions
    Write-Host "Policy cipher suite order is set (overrides OS defaults):"
    $policy -split "," | ForEach-Object { $_.Trim() } | Format-Table
} else {
    Write-Host "No cipher suite policy override found; OS defaults apply."
}

# Schannel error events
Write-Host "`n-- Recent Schannel/TLS errors (System log) --" -ForegroundColor Cyan
$since = (Get-Date).AddDays(-14)

$eventIds = 36871,36874,36887,36888,36870,36885,36886
$events = Get-WinEvent -FilterHashtable @{
    LogName      = "System"
    ProviderName = "Schannel"
    Id           = $eventIds
    StartTime    = $since
} -ErrorAction SilentlyContinue

if ($events) {
    $events |
        Group-Object Id |
        Sort-Object Count -Descending |
        ForEach-Object {
            $latest = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
            [pscustomobject]@{
                EventId  = $_.Name
                Count    = $_.Count
                Latest   = $latest.TimeCreated
                SampleMessage = ($latest.Message -replace "\s+"," ").
                                Substring(0,[Math]::Min(180,$latest.Message.Length))
            }
        } | Format-Table -AutoSize
} else {
    Write-Host "No Schannel errors found in the last 14 days."
}

# .NET strong crypto defaults
Write-Host "`n-- .NET strong crypto / default TLS --" -ForegroundColor Cyan

$netKey = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319"
Write-Host $netKey
    if (Test-Path $netKey) {
        $p = Get-ItemProperty $netKey -ErrorAction SilentlyContinue
        [pscustomobject]@{
            SchUseStrongCrypto = $p.SchUseStrongCrypto
            SystemDefaultTlsVersions = $p.SystemDefaultTlsVersions
        } | Format-Table -AutoSize
    }
 
 $netKey= "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319"
Write-Host $netKey
    if (Test-Path $netKey) {
        $p = Get-ItemProperty $netKey -ErrorAction SilentlyContinue
        [pscustomobject]@{
            SchUseStrongCrypto = $p.SchUseStrongCrypto
            SystemDefaultTlsVersions = $p.SystemDefaultTlsVersions
        } | Format-Table -AutoSize
    }
 
 
 

# WinHTTP DefaultSecureProtocols
Write-Host "`n-- WinHTTP DefaultSecureProtocols --" -ForegroundColor Cyan
$winhttpKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp"
if (Test-Path $winhttpKey) {
    $wh = Get-ItemProperty $winhttpKey -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Path = $winhttpKey
        DefaultSecureProtocols = $wh.DefaultSecureProtocols
    } | Format-Table -AutoSize
} else {
    Write-Host "WinHTTP DefaultSecureProtocols not explicitly set (OS defaults)."
}

Write-Host "`n=== Audit complete ===" -ForegroundColor Green
