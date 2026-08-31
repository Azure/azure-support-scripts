#!/bin/bash
# =============================================================================
# Secure Boot Certificate Update Status Check — Linux
#
# Collects and reports the Secure Boot certificate update status on a Linux VM.
# Reads EFI variables, shim/GRUB package versions, and boot logs to produce
# a summary report. Designed to run via Azure Run Command or directly from
# an elevated shell session.
#
# The script is READ-ONLY — it makes no changes to the device.
#
# Reference: https://aka.ms/securebootplaybook
#
# CHANGELOG:
#   v1.0 - 2026-06-05
#     - Initial version
#     - Checks Secure Boot state via mokutil and EFI vars
#     - Enumerates DB/KEK certificates for 2023 CA presence
#     - Reports shim and GRUB package versions per distro
#     - Checks dmesg for Secure Boot messages
#     - Color-coded summary with PASS/ACTION NEEDED
#
# LICENSE: MIT (see https://github.com/Azure/azure-support-scripts/blob/master/LICENSE.txt)
# =============================================================================

set -euo pipefail

# --- Colors (safe for Run Command — ANSI codes) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# =============================================================================
# Banner
# =============================================================================
echo ""
echo -e "${CYAN}===============================================================================${NC}"
echo -e "${CYAN}  Secure Boot Certificate Update Status Check — Linux${NC}"
echo -e "${GRAY}  Reference: https://aka.ms/securebootplaybook${NC}"
echo -e "${CYAN}===============================================================================${NC}"
echo ""

# =============================================================================
# Helper Functions
# =============================================================================
print_section() {
    echo -e "${WHITE}--- $1 ---${NC}"
}

print_pass() {
    echo -e "  ${GREEN}$1${NC}"
}

print_warn() {
    echo -e "  ${YELLOW}$1${NC}"
}

print_fail() {
    echo -e "  ${RED}$1${NC}"
}

print_info() {
    echo -e "  ${CYAN}$1${NC}"
}

print_value() {
    echo -e "  $1: ${GREEN}$2${NC}"
}

# =============================================================================
# Device Information
# =============================================================================
print_section "Device Information"
print_value "Hostname" "$(hostname)"
print_value "Collection Time" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
print_value "Kernel" "$(uname -r)"

# Detect distro
DISTRO="unknown"
DISTRO_VERSION="unknown"
if [ -f /etc/os-release ]; then
    DISTRO=$(. /etc/os-release && echo "${ID:-unknown}")
    DISTRO_VERSION=$(. /etc/os-release && echo "${VERSION_ID:-unknown}")
    DISTRO_NAME=$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")
    print_value "Distribution" "$DISTRO_NAME"
else
    print_warn "Cannot detect distribution (/etc/os-release not found)"
fi
echo ""

# =============================================================================
# Secure Boot Status
# =============================================================================
print_section "Secure Boot Status"

SB_ENABLED="unknown"
FINDINGS=()
NEXT_STEPS=()

# Check via mokutil
if command -v mokutil &>/dev/null; then
    SB_STATE=$(mokutil --sb-state 2>/dev/null || echo "unavailable")
    if echo "$SB_STATE" | grep -qi "SecureBoot enabled"; then
        SB_ENABLED="true"
        print_pass "Secure Boot: Enabled"
    elif echo "$SB_STATE" | grep -qi "SecureBoot disabled"; then
        SB_ENABLED="false"
        print_info "Secure Boot: Disabled"
        FINDINGS+=("Secure Boot is disabled — certificate updates do not apply.")
    else
        print_warn "Secure Boot: $SB_STATE"
    fi
