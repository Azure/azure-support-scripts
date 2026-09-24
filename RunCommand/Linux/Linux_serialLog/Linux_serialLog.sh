#!/usr/bin/bash
# -----------------------------------------------------------------------------
# File: Linux_serialLog.sh
# This script is designed to modify the 'printk' setting in a running Linux VM
# to increase or decrease the verbosity of the kernel logging printing to the
# serial console.
#
# The default will be to raise the log to level 7 (debug) in a non-persistent
# manner to capture as much information as possible. Options are available to
# specify the log level, as well as to make the changes permanent.
# -----------------------------------------------------------------------------
# Version: 1.1.0
# Released: 2026-09-10
# Latest update: 2026-09-10
# Author: Azure Support
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the terms found in the LICENSE file in the root of this source tree.
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# define this once for the script run - so that all backups have the same exact
# timestamp
TIMESTAMP=`date +%Y%m%dT%H%M%S`
# set an internal reference name - we can't use $0 because RunCommand creates 
# its payload script using the generic name 'script.sh'
SCRIPTNAME="Linux_serialLog.sh"

# -----------------------------------------------------------------------------
# printk / console reporting (runtime, phase 1)
# -----------------------------------------------------------------------------

# reads /proc/sys/kernel/printk into CUR_LEVEL/DEFAULT_LEVEL/MIN_LEVEL/BOOT_DEFAULT_LEVEL
function get_printk_levels() {
  if [[ ! -r /proc/sys/kernel/printk ]]; then
    echo "ERR: Unable to read /proc/sys/kernel/printk"
    return 1
  fi
  read -r CUR_LEVEL DEFAULT_LEVEL MIN_LEVEL BOOT_DEFAULT_LEVEL < /proc/sys/kernel/printk
}

# maps a numeric kernel log level (0-7) to its syslog priority name
function loglevel_name() {
  local level="$1"
  case "$level" in
    0) echo "emerg" ;;
    1) echo "alert" ;;
    2) echo "crit" ;;
    3) echo "err" ;;
    4) echo "warn" ;;
    5) echo "notice" ;;
    6) echo "info" ;;
    7) echo "debug" ;;
    *) echo "unknown" ;;
  esac
}

function report_printk_levels() {
  get_printk_levels || return 1
  echo "PRINTK: current=$CUR_LEVEL($(loglevel_name "$CUR_LEVEL")) default=$DEFAULT_LEVEL($(loglevel_name "$DEFAULT_LEVEL")) minimum=$MIN_LEVEL($(loglevel_name "$MIN_LEVEL")) boot_default=$BOOT_DEFAULT_LEVEL($(loglevel_name "$BOOT_DEFAULT_LEVEL"))"
}

# reports every registered kernel console output channel and how it is wired up
# one tagged line per data point - keeps az cli's escaped/flattened JSON output greppable
function report_console_channels() {
  if [[ -r /proc/consoles ]]; then
    while IFS= read -r line; do
      echo "CONSOLE: $line"
    done < /proc/consoles
    echo "CONSOLE_LEGEND: R=accepts kernel input W=receives kernel output U=unblanked (E)=enabled (B)=boot console (p)=preferred console (b)=braille device"
  else
    echo "WARN: /proc/consoles not readable"
  fi

  if [[ -r /sys/class/tty/console/active ]]; then
    echo "CONSOLE_ACTIVE: $(cat /sys/class/tty/console/active)"
  else
    echo "WARN: /sys/class/tty/console/active not readable"
  fi

  if [[ -r /proc/cmdline ]]; then
    local cmdline_consoles
    cmdline_consoles="$(grep -o 'console=[^ ]*' /proc/cmdline | tr '\n' ' ')"
    echo "CONSOLE_CMDLINE: ${cmdline_consoles:-none}"
  else
    echo "WARN: /proc/cmdline not readable"
  fi
}

function report_current_state() {
  echo "REPORT: printk/console state @ ${TIMESTAMP}"
  report_printk_levels
  report_console_channels
}

# -----------------------------------------------------------------------------
# printk level change (runtime, phase 2 - non-persistent)
# -----------------------------------------------------------------------------

