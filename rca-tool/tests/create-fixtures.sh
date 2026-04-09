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
    echo "[OK] Created scc_$name"
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
# Test 18b: Huge Pages Configuration
# Tests detection and display of huge pages (static and transparent)
################################################################################
echo ""
echo "=== Creating test-huge-pages.tar.xz ==="

# Create proc/meminfo with huge pages information
mkdir -p test-data/proc
cat > test-data/proc/meminfo << 'EOF'
MemTotal:       131941632 kB
MemFree:        120345678 kB
MemAvailable:   125678901 kB
Buffers:          123456 kB
Cached:          5432109 kB
SwapCached:            0 kB
Active:          6543210 kB
Inactive:        2109876 kB
Active(anon):    1234567 kB
Inactive(anon):   234567 kB
Active(file):    5308643 kB
Inactive(file):  1875309 kB
Unevictable:           0 kB
Mlocked:               0 kB
SwapTotal:       8388604 kB
SwapFree:        8388604 kB
Dirty:              1234 kB
Writeback:             0 kB
AnonPages:       1234567 kB
Mapped:           345678 kB
Shmem:            234567 kB
KReclaimable:     456789 kB
Slab:             789012 kB
SReclaimable:     456789 kB
SUnreclaim:       332223 kB
KernelStack:       12345 kB
PageTables:        45678 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:    74359420 kB
Committed_AS:    3456789 kB
VmallocTotal:   34359738367 kB
VmallocUsed:       87654 kB
VmallocChunk:          0 kB
Percpu:            45678 kB
HardwareCorrupted:     0 kB
AnonHugePages:   2097152 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB
FileHugePages:         0 kB
FilePmdMapped:         0 kB
HugePages_Total:    2048
HugePages_Free:      512
HugePages_Rsvd:      128
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:         4194304 kB
DirectMap4k:      524288 kB
DirectMap2M:    10485760 kB
DirectMap1G:   123731968 kB
EOF

# Create sysctl output with huge pages parameters
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
debug.exception-trace = 1
fs.file-max = 9223372036854775807
kernel.hostname = test-huge-pages
kernel.osrelease = 5.14.0-284.11.1.el9_2.x86_64
kernel.ostype = Linux
kernel.pid_max = 4194304
kernel.sem = 32000	1024000000	500	32000
kernel.shmall = 1152921504606846720
kernel.shmmax = 18446744073692774399
kernel.shmmni = 4096
net.core.rmem_max = 4194304
net.core.wmem_max = 1048576
vm.admin_reserve_kbytes = 8192
vm.dirty_background_bytes = 314572800
vm.dirty_bytes = 629145600
vm.hugetlb_shm_group = 0
vm.max_map_count = 2147483647
vm.min_free_kbytes = 4096000
vm.nr_hugepages = 2048
vm.nr_overcommit_hugepages = 512
vm.swappiness = 10
EOF

# Create basic SAP indicator
mkdir -p test-data/usr/sap
touch test-data/usr/sap/sapservices

create_fixture "test-huge-pages"

################################################################################
# Test 18c: Huge Pages - No Configuration
# Tests detection when no huge pages are configured (should show recommendations for SAP)
################################################################################
echo ""
echo "=== Creating test-huge-pages-none.tar.xz ==="

mkdir -p test-data/proc
cat > test-data/proc/meminfo << 'EOF'
MemTotal:       65970816 kB
MemFree:        60123456 kB
MemAvailable:   62345678 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:               0 kB
AnonHugePages:         0 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB
EOF

mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
kernel.hostname = test-no-hugepages
kernel.osrelease = 5.14.0-284.11.1.el9_2.x86_64
vm.nr_hugepages = 0
vm.nr_overcommit_hugepages = 0
vm.swappiness = 10
EOF

# Create SAP indicator
mkdir -p test-data/usr/sap
touch test-data/usr/sap/sapservices

create_fixture "test-huge-pages-none"

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
        echo "[OK] Created corrupted test fixture"
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
        echo "[OK] Created corrupted test fixture"
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
Dec  4 12:33:07 testhost kernel: XFS (sdk4): Found unrecovered unlinked inode 0xb75 in AG 0x4.  Initiating recovery.
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
echo "[OK] Created sosreport-rpm-raw (14 packages)"

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
echo "[OK] Created sosreport-yum-raw (15 packages)"

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
echo "[OK] Created sosreport-deb-raw (22 packages)"

################################################################################
# RPM.txt (SUSE supportconfig format) – exercises rpm.txt parsing with
# section headers (# rpm -qa --queryformat) and section terminators
################################################################################
echo ""
echo "=== Creating sosreport-rpm-txt-scc.tar.xz ==="
mkdir -p sosreport-rpm-txt-scc
cat > sosreport-rpm-txt-scc/rpm.txt << 'RPMSCC'
#==[ Command ]======================================#
# rpm -qa --queryformat '%{NAME} - %{DISTRIBUTION} - %{VERSION}\n'
NAME                                   DISTRIBUTION                       VERSION
SUSE_SLE-15-SP5_Update                 (none)                             15.5
aaa_base                               SUSE Linux Enterprise 15           84.87+git20180409
bash                                   SUSE Linux Enterprise 15           4.4
glibc                                  SUSE Linux Enterprise 15           2.31
kernel-default                         SUSE Linux Enterprise 15           5.14.21
cloud-netconfig-azure                  SUSE Linux Enterprise 15           1.5
resource-agents                        SUSE Linux Enterprise 15           4.8.0
fence-agents                           SUSE Linux Enterprise 15           4.10.0
#==[ Command ]======================================#
# rpm -qa --queryformat '%{NAME} %{SIGPGP:pgpsig}\n'
some-other-section-data
RPMSCC
tar -cJf "$FIXTURES_DIR/sosreport-rpm-txt-scc.tar.xz" sosreport-rpm-txt-scc
rm -rf sosreport-rpm-txt-scc
echo "[OK] Created sosreport-rpm-txt-scc (7 packages)"

################################################################################
# installed-rpms (RHEL sosreport format) – exercises RPM version validation:
# version too old (fence-agents), problematic range (python3-azure-core),
# valid packages, and missing packages
################################################################################
echo ""
echo "=== Creating sosreport-installed-rpms.tar.xz ==="
mkdir -p sosreport-installed-rpms/sos_commands/rpm
cat > sosreport-installed-rpms/installed-rpms << 'RPMINST'
fence-agents-4.2.1-30.el8.x86_64
python3-azure-mgmt-compute-21.0.0-1.el8.noarch
python3-azure-identity-1.5.0-2.el8.noarch
python3-azure-core-1.15.0-1.el8.noarch
resource-agents-4.9.0-12.el8.x86_64
bash-4.4.20-4.el8.x86_64
glibc-2.28-236.el8.x86_64
kernel-4.18.0-553.89.1.el8_10.x86_64
RPMINST
# Include corosync.conf so the UI renders Azure package validation results
mkdir -p sosreport-installed-rpms/etc/corosync
cat > sosreport-installed-rpms/etc/corosync/corosync.conf << 'COROCONF'
totem {
    version: 2
    transport: udpu
}
nodelist {
    node {
        ring0_addr: 10.0.0.4
        name: node1
        nodeid: 1
    }
}
COROCONF
tar -cJf "$FIXTURES_DIR/sosreport-installed-rpms.tar.xz" sosreport-installed-rpms
rm -rf sosreport-installed-rpms
echo "[OK] Created sosreport-installed-rpms (8 packages)"

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

# Test for automation detection (Ansible)
echo ""
echo "=== Creating test-automation.tar.xz ==="
mkdir -p test-data
cat > test-data/messages.txt << 'EOF'
Dec 18 10:15:23 testhost kernel: Linux version 5.14.0-427.13.1.el9_4.x86_64 (mockbuild@x86-64-01.build.eng.rdu2.redhat.com)
Dec 18 10:20:45 testhost ansible-command: Invoked with creates=None executable=None chdir=/tmp warn=True stdin_add_newline=True strip_empty_ends=True argv=None removes=None
Dec 18 10:20:46 testhost ansible-command: /usr/bin/python3 /tmp/ansible-playbook-test.py
Dec 18 10:25:30 testhost systemd[1]: Started Session 123 of user root.
Dec 18 10:30:15 testhost ansible-command: Running command: yum install -y httpd
Dec 18 10:35:22 testhost ansible-command: Invoked with name=httpd state=started enabled=yes
Dec 18 10:40:10 testhost ansible-command: Invoked with path=/etc/httpd/conf/httpd.conf regexp=^Listen line=Listen 8080
Dec 18 11:00:00 testhost systemd[1]: Stopping firewalld - dynamic firewall daemon...
EOF

create_fixture "test-automation"

################################################################################
# Test: Nested gzip decompression with multiple rotated cluster logs
################################################################################
echo ""
echo "=== Creating test-nested-gzip.tar.xz ==="
mkdir -p test-data/var/log/pacemaker
mkdir -p test-data/var/log/cluster

# Create pacemaker log files with cluster events and compress them
cat > test-data/var/log/pacemaker/pacemaker.log-20250101 << 'EOF'
Jan 01 10:15:30 node01 pacemaker-controld[12345] (do_state_transition) notice: State transition S_IDLE -> S_POLICY_ENGINE
Jan 01 10:15:31 node01 pacemaker-controld[12345] (do_lrm_rsc_op) notice: Operation testip_stop_0: ok (node=node01)
Jan 01 10:15:32 node01 pacemaker-controld[12345] (do_lrm_rsc_op) notice: Operation testip_start_0: ok (node=node02)
EOF
gzip test-data/var/log/pacemaker/pacemaker.log-20250101

cat > test-data/var/log/pacemaker/pacemaker.log-20250102 << 'EOF'
Jan 02 14:22:10 node02 pacemaker-controld[12346] (do_state_transition) notice: State transition S_IDLE -> S_POLICY_ENGINE
Jan 02 14:22:11 node02 pacemaker-controld[12346] (do_lrm_rsc_op) notice: Operation sapdb_stop_0: ok (node=node02)
Jan 02 14:22:12 node02 pacemaker-controld[12346] (do_lrm_rsc_op) notice: Operation sapdb_start_0: ok (node=node01)
EOF
gzip test-data/var/log/pacemaker/pacemaker.log-20250102

cat > test-data/var/log/pacemaker/pacemaker.log-20250103 << 'EOF'
Jan 03 08:45:20 node01 pacemaker-controld[12347] (do_state_transition) notice: State transition S_IDLE -> S_POLICY_ENGINE
Jan 03 08:45:21 node01 pacemaker-controld[12347] (do_lrm_rsc_op) notice: Operation filesystem_stop_0: ok (node=node01)
Jan 03 08:45:22 node01 pacemaker-controld[12347] (do_lrm_rsc_op) notice: Operation filesystem_start_0: ok (node=node02)
EOF
gzip test-data/var/log/pacemaker/pacemaker.log-20250103

# Create corosync log files with cluster events and compress them
cat > test-data/var/log/cluster/corosync.log-20250101 << 'EOF'
Jan 01 10:15:28 [QUORUM] Members[2]: 1 2
Jan 01 10:15:29 [TOTEM ] A processor joined or left the membership and a new membership was formed.
Jan 01 10:15:30 [CPG   ] Process 12345 joined group pacemaker
EOF
gzip test-data/var/log/cluster/corosync.log-20250101

cat > test-data/var/log/cluster/corosync.log-20250102 << 'EOF'
Jan 02 14:22:08 [QUORUM] Members[2]: 1 2
Jan 02 14:22:09 [TOTEM ] A processor joined or left the membership and a new membership was formed.
Jan 02 14:22:10 [CPG   ] Process 12346 joined group pacemaker
EOF
gzip test-data/var/log/cluster/corosync.log-20250102

# Create archive content statistics file
cat > test-data/archive-info.txt << 'EOF'
This archive contains 5 compressed log files (.gz):
- 3 pacemaker.log files
- 2 corosync.log files
All files should be decompressed and analyzed for cluster events.
EOF

create_fixture "test-nested-gzip"

# 31. Test for LVM configuration
echo ""
echo "=== Creating test-lvm.tar.xz ==="
mkdir -p test-data/lvm

cat > test-data/lvm/pvs.txt << 'EOF'
  PV         VG        Fmt  Attr PSize   PFree 
  /dev/sda2  rootvg    lvm2 a--  <19.00g 12.00g
  /dev/sdb1  datavg    lvm2 a--  100.00g 40.00g
  /dev/sdc1            lvm2 ---  50.00g  50.00g
EOF

cat > test-data/lvm/vgs.txt << 'EOF'
  VG     #PV #LV #SN Attr   VSize    VFree 
  rootvg   1   2   0 wz--n- <19.00g  12.00g
  datavg   1   3   0 wz--n- 100.00g  40.00g
  missingvg 2  1   0 wz-pn-  80.00g  10.00g
EOF

cat > test-data/lvm/lvs.txt << 'EOF'
  LV     VG     Attr       LSize  Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  root   rootvg -wi-ao---- 15.00g                                                    
  swap   rootvg -wi-ao----  2.00g                                                    
  app    datavg -wi-ao---- 20.00g                                                    
  data   datavg -wi-ao---- 30.00g                                                    
  backup datavg -wi-ao---- 10.00g                                                    
  db     missingvg -wi-a-----  70.00g
EOF

cat > test-data/lvm/pvdisplay.txt << 'EOF'
  --- Physical volume ---
  PV Name               /dev/sda2
  VG Name               rootvg
  PV Size               19.00 GiB / not usable 4.00 MiB
  Allocatable           yes 
  PE Size               4.00 MiB
  Total PE              4863
  Free PE               3072
  Allocated PE          1791
  
  --- Physical volume ---
  PV Name               /dev/sdb1
  VG Name               datavg
  PV Size               100.00 GiB
  Allocatable           yes 
  PE Size               4.00 MiB
  Total PE              25600
  Free PE               10240
  Allocated PE          15360
  
  "/dev/sdc1" is a new physical volume of "50.00 GiB"
  --- NEW Physical volume ---
  PV Name               /dev/sdc1
  VG Name               
  PV Size               50.00 GiB
  Allocatable           NO
  PE Size               0   
  Total PE              0
  Free PE               0
  Allocated PE          0
EOF

cat > test-data/lvm/vgdisplay.txt << 'EOF'
  --- Volume group ---
  VG Name               rootvg
  System ID             
  Format                lvm2
  Metadata Areas        1
  Metadata Sequence No  3
  VG Access             read/write
  VG Status             resizable
  MAX LV                0
  Cur LV                2
  Open LV               2
  Max PV                0
  Cur PV                1
  Act PV                1
  VG Size               <19.00 GiB
  PE Size               4.00 MiB
  Total PE              4863
  Alloc PE / Size       1791 / 7.00 GiB
  Free  PE / Size       3072 / 12.00 GiB
  
  --- Volume group ---
  VG Name               datavg
  System ID             
  Format                lvm2
  Metadata Areas        1
  Metadata Sequence No  4
  VG Access             read/write
  VG Status             resizable
  MAX LV                0
  Cur LV                3
  Open LV               3
  Max PV                0
  Cur PV                1
  Act PV                1
  VG Size               100.00 GiB
  PE Size               4.00 MiB
  Total PE              25600
  Alloc PE / Size       15360 / 60.00 GiB
  Free  PE / Size       10240 / 40.00 GiB
  
  --- Volume group ---
  VG Name               missingvg
  System ID             
  Format                lvm2
  Metadata Areas        2
  Metadata Sequence No  2
  VG Access             read/write
  VG Status             resizable/PARTIAL
  MAX LV                0
  Cur LV                1
  Open LV               1
  Max PV                0
  Cur PV                2
  Act PV                1
  VG Size               80.00 GiB
  PE Size               4.00 MiB
  Total PE              20480
  Alloc PE / Size       17920 / 70.00 GiB
  Free  PE / Size       2560 / 10.00 GiB
EOF

cat > test-data/lvm/lvdisplay.txt << 'EOF'
  --- Logical volume ---
  LV Path                /dev/rootvg/root
  LV Name                root
  VG Name                rootvg
  LV UUID                abc123-def4-5678-90ab-cdef12345678
  LV Write Access        read/write
  LV Creation host, time node01, 2024-01-15 10:30:00 +0000
  LV Status              available
  # open                 1
  LV Size                15.00 GiB
  Current LE             3840
  Segments               1
  Allocation             inherit
  Read ahead sectors     auto
  - currently set to     256
  Block device           253:0
  
  --- Logical volume ---
  LV Path                /dev/datavg/app
  LV Name                app
  VG Name                datavg
  LV UUID                def456-ghi7-8901-23ab-cdef45678901
  LV Write Access        read/write
  LV Creation host, time node01, 2024-02-20 14:15:00 +0000
  LV Status              available
  # open                 1
  LV Size                20.00 GiB
  Current LE             5120
  Segments               1
  Allocation             inherit
  Read ahead sectors     auto
  - currently set to     256
  Block device           253:1
EOF

create_fixture "test-lvm"

# 31b. Test for LVM configuration from sosreport (verbose pvs/vgs/lvs in sos_commands/lvm2/)
echo ""
echo "=== Creating test-lvm-sosreport.tar.xz ==="
mkdir -p test-data/sos_commands/lvm2

