# Windows Update Common Error Detection

A PowerShell diagnostic script that scans CBS logs on an Azure Windows VM for known Windows Update error codes, summarizes occurrences, and provides direct links to Microsoft remediation documentation.

## Overview

This script is intended to be run via **Azure Run Command** on Windows VMs. It automates the manual process of combing through Component-Based Servicing (CBS) logs to identify which Windows Update errors are present, how often they appear, and where to find guidance for fixing them.

## Script

| File | Description |
|---|---|
| `Windows_Update_Common_Error_Detections.ps1` | Main diagnostic script |

## Requirements

| Requirement | Detail |
|---|---|
| **Privileges** | Must be run as Administrator (enforced by the script) |
| **Log path** | `C:\Windows\Logs\CBS\` must be accessible |
| **PowerShell** | Windows PowerShell 5.1 or PowerShell 7+ |
| **Supported OS** | Windows Server 2016, 2019, 2022 / Windows 10, 11 |

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `StartDays` | `int` | `7` | Number of days back to scan CBS logs |

## Usage

### Run locally (as Administrator)

```powershell
# Scan the last 7 days (default)
.\Windows_Update_Common_Error_Detections.ps1

# Scan the last 30 days
.\Windows_Update_Common_Error_Detections.ps1 -StartDays 30
```

### Run via Azure Run Command (Portal)

1. Navigate to your VM in the Azure Portal.
2. Select **Run command** > **RunPowerShellScript**.
3. Paste the script content into the editor.
4. To override the default scan window, append `-StartDays <n>` in the **Parameters** field or at the end of the script.
5. Select **Run**.

### Run via Azure CLI

```bash
az vm run-command invoke \
  --resource-group <ResourceGroupName> \
  --name <VMName> \
  --command-id RunPowerShellScript \
  --scripts @Windows_Update_Common_Error_Detections.ps1
```

### Run via PowerShell (Az module)

```powershell
Invoke-AzVMRunCommand `
  -ResourceGroupName "<ResourceGroupName>" `
  -VMName "<VMName>" `
  -CommandId "RunPowerShellScript" `
  -ScriptPath ".\Windows_Update_Common_Error_Detections.ps1"
```

## What the Script Does

1. **Admin check** — Exits immediately if not running as Administrator.
2. **Log discovery** — Enumerates all `.log` and `.zip` files under `C:\Windows\Logs\CBS\` modified within the `StartDays` window.
3. **Archive handling** — Automatically extracts `.zip` archives to a temporary directory for scanning, then cleans up.
4. **Error scanning** — Searches each log file for 60+ known Windows Update error codes across the following categories:

   | Category | Examples |
   |---|---|
   | CBS errors | `0x800F081F`, `0x800F0831`, `0x800F0906`, `0x800F0922` |
   | PSFX errors | `0x800F0983`, `0x800F0985`, `0x800F0986`, `0x800F0991` |
   | Windows Update client | `0x8024002E`, `0x80240008`, `0x8024401C`, `0x8024402C` |
   | System / Win32 | `0x80070002`, `0x80070005`, `0x80070422`, `0x80073712` |
   | Network / transport | `0x80072EE2`, `0x80072F8F`, `0x800706BA`, `0x800706BE` |

5. **Summary output** — Prints a count of total errors and a per-error-code breakdown with direct links to Microsoft Learn remediation documentation.
6. **Remediation link** — Displays `https://aka.ms/AzVmIPUValidation` for additional Azure VM in-place upgrade validation guidance.

## Sample Output

```
------------------------------------------------------------
This script scans CBS logs for known Windows update errors
It counts occurrences of each error code and provides a
summary at the end. If any errors are found and a remediation exists,
a link to Microsoft documentation is displayed.
------------------------------------------------------------

Start date: 03/27/2026 09:00:00

Scanning for errors, please wait...

Total Errors Found in last 7 days: 14

Error Breakdown:
0x800F081F : 9 occurrences - https://learn.microsoft.com/en-us/troubleshoot/windows-server/deployment/error-0x800f081f
0x80070422 : 5 occurrences - https://learn.microsoft.com/...

For remediation guidance, visit: https://aka.ms/AzVmIPUValidation

Additional Information: https://aka.ms/AzVmIPUValidation

Script completed successfully.
```

If no matching errors are found:

```
No matching errors found in the scanned logs.
```

## Covered Error Codes

<details>
<summary>Click to expand full error code list</summary>

