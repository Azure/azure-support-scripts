#!/usr/bin/env bash

#===============================================================================
# mount-helper
#
# Purpose:
#   Safely mount a problem VM OS disk onto a rescue VM for inspection,
#   repair, or recovery. This script supports both LVM and non-LVM disks
#   and records all actions in a state file so they can be cleanly
#   reversed by umount-helper.sh.
#
# High-Level Workflow:
#
#   START
#     ├─ Initialize logging and state tracking
#     ├─ Detect rescue VM OS and disk layout (LVM / Non-LVM)
#     ├─ Validate root privileges
#     ├─ Select and validate mountpoint
#     ├─ Select and validate problem VM disk
#     ├─ Detect disk type and UUID relationships
#     ├─ Select mount method based on OS + disk combination
#     ├─ Execute mount strategy
#     ├─ Perform OS-specific post-mount fixes (RHEL 9+)
#     └─ EXIT with full rollback metadata recorded
#
# Mount Method Selection Logic:
#
#   Rescue OS   | User Disk   | Method | Description
#   ------------+-------------+--------+-------------------------------
#   Non-LVM     | Non-LVM     | 1      | Simple partition mount
#   LVM         | Non-LVM     | 4      | Simple partition mount
#   Non-LVM     | LVM         | 3      | Direct LVM activation
#   LVM         | LVM         | 2      | LVM clone (vgimportclone)
#
# Mount Method Behavior Summary:
#
#   Method 1 / 4:
#     - Detect partitions heuristically
#     - Mount root, /boot, /boot/efi
#     - Use XFS nouuid when needed
#
#   Method 2 (vgimportclone):
#     - Detect PVs on user disk
#     - Record ORIGINAL_VG in state file
#     - Detect VG name collisions
#     - Import VG under a new name
#     - Activate LVs and mount filesystems
#     - Always mount XFS with -o nouuid
#
#   Method 3:
#     - vgscan + vgchange -ay
#     - Mount /dev/mapper logical volumes directly
#
# Common Post-Mount Steps:
#   - Mount helper filesystems:
#       /proc, /sys, /dev, /run
#   - Record every mount action in STATEFILE
#
# RHEL 9+ Special Handling:
#   - Normalize /etc/fstab entries to UUID=
#   - Update boot loader entries (root=UUID=)
#   - Backup original files before modification
#
# Safety Guarantees:
#   - Script aborts on invalid input or unsafe conditions
#   - No mounts occur over non-empty or active directories
#   - UUID and VG collisions are explicitly handled
#   - All actions are logged and recorded for reversal
#
# Rollback:
#   - STATEFILE contains complete metadata of:
#       * mount order
#       * devices and mountpoints
#       * VG renames and imports
#       * dmsetup snapshots
#       * OS metadata
#   - umount-helper.sh consumes this file to safely undo changes
#
# Intended Usage:
#   - Rescue / recovery environments
#   - VM disk inspection and repair workflows
#   - Cloud rescue scenarios (Azure / similar)
#
#===============================================================================

#===============================================================================
# umount-helper
#
# Purpose:
#   Safely reverse and clean up all mount operations performed by
#   mount-helper. This script uses the state file generated during
#   the mount phase as the authoritative source of truth to ensure
#   correct unmount order, LVM cleanup, and disk detachment.
#
# High-Level Workflow:
#
#   START
#     ├─ Validate input state file
#     ├─ Initialize logging (with safe fallback)
#     ├─ Reconstruct mount context from STATEFILE
#     ├─ Detect mount method used during mount phase
#     ├─ Display consolidated state context to operator
#     ├─ Discover active mountpoints related to the user disk
#     ├─ Validate live mounts against recorded state
#     ├─ Perform safe, ordered unmount (children first)
#     ├─ Handle LVM-specific cleanup (if applicable)
#     ├─ Detach user disk from kernel (with confirmation)
#     └─ EXIT cleanly or with explicit operator guidance
#
# State-Driven Design:
#
#   umount-helper does NOT infer or guess mount state.
#   All teardown decisions are based on data recorded by
#   mount-helper in the STATEFILE, including:
#
#     - Mount method used (1–4)
#     - Mountpoint path
#     - User-selected disk
#     - Original and imported VG names
#     - PV → VG mappings
#     - OS version and safety policies
#     - Device-mapper snapshots (when applicable)
#
# Mount Method Awareness:
#
#   Method | Mount Phase Behavior             | Umount Phase Handling
#   -------+----------------------------------+------------------------------
#     1    | Non-LVM OS + Non-LVM disk        | Simple unmount only
#     2    | LVM clone (vgimportclone)        | Strict PV/VG verification,
#          |                                  | UUID normalization (RHEL 9),
#          |                                  | controlled LVM teardown
#     3    | Non-LVM OS + LVM disk            | vgchange cleanup + dmsetup
#     4    | LVM OS + Non-LVM disk            | Simple unmount only
#
# Unmount Strategy:
#
#   - Discover all mountpoints created under the mountpoint
#     (e.g. /rescue) using the STATEFILE
#   - Filter only currently mounted targets
#   - Sort by path depth (deepest first)
#   - Attempt normal unmount, escalate to lazy/force if required
#   - Retry failed unmounts after parent release
#   - Abort safely if unexpected mounts remain
#
# LVM Safety Checks (Method 2):
#
#   - Verify PV → VG mappings match recorded state
#   - Detect unexpected VG changes
#   - Enforce strict abort rules unless OS policy allows exception
#   - Prevent disk detach if live mounts do not match state
#
# OS-Specific Safety Policies:
#
#   - RHEL 8.10+, RHEL 9+, RHEL 10+:
#       * Skip live vgrename operations
#       * Avoid device-mapper remapping risks
#
#   - RHEL 9 + Method 2:
#       * Optional UUID normalization for:
#           - /etc/fstab
#           - boot loader entries
#       * Backup files before modification
#       * Require explicit user confirmation
#
# Disk Detachment:
#
#   - User disk is detached from the kernel ONLY after:
#       * All recorded mounts are unmounted
#       * Live mount state matches STATEFILE
#       * Operator explicitly confirms the action
#
#   - Kernel-level detach is performed via:
#       /sys/block/<device>/device/delete
#
# Safety Guarantees:
#
#   - No unmount or detach occurs without operator confirmation
#   - Unexpected live mounts cause a hard abort
#   - STATEFILE remains the single source of truth
#   - Errors are explicit and actionable
#
# Intended Usage:
#
#   - Companion teardown tool for mount-helper
#   - Rescue VM cleanup after disk inspection or repair
#   - Cloud VM recovery workflows (Azure and similar)
#
#===============================================================================


set -euo pipefail

# ---------------------------------------------------
# Global variables
# ---------------------------------------------------
LAST_STATE="/var/log/mount-helper-last.state"

