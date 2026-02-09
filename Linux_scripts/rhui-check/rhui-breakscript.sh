#!/bin/bash

#######################################################################
# RHUI Break/Fix Script
# Purpose: Break and fix various RHUI connectivity scenarios for testing
# Usage: 
#   rhuibreak.sh --break <scenario_number>
#   rhuibreak.sh --fix <scenario_number>
#   rhuibreak.sh --list
#######################################################################

set -e

# Configuration
LOGFILE="/var/log/rhuibreak.log"
BACKUP_DIR="/var/tmp/rhuibreak_backups"
RHUI4_IPS=("52.136.197.163" "20.225.226.182" "52.142.4.99" "20.248.180.252" "20.24.186.80")
RHUI3_IPS=("13.91.47.76" "40.85.190.91" "52.187.75.218")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#######################################################################
# Helper Functions
#######################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log_error() {
    echo -e "${RED}[ERROR] $*${NC}" | tee -a "$LOGFILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $*${NC}" | tee -a "$LOGFILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $*${NC}" | tee -a "$LOGFILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_rhel() {
    if [[ ! -f /etc/redhat-release ]]; then
        log_error "This script must be run on a RHEL system"
        exit 1
    fi
}

create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        local backup_name="$(basename "$file").backup.$(date +%s)"
        cp "$file" "$BACKUP_DIR/$backup_name"
        log "Backed up $file to $BACKUP_DIR/$backup_name"
    fi
}

#######################################################################
# Scenario 1: Block outbound traffic to RHUI IPs (Internal LB simulation)
#######################################################################

break_scenario_1() {
    log "Breaking Scenario 1: Blocking outbound traffic to RHUI IPs"
    
    # Block RHUI4 IPs using iptables
    for ip in "${RHUI4_IPS[@]}"; do
        iptables -A OUTPUT -d "$ip" -j DROP
        log "Blocked outbound traffic to $ip"
    done
    
    # Block RHUI3 IPs as well
    for ip in "${RHUI3_IPS[@]}"; do
        iptables -A OUTPUT -d "$ip" -j DROP
        log "Blocked outbound traffic to $ip"
    done
    
    # Save iptables rules
    if command -v iptables-save &> /dev/null; then
        iptables-save > "$BACKUP_DIR/iptables.rules.blocked"
        log_success "Scenario 1 broken: RHUI IPs blocked via iptables"
    fi
}

fix_scenario_1() {
    log "Fixing Scenario 1: Removing blocks on RHUI IPs"
    
    # Remove blocks for RHUI4 IPs
    for ip in "${RHUI4_IPS[@]}"; do
        iptables -D OUTPUT -d "$ip" -j DROP 2>/dev/null || true
        log "Removed block for $ip"
    done
    
    # Remove blocks for RHUI3 IPs
    for ip in "${RHUI3_IPS[@]}"; do
        iptables -D OUTPUT -d "$ip" -j DROP 2>/dev/null || true
        log "Removed block for $ip"
    done
    
    log_success "Scenario 1 fixed: RHUI IPs unblocked"
}

#######################################################################
# Scenario 2: Add incorrect routes (Force tunnel simulation)
#######################################################################

break_scenario_2() {
    log "Breaking Scenario 2: Adding incorrect routes to RHUI IPs"
    
    # Add routes that send RHUI traffic to a black hole
    for ip in "${RHUI4_IPS[@]}"; do
        ip route add "$ip" via 127.0.0.1 2>/dev/null || true
        log "Added incorrect route for $ip"
    done
    
    log_success "Scenario 2 broken: Incorrect routes added"
}

fix_scenario_2() {
    log "Fixing Scenario 2: Removing incorrect routes"
    
    # Remove incorrect routes
    for ip in "${RHUI4_IPS[@]}"; do
        ip route del "$ip" via 127.0.0.1 2>/dev/null || true
        log "Removed incorrect route for $ip"
    done
    
    log_success "Scenario 2 fixed: Incorrect routes removed"
}

#######################################################################
# Scenario 3: Block via hosts file (Firewall simulation)
#######################################################################

