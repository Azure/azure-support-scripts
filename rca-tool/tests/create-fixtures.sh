#!/bin/bash
# Script to generate test fixtures for SAP HANA Cluster Analyzer

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

echo "Creating test fixtures in $FIXTURES_DIR"
mkdir -p "$FIXTURES_DIR"

# Function to create and compress test data
create_fixture() {
    local name=$1
    echo "Creating $name..."
    # Create an scc-style directory structure
    mkdir -p "scc_$name"
    mv test-data/* "scc_$name/" 2>/dev/null || true
    rmdir test-data 2>/dev/null || true
    tar -cJf "$FIXTURES_DIR/scc_$name.tar.xz" "scc_$name"
    rm -rf "scc_$name"
    echo "✓ Created scc_$name"
}

# 1. Test for systemd false positives
echo ""
echo "=== Creating test-systemd-messages.tar.xz ==="
mkdir -p test-data/var/log
cat > test-data/var/log/messages.txt << 'EOF'
2025-11-13T07:39:23.000000+01:00 node01 kernel: Linux version 5.14.0
2025-11-13T07:39:23.997956+01:00 node01 systemd[1]: Stopping Getty on tty1...
2025-11-13T07:39:24.145728+01:00 node01 S50PatrolAgent.sh[1186580]: [LOG]Stopping PatrolAgent on port 3181.
2025-11-13T07:39:24.350856+01:00 node01 systemd[1]: Stopped Getty on tty1.
2025-11-13T07:39:25.000000+01:00 node01 systemd[1]: Started Session 123 of user root.
EOF
create_fixture "test-systemd-messages"

# 2. Test for Azure VM properties - BYOS via License Type
echo ""
echo "=== Creating test-azure-vm.tar.xz ==="
mkdir -p test-data
cat > test-data/instance_metadata.json << 'EOF'
{
  "vmSize": "Standard_E4s_v3",
  "publisher": "SUSE",
  "offer": "sles-sap-15-sp4-byos",
  "sku": "gen2",
  "licenseType": "SLES_BYOS"
}
EOF
mkdir -p test-data/etc
cat > test-data/etc/os-release << 'EOF'
NAME="SUSE Linux Enterprise Server"
VERSION="15-SP4"
ID="sles"
ID_LIKE="suse"
VERSION_ID="15.4"
PRETTY_NAME="SUSE Linux Enterprise Server 15 SP4"
EOF
create_fixture "test-azure-vm"

################################################################################
# Test 2a: Azure VM PAYG - RHEL with License Type
################################################################################
echo ""
echo "=== Creating test-azure-vm-rhel-payg.tar.xz ==="
mkdir -p test-data
cat > test-data/instance_metadata.json << 'EOF'
{
  "vmSize": "Standard_E16s_v3",
  "publisher": "RedHat",
  "offer": "RHEL-SAP-HA",
  "sku": "8.2",
  "billingCode": "Linux_IaaS_Software_RedHat_SAP_HA",
  "licenseType": "RHEL_SAPHA"
}
EOF
create_fixture "test-azure-vm-rhel-payg"

################################################################################
# Test 2b: Azure VM BYOS - RHEL with Billing Code
################################################################################
echo ""
echo "=== Creating test-azure-vm-rhel-byos.tar.xz ==="
mkdir -p test-data
cat > test-data/instance_metadata.json << 'EOF'
{
  "vmSize": "Standard_E16s_v3",
  "publisher": "RedHat",
  "offer": "rhel-byos",
  "sku": "rhel-lvm84",
  "billingCode": "Linux_IaaS",
  "licenseType": "N/A"
}
EOF
create_fixture "test-azure-vm-rhel-byos"

################################################################################
# Test 2c: Azure VM PAYG - SLES with Billing Code
################################################################################
echo ""
echo "=== Creating test-azure-vm-sles-payg.tar.xz ==="
mkdir -p test-data
cat > test-data/instance_metadata.json << 'EOF'
{
  "vmSize": "Standard_M32ts",
  "publisher": "SUSE",
  "offer": "sles-sap-15-sp3",
  "sku": "gen2",
  "billingCode": "Linux_IaaS_Software_SLES_for_SAP",
  "licenseType": "NONE"
}
EOF
create_fixture "test-azure-vm-sles-payg"

################################################################################
# Test 2d: Azure VM BYOS - Canonical Ubuntu
################################################################################
echo ""
echo "=== Creating test-azure-vm-ubuntu-byos.tar.xz ==="
mkdir -p test-data
cat > test-data/instance_metadata.json << 'EOF'
{
  "vmSize": "Standard_D4s_v3",
  "publisher": "Canonical",
  "offer": "0001-com-ubuntu-server-focal",
  "sku": "20_04-lts",
  "billingCode": "Linux_IaaS_Canonical"
}
EOF
create_fixture "test-azure-vm-ubuntu-byos"

################################################################################
# Test 2e: Azure VM PAYG - Ubuntu Pro
################################################################################
echo ""
echo "=== Creating test-azure-vm-ubuntu-pro.tar.xz ==="
mkdir -p test-data
cat > test-data/instance_metadata.json << 'EOF'
{
  "vmSize": "Standard_D4s_v3",
  "publisher": "Canonical",
  "offer": "0001-com-ubuntu-pro-focal",
  "sku": "pro-20_04-lts",
  "licenseType": "UBUNTU_PRO"
}
EOF
create_fixture "test-azure-vm-ubuntu-pro"

################################################################################
# Test 2f: Azure VM from SCC metadata.txt format (SLES SAP)
################################################################################
echo ""
echo "=== Creating test-azure-vm-scc-metadata.tar.xz ==="
mkdir -p test-data/public_cloud
cat > test-data/public_cloud/metadata.txt << 'EOF'
vmSize: Standard_M64ds_v2
publisher: SUSE
offer: sles-sap-15-sp5
sku: gen2
billingCode: Linux_IaaS_Software_SLES_for_SAP
licenseType: SLES_SAP
EOF
create_fixture "test-azure-vm-scc-metadata"

################################################################################
# Test 2g: Distribution detection from crm_report sysinfo.txt
################################################################################
echo ""
echo "=== Creating test-crm-report-sysinfo.tar.xz ==="
mkdir -p test-data
cat > test-data/sysinfo.txt << 'EOF'
#####Cluster info:
Corosync Cluster Engine, version '2.4.6'
Copyright (c) 2006-2009 Red Hat, Inc.
resource-agents: UNKnown

#####Cluster related packages:
pacemaker 2.1.5+20221208.a3f44794f-150500.6.17.1 - SUSE Linux Enterprise 15 x86_64
corosync 2.4.6-150300.12.10.1 - SUSE Linux Enterprise 15 x86_64
resource-agents 4.12.0+git30.7fd7c8fa-150500.3.12.2 - SUSE Linux Enterprise 15 x86_64

#####System info:
Platform: Linux
Kernel release: 5.14.21-150500.55.83-default
Architecture: x86_64
Distribution: SUSE Linux Enterprise Server 15 SP5
EOF
create_fixture "test-crm-report-sysinfo"

# 3. Test for cluster nodes and /etc/hosts validation
echo ""
echo "=== Creating test-cluster-nodes.tar.xz ==="
mkdir -p test-data/etc
cat > test-data/etc/hosts << 'EOF'
127.0.0.1   localhost
10.0.1.10   node1
10.0.1.11   node2
EOF
mkdir -p test-data
cat > test-data/ha.txt << 'EOF'
# /etc/hosts
127.0.0.1   localhost
10.0.1.10   node1
10.0.1.11   node2
10.0.1.12   node3
#==[ Configuration File ]====
EOF
cat > test-data/corosync.conf << 'EOF'
totem {
    version: 2
    cluster_name: hana-cluster
    token: 30000
}
nodelist {
    node {
        ring0_addr: node1
        nodeid: 1
    }
    node {
        ring0_addr: node2
        nodeid: 2
    }
    node {
        ring0_addr: node3
        nodeid: 3
    }
}
quorum {
    provider: corosync_votequorum
    expected_votes: 3
}
EOF
create_fixture "test-cluster-nodes"

# 4. Test for Corosync configuration
echo ""
echo "=== Creating test-corosync-config.tar.xz ==="
mkdir -p test-data
cat > test-data/corosync.conf << 'EOF'
totem {
    version: 2
    cluster_name: hana-cluster
    token: 30000
    consensus: 36000
}
quorum {
    provider: corosync_votequorum
    expected_votes: 2
    two_node: 1
}
EOF
create_fixture "test-corosync-config"

# 5. Test for Pacemaker resources
echo ""
echo "=== Creating test-pacemaker-resources.tar.xz ==="
mkdir -p test-data
cat > test-data/ha.txt << 'EOF'
#==[ Command ]====#
# /usr/sbin/crm_mon -1 -r -f
Stack: corosync
Current DC: node1
Last updated: Wed Nov 13 08:00:00 2025
2 nodes configured
3 resources configured

Online: [ node1 node2 ]

Full list of resources:

 rsc_SAPHana_HDB_HDB00  (ocf::heartbeat:SAPHana):      Started node1
 rsc_ip_HDB_HDB00       (ocf::heartbeat:IPaddr2):      Started node1
 stonith-sbd            (stonith:external/sbd):        Started node2
EOF
create_fixture "test-pacemaker-resources"

# 6. Test for fencing configuration
echo ""
echo "=== Creating test-fencing.tar.xz ==="
mkdir -p test-data
cat > test-data/ha.txt << 'EOF'
#==[ Command ]====#
# /usr/sbin/crm configure show
property cib-bootstrap-options: \
    stonith-enabled=true \
    stonith-timeout=150s

primitive stonith-fence_azure_arm stonith:fence_azure_arm \
    op monitor interval=3600 timeout=120
EOF
create_fixture "test-fencing"

# 6b. Test for fencing configuration (pcs_config format)
echo ""
echo "=== Creating test-fencing-pcs.tar.xz ==="
mkdir -p test-data/sos_commands/pacemaker
cat > test-data/sos_commands/pacemaker/pcs_config << 'EOF'
Cluster Name: mycluster
Corosync Nodes:
 node1 node2
Pacemaker Nodes:
 node1 node2

Resources:
  Clone: hana_scale_clone
    Resource: hana_scale (class=ocf provider=suse type=SAPHanaController)

Stonith Devices:
  Resource: rsc_st_azure (class=stonith type=fence_azure_arm)
    Attributes: rsc_st_azure-instance_attributes
      login=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      pcmk_host_map=node1:vm-node1;node2:vm-node2
      resourceGroup=myResourceGroup
      subscriptionId=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      tenantId=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    Operations:
      monitor: rsc_st_azure-monitor-interval-3600
        interval=3600
Fencing Levels:

Cluster Properties:
 cluster-infrastructure: corosync
 cluster-name: mycluster
 stonith-enabled: true
 stonith-timeout: 900
EOF
create_fixture "test-fencing-pcs"

# 7. Test for kernel reboot detection
echo ""
echo "=== Creating test-kernel-reboots.tar.xz ==="
mkdir -p test-data
cat > test-data/messages << 'EOF'
2025-11-12T23:58:59.000000+01:00 node1 systemd[1]: Shutting down.
2025-11-13T00:00:15.000000+01:00 node1 kernel: Linux version 5.14.0-284.30.1.el9_2.x86_64 (mockbuild@x86-64) (gcc version 11.3.0) #1 SMP PREEMPT_DYNAMIC
2025-11-13T00:00:15.000000+01:00 node1 kernel: Command line: BOOT_IMAGE=(hd0,gpt2)/boot/vmlinuz-5.14.0-284.30.1.el9_2.x86_64 root=/dev/mapper/vg_root-lv_root
2025-11-14T15:30:45.000000+01:00 node1 systemd[1]: Shutting down.
2025-11-14T15:31:00.000000+01:00 node1 kernel: Linux version 5.14.0-284.30.1.el9_2.x86_64 (mockbuild@x86-64) (gcc version 11.3.0) #1 SMP PREEMPT_DYNAMIC
2025-11-20T11:32:57.199160-05:00 azlsapzlwdb01 kernel: [    0.000000][    T0] Linux version 5.14.21-150400.24.103-default (geeko@buildhost) (gcc (SUSE Linux) 7.5.0, GNU ld (GNU Binutils; SUSE Linux Enterprise 15) 2.41.0.20230908-150100.7.46) #1 SMP PREEMPT_DYNAMIC Wed Jan 10 13:40:49 UTC 2024 (8afebed)
EOF
create_fixture "test-kernel-reboots"

# 8. Test for OOM killer events
echo ""
echo "=== Creating test-oom-killer.tar.xz ==="
mkdir -p test-data
cat > test-data/messages << 'EOF'
Nov 13 14:23:45 node1 kernel: hdbindexserver invoked oom-killer: gfp_mask=0x201da, order=0, oom_score_adj=0
Nov 13 14:23:45 node1 kernel: Out of memory: Killed process 12345 (hdbindexserver) total-vm:32768000kB
Nov 13 14:23:46 node1 kernel: oom_reaper: reaped process 12345 (hdbindexserver)
EOF
create_fixture "test-oom-killer"

# 9. Test for antivirus detection
echo ""
echo "=== Creating test-antivirus.tar.xz ==="
mkdir -p test-data
cat > test-data/rpm.txt << 'EOF'
falcon-sensor-7.10.16203.0-1.el8.x86_64
gpg-pubkey-7f4f6f89-5e9a18de
EOF
cat > test-data/ps.txt << 'EOF'
root      1234  0.0  0.1 123456  7890 ?        Ssl  10:00   0:00 /opt/CrowdStrike/falcon-sensor
EOF
mkdir -p test-data/opt/CrowdStrike
cat > test-data/opt/CrowdStrike/falconctl << 'EOF'
#!/bin/bash
echo "CrowdStrike Falcon Sensor Control"
echo "Version: 7.10.0"
echo "exclusions: /usr/sap,/hana/shared,/hana/data"
EOF
chmod +x test-data/opt/CrowdStrike/falconctl
create_fixture "test-antivirus"

# 9a. Test for Illumio detection
echo ""
echo "=== Creating test-illumio.tar.xz ==="
mkdir -p test-data/sos_commands/systemd
cat > test-data/sos_commands/systemd/systemctl_list-units_--all << 'EOF'
  proc-sys-fs-binfmt_misc.automount                                                                                                                          loaded    active   waiting   Arbitrary Executable File Formats File System Automount Point
  sys-devices-pci0000:00-0000:00:03.0-virtio0-net-eth0.device                                                                                               loaded    active   plugged   Virtio network device
  sys-devices-platform-serial8250-tty-ttyS0.device                                                                                                           loaded    active   plugged   /sys/devices/platform/serial8250/tty/ttyS0
  -.mount                                                                                                                                                    loaded    active   mounted   Root Mount
  boot-efi.mount                                                                                                                                             loaded    active   mounted   /boot/efi
  illumio-ven.service                                                                                                                                        loaded    active   exited    Illumio VEN Agent top level startup
  venAgentMgr.service                                                                                                                                        loaded    active   running   Illumio Agent Manager
  venAgentMonitor.service                                                                                                                                    loaded    active   running   Illumio Agent Monitor
  venPlatformHandler.service                                                                                                                                 loaded    active   running   Illumio Platform Handler
  basic.target                                                                                                                                               loaded    active   active    Basic System
  cryptsetup.target                                                                                                                                          loaded    active   active    Local Encrypted Volumes
  getty.target                                                                                                                                               loaded    active   active    Login Prompts
EOF
mkdir -p test-data/usr/sap
mkdir -p test-data/hana/shared
create_fixture "test-illumio"

# 9b. Test for Trend Micro Deep Security detection
echo ""
echo "=== Creating test-trendmicro.tar.xz ==="
mkdir -p test-data/sos_commands/systemd
cat > test-data/sos_commands/systemd/systemctl_list-units_--all << 'EOF'
  proc-sys-fs-binfmt_misc.automount                                                                                                                          loaded    active   waiting   Arbitrary Executable File Formats File System Automount Point
  sys-devices-pci0000:00-0000:00:03.0-virtio0-net-eth0.device                                                                                               loaded    active   plugged   Virtio network device
  sys-devices-platform-serial8250-tty-ttyS0.device                                                                                                           loaded    active   plugged   /sys/devices/platform/serial8250/tty/ttyS0
  -.mount                                                                                                                                                    loaded    active   mounted   Root Mount
  boot-efi.mount                                                                                                                                             loaded    active   mounted   /boot/efi
  ds_agent.service                                                                                                                                           loaded    active     running         Trend Micro Deep Security Agent
  basic.target                                                                                                                                               loaded    active   active    Basic System
  cryptsetup.target                                                                                                                                          loaded    active   active    Local Encrypted Volumes
  getty.target                                                                                                                                               loaded    active   active    Login Prompts
EOF
mkdir -p test-data/usr/sap
mkdir -p test-data/hana/shared
create_fixture "test-trendmicro"

# 9c. Test for DLM service detection
echo ""
echo "=== Creating test-dlm-service.tar.xz ==="
mkdir -p test-data/sos_commands/systemd
cat > test-data/sos_commands/systemd/systemctl_list-unit-files << 'EOF'
UNIT FILE                                     STATE
accounts-daemon.service                       enabled
acpid.service                                 disabled
alsa-restore.service                          static
alsa-state.service                            static
apparmor.service                              enabled
auditd.service                                enabled
autovt@.service                               enabled
blk-availability.service                      disabled
cgroup-init.service                           enabled
chronyd.service                               enabled
cloud-config.service                          enabled
cloud-final.service                           enabled
cloud-init-local.service                      enabled
cloud-init.service                            enabled
dlm.service                                   enabled
getty@.service                                enabled
grub2-once.service                            static
haveged.service                               enabled
EOF
mkdir -p test-data/etc
cat > test-data/etc/os-release << 'EOF'
NAME="Red Hat Enterprise Linux"
VERSION="8.6 (Ootpa)"
ID="rhel"
VERSION_ID="8.6"
PRETTY_NAME="Red Hat Enterprise Linux 8.6 (Ootpa)"
EOF
create_fixture "test-dlm-service"

# 10. Test for live migration events
echo ""
echo "=== Creating test-live-migration.tar.xz ==="
mkdir -p test-data
cat > test-data/messages << 'EOF'
2025-11-13T12:15:30.000000+01:00 node1 kernel: hv_vmbus: Vmbus version:4.0
2025-11-13T12:15:35.000000+01:00 node1 kernel: hv_utils: Heartbeat IC version 3.0
2025-11-13T12:15:36.000000+01:00 node1 kernel: hv_balloon: Using dynamic memory protocol version 2.0
2025-11-13T12:15:37.000000+01:00 node1 kernel: hv_netvsc: ring size: 2MB
2025-11-13T13:45:10.000000+01:00 node1 kernel: hv_utils: Heartbeat IC version 3.0
2025-11-13T13:45:11.000000+01:00 node1 kernel: hv_balloon: Max. dynamic memory size: 4096 MB
2025-11-13T13:45:12.000000+01:00 node1 kernel: hv_netvsc: opened device VF
EOF
create_fixture "test-live-migration"

################################################################################
# Test 8: Kernel Tuning Analysis
# Tests kernel parameter validation with both correct and incorrect values
################################################################################
echo ""
echo "=== Creating test-kernel-tuning.tar.xz ==="
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
debug.exception-trace = 1
debug.kprobes-optimization = 1
dev.cdrom.autoclose = 1
dev.cdrom.autoeject = 0
dev.cdrom.check_media = 0
dev.cdrom.debug = 0
dev.cdrom.info = CD-ROM information, Id: cdrom.c 3.20 2003/12/17
dev.cdrom.info = 
dev.cdrom.info = drive name:		
dev.cdrom.info = drive speed:		
dev.cdrom.info = drive # of slots:	
dev.cdrom.info = Can close tray:		
dev.cdrom.lock = 1
fs.aio-max-nr = 1048576
fs.aio-nr = 0
fs.file-max = 9223372036854775807
fs.file-nr = 1408	0	9223372036854775807
fs.inode-nr = 48652	354
fs.inode-state = 48652	354	0	0	0	0	0
fs.leases-enable = 1
fs.nr_open = 1048576
kernel.acct = 4	2	30
kernel.auto_msgmni = 0
kernel.cap_last_cap = 37
kernel.core_pattern = core
kernel.core_pipe_limit = 0
kernel.core_uses_pid = 0
kernel.dmesg_restrict = 0
kernel.hostname = test-host
kernel.msgmax = 8192
kernel.msgmnb = 16384
kernel.msgmni = 32000
kernel.osrelease = 4.18.0-425.3.1.el8.x86_64
kernel.ostype = Linux
kernel.panic = 0
kernel.panic_on_oops = 1
kernel.pid_max = 4194304
kernel.randomize_va_space = 2
kernel.real-root-dev = 0
kernel.sem = 32000	1024000000	500	32000
kernel.shmall = 1152921504606846720
kernel.shmmax = 18446744073692774399
kernel.shmmni = 4096
kernel.threads-max = 4127428
kernel.version = #1 SMP Thu Nov 10 15:21:08 UTC 2022
net.core.netdev_max_backlog = 5000
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.somaxconn = 4096
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
net.ipv4.ip_local_port_range = 40000	61000
net.ipv4.tcp_fin_timeout = 60
net.ipv4.tcp_keepalive_intvl = 75
net.ipv4.tcp_keepalive_probes = 9
net.ipv4.tcp_keepalive_time = 7200
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_rmem = 4096	87380	6291456
net.ipv4.tcp_slow_start_after_idle = 1
net.ipv4.tcp_syn_retries = 6
net.ipv4.tcp_synack_retries = 5
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 2
net.ipv4.tcp_wmem = 4096	16384	4194304
sunrpc.tcp_slot_table_entries = 65536
sunrpc.udp_slot_table_entries = 65536
user.max_user_namespaces = 15076
vm.admin_reserve_kbytes = 8192
vm.dirty_background_bytes = 314572800
vm.dirty_background_ratio = 10
vm.dirty_bytes = 629145600
vm.dirty_expire_centisecs = 3000
vm.dirty_ratio = 20
vm.dirty_writeback_centisecs = 500
vm.max_map_count = 2147483647
vm.min_free_kbytes = 4096000
vm.nr_hugepages = 0
vm.overcommit_memory = 0
vm.overcommit_ratio = 50
vm.swappiness = 10
vm.vfs_cache_pressure = 100
EOF
create_fixture "test-kernel-tuning"

################################################################################
# Test 9: Kernel Tuning with Incorrect Values
# Tests warning generation for non-optimal kernel parameters
################################################################################
echo ""
echo "=== Creating test-kernel-tuning-warnings.tar.xz ==="
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
debug.exception-trace = 1
fs.file-max = 9223372036854775807
kernel.hostname = test-host
kernel.osrelease = 4.18.0-425.3.1.el8.x86_64
kernel.ostype = Linux
kernel.pid_max = 4194304
kernel.sem = 32000	1024000000	500	32000
kernel.shmall = 1152921504606846720
kernel.shmmax = 18446744073692774399
kernel.shmmni = 4096
net.core.rmem_max = 4194304
net.core.wmem_max = 1048576
net.ipv4.ip_local_port_range = 40000	61000
net.ipv4.tcp_rmem = 4096	87380	6291456
net.ipv4.tcp_wmem = 4096	16384	4194304
vm.admin_reserve_kbytes = 8192
vm.dirty_background_bytes = 100000000
vm.dirty_background_ratio = 10
vm.dirty_bytes = 200000000
vm.dirty_expire_centisecs = 3000
vm.dirty_ratio = 20
vm.dirty_writeback_centisecs = 500
vm.max_map_count = 2147483647
vm.min_free_kbytes = 4096000
vm.swappiness = 60
EOF

create_fixture "test-kernel-tuning-warnings"

################################################################################
# Test 19: fstab Display
# Tests detection and display of /etc/fstab file
################################################################################
echo ""
echo "=== Creating test-fstab.tar.xz ==="
mkdir -p test-data/etc
cat > test-data/etc/fstab << 'EOF'
#
# /etc/fstab
# Created by anaconda on Wed Oct 12 14:23:45 2022
#
# Accessible filesystems, by reference, are maintained under '/dev/disk/'.
# See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info.
#
# After editing this file, run 'systemctl daemon-reload' to update systemd
# units generated from this file.
#
UUID=12345678-1234-1234-1234-123456789abc /                       xfs     defaults        0 0
UUID=87654321-4321-4321-4321-cba987654321 /boot                   xfs     defaults        0 0
UUID=abcdef12-3456-7890-abcd-ef1234567890 /data                   xfs     defaults,noatime 0 0
/dev/mapper/vg_data-lv_backup             /backup                 ext4    defaults        1 2
tmpfs                                     /dev/shm                tmpfs   defaults        0 0
EOF

create_fixture "test-fstab"

################################################################################
# Test 20: Corrupted/Truncated Archive
# Tests handling of corrupted tar.xz files (truncated at end)
################################################################################
echo ""
echo "=== Creating test-corrupted.tar.xz ==="
mkdir -p test-data/etc
cat > test-data/etc/hostname << 'EOF'
test-corrupted-host
EOF

mkdir -p test-data/var/log
cat > test-data/var/log/messages << 'EOF'
Nov 28 10:00:01 test-host kernel: Linux version 5.14.0
Nov 28 10:00:02 test-host systemd[1]: Started Session 1 of user root.
Nov 28 10:00:03 test-host sshd[1234]: Accepted publickey for root
EOF

# Create the archive normally first
create_fixture "test-corrupted"

# Now truncate it by removing some blocks from the end
# Remove last 200 bytes to simulate corruption
CORRUPTED_FILE="$FIXTURES_DIR/scc_test-corrupted.tar.xz"
if [ -f "$CORRUPTED_FILE" ]; then
    FILE_SIZE=$(stat -f%z "$CORRUPTED_FILE" 2>/dev/null || stat -c%s "$CORRUPTED_FILE" 2>/dev/null)
    # Truncate to 60% of original size to ensure corruption in compressed data
    TRUNCATE_SIZE=$((FILE_SIZE * 60 / 100))
    
    # Only truncate if file is large enough
    if [ $FILE_SIZE -gt 200 ]; then
        echo "  Truncating from $FILE_SIZE to $TRUNCATE_SIZE bytes (60%) to simulate corruption..."
        dd if="$CORRUPTED_FILE" of="${CORRUPTED_FILE}.tmp" bs=1 count=$TRUNCATE_SIZE 2>/dev/null
        mv "${CORRUPTED_FILE}.tmp" "$CORRUPTED_FILE"
        echo "✓ Created corrupted test fixture"
    else
        echo "  File too small to truncate, creating larger test data..."
        # Add more content to make file larger
        mkdir -p test-data/usr/share/doc
        for i in {1..20}; do
            cat > test-data/usr/share/doc/file$i.txt << EOF
This is test file number $i
It contains some dummy data to make the archive larger
So we can properly test corruption handling
Line 4
Line 5
EOF
        done
        # Recreate with more data
        create_fixture "test-corrupted"
        FILE_SIZE=$(stat -f%z "$CORRUPTED_FILE" 2>/dev/null || stat -c%s "$CORRUPTED_FILE" 2>/dev/null)
        # Truncate to 60% of original size to ensure corruption in compressed data
        TRUNCATE_SIZE=$((FILE_SIZE * 60 / 100))
        echo "  Truncating from $FILE_SIZE to $TRUNCATE_SIZE bytes (60%) to simulate corruption..."
        dd if="$CORRUPTED_FILE" of="${CORRUPTED_FILE}.tmp" bs=1 count=$TRUNCATE_SIZE 2>/dev/null
        mv "${CORRUPTED_FILE}.tmp" "$CORRUPTED_FILE"
        echo "✓ Created corrupted test fixture"
    fi
fi

################################################################################
# Test for XFS errors with timestamp normalization and deduplication
################################################################################
echo ""
echo "=== Creating test-xfs-errors.tar.xz ==="
mkdir -p test-data
cat > test-data/messages << 'EOF'
Dec  2 15:07:09 testhost kernel: XFS (sda1): Metadata I/O Error: block 0x12345 ("xfs_trans_read_buf_map") error 5 numblks 8
Dec  2 15:07:10 testhost kernel: XFS (sda1): xfs_do_force_shutdown(0x1) called from line 1234 of file fs/xfs/xfs_buf.c. Return address = 0xffffffffc0123456
Dec  2 15:07:11 testhost kernel: XFS (sdb2): Internal error xfs_trans_cancel at line 987 of file fs/xfs/xfs_trans.c. Caller xfs_create+0x456/0x789
Dec  3 08:45:23 testhost kernel: XFS (sdc3): Corruption detected. Unmount and run xfs_repair
Dec  3 08:45:24 testhost kernel: XFS (sdc3): corrupt dinode 123456, extent total = 1, nblocks = 10
EOF

# Create rotated log with duplicate entries (different day format to test normalization)
cat > test-data/messages-1 << 'EOF'
Dec 02 15:07:09 testhost kernel: XFS (sda1): Metadata I/O Error: block 0x12345 ("xfs_trans_read_buf_map") error 5 numblks 8
Dec 02 15:07:10 testhost kernel: XFS (sda1): xfs_do_force_shutdown(0x1) called from line 1234 of file fs/xfs/xfs_buf.c. Return address = 0xffffffffc0123456
Dec 01 12:30:45 testhost kernel: XFS (sdd4): log I/O error -5
EOF

# Create another rotated log
cat > test-data/messages-2 << 'EOF'
Nov 30 18:22:11 testhost kernel: XFS (sde5): metadata I/O error in "xfs_btree_read_buf_block" at daddr 0xabcdef
EOF

create_fixture "test-xfs-errors"

################################################################################
# Test for XFS errors with single-digit vs zero-padded days
################################################################################
echo ""
echo "=== Creating test-xfs-timestamp-normalization.tar.xz ==="
mkdir -p test-data
cat > test-data/messages << 'EOF'
Dec  5 10:15:30 node1 kernel: XFS (nvme0n1p1): Corruption warning: inode 456789
Dec  5 10:15:31 node1 kernel: XFS (nvme0n1p1): Internal error XFS_WANT_CORRUPTED_GOTO at line 2345
EOF

cat > test-data/messages-1 << 'EOF'
Dec 05 10:15:30 node1 kernel: XFS (nvme0n1p1): Corruption warning: inode 456789
Dec 05 10:15:31 node1 kernel: XFS (nvme0n1p1): Internal error XFS_WANT_CORRUPTED_GOTO at line 2345
EOF

create_fixture "test-xfs-timestamp-normalization"

################################################################################
# Test for XFS duplicate UUID errors
################################################################################
echo ""
echo "=== Creating test-xfs-duplicate-uuid.tar.xz ==="
mkdir -p test-data
cat > test-data/messages << 'EOF'
Dec  3 17:37:06 vmcdfaccdrmigoradbqa01 kernel: XFS (sde1): Filesystem has duplicate UUID ac560ede-78b1-4d66-b199-2c1284ad1aaf - can't mount
Dec  3 17:37:07 vmcdfaccdrmigoradbqa01 kernel: XFS (sdf1): Filesystem has duplicate UUID f1234567-89ab-cdef-0123-456789abcdef - can't mount
EOF

create_fixture "test-xfs-duplicate-uuid"

################################################################################
# Test: Azure Network Tuning - Correctly Configured
# Tests detection of properly configured Azure Network optimization parameters
################################################################################
echo ""
echo "=== Creating test-azure-network-tuned.tar.xz ==="
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
kernel.hostname = test-host
kernel.osrelease = 5.14.0-362.8.1.el9_3.x86_64
kernel.ostype = Linux
net.core.busy_poll = 50
net.core.busy_read = 50
net.core.rmem_default = 33554432
net.core.rmem_max = 134217728
net.core.wmem_default = 33554432
net.core.wmem_max = 134217728
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mem = 4096	87380	67108864
net.ipv4.tcp_rmem = 4096	87380	67108864
net.ipv4.tcp_wmem = 4096	65536	67108864
net.ipv4.udp_mem = 4096	87380	33554432
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
vm.swappiness = 60
EOF

create_fixture "test-azure-network-tuned"

################################################################################
# Test: Azure Network Tuning - Needs Adjustment
# Tests detection of Azure Network parameters that need adjustment
################################################################################
echo ""
echo "=== Creating test-azure-network-warnings.tar.xz ==="
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
kernel.hostname = test-host
kernel.osrelease = 5.14.0-362.8.1.el9_3.x86_64
kernel.ostype = Linux
net.core.busy_poll = 0
net.core.busy_read = 0
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
net.ipv4.tcp_congestion_control = cubic
net.ipv4.tcp_mem = 4096	87380	4194304
net.ipv4.tcp_rmem = 4096	87380	6291456
net.ipv4.tcp_wmem = 4096	16384	4194304
net.ipv4.udp_mem = 4096	87380	4194304
net.ipv4.udp_rmem_min = 4096
net.ipv4.udp_wmem_min = 4096
vm.swappiness = 60
EOF

create_fixture "test-azure-network-warnings"

################################################################################
# Test: Optional Network Tuning - Mixed Configuration
# Tests detection of optional network parameters with mixed values
################################################################################
echo ""
echo "=== Creating test-optional-network-tuning.tar.xz ==="
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
kernel.hostname = test-host
kernel.osrelease = 5.14.0-362.8.1.el9_3.x86_64
kernel.ostype = Linux
net.core.default_qdisc = fq
net.core.dev_weight = 64
net.core.netdev_budget = 1000
net.core.netdev_max_backlog = 32768
net.core.optmem_max = 65535
net.core.somaxconn = 32768
net.ipv4.ip_local_port_range = 1024	65535
net.ipv4.tcp_frto = 0
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_tw_reuse = 1
vm.swappiness = 60
EOF

create_fixture "test-optional-network-tuning"

################################################################################
# Test: Complete Network Tuning - All Parameters
# Tests detection of all Azure and optional network parameters configured correctly
################################################################################
echo ""
echo "=== Creating test-complete-network-tuning.tar.xz ==="
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
kernel.hostname = test-host
kernel.osrelease = 5.14.0-362.8.1.el9_3.x86_64
kernel.ostype = Linux
net.core.busy_poll = 50
net.core.busy_read = 50
net.core.default_qdisc = fq
net.core.dev_weight = 64
net.core.netdev_budget = 1000
net.core.netdev_max_backlog = 32768
net.core.optmem_max = 65535
net.core.rmem_default = 33554432
net.core.rmem_max = 134217728
net.core.somaxconn = 32768
net.core.wmem_default = 33554432
net.core.wmem_max = 134217728
net.ipv4.ip_local_port_range = 1024	65535
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mem = 4096	87380	67108864
net.ipv4.tcp_rmem = 4096	87380	67108864
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_wmem = 4096	65536	67108864
net.ipv4.udp_mem = 4096	87380	33554432
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
vm.swappiness = 60
EOF

create_fixture "test-complete-network-tuning"

# Test for raw RPM package list display
echo ""
echo "=== Creating sosreport-rpm-raw.tar.xz ==="
mkdir -p sosreport-rpm-raw/sos_commands/dnf
cat > sosreport-rpm-raw/sos_commands/dnf/dnf_list_installed << 'EOF'
Updating Subscription Management repositories.
Unable to read consumer identity
Installed Packages
GConf2.x86_64                          3.2.6-22.el8                           @rhel-8-for-x86_64-appstream-rpms
LibRaw.x86_64                          0.19.5-3.el8                           @rhui-rhel-8-for-x86_64-appstream-rhui-rpms
ModemManager-glib.x86_64               1.10.8-4.el8                           @rhel-8-for-x86_64-baseos-rpms
NetworkManager.x86_64                  1:1.40.16-4.el8_9                      @rhui-rhel-8-for-x86_64-baseos-rhui-rpms
NetworkManager-libnm.x86_64            1:1.40.16-4.el8_9                      @rhui-rhel-8-for-x86_64-baseos-rhui-rpms
PackageKit.x86_64                      1.1.12-6.el8                           @rhel-8-for-x86_64-appstream-rpms
PackageKit-glib.x86_64                 1.1.12-6.el8                           @rhel-8-for-x86_64-appstream-rpms
acl.x86_64                             2.2.53-1.el8                           @rhel-8-for-x86_64-baseos-rpms
bash.x86_64                            4.4.20-4.el8_6                         @rhui-rhel-8-for-x86_64-baseos-rhui-rpms
bash-completion.noarch                 1:2.7-5.el8                            @rhel-8-for-x86_64-baseos-rpms
bind-export-libs.x86_64                32:9.11.36-8.el8_8.2                   @rhui-rhel-8-for-x86_64-baseos-rhui-rpms
binutils.x86_64                        2.30-119.el8                           @rhui-rhel-8-for-x86_64-baseos-rhui-rpms
bzip2.x86_64                           1.0.6-26.el8                           @rhel-8-for-x86_64-baseos-rpms
ca-certificates.noarch                 2023.2.60_v7.0.306-80.0.el8_8          @rhui-rhel-8-for-x86_64-baseos-rhui-rpms
EOF
tar -cJf "$FIXTURES_DIR/sosreport-rpm-raw.tar.xz" sosreport-rpm-raw
rm -rf sosreport-rpm-raw
echo "✓ Created sosreport-rpm-raw (14 packages)"

# Test for raw YUM package list display (RHEL 7 style)
echo ""
echo "=== Creating sosreport-yum-raw.tar.xz ==="
mkdir -p sosreport-yum-raw/sos_commands/yum
cat > sosreport-yum-raw/sos_commands/yum/yum_list_installed << 'EOF'
Loaded plugins: langpacks, product-id, search-disabled-repos, subscription-
              : manager
Repository packages-microsoft-com-prod is listed more than once in the configuration
Installed Packages
BladeLogic_RSCD_Agent.x86_64        24.4.01-59               installed          
GConf2.x86_64                       3.2.6-8.el7              @DVD               
GeoIP.x86_64                        1.5.0-14.el7             @DVD               
ModemManager.x86_64                 1.6.10-4.el7             @DVD               
NetworkManager.x86_64               1:1.18.8-2.el7_9         @repo/$releasever  
NetworkManager-glib.x86_64          1:1.18.8-2.el7_9         @repo/$releasever  
PackageKit.x86_64                   1.1.10-2.el7             @DVD               
PackageKit-glib.x86_64              1.1.10-2.el7             @DVD               
PyYAML.x86_64                       3.10-11.el7              @DVD               
acl.x86_64                          2.2.51-15.el7            @DVD               
bash.x86_64                         4.2.46-35.el7_9          @repo/$releasever  
bind-export-libs.x86_64             32:9.11.4-26.P2.el7_9.15 @repo/$releasever  
binutils.x86_64                     2.27-44.base.el7_9.1     @repo/$releasever  
bzip2.x86_64                        1.0.6-13.el7             @DVD               
ca-certificates.noarch              2022.2.54-74.el7_9       @repo/$releasever  
EOF
tar -cJf "$FIXTURES_DIR/sosreport-yum-raw.tar.xz" sosreport-yum-raw
rm -rf sosreport-yum-raw
echo "✓ Created sosreport-yum-raw (15 packages)"

# Test for raw DEB package list display
echo ""
echo "=== Creating sosreport-deb-raw.tar.xz ==="
mkdir -p sosreport-deb-raw/sos_commands/dpkg
cat > sosreport-deb-raw/sos_commands/dpkg/dpkg_-l << 'EOF'
Desired=Unknown/Install/Remove/Purge/Hold
| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend
|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)
||/ Name                          Version                      Architecture Description
+++-=============================-============================-============-===============================================================================
ii  accountsservice               0.6.55-0ubuntu12~20.04.7     amd64        query and manipulate user account information
ii  acl                           2.2.53-6                     amd64        access control list - utilities
ii  adduser                       3.118ubuntu2                 all          add and remove users and groups
ii  apparmor                      2.13.3-7ubuntu5.3            amd64        user-space parser utility for AppArmor
ii  apt                           2.0.10                       amd64        commandline package manager
ii  apt-utils                     2.0.10                       amd64        package management related utility programs
ii  base-files                    11ubuntu5.8                  amd64        Debian base system miscellaneous files
ii  base-passwd                   3.5.47                       amd64        Debian base system master password and group files
ii  bash                          5.0-6ubuntu1.2               amd64        GNU Bourne Again SHell
ii  bash-completion               1:2.10-1ubuntu1              all          programmable completion for the bash shell
ii  bind9-dnsutils                1:9.16.1-0ubuntu2.16         amd64        Clients provided with BIND 9
ii  bsdutils                      1:2.34-0.1ubuntu9.6          amd64        basic utilities from 4.4BSD-Lite
ii  busybox-initramfs             1:1.30.1-4ubuntu6.5          amd64        Standalone shell setup for initramfs
ii  bzip2                         1.0.8-2                      amd64        high-quality block-sorting file compressor - utilities
ii  ca-certificates               20230311ubuntu0.20.04.1      all          Common CA certificates
ii  cloud-init                    24.1.3-0ubuntu1~20.04.4      all          Init scripts for cloud instances
ii  coreutils                     8.30-3ubuntu2                amd64        GNU core utilities
ii  cpio                          2.13+dfsg-2ubuntu0.4         amd64        GNU cpio -- a program to manage archives of files
ii  cron                          3.0pl1-136ubuntu1            amd64        process scheduling daemon
ii  curl                          7.68.0-1ubuntu2.22           amd64        command line tool for transferring data with URL syntax
ii  dbus                          1.12.16-2ubuntu2.3           amd64        simple interprocess messaging system (daemon and utilities)
ii  systemd                       245.4-4ubuntu3.23            amd64        system and service manager
EOF
tar -cJf "$FIXTURES_DIR/sosreport-deb-raw.tar.xz" sosreport-deb-raw
rm -rf sosreport-deb-raw
echo "✓ Created sosreport-deb-raw (22 packages)"

# Test for Azure VM with Ultra Disk and Premium SSD v2
echo ""
echo "=== Creating test-azure-vm-storage.tar.xz ==="
mkdir -p test-data
cat > test-data/instance_metadata.json << 'EOF'
{
  "compute": {
    "vmSize": "Standard_E32s_v3",
    "publisher": "SUSE",
    "offer": "sles-sap-15-sp5",
    "sku": "gen2",
    "licenseType": "SLES",
    "storageProfile": {
      "osDisk": {
        "name": "osdisk",
        "managedDisk": {
          "storageAccountType": "Premium_LRS"
        }
      },
      "dataDisks": [
        {
          "lun": 0,
          "name": "hana-data",
          "diskSizeGB": 512,
          "managedDisk": {
            "storageAccountType": "UltraSSD_LRS"
          }
        },
        {
          "lun": 1,
          "name": "hana-log",
          "diskSizeGB": 256,
          "managedDisk": {
            "storageAccountType": "PremiumV2_LRS"
          }
        },
        {
          "lun": 2,
          "name": "hana-shared",
          "diskSizeGB": 1024,
          "managedDisk": {
            "storageAccountType": "Premium_LRS"
          }
        }
      ]
    }
  }
}
EOF
create_fixture "test-azure-vm-storage"

################################################################################
# Test: Azure Site Recovery (involflt) detection
################################################################################
echo ""
echo "=== Creating test-asr.tar.xz ==="
mkdir -p test-data

# Create systemd-status.txt with involflt_start service
cat > test-data/systemd-status.txt << 'EOF'
#==[ Command ]======================================#
# /bin/systemctl status --all
● involflt_start.service - InMage Filter Driver Start Service
   Loaded: loaded (/etc/systemd/system/involflt_start.service; enabled; vendor preset: disabled)
   Active: active (exited) since Sun 2025-10-12 05:15:04 UTC; 3 months ago
  Process: 497 ExecStart=/sbin/involflt_init.sh start (code=exited, status=0/SUCCESS)
 Main PID: 497 (code=exited, status=0/SUCCESS)
    Tasks: 0
   Memory: 0B
   CGroup: /system.slice/involflt_start.service

Oct 12 05:15:02 p1laasspcr005 systemd[1]: Starting InMage Filter Driver Start Service...
Oct 12 05:15:04 p1laasspcr005 systemd[1]: Started InMage Filter Driver Start Service.

● systemd-journald.service - Journal Service
   Loaded: loaded (/usr/lib/systemd/system/systemd-journald.service; static; vendor preset: disabled)
   Active: active (running) since Sun 2025-10-12 05:15:02 UTC; 3 months ago
     Docs: man:systemd-journald.service(8)
           man:journald.conf(5)
 Main PID: 265 (systemd-journal)
   Status: "Processing requests..."
    Tasks: 1
   Memory: 43.8M
   CGroup: /system.slice/systemd-journald.service
           └─265 /usr/lib/systemd/systemd-journald
EOF

# Create modules.txt with involflt module information
cat > test-data/modules.txt << 'EOF'
#==[ Command ]======================================#
# /sbin/lsmod
Module                  Size  Used by
involflt              897024  14
xt_CHECKSUM            16384  1
ipt_MASQUERADE         16384  3
xt_conntrack           16384  1
ipt_REJECT             16384  2
nf_reject_ipv4         16384  1 ipt_REJECT

#==[ Command ]======================================#
# /sbin/modinfo involflt
filename:       /lib/modules/5.14.21-150400.24.173-default/kernel/drivers/char/involflt.ko
version:        Oct 23 2024 [ 02:41:25 ]
license:        GPL v2
description:    Microsoft Filter Driver
author:         Microsoft Corporation
srcversion:     E4F8D9C3A1B2F0E5A6D7C89
alias:          char-major-10-237
depends:        
retpoline:      Y
name:           involflt
vermagic:       5.14.21-150400.24.173-default SMP mod_unload modversions 

#==[ Command ]======================================#
# /sbin/modprobe -c
EOF

# Create messages.txt with involflt kernel log version
cat > test-data/messages-20251013.txt << 'EOF'
Oct 12 05:15:01 p1laasspcr005 kernel: Linux version 5.14.21-150400.24.173-default (geeko@buildhost) (gcc (SUSE Linux) 7.5.0, GNU ld (GNU Binutils; SUSE Linux Enterprise 15) 2.37) #1 SMP PREEMPT_DYNAMIC Tue Aug 13 09:20:16 UTC 2024 (c6c0d6b)
Oct 12 05:15:02 p1laasspcr005 kernel: Command line: BOOT_IMAGE=/boot/vmlinuz-5.14.21-150400.24.173-default root=UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300
Oct 12 05:15:02 p1laasspcr005 kernel: involflt: loading out-of-tree module taints kernel.
Oct 12 05:15:02 p1laasspcr005 kernel: involflt: module verification failed: signature and/or required key missing - tainting kernel
Oct 12 05:15:02 p1laasspcr005 kernel: involflt[involflt_init:3458 (INFO)]: Version - 9.63.1.7235
Oct 12 05:15:02 p1laasspcr005 kernel: involflt[alloc_data_pages:687 (INFO)]: Data Mode Init: Allocated pages 16384 Page size 4096
Oct 12 05:15:02 p1laasspcr005 kernel: involflt[alloc_data_pages:687 (INFO)]: Data Mode Init: Allocated pages 2044160 Page size 4096
Oct 12 05:15:02 p1laasspcr005 kernel: involflt[init_work_queue:151 (INFO)]: worker thread with pid = 507  has created
Oct 12 05:15:02 p1laasspcr005 kernel: involflt[init_work_queue:151 (INFO)]: worker thread with pid = 508  has created
Oct 12 05:15:02 p1laasspcr005 kernel: involflt[create_service_thread:65 (INFO)]: kernel thread with pid = 509 has created
Oct 12 05:15:02 p1laasspcr005 kernel: involflt[create_alloc_thread:1859 (INFO)]: inmallocd thread with pid = 510 has created
Oct 12 05:15:02 p1laasspcr005 kernel: involflt[involflt_init:3527 (INFO)]: Mirror capability is not supported by involflt driver
Oct 12 05:15:02 p1laasspcr005 kernel: involflt[involflt_init:3548 (INFO)]: Successfully loaded involflt target module from initrd
Oct 12 05:15:04 p1laasspcr005 systemd[1]: Started InMage Filter Driver Start Service.
EOF

create_fixture "test-asr"

echo ""
echo "========================================="
echo "✓ All test fixtures created successfully!"
echo "========================================="
echo ""
echo "Fixtures created in: $FIXTURES_DIR"
echo ""
echo "To run tests:"
echo "  npm install"
echo "  npm test"
