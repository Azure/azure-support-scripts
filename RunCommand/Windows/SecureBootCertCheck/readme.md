# Secure Boot Certificate Update Status Check

Collects and reports the Secure Boot certificate update status on a Windows device. Reads registry values, event log entries, and scheduled task state to produce a color-coded console report with prioritized next steps. Designed to run via **Run Command** or directly from an elevated PowerShell session.

The script is **read-only** — it makes no changes to the device.

Reference: [https://aka.ms/securebootplaybook](https://aka.ms/securebootplaybook)

## What It Does

| Section | Checks |
|---------|--------|
| **Device Information** | Hostname, collection timestamp |
| **Secure Boot Status** | Secure Boot enabled state; `AvailableUpdates` bitmask decoded into human-readable certificate update flags; opt-out/opt-in registry values |
| **Certificate Update Status** | `UEFICA2023Status` (Updated / OptedOut / pending); error code and error event ID if a failure was recorded |
| **Device Attributes** | OEM manufacturer, model, firmware version and release date, OS architecture, `CanAttemptUpdateAfter` timestamp |
| **Event Log Analysis** | Most recent Secure Boot event from the `Microsoft-Windows-TPM-WMI` provider; counts and error codes for all relevant event IDs (1795–1808) |
| **Update Delivery Mechanisms** | `Secure-Boot-Update` scheduled task state and last run time; WinCS key `F33E0C8E002` status |

## Why This Matters

Azure VM Secure Boot support cases frequently involve:
- **Event 1795 failures** where the Azure host node has not yet received the firmware update needed to support guest-initiated KEK updates
- **Certificate update stalls** caused by a disabled scheduled task, missing servicing stack update, or known firmware issue (`KI_<number>`)
- **Confusion between guest-side and host-side blockers** — this script surfaces both in a single pass

## Prerequisites

- Windows with UEFI Secure Boot support (Gen2 VM on Azure, or physical UEFI hardware)
- PowerShell 3.0 or higher
- Administrator privileges recommended (required for event log queries and WinCS key check)

## Usage

### Via Azure Run Command

1. Open the Azure Portal and navigate to the VM.
2. Go to **Operations** > **Run command** > **RunPowerShellScript**.
3. Paste the contents of `Detect-SecureBootCertUpdateStatus_Summary.ps1`.
4. Click **Run**.

### Manual Download and Run

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Azure/azure-support-scripts/master/RunCommand/Windows/SecureBootCertCheck/Detect-SecureBootCertUpdateStatus_Summary.ps1" -OutFile "Detect-SecureBootCertUpdateStatus_Summary.ps1"
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Detect-SecureBootCertUpdateStatus_Summary.ps1
```

### Parameters

The script takes no parameters. All output is written to the console.

## Sample Output

```
===============================================================================
  Secure Boot Certificate Update Status Check
  Reference: https://aka.ms/securebootplaybook
===============================================================================

--- Device Information ---
Hostname: MyVM
Collection Time: 04/10/2026 14:23:01

--- Secure Boot Status ---
Secure Boot Enabled: True
High Confidence Opt Out: Not Set
Microsoft Update Managed Opt In: Not Set
Available Updates: 0x5944
  -> Deploy ALL certificates and Boot Manager (0x5944)
  -> 0x4    - Add Microsoft Corporation KEK 2K CA 2023 certificate into KEK
  -> 0x40   - Add Windows UEFI CA 2023 certificate into DB
  -> 0x80   - Revoke PCA 2011 Certificate (update DBX)
  -> 0x100  - Update the Boot Managers
  -> 0x200  - Update SVN value into DBX

--- Certificate Update Status ---
Windows UEFI CA 2023 Status: NotStarted
  -> The certificate update has not completed yet.
UEFI CA 2023 Error: None

--- Event Log Analysis ---
Latest Event ID: 1795 - Firmware returned an error during the Secure Boot certificate update
  (Event Time: 2026-04-10T14:20:44.0000000Z)
Event 1795 (Firmware Error) Count: 3
  -> This typically means the device firmware rejected the update.

--- Update Delivery Mechanisms ---
SecureBoot Update Task: Ready (Enabled: True)
SecureBoot Update Task Last Run: 2026-04-10T14:20:40.0000000Z

===============================================================================
  Summary
===============================================================================
  STATUS: ⚠️  ACTION NEEDED

  FINDINGS:
  * Windows UEFI CA 2023 certificate has not been installed yet.
  * Firmware errors detected (3 occurrences).

  NEXT STEPS:
  -----------
  1. Contact Azure support or your hardware vendor. The firmware on this host
     does not support the Secure Boot certificate update (Event 1795).
     The host node must be updated before the guest can apply the KEK change.
```

## Output Legend

| Status | Color | Meaning |
|--------|-------|---------|
| PASS | Green | `UEFICA2023Status = Updated` and no reboot pending |
| ACTION NEEDED | Yellow/Red | Certificate update has not completed; see NEXT STEPS |
| Green values | Green | Value is in a healthy/expected state |
| Yellow values | Yellow | Warning — update not complete, opt-out set, or known issue |
| Red values | Red | Error — firmware rejected the update or an error code was recorded |
| Cyan values | Cyan | Informational — reboot pending or update initiated |

## Event ID Reference

| Event ID | Meaning |
|----------|---------|
| 1808 | Update completed successfully |
| 1801 | Update initiated — reboot required |
| 1800 | Reboot required to complete update (not an error) |
| 1803 | Matching KEK not found — OEM must supply a PK-signed KEK |
| 1802 | Known firmware issue blocked update — see `KI_<number>` in output |
| 1796 | Error code logged during update |
| 1795 | Firmware returned an error (e.g., write-protected NVRAM) |

## AvailableUpdates Bitmask

| Flag | Certificate Action |
|------|--------------------|
| `0x4` | Add Microsoft Corporation KEK 2K CA 2023 into KEK |
| `0x40` | Add Windows UEFI CA 2023 into DB |
| `0x80` | Revoke PCA 2011 certificate (update DBX) |
| `0x100` | Update Boot Managers |
| `0x200` | Update SVN value into DBX |
| `0x5944` | Deploy ALL certificates and Boot Manager (recommended combined value) |

## Common Scenarios

**Event 1795 on Azure VMs** — The host-side firmware does not yet support guest-initiated UEFI NVRAM writes for KEK updates. No guest-side action resolves this. The Azure host node must receive the firmware update. If this error persists across VM redeployments, file a support request referencing Event ID 1795.

**Event 1802 — Known Firmware Issue** — The `KI_<number>` value in the output identifies the specific known issue. Check [https://aka.ms/securebootplaybook](https://aka.ms/securebootplaybook) for guidance on that issue ID.

**Event 1803 — Missing KEK** — The OEM must supply a PK-signed KEK update. Contact your hardware vendor for physical hardware. This should not occur on standard Azure VM configurations.

**`UEFICA2023Status` = Not Available** — The Secure Boot servicing stack update has not been installed. Apply the latest Windows cumulative update and rerun the script.

**Scheduled task disabled** — Re-enable from an elevated prompt:

```cmd
schtasks /Change /TN "\Microsoft\Windows\PI\Secure-Boot-Update" /Enable
```

## Liability

As described in the [MIT license](../../../LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

If you encounter problems or have ideas for improvement, please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section.