break_scenario_3() {
    log "Breaking Scenario 3: Blocking RHUI hostnames via /etc/hosts"
    
    backup_file "/etc/hosts"
    
    # Add entries that point RHUI hostnames to localhost
    cat >> /etc/hosts << EOF

# RHUI Break - Scenario 3
127.0.0.1 rhui-1.microsoft.com
127.0.0.1 rhui-2.microsoft.com
127.0.0.1 rhui-3.microsoft.com
127.0.0.1 rhui4-1.microsoft.com
127.0.0.1 rhui4-2.microsoft.com
127.0.0.1 rhui4-3.microsoft.com
EOF
    
    log_success "Scenario 3 broken: RHUI hostnames redirected to localhost"
}

fix_scenario_3() {
    log "Fixing Scenario 3: Removing RHUI hostname blocks from /etc/hosts"
    
    backup_file "/etc/hosts"
    
    # Remove the RHUI entries
    sed -i '/# RHUI Break - Scenario 3/,+6d' /etc/hosts
    
    log_success "Scenario 3 fixed: RHUI hostname blocks removed"
}

#######################################################################
# Scenario 4: Corrupt CA certificates (SSL inspection simulation)
#######################################################################

break_scenario_4() {
    log "Breaking Scenario 4: Corrupting CA certificates"
    
    # Corrupt a source certificate file that rpm -V will detect
    # These files are part of the ca-certificates package and tracked by RPM
    local ca_file="/etc/pki/ca-trust/source/ca-bundle.trust.crt"
    
    if [[ ! -f "$ca_file" ]]; then
        # Try alternate location for older RHEL versions
        ca_file="/usr/share/pki/ca-trust-source/ca-bundle.trust.p11-kit"
    fi
    
    if [[ -f "$ca_file" ]]; then
        backup_file "$ca_file"
        
        # Copy to /tmp with permissions preserved
        cp -a "$ca_file" "/tmp/$(basename "$ca_file").scenario4.orig"
        log "Backed up to /tmp/$(basename "$ca_file").scenario4.orig"
        
        # Corrupt the source CA file (this will be detected by rpm -V)
        echo "INVALID CERTIFICATE DATA" >> "$ca_file"
        log "Corrupted CA source file: $ca_file"
        
        # Update CA trust to propagate the corruption
        update-ca-trust 2>/dev/null || true
        
        log_success "Scenario 4 broken: CA certificates corrupted"
    else
        log_error "Could not find CA certificate source file to corrupt"
        return 1
    fi
}

fix_scenario_4() {
    log "Fixing Scenario 4: Restoring CA certificates"
    
    # Find the backed up CA file
    local ca_file="/etc/pki/ca-trust/source/ca-bundle.trust.crt"
    local backup="/tmp/$(basename "$ca_file").scenario4.orig"
    
    if [[ ! -f "$ca_file" ]]; then
        ca_file="/usr/share/pki/ca-trust-source/ca-bundle.trust.p11-kit"
        backup="/tmp/$(basename "$ca_file").scenario4.orig"
    fi
    
    if [[ -f "$backup" ]]; then
        # Restore from /tmp with permissions preserved
        cp -a "$backup" "$ca_file"
        log "Restored CA file from $backup"
        rm -f "$backup"
    else
        log_warning "Backup not found in /tmp, reinstalling package"
        yum reinstall -y ca-certificates 2>/dev/null || dnf reinstall -y ca-certificates 2>/dev/null
    fi
    
    # Update CA trust
    update-ca-trust
    
    log_success "Scenario 4 fixed: CA certificates restored"
}

#######################################################################
# Scenario 5: Add incorrect proxy configuration
#######################################################################

break_scenario_5() {
    log "Breaking Scenario 5: Adding incorrect proxy configuration"
    
    local yum_conf="/etc/yum.conf"
    local dnf_conf="/etc/dnf/dnf.conf"
    
    # Determine which config file to use
    if [[ -f "$dnf_conf" ]]; then
        backup_file "$dnf_conf"
        
        cat >> "$dnf_conf" << EOF

# RHUI Break - Scenario 5
proxy=http://invalid-proxy.local:3128
proxy_username=invalid-user
proxy_password=invalid-password
EOF
        log "Added invalid proxy to $dnf_conf"
    elif [[ -f "$yum_conf" ]]; then
        backup_file "$yum_conf"
        
        cat >> "$yum_conf" << EOF

# RHUI Break - Scenario 5
proxy=http://invalid-proxy.local:3128
proxy_username=invalid-user
proxy_password=invalid-password
EOF
        log "Added invalid proxy to $yum_conf"
    fi
    
    log_success "Scenario 5 broken: Invalid proxy configuration added"
}