cat > "test-data/sos_commands/lvm2/pvs_-a_-v_-o_pv_mda_free_--config_global_locking_type_0" << 'EOF'
  Reloading config files
  WARNING: locking_type (0) is deprecated, using --nolocking.
  WARNING: File locking is disabled.
  PV         VG          Fmt  Attr PSize    PFree DevSize   PV UUID                            PMdaFree  PMdaSize  #PMda #PMdaUse 1st PE
  /dev/sda1                   ---        0     0    800.00m                                           0         0      0        0      0
  /dev/sda2  rootvg      lvm2 a--   <28.73g    0    <28.73g 4uu5BU-0TAy-rc94-icWO-qE9Q-nPgR-m0VmAc   507.50k  1020.00k     1        1   1.00m
  /dev/sda3  rootvg      lvm2 a--   <98.00g 4.00m    98.00g GFR5X8-rnj6-qUMi-ZIDS-cimp-thG1-ZlNN5L   507.50k  1020.00k     1        1   1.00m
  /dev/sdb1                   ---        0     0     <1.76t                                           0         0      0        0      0
  /dev/sdc1  vgoraclebip lvm2 a--   <64.00g    0    <64.00g VQZW3z-25sX-nZyU-q3f3-8AcZ-dCYz-Dp8fPr   508.00k  1020.00k     1        1   1.00m
  /dev/sdd1  vggridhome  lvm2 a--   <64.00g    0    <64.00g PUYyrj-DtbS-uChW-v6tH-aSZE-ezRh-MckD8g   508.00k  1020.00k     1        1   1.00m
EOF

cat > "test-data/sos_commands/lvm2/vgs_-v_-o_vg_mda_count_--config_global_locking_type_0" << 'EOF'
  Reloading config files
  WARNING: locking_type (0) is deprecated, using --nolocking.
  WARNING: File locking is disabled.
  VG          Attr   Ext   #PV #LV #SN VSize    VFree VG UUID                                VProfile #VMda VMdaFree  VMdaSize  #VMdaUse VG Tags
  rootvg      wz--n- 4.00m   2   2   0  126.72g 4.00m 67jA2p-1x3X-SqhR-1iY7-j9jS-h8XB-XNqtys              2   507.50k  1020.00k        2         
  vggridhome  wz--n- 4.00m   1   1   0  <64.00g    0  Al6ivs-izrr-zrw3-Yf6b-3a59-Trnt-yn3nRK              1   508.00k  1020.00k        1         
  vgoraclebip wz--n- 4.00m   1   1   0  <64.00g    0  rfoP9b-5Y4C-ZWBP-QsRM-B8dZ-4abx-u2hF7B              1   508.00k  1020.00k        1         
  Reloading config files
EOF

cat > "test-data/sos_commands/lvm2/lvs_-a_-o_lv_tags_devices_--config_global_locking_type_0" << 'EOF'
  WARNING: locking_type (0) is deprecated, using --nolocking.
  WARNING: File locking is disabled.
  LV          VG          Attr       LSize    Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert LV Tags Devices         KRahead Rahead #Str Stripe
  crashlv     rootvg      -wi-ao----   10.00g                                                             /dev/sda2(0)      4.00m   auto    1     0
  rootlv      rootvg      -wi-ao---- <116.72g                                                             /dev/sda3(0)      4.00m   auto    1     0
  lvgridhome  vggridhome  -wi-ao----  <64.00g                                                             /dev/sdd1(0)      4.00m   auto    1     0
  lvoraclebip vgoraclebip -wi-ao----  <64.00g                                                             /dev/sdc1(0)      4.00m   auto    1     0
EOF

create_fixture "test-lvm-sosreport"

# 32. Test for RAID configuration
echo ""
echo "=== Creating test-raid.tar.xz ==="
mkdir -p test-data/proc

cat > test-data/proc/mdstat.txt << 'EOF'
Personalities : [raid1] [raid5] [raid6] 
md0 : active raid1 sda1[0] sdb1[1]
      104320 blocks super 1.2 [2/2] [UU]
      
md1 : active raid5 sdc1[0] sdd1[1] sde1[2]
      209584128 blocks super 1.2 level 5, 512k chunk, algorithm 2 [3/3] [UUU]
      bitmap: 0/1 pages [0KB], 65536KB chunk

md2 : active (auto-read-only) raid1 sdf1[0] sdg1[1](F)
      52428800 blocks super 1.2 [2/1] [U_]
      [>....................]  recovery =  3.5% (1843200/52428800) finish=5.3min speed=157542K/sec
      
md3 : inactive sdi1[0](S) sdj1[2](S)
      209584128 blocks super 1.2
      
unused devices: <none>
EOF

mkdir -p test-data/mdadm
cat > test-data/mdadm/mdadm-detail-md0.txt << 'EOF'
/dev/md0:
           Version : 1.2
     Creation Time : Mon Jan 15 10:45:32 2024
        Raid Level : raid1
        Array Size : 104320 (101.89 MiB 106.82 MB)
     Used Dev Size : 104320 (101.89 MiB 106.82 MB)
      Raid Devices : 2
     Total Devices : 2
       Persistence : Superblock is persistent

       Update Time : Mon Mar 11 15:23:45 2024
             State : clean 
    Active Devices : 2
   Working Devices : 2
    Failed Devices : 0
     Spare Devices : 0

Consistency Policy : resync

              Name : node01:0
              UUID : 12345678:90abcdef:12345678:90abcdef
            Events : 125

    Number   Major   Minor   RaidDevice State
       0       8        1        0      active sync   /dev/sda1
       1       8       17        1      active sync   /dev/sdb1
EOF

cat > test-data/mdadm/mdadm-detail-md1.txt << 'EOF'
/dev/md1:
           Version : 1.2
     Creation Time : Mon Jan 15 11:00:00 2024
        Raid Level : raid5
        Array Size : 209584128 (199.87 GiB 214.61 GB)
     Used Dev Size : 104792064 (99.94 GiB 107.30 GB)
      Raid Devices : 3
     Total Devices : 3
       Persistence : Superblock is persistent

     Intent Bitmap : Internal

       Update Time : Mon Mar 11 15:30:12 2024
             State : clean 
    Active Devices : 3
   Working Devices : 3
    Failed Devices : 0
     Spare Devices : 0

            Layout : left-symmetric
        Chunk Size : 512K

Consistency Policy : bitmap

              Name : node01:1
              UUID : abcdef12:34567890:abcdef12:34567890
            Events : 2543

    Number   Major   Minor   RaidDevice State
       0       8       33        0      active sync   /dev/sdc1
       1       8       49        1      active sync   /dev/sdd1
       2       8       65        2      active sync   /dev/sde1
EOF

cat > test-data/mdadm/mdadm-detail-md2.txt << 'EOF'
/dev/md2:
           Version : 1.2
     Creation Time : Mon Feb 01 09:15:22 2024
        Raid Level : raid1
        Array Size : 52428800 (50.00 GiB 53.69 GB)
     Used Dev Size : 52428800 (50.00 GiB 53.69 GB)
      Raid Devices : 2
     Total Devices : 2
       Persistence : Superblock is persistent

       Update Time : Mon Mar 11 15:25:00 2024
             State : clean, degraded, recovering 
    Active Devices : 1
   Working Devices : 1
    Failed Devices : 1
     Spare Devices : 0

Consistency Policy : resync

    Rebuild Status : 3% complete

              Name : node01:2
              UUID : fedcba09:87654321:fedcba09:87654321
            Events : 89

    Number   Major   Minor   RaidDevice State
       0       8       81        0      active sync   /dev/sdf1
       -       0        0        1      removed
       
       1       8       97        -      faulty   /dev/sdg1
EOF

create_fixture "test-raid"

################################################################################
# Test: BTRFS Configuration
################################################################################
echo ""
echo "=== Creating test-btrfs.tar.xz ==="
mkdir -p test-data/basic-environment

cat > test-data/basic-environment/btrfs.txt << 'EOF'
#==[ Command ]======================================#
# /usr/sbin/btrfs filesystem show
Label: 'root'  uuid: 550e8400-e29b-41d4-a716-446655440000
	Total devices 2 FS bytes used 45.23GiB
	devid    1 size 100.00GiB used 50.00GiB path /dev/sda2
	devid    2 size 100.00GiB used 50.00GiB path /dev/sdb2

Label: 'data'  uuid: 7a8b9c0d-1e2f-3a4b-5c6d-7e8f9a0b1c2d
	Total devices 3 FS bytes used 250.75GiB
	devid    1 size 500.00GiB used 300.00GiB path /dev/sdc1
	devid    2 size 500.00GiB used 300.00GiB path /dev/sdd1
	devid    3 size 500.00GiB used 300.00GiB path /dev/sde1

Label: none  uuid: 1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d
	Total devices 1 FS bytes used 15.89GiB
	devid    1 size 50.00GiB used 20.00GiB path /dev/sdf1

#==[ Command ]======================================#
# /usr/sbin/btrfs subvolume list /
ID 256 gen 123 top level 5 path @rootfs
ID 257 gen 124 top level 5 path @home
ID 258 gen 125 top level 5 path @opt
ID 259 gen 126 top level 5 path @srv
ID 260 gen 127 top level 5 path @tmp
ID 261 gen 128 top level 5 path @var
ID 262 gen 129 parent 261 top level 5 path @var/log
ID 263 gen 130 parent 261 top level 5 path @var/cache
ID 264 gen 131 top level 5 path @snapshots
ID 265 gen 132 parent 264 top level 5 path @snapshots/root-2024-01-15
EOF

create_fixture "test-btrfs"

################################################################################
# Test: Block Devices and fstab UUID Correlation
################################################################################
echo ""
echo "=== Creating test-block-devices.tar.xz ==="
mkdir -p test-data/sos_commands/block
mkdir -p test-data/etc

