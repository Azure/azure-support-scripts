# Azure VM sudo Configuration Repair (Linux)

This bash script validates and repairs the most common issues that cause `sudo` to stop working on a Linux VM. It is an adaptation of the `sudo` remediation action from [ALAR](https://github.com/Azure/ALAR) (Azure Linux Auto Recovery), packaged as a single self-contained script for one-shot execution via Azure Run Command.

> **Warning:** It is strongly recommended to back up your VM before running this script. Changes are made to the sudoers configuration and the `sudo` binary's permissions, which — in an unexpected environment — could affect the ability to run `sudo`.

## How It Works

The script runs 5 phases:

1. **Duplicate sudo-user detection** — Scans `/etc/sudoers` and every file under `/etc/sudoers.d/` for usernames granted direct sudo rights in more than one file. If `/etc/sudoers.d/waagent` is involved (the most common failure mode — a conflict between cloud-init and the Azure `vmaccess` password-reset extension), that file is backed up and moved to `/root` so cloud-init's original definition wins.
2. **Sudoers permissions & ownership** — Checks and fixes every file in `/etc/sudoers` and `/etc/sudoers.d/*` to the required `0440` permissions and `root:root` ownership.
3. **`targetpw` remediation** — Detects the historic `Defaults targetpw` directive (common on older SUSE images) in `/etc/sudoers` and comments it out (along with its matching `ALL` line) after taking a backup. Does nothing if not present.
4. **`sudo` binary setuid bits** — Checks and fixes the permissions on the `sudo` binary itself: `4111` on Red Hat-family distros, `4755` on every other family, plus `root:root` ownership.
5. **`/etc` sanity check** — Verifies `/etc` itself is `root:root` and `0755`. This is reported only (not fixed), since a mismatch here is a signal of a larger, likely-accidental recursive `chmod`/`chown` elsewhere on the system.

Every fix is preceded by a check, and every check/fix pair prints its result as a tagged line (`OK:`, `MISMATCH:`, `FIX:`, `FIXED:`, `NOOP:`, `WARN:`, `ERR:`) so the before/after state is always visible in the output.

## Supported Distributions

OS family is detected from `/etc/os-release` (`ID` and `ID_LIKE`) and only affects the expected `sudo` binary permissions in phase 4 — every other phase behaves identically across families.

| Family | Recognized `ID` values | `sudo` binary permissions |
|---|---|---|
| Red Hat family (`fedora` in the script) | `rhel`, `fedora`, `centos`, `rocky`, `almalinux`, `ol`, `amzn` | `4111` |
| Debian family | `ubuntu`, `debian` | `4755` |
| SUSE family | `sles`, `suse`, `opensuse*` | `4755` |
| Unrecognized | any other `ID`, or `ID_LIKE` not matching the above | `4755` |

`ID_LIKE` is also scanned (with a Red Hat-family preference when multiple tokens match) so common derivatives are still classified correctly even with an unfamiliar `ID`.

## Prerequisites

- A working `bash` shell
- Root/sudo privileges (required to `chmod`/`chown` the sudoers files and the `sudo` binary itself)

## Usage

This script is only intended to be used in the context of Azure Run Command from the Azure portal or CLI. See [ALAR](https://github.com/Azure/ALAR) for alternate usage modes.

Download the script to the local session. This can be done in `bash` or PowerShell, optionally in the [Azure Cloud Shell](https://shell.azure.com):

```bash
curl -sL https://raw.githubusercontent.com/Azure/azure-support-scripts/master/RunCommand/Linux/Linux_sudoFix/Linux_sudoFix.sh -o Linux_sudoFix.sh
```

```PowerShell
Invoke-WebRequest `
    -Uri 'https://raw.githubusercontent.com/Azure/azure-support-scripts/master/RunCommand/Linux/Linux_sudoFix/Linux_sudoFix.sh' `
    -OutFile 'Linux_sudoFix.sh'
```

Run the script via Azure Run Command:

### Azure CLI

```bash
az vm run-command invoke \
    --resource-group <resource-group> \
    --name <vm-name> \
    --command-id RunShellScript \
    --scripts @Linux_sudoFix.sh
```

To get more readable output including the exit `code` and `displayStatus` alongside the script's log:

```powershell
az vm run-command invoke `
    --resource-group <resource-group> `
    --name <vm-name> `
    --command-id RunShellScript `
    --scripts @Linux_sudoFix.sh `
    --query "value[].[code, displayStatus, message]" -o tsv
```

`-o tsv` renders the embedded `\n` characters in `message` as real newlines, so each tagged check/fix line prints on its own line.

### Parameters

None.

### Example Output

```
OK: No users defined in more than one sudoers file.
OK: /etc/sudoers already has permissions 0440
NOOP: Permissions already correct; no change applied.
OK: /etc/sudoers owner:group OK (root:root)
NOOP: Ownership already correct; no change applied.
OK: /etc/sudoers.d/cloudguestregistryauth already has permissions 0440
NOOP: Permissions already correct; no change applied.
OK: /etc/sudoers.d/cloudguestregistryauth owner:group OK (root:root)
NOOP: Ownership already correct; no change applied.
OK: /etc/sudoers.d/90-cloud-init-users already has permissions 0440
NOOP: Permissions already correct; no change applied.
OK: /etc/sudoers.d/90-cloud-init-users owner:group OK (root:root)
NOOP: Ownership already correct; no change applied.
OK: /usr/bin/sudo already has permissions 4755
NOOP: Permissions already correct; no change applied.
OK: /usr/bin/sudo owner:group OK (root:root)
NOOP: Ownership already correct; no change applied.
OK: /etc owner:group OK (root:root)
OK: /etc already has permissions 0755
```

If you open a support request, please include the full text content from the output alongside the time the script was run.

## Exit Codes

The script does not define custom exit codes — it exits with the status of the last command it executed. Review the tagged output lines (`WARN:`, `ERR:`, `MISMATCH:`) rather than the exit code alone to determine whether any issues remain.

## References

- [ALAR (Azure Linux Auto Recovery)](https://github.com/Azure/ALAR)
- [sudoers file format](https://man7.org/linux/man-pages/man5/sudoers.5.html)
- [Azure Run Command overview](https://learn.microsoft.com/azure/virtual-machines/linux/run-command)

## Liability

As described in the [MIT license](../../../LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues

- While this script does intend to reset permissions and ownership modes to expected values, there may be some scenarios where these are not entirely appropriate. This could include running on very customized or unknown distributions, or an extremely hardened environment.