fix_scenario_5() {
    log "Fixing Scenario 5: Removing proxy configuration"
    
    local yum_conf="/etc/yum.conf"
    local dnf_conf="/etc/dnf/dnf.conf"
    
    if [[ -f "$dnf_conf" ]]; then
        sed -i '/# RHUI Break - Scenario 5/,+3d' "$dnf_conf"
        log "Removed proxy from $dnf_conf"
    fi
    
    if [[ -f "$yum_conf" ]]; then
        sed -i '/# RHUI Break - Scenario 5/,+3d' "$yum_conf"
        log "Removed proxy from $yum_conf"
    fi
    
    log_success "Scenario 5 fixed: Proxy configuration removed"
}

#######################################################################
# Scenario 6: Remove/Corrupt RHUI package
#######################################################################

break_scenario_6() {
    log "Breaking Scenario 6: Corrupting RHUI package"
    
    # Find RHUI package
    local rhui_pkg=$(rpm -qa 'rhui-*' | head -1)
    
    if [[ -z "$rhui_pkg" ]]; then
        log_error "No RHUI package found"
        return 1
    fi
    
    log "Found RHUI package: $rhui_pkg"
    
    # Corrupt the repo file
    local repo_file=$(rpm -ql "$rhui_pkg" | grep '\.repo$' | head -1)
    if [[ -n "$repo_file" ]]; then
        backup_file "$repo_file"
        
        # Copy to /tmp with permissions preserved
        cp -a "$repo_file" "/tmp/$(basename "$repo_file").scenario6.orig"
        log "Backed up to /tmp/$(basename "$repo_file").scenario6.orig"
        
        echo "CORRUPTED DATA" > "$repo_file"
        log "Corrupted repo file: $repo_file"
    fi
    
    log_success "Scenario 6 broken: RHUI package corrupted"
}

fix_scenario_6() {
    log "Fixing Scenario 6: Restoring RHUI package files"
    
    # Find RHUI package
    local rhui_pkg=$(rpm -qa 'rhui-*' | head -1)
    
    if [[ -z "$rhui_pkg" ]]; then
        log_error "No RHUI package found"
        return 1
    fi
    
    # Find the repo file
    local repo_file=$(rpm -ql "$rhui_pkg" | grep '\.repo$' | head -1)
    local backup="/tmp/$(basename "$repo_file").scenario6.orig"
    
    if [[ -f "$backup" ]]; then
        # Restore from /tmp with permissions preserved
        cp -a "$backup" "$repo_file"
        log "Restored repo file from $backup"
        rm -f "$backup"
    else
        log_warning "Backup not found in /tmp, reinstalling package"
        if command -v dnf &> /dev/null; then
            dnf reinstall -y "$rhui_pkg"
        else
            yum reinstall -y "$rhui_pkg"
        fi
    fi
    
    log_success "Scenario 6 fixed: RHUI package files restored"
}

#######################################################################
# Scenario 7: Simulate certificate expiration
#######################################################################

break_scenario_7() {
    log "Breaking Scenario 7: Simulating certificate expiration"
    
    # Find RHUI client certificate and key
    local rhui_pkg=$(rpm -qa 'rhui-*' | head -1)
    local cert_file=$(rpm -ql "$rhui_pkg" | grep '\.crt$' | head -1)
    local key_file=$(rpm -ql "$rhui_pkg" | grep '\.pem$' | head -1)
    
    if [[ -z "$cert_file" ]]; then
        log_error "No certificate file found"
        return 1
    fi
    
    backup_file "$cert_file"
    
    # Copy to /tmp with permissions preserved
    cp -a "$cert_file" "/tmp/$(basename "$cert_file").scenario7.orig"
    log "Backed up cert to /tmp/$(basename "$cert_file").scenario7.orig"
    
    if [[ -n "$key_file" && -f "$key_file" ]]; then
        cp -a "$key_file" "/tmp/$(basename "$key_file").scenario7.orig"
        log "Backed up key to /tmp/$(basename "$key_file").scenario7.orig"
    fi
    
    # Create an expired certificate (set system time forward temporarily is complex,
    # so we'll corrupt the cert instead to simulate validation failure)
    # Replace with a self-signed expired cert
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/expired.key -out "$cert_file" \
        -days -1 -nodes -subj "/CN=expired.microsoft.com" 2>/dev/null || {
        # If openssl fails, just corrupt the cert
        echo "EXPIRED CERTIFICATE" > "$cert_file"
    }
    
    log_success "Scenario 7 broken: Certificate corrupted/expired"
}