err() { printf '%s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

# optional: require root
if [ "$(id -u)" -ne 0 ]; then
  err "This script should be run as root. Please re-run with sudo or as root."
  exit 1
fi

echo
echo "==========================================="
echo " Welcome to the mount and umount helper."
echo "==========================================="
echo
echo
echo "⚠️  IMPORTANT WARNING"
echo "===================================================================="
echo " This script is intended to be used ONLY on:"
echo "   - Rescue VM"
echo "   - Recovery server"
echo
echo " ❌ DO NOT run this script on a live / production VM or server."
echo "    Doing so may result in DATA LOSS or SYSTEM OUTAGE."
echo
echo " Use this tool only when the OS disk is NOT actively in use."
echo "===================================================================="
echo


# ===================================================
# MOUNT LOGIC (from mount-helper.sh)
# ===================================================
mount_helper() {
  
  SCRIPT_NAME="$(basename "$0")"
  TS="$(date '+%Y%m%d-%H%M%S')"
  LOGFILE="/var/log/mount-helper-$TS.log"

  STATEFILE="/var/log/mount-helper-$TS.state"
  LAST_STATE="/var/log/mount-helper-last.state"
  echo "$STATEFILE" > "$LAST_STATE"

    OS_PRETTY=""
    OS_VERSION=""
    OS_MAJOR=""
    OS_ID=""
    OS_LIKE=""
    if [ -r /etc/os-release ]; then
      . /etc/os-release
      OS_PRETTY="${PRETTY_NAME:-$NAME $VERSION}"
      OS_VERSION="${VERSION_ID:-}"
      OS_ID="${ID:-}"
      OS_LIKE="${ID_LIKE:-}"
      if printf '%s' "$OS_VERSION" | grep -qE '^[0-9]+'; then
        OS_MAJOR="$(printf '%s' "$OS_VERSION" | sed -E 's/^([0-9]+).*/\1/')"
      fi
    fi

    printf "OS_PRETTY=%s\n" "$OS_PRETTY" >> "$STATEFILE"
    printf "OS_VERSION=%s\n" "$OS_VERSION" >> "$STATEFILE"
    printf "OS_MAJOR=%s\n" "$OS_MAJOR" >> "$STATEFILE"
    printf "OS_ID=%s\n" "$OS_ID" >>"$STATEFILE"
    printf "OS_LIKE=%s\n" "$OS_LIKE" >>"$STATEFILE"
    echo "Recorded OS_PRETTY='$OS_PRETTY' OS_VERSION='$OS_VERSION' OS_MAJOR='$OS_MAJOR' OS_ID='$OS_ID' OS_LIKE='$OS_LIKE' in $STATEFILE" >> "$LOGFILE"


  is_rhel() {
    case " ${OS_ID:-} " in
      *rhel*)
        return 0
        ;;
    esac
    return 1
  }

  is_oracle_linux() {
    case " ${OS_ID:-} " in
      *ol*)
        return 0
        ;;
    esac
    return 1
  }

  is_almalinux() {
    case " ${OS_ID:-} " in
      *almalinux*)
        return 0
        ;;
    esac
    return 1
  }

  is_centos() {
    case " ${OS_ID:-} " in
      *centos*)
        return 0
        ;;
    esac
    return 1
  }

  is_suse() {
    case " ${OS_LIKE:-} ${OS_ID:-} " in
      *suse*|*SUSE*|*SLES*)
        return 0
        ;;
    esac
    return 1
  }

  is_debian() {
    case " ${OS_LIKE:-} ${OS_ID:-} " in
      *debian*|*ubuntu*)
        return 0
        ;;
    esac
    return 1
  }

  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Exiting."
    exit 1
  fi

  {
    echo "=== $SCRIPT_NAME started at $(date -Iseconds) ==="
  } >> "$LOGFILE"

  err() { printf '%s\n' "$*" >&2; }

  cmd_exists() { command -v "$1" >/dev/null 2>&1; }

  run_and_log_cmd_plain() {
    local cmd="$*"
    echo "    [CMD] $cmd"
    echo ">>> CMD: $cmd" >> "$LOGFILE"
    if out=$(/bin/sh -c "$cmd" 2>&1); then
      printf '%s\n' "$out" | sed 's/^/     /' | tee -a "$LOGFILE"
      echo ">>> EXIT: 0" >> "$LOGFILE"
      echo "    [OK]"
      return 0
    else
      local rc=$?
      printf '%s\n' "$out" | sed 's/^/     /' | tee -a "$LOGFILE"
      echo ">>> EXIT: $rc" >> "$LOGFILE"
      echo "    [FAIL] (exit $rc)"
      return $rc
    fi
  }

  run_and_log_cmd_must_succeed() {
    local cmd="$*"
    run_and_log_cmd_plain "$cmd"
    local rc=$?
    if [ $rc -ne 0 ]; then
      echo "FATAL: command failed and is required for safe continuation: $cmd" | tee -a "$LOGFILE"
      printf "FATAL_CMD_FAIL=%s\n" "$cmd" >> "$STATEFILE"
      echo "=== $SCRIPT_NAME failed at $(date -Iseconds) ===" >> "$LOGFILE"
      exit $rc
    fi
    return 0
  }

  mkdir_must_succeed() {
    local dir="$1"
    if /bin/mkdir -p "$dir" 2>&1 | sed 's/^/     /' | tee -a "$LOGFILE"; then
      return 0
    else
      echo "FATAL: mkdir failed for $dir" | tee -a "$LOGFILE"
      printf "FATAL_MKDIR_FAIL=%s\n" "$dir" >> "$STATEFILE"
      echo "=== $SCRIPT_NAME failed at $(date -Iseconds) ===" >> "$LOGFILE"
      exit 1
    fi
  }

  state_record() {
    local src="$1"; local tgt="$2"; local note="${3:-}"
    if mountpoint -q "$tgt" 2>/dev/null || [ -n "$(findmnt -n -o SOURCE --target "$tgt" 2>/dev/null || true)" ]; then
      printf "%s\tMOUNT\t%s\t%s\t%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$src" "$tgt" "$note" >> "$STATEFILE"
    fi
  }

  canon() { readlink -f "$1" 2>/dev/null || printf '%s' "$1"; }

  is_lvm_strict() {
    local dev="$1"
    local dev_c
    dev_c="$(canon "$dev")"
    if printf '%s\n' "$dev_c" | grep -qE '^/dev/mapper/|^/dev/[^/]+/[^/]+'; then
      if command -v lvs >/dev/null 2>&1 && lvs --noheadings -o lv_path 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$dev_c"; then
        return 0
      fi
      if printf '%s\n' "$dev_c" | grep -qE '^/dev/[^/]+/[^/]+'; then
        return 0
      fi
    fi

    local type
    type="$(lsblk -dn -o TYPE "$dev_c" 2>/dev/null || true)"
    if [ "$type" = "disk" ]; then
      while IFS= read -r child; do
        [ -z "$child" ] && continue
        child="/dev/$child"
        child_c="$(canon "$child")"
        fstype="$(lsblk -dn -o FSTYPE "$child_c" 2>/dev/null || true)"
        if printf '%s\n' "$fstype" | grep -iq 'LVM2_member'; then
          return 0
        fi
        chtype="$(lsblk -dn -o TYPE "$child_c" 2>/dev/null || true)"
        if [ "$chtype" = "lvm" ]; then
          return 0
        fi
        if command -v pvs >/dev/null 2>&1; then
          if pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$child_c"; then
            return 0
          fi
        fi
      done < <(lsblk -ln -o NAME "$dev_c" 2>/dev/null | tail -n +2)
      return 1
    fi
    fstype_dev="$(lsblk -dn -o FSTYPE "$dev_c" 2>/dev/null || true)"
    if printf '%s\n' "$fstype_dev" | grep -iq 'LVM2_member'; then
      return 0
    fi
    if [ "$(lsblk -dn -o TYPE "$dev_c" 2>/dev/null || true)" = "lvm" ]; then
      return 0
    fi
    if command -v pvs >/dev/null 2>&1; then
      if pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$dev_c"; then
        return 0
      fi
    fi
    if command -v pvdisplay >/dev/null 2>&1; then
      if pvdisplay "$dev_c" >/dev/null 2>&1; then
        return 0
      fi
    fi

    return 1
  }


  get_disk_partitions() {
    local disk="$1"
    local base
    base=$(basename "$disk")
    lsblk -ln -o NAME,PKNAME,TYPE 2>/dev/null | awk -v dk="$base" '$2==dk && $3=="part" {print "/dev/"$1}'
  }

  get_uuid() {
    local dev="$1"
    local u
    u=$(blkid -s UUID -o value "$dev" 2>/dev/null || true)
    u=$(printf '%s' "$u" | tr -d '[:space:]')
    if [ -n "$u" ]; then printf '%s' "$u"; return 0; fi
    u=$(blkid -s PARTUUID -o value "$dev" 2>/dev/null || true)
    u=$(printf '%s' "$u" | tr -d '[:space:]')
    if [ -n "$u" ]; then printf '%s' "$u"; return 0; fi
    printf ''
  }

  collect_partitions_fdisk() {
    local disk="$1"
    PART_DEV=()
    PART_SIZE=()
    PART_TYPE=()
    if ! cmd_exists fdisk; then
      while IFS= read -r name; do
        PART_DEV+=("/dev/$name")
        PART_SIZE+=("$(lsblk -no SIZE /dev/$name 2>/dev/null | head -n1 || echo unknown)")
        PART_TYPE+=("$(lsblk -no FSTYPE /dev/$name 2>/dev/null | head -n1 || echo unknown)")
      done < <(lsblk -ln -o NAME,TYPE "$disk" | awk '$2=="part"{print $1}')
      return 0
    fi

    local fdout
    fdout="$(fdisk -l "$disk" 2>/dev/null || true)"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if printf '%s\n' "$line" | grep -qE '^/dev/'; then
        device=$(awk '{print $1}' <<<"$line")
        case "$device" in
          "$disk"*) ;;
          *)
            if [[ "$(basename "$disk")" =~ ^nvme ]] && [[ "$device" == "${disk}p"* ]]; then
              :
            else
              continue
            fi
            ;;
        esac
        size_field=$(awk '{print $5}' <<<"$line")
        type_field=$(awk '{for(i=6;i<=NF;i++)printf $i (i<NF?OFS:" "); print ""}' <<<"$line")
        [ -z "$type_field" ] && type_field="unknown"
        PART_DEV+=("$device")
        PART_SIZE+=("$size_field")
        PART_TYPE+=("$type_field")
      fi
    done <<< "$fdout"

    if [ "${#PART_DEV[@]}" -eq 0 ]; then
      while IFS= read -r name; do
        PART_DEV+=("/dev/$name")
        PART_SIZE+=("$(lsblk -no SIZE /dev/$name 2>/dev/null | head -n1 || echo unknown)")
        PART_TYPE+=("$(lsblk -no FSTYPE /dev/$name 2>/dev/null | head -n1 || echo unknown)")
      done < <(lsblk -ln -o NAME,TYPE "$disk" | awk '$2=="part"{print $1}')
    fi
  }

  collect_uuid_map_for_disk() {
    local disk="$1"
    local arr=()
    while IFS= read -r p; do
      [ -n "$p" ] && arr+=("$p")
    done < <(get_disk_partitions "$disk")

    declare -A tmpmap=()
    for p in "${arr[@]:-}"; do
      if [ -b "$p" ]; then
        u="$(get_uuid "$p" || true)"
        if [ -n "$u" ]; then
          tmpmap["$u"]="$p"
        else
          tmpmap["<no-uuid>::$p"]="$p"
        fi
      fi
    done

    for k in "${!tmpmap[@]}"; do
      printf '%s\t%s\n' "$k" "${tmpmap[$k]}"
    done
  }

  sets_equal() {
    local -n a=$1; local -n b=$2
    local -A ma=()
    local -A mb=()
    for x in "${a[@]}"; do
      if [[ "$x" == "<no-uuid>::"* ]]; then continue; fi
      ma["$x"]=1
    done
    for x in "${b[@]}"; do
      if [[ "$x" == "<no-uuid>::"* ]]; then continue; fi
      mb["$x"]=1
    done
    if [ "${#ma[@]}" -ne "${#mb[@]}" ]; then return 1; fi
    for k in "${!ma[@]}"; do
      if [ -z "${mb[$k]:-}" ]; then return 1; fi
    done
    return 0
  }

  register_lvm_devices_oracle9_for_disk() {

    is_oracle_linux || return 0
    [ "${OS_MAJOR:-0}" -ge 9 ] || return 0
    command -v lvmdevices >/dev/null 2>&1 || return 0

    local disk="$1"

    echo
    echo "  Oracle Linux: "
    echo "    registering LVM devices for $disk.."
    echo
    while read -r dev type; do
      [ "$type" = "part" ] || continue
      [ -b "$dev" ] || continue

      if lvmdevices --adddev "$dev" --yes </dev/null >>"$LOGFILE" 2>&1; then
        echo "    [OK] $dev registered"
      else
        echo "    [SKIP] $dev not registered"
      fi

    done < <(lsblk -ln -o PATH,TYPE "$disk")
  }



  mount_common_helpers() {
    local mp="$1"
    mkdir -p "$mp"/proc "$mp"/sys "$mp"/dev "$mp"/dev/pts "$mp"/run 2>/dev/null || true

    run_and_log_cmd_plain "mount -t proc proc '$mp/proc' || true"
    run_and_log_cmd_plain "mount -t sysfs sysfs '$mp/sys' || true"
    run_and_log_cmd_plain "mount -o bind /dev '$mp/dev' || true"
    run_and_log_cmd_plain "mount -o bind /dev/pts '$mp/dev/pts' || true"
    run_and_log_cmd_plain "mount -o bind /run '$mp/run' || true"
  }

  umount_common_helpers() {
    local mp="$1"
    for p in "$mp/run" "$mp/dev/pts" "$mp/dev" "$mp/sys" "$mp/proc"; do
      if mountpoint -q "$p"; then
        run_and_log_cmd_plain "umount -l '$p' || true"
      fi
    done
  }

  mount_nonlvm_nonlvm_or_lvm_nonlvm() {
    local parent="$1"
    local mp="$2"
    local use_nouuid="$3"
    local nouuid_opt=""
    [ "$use_nouuid" = "yes" ] && nouuid_opt="-o nouuid"

    collect_partitions_fdisk "$parent"

    local boot_part="" efi_part="" root_part=""
    local biggest_size=0 biggest_dev=""

    for dev in "${PART_DEV[@]}"; do
      [ -z "$dev" ] && continue
      local size_bytes
      size_bytes="$(lsblk -nb -o SIZE "$dev" 2>/dev/null | head -n1 || echo 0)"
      size_bytes=${size_bytes:-0}
      if [ "$size_bytes" -gt "$biggest_size" ]; then
        biggest_size="$size_bytes"
        biggest_dev="$dev"
      fi
    done
    root_part="$biggest_dev"


    local MIN_BOOT_BYTES=$((200 * 1024 * 1024))    # 200MB (lower bound for /boot)
    local MAX_BOOT_BYTES=$((1536 * 1024 * 1024))   # 1.5GB (upper bound for /boot)
    local BIOS_MAX_BYTES=$((10 * 1024 * 1024))     # <=10MB treat as BIOS boot (skip)

    for i in "${!PART_DEV[@]}"; do
      dev="${PART_DEV[$i]}"
      [ -z "$dev" ] && continue
      fstype="$(lsblk -n -o FSTYPE "$dev" 2>/dev/null | head -n1 || true)"
      parttype="${PART_TYPE[$i]:-}"

      if printf '%s\n' "$parttype" | tr '[:upper:]' '[:lower:]' | grep -qi 'bios'; then
        continue
      fi

      if printf '%s\n' "$fstype" | grep -iq '^vfat$' || printf '%s\n' "$parttype" | grep -qi 'efi'; then
        efi_part="$dev"
        break
      fi
    done


    for i in "${!PART_DEV[@]}"; do
      dev="${PART_DEV[$i]}"
      [ -z "$dev" ] && continue

      if [ "$dev" = "$root_part" ]; then
        continue
      fi
      fstype="$(lsblk -n -o FSTYPE "$dev" 2>/dev/null | head -n1 || true)"
      parttype="${PART_TYPE[$i]:-}"
      size_bytes="$(lsblk -nb -o SIZE "$dev" 2>/dev/null | head -n1 || echo 0)"
      size_bytes=${size_bytes:-0}

      if [ "$size_bytes" -le "$BIOS_MAX_BYTES" ] || printf '%s\n' "$parttype" | tr '[:upper:]' '[:lower:]' | grep -qi 'bios'; then
        continue
      fi

      if printf '%s\n' "$fstype" | grep -Eqi '^(xfs|ext4|ext3|btrfs)$' || printf '%s\n' "$parttype" | grep -qi 'linux filesystem'; then
        if [ "$size_bytes" -ge "$MIN_BOOT_BYTES" ] && [ "$size_bytes" -le "$MAX_BOOT_BYTES" ]; then
          boot_part="$dev"
          break
        fi
      fi
    done


    if [ -z "$boot_part" ]; then
      for dev in "${PART_DEV[@]}"; do
        [ -z "$dev" ] && continue
        [ "$dev" = "$root_part" ] && continue
        size_bytes="$(lsblk -nb -o SIZE "$dev" 2>/dev/null | head -n1 || echo 0)"
        size_bytes=${size_bytes:-0}
        fstype="$(lsblk -n -o FSTYPE "$dev" 2>/dev/null | head -n1 || true)"

        if [ "$size_bytes" -le "$BIOS_MAX_BYTES" ]; then
          continue
        fi
        if [ "$size_bytes" -gt 0 ] && [ "$size_bytes" -le "$MAX_BOOT_BYTES" ]; then
          if printf '%s\n' "$fstype" | grep -Eqi '^(xfs|ext4|ext3|btrfs)$' || printf '%s\n' "${PART_TYPE[@]}" | grep -qi 'linux filesystem'; then
            boot_part="$dev"
            break
          fi
        fi
      done
    fi


    if [ -n "$boot_part" ] && [ -n "$efi_part" ] && [ "$boot_part" = "$efi_part" ]; then
      boot_part=""
    fi

    echo
    echo "[ Mount LV/FS ]"
    echo

    mkdir_must_succeed "$mp"

    if [ -n "$root_part" ]; then

      existing_target="$(findmnt -n -o TARGET -S "$root_part" 2>/dev/null || true)"
      if [ -n "$existing_target" ] && [ "$existing_target" != "$mp" ]; then
        run_and_log_cmd_plain "umount -l '$existing_target' || true"
      fi

      fstype_r="$(lsblk -n -o FSTYPE "$root_part" 2>/dev/null | head -n1 || true)"
      if [ "$fstype_r" = "xfs" ] && [ "$use_nouuid" = "yes" ]; then
        run_and_log_cmd_must_succeed "mount -o nouuid '$root_part' '$mp'"
      else
        run_and_log_cmd_must_succeed "mount '$root_part' '$mp'"
      fi

      state_record "$root_part" "$mp" "root"
    fi

    if [ -n "$boot_part" ]; then

      bsize="$(lsblk -nb -o SIZE "$boot_part" 2>/dev/null | head -n1 || echo 0)"

      if [ "$bsize" -le $((10 * 1024 * 1024)) ]; then
        echo "Skipping mount of $boot_part because its size ($bsize bytes) is <= BIOS threshold."
      else
        existing_target="$(findmnt -n -o TARGET -S "$boot_part" 2>/dev/null || true)"
        if [ -n "$existing_target" ] && [ "$existing_target" != "$mp/boot" ]; then
          run_and_log_cmd_plain "umount -l '$existing_target' || true"
        fi

        fstype_b="$(lsblk -n -o FSTYPE "$boot_part" 2>/dev/null | head -n1 || true)"
        if [ "$fstype_b" = "xfs" ]; then
          run_and_log_cmd_must_succeed "mount -o nouuid '$boot_part' '$mp/boot'"
        else
          run_and_log_cmd_must_succeed "mount '$boot_part' '$mp/boot'"
        fi
        state_record "$boot_part" "$mp/boot" "boot"
      fi
    fi

    if [ -n "$efi_part" ]; then
      existing_target="$(findmnt -n -o TARGET -S "$efi_part" 2>/dev/null || true)"
      if [ -n "$existing_target" ] && [ "$existing_target" != "$mp/boot/efi" ]; then
        run_and_log_cmd_plain "umount -l '$existing_target' || true"
      fi
      run_and_log_cmd_must_succeed "mount '$efi_part' '$mp/boot/efi'"
      state_record "$efi_part" "$mp/boot/efi" "efi"
    fi

    mount_common_helpers "$mp"
  }

  mount_lvm_lvm() {
    local parent="$1"
    local mp="$2"
    local use_nouuid="$3"
    echo
    echo "    LVM clone/mirror flow chosen. This will attempt vgimportclone and activate the VG."
    echo

    if ! cmd_exists pvs || ! cmd_exists vgimportclone; then
      echo "Required LVM tools (pvs/vgimportclone) are not available. Cannot proceed with method 2."
      return 1
    fi

    PV_ON_DEV=()
    for p in $(get_disk_partitions "$parent"); do
      if pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$p"; then
        PV_ON_DEV+=("$p")
      else
        if printf '%s\n' "$(lsblk -no FSTYPE "$p" 2>/dev/null | head -n1 || true)" | grep -iq 'LVM2_member'; then
          PV_ON_DEV+=("$p")
        fi
      fi
    done

    if [ "${#PV_ON_DEV[@]}" -eq 0 ]; then
      echo "No PVs discovered on $parent; listing pvs output for inspection."
      run_and_log_cmd_plain "pvs || true"
      echo "Cannot continue method 2 without detectable PV(s) on the user disk."
      return 1
    fi

    echo "    Detected potential OS partition on disk $parent: ${PV_ON_DEV[*]}"
    run_and_log_cmd_plain "pvs -o pv_name,vg_name,pv_uuid ${PV_ON_DEV[*]} 2>/dev/null || true"

  orig_vg_names=""

  for _pv in "${PV_ON_DEV[@]:-}"; do
    _vg="$(pvs --noheadings -o vg_name "$_pv" 2>/dev/null | awk '{$1=$1;print}' || true)"
    if [ -n "$_vg" ]; then
      if ! printf '%s\n' "$orig_vg_names" | tr '|' '\n' | grep -Fxq -- "$_vg"; then
        orig_vg_names="${orig_vg_names}${_vg}|"
      fi
      pv_short="$(basename "$_pv")"
      pv_key="$(printf '%s' "$pv_short" | sed 's/[^A-Za-z0-9]/_/g')"
      printf "ORIG_PV_VG_%s=%s\n" "$pv_key" "$_vg" >> "$STATEFILE"
    else
      pv_short="$(basename "$_pv")"
      pv_key="$(printf '%s' "$pv_short" | sed 's/[^A-Za-z0-9]/_/g')"
      printf "ORIG_PV_VG_%s=%s\n" "$pv_key" "<unknown>" >> "$STATEFILE"
    fi
  done 

  orig_vg_names="$(printf '%s' "$orig_vg_names" | sed 's/|$//')"

  if [ -n "$orig_vg_names" ]; then
    printf "ORIGINAL_VG=%s\n" "$orig_vg_names" >> "$STATEFILE"
    echo "Recorded ORIGINAL_VG='$orig_vg_names' in $STATEFILE" >> "$LOGFILE"
  else

    echo "No VG name detected on provided PV(s); recorded no ORIGINAL_VG." >> "$LOGFILE"
  fi

    provided_parents=()
    for pv in "${PV_ON_DEV[@]:-}"; do
      parent="$pv"
      while true; do
        pk=$(lsblk -n -o PKNAME "$parent" 2>/dev/null | head -n1 || true)
        pk="$(printf '%s' "$pk" | tr -d '[:space:]')"
        if [ -z "$pk" ] || [ "$pk" = "-" ]; then
          break
        fi
        parent="/dev/$pk"
      done
      provided_parents+=("$parent")
    done
    provided_parents=($(printf "%s\n" "${provided_parents[@]}" | awk 'NF' | sort -u || true))
    all_disks=($(lsblk -dn -o NAME 2>/dev/null | awk '{print "/dev/" $1}'))

    candidate_disks=()
    for d in "${all_disks[@]:-}"; do
      skip=0
      for pd in "${provided_parents[@]:-}"; do
        if [ "$d" = "$pd" ]; then skip=1; break; fi
      done
      [ $skip -eq 1 ] && continue
      candidate_disks+=("$d")
    done

    OS_CAND_PVS=()
    for disk in "${candidate_disks[@]:-}"; do
      fdout="$(fdisk -l "$disk" 2>/dev/null || true)"
      if printf '%s\n' "$fdout" | grep -qEi 'HPFS/NTFS/exFAT'; then
        continue
      fi
      skip_by_fstype=0
      while IFS= read -r part; do
        fstype="$(lsblk -dn -o FSTYPE "$part" 2>/dev/null | head -n1 || true)"
        if printf '%s\n' "$fstype" | grep -qEi 'ntfs|exfat'; then
          skip_by_fstype=1
          break
        fi
      done < <(lsblk -ln -o NAME "$disk" | sed '1d' | awk '{print "/dev/"$1}')
      if [ $skip_by_fstype -eq 1 ]; then
        echo "Skipping disk $disk (azure temp disk detected via partition fstype)."
        continue
      fi

      os_part=""
      cand=""
      if [ -n "$fdout" ]; then
        while IFS= read -r line; do
          case "$line" in
            /dev/*)
              part=$(awk '{print $1}' <<<"$line")
              type_field=$(awk '{for(i=6;i<=NF;i++)printf $i (i<NF?OFS:" "); print ""}' <<<"$line")
              if printf '%s\n' "$type_field" | grep -qi 'Linux LVM'; then
                os_part="$part"
                break
              fi

              if printf '%s\n' "$type_field" | grep -Eqi 'Linux filesystem|Linux'; then
                [ -z "$cand" ] && cand="$part"
              fi
              ;;
            *)
              ;;
          esac
        done <<< "$fdout"
      fi

      if [ -z "$os_part" ]; then
        os_part="$cand"
      fi

      if [ -z "$os_part" ]; then
        largest_line=$(lsblk -nr -o NAME,SIZE,TYPE "$disk" 2>/dev/null | awk '$3=="part"{print $1" "$2}' | sort -k2 -h | tail -n1 || true)
        if [ -n "$largest_line" ]; then
          pname=$(awk '{print $1}' <<<"$largest_line")
          os_part="/dev/$pname"
        fi
      fi


      if [ -n "$os_part" ]; then
        echo
        echo "    Detected potential OS partition on disk $disk : $os_part"
        run_and_log_cmd_plain "pvs -o pv_name,vg_name,pv_uuid $os_part 2>/dev/null || true"
        vgname="$(pvs --noheadings -o vg_name "$os_part" 2>/dev/null | awk '{$1=$1;print}')"
        if [ -n "$vgname" ]; then
          echo
          printf "    Device-mapper entries of $os_part (searching for VG name: %s):\n" "$vgname"
          echo
          printf "      Matches for VG name: %s\n" "$vgname"
          dmsetup ls 2>/dev/null | awk -v VG="$vgname" 'BEGIN{IGNORECASE=1}
            $1 ~ VG {
              mm=$2; gsub(/[()]/,"",mm);
              printf "      %s -> %s\n", $1, mm
            }' || true
        fi
        OS_CAND_PVS+=("$os_part")
      else
        echo
        echo "No suitable OS partition detected on disk $disk (skipping)." | tee -a "$LOGFILE"
      fi
    done

    if [ "${#OS_CAND_PVS[@]}" -eq 0 ]; then
      echo
      echo "Warning: no OS PV partition detected on other attached disks." | tee -a "$LOGFILE"
    fi
  
      read -r -p "Proceed with vgimportclone on PV ${PV_ON_DEV[*]}? (y/yes or n/no) [Default: no]: " ans
      ans="${ans:-no}"
      ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"

      if [ "$ans" != "y" ] && [ "$ans" != "yes" ]; then
          echo "Skipping vgimportclone step. You can perform manual import later."
          return 1
      fi

      
      suggested_vg=""
      if [ "${#PV_ON_DEV[@]}" -gt 0 ]; then
          first_pv="${PV_ON_DEV[0]}"
          suggested_vg="$(pvs --noheadings -o vg_name "$first_pv" 2>/dev/null | awk '{$1=$1;print}' || true)"
          suggested_vg="$(printf '%s' "$suggested_vg" )"
      fi

      rescue_vg_list=""
      if [ "${#OS_CAND_PVS[@]}" -gt 0 ]; then
          for rpv in "${OS_CAND_PVS[@]}"; do
          rv="$(pvs --noheadings -o vg_name "$rpv" 2>/dev/null | awk '{$1=$1;print}' || true)"
          rv="$(printf '%s' "$rv")"
          [ -n "$rv" ] && rescue_vg_list="${rescue_vg_list}${rv}|"
          done
          rescue_vg_list="$(printf '%s' "$rescue_vg_list" | sed 's/|$//')"
      fi

      default_vg="rescuemevg"
      if [ -n "$suggested_vg" ]; then
          default_vg="$suggested_vg"
      fi

      collision_warning="no"
      collision_vg_name=""

      if [ -n "$suggested_vg" ] && [ -n "$rescue_vg_list" ]; then
          if printf '%s\n' "$rescue_vg_list" | tr '|' '\n' | grep -xq -- "$suggested_vg"; then
          echo
          echo "WARNING: "
          echo "        The user disk (${PV_ON_DEV[*]}) VG name and the rescue-VM OS disk ($os_part) VG name are the SAME: '$suggested_vg'."
          echo "        If you import using the same name ('$suggested_vg'), you WILL create a VG name collision on this rescue VM."
          echo "Recommendation: "
          echo "              Choose a different import name (for example: 'rescuemevg')."
          echo
          collision_warning="yes"
          collision_vg_name="$suggested_vg"
          default_vg="rescuemevg"
          echo "Suggested action: "
          echo "                Pick a different VG name (Default: $default_vg)."
          else
          echo
          echo "Detected user-disk VG: $suggested_vg"
          echo "No matching VG with that name was found on rescue VM OS disk candidates (${rescue_vg_list:-<none>})."
          echo "You may import with that name. Suggested default: $default_vg"
          fi
      else
          echo
          if [ -z "$suggested_vg" ]; then
          echo "Could not determine VG name on the provided PV(s). Default will be: $default_vg"
          else
          echo "Could not determine VG name on rescue VM OS disk(s). Suggested default: $default_vg"
          fi
      fi

      echo
      read -r -p "Enter VG name, or press enter for default $default_vg [q to quit]: " user_vgname
      
      if [ "$user_vgname" = "q" ] || [ "$user_vgname" = "Q" ]; then
          echo "User chose to quit. Exiting."
          exit 0
      fi
      user_vgname="${user_vgname:-$default_vg}"
    if command -v vgs >/dev/null 2>&1; then
      if vgs --noheadings -o vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$user_vgname"; then
        echo
        echo "WARNING: a volume group named '$user_vgname' already exists on this system."
        while true; do
          read -r -p "Do you want to (o)verwrite/replace, (e)nter a different name, or (c)ancel vgimportclone? [e/c]: " _choice
          _choice="$(printf '%s' "$_choice" | tr '[:upper:]' '[:lower:]')"
          case "$_choice" in
            o|overwrite)
              echo "Proceeding with vgimportclone using existing name (may fail if VG active)."
              break
              ;;
            e|enter)
              read -r -p "Enter alternate VG name to import (or q to cancel): " alt
              if [ -z "$alt" ]; then
                echo "No name entered; please enter a name or 'q' to cancel."
                continue
              fi
              if [ "$alt" = "q" ] || [ "$alt" = "Q" ]; then
                echo "User cancelled vgimportclone."
                return 1
              fi
              user_vgname="$alt"
              echo "Using alternate VG name: $user_vgname"
              break
              ;;
            c|cancel|q)
              echo "User cancelled vgimportclone."
              return 1
              ;;
            *)
              echo "Please answer 'o' (overwrite), 'e' (enter new name) or 'c' (cancel)."
              ;;
          esac
        done
      fi
    fi

    echo
    echo "[ Import VG ]"
    run_and_log_cmd_must_succeed "vgimportclone -n '$user_vgname' ${PV_ON_DEV[*]}"
    printf "IMPORTED_VG=%s\n" "$user_vgname" >> "$STATEFILE"
    printf "IMPORTED_FROM_DISK=%s\n" "${user_disk_short:-}" >> "$STATEFILE"

    echo
    echo "[ Activate VG ] "
    run_and_log_cmd_must_succeed "vgchange -ay '$user_vgname'"
    echo
    echo "[ Block devices ]"
    echo
    run_and_log_cmd_plain "lsblk -f || true"

    if [ "${collision_warning:-no}" = "yes" ] && [ -n "${collision_vg_name:-}" ]; then
      if vgs --noheadings -o vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$collision_vg_name"; then
        if command -v vgrename >/dev/null 2>&1; then
          target_oldvg="oldvg"
          if vgs --noheadings -o vg_name 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$target_oldvg"; then
            target_oldvg="oldvg-$(date '+%Y%m%d%H%M%S')"
          fi
          echo
          echo "Note: "
          echo "    Collision warning was shown earlier for VG '$collision_vg_name'."
          if is_rhel && [ -n "$OS_MAJOR" ] && [ "$OS_MAJOR" -ge 9 ]; then
            echo "Since rescue VM's OS major version is $OS_MAJOR; skipping live vgrename to avoid live-device remap disruptions." | tee -a "$LOGFILE"
            echo
            printf "OS_VG_RENAME_SKIPPED=yes\n" >> "$STATEFILE"
            printf "OS_VG_RENAME_SKIPPED_REASON=OS_major_%s_ge_9\n" "$OS_MAJOR" >> "$STATEFILE"
          else
            echo
            echo "[ VG rename ]"
            echo "  Attempting to rename rescue-VM VG '$collision_vg_name' -> '$target_oldvg' to avoid collision..."
            echo
            
            STATE_FILE="${LOGFILE%.log}.state"
            {
            echo "OS_VG_RENAMED=yes"
            echo "OS_VG_ORIG_NAME=$collision_vg_name"
            echo "OS_VG_NEW_NAME=$target_oldvg"
            echo "BEGIN_DMSETUP_OSVG_ORIG"
            dmsetup ls 2>/dev/null | grep -i "$collision_vg_name" || true
            echo "END_DMSETUP_OSVG_ORIG"
            } >> "$STATE_FILE"
            run_and_log_cmd_must_succeed "vgrename '$collision_vg_name' '$target_oldvg'"
            echo "Rescue VG renamed: $collision_vg_name -> $target_oldvg" >> "$LOGFILE"
          fi
        else
          echo "ERROR: vgrename not available; aborting as requested." | tee -a "$LOGFILE"
          exit 1
        fi
      else
        echo "Note: expected rescue VG '$collision_vg_name' not found at rename time; continuing." >> "$LOGFILE"
      fi
    fi
    
    mkdir_must_succeed "$mp"


    echo
    echo "[ Mount LV/FS ]"
    echo

    for lvpath in /dev/mapper/"$user_vgname"-*; do
        if [ ! -e "$lvpath" ]; then
          continue
        fi
        lvname=$(basename "$lvpath")
        
        case "$lvname" in
        *root*|*rootlv*|*rootvg*)
          tgt="$mp"
          mkdir_must_succeed "$tgt"
          fstype_lv="$(lsblk -n -o FSTYPE "$lvpath" 2>/dev/null | head -n1 || true)"
          if [ "$fstype_lv" = "xfs" ]; then
            run_and_log_cmd_must_succeed "mount -o nouuid '$lvpath' '$tgt'"
          else
            run_and_log_cmd_must_succeed "mount '$lvpath' '$tgt'"
          fi

          state_record "$lvpath" "$tgt" "lv"
          ;;
      esac
    done

    for lvpath in /dev/mapper/"$user_vgname"-*; do
      if [ ! -e "$lvpath" ]; then
        continue
      fi
      lvname=$(basename "$lvpath")
        case "$lvname" in
          *root*|*rootlv*|*rootvg*) continue ;;
        esac      
        case "$lvname" in
          *home*) tgt="$mp/home" ;;
          *var*)  tgt="$mp/var" ;;
          *usr*)  tgt="$mp/usr" ;;
          *tmp*)  tgt="$mp/tmp" ;;
          *opt*)  tgt="$mp/opt" ;;
          *crash*) tgt="$mp/var/crash"  ;; 
          *) tgt="$mp/$lvname" ;;
        esac

      fstype_lv="$(lsblk -n -o FSTYPE "$lvpath" 2>/dev/null | head -n1 || true)"
      
      if [ "$fstype_lv" = "xfs" ]; then
        run_and_log_cmd_must_succeed "mount -o nouuid '$lvpath' '$tgt'"
      else        
        if [ "$fstype_lv" = "xfs" ] && [ "$use_nouuid" = "yes" ]; then
          run_and_log_cmd_must_succeed "mount -o nouuid '$lvpath' '$tgt'"
        else
          run_and_log_cmd_must_succeed "mount '$lvpath' '$tgt'"
        fi
      fi
      state_record "$lvpath" "$tgt" "lv"
    done

    collect_partitions_fdisk "$parent"
    
    declare -A os_boot_uuid_map=()
    {
      os_boot_src="$(findmnt -n -o SOURCE /boot 2>/dev/null || true)"
      os_efi_src="$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || true)"

      if [ -n "$os_boot_src" ]; then
        u="$(get_uuid "$os_boot_src" || true)"
        [ -n "$u" ] && os_boot_uuid_map["$u"]="/boot"
      fi

      if [ -n "$os_efi_src" ]; then
        u="$(get_uuid "$os_efi_src" || true)"
        [ -n "$u" ] && os_boot_uuid_map["$u"]="/boot/efi"
      fi
    } >/dev/null 2>&1


    boot_part=""
    efi_part=""
    boot_fstype=""

    for i in "${!PART_DEV[@]}"; do
      pdev="${PART_DEV[$i]}"
      ptype="${PART_TYPE[$i]}"
      lptype="$(printf '%s' "$ptype" | tr '[:upper:]' '[:lower:]')"
      puuid="$(get_uuid "$pdev" || true)"
      s="$(lsblk -nb -o SIZE "$pdev" 2>/dev/null | head -n1 || echo 0)"
      s=${s:-0}
      fstype_p="$(lsblk -n -o FSTYPE "$pdev" 2>/dev/null | head -n1 || true)"
      if printf '%s\n' "$lptype" | grep -qi 'bios' || [ "$s" -le $((10*1024*1024)) ]; then
        continue
      fi
      if printf '%s\n' "$fstype_p" | grep -iq 'lvm2_member'; then
        continue
      fi
      if [ -z "$efi_part" ] && \
        ( printf '%s\n' "$lptype" | grep -qi 'efi' || \
          printf '%s\n' "$fstype_p" | grep -qi '^vfat$' ); then
        efi_part="$pdev"
        continue
      fi
      if [ -z "$boot_part" ] && \
        ! printf '%s\n' "$lptype" | grep -qi 'efi' && \
        ! printf '%s\n' "$fstype_p" | grep -qi 'vfat' && \
        printf '%s\n' "$fstype_p" | grep -Eqi 'linux filesystem|Linux extended boot|Microsoft basic|Microsoft basic data|xfs|ext4|ext3|btrfs|Linux' && [ "$s" -gt $((200*1024*1024)) ] && [ "$s" -le $((2*1024*1024*1024)) ]; then
        boot_part="$pdev"
        boot_fstype="$fstype_p"
        continue
      fi
      done


      if [ -n "$boot_part" ]; then
        existing_target="$(findmnt -n -o TARGET -S "$boot_part" 2>/dev/null || true)"
        if [ -n "$existing_target" ] && [ "$existing_target" != "$mp/boot" ]; then
          run_and_log_cmd_plain "umount -l '$existing_target' || true"
        fi

        if [ "$boot_fstype" = "xfs" ]; then
          run_and_log_cmd_must_succeed "mount -o nouuid '$boot_part' '$mp/boot'"
        else
          run_and_log_cmd_must_succeed "mount '$boot_part' '$mp/boot'"
        fi
        state_record "$boot_part" "$mp/boot" "boot"
      fi

      if [ -n "$efi_part" ]; then
        existing_target="$(findmnt -n -o TARGET -S "$efi_part" 2>/dev/null || true)"
        if [ -n "$existing_target" ] && [ "$existing_target" != "$mp/boot/efi" ]; then
          run_and_log_cmd_plain "umount -l '$existing_target' || true"
        fi

        run_and_log_cmd_must_succeed "mount '$efi_part' '$mp/boot/efi'"
        state_record "$efi_part" "$mp/boot/efi" "efi"
      fi

    mount_common_helpers "$mp"

      orig_vg="$(awk -F= '/^ORIGINAL_VG=/{print $2}' "$STATEFILE" | head -n1)"
      imported_vg="$(awk -F= '/^IMPORTED_VG=/{print $2}' "$STATEFILE" | head -n1)"

    if is_rhel && [ -n "$OS_MAJOR" ] && [ "$OS_MAJOR" -ge 9 ]; then
      printf "\n"
      printf "⚠️  WARNING ($OS_PRETTY >= 9):\n"
      printf "  Do NOT perform manual VG rename inside chroot.\n"
      printf "  On $OS_PRETTY, manual VG renaming can cause boot or initramfs issues.\n"
      printf "  VG name handling and restoration is automatically managed by umount-helper.sh.\n"
      printf "  No manual VG rename action is required on this OS version.\n"
    elif [ -n "$orig_vg" ] && [ -n "$imported_vg" ] && [ "$orig_vg" = "$imported_vg" ]; then
      printf "⚠️  NOTE:\n"
      printf "  No VG rename is required inside chroot.\n"
      printf "  Imported VG name $orig_vg' already matches the original VG name.\n"
    else 
      printf "\n"
      printf "⚠️  NOTE:\n"
      printf "  After chroot, you may want to run:\n"
      printf "    vgrename $imported_vg $orig_vg \n"
      printf "  This is a MANUAL step and must be done inside the chroot environment.\n"
    fi

  }

  mount_nonlvm_with_user_lvm() {
    local parent="$1"
    local mp="$2"
    local use_nouuid="${3:-no}"    # accept optional use_nouuid flag

    if ! cmd_exists vgchange || ! cmd_exists vgscan; then
      echo "LVM tools not present; cannot activate user LVs. Please install lvm2 and retry."
      return 1
    fi

    echo
    echo "[ vgscan ]"
    run_and_log_cmd_must_succeed "vgscan --mknodes"
    echo
    echo "[ vgchange ]"
    run_and_log_cmd_must_succeed "vgchange -ay"
    echo
    echo "[ lvscan ]"
    run_and_log_cmd_must_succeed "lvscan"
    echo
    local vgname
    vgname="$(
    pvs --noheadings -o pv_name,vg_name 2>/dev/null |
    awk -v d="$parent" '$1 ~ "^"d {print $2}' |
    head -n1
    )"

    if [ -z "$vgname" ]; then
    echo "ERROR: Unable to detect VG name from $parent"
    return 1
    fi
    echo [ vgname ]
    echo "  Detected VG on $parent: $vgname"
    echo
    echo
    echo "[ Mount LV/FS ]"

    mkdir_must_succeed "$mp"
    
    for lv in /dev/mapper/"$vgname"-*; do
      [ -e "$lv" ] || continue
      lvname=$(basename "$lv")
        case "$lvname" in
        *-root*|*rootlv*)
          tgt="$mp"
          mkdir_must_succeed "$tgt"

          run_and_log_cmd_must_succeed "mount '$lv' '$tgt'"
          state_record "$lv" "$tgt" "lv"

          if ! mountpoint -q "$tgt"; then
            echo "ERROR: failed to mount root LV $lv -> $tgt" | tee -a "$LOGFILE"
            run_and_log_cmd_plain "dmesg | tail -n 20 || true"
            return 1
          fi
          ;;
      esac
    done

    for lv in /dev/mapper/"$vgname"-*; do
      [ -e "$lv" ] || continue
      [ -b "$lv" ] || continue

      lvname="$(basename "$lv")"
      [ "$lvname" = "control" ] && continue
      case "$lvname" in
        *-root*|*rootlv*) continue ;;
      esac

      case "$lvname" in
        *home*) tgt="$mp/home" ;;
        *var*)  tgt="$mp/var"  ;;
        *usr*)  tgt="$mp/usr"  ;;
        *tmp*)  tgt="$mp/tmp"  ;;
        *opt*)  tgt="$mp/opt"  ;;  
        *crash*) tgt="$mp/var/crash"  ;;  
        *) tgt="$mp/$lvname" ;;
      esac
      
      run_and_log_cmd_must_succeed "mount '$lv' '$tgt'"
      state_record "$lv" "$tgt" "lv"

      if ! mountpoint -q "$tgt"; then
        echo "ERROR: failed to mount LV $lv -> $tgt" | tee -a "$LOGFILE"
        run_and_log_cmd_plain "mount '$lv' '$tgt' || true"
        run_and_log_cmd_plain "dmesg | tail -n 20 || true"
      fi
    done

    collect_partitions_fdisk "$parent"
    boot_part=""
    efi_part=""
    boot_fstype=""

    for i in "${!PART_DEV[@]}"; do
      pdev="${PART_DEV[$i]}"
      ptype="${PART_TYPE[$i]}"
      lptype="$(printf '%s' "$ptype" | tr '[:upper:]' '[:lower:]')"
      puuid="$(get_uuid "$pdev" || true)"
    s="$(lsblk -nb -o SIZE "$pdev" 2>/dev/null | head -n1 || echo 0)"
    s=${s:-0}
    fstype_p="$(lsblk -n -o FSTYPE "$pdev" 2>/dev/null | head -n1 || true)"
    if printf '%s\n' "$lptype" | grep -qi 'bios' || [ "$s" -le $((10*1024*1024)) ]; then
      continue
    fi

    if printf '%s\n' "$fstype_p" | grep -iq 'lvm2_member'; then
      continue
    fi

    if [ -z "$efi_part" ] && \
      ( printf '%s\n' "$lptype" | grep -qi 'efi' || \
        printf '%s\n' "$fstype_p" | grep -qi '^vfat$' ); then
      efi_part="$pdev"
      continue
    fi

    if [ -z "$boot_part" ] && \
      ! printf '%s\n' "$lptype" | grep -qi 'efi' && \
      ! printf '%s\n' "$fstype_p" | grep -qi 'vfat' && \
      printf '%s\n' "$fstype_p" | grep -Eqi 'linux filesystem|Linux extended boot|Microsoft basic|Microsoft basic data|xfs|ext4|ext3|btrfs|Linux' && [ "$s" -gt $((200*1024*1024)) ] && [ "$s" -le $((2*1024*1024*1024)) ]; then
      boot_part="$pdev"
      boot_fstype="$fstype_p"
      continue
    fi
  done

  if [ -n "$boot_part" ]; then
    existing_target="$(findmnt -n -o TARGET -S "$boot_part" 2>/dev/null || true)"
    if [ -n "$existing_target" ] && [ "$existing_target" != "$mp/boot" ]; then
      run_and_log_cmd_plain "umount -l '$existing_target' || true"
    fi

    if [ "$boot_fstype" = "xfs" ]; then
      run_and_log_cmd_must_succeed "mount -o nouuid '$boot_part' '$mp/boot'"
    else
      run_and_log_cmd_must_succeed "mount '$boot_part' '$mp/boot'"
    fi

    state_record "$boot_part" "$mp/boot" "boot"
  fi


  if [ -n "$efi_part" ]; then
    existing_target="$(findmnt -n -o TARGET -S "$efi_part" 2>/dev/null || true)"
    if [ -n "$existing_target" ] && [ "$existing_target" != "$mp/boot/efi" ]; then
      run_and_log_cmd_plain "umount -l '$existing_target' || true"
    fi

    run_and_log_cmd_must_succeed "mount '$efi_part' '$mp/boot/efi'"
    state_record "$efi_part" "$mp/boot/efi" "efi"
  fi

    mount_common_helpers "$mp"
  }

  perform_mounts_for_selected_device() {
    local device_canon="$1"
    local mp="$2"
    local provided_type
    provided_type="$(lsblk -dn -o TYPE "$device_canon" 2>/dev/null || true)"
    local parent_disk="$device_canon"
    if [ "$provided_type" != "disk" ]; then
      local pkname
      pkname="$(lsblk -dn -o PKNAME "$device_canon" 2>/dev/null || true)"
      if [ -n "$pkname" ]; then
        parent_disk="/dev/$pkname"
      fi
    fi

    local device_is_lvm="no"
    if is_lvm_strict "$device_canon"; then device_is_lvm="yes"; fi

    local os_is_lvm="no"
    if is_lvm_strict "${root_src:-/dev/sda}"; then os_is_lvm="yes"; fi

    uuids_match="no"
    if compare_uuid_sets "$parent_disk" "$rescuevm_os_disk_name"; then
      uuids_match="yes"
    else
      uuids_match="no"
    fi

    echo
    echo "[ Mount decision ]"
    echo "  Is rescue VM OS disk LVM?: $os_is_lvm"
    echo "  Is selected device LVM?: $device_is_lvm"
    echo "  Are both disks OS partitions UUID's matching?: $uuids_match"
    echo

    mkdir -p "$mp" 2>/dev/null || true

    if [ "$os_is_lvm" = "no" ] && [ "$device_is_lvm" = "no" ]; then
      printf "MOUNT_METHOD=%s\n" "1" >> "$STATEFILE"
      printf "MOUNT_METHOD_DESC=%s\n" "method 1 (non-lvm rescue OS, non-lvm user disk)" >> "$STATEFILE"
      echo "  Using method 1 (non-lvm rescue OS, non-lvm user disk)."
      mount_nonlvm_nonlvm_or_lvm_nonlvm "$parent_disk" "$mp" "$([ "$uuids_match" = "yes" ] && echo yes || echo no)"
      return $?
    fi

    if [ "$os_is_lvm" = "yes" ] && [ "$device_is_lvm" = "yes" ]; then
      printf "MOUNT_METHOD=%s\n" "2" >> "$STATEFILE"
      printf "MOUNT_METHOD_DESC=%s\n" "method 2 (rescue OS LVM, user disk LVM: clone style)" >> "$STATEFILE"
      echo "  Using method 2 (rescue OS LVM, user disk LVM: clone style)."
      mount_lvm_lvm "$parent_disk" "$mp" "$([ "$uuids_match" = "yes" ] && echo yes || echo no)"
      return $?
    fi

    if [ "$os_is_lvm" = "no" ] && [ "$device_is_lvm" = "yes" ]; then
      printf "MOUNT_METHOD=%s\n" "3" >> "$STATEFILE"
      printf "MOUNT_METHOD_DESC=%s\n" "method 3 (rescue OS non-lvm, user disk LVM)" >> "$STATEFILE"
      echo "  Using method 3 (rescue OS non-lvm, user disk LVM)."
      mount_nonlvm_with_user_lvm "$parent_disk" "$mp" "$([ "$uuids_match" = "yes" ] && echo yes || echo no)"
      return $?
    fi


    if [ "$os_is_lvm" = "yes" ] && [ "$device_is_lvm" = "no" ]; then
      printf "MOUNT_METHOD=%s\n" "4" >> "$STATEFILE"
      printf "MOUNT_METHOD_DESC=%s\n" "method 4 (rescue OS LVM, user disk non-lvm)" >> "$STATEFILE"
      echo "  Using method 4 (rescue OS LVM, user disk non-lvm)."
      mount_nonlvm_nonlvm_or_lvm_nonlvm "$parent_disk" "$mp" "$([ "$uuids_match" = "yes" ] && echo yes || echo no)"
      return $?
    fi

    echo "  Unknown combination; no mounts attempted."
    return 1
  }


  compare_uuid_sets() {
    local disk1="$1"
    local disk2="$2"

    declare -A map1=()
    declare -A map2=()

    while IFS=$'\t' read -r uuid dev; do
      [ -z "$uuid" ] && continue
      [[ "$uuid" == "<no-uuid>::"* ]] && continue
      map1["$uuid"]=1
    done < <(collect_uuid_map_for_disk "$disk1")

    while IFS=$'\t' read -r uuid dev; do
      [ -z "$uuid" ] && continue
      [[ "$uuid" == "<no-uuid>::"* ]] && continue
      map2["$uuid"]=1
    done < <(collect_uuid_map_for_disk "$disk2")

    if [ "${#map1[@]}" -ne "${#map2[@]}" ]; then
      return 1
    fi

    for u in "${!map1[@]}"; do
      if [ -z "${map2[$u]:-}" ]; then
        return 1
      fi
    done

    return 0
  }


  timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

  echo
  echo "===================================================================="
  echo "  Mount Helper v1.0 ($(timestamp))"
  echo "===================================================================="
  echo


  echo "[ Rescue VM OS Details ]"

  printf "  OS: %s\n" "$OS_PRETTY"
  echo
  echo "OS: $OS_PRETTY" >> "$LOGFILE"


  echo "[ Logfile ]"
  printf "  Path: %s\n" "$LOGFILE"
  printf "  State: %s\n" "$STATEFILE"
  echo

  echo "Logfile: $LOGFILE" >> "$LOGFILE"
  echo "Statefile: $STATEFILE" >> "$LOGFILE"
  echo


  echo "[ Block devices ]"
  echo
  LSBLK_COLUMNS="NAME,UUID,TYPE,STATE,MAJ:MIN,SIZE,FSTYPE,MOUNTPOINT"
  if lsblk -o "$LSBLK_COLUMNS" >/dev/null 2>&1; then
    run_and_log_cmd_plain "lsblk -o $LSBLK_COLUMNS"
  else
    LSBLK_COLUMNS="NAME,UUID,TYPE,MAJ:MIN,SIZE,FSTYPE,MOUNTPOINT"
    run_and_log_cmd_plain "lsblk -o $LSBLK_COLUMNS"
  fi
  echo


  root_src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  root_src="${root_src%%[*}"
  if [ -z "$root_src" ]; then
    root_src="$(awk '$2=="/"{print $1; exit}' /proc/mounts 2>/dev/null || true)"
  fi
  os_lvm_status="Unknown"
  log_msg=""


  if [ -n "$root_src" ]; then
    if is_lvm_strict "$root_src"; then
      os_lvm_status="LVM"
      log_msg="Root source $root_src has LVM partitions (strict rule matched)"
    else
      os_lvm_status="Non-LVM"
      log_msg="Root source $root_src has no LVM partitions (strict rule)"
    fi
  else
    os_lvm_status="Unknown"
    log_msg="Could not determine root source device"
  fi

  echo
  echo "[ Rescue VM OS disk type ]"
  printf "  OS Disk(s) hosting root filesystem:"
  rescuevm_os_disks=()

  while read -r name type; do
    if [ "$type" = "disk" ]; then
      rescuevm_os_disks+=("/dev/$name")
    fi
  done < <(lsblk -r -sno NAME,TYPE "$root_src" 2>/dev/null)

  for d in "${rescuevm_os_disks[@]}"; do
    echo "  $d"
  done
  rescuevm_os_disk_name="${rescuevm_os_disks[0]:-}"
  if [ -z "$rescuevm_os_disk_name" ]; then
    echo "ERROR: Could not determine Rescue VM OS disk."
    echo "Root source was: $root_src" >> "$LOGFILE"
    exit 1
  fi
  printf "  OS disk is: %s\n" "$os_lvm_status"
  echo "  Root filesystem source : $root_src"
  echo "OS disk LVM check: $log_msg" >> "$LOGFILE"


  DEFAULT_MP="/rescue"
  while true; do
  echo
  echo -n "[ Create mountpoint directory ]"
  echo
  echo -n "  Enter mountpoint directory, or press enter to create default: ${DEFAULT_MP} [q to quit]: "

  read -r mp_input || { echo; echo "Input error"; exit 1; }
  if [ -z "$mp_input" ]; then
      MOUNTPOINT="$DEFAULT_MP"
  elif [ "$mp_input" = "q" ] || [ "$mp_input" = "Q" ]; then
      echo
      echo "Quitting as requested."
      echo "User quit at prompt" >> "$LOGFILE"
      echo "=== $SCRIPT_NAME finished at $(date -Iseconds) ===" >> "$LOGFILE"
      exit 0
  else
      MOUNTPOINT="$mp_input"
  fi

    echo "Chosen mountpoint: $MOUNTPOINT" >> "$LOGFILE"
    if [ -d "$MOUNTPOINT" ]; then
      printf "  Mountpoint exists: %s\n" "$MOUNTPOINT"
      echo "  Mountpoint exists: $MOUNTPOINT" >> "$LOGFILE"
    else
      echo
      echo "  Mountpoint $MOUNTPOINT does not exist — attempting to create..."
      echo ">>> CMD: mkdir -p '$MOUNTPOINT' && chmod 0755 '$MOUNTPOINT'" >> "$LOGFILE"
      if mkdir -p "$MOUNTPOINT" 2>&1 | sed 's/^/     /' | tee -a "$LOGFILE"; then
        chmod 0755 "$MOUNTPOINT" 2>/dev/null || true
        printf "  Created mountpoint: %s\n" "$MOUNTPOINT"
        echo "Created mountpoint: $MOUNTPOINT" >> "$LOGFILE"
      else
        printf "Failed to create mountpoint: %s\n" "$MOUNTPOINT"
        echo "Failed to create mountpoint: $MOUNTPOINT" >> "$LOGFILE"
        continue
      fi
    fi

    if mountpoint -q "$MOUNTPOINT" 2>/dev/null || findmnt -n "$MOUNTPOINT" >/dev/null 2>&1; then
      echo
      echo "Mountpoint is being actively used: $MOUNTPOINT"
      echo "Please provide a different mountpoint." >> "$LOGFILE"
      echo "Mountpoint actively used: $MOUNTPOINT" >> "$LOGFILE"
      continue
    fi

    if [ "$(ls -A "$MOUNTPOINT" 2>/dev/null | wc -l)" -gt 0 ]; then
      echo
      echo "Mountpoint contains data: $MOUNTPOINT"
      echo "Please provide a different (empty) mountpoint." >> "$LOGFILE"
      echo "Mountpoint contains data: $MOUNTPOINT" >> "$LOGFILE"
      continue
    fi

    printf "  Mountpoint ready: %s (not mounted, empty)\n" "$MOUNTPOINT"
    echo "  Mountpoint ready: $MOUNTPOINT" >> "$LOGFILE"
    printf "MOUNTPOINT=%s\n" "$MOUNTPOINT" >> "$STATEFILE"
    break
  done

  while true; do
    echo
    echo -n "[ Problem VM OS disk name ]"
    echo
    echo -n "  Enter disk device to mount (eg: /dev/sdc or /dev/nvme0n2 or sdc or nvme0n2) [q to quit]: "
    read -r user_input || { echo; echo "Input error"; exit 1; }
    if [ "$user_input" = "q" ] || [ "$user_input" = "Q" ]; then
      echo
      echo "Quitting as requested."
      echo "User quit at prompt" >> "$LOGFILE"
      echo "=== $SCRIPT_NAME finished at $(date -Iseconds) ===" >> "$LOGFILE"
      exit 0
    fi

    if [ -z "$user_input" ]; then
      echo
      echo "disk not available, enter a valid name."
      continue
    fi

    case "$user_input" in
      /dev/*) device="$user_input" ;;
      *) device="/dev/$user_input" ;;
    esac

    if [ ! -b "$device" ]; then
      echo
      echo "disk not available, enter a valid name."
      echo "Invalid device entered: $device" >> "$LOGFILE"
      continue
    fi

    device_canon="$(canon "$device")"
    user_disk_short="$(basename "$device")"
    printf "USER_DISK=%s\n" "$user_disk_short" >> "$STATEFILE"
    echo "Recorded USER_DISK=$user_disk_short in $STATEFILE" >> "$LOGFILE"


    if is_lvm_strict "$device_canon"; then
      dev_type_desc="LVM-based"
      pv_match=""
      if command -v pvs >/dev/null 2>&1; then
        if pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$device_canon"; then
          pv_match="$device_canon"
        else
          if [ "$(lsblk -dn -o TYPE "$device_canon" 2>/dev/null || true)" = "disk" ]; then
            while IFS= read -r child; do
              [ -z "$child" ] && continue
              child="/dev/$child"
              child_c="$(canon "$child")"
              if pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$child_c"; then
                pv_match="$child_c"
                break
              fi
            done < <(lsblk -ln -o NAME "$device_canon" 2>/dev/null | tail -n +2)
          fi
        fi
      fi

      if [ -n "$pv_match" ]; then
        device_type="LVM - Physical Volume (PV)"
        vgname="$(pvs --noheadings -o vg_name "$pv_match" 2>/dev/null | awk '{$1=$1;print}')"
        device_info="PV: $pv_match"
        [ -n "$vgname" ] && device_info="$device_info belongs to VG: $vgname"
          if [ -n "$vgname" ]; then
            printf "DISK_VG=%s\n" "$vgname" >> "$STATEFILE"
            echo "Recorded DISK_VG=$vgname (from disk metadata)" >> "$LOGFILE"
          else
            printf "DISK_VG=<unknown>\n" >> "$STATEFILE"
            echo "DISK_VG could not be determined from PV metadata" >> "$LOGFILE"
          fi
      else
        if printf '%s\n' "$device_canon" | grep -qE '^/dev/mapper/|^/dev/[^/]+/[^/]+'; then
          if command -v lvs >/dev/null 2>&1 && lvs --noheadings -o lv_path 2>/dev/null | awk '{$1=$1;print}' | grep -Fxq "$device_canon"; then
            device_type="LVM - Logical Volume (LV)"
            device_info="LV path: $device_canon"
          else
            device_type="LVM - Logical Volume (LV) (detected)"
            device_info="LVM member found on device or its partitions"
          fi
        else
          device_type="LVM - Physical Volume (PV) (on partition)"
          device_info="Device contains partition(s) that are PVs/LVs"
        fi
      fi
    else
      device_type="Non-LVM"
      device_info="No LVM metadata found on device or its partitions (strict rule)"
    fi

    echo
    printf "  Selected device: %s\n" "$device"
    printf "    Device type: %s\n" "$device_type"
    [ -n "$device_info" ] && printf "  (%s)\n" "$device_info"
    echo "  Selected device: $device" >> "$LOGFILE"
    echo "    Device type: $device_type $device_info" >> "$LOGFILE"

    parent_disk="$device_canon"

    register_lvm_devices_oracle9_for_disk "$parent_disk"

    
    provided_type="$(lsblk -dn -o TYPE "$device_canon" 2>/dev/null || true)"
    if [ "$provided_type" != "disk" ]; then
      pkname="$(lsblk -dn -o PKNAME "$device_canon" 2>/dev/null || true)"
      if [ -n "$pkname" ]; then
        parent_disk="/dev/$pkname"
      fi
    fi

    if [ -b "$parent_disk" ]; then
      collect_partitions_fdisk "$parent_disk"
      echo
      echo "  Partitions details:"
      printf "\n    %-18s\t%-8s\t%-28s\t%s\n" "Device" "Size" "Type" "Expected Mountpoints"
      printf "    %-18s\t%-8s\t%-28s\t%s\n" "------------------" "--------" "----------------------------" "--------------------"
      for i in "${!PART_DEV[@]}"; do
        dev="${PART_DEV[$i]}"
        size="${PART_SIZE[$i]:-unknown}"
        ptype="${PART_TYPE[$i]:-unknown}"
        lptype="$(printf '%s\n' "$ptype" | tr '[:upper:]' '[:lower:]')"      
        size_bytes="$(lsblk -nb -o SIZE "$dev" 2>/dev/null || echo 0)"
        fstype="$(lsblk -no FSTYPE "$dev" 2>/dev/null | head -n1 || true)"
        mp_display=""
        if printf '%s\n' "$lptype" | grep -Eqi 'linux lvm|Linux root (x86-64)'; then
          mp_display="OS filesystem partition"
        elif printf '%s\n' "$lptype" | grep -Eqi 'linux filesystem|Linux extended boot|Microsoft basic|Microsoft basic data|xfs|ext4|ext3|btrfs|Linux' && [ "$size_bytes" -gt $((200*1024*1024)) ] && [ "$size_bytes" -le $((2*1024*1024*1024)) ]; then
          mp_display="${MOUNTPOINT%/}/boot"
        elif printf '%s\n' "$lptype" | grep -Eqi 'EFI System|efi|vfat|FAT16'; then
          mp_display="${MOUNTPOINT%/}/boot/efi"
        elif printf '%s\n' "$lptype" | grep -qi 'BIOS boot'|| { [ "$size_bytes" -le $((10*1024*1024)) ] && [ -z "$fstype" ]; }; then
          mp_display=""
        else
          fstype_dev="$(lsblk -no FSTYPE "$dev" 2>/dev/null | head -n1 || true)"
          if printf '%s\n' "$fstype_dev" | grep -iq 'LVM2_member'; then
            mp_display="OS filesystem partition"
          else
            mp_display="${MOUNTPOINT%/}"
          fi
        fi      
        printf "    %-18s\t%-8s\t%-28s\t%s\n" "$dev" "$size" "$ptype" "${mp_display:-}" | tee -a "$LOGFILE"
      done
      echo
    fi


    echo "[ UUID comparison - strict set equality ]"
    echo "  Problem VM OS $parent_disk partitions UUIDs:"
    while IFS=$'\t' read -r k v; do
      if [ -z "$k" ]; then continue; fi
      if [[ "$k" == "<no-uuid>::"* ]]; then
        printf "    <no-uuid> -> %s\n" "$v"
      else
        printf "    %s -> %s\n" "$k" "$v"
      fi
    done < <(collect_uuid_map_for_disk "$parent_disk")

    echo "  Rescue VM OS disk partitions UUIDs:"
    while IFS=$'\t' read -r k v; do
      if [ -z "$k" ]; then continue; fi
      if [[ "$k" == "<no-uuid>::"* ]]; then
        printf "    <no-uuid> -> %s\n" "$v"
      else
        printf "    %s -> %s\n" "$k" "$v"
      fi
    done < <(collect_uuid_map_for_disk "$rescuevm_os_disk_name")

    if compare_uuid_sets "$parent_disk" "$rescuevm_os_disk_name"; then
      echo
      echo "    RESULT: ✅ Provided disk partitions 'UUIDs MATCH the OS disk partitions' UUIDs."
      uuid_match="yes"
    else
      echo
      echo "    RESULT: ❌ Provided disk partitions 'UUIDs DO NOT MATCH the OS disk partitions' UUIDs."
      uuid_match="no"
    fi


  rhel9_update_fstab_and_loader_to_uuid() {
    local OS_MAJOR="$1"
    is_rhel || return 0
    [ -z "$OS_MAJOR" ] && return 0
    [ "$OS_MAJOR" -lt 9 ] && return 0

    echo
    echo "[ RHEL9 UUID normalization for rescue VM ]"
    echo "  Rescue OS detected as RHEL $OS_MAJOR"

    local TS
    TS="$(date +%Y%m%d-%H%M%S)"

    declare -a BACKUP_FILES_CREATED=()
    declare -A LV_UUID_MAP=()
    while read -r dev uuid; do
      [ -n "$dev" ] && [ -n "$uuid" ] && LV_UUID_MAP["$dev"]="$uuid"
    done < <(
      lsblk -ln -o PATH,UUID | awk '$1 ~ "^/dev/mapper/" && $2 != ""'
    )

    local fstab_needs_fix="no"
    declare -a FSTAB_LVS_TO_UPDATE=()

    if [ -f /etc/fstab ]; then
      while read -r src mp _; do
        [[ "$src" =~ ^# ]] && continue
        [ -z "$src" ] && continue
        [ "$mp" = "/mnt" ] && continue

        if [[ "$src" =~ ^UUID=|^LABEL=|^PARTUUID= ]]; then
          continue
        fi

        if [[ "$src" =~ ^/dev/mapper/|^/dev/[^/]+/[^/]+ ]]; then
          if [ -n "${LV_UUID_MAP[$src]:-}" ]; then
            fstab_needs_fix="yes"
            FSTAB_LVS_TO_UPDATE+=("$src")
          fi
        fi
      done < /etc/fstab
    fi

    if [ "$fstab_needs_fix" = "yes" ]; then
      echo
      echo "  Non-UUID entries detected in /etc/fstab"
      echo "    The following entries will be converted to UUIDs:"
      for lv in "${FSTAB_LVS_TO_UPDATE[@]}"; do
        printf "      - %s -> UUID=%s\n" "$lv" "${LV_UUID_MAP[$lv]}"
      done

      local fstab_bak="/etc/fstab.bak.$TS"
      cp -p /etc/fstab "$fstab_bak"
      BACKUP_FILES_CREATED+=("$fstab_bak")

      for lv in "${FSTAB_LVS_TO_UPDATE[@]}"; do
        sed -i "s|^$lv[[:space:]]|UUID=${LV_UUID_MAP[$lv]} |" /etc/fstab
      done
    else
      echo "  /etc/fstab already uses UUIDs — skipping"
    fi

    declare -a LOADER_FILES_TO_UPDATE=()

    local root_dev
    local root_uuid
    root_dev="$(findmnt -n -o SOURCE /)"
    root_uuid="$(blkid -s UUID -o value "$root_dev" 2>/dev/null || true)"

    if [ -d /boot/loader/entries ]; then
      for f in /boot/loader/entries/*.conf; do
        [ -f "$f" ] || continue
        if grep -Eq 'root=/dev/mapper/|root=/dev/[^/]+/[^/]+' "$f"; then
          LOADER_FILES_TO_UPDATE+=("$f")
        fi
      done
    fi

    if [ "${#LOADER_FILES_TO_UPDATE[@]}" -gt 0 ] && [ -n "$root_uuid" ]; then
      echo
      echo "  Non-UUID root= detected in the following loader entries:"
      for f in "${LOADER_FILES_TO_UPDATE[@]}"; do
        echo "    - $(basename "$f")"
      done

      echo "    Updating kernel root device:"
      printf "      - %s -> root=UUID=%s\n" "$root_dev" "$root_uuid"

      for f in "${LOADER_FILES_TO_UPDATE[@]}"; do
        local bak="$f.bak.$TS"
        cp -p "$f" "$bak"
        BACKUP_FILES_CREATED+=("$bak")
        sed -i "s|root=$root_dev|root=UUID=$root_uuid|g" "$f"
      done
    else
      echo "  /boot/loader/entries already use UUIDs — skipping"
    fi

    if [ "$fstab_needs_fix" = "yes" ] || [ "${#LOADER_FILES_TO_UPDATE[@]}" -gt 0 ]; then
      echo
      echo "  fstab validation:"
      if findmnt --verify >/tmp/findmnt-verify.out 2>&1; then
        echo "    findmnt --verify: OK"
      else
        echo "    WARNING: findmnt --verify reported issues"
        cat /tmp/findmnt-verify.out | tee -a "$LOGFILE"
      fi
      rm -f /tmp/findmnt-verify.out

      printf "RHEL9_UUID_FIX_APPLIED=yes\n" >> "$STATEFILE"
    fi

    echo
    if [ "${#BACKUP_FILES_CREATED[@]}" -gt 0 ]; then
      echo "  Backups created (for reference):"
      for b in "${BACKUP_FILES_CREATED[@]}"; do
        echo "    $b"
      done
    else
      echo "  No backups were created."
    fi
  }

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    OS_MAJOR_TMP="$(printf '%s' "${VERSION_ID:-}" | sed -E 's/^([0-9]+).*/\1/')"
    rhel9_update_fstab_and_loader_to_uuid "$OS_MAJOR_TMP"
  fi
    echo
    perform_mounts_for_selected_device "$device_canon" "$MOUNTPOINT"
    echo
    printf "Script completed successfully after selecting %s (mountpoint: %s)\n" "$device" "$MOUNTPOINT" >> "$LOGFILE"
    printf "Script completed successfully.\n"
    echo "=== $SCRIPT_NAME finished at $(date -Iseconds) ==="
    echo "=== $SCRIPT_NAME finished at $(date -Iseconds) ===" >> "$LOGFILE"
    exit 0
  done

  exit 0
}

