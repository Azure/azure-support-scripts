# Secure Boot Certificate Status Check — Linux

Collects and reports Secure Boot certificate update status on a Linux Azure VM. Reads EFI variables, shim/GRUB package versions, and boot logs to produce a color-coded summary with prioritized next steps. Designed to run via **Run Command** or directly from an elevated shell session.

The script is **read-only** — it makes no changes to the device.

Reference: [https://aka.ms/securebootplaybook](https://aka.ms/securebootplaybook)

## What It Does

| Section | Checks |
|---------|--------|
| **Device Information** | Hostname, kernel version, distribution |
| **Secure Boot Status** | Secure Boot enabled state via `mokutil` or EFI variables |
| **Certificate Inventory** | DB and KEK certificates enumerated; checks for Microsoft UEFI CA 2023 and KEK 2K CA 2023 |
| **Bootloader Packages** | Shim and GRUB package versions (distro-aware: Ubuntu, RHEL, SUSE, Azure Linux) |
| **Boot Log Analysis** | `dmesg` and `journalctl` for Secure Boot messages, errors, attestation |
| **Azure VM Information** | IMDS metadata: VM name, size, image, security type (TrustedLaunch/ConfidentialVM) |

## Supported Distributions

- Ubuntu Server 20.04 LTS, 22.04 LTS
- RHEL 8.x, 9.x
- SUSE Enterprise Linux 15 SP3+
- Alma Linux 8.x, 9.x
- Rocky Linux 8.x, 9.x
- Oracle Linux 8.x, 9.x
- Debian 11, 12
- Azure Linux 1.0, 2.0

## Prerequisites

- Azure Gen2 Trusted Launch or Confidential VM running Linux
- `mokutil` installed (recommended — install via package manager if missing)
- Root/sudo privileges recommended for full EFI variable access and event log queries

## Usage

### Via Azure Run Command

1. Open the Azure Portal and navigate to the VM.
2. Go to **Operations** > **Run command** > **RunShellScript**.
3. Paste the contents of `Detect-SecureBootCertStatus-Linux.sh`.
4. Click **Run**.

### Manual Download and Run

```bash
curl -sSL -o Detect-SecureBootCertStatus-Linux.sh \
  "https://raw.githubusercontent.com/Azure/azure-support-scripts/master/RunCommand/Linux/SecureBootCertCheck/Detect-SecureBootCertStatus-Linux.sh"
chmod +x Detect-SecureBootCertStatus-Linux.sh
sudo ./Detect-SecureBootCertStatus-Linux.sh
```

## Sample Output

```
===============================================================================
  Secure Boot Certificate Update Status Check — Linux
  Reference: https://aka.ms/securebootplaybook
===============================================================================

--- Device Information ---
  Hostname: mylinuxvm
  Collection Time: 2026-06-05T14:23:01Z
  Kernel: 5.15.0-1064-azure
  Distribution: Ubuntu 22.04.4 LTS

--- Secure Boot Status ---
  Secure Boot: Enabled

--- Certificate Inventory ---
  DB Certificates: 4 found
    -> Microsoft UEFI CA 2023: Found in DB
    -> Microsoft UEFI CA 2011: Present in DB (expiring June 2026)
  KEK Certificates: 2 found
    -> Microsoft KEK 2K CA 2023: Found in KEK

--- Bootloader Packages ---
  Shim: shim-signed 1.54+15.8-0ubuntu1
  GRUB: grub-efi-amd64-signed 1.197+2.12-1ubuntu7

--- Boot Log Analysis ---
  [    0.000000] secureboot: Secure boot enabled

--- Azure VM Information ---
  VM Name: mylinuxvm
  VM Size: Standard_D4s_v5
  Image: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2
  Security Type: TrustedLaunch

===============================================================================
  Summary
===============================================================================
  STATUS: ✅ PASS

  Microsoft UEFI CA 2023 certificates are present in firmware.
  Ensure shim package is up to date from your distro repos.
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | PASS — certificates updated, or Secure Boot disabled (not applicable) |
| 1 | ACTION NEEDED — certificates not yet updated |

## Common Scenarios

**2023 certificates not found in DB/KEK** — The VM was created before March 2024 and has not received the firmware certificate update. Restart or redeploy the VM to trigger the platform update.

**mokutil not installed** — Install it: `apt install mokutil` (Ubuntu/Debian), `dnf install mokutil` (RHEL/Fedora), `zypper install mokutil` (SUSE).

**Security type is "Standard" not "TrustedLaunch"** — The VM is not Trusted Launch. Secure Boot certificates are not applicable. Consider upgrading to Trusted Launch for enhanced security.

**Secure Boot disabled** — Certificate updates don't apply when Secure Boot is disabled. Re-enable via Azure Portal if desired (requires VM deallocation).

## Liability

As described in the [MIT license](../../../LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

If you encounter problems or have ideas for improvement, please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section.