fix_scenario_7() {
    log "Fixing Scenario 7: Restoring certificate"
    
    # Find RHUI certificate and key files
    local rhui_pkg=$(rpm -qa 'rhui-*' | head -1)
    
    if [[ -z "$rhui_pkg" ]]; then
        log_error "No RHUI package found"
        return 1
    fi
    
    local cert_file=$(rpm -ql "$rhui_pkg" | grep '\.crt$' | head -1)
    local key_file=$(rpm -ql "$rhui_pkg" | grep '\.pem$' | head -1)
    
    local cert_backup="/tmp/$(basename "$cert_file").scenario7.orig"
    local key_backup="/tmp/$(basename "$key_file").scenario7.orig"
    
    local restored=0
    
    if [[ -f "$cert_backup" ]]; then
        # Restore cert from /tmp with permissions preserved
        cp -a "$cert_backup" "$cert_file"
        log "Restored certificate from $cert_backup"
        rm -f "$cert_backup"
        restored=1
    fi
    
    if [[ -n "$key_file" && -f "$key_backup" ]]; then
        # Restore key from /tmp with permissions preserved
        cp -a "$key_backup" "$key_file"
        log "Restored key from $key_backup"
        rm -f "$key_backup"
        restored=1
    fi
    
    if [[ $restored -eq 0 ]]; then
        log_warning "Backup not found in /tmp, reinstalling package"
        rpm -e --nodeps "$rhui_pkg" 2>/dev/null || true
        if command -v dnf &> /dev/null; then
            yum install -y "$rhui_pkg" 2>/dev/null || dnf install -y "$rhui_pkg"
        else
            yum install -y "$rhui_pkg"
        fi
    fi
    
    log_success "Scenario 7 fixed: Certificate restored"
}

#######################################################################
# Scenario 8: Incorrect repository configuration
#######################################################################

break_scenario_8() {
    log "Breaking Scenario 8: Creating incorrect repository configuration"
    
    # Find the RHUI repo file
    local rhui_pkg=$(rpm -qa 'rhui-*' | head -1)
    local repo_file=$(rpm -ql "$rhui_pkg" | grep '\.repo$' | head -1)
    
    if [[ -z "$repo_file" ]]; then
        log_error "No repo file found"
        return 1
    fi
    
    backup_file "$repo_file"
    
    # Copy to /tmp with permissions preserved
    cp -a "$repo_file" "/tmp/$(basename "$repo_file").scenario8.orig"
    log "Backed up to /tmp/$(basename "$repo_file").scenario8.orig"
    
    # Corrupt the baseurl
    sed -i 's|baseurl=|baseurl=http://invalid.repo.microsoft.com/|' "$repo_file"
    
    # Disable the repos
    sed -i 's|enabled=1|enabled=0|g' "$repo_file"
    
    log_success "Scenario 8 broken: Repository configuration corrupted"
}

fix_scenario_8() {
    log "Fixing Scenario 8: Restoring repository configuration"
    
    local rhui_pkg=$(rpm -qa 'rhui-*' | head -1)
    
    if [[ -z "$rhui_pkg" ]]; then
        log_error "No RHUI package found"
        return 1
    fi
    
    # Find the repo file
    local repo_file=$(rpm -ql "$rhui_pkg" | grep '\.repo$' | head -1)
    local backup="/tmp/$(basename "$repo_file").scenario8.orig"
    
    if [[ -f "$backup" ]]; then
        # Restore from /tmp with permissions preserved
        cp -a "$backup" "$repo_file"
        log "Restored repo file from $backup"
        rm -f "$backup"
    else
        log_warning "Backup not found in /tmp, reinstalling package"
        if command -v dnf &> /dev/null; then
            dnf reinstall -y "$rhui_pkg"
        else
            yum reinstall -y "$rhui_pkg"
        fi
    fi
    
    log_success "Scenario 8 fixed: Repository configuration restored"
}