else
    # Fallback: check EFI variable directly
    if [ -d /sys/firmware/efi/efivars ]; then
        SB_VAR=$(find /sys/firmware/efi/efivars/ -name "SecureBoot-*" 2>/dev/null | head -1)
        if [ -n "$SB_VAR" ]; then
            SB_BYTE=$(xxd -p -l1 -s4 "$SB_VAR" 2>/dev/null || echo "??")
            if [ "$SB_BYTE" = "01" ]; then
                SB_ENABLED="true"
                print_pass "Secure Boot: Enabled (via EFI var)"
            else
                SB_ENABLED="false"
                print_info "Secure Boot: Disabled (via EFI var)"
            fi
        else
            print_warn "Secure Boot EFI variable not found"
        fi
    else
        print_warn "EFI not available (not a UEFI system or efivarfs not mounted)"
        SB_ENABLED="false"
        FINDINGS+=("EFI firmware not detected — this may not be a Gen2/Trusted Launch VM.")
    fi
fi
echo ""

# =============================================================================
# Certificate Inventory (DB and KEK)
# =============================================================================
print_section "Certificate Inventory"

HAS_2023_DB="false"
HAS_2023_KEK="false"
CERT_COUNT_DB=0
CERT_COUNT_KEK=0

if command -v mokutil &>/dev/null; then
    # Check DB certificates
    DB_OUTPUT=$(mokutil --db 2>/dev/null || echo "")
    if [ -n "$DB_OUTPUT" ]; then
        CERT_COUNT_DB=$(echo "$DB_OUTPUT" | grep -c "Certificate:" 2>/dev/null || echo 0)
        print_value "DB Certificates" "$CERT_COUNT_DB found"

        if echo "$DB_OUTPUT" | grep -qi "2023"; then
            HAS_2023_DB="true"
            print_pass "  -> Microsoft UEFI CA 2023: Found in DB"
        else
            print_warn "  -> Microsoft UEFI CA 2023: NOT found in DB"
            FINDINGS+=("Microsoft UEFI CA 2023 certificate not found in Secure Boot DB.")
            NEXT_STEPS+=("Restart or redeploy the VM to trigger firmware certificate update.")
        fi

        if echo "$DB_OUTPUT" | grep -qi "2011"; then
            print_info "  -> Microsoft UEFI CA 2011: Present in DB (expiring June 2026)"
        fi
    else
        print_warn "Could not read DB certificates"
    fi

    # Check KEK certificates
    KEK_OUTPUT=$(mokutil --kek 2>/dev/null || echo "")
    if [ -n "$KEK_OUTPUT" ]; then
        CERT_COUNT_KEK=$(echo "$KEK_OUTPUT" | grep -c "Certificate:" 2>/dev/null || echo 0)
        print_value "KEK Certificates" "$CERT_COUNT_KEK found"

        if echo "$KEK_OUTPUT" | grep -qi "2023"; then
            HAS_2023_KEK="true"
            print_pass "  -> Microsoft KEK 2K CA 2023: Found in KEK"
        else
            print_warn "  -> Microsoft KEK 2K CA 2023: NOT found in KEK"
            FINDINGS+=("Microsoft KEK 2K CA 2023 certificate not found in KEK.")
        fi
    else
        print_warn "Could not read KEK certificates"
    fi
else
    print_warn "mokutil not installed — cannot enumerate certificates"
    print_info "Install: apt install mokutil (Ubuntu/Debian) or dnf install mokutil (RHEL/Fedora)"
    NEXT_STEPS+=("Install mokutil to check Secure Boot certificate status.")
fi
echo ""

# =============================================================================
# Shim and GRUB Package Versions
# =============================================================================
print_section "Bootloader Packages"

SHIM_VERSION="not found"
GRUB_VERSION="not found"