# ===================================================
# UMOUNT LOGIC (from umount-helper.sh)
# ===================================================

umount_helper() {

prog=$(basename "$0" 2>/dev/null || echo "umount-helper")

usage() {
  cat <<EOF
Usage: $prog <state-file>
  Example: $prog /var/log/mount-helper-20251126-044414.state
EOF
  exit 1
}

STATE_FILE="${1:-}"


if [ -z "$STATE_FILE" ]; then
  err "State file path is required."
  #usage
fi


if [ ! -f "$STATE_FILE" ]; then
  err "State file not found: $STATE_FILE"
  exit 2
fi


TS="$(date '+%Y%m%d-%H%M%S')"
LOGDIR="/var/log"
LOGFILE="${LOGDIR}/umount-helper-${TS}.log"


if ! touch "$LOGFILE" 2>/dev/null; then
  LOGFILE="/tmp/umount-helper-${TS}.log"
  touch "$LOGFILE" 2>/dev/null || {
    err "Failed to create logfile in /var/log and /tmp. Exiting."
    exit 1
  }
fi

exec > >(tee -a "$LOGFILE") 2> >(tee -a "$LOGFILE" >&2)


echo "[ Logfile ]"
  info "  Using state file: $STATE_FILE"
  info "  Logfile: $LOGFILE"


trim() { printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

normalize_user_disk() {
  local d="$1"
  if [ -z "$d" ]; then
    echo ""
    return 0
  fi
  if [[ "$d" =~ ^/dev/ ]]; then
    echo "$d"
  else
    echo "/dev/$d"
  fi
}

get_disk_partitions() {
  local parent="$1"
  local pbase


  pbase="$(basename "$parent")"


  lsblk -ln -o NAME,PKNAME,TYPE 2>/dev/null | awk -v pb="$pbase" '$2==pb && $3=="part" {print "/dev/"$1}'
}

state_file_disk_mount_targets() {
  local parent="$1"
  local base

  base="$(basename "$parent")"

  awk -v base="$base" -F'\t' '
    $2 == "MOUNT" {
      src=$3; tgt=$4;

      # Case 1: plain /dev paths (disk or partitions)
      if (src ~ /^\/dev\// && src !~ /^\/dev\/[A-Za-z0-9_-]+[\/]/) {
        if (index(src, "/dev/" base) == 1 || index(src, "/dev/" base) > 0) {
          print tgt
        }
        # Case 2: other device paths (e.g. device-mapper)
      } else {
        if (src ~ ("/dev/" base)) {
          print tgt
        }
      }
    }
  ' "$STATE_FILE" | sed -e 's/[[:space:]]*$//' -e '/^$/d' || true
}

state_file_all_mount_targets() {
  awk -F'\t' '$2 == "MOUNT" {print $4}' "$STATE_FILE" | sed -e 's/[[:space:]]*$//' -e '/^$/d' || true
}

state_file_mount_src_tgt_pairs() {
  awk -F'\t' '$2 == "MOUNT" {print $3 "|" $4 "|" $5}' "$STATE_FILE" | sed -e '/^$/d' || true
}

read_mount_method() {
  awk -F= '/^MOUNT_METHOD=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true
}

read_imported_vg() {
  awk -F= '/^IMPORTED_VG=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true
}

read_original_vg() {
  awk -F= '/^ORIGINAL_VG=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true
}

read_orig_pv_vg_mapping() {
  awk -F= '/^ORIG_PV_VG_/{print $1"="$2}' "$STATE_FILE" 2>/dev/null || true
}

try_unmount_once() {
  local target="$1"
  [ -z "$target" ] && return 1
  
  if [ "$target" != "/" ]; then target="${target%/}"; fi
  
  if ! findmnt -n -o TARGET --target "$target" >/dev/null 2>&1; then
    info "  Skipping (not mounted): $target"
    return 0
  fi

  info "  - $target"
  if umount -- "$target" >/dev/null 2>&1; then
    info "    status: OK"
    return 0
  fi
  
  info "    attempting lazy/force unmount"
  if umount -fl -- "$target" >/dev/null 2>&1; then
    info "    status: OK (lazy/force)"
    [ "$target" = "$MOUNTPOINT" ] && parent_unmounted=1
  return 0
  fi

  return 1
}

try_unmount() {
  local t="$1"
  if try_unmount_once "$t"; then
    return 0
  fi
  err "    status: failed (busy, will retry)"
  return 1
}


OS_VG_RENAMED=$(awk -F= '/^OS_VG_RENAMED=/{print $2;exit}' "$STATE_FILE" 2>/dev/null || true)
OS_VG_RENAMED="$(trim "$OS_VG_RENAMED")"

OS_VG_ORIG_NAME=$(awk -F= '/^OS_VG_ORIG_NAME=/{print $2;exit}' "$STATE_FILE" 2>/dev/null || true)
OS_VG_ORIG_NAME="$(trim "$OS_VG_ORIG_NAME")"

OS_VG_NEW_NAME=$(awk -F= '/^OS_VG_NEW_NAME=/{print $2;exit}' "$STATE_FILE" 2>/dev/null || true)
OS_VG_NEW_NAME="$(trim "$OS_VG_NEW_NAME")"

DISK_VG=""
if grep -q '^DISK_VG=' "$STATE_FILE"; then
  DISK_VG="$(awk -F= '/^DISK_VG=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true)"
  DISK_VG="$(trim "$DISK_VG")"
fi


OS_PRETTY="$(awk -F= '/^OS_PRETTY=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true)"
OS_PRETTY="$(trim "$OS_PRETTY")"

OS_ID="$(awk -F= '/^OS_ID=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true)"
OS_ID="$(trim "$OS_ID")"

OS_MAJOR="$(awk -F= '/^OS_MAJOR=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true)"
OS_MAJOR="$(trim "$OS_MAJOR")"

OS_VERSION_STATE="$(awk -F= '/^OS_VERSION=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true)"
OS_VERSION_STATE="$(trim "$OS_VERSION_STATE")"


OS_VER_MAJ="$(printf '%s' "$OS_VERSION_STATE" | sed -E 's/^([0-9]+).*/\1/;t; s/.*/0/')"
OS_VER_MIN="$(printf '%s' "$OS_VERSION_STATE" | sed -E 's/^[0-9]+\.([0-9]+).*/\1/;t; s/.*/0/')"


OS_VER_MAJ="${OS_VER_MAJ:-0}"
OS_VER_MIN="${OS_VER_MIN:-0}"

OS_DMSETUP_ORIG=$(awk '
  /^BEGIN_DMSETUP_OSVG_ORIG$/ {flag=1;next}
  /^END_DMSETUP_OSVG_ORIG$/   {flag=0}
  flag {print}
' "$STATE_FILE" 2>/dev/null || true)

USER_DISK_RAW=$(awk '
  /Selected device:/ {
    dev=$NF
  }
  END{
    if (dev != "") print dev;
  }
' "$STATE_FILE" 2>/dev/null || true)
USER_DISK_RAW="$(trim "$USER_DISK_RAW")"

if [ -z "$USER_DISK_RAW" ]; then
  LOGFILE_GUESS="${STATE_FILE%.state}.log"
  if [ -f "$LOGFILE_GUESS" ]; then
    USER_DISK_RAW=$(awk '
      /Selected device:/ {
        dev=$NF
      }
      END{
        if (dev != "") print dev;
      }
    ' "$LOGFILE_GUESS" 2>/dev/null || true)
    USER_DISK_RAW="$(trim "$USER_DISK_RAW")"
  fi
fi

if [ -z "$USER_DISK_RAW" ]; then
  USER_DISK_RAW=$(awk -F= '/^USER_DISK=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true)
  USER_DISK_RAW="$(trim "$USER_DISK_RAW")"
fi


USER_DISK="$(normalize_user_disk "$USER_DISK_RAW")"

if [ "$OS_VG_RENAMED" = "yes" ] || [ "$OS_VG_RENAMED" = "YES" ]; then
  info "State indicates Rescue VM OS VG was renamed from '$OS_VG_ORIG_NAME' to '$OS_VG_NEW_NAME' by mount-helper."
fi

MOUNT_METHOD="$(trim "$(read_mount_method)")"
MOUNT_METHOD_DESC="$(trim "$(awk -F= '/^MOUNT_METHOD_DESC=/{print $2; exit}' "$STATE_FILE" 2>/dev/null || true)")"

MOUNTPOINT=""
MOUNTPOINT=$(awk 'BEGIN{IGNORECASE=1}
  /^(Chosen mountpoint:|Mountpoint ready:|Mountpoint:|Chosen mountpoint|MOUNTPOINT=|MOUNTPOINT:)/ {
    line=$0
    if (match(line, /=/)) {
      sub(/^[^=]*=[[:space:]]*/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      print line; exit
    } else if (match(line, /:/)) {
      sub(/^[^:]*:[[:space:]]*/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      print line; exit
    } else {
      n=split(line, a, /[[:space:]]+/)
      print a[n]; exit
    }
  }
  /Mountpoint exists:/ {
    sub(/^[^:]*:[[:space:]]*/, "", $0)
    gsub(/[[:space:]]+$/, "", $0)
    print $0; exit
  }
' "$STATE_FILE" | tr -d '\r')

MOUNTPOINT="$(trim "$MOUNTPOINT")"

if [ -z "$MOUNTPOINT" ]; then
  info "Could not extract mountpoint from state file. Defaulting to /rescue"
  MOUNTPOINT="/rescue"
fi

if [ "$MOUNTPOINT" != "/" ]; then
  MOUNTPOINT="${MOUNTPOINT%/}"
fi

skip_vgrename="no"
if [ -n "$OS_PRETTY" ] && printf '%s\n' "$OS_PRETTY" | grep -qi 'red hat'; then
  maj="${OS_VER_MAJ:-0}"
  min="${OS_VER_MIN:-0}"

  if [ "$maj" -gt 8 ] || { [ "$maj" -eq 8 ] && [ "$min" -gt 10 ]; }; then
    skip_vgrename="yes"
  fi
fi


uuid_update_applicable="no"
if [ "$MOUNT_METHOD" = "2" ] \
  && printf '%s\n' "$OS_PRETTY" | grep -qi 'red hat' \
  && [ "${OS_VER_MAJ:-0}" -eq 9 ]; then
  uuid_update_applicable="yes"
fi


ORIGINAL_VG="$(trim "$(read_original_vg)")"
IMPORTED_VG="$(trim "$(read_imported_vg)")"

print_state_context() {
  echo
  echo "[ Sate File Context ]"
  printf "  Mount method        : %s (%s)\n" "$MOUNT_METHOD" "$MOUNT_METHOD_DESC"
  printf "  Rescue OS           : %s\n" "${OS_PRETTY:-<unknown>}"
  
  if [ "$skip_vgrename" = "yes" ]; then
    printf "  Policy              : RHEL > 8.10 → skip live vgrename\n"
  else
    printf "  Policy              : live vgrename permitted\n"
  fi
  
  printf "  User disk           : %s\n" "$USER_DISK"
  
  if [ "$uuid_update_applicable" = "yes" ]; then
  printf "  UUID normalization  : enabled \n"
  fi
  
  [ -n "${ORIGINAL_VG:-}" ] && printf "  Original VG         : %s\n" "$ORIGINAL_VG"
  [ -n "${IMPORTED_VG:-}" ] && printf "  Imported VG         : %s\n" "$IMPORTED_VG"
  printf "  Mountpoint          : %s\n" "$MOUNTPOINT"
  echo
}

print_state_context

escape_for_grep() { printf '%s' "$1" | sed -e 's/[][\.*^$(){}?+|\/]/\\&/g'; }
ESC_MP=$(escape_for_grep "$MOUNTPOINT")


candidates_raw=$(grep -oE "'$ESC_MP([^']*)?'" "$STATE_FILE" 2>/dev/null | sed "s/^'//;s/'$//" || true)

candidates_raw="$candidates_raw
$(grep -oE "$ESC_MP(/[^[:space:]'\"]*)?" "$STATE_FILE" 2>/dev/null || true)"


declare -A cand_map=()
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ "$p" != "/" ]; then
    p="${p%/}"
  fi
  cand_map["$p"]=1
done <<EOF
$candidates_raw
EOF

while IFS= read -r line; do
  case "$line" in
    *"$MOUNTPOINT"*)
      for token in $line; do
        case "$token" in
          "$MOUNTPOINT"*)
            t="${token%%,*}"
            t="${t%%;}"
            if [ "$t" != "/" ]; then
              t="${t%/}"
            fi
            [ -n "$t" ] && cand_map["$t"]=1
            ;;
        esac
      done
      ;;
  esac
done < "$STATE_FILE"


if [ "${#cand_map[@]}" -eq 0 ]; then
  info "No mount targets detected in state file; falling back to common children under ${MOUNTPOINT}"
  cand_map["$MOUNTPOINT/proc"]=1
  cand_map["$MOUNTPOINT/sys"]=1
  cand_map["$MOUNTPOINT/dev/pts"]=1
  cand_map["$MOUNTPOINT/dev"]=1
  cand_map["$MOUNTPOINT/run"]=1
  cand_map["$MOUNTPOINT/boot/efi"]=1
  cand_map["$MOUNTPOINT/boot"]=1
  cand_map["$MOUNTPOINT/home"]=1
  cand_map["$MOUNTPOINT/var"]=1
  cand_map["$MOUNTPOINT/usr"]=1
  cand_map["$MOUNTPOINT/tmp"]=1
  cand_map["$MOUNTPOINT/opt"]=1
  cand_map["$MOUNTPOINT"]=1
fi


candidates=()
for k in "${!cand_map[@]}"; do
  candidates+=("$k")
done

mounted_targets=()
for p in "${candidates[@]}"; do
  [ -z "$p" ] && continue
  if findmnt -n -o TARGET --target "$p" >/dev/null 2>&1; then
    mounted_targets+=("$p")
  fi
done

if [ "${#mounted_targets[@]}" -eq 0 ]; then
  info "No matching mounted targets were detected (from state file) on this system."
  info "Nothing to unmount. Exiting."
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 0
fi

sorted_targets=$(for t in "${mounted_targets[@]}"; do
  depth=$(printf '%s' "$t" | awk -F"/" '{print NF}')
  printf '%s\t%s\n' "$depth" "$t"
done | sort -rn | awk -F"\t" '{print $2}')

if [ -z "$MOUNT_METHOD" ] || [ "$MOUNT_METHOD" != "2" ]; then
  echo
  info "[ Umounting mount points ]"
  info "  Will attempt to unmount the following mounted targets (children first):"
  while IFS= read -r t; do
    [ -n "$t" ] && printf "  %s\n" "$t"
  done <<EOF
  $sorted_targets
EOF

  echo
  read -r -p "Proceed to unmount the above targets or press enter to default:quit ? (y/yes to proceed, q to quit): " ans

  ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  
  if [ "$ans" = "q" ]; then
    info "User requested quit. Exiting without changes."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 0
  fi
  
  if [ "$ans" != "y" ] && [ "$ans" != "yes" ]; then
    info "User declined. Exiting without changes."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 0
  fi
  
  info ""
  info "[ Unmount execution ]"
  info "→ First pass (children-first)"
  info ""

  parent_unmounted=0

  declare -a failed_once=()

while IFS= read -r target; do
  [ -z "$target" ] && continue
  
  if findmnt -n -o TARGET --target "$target" >/dev/null 2>&1; then
    if try_unmount "$target"; then
      :  # success → nothing to do
    else
      failed_once+=("$target")
    fi
    sleep 1
  else
    info "-> Skipping (not mounted): $target"
  fi
done <<EOF
$sorted_targets
EOF

  if [ "${#failed_once[@]}" -gt 0 ]; then
    info ""
    info "→ Retry after parent unmount"
          if [ "${parent_unmounted:-0}" -eq 1 ]; then
        info "  Parent $MOUNTPOINT was already unmounted (lazy/force); retrying failed targets."
      elif findmnt -n -o TARGET --target "$MOUNTPOINT" >/dev/null 2>&1; then
        info "Attempting to unmount parent mountpoint: $MOUNTPOINT"
        if umount -- "$MOUNTPOINT" >/dev/null 2>&1 || umount -fl -- "$MOUNTPOINT" >/dev/null 2>&1; then
          info "  Parent $MOUNTPOINT unmounted successfully; retrying failed targets."
          parent_unmounted=1
        else
          info "  Parent $MOUNTPOINT unmount failed; will still retry failed targets."
        fi
      else
        info "  Parent $MOUNTPOINT is not mounted; retrying failed targets directly."
        parent_unmounted=1
      fi
    
    declare -a still_failed=()
    for t in "${failed_once[@]}"; do
      if try_unmount "$t"; then
        :
      else
        still_failed+=("$t")
      fi
    done

    if [ "${#still_failed[@]}" -gt 0 ]; then
      err "The following targets remain mounted after retry: ${still_failed[*]}"
      for t in "${still_failed[@]}"; do
        err "Please manually unmount: $t"
      done
      read -r -p "After manual unmount(s), press ENTER to re-check or type 'q' to abort: " mancmd
      if [ "$mancmd" = "q" ] || [ "$mancmd" = "Q" ]; then
        err "User aborted. Exiting without further changes."
        info "=== $prog finished at $(date -Iseconds) ==="
        exit 3
      fi
      for t in "${still_failed[@]}"; do
        if findmnt -n -o TARGET --target "$t" >/dev/null 2>&1; then
          err "Still mounted: $t  -- aborting to avoid data corruption."
          info "=== $prog finished at $(date -Iseconds) ==="
          exit 4
        fi
      done
    fi
  fi

if [[ "$OS_ID" == "ol" && "$OS_MAJOR" == "8" ]]; then
    for mp in $(lsblk -ln -o MOUNTPOINT "$USER_DISK" | grep -v '^$' | grep -v '^/$'); do
        try_unmount "$mp"
    done
fi

  info "✓ All requested mounts unmounted successfully"
  
  if [ -z "$USER_DISK" ]; then
    err "Could not determine user disk to detach from state file. Please detach manually in the Azure portal."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 5
  fi

  USER_DISK="$(normalize_user_disk "$USER_DISK")"
  devbase="${USER_DISK#/dev/}"
  

  disk_type="unknown"
  case "$devbase" in
    sd[a-z]*)
      disk_type="scsi"
      ;;
    nvme*n*)
      disk_type="nvme"
      ;;
  esac
  echo
  info "[ Detach the ${devbase} disk from the kernel ]"
  info "  Detected type  : $disk_type"

  if [ "$disk_type" = "scsi" ]; then
    sysdel="/sys/block/$devbase/device/delete"

    if [ ! -w "$sysdel" ]; then
      err "Delete path '$sysdel' is not writable or does not exist; cannot detach kernel device automatically."
      err "Please detach the disk $USER_DISK in the Azure portal manually."
      info "=== $prog finished at $(date -Iseconds) ==="
      exit 6
    fi
    
    read -r -p "  Are you sure you want to DELETE ${devbase} disk from kernel? (type YES in CAPITAL to proceed, q to quit): " delans

    if [ "$delans" = "q" ] || [ "$delans" = "Q" ]; then
      info "Disk deletion aborted by user. Exiting without detaching disk."
      info "=== $prog finished at $(date -Iseconds) ==="
      exit 0
    fi

    if [ "$delans" != "YES" ]; then
      info "User did not type YES. Aborting disk detach."
      info "=== $prog finished at $(date -Iseconds) ==="
      exit 0
    fi

    if ! echo 1 > "$sysdel" 2>/dev/null; then
      err "Failed to write to $sysdel; aborting. Please detach disk manually from Azure portal."
      info "=== $prog finished at $(date -Iseconds) ==="
      exit 7
    fi

    info "Disk successfully detached from kernel."
    echo

  elif [ "$disk_type" = "nvme" ]; then

    echo
    err "NVMe disk '$USER_DISK' cannot be detached from the guest OS."
    err "Azure exposes NVMe disks via a shared controller."
    err "Kernel-level detach would remove ALL NVMe disks."
    echo
    info "ACTION REQUIRED:"
    info "  → Detach disk $USER_DISK from the Azure portal."
    info "  → Then confirm here."

    while :; do
      echo
      read -r -p "Type YES after detaching the disk in Azure portal (q to quit): " azans

      if [ "$azans" = "q" ] || [ "$azans" = "Q" ]; then
        info "User chose to quit. Disk detach not confirmed."
        info "=== $prog finished at $(date -Iseconds) ==="
        exit 0
      fi

      if [ "$azans" != "YES" ]; then
        err "Invalid input."
        err "Please detach the disk from Azure portal and type YES, or q to quit."
        continue
      fi

      if [ -b "$USER_DISK" ]; then
        err "Disk $USER_DISK is STILL EXISTS in the kernel."
        err "Azure detach has NOT completed yet."
        info "Please detach the disk from the Azure portal and try again."
        continue
      fi

      devbase="${USER_DISK#/dev/}"
      if [ -e "/sys/block/$devbase" ]; then
        err "Disk $USER_DISK still exists under /sys/block."
        err "Detach is not complete yet."
        continue
      fi

      info "Confirmed: $USER_DISK is no longer present in the kernel."
      break
    done
  fi

  if [ "$MOUNT_METHOD" = "1" ]; then
    info "Script completed successfully."
    info "Please detach the disk $USER_DISK from the Azure portal now."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 0
  fi
    
  info "[ Device-mapper cleanup ]"
  info "  Removing device-mapper nodes for disk VG: $DISK_VG"
  
  mapfile -t dm_nodes < <(
    dmsetup ls 2>/dev/null | awk -v VG="$DISK_VG" '$1 ~ "^"VG"-" {print $1}'
  )
    
  if [ "${#dm_nodes[@]}" -eq 0 ]; then
    info "  No device-mapper nodes found for VG: $DISK_VG"
  else
    for dm in "${dm_nodes[@]}"; do
      printf "    - '%s'\n" "$dm"
    done

    for dm in "${dm_nodes[@]}"; do
      dmsetup remove "$dm"
    done
  fi

  echo
  info "Script completed successfully."
  info "Please detach the disk $USER_DISK from the Azure portal now."
  echo
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 0
fi

if [ -z "$USER_DISK" ]; then
  err "USER_DISK not found in state file; cannot proceed with method 2 safe flow."
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 8
fi

USER_DISK="$(normalize_user_disk "$USER_DISK")"


if [ ! -b "$USER_DISK" ]; then
  err "User disk $USER_DISK not found as block device on this system. Exiting."
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 9
fi


declare -A orig_pv_vg_map=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  key="$(echo "$line" | awk -F= '{print $1}')"
  val="$(echo "$line" | awk -F= '{print $2}')"
  pvbase="$(printf '%s' "$key" | sed 's/^ORIG_PV_VG_//')"
  orig_pv_vg_map["$pvbase"]="$val"
done <<EOF
$(read_orig_pv_vg_mapping)
EOF


if [ "${#orig_pv_vg_map[@]}" -eq 0 ]; then
  info "No ORIG_PV_VG_* entries found in state file. As a fallback, reading ORIGINAL_VG and IMPORTED_VG."
  ORIGINAL_VG="$(trim "$(read_original_vg)")"
  IMPORTED_VG="$(trim "$(read_imported_vg)")"
else
  ORIGINAL_VG="$(trim "$(read_original_vg)")"
  IMPORTED_VG="$(trim "$(read_imported_vg)")"
fi


mismatch_found=0

for pvbase in "${!orig_pv_vg_map[@]}"; do
  pvpath="/dev/${pvbase}"

  if [ ! -b "$pvpath" ]; then
    if [ -b "${USER_DISK}${pvbase#${pvbase%%[0-9]*}}" ]; then
      pvpath="${USER_DISK}${pvbase#${pvbase%%[0-9]*}}"
    else
      found=""
      for p in $(get_disk_partitions "$USER_DISK"); do
        if [ "$(basename "$p")" = "$pvbase" ]; then
          found="$p"
          break
        fi
      done
      if [ -n "$found" ]; then
        pvpath="$found"
      fi
    fi
  fi

  if [ ! -b "$pvpath" ]; then
    err "Expected PV '$pvpath' (from state ORIG_PV_VG_$pvbase) not present on disk $USER_DISK. Aborting."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 10
  fi
  
  curr_vg="$(pvs --noheadings -o vg_name "$pvpath" 2>/dev/null | awk '{$1=$1;print}' || true)"
  curr_vg="$(trim "$curr_vg")"
  expected_vg="$(trim "${orig_pv_vg_map[$pvbase]}")"

  if [ -z "$expected_vg" ]; then
    err "No expected VG name recorded for PV $pvpath. Aborting."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 11
  fi

  if [ -z "$curr_vg" ]; then
    err "Could not detect current VG on PV $pvpath (pvs returned empty). Aborting."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 12
  fi
  

    if [ "$curr_vg" = "$expected_vg" ]; then
      info ""
      info "[ PV → VG verification ]"
      info "  PV            : $pvpath"
      info "  Expected VG   : $expected_vg"
      info "  Current VG    : $curr_vg"
      info "  Result        : MATCH"
    else
      skip_vg_check="no"
      if [ -n "$OS_PRETTY" ] && printf '%s\n' "$OS_PRETTY" | grep -qi 'red hat'; then
        maj="${OS_VER_MAJ:-0}"
        min="${OS_VER_MIN:-0}"
        if [ "$maj" -gt 8 ] || { [ "$maj" -eq 8 ] && [ "$min" -gt 10 ]; }; then
          skip_vg_check="yes"
        fi
      fi

      if [ "$skip_vg_check" = "yes" ]; then
        info ""
        info "[ PV → VG verification ]"
        info "  PV            : $pvpath"
        info "  Expected VG   : $expected_vg"
        info "  Current VG    : $curr_vg"
        info "  Result        : MISMATCH"
        info "  Policy        : Allowed (RHEL > 8.10)"
        info "  Action        : Proceeding without live vgrename/dmsetup"
        mismatch_found=1
      else
        err "VG mismatch for PV $pvpath: expected '$expected_vg' but observed '$curr_vg'."
        err "Aborting to avoid data corruption."
        info "=== $prog finished at $(date -Iseconds) ==="
        exit 13
      fi
    fi
done


if [ "${mismatch_found:-0}" -eq 1 ]; then
:
else
  echo
  info "PV -> VG verification successful." 
  info "Current VG(s) on user disk match the recorded ORIGINAL VG(s)."
fi

echo
info "[ Disk mount consistency verification ]"
declare -A current_disk_mounts=()

for p in $(get_disk_partitions "$USER_DISK"); do
  tgt="$(findmnt -n -o TARGET --source "$p" 2>/dev/null || true)"

  if [ -n "$tgt" ]; then
    if [ "$tgt" != "/" ]; then tgt="${tgt%/}"; fi

    current_disk_mounts["$tgt"]=1
  fi
done


declare -A recorded_disk_mounts=()


while IFS= read -r t; do
  [ -z "$t" ] && continue


  if [ "$t" != "/" ]; then t="${t%/}"; fi
  recorded_disk_mounts["$t"]=1
done <<EOF
$(state_file_disk_mount_targets "$USER_DISK")
EOF

eq=1   # assume equal until proven otherwise

if [ "${#current_disk_mounts[@]}" -ne "${#recorded_disk_mounts[@]}" ]; then
  eq=0
else

  for k in "${!recorded_disk_mounts[@]}"; do
    if [ -z "${current_disk_mounts[$k]:-}" ]; then
      eq=0
      break
    fi
  done
fi

if [ "$eq" -ne 1 ]; then
  err "Disk mountpoint mismatch: mounts on $USER_DISK do not match the recorded mountpoints in state file."
  err "Recorded (statefile) disk targets:"
  for k in "${!recorded_disk_mounts[@]}"; do printf "  %s\n" "$k"; done
  err "Current (live) disk targets:"
  for k in "${!current_disk_mounts[@]}"; do printf "  %s\n" "$k"; done
  err "Aborting to avoid accidental detach while unexpected mounts exist."
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 14
fi


info "  Disk-mounted partition mountpoints match the state file for $USER_DISK."
echo

rhel9_method2_uuid_update_module() {
  

  [ "$MOUNT_METHOD" = "2" ] || return 0
  printf '%s\n' "$OS_PRETTY" | grep -qi 'red hat' || return 0
  [ "${OS_VER_MAJ:-0}" -eq 9 ] || return 0
  
  info "[ UUID normalization ]"
  
  local FSTAB_PATH="$MOUNTPOINT/etc/fstab"
  local LOADER_DIR="$MOUNTPOINT/boot/loader/entries"

  [ -f "$FSTAB_PATH" ] || return 0
  [ -d "$LOADER_DIR" ] || return 0

  declare -A MP_UUID=()

  while read -r tgt; do
    case "$tgt" in
      "$MOUNTPOINT" | "$MOUNTPOINT"/*)
        src="$(findmnt -n -o SOURCE --target "$tgt" 2>/dev/null || true)"
        [ -z "$src" ] && continue

        uuid="$(blkid -s UUID -o value "$src" 2>/dev/null || true)"
        [ -n "$uuid" ] && MP_UUID["$tgt"]="$uuid"
        ;;
    esac
  done < <(awk '$3=="MOUNT" {print $5}' "$STATE_FILE")
  

  [ "${#MP_UUID[@]}" -gt 0 ] || {
    err "No USER_DISK-backed mountpoints found under $MOUNTPOINT"
    exit 30
  }
  

  ROOT_UUID="${MP_UUID[$MOUNTPOINT]}"
  [ -n "$ROOT_UUID" ] || {
    err "Root filesystem UUID could not be determined"
    exit 31
  }


  need_fstab_update=0
  need_loader_update=0


  for mp in "${!MP_UUID[@]}"; do
    rel="${mp#$MOUNTPOINT}"
    [ -z "$rel" ] && rel="/"

    awk -v u="UUID=${MP_UUID[$mp]}" -v m="$rel" '
      $1==u && $2==m {found=1}
      END {exit !found}
    ' "$FSTAB_PATH" || need_fstab_update=1
  done


  grep -R -q "root=UUID=$ROOT_UUID" "$LOADER_DIR" || need_loader_update=1


  if [ "$need_fstab_update" -eq 0 ] && [ "$need_loader_update" -eq 0 ]; then
    info "  $FSTAB_PATH and $LOADER_DIR already contain correct UUIDs – skipping UUID updates"
    return 0
  fi
  

  TS_UUID="$(date +%Y%m%d-%H%M%S)"
  backups=()

  if [ "$need_fstab_update" -eq 1 ]; then
    cp -a "$FSTAB_PATH" "$FSTAB_PATH.bak.$TS_UUID"
    backups+=("$FSTAB_PATH.bak.$TS_UUID")
  fi

  if [ "$need_loader_update" -eq 1 ]; then
    for f in "$LOADER_DIR"/*.conf; do
      [ -f "$f" ] || continue
      cp -a "$f" "$f.bak.$TS_UUID"
      backups+=("$f.bak.$TS_UUID")
    done
  fi

  info "  Backup files created:"
  for b in "${backups[@]}"; do
    info "    - $b"
  done

  if [ "$need_fstab_update" -eq 1 ]; then
    info "  Updating $FSTAB_PATH"
    for mp in "${!MP_UUID[@]}"; do
      rel="${mp#$MOUNTPOINT}"
      [ -z "$rel" ] && rel="/"

      sed -i -E \
        "s#^[^[:space:]]+[[:space:]]+$rel[[:space:]]+#UUID=${MP_UUID[$mp]} $rel #g" \
        "$FSTAB_PATH"
    done
  else
    info "fstab already uses correct UUIDs – skipping fstab update"
  fi


  if [ "$need_loader_update" -eq 1 ]; then
    info "  Updating boot loader root=UUID"
    for conf in "$LOADER_DIR"/*.conf; do
      sed -i -E \
        "s#root=[^[:space:]]+#root=UUID=$ROOT_UUID#g" \
        "$conf"
    done
  else
    info "boot loader entries already use correct root UUID – skipping loader update"
  fi


  info ""
  info "  UUID update summary:"
  

  if [ "$need_fstab_update" -eq 1 ]; then
    echo
    echo "    $FSTAB_PATH:"
    
    awk '
      $1 ~ "^/dev/" {
        old[$2] = $1
      }
      $1 ~ "^UUID=" {
        new[$2] = $1
      }
      END {
        for (m in new) {
          if (m in old) {
            printf "    %-25s : %-30s → %s\n", m, old[m], new[m]
          } else {
            printf "    %-25s : %s (unchanged)\n", m, new[m]
          }
        }
      }
    ' "$FSTAB_PATH.bak.$TS_UUID" "$FSTAB_PATH"
  fi


  if [ "$need_loader_update" -eq 1 ]; then
    echo
    echo "  $LOADER_DIR/* :"
    
    old_root="$(grep -R 'options root=' "$LOADER_DIR"/*.bak."$TS_UUID" | head -1 | sed 's/.*root=\([^[:space:]]*\).*/\1/')"
    new_root="UUID=$ROOT_UUID"

    printf "    root= %-30s → root=%s\n" "$old_root" "$new_root"
    echo "    Note: "
    echo "        Applies to all kernel entries"
  fi

  echo ""
  
  

  while :; do
  printf "  Confirm that the above UUID updates are correct. Proceed? (yes/no): "
  read -r ans

  case "$ans" in
    y|Y|yes|YES|Yes)
      info "UUID update accepted by user"
      break
      ;;
    n|N|no|NO|No)
      err "UUID updates were not confirmed by the user."
      err "No changes have been committed. Please review and correct the UUID entries manually if required, then re-run this script."
      err "Restoring backups"
      for b in "${backups[@]}"; do
        orig="${b%.bak.$TS_UUID}"
        cp -a "$b" "$orig"
      done
      exit 33
      ;;
    *)
      err "Invalid input. Please enter yes or no."
      ;;
  esac
  done
}


rhel9_method2_uuid_update_module

echo
info "[ Umounting mount points ]"
info "  Will attempt to unmount the following mounted targets (children first):"


while IFS= read -r tt; do
printf "  %s\n" "$tt"
done <<EOF
$sorted_targets
EOF

read -r -p "Proceed to unmount the recorded targets (y/yes to proceed, q to quit)? " confirm
confirm="$(printf '%s' "$confirm" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if [ "$confirm" = "q" ] || [ "$confirm" = "Q" ]; then
  info "User requested quit. Exiting without changes."
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 0
fi
if [ "$confirm" != "y" ] && [ "$confirm" != "yes" ]; then
  info "User declined. Exiting without changes."
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 0
fi

preferred_suffixes=(
  "/proc"
  "/sys"
  "/dev/pts"
  "/dev"
  "/run"
  "/boot/efi"
  "/boot"
  "/var"
  "/usr"
  "/tmp"
  "/opt"
  "/home"
)


ordered_unmounts=()
declare -A mounted_map=()
for mt in "${mounted_targets[@]:-}"; do
  if [ -n "$mt" ] && [ "$mt" != "/" ]; then mt="${mt%/}"; fi
  mounted_map["$mt"]=1
done


for suf in "${preferred_suffixes[@]}"; do
  tgt="${MOUNTPOINT%/}${suf}"
  if [ "$suf" = "" ]; then tgt="${MOUNTPOINT%/}"; fi
  if [ "$tgt" != "/" ]; then tgt="${tgt%/}"; fi
  if [ -n "${mounted_map[$tgt]:-}" ]; then
    ordered_unmounts+=("$tgt")
  fi
done


if findmnt -n -o TARGET --target "$MOUNTPOINT" >/dev/null 2>&1; then
  already=0
  for x in "${ordered_unmounts[@]:-}"; do [ "$x" = "$MOUNTPOINT" ] && already=1 && break; done
  if [ $already -eq 0 ]; then
    ordered_unmounts+=("${MOUNTPOINT%/}")
  fi
fi


parent_unmounted=0
echo
info "[ Unmount execution ]"
info "→ First pass (children-first)"

declare -a failed_once=()

for tgt in "${ordered_unmounts[@]}"; do
  if [ "$tgt" != "/" ]; then tgt="${tgt%/}"; fi

  if findmnt -n -o TARGET --target "$tgt" >/dev/null 2>&1; then
    if try_unmount "$tgt"; then
      :
    else
      failed_once+=("$tgt")
    fi
    sleep 1
  else
    info "Skipping (not mounted): $tgt"
  fi
done


if [ "${#failed_once[@]}" -gt 0 ]; then
  info ""
  info "→ Retry after parent unmount"

  if [ "${parent_unmounted:-0}" -eq 1 ]; then
    info "  Parent $MOUNTPOINT was already unmounted; retrying failed targets."
  elif findmnt -n -o TARGET --target "$MOUNTPOINT" >/dev/null 2>&1; then
    info "Attempting to unmount parent mountpoint: $MOUNTPOINT"
  if umount -- "$MOUNTPOINT" >/dev/null 2>&1 || umount -fl -- "$MOUNTPOINT" >/dev/null 2>&1; then
    info "  Parent $MOUNTPOINT unmounted successfully; retrying failed targets."
  else
    info "  Parent $MOUNTPOINT unmount failed; will still retry failed targets."
  fi
  else
  info "  Parent $MOUNTPOINT is not mounted; retrying failed targets directly."
  fi

  declare -a still_failed=()
  for t in "${failed_once[@]}"; do
    if try_unmount "$t"; then
      :
    else
      still_failed+=("$t")
    fi
  done

  if [ "${#still_failed[@]}" -gt 0 ]; then
    err "The following targets remain mounted after retry: ${still_failed[*]}"
    for t in "${still_failed[@]}"; do
      err "Please manually unmount: $t"
    done
    read -r -p "After manual unmount(s), press ENTER to re-check or type 'q' to abort: " mancmd
    if [ "$mancmd" = "q" ] || [ "$mancmd" = "Q" ]; then
      err "User aborted. Exiting without further changes."
      info "=== $prog finished at $(date -Iseconds) ==="
      exit 15
    fi
    for t in "${still_failed[@]}"; do
      if findmnt -n -o TARGET --target "$t" >/dev/null 2>&1; then
        err "Still mounted: $t  -- aborting to avoid data corruption."
        info "=== $prog finished at $(date -Iseconds) ==="
        exit 16
      fi
    done
  fi
fi

if [[ "$OS_ID" == "ol" && "$OS_MAJOR" == "8" ]]; then
    for mp in $(lsblk -ln -o MOUNTPOINT "$USER_DISK" | grep -v '^$' | grep -v '^/$'); do
        try_unmount "$mp"
    done
fi

info "✓ All requested mounts unmounted successfully"


devbase="${USER_DISK#/dev/}"


disk_type="unknown"
case "$devbase" in
  sd[a-z]*)
    disk_type="scsi"
    ;;
  nvme*n*)
    disk_type="nvme"
    ;;