# lsblk basic output
cat > test-data/sos_commands/block/lsblk << 'EOF'
NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda       8:0    0   64G  0 disk 
|-sda1    8:1    0  500M  0 part /boot/efi
|-sda2    8:2    0    1G  0 part /boot
`-sda3    8:3    0 62.5G  0 part /
sdb       8:16   0  128G  0 disk 
`-sdb1    8:17   0  128G  0 part /mnt
sdc       8:32   0  256G  0 disk 
`-sdc1    8:33   0  256G  0 part /data
EOF

# lsblk -f -a -l output with filesystem and UUID info
cat > 'test-data/sos_commands/block/lsblk_-f_-a_-l' << 'EOF'
NAME  FSTYPE FSVER LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
sda                                                                          
sda1  vfat   FAT32       ABCD-1234                            450M     10% /boot/efi
sda2  ext4   1.0         11111111-1111-1111-1111-111111111111  800M    20% /boot
sda3  ext4   1.0         22222222-2222-2222-2222-222222222222   45G    28% /
sdb                                                                          
sdb1  ext4   1.0         33333333-3333-3333-3333-333333333333  120G     6% /mnt
sdc                                                                          
sdc1  ext4   1.0         44444444-4444-4444-4444-444444444444  240G     6% /data
EOF

# blkid output
cat > 'test-data/sos_commands/block/blkid_-c_.dev.null' << 'EOF'
/dev/sda1: UUID="ABCD-1234" BLOCK_SIZE="512" TYPE="vfat" PARTUUID="aaaa1111-01"
/dev/sda2: UUID="11111111-1111-1111-1111-111111111111" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="aaaa1111-02"
/dev/sda3: UUID="22222222-2222-2222-2222-222222222222" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="aaaa1111-03"
/dev/sdb1: UUID="33333333-3333-3333-3333-333333333333" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="bbbb2222-01"
/dev/sdc1: UUID="44444444-4444-4444-4444-444444444444" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="cccc3333-01"
EOF

# fstab - matching UUIDs (no issues)
cat > test-data/etc/fstab << 'EOF'
# /etc/fstab
UUID=22222222-2222-2222-2222-222222222222 / ext4 defaults 0 1
UUID=11111111-1111-1111-1111-111111111111 /boot ext4 defaults 0 2
UUID=ABCD-1234 /boot/efi vfat defaults 0 2
UUID=33333333-3333-3333-3333-333333333333 /mnt ext4 defaults,nofail 0 2
UUID=44444444-4444-4444-4444-444444444444 /data ext4 defaults,nofail 0 2
EOF

create_fixture "test-block-devices"

################################################################################
# Test: Block Devices with fstab UUID Mismatch
################################################################################
echo ""
echo "=== Creating test-block-devices-mismatch.tar.xz ==="
mkdir -p test-data/sos_commands/block
mkdir -p test-data/etc

# lsblk -f -a -l output
cat > 'test-data/sos_commands/block/lsblk_-f_-a_-l' << 'EOF'
NAME  FSTYPE FSVER LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
sda                                                                          
sda1  vfat   FAT32       ABCD-1234                            450M     10% /boot/efi
sda2  ext4   1.0         11111111-1111-1111-1111-111111111111  800M    20% /boot
sda3  ext4   1.0         22222222-2222-2222-2222-222222222222   45G    28% /
sdb                                                                          
sdb1  ext4   1.0         NEW-UUID-5555-5555-5555-555555555555  120G     6% /mnt
sdc                                                                          
sdc1  xfs          data  66666666-6666-6666-6666-666666666666  240G     6% /data
EOF

# blkid output - note sdb1 has a different UUID than expected in fstab
cat > 'test-data/sos_commands/block/blkid_-c_.dev.null' << 'EOF'
/dev/sda1: UUID="ABCD-1234" BLOCK_SIZE="512" TYPE="vfat" PARTUUID="aaaa1111-01"
/dev/sda2: UUID="11111111-1111-1111-1111-111111111111" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="aaaa1111-02"
/dev/sda3: UUID="22222222-2222-2222-2222-222222222222" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="aaaa1111-03"
/dev/sdb1: UUID="NEW-UUID-5555-5555-5555-555555555555" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="bbbb2222-01"
/dev/sdc1: UUID="66666666-6666-6666-6666-666666666666" BLOCK_SIZE="4096" TYPE="xfs" PARTUUID="cccc3333-01"
EOF

# fstab - has UUID mismatches and filesystem type mismatch
cat > test-data/etc/fstab << 'EOF'
# /etc/fstab - with intentional issues for testing
UUID=22222222-2222-2222-2222-222222222222 / ext4 defaults 0 1
UUID=11111111-1111-1111-1111-111111111111 /boot ext4 defaults 0 2
UUID=ABCD-1234 /boot/efi vfat defaults 0 2
# This UUID no longer exists - disk was replaced
UUID=OLD-UUID-3333-3333-3333-333333333333 /mnt ext4 defaults,nofail 0 2
# This has wrong filesystem type (fstab says ext4 but disk has xfs)
UUID=66666666-6666-6666-6666-666666666666 /data ext4 defaults,nofail 0 2
# This UUID doesn't exist at all
UUID=MISSING-UUID-9999-9999-9999-999999 /opt ext4 defaults,nofail 0 2
EOF

create_fixture "test-block-devices-mismatch"

################################################################################
# Test: EOL Distribution - SLES 12 (End of Life)
################################################################################
echo ""
echo "=== Creating test-eol-sles12.tar.xz ==="
mkdir -p test-data

# basic-environment.txt for SLES 12 SP5 (EOL distribution)
cat > test-data/basic-environment.txt << 'EOF'
#==[ Configuration File ]===========================#
# /etc/os-release
NAME="SLES"
VERSION="12-SP5"
VERSION_ID="12.5"
PRETTY_NAME="SUSE Linux Enterprise Server 12 SP5"
ID="sles"
ID_LIKE="suse"
ANSI_COLOR="0;32"
CPE_NAME="cpe:/o:suse:sles:12:sp5"

#==[ Command ]======================================#
# uname -a
Linux sles12-test 4.12.14-122.162-default #1 SMP Thu May 30 08:00:36 UTC 2024 x86_64 x86_64 x86_64 GNU/Linux
EOF

create_fixture "test-eol-sles12"

################################################################################
# Test: EOL Distribution - RHEL 7 (End of Life)
################################################################################
echo ""
echo "=== Creating test-eol-rhel7.tar.xz ==="
mkdir -p test-data/usr/lib

# os-release for RHEL 7.9 (EOL distribution)
cat > test-data/usr/lib/os-release << 'EOF'
NAME="Red Hat Enterprise Linux Server"
VERSION="7.9 (Maipo)"
ID="rhel"
ID_LIKE="fedora"
VARIANT="Server"
VARIANT_ID="server"
VERSION_ID="7.9"
PRETTY_NAME="Red Hat Enterprise Linux Server 7.9 (Maipo)"
ANSI_COLOR="0;31"
CPE_NAME="cpe:/o:redhat:enterprise_linux:7.9:GA:server"
HOME_URL="https://www.redhat.com/"
BUG_REPORT_URL="https://bugzilla.redhat.com/"
REDHAT_BUGZILLA_PRODUCT="Red Hat Enterprise Linux 7"
REDHAT_BUGZILLA_PRODUCT_VERSION=7.9
REDHAT_SUPPORT_PRODUCT="Red Hat Enterprise Linux"
REDHAT_SUPPORT_PRODUCT_VERSION="7.9"
EOF

create_fixture "test-eol-rhel7"

################################################################################
# Test: EOL Distribution - CentOS 7 (End of Life)
################################################################################
echo ""
echo "=== Creating test-eol-centos7.tar.xz ==="
mkdir -p test-data/usr/lib

# os-release for CentOS 7.9 (EOL distribution)
cat > test-data/usr/lib/os-release << 'EOF'
NAME="CentOS Linux"
VERSION="7 (Core)"
ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="7"
PRETTY_NAME="CentOS Linux 7 (Core)"
ANSI_COLOR="0;31"
CPE_NAME="cpe:/o:centos:centos:7"
HOME_URL="https://www.centos.org/"
BUG_REPORT_URL="https://bugs.centos.org/"
CENTOS_MANTISBT_PROJECT="CentOS-7"
CENTOS_MANTISBT_PROJECT_VERSION="7"
EOF

create_fixture "test-eol-centos7"

################################################################################
# Test: Time Sync Service - chronyd enabled and running
################################################################################
echo ""
echo "=== Creating test-timesync-chrony.tar.xz ==="
mkdir -p test-data/sos_commands/systemd

# systemd-status.txt with chronyd service status (SCC format)
cat > test-data/sos_commands/systemd/systemd-status.txt << 'EOF'
# /bin/systemctl status 'chronyd.service'
● chronyd.service - NTP client/server
     Loaded: loaded (/usr/lib/systemd/system/chronyd.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2026-01-27 10:00:00 UTC; 1 week 2 days ago
       Docs: man:chronyd(8)
             man:chrony.conf(5)
   Main PID: 1234 (chronyd)
      Tasks: 1 (limit: 49152)
     Memory: 1.5M
        CPU: 123ms
     CGroup: /system.slice/chronyd.service
             └─1234 /usr/sbin/chronyd

Jan 27 10:00:00 test-host systemd[1]: Starting NTP client/server...
Jan 27 10:00:00 test-host chronyd[1234]: chronyd version 4.1 starting (+CMDMON +NTP +REFCLOCK +RTC +PRIVDROP +SCFILTER +SIGND +ASYNCDNS +NTS +SECHASH +IPV6 +DEBUG)
Jan 27 10:00:00 test-host systemd[1]: Started NTP client/server.
EOF

create_fixture "test-timesync-chrony"

################################################################################
# Test: SAP Instance Configuration - START_PROFILE and InstanceName issues
# Tests for sapInstanceConfigParser and sapInstanceErrorsParser
# Reference: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux_for_sap_solutions/8/html/configuring_ha_clusters_to_manage_sap_netweaver_or_sap_s4hana_application_server_instances_using_the_rhel_ha_add-on
################################################################################
echo ""
echo "=== Creating test-sap-instance-config.tar.xz ==="
mkdir -p test-data/sos_commands/pacemaker
mkdir -p test-data/sos_commands/pacemaker/crm_report
# SAP indicator directories for SAP detection in UI
mkdir -p test-data/usr/sap/PJU
mkdir -p test-data/sapmnt/PJU/profile
touch test-data/usr/sap/PJU/sapservices

# pcs_config with SAP SAPInstance resources - note hostname mismatch
cat > test-data/sos_commands/pacemaker/pcs_config << 'EOF'
Cluster Name: pju-prod-cluster
Corosync Nodes:
 awenwjeupcs01 awenwjeupcs02
Pacemaker Nodes:
 awenwjeupcs01 awenwjeupcs02

Resources:
 Group: g-PJU_SCS
  Meta Attrs: resource-stickiness=3000
  Resource: fs_PJU_SCS (class=ocf provider=heartbeat type=Filesystem)
   Attributes: device=eufusionsapwesteuprodst.file.core.windows.net:/eufusionsapwesteuprodst/sap-core-pju-scs01 directory=/usr/sap/PJU/SCS01 force_unmount=safe fstype=nfs options=sec=sys,vers=4.1
   Operations: monitor interval=200 timeout=40 (fs_PJU_SCS-monitor-interval-200)
               start interval=0 timeout=60 (fs_PJU_SCS-start-interval-0)
               stop interval=0 timeout=120 (fs_PJU_SCS-stop-interval-0)
  Resource: vip_PJU_SCS (class=ocf provider=heartbeat type=IPaddr2)
   Attributes: ip=10.82.8.23
   Operations: monitor interval=10s timeout=20s (vip_PJU_SCS-monitor-interval-10s)
               start interval=0s timeout=20s (vip_PJU_SCS-start-interval-0s)
               stop interval=0s timeout=20s (vip_PJU_SCS-stop-interval-0s)
  Resource: nc_PJU_SCS (class=ocf provider=heartbeat type=azure-lb)
   Attributes: port=62000
   Operations: monitor interval=10s timeout=20s (nc_PJU_SCS-monitor-interval-10s)
               start interval=0s timeout=20s (nc_PJU_SCS-start-interval-0s)
               stop interval=0s timeout=20s (nc_PJU_SCS-stop-interval-0s)
  Resource: rsc_sap_PJU_SCS01 (class=ocf provider=heartbeat type=SAPInstance)
   Attributes: AUTOMATIC_RECOVER=false InstanceName=PJU_SCS01_ppu-scs START_PROFILE=/sapmnt/PJU/profile/PJU_SCS01_awenwjeusscs
   Meta Attrs: failure-timeout=60 migration-threshold=1 resource-stickiness=5000
   Operations: demote interval=0s timeout=320s (rsc_sap_PJU_SCS01-demote-interval-0s)
               methods interval=0s timeout=5s (rsc_sap_PJU_SCS01-methods-interval-0s)
               monitor interval=20 on-fail=restart timeout=60 (rsc_sap_PJU_SCS01-monitor-interval-20)
               promote interval=0s timeout=320s (rsc_sap_PJU_SCS01-promote-interval-0s)
               reload interval=0s timeout=320s (rsc_sap_PJU_SCS01-reload-interval-0s)
               start interval=0 timeout=600 (rsc_sap_PJU_SCS01-start-interval-0)
               stop interval=0 timeout=600 (rsc_sap_PJU_SCS01-stop-interval-0)
 Group: g-PJU_ERS
  Resource: fs_PJU_ERS (class=ocf provider=heartbeat type=Filesystem)
   Attributes: device=eufusionsapwesteuprodst.file.core.windows.net:/eufusionsapwesteuprodst/sap-core-pju-ers11 directory=/usr/sap/PJU/ERS11 force_unmount=safe fstype=nfs options=sec=sys,vers=4.1
   Operations: monitor interval=200 timeout=40 (fs_PJU_ERS-monitor-interval-200)
               start interval=0 timeout=60 (fs_PJU_ERS-start-interval-0)
               stop interval=0 timeout=120 (fs_PJU_ERS-stop-interval-0)
  Resource: vip_PJU_AERS (class=ocf provider=heartbeat type=IPaddr2)
   Attributes: ip=10.82.8.24
   Operations: monitor interval=10s timeout=20s (vip_PJU_AERS-monitor-interval-10s)
               start interval=0s timeout=20s (vip_PJU_AERS-start-interval-0s)
               stop interval=0s timeout=20s (vip_PJU_AERS-stop-interval-0s)
  Resource: nc_PJU_AERS (class=ocf provider=heartbeat type=azure-lb)
   Attributes: port=62111
   Operations: monitor interval=10s timeout=20s (nc_PJU_AERS-monitor-interval-10s)
               start interval=0s timeout=20s (nc_PJU_AERS-start-interval-0s)
               stop interval=0s timeout=20s (nc_PJU_AERS-stop-interval-0s)
  Resource: rsc_sap_PJU_ERS11 (class=ocf provider=heartbeat type=SAPInstance)
   Attributes: AUTOMATIC_RECOVER=false IS_ERS=true InstanceName=PJU_ERS11_ppu-ers START_PROFILE=/sapmnt/PJU/profile/PJU_ERS11_awenwjeusscs
   Operations: demote interval=0s timeout=320s (rsc_sap_PJU_ERS11-demote-interval-0s)
               methods interval=0s timeout=5s (rsc_sap_PJU_ERS11-methods-interval-0s)
               monitor interval=20 on-fail=restart timeout=60 (rsc_sap_PJU_ERS11-monitor-interval-20)
               promote interval=0s timeout=320s (rsc_sap_PJU_ERS11-promote-interval-0s)
               reload interval=0s timeout=320s (rsc_sap_PJU_ERS11-reload-interval-0s)
               start interval=0 timeout=600 (rsc_sap_PJU_ERS11-start-interval-0)
               stop interval=0 timeout=600 (rsc_sap_PJU_ERS11-stop-interval-0)

Stonith Devices:
  Resource: rsc_st_azure (class=stonith type=fence_azure_arm)
    Attributes: msi=true resourceGroup=myRG subscriptionId=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    Operations:
      monitor: rsc_st_azure-monitor-interval-3600
        interval=3600

Cluster Properties:
 cluster-infrastructure: corosync
 cluster-name: pju-prod-cluster
 stonith-enabled: true
 stonith-timeout: 900
EOF

# crm_report analysis.txt with SAP errors (START_PROFILE and GRAY status)
cat > test-data/sos_commands/pacemaker/crm_report/analysis.txt << 'EOF'
Diff members.txt... OK
Diff cib.xml... OK
Diff crm_mon.txt... OK
Diff sysinfo.txt... OK
Log pattern matches from awenwjeupcs01:
Jan 11 11:02:37 awenwjeupcs01 SAPInstance(rsc_sap_PJU_ERS11)[16872]: ERROR: Expected /sapmnt/PJU/profile/PJU_ERS11_awenwjeusscs to be the instance START profile, please set START_PROFILE parameter!
Jan 11 11:03:36 awenwjeupcs01 SAPInstance(rsc_sap_PJU_ERS11)[18199]: ERROR: Expected /sapmnt/PJU/profile/PJU_ERS11_awenwjeusscs to be the instance START profile, please set START_PROFILE parameter!
Jan 11 11:19:03 awenwjeupcs01 SAPInstance(rsc_sap_PJU_SCS01)[37447]: ERROR: SAP instance service msg_server is not running with status GRAY !
Jan 11 11:19:03 awenwjeupcs01 SAPInstance(rsc_sap_PJU_SCS01)[37447]: ERROR: SAP instance service enserver is not running with status GRAY !
Jan 11 11:19:06 awenwjeupcs01 Filesystem(fs_PJU_SCS)[38065]: ERROR: Couldn't unmount /usr/sap/PJU/SCS01; trying cleanup with TERM
Jan 11 11:23:44 awenwjeupcs01 SAPInstance(rsc_sap_PJU_ERS11)[41957]: ERROR: Expected /sapmnt/PJU/profile/PJU_ERS11_awenwjeusscs to be the instance START profile, please set START_PROFILE parameter!
Jan 11 11:26:37 awenwjeupcs01 Filesystem(fs_PJU_SCS)[45202]: ERROR: Couldn't unmount /usr/sap/PJU/SCS01; trying cleanup with TERM
EOF

# Add pcs_status to show the daemon status
cat > test-data/sos_commands/pacemaker/pcs_status_--full << 'EOF'
Cluster name: pju-prod-cluster
Cluster Summary:
  * Stack: corosync
  * Current DC: awenwjeupcs01 (version 2.1.2-4.el8_6.9-ada5c3b36e2) - partition with quorum
  * Last updated: Sun Jan 12 14:01:52 2026
  * Last change:  Sat Jan 11 08:31:29 2026 by root via cibadmin on awenwjeupcs01
  * 2 nodes configured
  * 12 resource instances configured

Node List:
  * Online: [ awenwjeupcs01 awenwjeupcs02 ]

Full List of Resources:
  * Resource Group: g-PJU_SCS:
    * fs_PJU_SCS        (ocf::heartbeat:Filesystem):     Started awenwjeupcs01
    * vip_PJU_SCS       (ocf::heartbeat:IPaddr2):        Started awenwjeupcs01
    * nc_PJU_SCS        (ocf::heartbeat:azure-lb):       Started awenwjeupcs01
    * rsc_sap_PJU_SCS01 (ocf::heartbeat:SAPInstance):    Started awenwjeupcs01
  * Resource Group: g-PJU_ERS:
    * fs_PJU_ERS        (ocf::heartbeat:Filesystem):     Started awenwjeupcs02
    * vip_PJU_AERS      (ocf::heartbeat:IPaddr2):        Started awenwjeupcs02
    * nc_PJU_AERS       (ocf::heartbeat:azure-lb):       Started awenwjeupcs02
    * rsc_sap_PJU_ERS11 (ocf::heartbeat:SAPInstance):    Started awenwjeupcs02
  * rsc_st_azure        (stonith:fence_azure_arm):       Started awenwjeupcs01

Daemon Status:
  corosync: active/disabled
  pacemaker: active/enabled
  pcsd: active/enabled
EOF

create_fixture "test-sap-instance-config"

################################################################################
# Test: Cluster events detection from supportconfig ha.txt
# Verifies that clusterEvents parser can extract embedded pacemaker/corosync
# log sections from ha.txt and detect resource migrations, fencing events,
# and resource failures.
################################################################################
echo ""
echo "=== Creating test-cluster-events.tar.xz ==="
mkdir -p test-data
cat > test-data/ha.txt << 'EOF'
#==[ Configuration File ]====# /etc/corosync/corosync.conf
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
}

#==[ Command ]====# /usr/sbin/crm configure show
property cib-bootstrap-options: \
    stonith-enabled=true \
    stonith-timeout=150s

primitive rsc_SAPHana_HDB_HDB00 ocf:suse:SAPHana \
    op start timeout=3600 \
    op stop timeout=3600

primitive stonith-fence_azure_arm stonith:fence_azure_arm \
    op monitor interval=3600 timeout=120

#==[ Command ]====# /usr/sbin/crm_mon -1 -r -f
Stack: corosync
Current DC: node1
Last updated: Wed Jan 15 10:35:00 2025
2 nodes configured
3 resources configured

Online: [ node1 ]
OFFLINE: [ node2 ]

Full list of resources:

 rsc_SAPHana_HDB_HDB00  (ocf::heartbeat:SAPHana):      Started node1
 rsc_ip_HDB_HDB00       (ocf::heartbeat:IPaddr2):      Started node1
 stonith-fence_azure_arm (stonith:fence_azure_arm):     Started node1

#==[ Log File ]====# /var/log/pacemaker/pacemaker.log
Jan 15 10:30:45 node1 pacemaker-controld  [1234] (handle_request)          notice: Requesting fencing (reboot) of node node2
Jan 15 10:30:48 node1 pacemaker-fenced    [1235] (handle_request)          notice: fence_azure_arm: Called fence_azure_arm for node node2
Jan 15 10:30:50 node1 pacemaker-controld  [1234] (tengine_stonith_notify)  notice: Peer node2 was terminated (reboot) by node1 on behalf of pacemaker-controld.1234
Jan 15 10:31:00 node1 pacemaker-controld  [1234] (te_rsc_command)          notice: Moving resource rsc_ip_HDB_HDB00 from node2 to node1
Jan 15 10:31:05 node1 pacemaker-controld  [1234] (do_lrm_rsc_op)          notice: Operation rsc_SAPHana_HDB_HDB00_start_0: ok (node=node1)
Jan 15 10:33:00 node1 pacemaker-controld  [1234] (process_lrm_event)      notice: Unexpected result (error: unknown error) was recorded for monitor of rsc_SAPHana_HDB_HDB00 on node2

#==[ Log File ]====# /var/log/cluster/corosync.log
Jan 15 10:30:42 node1 corosync  [5678] notice: Node node2 will be fenced
Jan 15 10:30:55 node1 corosync  [5678] notice: Fencing node2: success
EOF

create_fixture "test-cluster-events"

################################################################################
# Test: Cluster events detection from sosreport (RHEL format)
# Verifies that clusterEvents parser handles sosreport structure:
# - pacemaker.log in sos_strings as .tailed file
# - "targeting node X" format (vs SUSE's "of node X")
# - "Cluster node X will be fenced" format  
# - "Peer X was not terminated" as fencing failure
# Also verifies RHEL-specific totem transport validation (knet expected)
################################################################################
echo ""
echo "=== Creating test-cluster-events-sosreport.tar.xz ==="
SOSDIR="sosreport-testnode-2025-01-27-abc123"
mkdir -p "test-data/${SOSDIR}/etc/corosync"
mkdir -p "test-data/${SOSDIR}/sos_strings/pacemaker"
mkdir -p "test-data/${SOSDIR}/var/log/pacemaker"
mkdir -p "test-data/${SOSDIR}/etc"

# Create os-release for RHEL detection
cat > "test-data/${SOSDIR}/etc/os-release" << 'EOF'
NAME="Red Hat Enterprise Linux"
VERSION="8.8 (Ootpa)"
ID="rhel"
ID_LIKE="fedora"
VERSION_ID="8.8"
PRETTY_NAME="Red Hat Enterprise Linux 8.8 (Ootpa)"
EOF

# Create corosync.conf with knet transport (correct for RHEL)
cat > "test-data/${SOSDIR}/etc/corosync/corosync.conf" << 'EOF'
totem {
    version: 2
    cluster_name: testcluster
    transport: knet
    token: 30000
    token_retransmits_before_loss_const: 10
    join: 60
    consensus: 36000
    max_messages: 20
}

quorum {
    provider: corosync_votequorum
    expected_votes: 2
    two_node: 1
}

nodelist {
    node {
        ring0_addr: testnode1
        nodeid: 1
    }
    node {
        ring0_addr: testnode2
        nodeid: 2
    }
}
EOF

# Create pacemaker.log as a tailed file in sos_strings (sosreport format)
cat > "test-data/${SOSDIR}/sos_strings/pacemaker/var.log.pacemaker.pacemaker.log.tailed" << 'EOF'
Jan 27 09:10:00 testnode1 pacemaker-schedulerd[8138] (unpack_rsc_op_failure)	warning: Unexpected result (error: Resource agent did not complete within 11m40s) was recorded for monitor of SAPHana_TST_00:1 on testnode2 at Jan 27 09:08:10 2025
Jan 27 09:13:13 testnode1 pacemaker-schedulerd[8138] (pe_fence_node)	warning: Cluster node testnode2 will be fenced: SAPHanaTopology_TST_00:1 is thought to be active there
Jan 27 09:13:13 testnode1 pacemaker-controld  [8146] (controld_execute_fence_action)	notice: Requesting fencing (reboot) targeting node testnode2 | action=4 timeout=150000
Jan 27 09:13:30 testnode1 pacemaker-controld  [8146] (handle_fence_notification)	notice: Peer testnode2 was not terminated (reboot) by testnode1 on behalf of pacemaker-controld.8146: delegate failed
Jan 27 09:14:00 testnode1 pacemaker-controld  [8146] (controld_execute_fence_action)	notice: Requesting fencing (reboot) targeting node testnode2 | action=4 timeout=150000
Jan 27 09:14:30 testnode1 pacemaker-controld  [8146] (tengine_stonith_notify)	notice: Peer testnode2 was terminated (reboot) by testnode1 on behalf of pacemaker-controld.8146
Jan 27 09:15:00 testnode1 pacemaker-controld  [8146] (te_rsc_command)	notice: Moving resource rsc_ip_TST_00 from testnode2 to testnode1
EOF

# Create 0-byte symlink placeholder at original path (sosreport convention)
touch "test-data/${SOSDIR}/var/log/pacemaker/pacemaker.log"

create_fixture "test-cluster-events-sosreport"

################################################################################
# Test: Firewall Rules - SCC (supportconfig) format
# Tests iptables, ip6tables, nftables, and firewalld detection in network.txt
################################################################################
echo ""
echo "=== Creating test-firewall-scc.tar.xz ==="
mkdir -p test-data
cat > test-data/network.txt << 'SCCEOF'
#==[ Verification ]=================================#
# rpm -V firewalld-0.9.3-150400.8.12.1.noarch
# Verification Status: Passed

#==[ Command ]======================================#
# /bin/systemctl status firewalld.service
○ firewalld.service - firewalld - dynamic firewall daemon
     Loaded: loaded (/usr/lib/systemd/system/firewalld.service; disabled; vendor preset: disabled)
     Active: inactive (dead)
       Docs: man:firewalld(1)

#==[ Command ]======================================#
# /usr/bin/firewall-cmd --list-all
FirewallD is not running

#==[ Command ]======================================#
# iptables

# NOTE: The iptable_filter module is not loaded, skipping check

#==[ Command ]======================================#
# iptables

# NOTE: The iptable_nat module is not loaded, skipping check

#==[ Command ]======================================#
# iptables

# NOTE: The iptable_mangle module is not loaded, skipping check

#==[ Command ]======================================#
# iptables

# NOTE: The iptable_raw module is not loaded, skipping check

#==[ Command ]======================================#
# ip6tables

# NOTE: The ip6table_filter module is not loaded, skipping check

#==[ Command ]======================================#
# ip6tables

# NOTE: The ip6table_nat module is not loaded, skipping check

#==[ Command ]======================================#
# ip6tables

# NOTE: The ip6table_mangle module is not loaded, skipping check

#==[ Command ]======================================#
# ip6tables

# NOTE: The ip6table_raw module is not loaded, skipping check

#==[ Verification ]=================================#
# rpm -V nftables-0.9.8-150400.6.3.1.x86_64
# Verification Status: Passed

#==[ Command ]======================================#
# /usr/sbin/nft list tables

SCCEOF
create_fixture "test-firewall-scc"

################################################################################
# Test: Firewall Rules - SCC with active nftables rules
# Tests nftables ruleset detection in SCC network.txt
################################################################################
echo ""
echo "=== Creating test-firewall-scc-nftables.tar.xz ==="
mkdir -p test-data
cat > test-data/network.txt << 'SCCEOF'
#==[ Command ]======================================#
# /bin/systemctl status firewalld.service
○ firewalld.service - firewalld - dynamic firewall daemon
     Loaded: loaded (/usr/lib/systemd/system/firewalld.service; disabled; vendor preset: disabled)
     Active: inactive (dead)

#==[ Command ]======================================#
# /usr/bin/firewall-cmd --list-all
FirewallD is not running

#==[ Command ]======================================#
# iptables

# NOTE: The iptable_filter module is not loaded, skipping check

#==[ Command ]======================================#
# /usr/sbin/nft list tables
ip security

#==[ Command ]======================================#
# /usr/sbin/nft -a list ruleset
table ip security {
    chain INPUT {
        type filter hook input priority 150; policy accept;
    }
    chain FORWARD {
        type filter hook forward priority 150; policy accept;
    }
    chain OUTPUT {
        type filter hook output priority 150; policy accept;
        meta l4proto tcp ip daddr 168.63.129.16 tcp dport 53 counter packets 0 bytes 0 accept
        meta l4proto tcp ip daddr 168.63.129.16 skuid 0 counter packets 12345 bytes 6789012 accept
        meta l4proto tcp ip daddr 168.63.129.16 ct state invalid,new counter packets 0 bytes 0 drop
    }
}

SCCEOF
create_fixture "test-firewall-scc-nftables"

################################################################################
# Test: Firewall Rules - SOS (sosreport) format
# Tests firewalld, nftables and config file detection across multiple files
################################################################################
echo ""
echo "=== Creating test-firewall-sosreport.tar.xz ==="
SOSDIR="sosreport-testfw-2025-01-15-abcdef"
mkdir -p "test-data/${SOSDIR}/sos_commands/firewalld"
mkdir -p "test-data/${SOSDIR}/sos_commands/firewall_tables"
mkdir -p "test-data/${SOSDIR}/etc/sysconfig"
mkdir -p "test-data/${SOSDIR}/etc/firewalld"

# firewalld state: not running
echo "not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--state"

# firewalld zones (runtime)
echo "FirewallD is not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--list-all-zones"

# firewalld zones (permanent)
echo "FirewallD is not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--permanent_--list-all-zones"

# firewalld direct rules
echo "FirewallD is not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--direct_--get-all-rules"
echo "FirewallD is not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--permanent_--direct_--get-all-rules"

# firewalld direct chains
echo "FirewallD is not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--direct_--get-all-chains"
echo "FirewallD is not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--permanent_--direct_--get-all-chains"

# firewalld passthroughs
echo "FirewallD is not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--direct_--get-all-passthroughs"
echo "FirewallD is not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--permanent_--direct_--get-all-passthroughs"

# firewalld log-denied
echo "FirewallD is not running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--get-log-denied"

# nftables ruleset
cat > "test-data/${SOSDIR}/sos_commands/firewall_tables/nft_-a_list_ruleset" << 'EOF'
table ip security { # handle 3
    chain INPUT { # handle 1
        type filter hook input priority 150; policy accept;
    }

    chain FORWARD { # handle 2
        type filter hook forward priority 150; policy accept;
    }

    chain OUTPUT { # handle 3
        type filter hook output priority 150; policy accept;
        meta l4proto tcp ip daddr 168.63.129.16 tcp dport 53 counter packets 0 bytes 0 accept # handle 4
        meta l4proto tcp ip daddr 168.63.129.16 skuid 0 counter packets 319671 bytes 451835370 accept # handle 5
        meta l4proto tcp ip daddr 168.63.129.16 ct state invalid,new counter packets 0 bytes 0 drop # handle 6
    }
}
EOF

# firewalld.conf
cat > "test-data/${SOSDIR}/etc/firewalld/firewalld.conf" << 'EOF'
# firewalld config file
DefaultZone=public
CleanupOnExit=yes
Lockdown=no
IPv6_rpfilter=yes
IndividualCalls=no
LogDenied=off
FirewallBackend=nftables
FlushAllOnReload=yes
AllowZoneDrifting=yes
EOF

# /etc/sysconfig/iptables-config
cat > "test-data/${SOSDIR}/etc/sysconfig/iptables-config" << 'EOF'
IPTABLES_MODULES=""
IPTABLES_SAVE_ON_STOP="no"
IPTABLES_SAVE_ON_RESTART="no"
IPTABLES_SAVE_COUNTER="no"
IPTABLES_STATUS_NUMERIC="yes"
IPTABLES_STATUS_VERBOSE="no"
IPTABLES_STATUS_LINENUMBERS="yes"
EOF

# /etc/sysconfig/ebtables-config
cat > "test-data/${SOSDIR}/etc/sysconfig/ebtables-config" << 'EOF'
EBTABLES_SAVE_ON_STOP="no"
EBTABLES_SAVE_COUNTER="no"
EOF

# /etc/sysconfig/nftables.conf
cat > "test-data/${SOSDIR}/etc/sysconfig/nftables.conf" << 'EOF'
# Uncomment the include statement here to load the default config sample
#include "/etc/nftables/main.nft"
EOF

# /etc/sysconfig/firewalld
cat > "test-data/${SOSDIR}/etc/sysconfig/firewalld" << 'EOF'
# firewalld command line args
FIREWALLD_ARGS=
EOF

create_fixture "test-firewall-sosreport"

################################################################################
# Test: Firewall Rules - SOS with firewalld running and active zones
################################################################################
echo ""
echo "=== Creating test-firewall-sosreport-active.tar.xz ==="
SOSDIR="sosreport-testfwactive-2025-01-15-xyzabc"
mkdir -p "test-data/${SOSDIR}/sos_commands/firewalld"
mkdir -p "test-data/${SOSDIR}/sos_commands/firewall_tables"
mkdir -p "test-data/${SOSDIR}/etc/firewalld"

# firewalld state: running
echo "running" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--state"

# firewalld zones (runtime) - active
cat > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--list-all-zones" << 'EOF'
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: eth0
  sources:
  services: cockpit dhcpv6-client ssh
  ports: 8080/tcp 443/tcp
  protocols:
  forward: yes
  masquerade: no
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:
	rule family="ipv4" source address="10.0.0.0/8" accept
EOF

# firewalld zones (permanent)
cat > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--permanent_--list-all-zones" << 'EOF'
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: eth0
  sources:
  services: cockpit dhcpv6-client ssh
  ports: 8080/tcp 443/tcp
  protocols:
  forward: yes
  masquerade: no
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:
	rule family="ipv4" source address="10.0.0.0/8" accept
EOF

# firewalld direct rules
echo "" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--direct_--get-all-rules"
echo "" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--permanent_--direct_--get-all-rules"

# firewalld direct chains
echo "" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--direct_--get-all-chains"
echo "" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--permanent_--direct_--get-all-chains"

# firewalld passthroughs
echo "" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--direct_--get-all-passthroughs"
echo "" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--permanent_--direct_--get-all-passthroughs"

# firewalld log-denied
echo "off" > "test-data/${SOSDIR}/sos_commands/firewalld/firewall-cmd_--get-log-denied"

# nftables ruleset (firewalld-generated)
cat > "test-data/${SOSDIR}/sos_commands/firewall_tables/nft_-a_list_ruleset" << 'EOF'
table inet firewalld { # handle 1
    chain filter_INPUT { # handle 1
        type filter hook input priority 10; policy accept;
        ct state established,related accept # handle 4
        iifname "lo" accept # handle 5
        ct state invalid drop # handle 6
        jump filter_INPUT_ZONES # handle 7
        reject with icmpx admin-prohibited # handle 8
    }
    chain filter_FORWARD { # handle 2
        type filter hook forward priority 10; policy accept;
        ct state established,related accept # handle 9
        ct state invalid drop # handle 10
        jump filter_FORWARD_ZONES # handle 11
        reject with icmpx admin-prohibited # handle 12
    }
    chain filter_OUTPUT { # handle 3
        type filter hook output priority 10; policy accept;
    }
}
EOF

# firewalld.conf
cat > "test-data/${SOSDIR}/etc/firewalld/firewalld.conf" << 'EOF'
DefaultZone=public
CleanupOnExit=yes
Lockdown=no
IPv6_rpfilter=yes
LogDenied=off
FirewallBackend=nftables
FlushAllOnReload=yes
AllowZoneDrifting=no
EOF

create_fixture "test-firewall-sosreport-active"

################################################################################
# Test: Network Interfaces - SCC (supportconfig) format
# Tests interface detection, DHCP/static, accelerated networking in network.txt
################################################################################
echo ""
echo "=== Creating test-network-interfaces-scc.tar.xz ==="
mkdir -p test-data
cat > test-data/network.txt << 'SCCEOF'
#==[ Command ]======================================#
# /sbin/ip addr show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:0d:3a:12:34:56 brd ff:ff:ff:ff:ff:ff
    inet 10.0.0.4/24 brd 10.0.0.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::20d:3aff:fe12:3456/64 scope link
       valid_lft forever preferred_lft forever
3: eth1: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 1500 qdisc mq master eth0 state UP group default qlen 1000
    link/ether 00:0d:3a:12:34:57 brd ff:ff:ff:ff:ff:ff

#==[ Command ]======================================#
# /sbin/ethtool -i eth0
driver: hv_netvsc
version: 5.4.0
firmware-version: N/A
bus-info: vmbus:xxx-yyy
supports-statistics: yes

#==[ Command ]======================================#
# /sbin/ethtool -i eth1
driver: mlx5_core
version: 5.8-3.0.7
firmware-version: 16.35.2000
bus-info: 0000:00:02.0
supports-statistics: yes

#==[ Configuration File ]======================================#
# /etc/sysconfig/network/ifcfg-eth0
BOOTPROTO='dhcp'
STARTMODE='onboot'
CLOUD_NETCONFIG_MANAGE='yes'

#==[ Configuration File ]======================================#
# /etc/sysconfig/network/ifcfg-eth1
BOOTPROTO='static'
IPADDR='10.0.0.10'
NETMASK='255.255.255.0'
STARTMODE='hotplug'
SCCEOF
create_fixture "test-network-interfaces-scc"

################################################################################
# Test: Network Interfaces - SOS report format with MANA driver
# Tests MANA detection and DHCP config in separate SOS files
################################################################################
echo ""
echo "=== Creating test-network-interfaces-sos-mana.tar.xz ==="
SOSDIR="sos_commands"
mkdir -p "test-data/${SOSDIR}/networking"
mkdir -p "test-data/etc/sysconfig/network-scripts"

cat > "test-data/${SOSDIR}/networking/ip_-o_addr" << 'EOF'
1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
2: eth0    inet 10.1.0.5/24 brd 10.1.0.255 scope global dynamic noprefixroute eth0\       valid_lft 86399sec preferred_lft 86399sec
3: enP30832s1    inet 10.1.0.5/24 brd 10.1.0.255 scope global dynamic noprefixroute enP30832s1\       valid_lft 86399sec preferred_lft 86399sec
1: lo    inet6 ::1/128 scope host \       valid_lft forever preferred_lft forever
2: eth0    inet6 fe80::1234:abcd:ef01:2345/64 scope link \       valid_lft forever preferred_lft forever
EOF

cat > "test-data/${SOSDIR}/networking/ip_-s_-d_link" << 'EOF'
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00 promiscuity 0 minmtu 0 maxmtu 0 addrgenmode eui64 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 60:45:bd:12:34:56 brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 65521 addrgenmode eui64 numtxqueues 64 numrxqueues 64 gso_max_size 62780 gso_max_segs 44
3: enP30832s1: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 1500 qdisc mq master eth0 state UP mode DEFAULT group default qlen 1000
    link/ether 60:45:bd:12:34:57 brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 9706 addrgenmode eui64 numtxqueues 64 numrxqueues 64 gso_max_size 62780 gso_max_segs 44
EOF

cat > "test-data/${SOSDIR}/networking/ethtool_-i_eth0" << 'EOF'
driver: hv_netvsc
version: N/A
firmware-version: N/A
bus-info: {c6a23e40-1234-5678-abcd-ef0123456789}
supports-statistics: yes
supports-test: no
supports-eeprom-access: no
supports-register-dump: yes
supports-priv-flags: no
EOF

cat > "test-data/${SOSDIR}/networking/ethtool_-i_enP30832s1" << 'EOF'
driver: mana
version: N/A
firmware-version: N/A
bus-info: 7870:00:01.0
supports-statistics: yes
supports-test: no
supports-eeprom-access: no
supports-register-dump: no
supports-priv-flags: no
EOF

cat > "test-data/etc/sysconfig/network-scripts/ifcfg-eth0" << 'EOF'
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=dhcp
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=eth0
UUID=abc12345-6789-def0-1234-567890abcdef
DEVICE=eth0
ONBOOT=yes
EOF
create_fixture "test-network-interfaces-sos-mana"

# === Vmcore / Kernel Crash Dump test fixtures ===

echo ""
echo "=== Creating test-vmcore-crashes.tar.xz ==="
# Simulates a sosreport with vmcore crash dumps under /var/crash/
mkdir -p test-data/var/crash/127.0.0.1-2026-02-13-03:48:00
cat > test-data/var/crash/127.0.0.1-2026-02-13-03:48:00/vmcore-dmesg.txt << 'VMCORE1'
[1402779.794755] RBP: 00007ffd130716b0 R08: 0000000000000000 R09: 000055afb46cc04a
[1402779.794758] Call Trace:
[1402779.794758]  <NMI>
[1402779.794759]  ? nmi_cpu_backtrace.cold.8+0x36/0x4f
[1402779.794760]  ? nmi_handle+0x63/0x110
[1402779.794760]  ? default_do_nmi+0x49/0x110
[1402779.794762]  ? entry_SYSCALL_64+0x20/0x29
[1402779.794763]  </NMI>
[1402779.795694] Kernel panic - not syncing: hung_task: blocked tasks
[1402779.799668] CPU: 2 PID: 71 Comm: khungtaskd Kdump: loaded Not tainted 4.18.0-553.89.1.el8_10.x86_64 #1
[1402779.804715] Hardware name: Microsoft Corporation Virtual Machine/Virtual Machine, BIOS 090008  12/07/2018
[1402779.810167] Call Trace:
[1402779.811613]  dump_stack+0x41/0x60
[1402779.813585]  panic+0xe7/0x2ac
[1402779.815436]  watchdog+0x25c/0x2f0
[1402779.817475]  ? hungtask_pm_notify+0x50/0x50
[1402779.819840]  kthread+0x134/0x150
[1402779.822015]  ? set_kthread_struct+0x50/0x50
[1402779.824325]  ret_from_fork+0x35/0x40
[1402779.827475] Kernel Offset: 0x31800000 from 0xffffffff81000000
VMCORE1

mkdir -p test-data/var/crash/127.0.0.1-2025-10-05-09:02:28
cat > test-data/var/crash/127.0.0.1-2025-10-05-09:02:28/vmcore-dmesg.txt << 'VMCORE2'
[1597907.803447]  </NMI>
[1597907.803448]  do_sys_openat2+0x19a/0x2b0
[1597907.803449]  do_sys_open+0x4b/0x80
[1597907.803449]  do_syscall_64+0x5b/0x1a0
[1597907.804298] Kernel panic - not syncing: hung_task: blocked tasks
[1597907.807824] CPU: 2 PID: 71 Comm: khungtaskd Kdump: loaded Not tainted 4.18.0-553.75.1.el8_10.x86_64 #1
[1597907.812843] Hardware name: Microsoft Corporation Virtual Machine/Virtual Machine, BIOS 090008  12/07/2018
[1597907.817822] Call Trace:
[1597907.819308]  dump_stack+0x41/0x60
[1597907.821112]  panic+0xe7/0x2ac
[1597907.823058]  watchdog+0x25c/0x2f0
[1597907.825156]  ? hungtask_pm_notify+0x50/0x50
[1597907.827669]  kthread+0x134/0x150
[1597907.829724]  ? set_kthread_struct+0x50/0x50
[1597907.832021]  ret_from_fork+0x35/0x40
VMCORE2

mkdir -p test-data/sos_commands/kdump
cat > test-data/sos_commands/kdump/kdumpctl_status << 'KDSTATUS'
kdump: Kdump is operational
KDSTATUS

cat > test-data/sos_commands/kdump/ls_-alZR_.var.crash << 'CRASHLS'
/var/crash:
total 4
drwxr-xr-x.  4 root root system_u:object_r:kdump_crash_t:s0  154 Feb 13 03:48 .
drwxr-xr-x. 22 root root system_u:object_r:var_t:s0         4096 Mar 17  2022 ..
drwxr-xr-x.  2 root root system_u:object_r:unlabeled_t:s0     67 Oct  5 09:02 127.0.0.1-2025-10-05-09:02:28
drwxr-xr-x.  2 root root system_u:object_r:unlabeled_t:s0     67 Feb 13 03:48 127.0.0.1-2026-02-13-03:48:00

/var/crash/127.0.0.1-2025-10-05-09:02:28:
total 735368
drwxr-xr-x. 2 root root system_u:object_r:unlabeled_t:s0          67 Oct  5 09:02 .
drwxr-xr-x. 4 root root system_u:object_r:kdump_crash_t:s0       154 Feb 13 03:48 ..
-rw-------. 1 root root system_u:object_r:unlabeled_t:s0       50098 Oct  5 09:02 kexec-dmesg.log
-rw-------. 1 root root system_u:object_r:unlabeled_t:s0   752719997 Oct  5 09:02 vmcore
-rw-------. 1 root root system_u:object_r:unlabeled_t:s0      240185 Oct  5 09:02 vmcore-dmesg.txt

/var/crash/127.0.0.1-2026-02-13-03:48:00:
total 1320564
drwxr-xr-x. 2 root root system_u:object_r:unlabeled_t:s0           67 Feb 13 03:48 .
drwxr-xr-x. 4 root root system_u:object_r:kdump_crash_t:s0        154 Feb 13 03:48 ..
-rw-------. 1 root root system_u:object_r:unlabeled_t:s0        50470 Feb 13 03:48 kexec-dmesg.log
-rw-------. 1 root root system_u:object_r:unlabeled_t:s0   1351110790 Feb 13 03:48 vmcore
-rw-------. 1 root root system_u:object_r:unlabeled_t:s0      1082635 Feb 13 03:48 vmcore-dmesg.txt
CRASHLS

mkdir -p test-data/etc
cat > test-data/etc/kdump.conf << 'KDCONF'
# kdump configuration
path /var/crash
core_collector makedumpfile -l --message-level 7 -d 31
failure_action shell
KDCONF

create_fixture "test-vmcore-crashes"

################################################################################
# Vmcore edge-cases: empty kdump status, no-vmcore listing, no-date crash,
# timestamp-free dmesg ending with ---[ ... ]--- (exercises every branch)
################################################################################
echo ""
echo "=== Creating test-vmcore-edge-cases.tar.xz ==="

# vmcore-dmesg WITHOUT date in directory path → crash.date stays null
# Also no timestamp prefixes so "---[ end ... ]---" terminates the call trace
mkdir -p test-data/var/crash/nodate-crash
cat > test-data/var/crash/nodate-crash/vmcore-dmesg.txt << 'VMCORE_NODATE'
Linux version 5.14.0-362.el9.x86_64
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
CPU: 0 PID: 1 Comm: swapper/0 Kdump: loaded Not tainted 5.14.0-362.el9.x86_64 #1
Hardware name: Microsoft Corporation Virtual Machine/Virtual Machine, BIOS 090008  12/07/2018
Call Trace:
 <TASK>
 mount_block_root+0x1f0/0x220
 prepare_namespace+0x136/0x170
 kernel_init_freeable+0x2a4/0x2d0
 kernel_init+0x1a/0x130
 </TASK>
Kernel Offset: disabled
VMCORE_NODATE

# vmcore-dmesg WITH valid date → when sorted with the nodate crash, exercises
# the !a.date / !b.date null-date sort guards
mkdir -p "test-data/var/crash/127.0.0.1-2026-01-20-15:30:00"
cat > "test-data/var/crash/127.0.0.1-2026-01-20-15:30:00/vmcore-dmesg.txt" << 'VMCORE_DATED'
[300.000001] Kernel panic - not syncing: Fatal exception in interrupt
[300.000005] CPU: 3 PID: 0 Comm: swapper/3 Kdump: loaded Not tainted 5.14.0-362.el9.x86_64 #1
[300.000010] Hardware name: Microsoft Corporation Virtual Machine/Virtual Machine, BIOS 090008  12/07/2018
[300.000015] Call Trace:
[300.000016]  die+0x5/0x50
[300.000017]  do_trap+0x80/0x100
[300.000018]  do_error_trap+0x65/0x80
VMCORE_DATED

# Empty kdump status → parseKdumpStatus returns null (covers empty-content branch)
mkdir -p test-data/sos_commands/kdump
touch test-data/sos_commands/kdump/kdumpctl_status

# Crash listing with no vmcore files → parseCrashListing returns null
cat > test-data/sos_commands/kdump/ls_-alZR_.var.crash << 'CRASHLS_EMPTY'
/var/crash:
total 0
drwxr-xr-x. 2 root root system_u:object_r:var_t:s0    6 Jan  1 00:00 .
drwxr-xr-x. 22 root root system_u:object_r:var_t:s0 4096 Jan  1 00:00 ..
CRASHLS_EMPTY

# Basic kdump.conf
mkdir -p test-data/etc
cat > test-data/etc/kdump.conf << 'KDCONF_EDGE'
# kdump configuration
path /var/crash
core_collector makedumpfile -l --message-level 7 -d 31
default reboot
KDCONF_EDGE

create_fixture "test-vmcore-edge-cases"

################################################################################
# Test: InspectIaaSDisk storage - block devices from results.txt + fstab
# Tests that blockDevicesParser extracts Filesystem Status from results.txt
# and correlates UUIDs with fstab entries (including mismatches)
################################################################################
echo ""
echo "=== Creating test-inspect-iaas-disk-storage.zip ==="

python3 - "$FIXTURES_DIR" << 'INSPECT_STORAGE_PYEOF'
import zipfile, sys
fixtures_dir = sys.argv[1]
fixture_path = f"{fixtures_dir}/test-inspect-iaas-disk-storage.zip"

# results.txt with Filesystem Status providing device/uuid/fstype data
results_txt = """Execution start time: 14:30:00.

========== Request Info ==========
Storage Acct: md-storagetest.z45.blob.storage.azure.net
Container/Vhd: /storagecontainer/test
Manifest requested: diagnostic
Inspect service Operational ID: aabbccdd-1234-5678-90ab-cdef01234567
Guestfish version: 1.52.1.
========== End Request Info ==========

Filesystem Status:
/dev/sda1: xfs [uuid=11111111-aaaa-bbbb-cccc-111111111111]
/dev/sda14: unknown [uuid=]
/dev/sda15: vfat [uuid=ABCD-EF01]
/dev/rootvg/homelv: xfs [uuid=22222222-aaaa-bbbb-cccc-222222222222]
/dev/rootvg/rootlv: xfs [uuid=33333333-aaaa-bbbb-cccc-333333333333]
/dev/rootvg/tmplv: xfs [uuid=44444444-aaaa-bbbb-cccc-444444444444]
/dev/rootvg/usrlv: xfs [uuid=55555555-aaaa-bbbb-cccc-555555555555]
/dev/rootvg/varlv: xfs [uuid=66666666-aaaa-bbbb-cccc-666666666666]
Inspection Status:
/dev/rootvg/rootlv
Inspection Metadata for /dev/rootvg/rootlv
Type: linux
Distribution: rhel
Product Name: Red Hat Enterprise Linux release 8.8 (Ootpa)
Mount Points:
/: /dev/rootvg/rootlv
/var: /dev/rootvg/varlv
/usr: /dev/rootvg/usrlv
/tmp: /dev/rootvg/tmplv
/home: /dev/rootvg/homelv
/boot: /dev/sda1
/boot/efi: /dev/sda15
/mnt: /dev/disk/cloud/azure_resource-part1
Mounting /dev/rootvg/rootlv on / SUCCEEDED.
Mounting /dev/rootvg/varlv on /var SUCCEEDED.
Mounting /dev/rootvg/usrlv on /usr SUCCEEDED.
Mounting /dev/rootvg/tmplv on /tmp SUCCEEDED.
Mounting /dev/rootvg/homelv on /home SUCCEEDED.
Mounting /dev/sda1 on /boot SUCCEEDED.
Mounting /dev/sda15 on /boot/efi SUCCEEDED.
Mounting /dev/disk/cloud/azure_resource-part1 on /mnt FAILED.

Using manifest: diagnostic  [linux]
14:30:30  Executing Operation [1/1]: echo,### Done ###
### Done ###
"""

# fstab with intentional issues for testing UUID correlation:
# - OLD-UUID-DEAD references a UUID not present on disk (disk replaced)
# - 77777777 has fstype mismatch (fstab=ext4, disk=xfs)
# - GONE-UUID has no matching device at all
fstab_content = """#
# /etc/fstab
#
/dev/mapper/rootvg-rootlv /                       xfs     defaults        0 0
UUID=11111111-aaaa-bbbb-cccc-111111111111 /boot   xfs     defaults        0 0
UUID=ABCD-EF01          /boot/efi               vfat    defaults,uid=0,gid=0,umask=077,shortname=winnt 0 2
/dev/mapper/rootvg-homelv /home                   xfs     defaults        0 0
/dev/mapper/rootvg-tmplv /tmp                    xfs     defaults        0 0
/dev/mapper/rootvg-usrlv /usr                    xfs     defaults        0 0
/dev/mapper/rootvg-varlv /var                    xfs     defaults        0 0
/dev/disk/cloud/azure_resource-part1    /mnt    auto    defaults,nofail,x-systemd.requires=cloud-init.service,comment=cloudconfig       0       2
# Data disk was replaced - UUID no longer exists on any device
UUID=OLD-UUID-DEAD-DEAD-DEAD-DEADDEADDEAD /data xfs defaults,nofail 0 2
# UUID does not exist at all
UUID=GONE-UUID-0000-0000-0000-000000000000 /opt ext4 defaults,nofail 0 2
"""

redhat_release = "Red Hat Enterprise Linux release 8.8 (Ootpa)\\n"
hostname_content = "storagetest01\\n"

with zipfile.ZipFile(fixture_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('results.txt', results_txt)
    zf.writestr('diskinfo.txt', 'Disk info placeholder\\n')
    zf.writestr('device_0/etc/fstab', fstab_content)
    zf.writestr('device_0/etc/redhat-release', redhat_release)
    zf.writestr('device_0/etc/hostname', hostname_content)
INSPECT_STORAGE_PYEOF
echo "[OK] Created test-inspect-iaas-disk-storage.zip"

################################################################################
# Test: sosreport storage - block devices from lsblk/blkid + fstab
# Tests blockDevicesParser with sosreport sos_commands/block files including
# basic lsblk, lsblk -f, and blkid, correlated with /etc/fstab
################################################################################
echo ""
echo "=== Creating test-sosreport-storage.tar.xz ==="

# Standard sosreport directory structure
mkdir -p test-data/sos_commands/block
mkdir -p test-data/etc

# Basic lsblk output
cat > test-data/sos_commands/block/lsblk << 'EOF'
NAME            MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda               8:0    0    64G  0 disk 
├─sda1            8:1    0   500M  0 part /boot
├─sda2            8:2    0     1M  0 part 
├─sda14           8:14   0     4M  0 part 
├─sda15           8:15   0   495M  0 part /boot/efi
└─sda16           8:16   0    63G  0 part 
  ├─rootvg-rootlv  253:0  0    10G  0 lvm  /
  ├─rootvg-usrlv   253:1  0    10G  0 lvm  /usr
  ├─rootvg-varlv   253:2  0    10G  0 lvm  /var
  ├─rootvg-tmplv   253:3  0     5G  0 lvm  /tmp
  └─rootvg-homelv  253:4  0     5G  0 lvm  /home
sdb               8:16   0   128G  0 disk 
└─sdb1            8:17   0   128G  0 part /mnt
sdc               8:32   0   256G  0 disk 
└─sdc1            8:33   0   256G  0 part /data
EOF

# lsblk -f -a -l output (includes filesystem, UUID, mount info)
cat > 'test-data/sos_commands/block/lsblk_-f_-a_-l' << 'EOF'
NAME             FSTYPE FSVER LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
sda                                                                                      
sda1             xfs                aaaa1111-1111-1111-1111-aaaaaaaaaaaa  300M    40%    /boot
sda2                                                                                     
sda14                                                                                    
sda15            vfat   FAT32       EFI0-BOOT                            400M    19%    /boot/efi
sda16            LVM2_m LVM2                                                             
rootvg-rootlv    xfs                bbbb2222-2222-2222-2222-bbbbbbbbbbbb    7G    30%    /
rootvg-usrlv     xfs                cccc3333-3333-3333-3333-cccccccccccc    6G    40%    /usr
rootvg-varlv     xfs                dddd4444-4444-4444-4444-dddddddddddd    7G    30%    /var
rootvg-tmplv     xfs                eeee5555-5555-5555-5555-eeeeeeeeeeee    4G    20%    /tmp
rootvg-homelv    xfs                ffff6666-6666-6666-6666-ffffffffffff    4G    20%    /home
sdb                                                                                      
sdb1             ext4   1.0         1234abcd-abcd-abcd-abcd-1234abcd1234  110G     6%   /mnt
sdc                                                                                      
sdc1             xfs          data  5678ef01-ef01-ef01-ef01-5678ef015678  230G     6%   /data
EOF

# blkid output
cat > 'test-data/sos_commands/block/blkid_-c_.dev.null' << 'EOF'
/dev/sda1: UUID="aaaa1111-1111-1111-1111-aaaaaaaaaaaa" BLOCK_SIZE="512" TYPE="xfs" PARTUUID="p-sda1"
/dev/sda15: UUID="EFI0-BOOT" BLOCK_SIZE="512" TYPE="vfat" PARTUUID="p-sda15"
/dev/sda16: TYPE="LVM2_member" PARTUUID="p-sda16"
/dev/mapper/rootvg-rootlv: UUID="bbbb2222-2222-2222-2222-bbbbbbbbbbbb" BLOCK_SIZE="4096" TYPE="xfs"
/dev/mapper/rootvg-usrlv: UUID="cccc3333-3333-3333-3333-cccccccccccc" BLOCK_SIZE="4096" TYPE="xfs"
/dev/mapper/rootvg-varlv: UUID="dddd4444-4444-4444-4444-dddddddddddd" BLOCK_SIZE="4096" TYPE="xfs"
/dev/mapper/rootvg-tmplv: UUID="eeee5555-5555-5555-5555-eeeeeeeeeeee" BLOCK_SIZE="4096" TYPE="xfs"
/dev/mapper/rootvg-homelv: UUID="ffff6666-6666-6666-6666-ffffffffffff" BLOCK_SIZE="4096" TYPE="xfs"
/dev/sdb1: UUID="1234abcd-abcd-abcd-abcd-1234abcd1234" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="p-sdb1"
/dev/sdc1: UUID="5678ef01-ef01-ef01-ef01-5678ef015678" BLOCK_SIZE="4096" TYPE="xfs" LABEL="data" PARTUUID="p-sdc1"
EOF

# fstab with known-good entries + one missing UUID + one fstype mismatch
cat > test-data/etc/fstab << 'EOF'
# /etc/fstab - sosreport storage test
/dev/mapper/rootvg-rootlv /                       xfs     defaults        0 1
UUID=aaaa1111-1111-1111-1111-aaaaaaaaaaaa /boot   xfs     defaults        0 2
UUID=EFI0-BOOT /boot/efi                          vfat    defaults        0 2
/dev/mapper/rootvg-usrlv /usr                      xfs     defaults        0 0
/dev/mapper/rootvg-varlv /var                      xfs     defaults        0 0
/dev/mapper/rootvg-tmplv /tmp                      xfs     defaults        0 0
/dev/mapper/rootvg-homelv /home                    xfs     defaults        0 0
UUID=1234abcd-abcd-abcd-abcd-1234abcd1234 /mnt    ext4    defaults,nofail 0 2
# Filesystem type mismatch: fstab says ext4, actual disk (sdc1) is xfs
UUID=5678ef01-ef01-ef01-ef01-5678ef015678 /data   ext4    defaults,nofail 0 2
# This UUID no longer exists on any disk
UUID=DEAD0000-0000-0000-0000-DEAD00000000 /backup ext4    defaults,nofail 0 2
EOF

# Add os-release for sosreport identification
cat > test-data/etc/os-release << 'EOF'
NAME="Red Hat Enterprise Linux"
VERSION="8.8 (Ootpa)"
ID="rhel"
VERSION_ID="8.8"
PRETTY_NAME="Red Hat Enterprise Linux 8.8 (Ootpa)"
EOF

create_fixture "test-sosreport-storage"

# =====================================================================
# InspectIaaSDisk ZIP fixture
# =====================================================================
echo ""
echo "=== Creating test-inspect-iaas-disk.zip ==="

# InspectIaaSDisk files are ZIP archives (not tar.xz), so we use python/zip directly
python3 - "$FIXTURES_DIR" << 'INSPECT_PYEOF'
import zipfile, sys
fixtures_dir = sys.argv[1]
fixture_path = f"{fixtures_dir}/test-inspect-iaas-disk.zip"

results_txt = """Execution start time: 20:46:49.

========== Request Info ==========
Storage Acct: md-testaccount.z45.blob.storage.azure.net
Container/Vhd: /testcontainer/abcd
Manifest requested: diagnostic
Inspect service Operational ID: 117c4d70-8c42-44c5-9f3e-cddeb3eb4264
Guestfish version: 1.52.1.
========== End Request Info ==========

Filesystem Status:
/dev/sda1: xfs [uuid=849d8772-f8d2-4698-8d69-53c316388aa8]
/dev/sda14: unknown [uuid=]
/dev/sda15: vfat [uuid=E1E6-DC77]
/dev/rootvg/homelv: xfs [uuid=49728169-a170-45f8-a201-4a379b58e421]
/dev/rootvg/rootlv: xfs [uuid=b6a91419-76de-400f-b28c-6eb44864e89f]
/dev/rootvg/tmplv: xfs [uuid=ff83b522-e9c1-4d94-98c9-5a9fe925a8e8]
/dev/rootvg/usrlv: xfs [uuid=d081f48e-8ab0-4512-b8c6-bd4180d2e13e]
/dev/rootvg/varlv: xfs [uuid=d73a5f17-6c3f-4cd6-b6b5-cea4b582aef2]
Inspection Status:
/dev/rootvg/rootlv
Inspection Metadata for /dev/rootvg/rootlv
Type: linux
Distribution: rhel
Product Name: Red Hat Enterprise Linux release 8.8 (Ootpa)
Mount Points:
/: /dev/rootvg/rootlv
/mnt: /dev/disk/cloud/azure_resource-part1
/var: /dev/rootvg/varlv
/usr: /dev/rootvg/usrlv
/tmp: /dev/rootvg/tmplv
/home: /dev/rootvg/homelv
/boot: /dev/sda1
/boot/efi: /dev/sda15
Mounting /dev/rootvg/rootlv on / SUCCEEDED.
Mounting /dev/disk/cloud/azure_resource-part1 on /mnt FAILED.
Mounting /dev/rootvg/varlv on /var SUCCEEDED.
Mounting /dev/rootvg/usrlv on /usr SUCCEEDED.
Mounting /dev/rootvg/tmplv on /tmp SUCCEEDED.
Mounting /dev/rootvg/homelv on /home SUCCEEDED.
Mounting /dev/sda1 on /boot SUCCEEDED.
Mounting /dev/sda15 on /boot/efi SUCCEEDED.


Using manifest: diagnostic  [linux]
20:47:21  Executing Operation [1/3]: echo,### Probing Directories ###
### Probing Directories ###
20:47:21  Executing Operation [2/3]: ll,/boot
20:47:21  Listing contents of /boot:
total 226040
drwxr-xr-x.  2 root root     4096 Oct 18 22:57 .
20:47:22  Executing Operation [3/3]: ll,/var/log
20:47:22  Listing contents of /var/log:
total 1000
drwxr-xr-x.  2 root root     4096 Oct 18 22:57 .
"""

fstab_content = """#
# /etc/fstab
# Created by anaconda on Thu Aug 18 07:45:40 2022
#
/dev/mapper/rootvg-rootlv /                       xfs     defaults        0 0
UUID=849d8772-f8d2-4698-8d69-53c316388aa8 /boot                   xfs     defaults        0 0
UUID=E1E6-DC77          /boot/efi               vfat    defaults,uid=0,gid=0,umask=077,shortname=winnt 0 2
/dev/mapper/rootvg-homelv /home                   xfs     defaults        0 0
/dev/mapper/rootvg-tmplv /tmp                    xfs     defaults        0 0
/dev/mapper/rootvg-usrlv /usr                    xfs     defaults        0 0
/dev/mapper/rootvg-varlv /var                    xfs     defaults        0 0
/dev/disk/cloud/azure_resource-part1    /mnt    auto    defaults,nofail,x-systemd.requires=cloud-init.service,comment=cloudconfig       0       2
"""

redhat_release = "Red Hat Enterprise Linux release 8.8 (Ootpa)\n"
hostname_content = "testvm001\n"

hosts_content = """127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
10.0.0.10   testvm001 testvm001.internal.cloudapp.net
10.0.0.11   testvm002 testvm002.internal.cloudapp.net
"""

waagent_conf = """#
# Microsoft Azure Linux Agent Configuration
#
Extensions.Enabled=y
Provisioning.Agent=auto
ResourceDisk.Format=n
ResourceDisk.EnableSwap=n
ResourceDisk.SwapSizeMB=2048
ResourceDisk.MountPoint=/mnt
OS.EnableFirewall=y
OS.EnableFIPS=n
OS.RootDeviceScsiTimeout=300
Logs.Verbose=n
Logs.Collect=n
AutoUpdate.Enabled=y
AutoUpdate.GAFamily=Prod
"""

messages_content = """2026-01-15T03:22:01.000000+00:00 testvm001 kernel: Linux version 4.18.0-477.27.1.el8_8.x86_64 (mockbuild@x86-vm-09.build.eng.example.com) (gcc version 8.5.0 20210514 (Red Hat 8.5.0-18)) #1 SMP Thu Aug 31 10:29:22 EDT 2025
2026-01-15T03:22:05.000000+00:00 testvm001 kernel: Command line: BOOT_IMAGE=(hd0,gpt2)/vmlinuz-4.18.0-477.27.1.el8_8.x86_64 root=/dev/mapper/rootvg-rootlv ro crashkernel=auto
2026-01-15T03:22:30.000000+00:00 testvm001 cloud-init[1234]: ci-info: ++++++++++++++++++++++++++++++++++++++Net device info+++++++++++++++++++++++++++++++++++++++
2026-01-15T03:22:30.000001+00:00 testvm001 cloud-init[1234]: ci-info: +--------+------+-----------------------------+---------------+--------+-------------------+
2026-01-15T03:22:30.000002+00:00 testvm001 cloud-init[1234]: ci-info: | Device |  Up  |           Address           |      Mask     | Scope  |     Hw-Address    |
2026-01-15T03:22:30.000003+00:00 testvm001 cloud-init[1234]: ci-info: +--------+------+-----------------------------+---------------+--------+-------------------+
2026-01-15T03:22:30.000004+00:00 testvm001 cloud-init[1234]: ci-info: |  eth0  | True |         10.0.0.99           | 255.255.255.0 | global | 00:11:22:33:44:55 |
2026-01-15T03:22:30.000005+00:00 testvm001 cloud-init[1234]: ci-info: |   lo   | True |          127.0.0.1          |   255.0.0.0   |  host  |         .         |
2026-01-15T03:22:30.000006+00:00 testvm001 cloud-init[1234]: ci-info: +--------+------+-----------------------------+---------------+--------+-------------------+
2026-01-15T03:22:30.000007+00:00 testvm001 cloud-init[1234]: ci-info: +++++++++++++++++++++++++++++++Route IPv4 info+++++++++++++++++++++++++++++++
2026-01-15T08:15:33.000000+00:00 testvm001 systemd[1]: Shutting down...
2026-01-15T08:15:45.000000+00:00 testvm001 kernel: Linux version 4.18.0-477.27.1.el8_8.x86_64 (mockbuild@x86-vm-09.build.eng.example.com) (gcc version 8.5.0 20210514 (Red Hat 8.5.0-18)) #1 SMP Thu Aug 31 10:29:22 EDT 2025
2026-01-15T08:16:10.000000+00:00 testvm001 cloud-init[2634]: ci-info: ++++++++++++++++++++++++++++++++++++++Net device info+++++++++++++++++++++++++++++++++++++++
2026-01-15T08:16:10.000001+00:00 testvm001 cloud-init[2634]: ci-info: +--------+------+-----------------------------+---------------+--------+-------------------+
2026-01-15T08:16:10.000002+00:00 testvm001 cloud-init[2634]: ci-info: | Device |  Up  |           Address           |      Mask     | Scope  |     Hw-Address    |
2026-01-15T08:16:10.000003+00:00 testvm001 cloud-init[2634]: ci-info: +--------+------+-----------------------------+---------------+--------+-------------------+
2026-01-15T08:16:10.000004+00:00 testvm001 cloud-init[2634]: ci-info: |  eth0  | True |         10.0.0.4            | 255.255.254.0 | global | 00:0d:3a:ab:cd:ef |
2026-01-15T08:16:10.000005+00:00 testvm001 cloud-init[2634]: ci-info: |  eth0  | True | fe80::20d:3aff:feab:cdef/64 |       .       |  link  | 00:0d:3a:ab:cd:ef |
2026-01-15T08:16:10.000006+00:00 testvm001 cloud-init[2634]: ci-info: |  eth1  | True | fe80::20d:3aff:feab:cdef/64 |       .       |  link  | 00:0d:3a:ab:cd:ef |
2026-01-15T08:16:10.000007+00:00 testvm001 cloud-init[2634]: ci-info: |   lo   | True |          127.0.0.1          |   255.0.0.0   |  host  |         .         |
2026-01-15T08:16:10.000008+00:00 testvm001 cloud-init[2634]: ci-info: |   lo   | True |           ::1/128           |       .       |  host  |         .         |
2026-01-15T08:16:10.000009+00:00 testvm001 cloud-init[2634]: ci-info: +--------+------+-----------------------------+---------------+--------+-------------------+
2026-01-15T08:16:10.000010+00:00 testvm001 cloud-init[2634]: ci-info: +++++++++++++++++++++++++++++++Route IPv4 info+++++++++++++++++++++++++++++++
2026-02-10T14:33:12.000000+00:00 testvm001 kernel: java invoked oom-killer: gfp_mask=0x6200ca(GFP_HIGHUSER_MOVABLE), order=0
2026-02-10T14:33:12.100000+00:00 testvm001 kernel: Out of memory: Killed process 12345 (java) total-vm:8192000kB, anon-rss:7654321kB, file-rss:0kB, shmem-rss:0kB, UID:1000 pgtables:15012kB oom_score_adj:0
2026-02-18T22:05:44.000000+00:00 testvm001 kernel: XFS (sdb1): Internal error xfs_iget_cache_miss at line 355 of file fs/xfs/xfs_icache.c. Caller xfs_iget+0x15c/0x240
2026-02-19T04:10:01.000000+00:00 testvm001 kernel: XFS (sdk4): Found unrecovered unlinked inode 0xb75 in AG 0x4.  Initiating recovery.
2026-02-20T01:45:22.000000+00:00 testvm001 systemd[1]: You are in emergency mode. After logging in, type \"journalctl -xb\" to view
"""

ifcfg_eth0 = """DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
NM_CONTROLLED=no
"""

ifcfg_eth1 = """DEVICE=eth1
BOOTPROTO=static
IPADDR=10.0.0.50
PREFIX=24
ONBOOT=yes
TYPE=Ethernet
USERCTL=no
IPV6INIT=no
NM_CONTROLLED=no
"""

firewalld_conf = """# firewalld config file
DefaultZone=public
MinimalMark=100
CleanupOnExit=yes
Lockdown=no
IPv6_rpfilter=yes
IndividualCalls=no
LogDenied=off
FirewallBackend=nftables
"""

dnf_log = """2024-11-17T09:27:25+0000 INFO Installed: python3-azure-mgmt-compute-18.0.0-1.el8.noarch
2024-11-17T09:27:26+0000 INFO Installed: python3-azure-identity-1.5.0-1.el8.noarch
2024-11-17T09:27:27+0000 INFO Installed: python3-azure-core-1.22.1-1.el8.noarch
2024-11-17T09:28:00+0000 INFO Installed: fence-agents-azure-arm-4.10.0-55.el8_9.3.x86_64
2024-11-17T09:28:01+0000 INFO Installed: resource-agents-4.9.0-44.el8.x86_64
"""

# Azure VM extension HandlerStatus files (JSON)
handler_status_defender = '{"name": "Microsoft.Azure.AzureDefenderForServers.MDE.Linux", "version": "1.0.9.2", "status": "NotReady", "code": 1009, "message": "[ExtensionOperationError] Non-zero exit code: 1, /var/lib/waagent/Microsoft.Azure.AzureDefenderForServers.MDE.Linux-1.0.9.2/MDE-installer.sh", "supports_multi_config": false, "extension_status": null}'

handler_status_backup = '{"name": "Microsoft.Azure.RecoveryServices.VMSnapshotLinux", "version": "1.0.9225.0", "status": "Ready", "code": 0, "message": "Plugin enabled", "supports_multi_config": false, "extension_status": null}'

handler_status_patch = '{"name": "Microsoft.CPlat.Core.LinuxPatchExtension", "version": "1.6.64", "status": "Ready", "code": 0, "message": "Plugin enabled", "supports_multi_config": false, "extension_status": null}'

handler_status_runcommand = '{"name": "Microsoft.CPlat.Core.RunCommandLinux", "version": "1.0.11", "status": "Ready", "code": 0, "message": "Plugin enabled", "supports_multi_config": false, "extension_status": null}'

with zipfile.ZipFile(fixture_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('results.txt', results_txt)
    zf.writestr('diskinfo.txt', 'Disk info placeholder\n')
    zf.writestr('device_0/etc/fstab', fstab_content)
    zf.writestr('device_0/etc/redhat-release', redhat_release)
    zf.writestr('device_0/etc/hostname', hostname_content)
    zf.writestr('device_0/etc/hosts', hosts_content)
    zf.writestr('device_0/etc/waagent.conf', waagent_conf)
    zf.writestr('device_0/var/log/messages', messages_content)
    zf.writestr('device_0/etc/sysconfig/network-scripts/ifcfg-eth0', ifcfg_eth0)
    zf.writestr('device_0/etc/sysconfig/network-scripts/ifcfg-eth1', ifcfg_eth1)
    zf.writestr('device_0/etc/firewalld/firewalld.conf', firewalld_conf)
    zf.writestr('device_0/var/log/dnf.log', dnf_log)
    zf.writestr('device_0/var/lib/waagent/Microsoft.Azure.AzureDefenderForServers.MDE.Linux-1.0.9.2/config/HandlerStatus', handler_status_defender)
    zf.writestr('device_0/var/lib/waagent/Microsoft.Azure.RecoveryServices.VMSnapshotLinux-1.0.9225.0/config/HandlerStatus', handler_status_backup)
    zf.writestr('device_0/var/lib/waagent/Microsoft.CPlat.Core.LinuxPatchExtension-1.6.64/config/HandlerStatus', handler_status_patch)
    zf.writestr('device_0/var/lib/waagent/Microsoft.CPlat.Core.RunCommandLinux-1.0.11/config/HandlerStatus', handler_status_runcommand)
INSPECT_PYEOF
echo "[OK] Created test-inspect-iaas-disk.zip"

echo "=== Creating test-inspect-iaas-disk-cluster.zip ==="

python3 - "$FIXTURES_DIR" << 'INSPECT_CLUSTER_PYEOF'
import zipfile, sys
fixtures_dir = sys.argv[1]
fixture_path = f"{fixtures_dir}/test-inspect-iaas-disk-cluster.zip"

results_txt = """Execution start time: 10:12:30.

========== Request Info ==========
Storage Acct: md-clustertest.z45.blob.storage.azure.net
Container/Vhd: /clustercontainer/efgh
Manifest requested: diagnostic
Inspect service Operational ID: 99a1b2c3-d4e5-6f78-90ab-cdef01234567
Guestfish version: 1.52.1.
========== End Request Info ==========

Filesystem Status:
/dev/sda1: xfs [uuid=aaa11111-1111-1111-1111-111111111111]
/dev/sda15: vfat [uuid=B00B-1234]
/dev/rootvg/rootlv: xfs [uuid=bbb22222-2222-2222-2222-222222222222]
Inspection Status:
/dev/rootvg/rootlv
Inspection Metadata for /dev/rootvg/rootlv
Type: linux
Distribution: sles
Product Name: SUSE Linux Enterprise Server 15 SP5
Mount Points:
/: /dev/rootvg/rootlv
/boot: /dev/sda1
/boot/efi: /dev/sda15
Mounting /dev/rootvg/rootlv on / SUCCEEDED.
Mounting /dev/sda1 on /boot SUCCEEDED.
Mounting /dev/sda15 on /boot/efi SUCCEEDED.
"""

hosts_content = """127.0.0.1   localhost
::1         localhost
# Cluster nodes
10.0.1.10   hananode01 hananode01.internal.cloudapp.net
10.0.1.11   hananode02 hananode02.internal.cloudapp.net
10.0.1.20   hanamajority hanamajority.internal.cloudapp.net
"""

corosync_conf = """totem {
    version: 2
    secauth: on
    crypto_hash: sha1
    crypto_cipher: aes256
    cluster_name: hacluster
    clear_node_high_bit: yes
    token: 30000
    token_retransmits_before_loss_const: 10
    join: 60
    consensus: 36000
    max_messages: 20
    transport: udpu
    interface {
        ringnumber: 0
        bindnetaddr: 10.0.1.0
        mcastport: 5405
        ttl: 1
    }
}

logging {
    fileline: off
    to_logfile: yes
    to_syslog: yes
    logfile: /var/log/cluster/corosync.log
    debug: off
    timestamp: on
    logger_subsys {
        subsys: QUORUM
        debug: off
    }
}

quorum {
    provider: corosync_votequorum
    expected_votes: 2
    two_node: 1
}

nodelist {
    node {
        ring0_addr: 10.0.1.10
        name: hananode01
        nodeid: 1
    }
    node {
        ring0_addr: 10.0.1.11
        name: hananode02
        nodeid: 2
    }
}
"""

fstab_content = """#
# /etc/fstab
#
/dev/mapper/rootvg-rootlv /                       xfs     defaults        0 0
UUID=aaa11111-1111-1111-1111-111111111111 /boot   xfs     defaults        0 0
UUID=B00B-1234          /boot/efi               vfat    defaults        0 2
"""

sles_release = "SUSE Linux Enterprise Server 15 (s390x)\nVERSION = 15\nPATCHLEVEL = 5\n"

ifcfg_eth0_suse = """BOOTPROTO='dhcp'
MTU=''
REMOTE_IPADDR=''
STARTMODE='auto'
CLOUD_NETCONFIG_MANAGE='yes'
"""

cloud_init_output = """ci-info: ++++++++++++++++++++++++++++++++++++++Net device info+++++++++++++++++++++++++++++++++++++++
ci-info: +--------+------+-----------------------------+---------------+--------+-------------------+
ci-info: | Device |  Up  |           Address           |      Mask     | Scope  |     Hw-Address    |
ci-info: +--------+------+-----------------------------+---------------+--------+-------------------+
ci-info: |  eth0  | True |         10.0.1.10           | 255.255.255.0 | global | 60:45:bd:12:34:56 |
ci-info: |  eth0  | True | fe80::6245:bdff:fe12:3456/64 |       .       |  link  | 60:45:bd:12:34:56 |
ci-info: |   lo   | True |          127.0.0.1          |   255.0.0.0   |  host  |         .         |
ci-info: |   lo   | True |           ::1/128           |       .       |  host  |         .         |
ci-info: +--------+------+-----------------------------+---------------+--------+-------------------+
ci-info: +++++++++++++++++++++++++++++++Route IPv4 info+++++++++++++++++++++++++++++++
ci-info: +-------+-----------------+-----------+-----------------+-----------+-------+
ci-info: | Route |   Destination   |  Gateway  |     Genmask     | Interface | Flags |
ci-info: +-------+-----------------+-----------+-----------------+-----------+-------+
ci-info: |   0   |     0.0.0.0     | 10.0.1.1  |     0.0.0.0     |    eth0   |   UG  |
ci-info: |   1   |    10.0.1.0     |  0.0.0.0  |  255.255.255.0  |    eth0   |   U   |
ci-info: |   2   |  168.63.129.16  | 10.0.1.1  | 255.255.255.255 |    eth0   |  UGH  |
ci-info: |   3   | 169.254.169.254 | 10.0.1.1  | 255.255.255.255 |    eth0   |  UGH  |
ci-info: +-------+-----------------+-----------+-----------------+-----------+-------+
"""

zypper_history = """# zypp history v1
2021-03-08 15:31:22|radd   |fe6aa9d27ce|dir:/usr/src/packages/SOURCES/repos/SUSE%3ASLE-15-SP1%3AUpdate/standard|
2021-03-08 15:31:22|command|root@hananode01|'zypper' 'install' '--auto-agree-with-licenses' 'pacemaker' 'corosync'|
2021-03-08 15:31:23|install|pacemaker|2.1.7+20231219.0f7f88312-150600.4.7|x86_64||SLE-HA-Product|abc123|
2021-03-08 15:31:23|install|corosync|2.4.6-150300.12.10.1|x86_64||SLE-HA-Product|def456|
2021-03-08 15:31:24|install|resource-agents|4.13.0+git6.ae50f94f-150600.2.2|x86_64||SLE-HA-Product|ghi789|
2021-03-08 15:31:24|install|fence-agents-azure-arm|4.12.1+git.1677142927.bf55c675-150500.4.19.1|noarch||SLE-HA-Product|jkl012|
2021-03-08 15:31:25|install|cloud-netconfig-azure|1.15-150000.25.26.1|noarch||SLE-Module-Public-Cloud|mno345|
2021-03-08 15:31:25|install|python3-azure-mgmt-compute|18.0.0-150100.6.11.2|noarch||SLE-Module-Public-Cloud|pqr678|
2021-03-08 15:31:25|install|python3-azure-core|1.22.1-150100.3.7.2|noarch||SLE-Module-Public-Cloud|stu901|
2021-03-08 15:31:26|install|sbd|1.5.2+20241209.5946119-150500.3.3.2|x86_64||SLE-HA-Product|vwx234|
"""

with zipfile.ZipFile(fixture_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('results.txt', results_txt)
    zf.writestr('diskinfo.txt', 'Disk info placeholder\n')
    zf.writestr('device_0/etc/fstab', fstab_content)
    zf.writestr('device_0/etc/SuSE-release', sles_release)
    zf.writestr('device_0/etc/hostname', 'hananode01\n')
    zf.writestr('device_0/etc/hosts', hosts_content)
    zf.writestr('device_0/etc/corosync/corosync.conf', corosync_conf)
    zf.writestr('device_0/etc/sysconfig/network/network/ifcfg-eth0', ifcfg_eth0_suse)
    zf.writestr('device_0/var/log/cloud-init-output.log', cloud_init_output)
    zf.writestr('device_0/var/log/zypp/history', zypper_history)
INSPECT_CLUSTER_PYEOF
echo "[OK] Created test-inspect-iaas-disk-cluster.zip"

################################################################################
# InspectIaaSDisk SLES ZIP fixture
# Used by unix.spec.js tests for SLES-specific InspectIaaSDisk parsing:
#   - results.txt with SLES distribution, mount successes/failures
#   - os-release, fstab with HANA mounts, sysctl.conf, sysctl.d
#   - waagent.conf, waagent.log with categorised errors/warnings
#   - Azure VM extension HandlerStatus files
#   - sysconfig network interface (ifcfg-eth0)
################################################################################
echo ""
echo "=== Creating test-inspect-iaas-disk-sles.zip ==="

python3 - "$FIXTURES_DIR" << 'INSPECT_SLES_PYEOF'
import zipfile, sys
fixtures_dir = sys.argv[1]
fixture_path = f"{fixtures_dir}/test-inspect-iaas-disk-sles.zip"

results_txt = """Execution start time: 18:12:51.

========== Request Info ==========
Storage Acct: md-djzwkqttxnxb.z50.blob.storage.azure.net
Container/Vhd: /jhfcb3s4xnxv/abcd
Manifest requested: diagnostic
Inspect service Operational ID: fc5d80d2-86aa-4b1f-a601-1d59ae66eba7
Guestfish version: 1.57.5.
========== End Request Info ==========

Filesystem Status:
/dev/sda1: unknown [uuid=]
/dev/sda2: vfat [uuid=4150-8F0C]
/dev/sda3: xfs [uuid=e98ca93f-ca1e-497e-a071-6157e9b1b704]
/dev/sda4: xfs [uuid=3b92cd1e-e4ff-498d-b4a1-3cf4710b9e84]
Inspection Status:
/dev/sda4
Inspection Metadata for /dev/sda4
Type: linux
Distribution: sles
Product Name: SUSE Linux Enterprise Server 15 SP6
Mount Points:
/: /dev/sda4
/mnt: /dev/disk/cloud/azure_resource-part1
/boot: /dev/sda3
/boot/efi: /dev/sda2
Mounting /dev/sda4 on / SUCCEEDED.
Mounting /dev/disk/cloud/azure_resource-part1 on /mnt FAILED.
Mounting /dev/sda3 on /boot SUCCEEDED.
Mounting /dev/sda2 on /boot/efi SUCCEEDED.


Using manifest: diagnostic  [linux]
18:13:11  Executing Operation [1/3]: echo,### Probing Directories ###
### Probing Directories ###
18:13:12  Executing Operation [2/3]: ll,/boot
18:13:12  Listing contents of /boot:
total 151204
drwxr-xr-x  4 root root     4096 Feb 19 08:01 .
drwxr-xr-x 25 root root     4096 Apr 21  2024 ..
-rw-r--r--  1 root root 14191584 Jun 12  2024 vmlinuz-6.4.0-150600.21-default
18:13:13  Executing Operation [3/3]: ll,/var/log
18:13:13  Listing contents of /var/log:
total 90924
drwxr-xr-x 23 root root    16384 Feb 20 16:23 .
drwxr-xr-x 11 root root      175 Feb 15 09:29 ..
drwxr-xr-x  8 root root      310 Mar 29  2025 azure
-rw-r--r--  1 root root   185883 Feb 20 16:21 cloud-init-output.log
-rw-r-----  1 root root  4284310 Feb 20 16:21 cloud-init.log
-rw-r-----  1 root root   734311 Feb 20 16:16 messages
"""

diskinfo_txt = """Filesystem      Size  Used Avail Use% Mounted on
/dev/root       4.0G  455M  3.3G  12% /
/dev            592M     0  592M   0% /dev
shmfs           600M     0  600M   0% /dev/shm
tmpfs           240M  308K  240M   1% /run
/dev/sda4        39G   12G   28G  30% /sysroot
/dev/sda3      1014M  162M  853M  16% /sysroot/boot
/dev/sda2       512M  336K  512M   1% /sysroot/boot/efi
"""

fstab_content = """UUID=3b92cd1e-e4ff-498d-b4a1-3cf4710b9e84 / xfs defaults 0 0
UUID=e98ca93f-ca1e-497e-a071-6157e9b1b704 /boot xfs defaults 0 0
UUID=4150-8F0C /boot/efi vfat defaults 0 0
UUID=7a9e73d4-8de4-4eea-b71c-9bf061c3ac58 /hana/data xfs nofail,noatime,nodiratime,logbsize=256k 0 0
UUID=3c468c3c-f109-4afe-8817-9d3b98fe752d /hana/log xfs nofail,noatime,nodiratime,logbsize=64k 0 0
UUID=302db8c5-2c48-45ef-a9b3-d4a4a7a1aff7 /hana/shared xfs nofail,noatime,nodiratime 0 0
UUID=c2b3591b-c75b-4b4d-81d0-07bb200be71c /usr/sap xfs nofail,noatime,nodiratime 0 0
/dev/disk/cloud/azure_resource-part1    /mnt    auto    defaults,nofail,x-systemd.requires=cloud-init.service,_netdev,comment=cloudconfig       0       2
"""

os_release = """NAME="SLES"
VERSION="15-SP6"
VERSION_ID="15.6"
PRETTY_NAME="SUSE Linux Enterprise Server 15 SP6"
ID="sles"
ID_LIKE="suse"
ANSI_COLOR="0;32"
CPE_NAME="cpe:/o:suse:sles:15:sp6"
"""

hostname_content = "PH1LDBI02\n"

hosts_content = """127.0.0.1 localhost
::1 localhost
10.100.1.10 PH1LDBI02
168.63.129.16 metadata.azure.com
"""

ifcfg_eth0 = """BOOTPROTO='dhcp'
STARTMODE='onboot'
CLOUD_NETCONFIG_MANAGE='yes'
"""

sysctl_conf = """net.core.rmem_max=629145
net.core.wmem_max=4194304
"""

sysctl_sap = """fs.aio-max-nr=18446744073709551615
vm.memory_failure_early_kill=1
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_window_scaling=1
net.core.somaxconn=4096
vm.swappiness=15
vm.dirty_bytes=629145600
vm.dirty_background_bytes=314572800
"""

waagent_conf = """Provisioning.Enabled=y
Extensions.Enabled=y
Provisioning.UseCloudInit=n
Provisioning.DeleteRootPassword=y
ResourceDisk.Format=y
ResourceDisk.Filesystem=ext4
ResourceDisk.MountPoint=/mnt
ResourceDisk.EnableSwap=y
ResourceDisk.SwapSizeMB=2048
OS.EnableFirewall=y
AutoUpdate.Enabled=n
"""

messages_log = """Feb 20 16:21:01 PH1LDBI02 systemd[1]: Starting Azure Linux Agent...
Feb 20 16:21:02 PH1LDBI02 python3[1234]: 2026/02/20 16:21:02.123456 INFO MonitorHandler Azure Enhanced Monitoring agent for SAP enabled
Feb 20 16:21:03 PH1LDBI02 kernel: [    0.000000] Linux version 6.4.0-150600.21-default (geeko@buildhost) (gcc-13 (SUSE Linux)) #1 SMP PREEMPT_DYNAMIC
Feb 20 16:22:00 PH1LDBI02 wickedd-dhcp4[567]: eth0: Committed DHCPv4 lease with address 10.100.1.10
Feb 20 16:23:00 PH1LDBI02 systemd[1]: Started Pacemaker High Availability Cluster Manager.
Feb 20 16:23:01 PH1LDBI02 corosync[890]: [TOTEM] A processor joined or left the membership and a new membership was formed.
"""

waagent_log = """2026-02-19T06:05:04.123456Z INFO ExtHandler ExtHandler [HEARTBEAT] Agent WALinuxAgent-2.14.0.1 is running as the goal state agent [DEBUG HeartbeatCounter: 1;HeartbeatId: E4ADA91F-9183-4119-BA91-DF4FB32320D7;UpdateGSErrors: 0;AutoUpdate: 0;UpdateMode: SelfUpdate;]
2026-02-19T06:11:48.234567Z INFO ExtHandler ExtHandler Fetched new vmSettings [HostGAPlugin correlation ID: 66b50f65-1914-44ca-af6e-d3ae6fcfab4d eTag: 15590114118628401591 source: FastTrack]
2026-02-19T06:11:48.345678Z INFO ExtHandler ExtHandler ProcessExtensionsGoalState started [etag_15590114118628401591 channel: HostGAPlugin source: FastTrack activity: 1d0e7c19-a12b-441c-8a04-1783c6908355]
2026-02-19T06:20:14.456789Z INFO ExtHandler [Microsoft.Azure.RecoveryServices.VMSnapshotLinux-1.0.9225.0] Target handler state: enabled [etag_15590114118628401591]
2026-02-19T06:20:14.567890Z INFO ExtHandler [Microsoft.Azure.RecoveryServices.VMSnapshotLinux-1.0.9225.0] [Enable] current handler state is: enabled
2026-02-19T07:22:26.678901Z ERROR ExtHandler ExtHandler Error fetching the goal state: [ProtocolError] GET vmSettings [correlation ID: 16758839-2b40-40d5-80cd-10572beda761 eTag: 1234] [Internal error: 500]
2026-02-19T07:28:24.789012Z ERROR ExtHandler ExtHandler Error fetching the goal state: [ProtocolError] [Wireserver Exception] [HttpError] [HTTP Failed] GET http://168.63.129.16/machine/?comp=goalstate [HTTP Retry]
2026-02-19T08:10:28.890123Z WARNING MonitorHandler ExtHandler [PERIODIC] [IMDS_CONNECTION_ERROR] Unable to connect to IMDS endpoint 169.254.169.254
2026-02-19T08:28:52.901234Z ERROR ExtHandler ExtHandler Event: name=Microsoft.Azure.AzureDefenderForServers.MDE.Linux, op=Enable, message=[ExtensionOperationError] Non-zero exit code: 52, /var/lib/waagent/Microsoft.Azure.AzureDefenderForServers.MDE.Linux-1.0.9.2/MDE.Linux.sh enable
2026-02-19T08:44:26.012345Z ERROR Daemon Daemon Failed to mount resource disk [ResourceDiskError] Could not mount /dev/sdc1 after syncing partition table: [32] mount: /mnt: /dev/sdc1 already mounted on /mnt.
2026-02-19T09:27:24.123456Z WARNING ExtHandler ExtHandler [PERIODIC] The status reported by the extension Microsoft.CPlat.Core.LinuxPatchExtension-1.6.64(Sequence number 17), was in an incorrect format and the agent could not parse it correctly. Failed due to [ExtensionStatusError] Expecting value: line 1 column 1 (char 0)
2026-02-19T09:27:24.234567Z WARNING ExtHandler ExtHandler [PERIODIC] This status is being reported by the Guest Agent since no status file was reported by extension Microsoft.Azure.AzureDefenderForServers.MDE.Linux: [ExtensionStatusError] Status file /var/lib/waagent/Microsoft.Azure.AzureDefenderForServers.MDE.Linux-1.0.9.2/status/51.status does not exist
2026-02-19T10:36:32.345678Z INFO ExtHandler ExtHandler Extension status: [("Microsoft.Azure.AzureDefenderForServers.MDE.Linux", "transitioning"), ("Microsoft.Azure.RecoveryServices.VMSnapshotLinux", "success"), ("Microsoft.CPlat.Core.LinuxPatchExtension", "error"), ("Microsoft.CPlat.Core.RunCommandLinux", "success")]
2026-02-19T12:10:11.456789Z INFO Daemon Daemon Agent WALinuxAgent-2.14.0.1 launched with command "/usr/bin/python3 -u /usr/sbin/waagent -run-exthandlers" is successfully running
2026-02-19T15:29:33.567890Z INFO ExtHandler ExtHandler [HEARTBEAT] Agent WALinuxAgent-2.14.0.1 is running as the goal state agent [DEBUG HeartbeatCounter: 2;HeartbeatId: E4ADA91F-9183-4119-BA91-DF4FB32320D7;UpdateGSErrors: 0;AutoUpdate: 0;UpdateMode: SelfUpdate;]
2026-02-20T16:11:27.678901Z WARNING Daemon Daemon Failed to mount resource disk. Attempting to format and retry mount. [mount: /mnt: /dev/sdc1 already mounted on /mnt.
2026-02-20T16:23:39.789012Z INFO ExtHandler ExtHandler ProcessExtensionsGoalState completed [etag_5312742817917373788 125692 ms]
"""

mde_status = '{"handlerName":"Microsoft.Azure.AzureDefenderForServers.MDE.Linux","handlerVersion":"1.0.9.2","status":"Ready","code":0,"formattedMessage":{"lang":"en-US","message":"MDE agent installed successfully"}}'

snapshot_status = '{"handlerName":"Microsoft.Azure.RecoveryServices.VMSnapshotLinux","handlerVersion":"1.0.9225.0","status":"Ready","code":0,"formattedMessage":{"lang":"en-US","message":"Snapshot extension ready"}}'

workload_status = '{"handlerName":"Microsoft.Azure.RecoveryServices.WorkloadBackup.AzureBackupLinuxWorkload","handlerVersion":"2.0.0.5","status":"Ready","code":0,"formattedMessage":{"lang":"en-US","message":"Workload backup handler ready"}}'

patch_status = '{"handlerName":"Microsoft.CPlat.Core.LinuxPatchExtension","handlerVersion":"1.6.64","status":"Ready","code":0,"formattedMessage":{"lang":"en-US","message":"Patch extension ready"}}'

runcmd_status = '{"handlerName":"Microsoft.CPlat.Core.RunCommandLinux","handlerVersion":"1.0.11","status":"Ready","code":0,"formattedMessage":{"lang":"en-US","message":"RunCommand handler ready"}}'

with zipfile.ZipFile(fixture_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('results.txt', results_txt)
    zf.writestr('diskinfo.txt', diskinfo_txt)
    zf.writestr('device_0/etc/fstab', fstab_content)
    zf.writestr('device_0/etc/hostname', hostname_content)
    zf.writestr('device_0/etc/hosts', hosts_content)
    zf.writestr('device_0/etc/os-release', os_release)
    zf.writestr('device_0/etc/sysconfig/network/network/ifcfg-eth0', ifcfg_eth0)
    zf.writestr('device_0/etc/sysctl.conf', sysctl_conf)
    zf.writestr('device_0/etc/sysctl.d/sap_hdb_sysctl.conf', sysctl_sap)
    zf.writestr('device_0/etc/waagent.conf', waagent_conf)
    zf.writestr('device_0/var/log/messages', messages_log)
    zf.writestr('device_0/var/log/waagent.log', waagent_log)
    zf.writestr('device_0/var/lib/waagent/Microsoft.Azure.AzureDefenderForServers.MDE.Linux-1.0.9.2/config/HandlerStatus', mde_status)
    zf.writestr('device_0/var/lib/waagent/Microsoft.Azure.RecoveryServices.VMSnapshotLinux-1.0.9225.0/config/HandlerStatus', snapshot_status)
    zf.writestr('device_0/var/lib/waagent/Microsoft.Azure.RecoveryServices.WorkloadBackup.AzureBackupLinuxWorkload-2.0.0.5/config/HandlerStatus', workload_status)
    zf.writestr('device_0/var/lib/waagent/Microsoft.CPlat.Core.LinuxPatchExtension-1.6.64/config/HandlerStatus', patch_status)
    zf.writestr('device_0/var/lib/waagent/Microsoft.CPlat.Core.RunCommandLinux-1.0.11/config/HandlerStatus', runcmd_status)
INSPECT_SLES_PYEOF
echo "[OK] Created test-inspect-iaas-disk-sles.zip"

# Test: mtab vs fstab comparison
# Tests detection of mounts in mtab that are NOT in fstab
echo ""
echo "=== Creating test-mtab-comparison.tar.xz ==="
mkdir -p test-data/etc

# fstab - defines a few mounts
cat > test-data/etc/fstab << 'EOF'
# /etc/fstab
UUID=1234-5678-9abc-def0 / xfs defaults 0 1
UUID=aaaa-bbbb-cccc-dddd /boot ext4 defaults 0 2
UUID=2222-3333-4444-5555 /home xfs defaults,nofail 0 0
UUID=7777-8888-9999-0000 /mnt xfs defaults,nofail 0 0
EOF

# mtab - has extra mounts not in fstab (hand-mounted + cluster-managed)
cat > test-data/etc/mtab << 'EOF'
/dev/sda2 / xfs rw,relatime,attr2 0 0
/dev/sda1 /boot ext4 rw,relatime 0 0
/dev/sdb1 /home xfs rw,relatime,nofail 0 0
/dev/sdc1 /mnt xfs rw,relatime,nofail 0 0
/dev/sdd1 /data ext4 rw,relatime 0 0
10.0.0.5:/shared /sapmnt nfs rw,hard,rsize=65536,wsize=65536 0 0
/dev/mapper/datavg-hanalv /hana/data xfs rw,relatime,attr2 0 0
/dev/mapper/logvg-hanaloglv /hana/log xfs rw,relatime,attr2 0 0
sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
tmpfs /run tmpfs rw,nosuid,nodev 0 0
devtmpfs /dev devtmpfs rw,nosuid,relatime 0 0
EOF

create_fixture "test-mtab-comparison"

################################################################################
# Test: FIPS Enabled (sosreport style)
# Tests detection of FIPS mode from multiple indicators:
#   - sos_commands/crypto/fips-mode-setup_--check
#   - proc/cmdline with fips=1
#   - sysctl crypto.fips_enabled = 1
#   - crypto-policies/config = FIPS
#   - installed-rpms with dracut-fips
#   - waagent.conf with OS.EnableFIPS=y
################################################################################
echo ""
echo "=== Creating test-fips-enabled.tar.xz ==="

# fips-mode-setup --check output
mkdir -p test-data/sos_commands/crypto
cat > "test-data/sos_commands/crypto/fips-mode-setup_--check" << 'EOF'
FIPS mode is enabled.
EOF

# Kernel command line with fips=1
mkdir -p test-data/proc
cat > test-data/proc/cmdline << 'EOF'
BOOT_IMAGE=(hd0,gpt2)/vmlinuz-4.18.0-425.3.1.el8.x86_64 root=UUID=abcdef01-2345-6789-abcd-ef0123456789 ro crashkernel=auto fips=1 rd.lvm.lv=rootvg/rootlv console=tty0 console=ttyS0,115200n8
EOF

# Kernel sysctl with crypto.fips_enabled = 1
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
crypto.fips_enabled = 1
kernel.hostname = fips-test-host
kernel.osrelease = 4.18.0-425.3.1.el8.x86_64
kernel.ostype = Linux
vm.swappiness = 10
net.ipv4.tcp_keepalive_time = 7200
EOF

# Crypto policy set to FIPS
mkdir -p test-data/etc/crypto-policies
cat > test-data/etc/crypto-policies/config << 'EOF'
FIPS
EOF

# installed-rpms with dracut-fips
mkdir -p test-data/sos_commands/rpm
cat > test-data/sos_commands/rpm/installed-rpms << 'EOF'
WALinuxAgent-2.9.1.1-3.el8_8.noarch      Wed Aug  2 00:00:00 2023
bash-4.4.20-4.el8_6.x86_64               Mon Oct 17 00:00:00 2022
cloud-init-23.1.1-12.el8.noarch          Thu Oct  5 00:00:00 2023
crypto-policies-20230731-1.git94f0e2c.el8.noarch Thu Oct  5 00:00:00 2023
dracut-fips-049-233.git20240115.el8.x86_64 Wed Jan 17 00:00:00 2024
fipscheck-1.5.0-5.el8.x86_64             Thu Oct  5 00:00:00 2023
fipscheck-lib-1.5.0-5.el8.x86_64         Thu Oct  5 00:00:00 2023
kernel-4.18.0-425.3.1.el8.x86_64         Thu Nov  3 00:00:00 2022
openssl-1.1.1k-12.el8_9.x86_64           Mon Dec 18 00:00:00 2023
EOF

# waagent.conf with FIPS enabled
mkdir -p test-data/etc
cat > test-data/etc/waagent.conf << 'EOF'
# Microsoft Azure Linux Agent Configuration
OS.EnableFIPS=y
Provisioning.Agent=auto
ResourceDisk.Format=n
EOF

# os-release for distro detection
cat > test-data/etc/os-release << 'EOF'
NAME="Red Hat Enterprise Linux"
VERSION="8.8 (Ootpa)"
ID="rhel"
ID_LIKE="fedora"
VERSION_ID="8.8"
PRETTY_NAME="Red Hat Enterprise Linux 8.8 (Ootpa)"
EOF

create_fixture "test-fips-enabled"

################################################################################
# Test: FIPS Disabled (sosreport style)
# Tests detection when FIPS mode is explicitly disabled
################################################################################
echo ""
echo "=== Creating test-fips-disabled.tar.xz ==="

# fips-mode-setup --check output (disabled)
mkdir -p test-data/sos_commands/crypto
cat > "test-data/sos_commands/crypto/fips-mode-setup_--check" << 'EOF'
FIPS mode is disabled.
EOF

# Kernel command line without fips=1
mkdir -p test-data/proc
cat > test-data/proc/cmdline << 'EOF'
BOOT_IMAGE=(hd0,gpt2)/vmlinuz-4.18.0-425.3.1.el8.x86_64 root=UUID=abcdef01-2345-6789-abcd-ef0123456789 ro crashkernel=auto rd.lvm.lv=rootvg/rootlv console=tty0 console=ttyS0,115200n8
EOF

# Kernel sysctl with crypto.fips_enabled = 0
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
crypto.fips_enabled = 0
kernel.hostname = nofips-test-host
kernel.osrelease = 4.18.0-425.3.1.el8.x86_64
kernel.ostype = Linux
vm.swappiness = 10
net.ipv4.tcp_keepalive_time = 7200
EOF

# Crypto policy set to DEFAULT
mkdir -p test-data/etc/crypto-policies
cat > test-data/etc/crypto-policies/config << 'EOF'
DEFAULT
EOF

# installed-rpms without dracut-fips
mkdir -p test-data/sos_commands/rpm
cat > test-data/sos_commands/rpm/installed-rpms << 'EOF'
WALinuxAgent-2.9.1.1-3.el8_8.noarch      Wed Aug  2 00:00:00 2023
bash-4.4.20-4.el8_6.x86_64               Mon Oct 17 00:00:00 2022
cloud-init-23.1.1-12.el8.noarch          Thu Oct  5 00:00:00 2023
crypto-policies-20230731-1.git94f0e2c.el8.noarch Thu Oct  5 00:00:00 2023
kernel-4.18.0-425.3.1.el8.x86_64         Thu Nov  3 00:00:00 2022
openssl-1.1.1k-12.el8_9.x86_64           Mon Dec 18 00:00:00 2023
EOF

# waagent.conf without FIPS
mkdir -p test-data/etc
cat > test-data/etc/waagent.conf << 'EOF'
# Microsoft Azure Linux Agent Configuration
Provisioning.Agent=auto
ResourceDisk.Format=n
EOF

# os-release
cat > test-data/etc/os-release << 'EOF'
NAME="Red Hat Enterprise Linux"
VERSION="8.8 (Ootpa)"
ID="rhel"
ID_LIKE="fedora"
VERSION_ID="8.8"
PRETTY_NAME="Red Hat Enterprise Linux 8.8 (Ootpa)"
EOF

create_fixture "test-fips-disabled"

################################################################################
# Test: FIPS Inconsistent state (sosreport style)
# Tests detection when FIPS mode is in an inconsistent state:
#   fips-mode-setup says enabled but sysctl says disabled
################################################################################
echo ""
echo "=== Creating test-fips-inconsistent.tar.xz ==="

# fips-mode-setup reports inconsistent
mkdir -p test-data/sos_commands/crypto
cat > "test-data/sos_commands/crypto/fips-mode-setup_--check" << 'EOF'
FIPS mode is enabled.
Inconsistent state detected.
The current crypto policy (DEFAULT) does not match FIPS.
EOF

# Kernel command line WITH fips=1 (was set at boot)
mkdir -p test-data/proc
cat > test-data/proc/cmdline << 'EOF'
BOOT_IMAGE=(hd0,gpt2)/vmlinuz-4.18.0-425.3.1.el8.x86_64 root=UUID=abcdef01-2345-6789-abcd-ef0123456789 ro crashkernel=auto fips=1 rd.lvm.lv=rootvg/rootlv console=tty0 console=ttyS0,115200n8
EOF

# sysctl says FIPS enabled at kernel level
mkdir -p test-data/sos_commands/kernel
cat > test-data/sos_commands/kernel/sysctl_-a << 'EOF'
crypto.fips_enabled = 1
kernel.hostname = fips-inconsistent-host
kernel.osrelease = 4.18.0-425.3.1.el8.x86_64
kernel.ostype = Linux
vm.swappiness = 10
EOF

# But crypto policy is DEFAULT (not FIPS) - the inconsistency!
mkdir -p test-data/etc/crypto-policies
cat > test-data/etc/crypto-policies/config << 'EOF'
DEFAULT
EOF

# installed-rpms with dracut-fips
mkdir -p test-data/sos_commands/rpm
cat > test-data/sos_commands/rpm/installed-rpms << 'EOF'
WALinuxAgent-2.9.1.1-3.el8_8.noarch      Wed Aug  2 00:00:00 2023
dracut-fips-049-233.git20240115.el8.x86_64 Wed Jan 17 00:00:00 2024
kernel-4.18.0-425.3.1.el8.x86_64         Thu Nov  3 00:00:00 2022
EOF

# os-release
mkdir -p test-data/etc
cat > test-data/etc/os-release << 'EOF'
NAME="Red Hat Enterprise Linux"
VERSION="8.8 (Ootpa)"
ID="rhel"
ID_LIKE="fedora"
VERSION_ID="8.8"
PRETTY_NAME="Red Hat Enterprise Linux 8.8 (Ootpa)"
EOF

create_fixture "test-fips-inconsistent"

echo ""
echo "========================================="
echo "All test fixtures created successfully!"
echo "========================================="
echo ""
echo "Fixtures created in: $FIXTURES_DIR"
echo ""
echo "To run tests:"
echo "  npm install"
echo "  npm test"