#######################################################################
# Scenario 9: DNS resolution issues
#######################################################################

break_scenario_9() {
    log "Breaking Scenario 9: Breaking DNS resolution for RHUI"
    
    backup_file "/etc/resolv.conf"
    
    # Point to an invalid DNS server
    cat > /etc/resolv.conf << EOF
# RHUI Break - Scenario 9
nameserver 127.0.0.1
nameserver 192.0.2.1
EOF
    
    # Make it immutable so DHCP doesn't overwrite
    chattr +i /etc/resolv.conf 2>/dev/null || true
    
    log_success "Scenario 9 broken: DNS resolution broken"
}

fix_scenario_9() {
    log "Fixing Scenario 9: Restoring DNS resolution"
    
    # Remove immutable flag
    chattr -i /etc/resolv.conf 2>/dev/null || true
    
    # Restore from backup or use default
    local latest_backup=$(ls -t "$BACKUP_DIR"/resolv.conf.backup.* 2>/dev/null | head -1)
    
    if [[ -n "$latest_backup" ]]; then
        cp "$latest_backup" /etc/resolv.conf
        log "Restored from backup: $latest_backup"
    else
        # Use Azure's default DNS
        cat > /etc/resolv.conf << EOF
nameserver 168.63.129.16
options timeout:2 attempts:5
EOF
        log "Restored default Azure DNS configuration"
    fi
    
    log_success "Scenario 9 fixed: DNS resolution restored"
}

#######################################################################
# Main Menu and Execution
#######################################################################

list_scenarios() {
    cat << 'EOF'
Available RHUI Break/Fix Scenarios:
====================================

1.  Block outbound traffic to RHUI IPs (Internal Load Balancer simulation)
2.  Add incorrect routes to RHUI (Force tunnel simulation)
3.  Block RHUI via hosts file (Firewall simulation)
4.  Corrupt CA certificates (SSL inspection issues)
5.  Add incorrect proxy configuration
6.  Remove/Corrupt RHUI package
7.  Simulate certificate expiration
8.  Corrupt repository configuration
9.  Break DNS resolution

Usage:
  ./rhuibreak.sh --break <number>    Break a specific scenario
  ./rhuibreak.sh --fix <number>      Fix a specific scenario
  ./rhuibreak.sh --list              List all scenarios
  ./rhuibreak.sh --break-all         Break all scenarios
  ./rhuibreak.sh --fix-all           Fix all scenarios

Examples:
  ./rhuibreak.sh --break 1           Break scenario 1
  ./rhuibreak.sh --fix 5             Fix scenario 5

EOF
}

break_all() {
    log "Breaking all scenarios..."
    for i in {1..9}; do
        log "Breaking scenario $i"
        break_scenario_$i || log_warning "Failed to break scenario $i"
    done
    log_success "All scenarios broken"
}

fix_all() {
    log "Fixing all scenarios..."
    for i in {1..9}; do
        log "Fixing scenario $i"
        fix_scenario_$i || log_warning "Failed to fix scenario $i"
    done
    log_success "All scenarios fixed"
}

#######################################################################
# Main Script
#######################################################################

main() {
    check_root
    check_rhel
    create_backup_dir
    
    if [[ $# -eq 0 ]]; then
        list_scenarios
        exit 0
    fi
    
    case "$1" in
        --list)
            list_scenarios
            ;;
        --break)
            if [[ -z "$2" ]]; then
                log_error "Please specify a scenario number"
                exit 1
            fi
            scenario=$2
            if [[ "$scenario" =~ ^[1-9]$ ]]; then
                break_scenario_$scenario
            else
                log_error "Invalid scenario number: $scenario"
                exit 1
            fi
            ;;
        --fix)
            if [[ -z "$2" ]]; then
                log_error "Please specify a scenario number"
                exit 1
            fi
            scenario=$2
            if [[ "$scenario" =~ ^[1-9]$ ]]; then
                fix_scenario_$scenario
            else
                log_error "Invalid scenario number: $scenario"
                exit 1
            fi
            ;;
        --break-all)
            break_all
            ;;
        --fix-all)
            fix_all
            ;;
        *)
            log_error "Unknown option: $1"
            list_scenarios
            exit 1
            ;;
    esac
}

main "$@"