case "$DISTRO" in
    ubuntu|debian)
        SHIM_PKG=$(dpkg -l 2>/dev/null | grep -E "shim-signed|shim-efi" | head -1 | awk '{print $2 " " $3}')
        GRUB_PKG=$(dpkg -l 2>/dev/null | grep "grub-efi-amd64-signed" | head -1 | awk '{print $2 " " $3}')
        if [ -n "$SHIM_PKG" ]; then
            SHIM_VERSION="$SHIM_PKG"
            print_value "Shim" "$SHIM_VERSION"
        else
            print_warn "shim-signed package not found"
        fi
        if [ -n "$GRUB_PKG" ]; then
            GRUB_VERSION="$GRUB_PKG"
            print_value "GRUB" "$GRUB_VERSION"
        else
            print_warn "grub-efi-amd64-signed package not found"
        fi
        ;;
    rhel|centos|almalinux|rocky|ol|fedora)
        SHIM_PKG=$(rpm -q shim-x64 2>/dev/null || echo "not installed")
        GRUB_PKG=$(rpm -q grub2-efi-x64 2>/dev/null || echo "not installed")
        SHIM_VERSION="$SHIM_PKG"
        GRUB_VERSION="$GRUB_PKG"
        print_value "Shim" "$SHIM_VERSION"
        print_value "GRUB" "$GRUB_VERSION"
        ;;
    sles|opensuse*)
        SHIM_PKG=$(rpm -q shim 2>/dev/null || echo "not installed")
        GRUB_PKG=$(rpm -q grub2-x86_64-efi 2>/dev/null || echo "not installed")
        SHIM_VERSION="$SHIM_PKG"
        GRUB_VERSION="$GRUB_PKG"
        print_value "Shim" "$SHIM_VERSION"
        print_value "GRUB" "$GRUB_VERSION"
        ;;
    mariner|azurelinux)
        SHIM_PKG=$(rpm -q shim-unsigned-x64 2>/dev/null || rpm -q shim 2>/dev/null || echo "not installed")
        GRUB_PKG=$(rpm -q grub2-efi 2>/dev/null || echo "not installed")
        SHIM_VERSION="$SHIM_PKG"
        GRUB_VERSION="$GRUB_PKG"
        print_value "Shim" "$SHIM_VERSION"
        print_value "GRUB" "$GRUB_VERSION"
        ;;
    *)
        print_warn "Unknown distribution '$DISTRO' — check shim/GRUB packages manually"
        ;;
esac
echo ""

# =============================================================================
# Boot Log Analysis
# =============================================================================
print_section "Boot Log Analysis"

SB_DMESG=$(dmesg 2>/dev/null | grep -iE "secureboot|secure boot|uefi" | tail -5)
if [ -n "$SB_DMESG" ]; then
    echo "$SB_DMESG" | while IFS= read -r line; do
        if echo "$line" | grep -qi "error\|fail\|denied\|violation"; then
            print_fail "$line"
            FINDINGS+=("Secure Boot error detected in dmesg.")
        elif echo "$line" | grep -qi "enabled\|success"; then
            print_pass "$line"
        else
            print_info "$line"
        fi
    done
else
    print_info "No Secure Boot messages found in dmesg (may require root)"
fi

# Check journal for boot attestation
if command -v journalctl &>/dev/null; then
    ATTEST_MSGS=$(journalctl -b --no-pager 2>/dev/null | grep -i "secure boot\|attestation" | tail -3)
    if [ -n "$ATTEST_MSGS" ]; then
        echo ""
        print_info "Journal boot messages:"
        echo "$ATTEST_MSGS" | while IFS= read -r line; do
            print_info "  $line"
        done
    fi
fi
echo ""

# =============================================================================
# VM Metadata (Azure IMDS)
# =============================================================================
print_section "Azure VM Information"

