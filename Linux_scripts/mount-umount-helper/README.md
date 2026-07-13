# Mount-Umount Helper Script

---

## Overview

`mount-umount-helper.sh` is an **interactive shell script** designed to simplify disk mount and unmount operations in a **rescue/recovery VM environment**, primarily for **Linux VM boot failure scenarios in Azure**.

This automation is based on Microsoft guidance:  
👉 https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux/chroot-environment-linux

---

## ⚠️ Important Warning

This script must be used **ONLY** in a rescue VM or recovery environment.  

**Do NOT run on a production VM**, as it may lead to:
- Data corruption  
- Service outage  
- System instability  

---

## Key Features

- Interactive workflow  
- Supports both **LVM and non-LVM** disk configurations  
- Automatically detects **rescue VM OS disk type**  
- Intelligent mount method selection  

---

### Advanced Handling

The script includes special handling for platform-specific behaviors:

- **RHEL 9**: root VG naming and conflict-safe handling  
- **Oracle Linux 8**: LVM behavior alignment  
- **Oracle Linux 9**: support for `lvmdevices` environments  
- **NVMe disks**: safe handling and selection  

---

### Reliability

- State-based tracking for safe unmount operations  
- Automatic logging (**no customer data stored**)  

---

## Supported Distributions

- RHEL / CentOS  
- Oracle Linux  
- AlmaLinux  
- SUSE / SLES  
- Ubuntu / Debian  

---

## Mount Methods

| Method   | Scenario |
|----------|----------|
| Method 1 | Non-LVM Rescue OS + Non-LVM Disk |
| Method 2 | LVM Rescue OS + LVM Disk (uses `vgimportclone`) |
| Method 3 | Non-LVM Rescue OS + LVM Disk |
| Method 4 | LVM Rescue OS + Non-LVM Disk |

---

## ⚡ Quick Start

- Download and execute
```bash
wget https://aka.ms/mountumounthelper
chmod +x mount-umount-helper.sh
sudo ./mount-umount-helper.sh
```
- Select mount → mount the disk
- Perform required fixes:
  ```bash
  chroot /rescue
  ```
- Run again → select umount

## Workflow
1. Script Start
   - Displays safety warning
   - Prompts user to choose:
     - mount
     - umount
2. Mount Flow
   - Displays rescue VM OS details
   - Lists block devices (lsblk)
   - Detects rescue VM disk type (LVM / non-LVM)
   - Prompts for mount point (default: /rescue)
   - Validates or creates mount directory
   - Prompts for disk selection
   - Displays:
     - Disk layout
     - Expected mount points
       - /boot and /boot/efi determined based on partition size
     - Compares UUIDs (rescue VM vs target disk)
     - Selects appropriate mount method
     - Performs mount with:
       - logging
       - state tracking
3. Unmount Flow
   - Uses previously generated state file
     (or prompts if not found)
   - Identifies all mounted paths
   - Unmount sequence:
     - Child mount points first
     - Parent mount point last
   - Validates mount consistency
   - Requests confirmation before disk detach
   - Performs cleanup:
     - Device-mapper entries
     - Mount namespaces
   - Restores the original VG name of the rescue VM OS disk (if modified during mount)
   - Exits safely

---
## Generated Files

| File Path | Description |
|----------|-------------|
| `/var/log/mount-helper-<timestamp>.log` | Mount logs |
| `/var/log/mount-helper-<timestamp>.state` | State tracking file |
| `/var/log/umount-helper-<timestamp>.log` | Unmount logs |

---
## Prerequisites

Before running the script:
- You must be in a rescue VM
- Target disk must be attached but not mounted
- Root/sudo access is required

Required Tools
- lsblk
- blkid
- mount, umount
- lvm2
- dmsetup

---
## Scope Considerations
- Optimized for single-disk OS layouts
- Best results when:
  - All mount operations are performed using this script
  - The environment starts in a clean state
---
## Current Limitations
- Not supported:
  - OS spanning across multiple disks
- Not optimized for:
  - Partially mounted filesystems
  - Mixed manual + automated mount scenarios
---
## When to Use
- Azure VM boot failure recovery
- Offline disk troubleshooting
- Chroot-based repairs
- LVM conflict resolution

---
## Summary

This automation provides a **safe, structured, and user-guided approach** for mounting and unmounting OS disks during recovery operations, minimizing risk and improving operational efficiency.