esac

echo
info "[ Detach the ${devbase} disk from the kernel ]"
info "  Detected type  : $disk_type"

if [ "$disk_type" = "scsi" ]; then

  sysdel="/sys/block/$devbase/device/delete"

  if [ ! -w "$sysdel" ]; then
    err "Delete path '$sysdel' is not writable or does not exist; cannot detach kernel device automatically."
    err "Please detach disk $USER_DISK manually in the Azure portal."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 17
  fi

  read -r -p "Are you sure you want to DELETE ${devbase} disk from kernel? (type YES in CAPITAL to proceed, q to quit): " delans2
  if [ "$delans2" = "q" ] || [ "$delans2" = "Q" ]; then
    info "Disk deletion aborted by user. Exiting without detaching disk."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 0
  fi
  if [ "$delans2" != "YES" ]; then
    info "User did not type YES. Aborting disk detach."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 0
  fi


  if ! echo 1 > "$sysdel" 2>/dev/null; then
    err "Failed to write to $sysdel; aborting. Please detach disk manually from Azure portal."
    info "=== $prog finished at $(date -Iseconds) ==="
    exit 18
  fi


  info "Disk successfully detached from kernel."

elif [ "$disk_type" = "nvme" ]; then

  echo
  err "⚠️  NVMe disk '$USER_DISK' cannot be detached from the guest OS."
  err "Azure exposes NVMe disks via a shared controller."
  err "Kernel-level detach would remove ALL NVMe disks."
  echo
  info "ACTION REQUIRED:"
  info "  → Detach disk $USER_DISK from the Azure portal."
  info "  → Then confirm here."

  while :; do
    echo
    read -r -p "Type YES after detaching the disk in Azure (q to quit): " azans


    if [ "$azans" = "q" ] || [ "$azans" = "Q" ]; then
      info "User chose to quit. Disk detach not confirmed."
      info "=== $prog finished at $(date -Iseconds) ==="
      exit 0
    fi


    if [ "$azans" != "YES" ]; then
      err "Invalid input."
      err "Please detach the disk from Azure and type YES, or q to quit."
      continue
    fi


    if [ -b "$USER_DISK" ]; then
      err "Disk $USER_DISK is STILL PRESENT in the kernel."
      err "Azure detach has NOT completed yet."
      info "Please detach the disk from the Azure portal and try again."
      continue
    fi


    devbase="${USER_DISK#/dev/}"
    if [ -e "/sys/block/$devbase" ]; then
      err "Disk $USER_DISK still exists under /sys/block."
      err "Detach is not complete yet."
      continue
    fi


    info "Confirmed: $USER_DISK is no longer present in the kernel."
    echo
    break
  done