| Error Code | Symbolic Name |
|---|---|
| `0x80070002` | ERROR_FILE_NOT_FOUND |
| `0x80070490` | ERROR_NOT_FOUND |
| `0x800F0805` | CBS_E_INVALID_PACKAGE |
| `0x80004005` | E_FAIL |
| `0x80070422` | ERROR_SERVICE_DISABLED |
| `0x80010108` | RPC_E_DISCONNECTED |
| `0x8007045B` | ERROR_SHUTDOWN_IN_PROGRESS |
| `0x8007000D` | ERROR_INVALID_DATA |
| `0x80070020` | ERROR_SHARING_VIOLATION |
| `0x80070005` | ERROR_ACCESS_DENIED |
| `0x800F081F` | CBS_E_SOURCE_MISSING |
| `0x80004004` | E_ABORT |
| `0x800F0831` | CBS_E_STORE_CORRUPTION |
| `0x800F0906` | CBS_E_DOWNLOAD_FAILURE |
| `0x8000FFFF` | E_UNEXPECTED |
| `0x80073712` | ERROR_SXS_COMPONENT_STORE_CORRUPT |
| `0x80040154` | REGDB_E_CLASSNOTREG |
| `0x800F0983` | PSFX_E_MATCHING_COMPONENT_MISSING |
| `0x80070BC9` | ERROR_FAIL_REBOOT_REQUIRED |
| `0x800706BA` | RPC_S_SERVER_UNAVAILABLE |
| `0x80070057` | ERROR_INVALID_PARAMETER |
| `0x80070003` | ERROR_PATH_NOT_FOUND |
| `0x800F0922` | CBS_E_INSTALLERS_FAILED |
| `0x8024002E` | WU_E_UNEXPECTED |
| `0x80073701` | ERROR_SXS_ASSEMBLY_MISSING |
| `0x8007007E` | ERROR_MOD_NOT_FOUND |
| `0x800736B3` | ERROR_SXS_ASSEMBLY_NOT_FOUND |
| `0x80070643` | ERROR_INSTALL_FAILURE |
| `0x800F0823` | CBS_E_NEW_SERVICING_STACK_REQUIRED |
| `0x800706BE` | RPC_S_CALL_FAILED |
| `0x8007000E` | ERROR_OUTOFMEMORY |
| `0x80080005` | CO_E_SERVER_EXEC_FAILURE |
| `0x800F0991` | PSFX_E_MISSING_PAYLOAD_FILE |
| `0x800F0905` | CBS_E_INVALID_XML |
| `0x80070013` | ERROR_WRITE_PROTECT |
| `0x80072F8F` | ERROR_INTERNET_SECURE_FAILURE |
| `0x800706C6` | RPC_S_CALL_FAILED_DNE |
| `0x80240438` | WU_E_PT_HTTP_STATUS_REQUEST_TIMEOUT |
| `0x800F0982` | PSFX_E_MATCHING_COMPONENT_NOT_FOUND |
| `0x8024001E` | WU_E_SERVICE_STOP |
| `0x800F0920` | CBS_E_INVALID_DRIVE |
| `0x8024401C` | WU_E_PT_HTTP_STATUS_REQUEST_TIMEOUT |
| `0x80070070` | ERROR_DISK_FULL |
| `0x800F0986` | PSFX_E_APPLY_FORWARD_DELTA_FAILED |
| `0x80072EE2` | ERROR_INTERNET_TIMEOUT |
| `0x800705AF` | ERROR_NO_SYSTEM_RESOURCES |
| `0x8024402C` | WU_E_PT_HTTP_STATUS_BAD_REQUEST |
| `0x800F0900` | CBS_E_XML_PARSER_FAILURE |
| `0x8007007B` | ERROR_INVALID_NAME |
| `0x800F0902` | CBS_E_XML_PARSER_FAILURE |
| `0x8024500C` | WU_E_PT_SOAPCLIENT_SEND |
| `0x80240008` | WU_E_ITEMNOTFOUND |
| `0x80070008` | ERROR_NOT_ENOUGH_MEMORY |
| `0x80244007` | WU_E_PT_HTTP_STATUS_DENIED |
| `0x800F0985` | PSFX_E_APPLY_REVERSE_DELTA_FAILED |
| `0x800705B4` | ERROR_TIMEOUT |
| `0x800F080D` | CBS_E_MANIFEST_INVALID |
| `0x800F0988` | PSFX_E_INVALID_DELTA_COMBINATION |
| `0x80244022` | WU_E_PT_HTTP_STATUS_SERVICE_UNAVAIL |
| `0x80244017` | WU_E_PT_HTTP_STATUS_NOT_FOUND |
| `0x80004002` | E_NOINTERFACE |
| `0x800F080A` | CBS_E_REQUIRES_ELEVATION |
| `D0000017`   | STATUS_NO_MEMORY |
| `0x800705AA` | ERROR_NO_SYSTEM_RESOURCES |
| `0x80070776` | ERROR_INVALID_GROUP |
| `0x800F0819` | CBS_E_INVALID_DRIVE |
| `0x800701D9` | ERROR_CLUSTER_INVALID_NODE |
| `0x800703FB` | ERROR_INVALID_OPERATION |
| `0x800719E4` | ERROR_CLUSTER_NODE_ALREADY_UP |

</details>

## Liability

As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Related Resources

- [Troubleshoot Windows Update download errors](https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/troubleshoot-windows-update-download-errors)
- [Windows Update error reference](https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference)
- [Azure VM in-place upgrade validation](https://aka.ms/AzVmIPUValidation)

## Contributing

This script is part of the [azure-support-scripts](https://github.com/Azure/azure-support-scripts) repository. See [CONTRIBUTING.md](https://github.com/Azure/azure-support-scripts/blob/master/CONTRIBUTING.md) for guidelines.
