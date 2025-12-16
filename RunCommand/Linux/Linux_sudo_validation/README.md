# Azure Virtual Machine - Linux sudo validation

## Overview

This bash script will validate common issues causing the inability to use the `sudo` command.  This is an adaptation of the `sudo` action from ALAR.

- Checks for and fixes:
  - expected owner/permissions on the main `/etc/sudoers` file
  - expected owner/permissions for all drop-in files in `/etc/sudoers.d/`
  - setuid bit on the `/usr/bin/sudo` binary, along with expected permissions according to distribution family
- Checks for and reports
  - expected permissions on `/etc` as an indicator of a potential recursive `chmod` operation

## Prerequisites

- working bash shell

## Usage

This script is only intended to be used in the context of the RunCommand from Azure portal.  See ALAR for alternate usage modes.

<h3 style="color:red;">⚠️ IMPORTANT: It is strongly recommended to back up your VM before running this script.
Changes will potentially be made to the sudoers configuration which may cause the inability to run sudo.
</h3>

### Parameters

None

## Examples

### Output
```bash
Enable succeeded: 
[stdout]
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

[stderr]
```

# Analyzing output

## Script Output

The output will detail any changes performed, as well as files checked for the expected permissions modes and owner information.

If you open a support request, please include the text content from the output screen in your request, as well as the time the script was run.

# General info

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues


## Notes

- While this script does intend to reset permissions and ownership modes to expected values, there may be some scenarios where these are not entirely appropriate. This could include running on very customized or unknown distributions, or an extremely hardened environment.