fi


skip_vgrename="no"


if [ -n "$OS_PRETTY" ] && printf '%s\n' "$OS_PRETTY" | grep -qi 'red hat'; then
  maj="${OS_VER_MAJ:-0}"
  min="${OS_VER_MIN:-0}"


  if [ "$maj" -gt 8 ] || { [ "$maj" -eq 8 ] && [ "$min" -gt 10 ]; }; then
    skip_vgrename="yes"
  fi
fi

if [ "$skip_vgrename" = "yes" ]; then
  
  echo
  info "Note: This script will NOT attempt to run vgrename here."



  remove_vg_candidates=()
  if [ -n "${IMPORTED_VG:-}" ]; then
    remove_vg_candidates+=("$IMPORTED_VG")
  fi
  if [ -n "${OS_VG_NEW_NAME:-}" ]; then


    skipit=0
    for v in "${remove_vg_candidates[@]:-}"; do [ "$v" = "$OS_VG_NEW_NAME" ] && skipit=1 && break; done
    [ "$skipit" -eq 0 ] && remove_vg_candidates+=("$OS_VG_NEW_NAME")
  fi


  if [ "${#remove_vg_candidates[@]}" -eq 0 ] && [ -n "${curr_vg:-}" ]; then
    remove_vg_candidates+=("$curr_vg")
  fi


  if [ "${#remove_vg_candidates[@]}" -eq 0 ]; then
    info "No imported VG name available (IMPORTED_VG / OS_VG_NEW_NAME / curr_vg empty)."
    info "Skipping automated dmsetup removal. Manual cleanup may be required on the rescue VM or the original VM."
  else
    info""
    info "[ Device-mapper cleanup ]"
    info "  Removing device-mapper nodes for imported VG(s): ${remove_vg_candidates[*]}"

    dm_list="$(dmsetup ls 2>/dev/null || true)"

    for tgtvg in "${remove_vg_candidates[@]}"; do


      matches="$(printf '%s\n' "$dm_list" | grep -Ei "^${tgtvg}-" || true)"
      if [ -z "$matches" ]; then
        info "  No device-mapper nodes found for VG '$tgtvg' (none to remove)."
        continue
      fi

      while IFS= read -r dmline; do
        [ -z "$dmline" ] && continue
        dmname="$(printf '%s' "$dmline" | awk '{print $1}')"
        info "    - '$dmname'"
        if ! dmsetup remove "$dmname" >/dev/null 2>&1; then
          err "  Failed to remove '$dmname'. Continuing."
        fi
      done <<EOF