# writing a single value to /proc/sys/kernel/printk only updates the leading
# (current) field, leaving default/minimum/boot-default untouched - this
# works on every distro and kernel version with procfs, no dependency on
# dmesg/sysctl being installed, making it the most portable option
function set_printk_level_runtime() {
  local level="$1"

  if [[ ! "$level" =~ ^[0-7]$ ]]; then
    echo "ERR: requested level '$level' is invalid - must be 0-7"
    return 1
  fi

  if [[ ! -w /proc/sys/kernel/printk ]]; then
    echo "ERR: /proc/sys/kernel/printk is not writable (must run as root)"
    return 1
  fi

  echo "$level" > /proc/sys/kernel/printk
  echo "SET: runtime (non-persistent) current printk level requested = $level"
}

# -----------------------------------------------------------------------------
# printk level change (persistent, phase 3 - survives reboot)
# -----------------------------------------------------------------------------

# drop-in read by systemd-sysctl.service on every systemd-based distro (RHEL,
# SLES, Ubuntu/Debian, etc.) - no distro-family branching needed for this part
SYSCTL_DROPIN="/etc/sysctl.d/01-linux-seriallog-printk.conf"

function set_printk_level_persistent() {
  local level="$1"

  if [[ ! "$level" =~ ^[0-7]$ ]]; then
    echo "ERR: requested level '$level' is invalid - must be 0-7"
    return 1
  fi

  if [[ ! -d /etc/sysctl.d ]]; then
    echo "ERR: /etc/sysctl.d does not exist - cannot persist via systemd-sysctl"
    return 1
  fi

  if [[ -e "$SYSCTL_DROPIN" ]]; then
    cp -p "$SYSCTL_DROPIN" "${SYSCTL_DROPIN}.bak.${TIMESTAMP}"
    echo "INFO: backed up existing $SYSCTL_DROPIN to ${SYSCTL_DROPIN}.bak.${TIMESTAMP}"
  fi

  cat > "$SYSCTL_DROPIN" <<EOF
# Created by Linux_serialLog.sh (${TIMESTAMP})
# Sets the printk console log level applied at boot by systemd-sysctl.service
kernel.printk = ${level}
EOF

  echo "SET: persistent printk level written to $SYSCTL_DROPIN (applied on next boot by systemd-sysctl.service)"

  if command -v sysctl >/dev/null 2>&1; then
    if sysctl -p "$SYSCTL_DROPIN" >/dev/null 2>&1; then
      echo "SET: sysctl -p also applied $SYSCTL_DROPIN immediately"
    else
      echo "WARN: sysctl -p failed to apply $SYSCTL_DROPIN immediately - it will still take effect on next boot"
    fi
  else
    echo "WARN: sysctl command not found - drop-in will only take effect on next boot via systemd-sysctl.service"
  fi
}

# -----------------------------------------------------------------------------
# OS family detection (phase 4 prerequisite - RedHat-like distros persist a
# printk-related kernel cmdline boot parameter via GRUB; SLES and
# Debian-based distros do not, so no branching is needed for those families)
# - we won't invent the loglevel kernel cmdline boot parameter for distributions 
#   that don't already use it normally
# -----------------------------------------------------------------------------

# reads /etc/os-release into OS_ID/OS_ID_LIKE and sets IS_REDHAT_FAMILY (0/1)
function detect_os_family() {
  OS_ID=""
  OS_ID_LIKE=""
  IS_REDHAT_FAMILY=0

  if [[ ! -r /etc/os-release ]]; then
    echo "WARN: /etc/os-release not readable - unable to determine OS family"
    return 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID="${ID:-}"
  OS_ID_LIKE="${ID_LIKE:-}"

  # ID_LIKE can hold multiple space-separated values (e.g. "rhel fedora")
  if [[ "$OS_ID" =~ ^(rhel|centos|fedora|rocky|almalinux|ol)$ ]] || [[ " $OS_ID_LIKE " =~ (rhel|fedora) ]]; then
    IS_REDHAT_FAMILY=1
  fi

  echo "OS_FAMILY: id=${OS_ID:-unknown} id_like=${OS_ID_LIKE:-none} redhat_family=$([[ $IS_REDHAT_FAMILY -eq 1 ]] && echo yes || echo no)"
}

# -----------------------------------------------------------------------------
# GRUB boot parameter update (phase 4b/4c - RedHat-family only)
# grubby is Red Hat's documented tool for adding/removing kernel command-line
# parameters (`grubby --update-kernel=ALL --args=...` / `--remove-args=...`),
# and it transparently handles both legacy grub2 menuentry-based configs
# (RHEL7-style) and BLS (/boot/loader/entries, RHEL8+) systems - so there is
# no need to separately hand-edit /etc/default/grub and regenerate grub.cfg
# via grub2-mkconfig; grubby edits the real, in-effect boot entries for every
# currently installed kernel directly.
# -----------------------------------------------------------------------------

