# Azure VM Kernel Serial Log Verbosity Adjuster (Linux)

This bash script adjusts the kernel `printk` console log level on a running Linux VM, controlling how much kernel logging is written to the linux device configured as 'console' at boot. When configured properly, this is `ttyS0` and connects to the Azure Serial Console available in the Azure portal or through the cli command `az serial-console` ([documentation](https://learn.microsoft.com/en-us/cli/azure/serial-console)) Raising the numeric level (up to `7`/debug) captures far more boot and runtime kernel diagnostics for troubleshooting; lowering it reduces noise.

By default the script sets the level to `7` (debug) in a **non-persistent** (runtime-only) manner, so it can be run as a one-shot diagnostic capture via Azure Run Command without altering the persistent state of the VM. An optional flag makes the change permanent (survives reboot).

## How It Works

The script runs up to 4 phases:

1. **Initial state report** — Reads `/proc/sys/kernel/printk` (current/default/minimum/boot-default levels) and every registered kernel console channel (`/proc/consoles`, `/sys/class/tty/console/active`, `console=` boot cmdline args), printing each with the description of the value.
2. **Runtime level change** — Writes the requested level to `/proc/sys/kernel/printk`. This only updates the *current* field, leaving default/minimum/boot-default untouched, and takes effect immediately with no reboot required.
3. **Persistent sysctl drop-in** *(only if the persist flag is set)* — Writes `kernel.printk = <level>` to `/etc/sysctl.d/01-linux-seriallog-printk.conf`, backing up a drop-in from a previous execution first, and applies it immediately via `sysctl -p` if available. This is read by `systemd-sysctl.service` on every boot, on any systemd-based distro.
4. **Persistent GRUB boot parameter** *(only if the persist flag is set, RedHat-family only)* — Some distributions (RHEL and derivatives) traditionally carry an explicit `loglevel=` kernel boot parameter. If one is already present, the script updates it across every installed kernel via `grubby --update-kernel=ALL`. It never introduces a `loglevel=` parameter on a distro/VM that didn't already have one.
5. **Final state report** — Re-reads and prints the levels with the same methods as phase 1 so the before/after values can be compared.

## Parameters

The script takes two **positional** parameters — no named/flag parsing is done, since Azure Run Command's `--parameters` strips any `name=` prefix before invoking the script, leaving only bare values passed as `$1`, `$2`, ...

| Position | Meaning | Valid values | Default when omitted |
|---|---|---|---|
| `$1` | Desired printk log level | `0`-`7` | `7` (debug) |
| `$2` | Persist flag | `persist`, `true`, `yes` (case-insensitive) → persistent; anything else → runtime-only | runtime-only (not persisted) |

> **Note:** `1` is deliberately **not** accepted as a persist-flag value, to avoid confusion with the numeric log level `1` (`alert`).

## Persistence Details

| Mechanism | Scope | Applies to |
|---|---|---|
| `/proc/sys/kernel/printk` write | Runtime only, lost on reboot | All distros/kernels with procfs |
| `/etc/sysctl.d/01-linux-seriallog-printk.conf` | Survives reboot via `systemd-sysctl.service` | All systemd-based distros (RHEL, SUSE, Ubuntu/Debian, etc.) |
| GRUB `loglevel=` boot parameter (via `grubby`) | Survives reboot, affects kernel messages emitted before systemd starts | RedHat-family only (`rhel`, `centos`, `fedora`, `rocky`, `almalinux`, `ol`, or any `ID_LIKE` containing `rhel`/`fedora`) — and only when a `loglevel=` parameter already exists |

SUSE and Debian-based families don't set a `loglevel=` boot parameter by default, so the script intentionally does not insert one there; the sysctl drop-in is the only persistence for those families.

## Supported Distributions

The script attempts [phases 1-3](#how-it-works) unconditionally on any systemd-based Linux — no distro-family branching is needed for the runtime write or the sysctl drop-in. Phase 4 (GRUB boot parameter) is explicitly gated:

| Family | GRUB boot-parameter phase |
|---|---|
| Red Hat family (`rhel`, `centos`, `fedora`, `rocky`, `almalinux`, `ol`) | Attempted (requires `grubby`) |
| SUSE, Debian/Ubuntu, and others | Skipped — reported via an `INFO:` line, not an error |

## Prerequisites

- Root/sudo privileges (required to write `/proc/sys/kernel/printk` and the sysctl drop-in)
- `systemd` (for the persistent sysctl drop-in to take effect at boot)
- `sysctl` (optional — applies the persistent value immediately; otherwise it only takes effect on next boot)
- `grubby` (only required for the persistent GRUB boot-parameter phase on RedHat-family distros)

## Usage

Download the script to the local session. This can be done in `bash` or PowerShell, optionally in the [Azure Cloud Shell](https://shell.azure.com):

```bash
curl -sL https://aka.ms/rcl-seriallevel -o Linux_serialLog.sh
```

```PowerShell
Invoke-WebRequest `
    -Uri 'https://aka.ms/rcl-seriallevel' -OutFile 'Linux_serialLog.sh'
```

Run the script via Azure Run Command:

### Azure CLI

Raise verbosity to debug (level 7), runtime-only (default behavior, no parameters needed):

```bash
az vm run-command invoke \
    --resource-group <resource-group> \
    --name <vm-name> \
    --command-id RunShellScript \
    --scripts @Linux_serialLog.sh
```

Set a specific level, runtime-only:

```bash
az vm run-command invoke \
    --resource-group <resource-group> \
    --name <vm-name> \
    --command-id RunShellScript \
    --scripts @Linux_serialLog.sh \
    --parameters 4
```

Set a specific level and make it persistent (survives reboot):

```bash
az vm run-command invoke \
    --resource-group <resource-group> \
    --name <vm-name> \
    --command-id RunShellScript \
    --scripts @Linux_serialLog.sh \
    --parameters 7 persist
```

To get more readable output including the exit `code` and `displayStatus` alongside the script's log:

```powershell
az vm run-command invoke `
    --resource-group <resource-group> `
    --name <vm-name> `
    --command-id RunShellScript `
    --scripts @Linux_serialLog.sh `
    --parameters 7 persist `
    --query "value[].[code, displayStatus, message]" -o tsv
```

`-o tsv` renders the embedded `\n` characters in `message` as real newlines, so each tagged output line (`REPORT:`, `PRINTK:`, `CONSOLE:`, `SET:`, etc.) prints on its own line.

## Important: Non-Persistent by Default

Unless the persist flag (`$2`) is explicitly set to `persist`, `true`, or `yes`, every change made by this script is **runtime-only**:

- The requested printk level takes effect immediately
- After the next reboot, the VM reverts to whatever printk level/boot parameters were already configured

## Exit Codes

The script does not define custom exit codes — it exits with the status of the last command it executed. A non-zero exit generally indicates the runtime `printk` write failed (e.g. invalid level, or not running as root), since that failure short-circuits the persistent phases.

## References

- [Azure Serial Console for Linux](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/serial-console-linux)
- [Kernel command-line parameters (Red Hat)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/managing_monitoring_and_updating_the_kernel/configuring-kernel-command-line-parameters_managing-monitoring-and-updating-the-kernel)
- [`sysctl.d` directories and drop-ins (systemd)](https://www.freedesktop.org/software/systemd/man/latest/sysctl.d.html)
- [`printk` kernel documentation](https://www.kernel.org/doc/html/latest/core-api/printk-basics.html)
- [Azure Run Command overview](https://learn.microsoft.com/azure/virtual-machines/linux/run-command)

## Liability

As described in the [MIT license](../../../LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues

- The GRUB boot-parameter phase only updates an existing `loglevel=` value — it will not add one to a distro/kernel that never had one configured.
- SUSE and Debian/Ubuntu-family distros do not receive a GRUB boot-parameter update, since they don't set a `loglevel=` parameter by default; the sysctl drop-in is relied upon for those families.
