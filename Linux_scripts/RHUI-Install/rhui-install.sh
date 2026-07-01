#!/bin/bash
#===============================================================================
# RHUI Installation Automation Script for Microsoft Azure RHEL Images
#===============================================================================
#
# PURPOSE
# -------
# This script automatically installs the correct RHUI package and repository
# configuration for Red Hat Enterprise Linux virtual machines running in
# Microsoft Azure.
#
# The script detects:
#   - RHEL major/minor version
#   - Azure image type
#   - EUS eligibility
#   - SAP / HA image variants
#   - Last supported releases
#
# Based on detected VM metadata, the script automatically selects:
#   - Correct RHUI package
#   - Correct RHUI repository
#   - EUS or Non-EUS model
#   - releasever version lock requirement
#
#
# SUPPORTED IMAGE TYPES
# ---------------------
#   - Standard RHEL images
#   - SAP images
#   - SAP Apps images
#   - SAP HA images
#   - HA images
#
#
# SUPPORTED RHEL VERSIONS
# -----------------------
#   - RHEL 7
#   - RHEL 8
#   - RHEL 9
#   - RHEL10
#
#
# IMPORTANT NOTES
# ---------------
# 1. SAPAPPS / SAP-HA / HA images support only:
#       - Even-numbered EUS/E4S releases
#       - Last supported releases
#
# 2. Last supported releases:
#       - RHEL 7.9
#       - RHEL 8.10
#       - RHEL 9.10
#       - RHEL 10.X
#
# 3. releasever lock is automatically configured for:
#       - EUS-enabled systems
#       - SAP/HA EUS-based images
#
# 4. releasever lock is NOT configured for:
#       - Last supported releases
#       - Non-EUS systems
#
#
# USAGE
# -----
# chmod +x rhui-install.sh
# sudo ./rhui-install.sh
#
#
# REQUIREMENTS
# ------------
#   - Azure VM
#   - Internet access to RHUI servers
#   - curl package
#   - root/sudo privileges
#
#===============================================================================
set -euo pipefail

METADATA_URL="http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"
HEADER="Metadata:true"
RHUI_HOST="rhui4-1.microsoft.com"

#--------------------------------------------------
# UI Helpers
#--------------------------------------------------
line() { echo "--------------------------------------------------"; }
section() { echo; echo "[ $1 ]"; }
info() { echo "➜  $1"; }
ok() { echo "✔  $1"; }
warn() { echo "⚠  $1"; }
fail() { echo "✖  $1"; exit 1; }

#--------------------------------------------------
# Helper: Package Manager
#--------------------------------------------------
pkg_mgr() {
    if [[ "$OS_VERSION" -ge 8 ]]; then
        echo "dnf"
    else
        echo "yum"
    fi
}

#--------------------------------------------------
# Helper: Repo Query
#--------------------------------------------------
repo_query() {
    if [[ "$OS_VERSION" -ge 8 ]]; then
        dnf repoquery --config "$1" --qf "$2" "$3" 2>/dev/null || true
    else
        repoquery --config "$1" --qf "$2" "$3" 2>/dev/null || true
    fi
}

#--------------------------------------------------
# 1. OS Details
#--------------------------------------------------
section "Detecting Operating System"

[ -f /etc/os-release ] || fail "OS detection failed"

source /etc/os-release

OS_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
OS_MINOR=$(echo "${VERSION_ID#*.}" | cut -d '.' -f1)
OS_MINOR=${OS_MINOR:-0}

ok "OS        : $PRETTY_NAME"
ok "Version   : $OS_VERSION"
ok "Minor     : $OS_MINOR"

#--------------------------------------------------
# Last Supported Minor Version Detection
#--------------------------------------------------
LAST_MINOR_RELEASE=0

# RHEL 7  -> 7.9
# RHEL 8+ -> x.10

if [[ "$OS_VERSION" == "7" && "$OS_MINOR" == "9" ]]; then
    LAST_MINOR_RELEASE=1
elif [[ "$OS_VERSION" -ge 8 && "$OS_MINOR" == "10" ]]; then
    LAST_MINOR_RELEASE=1
fi

#--------------------------------------------------
# 2. RHUI Check
#--------------------------------------------------
section "Checking Existing RHUI"

RHUI_INSTALLED=$(rpm -qa | grep -i rhui || true)

if [[ -n "$RHUI_INSTALLED" ]]; then
    warn "RHUI already installed"
    echo "$RHUI_INSTALLED"
    exit 0
fi

ok "RHUI not present"

#--------------------------------------------------
# 3. Azure Metadata
#--------------------------------------------------
section "Fetching Azure Metadata"

METADATA=$(curl -s -H "$HEADER" "$METADATA_URL") || fail "Metadata fetch failed"

OFFER=$(echo "$METADATA" | grep -oP '"offer":\s*"\K[^"]+' | head -1)
SKU=$(echo "$METADATA" | grep -oP '"sku":\s*"\K[^"]+' | head -1)

ok "Offer : $OFFER"
ok "SKU   : $SKU"