# inspects the default boot entry's kernel args for an existing loglevel= via
# grubby - sets BOOT_LOGLEVEL_CUR; reports and returns 1 when nothing is set,
# so a missing loglevel= is never introduced (matches the persistent sysctl
# drop-in's "don't invent a parameter" contract)
function get_boot_loglevel() {
  BOOT_LOGLEVEL_CUR=""

  local info
  info="$(grubby --info=DEFAULT 2>/dev/null)"
  if [[ -z "$info" ]]; then
    echo "WARN: grubby --info=DEFAULT returned no output - unable to inspect current boot args"
    return 1
  fi

  if [[ "$info" =~ loglevel=([0-9]+) ]]; then
    BOOT_LOGLEVEL_CUR="${BASH_REMATCH[1]}"
    echo "INFO: existing boot loglevel found = ${BOOT_LOGLEVEL_CUR}"
    return 0
  fi

  echo "INFO: no explicit loglevel= boot parameter set - kernel uses its compiled-in default at boot"
  return 1
}

# updates loglevel= across every installed kernel's boot entry via grubby -
# only called once get_boot_loglevel has confirmed one is already set, so a
# missing loglevel= is never introduced
function set_boot_loglevel() {
  local level="$1"

  if [[ -d /boot/loader/entries ]]; then
    local entry
    for entry in /boot/loader/entries/*.conf; do
      [[ -e "$entry" ]] || continue
      cp -p "$entry" "${entry}.bak.${TIMESTAMP}"
    done
    echo "INFO: backed up existing BLS entries under /boot/loader/entries to *.bak.${TIMESTAMP}"
  fi

  if grubby --update-kernel=ALL --remove-args="loglevel" --args="loglevel=${level}"; then
    echo "SET: updated loglevel=${level} across all installed kernels via grubby"
  else
    echo "ERR: grubby failed to update loglevel across boot entries"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# printk level change (persistent boot parameter, phase 4 - RedHat-like only)
# -----------------------------------------------------------------------------

# RHEL and derived distributions persist a printk-related boot parameter via
# GRUB that no other distributions set today.  We could make this work for all
# distros but that could be more expansive.  If others start making loglevel= 
# directives we will build it.  Updates an existing loglevel= via grubby only
# - a missing one is never introduced.
function reset_boot_printk_param() {
  local level="$1"

  detect_os_family

  if [[ "$IS_REDHAT_FAMILY" -ne 1 ]]; then
    echo "INFO: boot parameter reset not required for this OS family (id=${OS_ID:-unknown}) - skipping"
    return 0
  fi

  if ! command -v grubby >/dev/null 2>&1; then
    echo "ERR: grubby not found - cannot inspect/update boot loader kernel parameters"
    return 1
  fi

  # only update an existing loglevel= - never introduce one that wasn't already there
  if ! get_boot_loglevel; then
    echo "INFO: no existing loglevel= boot parameter to update - leaving boot configuration untouched"
    return 0
  fi

  set_boot_loglevel "$level"
}

# -----------------------------------------------------------------------------
# main
#   $1 = desired printk level (0-7), optional - defaults to 7 (debug) when omitted
#   $2 = persist flag - defaults to runtime-only (not persisted) when omitted
# -----------------------------------------------------------------------------
REQUESTED_LEVEL="${1:-7}"
PERSIST_FLAG="${2:-}"

report_current_state

case "${PERSIST_FLAG,,}" in
  # do not include '1' in the list of accepted values - to avoid confusion with the numeric log level 1 (alert)
  persist|true|yes) DO_PERSIST=1 ;;
  *) DO_PERSIST=0 ;;
esac

echo "REQUEST: change printk level to $REQUESTED_LEVEL (persist=$([[ $DO_PERSIST -eq 1 ]] && echo yes || echo no))"

if set_printk_level_runtime "$REQUESTED_LEVEL"; then
  if [[ "$DO_PERSIST" -eq 1 ]]; then
    set_printk_level_persistent "$REQUESTED_LEVEL"
    reset_boot_printk_param "$REQUESTED_LEVEL"
  fi
  report_current_state
fi