$matches
EOF
done


    remaining="$(dmsetup ls 2>/dev/null | grep -Ei "$(printf '%s' "${remove_vg_candidates[*]}" | sed 's/ /|/g')" || true)"
    if [ -n "$remaining" ]; then
      info "Some device-mapper nodes for the imported/current VG(s) remain after attempted removal:"
      printf '%s\n' "$remaining"
      info "If these nodes should be removed, consider removing them manually or rebooting the rescue VM to clear stale mappings."
    else
      info ""
      info "  Device-mapper cleanup completed."
    fi
  fi


  info ""
  info "===================================================================="
  info "⚠️  IMPORTANT – MANUAL STEPS REQUIRED (READ CAREFULLY) !!!"
  info "===================================================================="
  info ""
  info "EXPECTED NEXT STEPS (manual action on the original VM after swapping disks):"
  info ""
  info "  1) Swap the disks:"
  info "     - Swap ${USER_DISK} back to the VM's OS disk slot"
  info ""
  info "  2) Boot the VM and log in"
  info ""
  info "  3) Verify the VG name on the restored disk"
  info "     (example observed: '${IMPORTED_VG:-${curr_vg:-<unknown>}}')."
  info ""
  info "  4) If you want the original VG name back, run (as root):"
  info ""
  info "       vgrename <current-vg-name-on-disk> <original-vg-name>"
  info ""
  info "     Example:"
  info "       vgrename rescuemevg rootvg"
  info ""
  info "  NOTE:"
  info "    • Temporary loss of connectivity is EXPECTED after running vgrename"
  info "    • Simply reboot to the server to restore access with rootvg"
  info ""
  info "--------------------------------------------------------------------"
  info "This approach avoids live device-mapper remapping during the rescue VM"
  info "session while safely cleaning up stale device-mapper nodes."
  info "--------------------------------------------------------------------"
  info ""
  info "Disk detached and LVM cleanup completed (vgrename intentionally skipped)."
  info "ACTION REQUIRED: Detach disk ${USER_DISK} from the Azure portal."
  info "===================================================================="
  info""
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 0
fi