#--------------------------------------------------
# 4. Detect Image Type
#--------------------------------------------------
section "Detecting Image Type"

SKU_LOWER=$(echo "$SKU" | tr '[:upper:]' '[:lower:]')
IMAGE_SUFFIX="standard"

if echo "$SKU_LOWER" | grep -q "sapapps"; then
    IMAGE_SUFFIX="sapapps"
elif echo "$SKU_LOWER" | grep -q "sap" && echo "$SKU_LOWER" | grep -q "ha"; then
    IMAGE_SUFFIX="sap-ha"
elif echo "$SKU_LOWER" | grep -q "sap"; then
    IMAGE_SUFFIX="sap"
elif echo "$SKU_LOWER" | grep -q "ha"; then
    IMAGE_SUFFIX="ha"
fi

ok "Detected Image Type : $IMAGE_SUFFIX"

#--------------------------------------------------
# Unsupported SAP / HA Minor Version Validation
#--------------------------------------------------

if [[ "$IMAGE_SUFFIX" == "sapapps" || \
      "$IMAGE_SUFFIX" == "sap-ha" || \
      "$IMAGE_SUFFIX" == "ha" ]]; then
    section "Validating Supported Minor Version"
    SUPPORTED_VERSION=0

    # Last supported releases
    if [[ "$LAST_MINOR_RELEASE" -eq 1 ]]; then
        SUPPORTED_VERSION=1

    # Supported EUS/E4S releases = even minor versions
    elif (( OS_MINOR % 2 == 0 )); then
        SUPPORTED_VERSION=1
    fi

    if [[ "$SUPPORTED_VERSION" -ne 1 ]]; then

        echo
        fail "Detected unsupported OS minor version: $OS_VERSION.$OS_MINOR

This VM appears to have been updated using incorrect repositories/packages.

Supported versions for $IMAGE_SUFFIX images include:
  - Even-numbered EUS/E4S minor releases
  - Last supported x.10 releases

Examples:
  - 8.2
  - 8.4
  - 8.6
  - 8.8
  - 8.10
  - 9.2
  - 9.4
  - 9.6
  - 9.8
  - 9.10

Current detected version:
  - $OS_VERSION.$OS_MINOR

Recommended action:
  Create a support case with Microsoft to validate and correct RHUI/repository configuration."
    fi

    ok "Supported OS minor version detected"

fi

#--------------------------------------------------
# 5. RHUI Support Model Detection
#--------------------------------------------------
section "RHUI Support Model Detection"

#--------------------------------------------------
# Check EUS availability for STANDARD images
#--------------------------------------------------
EUS_AVAILABLE=0

if [[ "$IMAGE_SUFFIX" == "standard" ]]; then

    EUS_REPO="microsoft-azure-rhel${OS_VERSION}-eus"
    PREVIEW_CONFIG="/tmp/rhui-preview.repo"

    cat <<EOF > "$PREVIEW_CONFIG"
[$EUS_REPO]
name=EUS Repo
baseurl=https://${RHUI_HOST}/pulp/repos/unprotected/${EUS_REPO}
enabled=1
gpgcheck=0
sslverify=1
EOF

    EUS_PKGS=$(repo_query "$PREVIEW_CONFIG" "%{name}" "rhui-azure-rhel${OS_VERSION}-eus*" | sort -u)

    if [[ -n "$EUS_PKGS" ]]; then
        EUS_AVAILABLE=1
    fi

    rm -f "$PREVIEW_CONFIG"

fi

#--------------------------------------------------
# 6. Automatic EUS / Non-EUS Decision
#--------------------------------------------------

if [[ "$IMAGE_SUFFIX" != "standard" ]]; then

    if [[ "$LAST_MINOR_RELEASE" -eq 1 ]]; then
        warn "EUS is not applicable for this system"
        echo ""
        info "Proceeding with BASE RHUI package automatically"
    else
        warn "Non-EUS is not applicable for this system"
        echo ""
        info "Proceeding with EUS RHUI package automatically"
    fi

else

    # Last supported minor versions should always use Non-EUS
    if [[ "$LAST_MINOR_RELEASE" -eq 1 ]]; then

        info "Detected last supported minor version ($OS_VERSION.$OS_MINOR)"
        info "Proceeding with Non-EUS RHUI package automatically"
        MODE="2"

    # Even minor version -> EUS
    # Odd minor version  -> Non-EUS
    elif (( OS_MINOR % 2 == 0 )); then

        if [[ "$EUS_AVAILABLE" -eq 1 ]]; then
            info "Detected OS version ($OS_VERSION.$OS_MINOR)"
            info "Proceeding with EUS RHUI package automatically"
            MODE="1"
        else
            warn "Even minor version detected but EUS repo not available"
            info "Proceeding with Non-EUS automatically"
            MODE="2"
        fi

    else

        info "Detected ODD minor version ($OS_MINOR)"
        info "Proceeding with Non-EUS RHUI package automatically"
        MODE="2"

    fi

fi