IMDS_RESPONSE=$(curl -s -H "Metadata:true" --noproxy "*" \
    "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null || echo "")

if [ -n "$IMDS_RESPONSE" ] && command -v python3 &>/dev/null; then
    VM_NAME=$(echo "$IMDS_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('compute',{}).get('name','N/A'))" 2>/dev/null || echo "N/A")
    VM_SIZE=$(echo "$IMDS_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('compute',{}).get('vmSize','N/A'))" 2>/dev/null || echo "N/A")
    VM_OFFER=$(echo "$IMDS_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); sr=d.get('compute',{}).get('storageProfile',{}).get('imageReference',{}); print(f\"{sr.get('publisher','?')}:{sr.get('offer','?')}:{sr.get('sku','?')}\")" 2>/dev/null || echo "N/A")
    SEC_TYPE=$(echo "$IMDS_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('compute',{}).get('securityProfile',{}).get('securityType','Standard'))" 2>/dev/null || echo "N/A")

    print_value "VM Name" "$VM_NAME"
    print_value "VM Size" "$VM_SIZE"
    print_value "Image" "$VM_OFFER"
    print_value "Security Type" "$SEC_TYPE"

    if [ "$SEC_TYPE" != "TrustedLaunch" ] && [ "$SEC_TYPE" != "ConfidentialVM" ]; then
        print_info "This VM is not Trusted Launch — Secure Boot cert updates may not apply."
        FINDINGS+=("VM security type is '$SEC_TYPE', not TrustedLaunch.")
    fi
elif [ -n "$IMDS_RESPONSE" ]; then
    print_info "IMDS reachable but python3 not available for parsing"
else
    print_warn "Cannot reach IMDS (169.254.169.254) — may not be an Azure VM"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
echo -e "${CYAN}===============================================================================${NC}"
echo -e "${CYAN}  Summary${NC}"
echo -e "${CYAN}===============================================================================${NC}"

if [ "$SB_ENABLED" = "false" ]; then
    echo -e "  STATUS: ${CYAN}NOT APPLICABLE${NC}"
    echo ""
    echo -e "  Secure Boot is disabled. Certificate updates do not apply."
    echo -e "  No action needed unless Secure Boot is re-enabled."
elif [ "$HAS_2023_DB" = "true" ] && [ "$HAS_2023_KEK" = "true" ]; then
    echo -e "  STATUS: ${GREEN}✅ PASS${NC}"
    echo ""
    echo -e "  ${GREEN}Microsoft UEFI CA 2023 certificates are present in firmware.${NC}"
    echo -e "  ${GREEN}Ensure shim package is up to date from your distro repos.${NC}"
else
    echo -e "  STATUS: ${YELLOW}⚠️  ACTION NEEDED${NC}"
    echo ""
    echo -e "  ${YELLOW}FINDINGS:${NC}"
    for finding in "${FINDINGS[@]:-}"; do
        [ -n "$finding" ] && echo -e "  ${YELLOW}* $finding${NC}"
    done
    echo ""
    echo -e "  ${WHITE}NEXT STEPS:${NC}"
    echo -e "  ${WHITE}-----------${NC}"
    STEP=1

    if [ "$HAS_2023_DB" = "false" ] || [ "$HAS_2023_KEK" = "false" ]; then
        echo -e "  ${STEP}. Restart the VM to allow Azure platform to update firmware certificates."
        echo -e "     If this persists, redeploy the VM: az vm redeploy -g <rg> -n <vm>"
        STEP=$((STEP + 1))
    fi

    echo -e "  ${STEP}. Update shim and GRUB packages from your distro repos:"
    case "$DISTRO" in
        ubuntu|debian)
            echo -e "     sudo apt update && sudo apt install --only-upgrade shim-signed grub-efi-amd64-signed"
            ;;
        rhel|centos|almalinux|rocky|ol|fedora)
            echo -e "     sudo dnf update shim-x64 grub2-efi-x64"
            ;;
        sles|opensuse*)
            echo -e "     sudo zypper update shim grub2-x86_64-efi"
            ;;
        *)
            echo -e "     Update shim and GRUB packages using your distribution's package manager."
            ;;
    esac
    STEP=$((STEP + 1))

    echo -e "  ${STEP}. Reboot and re-run this script to verify."
fi

echo ""

# Exit code: 0 = pass/not-applicable, 1 = action needed
if [ "$SB_ENABLED" = "true" ] && { [ "$HAS_2023_DB" = "false" ] || [ "$HAS_2023_KEK" = "false" ]; }; then
    exit 1
else
    exit 0
fi
