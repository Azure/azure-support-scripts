# Windows Firewall Rules Validation

Validates Windows Firewall configuration and tests connectivity to Azure service endpoints on an Azure VM. Designed to run via **Run Command** or locally with mock data for testing.

## What It Does

| Section              | Checks                                                                     |
|----------------------|----------------------------------------------------------------------------|
| **Firewall Service** | Windows Firewall (MpsSvc) service status                                   |
| **Firewall Profiles**| Domain, Private, Public profile state and default inbound/outbound actions |
| **Port Rules**       | RDP (3389), WinRM (5985/5986), SMB (445), HTTP (80), HTTPS (443)          |
| **Endpoints**        | 41 Azure endpoints across Infra, Mgmt, Identity, Storage, Monitor, Backup, Security, Updates, Certs, DevOps, Containers |
| **PerfInsights**     | Storage account connectivity if PerfInsights extension is configured       |
| **WSUS**             | Reads WSUS server URL from registry; tests connectivity if configured      |
| **Azure IP Blocks**  | Firewall rules blocking IMDS (169.254.169.254) or WireServer (168.63.129.16) |
| **WinRM/RDP Rules**  | Presence of allow rules for Windows Remote Management and Remote Desktop   |
| **Routing**          | Default gateway, learned route count, ExpressRoute/VPN detection, forced tunneling |

## Prerequisites

- PowerShell 5.1 or higher
- Administrator privileges (when running live on an Azure VM)

## Usage

### Via Azure Run Command

1. Open the Azure Portal and navigate to the VM.
2. Go to **Operations** > **Run command** > **RunPowerShellScript**.
3. Paste the contents of `Windows_Firewall_Rules_Validation.ps1`.
4. Ensure `$isMock = $false` (the default).
5. Click **Run**.

> **Note:** Run Command output is limited to 4 KB. The script's table format is optimized to stay within this limit.

### Manual download and run

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_Firewall_Rules_Validation.ps1
```

## Local Testing with Mock Data

The script includes a built-in mock mode for local testing without admin privileges or Azure VM access.

### Setup

1. The mock config file `mock_config_sample.json` is included in this folder.
2. Open `Windows_Firewall_Rules_Validation.ps1` and change line 59:

```powershell
# Change from:
$isMock = $false
# To:
$isMock = $true
```

3. Run the script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Windows_Firewall_Rules_Validation.ps1
```

### Mock Config Schema

The `mock_config_sample.json` file controls all test data:

| Key                  | Type     | Description                                          |
|----------------------|----------|------------------------------------------------------|
| `FirewallService`    | string   | Service status: `"Running"`, `"Stopped"`, etc.       |
| `FirewallProfiles`   | array    | Objects with `Name`, `Enabled`, `DefaultInboundAction`, `DefaultOutboundAction` |
| `PortRules`          | array    | Objects with `Port` (int) and `Result` (`"Allow"`, `"Block"`, `"NoRule"`) |
| `Endpoints`          | array    | Objects with `Host`, `Port`, `Pass` (bool)           |
| `PerfInsights`       | object   | `StorageAccountName` (string) and `Pass` (bool)      |
| `WSUS`               | object   | `WUServer` (string, URL) and `Pass` (bool). Omit or null = not configured |
| `AzureIPBlockRules`  | array    | Strings describing blocking rules (empty = no blocks)|
| `WinRMAllowRules`    | int      | Count of WinRM allow rules                           |
| `RDPAllowRules`      | int      | Count of RDP allow rules                             |
| `Routing`            | object   | `DefaultGateway` (string), `LearnedRouteCount` (int), `ForcedTunneling` (bool) |

## Sample Output (Run Command)

```
=== Firewall and Endpoint Validation ===
Check                                                Status
---------------------------------------------------- ------
Firewall Service: Running                            OK
Domain:On In=NotConfigured Out=NotConfigured         OK
Private:On In=NotConfigured Out=NotConfigured        OK
Public:On In=NotConfigured Out=NotConfigured         OK
-- Ports --
RDP/3389                                             OK
WinRM/5985                                           OK
WinRM-S/5986                                         OK
SMB/445                                              OK
HTTP/80                                              OK
HTTPS/443                                            OK
-- Endpoints --
IMDS 169.254.169.254:80                              OK
WireServer 168.63.129.16:80                          OK
KMS azkms.core.windows.net:1688                      OK
KMS-Alt kms.core.windows.net:1688                    OK
Time time.windows.com:123                            FAIL
ARM management.azure.com:443                         OK
ARM-Classic management.core.windows.net:443          OK
Portal portal.azure.com:443                          OK
AAD login.microsoftonline.com:443                    OK
Graph graph.microsoft.com:443                        OK
AAD-Legacy graph.windows.net:443                     OK
AAD-USGov login.microsoftonline.us:443               OK
Blob blob.core.windows.net:443                       FAIL
File file.core.windows.net:443                       FAIL
Table table.core.windows.net:443                     FAIL
Queue queue.core.windows.net:443                     FAIL
Monitor monitor.azure.com:443                        FAIL
LogAnalytics ods.opinsights.azure.com:443            FAIL
LogAnalyticsCfg oms.opinsights.azure.com:443         FAIL
AppInsights dc.applicationinsights.azure.com:443     OK
AppInsights-L dc.services.visualstudio.com:443       OK
Backup backup.windowsazure.com:443                   FAIL
SiteRecovery hypervrecoverymanager.windowsazure.com:443 FAIL
KeyVault vault.azure.net:443                         FAIL
SecurityCtr security.azure.com:443                   OK
Defender wdcp.microsoft.com:443                      OK
DefenderATP wdcpalt.microsoft.com:443                OK
WinUpdate windowsupdate.microsoft.com:443            OK
WinUpdate-Alt update.microsoft.com:443               OK
WSUS download.windowsupdate.com:443                  OK
DigiCert-AIA cacerts.digicert.com:80                 OK
DigiCert-CRL crl3.digicert.com:80                    OK
DigiCert-OCSP ocsp.digicert.com:80                   OK
MS-CRL crl.microsoft.com:80                          OK
MS-OCSP oneocsp.microsoft.com:80                     OK
MS-PKI www.microsoft.com:80                          OK
DevOps dev.azure.com:443                             OK
NuGet api.nuget.org:443                              OK
VSMarket marketplace.visualstudio.com:443            OK
ACR azurecr.io:443                                   OK
MCR mcr.microsoft.com:443                            OK
-- PerfInsights --
PerfInsights: not configured (skipped)               OK
-- WSUS --
WSUS: not configured (using Windows Update)          OK
-- Azure IP Blocks --
No block rules for Azure IPs                         OK
-- WinRM/RDP --
WinRM: 2 allow rule(s)                               OK
RDP: 3 allow rule(s)                                 OK
-- Routing --
Routing: 2 learned routes                            OK

=== RESULT: 41 OK / 11 FAIL ===
Docs: https://learn.microsoft.com/azure/virtual-machines/troubleshooting-guide
Ref: https://aka.ms/AzVmFirewallValidation
```

## Output Legend

| Status | Color    | Meaning                                                    |
|--------|----------|------------------------------------------------------------|
| OK     | Green    | Check passed                                               |
| FAIL   | Red      | Check failed -- action needed                              |
| WARN   | Yellow   | Non-critical issue or informational warning                |

## Liability

As described in the [MIT license](../../../LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

If you encounter problems or have ideas for improvement, please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section.