#--------------------------------------------------
# 7. Package Selection
#--------------------------------------------------
section "Selecting RHUI Package"

PKG_BASE="rhui-azure-rhel${OS_VERSION}"

case "$IMAGE_SUFFIX" in

    sapapps)
        if [[ "$LAST_MINOR_RELEASE" -eq 1 ]]; then
            PKG="${PKG_BASE}-base-sap-apps"
            REPO_NAME="microsoft-azure-rhel${OS_VERSION}-base-sap-apps"
        else
            PKG="${PKG_BASE}-sapapps"
            REPO_NAME="microsoft-azure-rhel${OS_VERSION}-sapapps"
        fi
        ;;

    sap-ha)
        if [[ "$LAST_MINOR_RELEASE" -eq 1 ]]; then
            PKG="${PKG_BASE}-base-sap-ha"
            REPO_NAME="microsoft-azure-rhel${OS_VERSION}-base-sap-ha"
        else
            PKG="${PKG_BASE}-sap-ha"
            REPO_NAME="microsoft-azure-rhel${OS_VERSION}-sap-ha"
        fi
        ;;

    ha)
        if [[ "$LAST_MINOR_RELEASE" -eq 1 ]]; then
            PKG="${PKG_BASE}-base-ha"
            REPO_NAME="microsoft-azure-rhel${OS_VERSION}-base-ha"
        else
            PKG="${PKG_BASE}-ha"
            REPO_NAME="microsoft-azure-rhel${OS_VERSION}-ha"
        fi
        ;;

    sap)
        PKG="${PKG_BASE}-sap"
        REPO_NAME="microsoft-azure-rhel${OS_VERSION}-sap"
        ;;

    standard)
        if [[ "$MODE" == "1" ]]; then
            PKG="${PKG_BASE}-eus"
            REPO_NAME="microsoft-azure-rhel${OS_VERSION}-eus"
        else
            PKG="${PKG_BASE}"
            REPO_NAME="microsoft-azure-rhel${OS_VERSION}"
        fi
        ;;

esac

ok "Selected Package : $PKG"
ok "Repo Name        : $REPO_NAME"

#--------------------------------------------------
# 8. Create Repo
#--------------------------------------------------
CONFIG_FILE="/tmp/rhui.repo"

section "Creating Repository Configuration"

cat <<EOF > "$CONFIG_FILE"
[$REPO_NAME]
name=Microsoft Azure RPMs for RHEL $OS_VERSION ($REPO_NAME)
baseurl=https://${RHUI_HOST}/pulp/repos/unprotected/${REPO_NAME}
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
sslverify=1
EOF

ok "Repository file created"

#--------------------------------------------------
# 9. Install RHUI
#--------------------------------------------------
section "Installing RHUI Package"

PM=$(pkg_mgr)
TMP_LOG="/tmp/rhui_install.log"

info "Installing package: $PKG"

if ! $PM --config "$CONFIG_FILE" install -y "$PKG" >"$TMP_LOG" 2>&1; then
    echo
    echo "✖ Installation failed"
    echo
    echo "------ ERROR DETAILS ------"
    cat "$TMP_LOG"
    echo "---------------------------"
    exit 1
fi

ok "Installed: $PKG"

#--------------------------------------------------
# 10. VERSION LOCK
#--------------------------------------------------
section "Configuring release version lock"

CURRENT_VERSION="$VERSION_ID"
SET_LOCK=0

# SAP / HA → only if NOT base versions
if [[ "$IMAGE_SUFFIX" != "standard" ]]; then
    if [[ "$LAST_MINOR_RELEASE" -ne 1 ]]; then
        SET_LOCK=1
    fi
fi

# Standard → only if EUS selected
if [[ "$IMAGE_SUFFIX" == "standard" && "${MODE:-}" == "1" ]]; then
    SET_LOCK=1
fi

if [[ "$SET_LOCK" -eq 1 ]]; then

    if [[ "$OS_VERSION" -ge 8 ]]; then
        VAR_PATH="/etc/dnf/vars/releasever"
    else
        VAR_PATH="/etc/yum/vars/releasever"
    fi

    mkdir -p "$(dirname "$VAR_PATH")"
    echo "$CURRENT_VERSION" > "$VAR_PATH"

    ok "releasever locked to $CURRENT_VERSION"

else
    info "releasever lock not required"
fi

#--------------------------------------------------
# 11. Validation
#--------------------------------------------------
section "Validating Installation"

rpm -qa | grep -i rhui || fail "RHUI install failed"

ok "RHUI package verified"

$PM repolist >/dev/null 2>&1 || fail "Repo access failed"

ok "Repositories accessible"

#--------------------------------------------------
# 12. Summary
#--------------------------------------------------
section "Installation Complete"

echo "RHUI installation completed successfully!"
echo
echo "Summary"

line

echo "OS        : $PRETTY_NAME"
echo "Image     : $IMAGE_SUFFIX"
echo "Repo      : $REPO_NAME"
echo "Package   : $(rpm -qa | grep -i rhui)"

line