info "[ Device-mapper cleanup ]"
info "  Removing stale device-mapper entries for VG name '$OS_VG_ORIG_NAME'..."


curr_before_rm=$(dmsetup ls 2>/dev/null | grep -i "$OS_VG_ORIG_NAME" || true)
if [ -z "$curr_before_rm" ]; then
  info "No device-mapper entries found for '$OS_VG_ORIG_NAME' (nothing to remove)."
else


while IFS= read -r dmline; do
    [ -z "$dmline" ] && continue
    dmname=$(printf '%s\n' "$dmline" | awk '{print $1}')
    case "$dmname" in
      "$OS_VG_ORIG_NAME"-*)
        info "-> dmsetup remove '$dmname'"
        if ! dmsetup remove "$dmname" >/dev/null 2>&1; then
          err "Failed to remove device-mapper node '$dmname'. Aborting."
          info "=== $prog finished at $(date -Iseconds) ==="
          exit 19
        fi
        ;;
      *)  # Ignore unrelated dm nodes
        :
        ;;
    esac
done <<EOF
$curr_before_rm
EOF
fi

remaining=$(dmsetup ls 2>/dev/null | grep -i "$OS_VG_ORIG_NAME" || true)
if [ -n "$remaining" ]; then
  err "Some device-mapper entries for '$OS_VG_ORIG_NAME' remain after attempted removal:"
  printf '%s\n' "$remaining" >&2
  err "Aborting to avoid inconsistent LVM state."
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 20
fi


if [ -z "$OS_VG_NEW_NAME" ] || [ -z "$OS_VG_ORIG_NAME" ]; then
  err "Missing OS VG original/new names in state file; cannot perform vgrename safely."
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 21
fi


info ""
info "[ VG rename ]"
info "  Renaming rescue OS VG from '$OS_VG_NEW_NAME' back to '$OS_VG_ORIG_NAME'..."
if ! vgrename "$OS_VG_NEW_NAME" "$OS_VG_ORIG_NAME"; then
  err "vgrename $OS_VG_NEW_NAME $OS_VG_ORIG_NAME failed; please resolve LVM configuration manually."
  info "=== $prog finished at $(date -Iseconds) ==="
  exit 22
fi


info "  VG rename successful."
echo
info "Disk detached and LVM cleanup completed successfully."
info "Please detach the disk $USER_DISK from the Azure portal now."
info "=== $prog finished at $(date -Iseconds) ==="
exit 0

}


main() {

while true; do
  printf "Which action do you want to perform? [mount/umount] (q to quit): "
  read -r action || { echo; err "Input error"; exit 1; }
  action="$(printf '%s' "$action" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  case "$action" in
    mount)
      echo
      echo "Invoking mount helper"
      echo
      echo "NOTE: The mount helper will generate a state file (e.g. /var/log/mount-helper-<timestamp>.state)."
      echo "      That state file should later be provided as the argument to the unmount helper."
      echo
      # run the mount helper (interactive)
      mount_helper 
      break
      ;; # exec replaces this process; if you prefer to return, remove exec
    umount|unmount)
      echo
      # --- Try last known state file first ---
      if [ -f "$LAST_STATE" ]; then
        statepath="$(cat "$LAST_STATE")"
        if [ -n "$statepath" ] && [ -f "$statepath" ]; then
          echo "Using last known state file:"
          echo "  $statepath"
          echo
          echo "Invoking unmount helper"
          echo
          umount_helper "$statepath"
          break
        else
          echo "$LAST_STATE is empty."
          echo
        fi
      else
        echo "$LAST_STATE is missing."
        echo
      fi

      # --- Fallback to manual prompt ---
      
      # prompt for state file path
      while true; do
        printf "Enter path to state file (created by mount-helper) [q to cancel]: "
        read -r statepath || { echo; err "Input error"; exit 1; }
        if [ -z "$statepath" ]; then
          echo "Please enter a valid path."
          continue
        fi
        if [ "$statepath" = "q" ] || [ "$statepath" = "Q" ]; then
          echo "Cancelled by user."
          exit 0
        fi
        if [ ! -f "$statepath" ]; then
          echo "State file not found: $statepath"
          read -r -p "Retry? (y to retry, any other key to abort): " retry || { echo; err "Input error"; exit 1; }
          retry="$(printf '%s' "$retry" | tr '[:upper:]' '[:lower:]')"
          if [ "$retry" = "y" ] || [ "$retry" = "yes" ]; then
            continue
          else
            echo "Aborting."
            exit 1
          fi
        fi
        # found file, call umount helper with argument
        echo
        echo "Invoking unmount helper"
        echo
        umount_helper "$statepath"
        break
      done
      ;;
    q|quit|exit)
      echo "Goodbye."
      exit 0
      ;;
    *)
      echo "Invalid choice. Please enter 'mount' or 'umount' (or q to quit)."
      ;;
  esac
done

}

main "$@"
