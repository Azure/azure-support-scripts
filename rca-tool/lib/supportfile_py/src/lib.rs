//! Python bindings for the Supportfile parser library.

use pyo3::prelude::*;
use supportfile_core::{
    parse_automation_events_json, parse_azure_extensions_json, parse_azure_site_recovery_json,
    parse_azure_vm_generation_json, parse_azure_vm_properties_json,
    parse_basic_environment_json, parse_block_devices_json,
    parse_btrfs_config_json, parse_chrony_makestep_json, parse_chrony_tracking_json,
    parse_cluster_events_json, parse_cluster_maintenance_mode_json, parse_cluster_status_json,
    parse_corosync_config_json, parse_crash_listing_json, parse_crypto_policies_json,
    parse_df_output_json, parse_distro_packages_json, parse_dlm_service_json,
    parse_emergency_mode_json, parse_eus_version_lock_json, parse_extfrag_json,
    parse_falcon_sensor_config_json, parse_falcon_sensor_json, parse_firewall_rules_json,
    parse_fips_mode_setup_json, parse_fstab_analysis_json, parse_fstab_json,
    parse_fstrim_json,
    parse_guardicore_agent_json, parse_hana_deadlocks_json, parse_hana_merge_errors_json,
    parse_hana_oom_json, parse_hana_savepoints_json, parse_huge_pages_json, parse_hv_balloon_json,
    parse_illumio_json, parse_inspect_disk_results_json, parse_involflt_kernel_version_json,
    parse_involflt_version_json, parse_kdump_conf_json,
    parse_kdump_status_json, parse_kernel_cmdline_json, parse_kernel_reboots_json,
    parse_kernel_tuning_json, parse_leapp_log_json, parse_leapp_report_json,
    parse_lvm_config_json, parse_ms_defender_config_json, parse_ms_defender_json,
    parse_mtab_analysis_json, parse_network_interfaces_json, parse_nfs_mounts_json,
    parse_oom_killer_json,
    parse_os_release_json, parse_pacemaker_high_cpu_json, parse_ptp_clock_source_json,
    parse_ptp_device_json, parse_raid_config_json, parse_package_distro_mismatch_json,
    parse_rhel_rhui_check_json,
    parse_rhui_config_json, parse_rhui_errors_json, parse_secure_boot_json,
    parse_ssh_service_issues_json,
    parse_selinux_json, parse_swap_space_json, parse_tuned_profile_json,
    parse_suse_cloud_register_json, parse_time_sync_json, parse_time_sync_service_json,
    parse_timedatectl_json, parse_trend_micro_json, parse_vmcore_dmesg_json,
    parse_vmcore_summary_json, parse_waagent_config_json, parse_waagent_log_json,
    parse_xfs_errors_json,
};

// ============================================================================
// Cluster (Pacemaker / Corosync)
// ============================================================================

/// Detect Pacemaker high CPU load events.
///
/// Scans Pacemaker controld log lines for ``notice: High CPU load detected: <value>``
/// messages and returns one record per occurrence.
///
/// Args:
///     content (str): Raw log text. Typical sources are ``pacemaker.log``,
///         ``messages``, ``localmessages``, or ``journalctl*`` outputs from a
///         supportconfig (SCC) or sosreport (SOS) archive.
///
/// Returns:
///     str: A JSON-encoded list. Each element has the shape
///     ``{"timestamp": str, "sourceNode": str, "cpuLoad": float,
///     "lineNumber": int, "rawLine": str}``. Returns ``"[]"`` when no
///     events are found.
///
/// Example:
///     >>> import json, supportfile
///     >>> log = "Jan 10 12:23:45 node01 pacemaker-controld[2404]: notice: High CPU load detected: 23.27\n"
///     >>> events = json.loads(supportfile.parse_high_cpu_events(log))
///     >>> events[0]["sourceNode"]
///     'node01'
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_high_cpu_events(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_pacemaker_high_cpu_json(content, source_path))
}

/// Detect Pacemaker / Corosync cluster lifecycle events.
///
/// Multi-file capable: when called repeatedly with rotated log content, the
/// caller can merge the resulting event lists. Detects node join / leave,
/// resource start / stop / failover, and fencing (STONITH) actions.
///
/// Args:
///     content (str): Raw text from ``pacemaker.log``, ``corosync.log``,
///         ``messages``, ``localmessages``, or ``journalctl*`` files
///         (including rotated ``.1``, ``.2.gz`` siblings).
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found": bool, "count": int, "events": [{"timestamp", "type",
///     "node", "resource", "rawLine", ...}]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_cluster_events(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_cluster_events_json(content, source_path))
}

/// Parse Pacemaker cluster status (DC, quorum, online/offline nodes).
///
/// Args:
///     content (str): Contents of ``cib.xml``, ``crm_mon*.txt``, ``ha.txt``,
///         or ``pcs_status``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found": bool, "clusterName": str|None, "dcNode": str|None,
///     "nodesConfigured": int|None, "resourcesConfigured": int|None,
///     "nodeStatuses": [{"name": str, "online": bool}], ...}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_cluster_status(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_cluster_status_json(content, source_path))
}

/// Parse ``corosync.conf`` totem and quorum settings.
///
/// Validates token / retransmit / consensus / transport values and quorum
/// configuration (``two_node``, ``expected_votes``, ``provider``). Emits
/// warnings for known-bad combinations.
///
/// Args:
///     content (str): Contents of ``corosync.conf`` (or the corosync section
///         of an aggregated ``ha.txt``).
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found": bool, "totem": {...}, "quorum": {...}, "warnings": [...]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_corosync_config(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_corosync_config_json(content, source_path))
}

/// Detect cluster-wide or per-resource maintenance mode.
///
/// Args:
///     content (str): Contents of ``cib.xml``, ``crm_mon*.txt``, or ``ha.txt``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found": bool, "clusterMaintenanceMode": bool,
///     "resourcesInMaintenance": [str], "warnings": [...]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_cluster_maintenance_mode(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_cluster_maintenance_mode_json(content, source_path))
}

// ============================================================================
// Automation (Ansible / Puppet / Chef)
// ============================================================================

/// Detect configuration-management tool executions in system logs.
///
/// Scans for Ansible (``ansible-command:``, ``ansible-setup:``), Puppet
/// (``puppet-agent:``, ``puppet apply``, ``puppet-run:``), and Chef
/// (``chef-client``, ``chef-solo``, ``chef-apply``) activity. Chef events
/// include up to 5 lines of context for key phases (Starting Chef,
/// Converging, FATAL, ERROR, ...).
///
/// Args:
///     content (str): Raw text from ``messages``, ``localmessages``,
///         ``syslog``, or ``journalctl*`` files.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found": bool, "count": int, "events": [{"timestamp", "lineNumber",
///     "toolType", "patternType", "command", "rawLine", "sourceFile"}]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_automation_events(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_automation_events_json(content, source_path))
}

// ============================================================================
// Azure VM metadata and agent
// ============================================================================

/// Extract Azure VM properties and infer billing model (PAYG vs BYOS).
///
/// Reads the IMDS (Instance Metadata Service) snapshot captured by the
/// support tooling. The billing model is determined by a two-rule cascade:
/// ``licenseType`` takes precedence (e.g. ``RHEL_BYOS``, ``SLES``,
/// ``UBUNTU_PRO``); ``billingCode`` is used as fallback (e.g.
/// ``Linux_IaaS_SUSE``, ``Linux_IaaS``).
///
/// Args:
///     content (str): Either JSON content from ``instance_metadata.json``
///         (sosreport) or the key-value text of ``public_cloud/metadata.txt``
///         (supportconfig).
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "vmSize", "publisher", "offer", "sku", "billingCode",
///     "licenseType", "billingModel", "detectionMethod", "osDiskType",
///     "dataDisks", "hasUltraDisk", "hasPremiumV2"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_azure_vm_properties(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_azure_vm_properties_json(content, source_path))
}

/// Classify Azure VM generation from ``vmSize`` and flag legacy generations.
///
/// Args:
///     content (str): IMDS JSON content or key-value metadata text.
///
/// Returns:
///     str: JSON object ``{"found", "vmSize", "vmGeneration",
///     "isLegacyGeneration", "recommendation"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_azure_vm_generation(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_azure_vm_generation_json(content, source_path))
}

/// Detect SUSE cloud registration server and infer billing model.
///
/// PAYG indicators: ``smt-azure``, ``susecloud.net``, ``update.suse.com``.
/// BYOS indicators: ``scc.suse.com`` and custom RMT servers.
///
/// Args:
///     content (str): Contents of ``public_cloud/cloudregister.txt``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "billingModel", "detectionMethod",
///     "registrationServer", "registrationType"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_suse_cloud_register(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_suse_cloud_register_json(content, source_path))
}

/// Detect UEFI Secure Boot state from the sosreport ``mokutil --sb-state``
/// capture (``sos_commands/boot/mokutil_--sb-state``).
///
/// Args:
///     content (str): Output of ``mokutil --sb-state``.
///     source_path (str): Optional source path for provenance.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "enabled", "supported",
///     "stateText", "sourcePath", "sourceLine"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_secure_boot(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_secure_boot_json(content, source_path))
}

/// Parse the Azure Linux Agent (waagent) configuration file.
///
/// Extracts settings from groups Extensions, Provisioning, ResourceDisk,
/// Firewall, FIPS, SCSI timeout, Logging, and AutoUpdate. Warnings are
/// raised when extensions are disabled, swap is enabled on the resource
/// disk, the OS firewall is disabled, or FIPS mode is enabled.
///
/// Args:
///     content (str): Contents of ``/etc/waagent.conf`` (INI-like
///         ``key=value``, no sections).
///
/// Returns:
///     str: JSON-encoded object ``{"found", "config": {...}, "warnings": [...]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_waagent_config(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_waagent_config_json(content, source_path))
}

/// Parse the Azure Linux Agent runtime log (``waagent.log``).
///
/// Extracts the agent version (and history of versions seen), goal-state
/// errors, extension enable/operation failures, resource disk errors, IMDS
/// connectivity errors, and a summary of extension status reports.
///
/// Args:
///     content (str): Contents of ``waagent.log`` (timestamped lines).
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "agentVersion", "agentVersionHistory", "errors",
///     "warnings", "goalStateErrors", "extensionErrors",
///     "resourceDiskErrors", "imdsErrors", "extensionStatusSummary",
///     "hasErrors", "hasWarnings"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_waagent_log(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_waagent_log_json(content, source_path))
}

/// Parse a single Azure VM extension status JSON document.
///
/// Reads one extension status file (such as those under
/// ``/var/lib/waagent/.../status/*.status``), maps the publisher/extension
/// name to a friendly label (Microsoft Defender for Endpoint, Azure Backup,
/// Azure Update Manager, Azure Monitor Agent, Run Command, ...), and reports
/// whether the extension is healthy (``status == "Ready"`` and ``code == 0``).
///
/// Args:
///     content (str): JSON content of a single ``*.status`` document.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "count", "events": [{"name", "label", "version",
///     "status", "code", "message", "healthy"}]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_azure_extensions(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_azure_extensions_json(content, source_path))
}

// ============================================================================
// Debugfs (Hyper-V balloon, memory fragmentation)
// ============================================================================

/// Parse the Hyper-V Dynamic Memory balloon driver status.
///
/// Computes committed and maximum memory from page counts and emits warnings
/// when ballooning is active (``pages_ballooned > 0``) or memory is near
/// capacity (``committed > 90% of max``).
///
/// Args:
///     content (str): Contents of ``sys/kernel/debug/hv-balloon`` (or
///         ``hv_balloon``).
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "hostVersion", "capabilities", "state", "stateText",
///     "pageSize", "pagesAdded", "pagesOnlined", "pagesBallooned",
///     "totalPagesCommitted", "maxDynamicPageCount", "committedMemoryGB",
///     "maxDynamicMemoryGB", "balloonedMemoryMB", "warnings", "rawContent"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_hv_balloon(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_hv_balloon_json(content, source_path))
}

/// Parse memory fragmentation indices per NUMA node and zone.
///
/// Reads ``extfrag_index`` / ``unusable_index`` values for orders 0-10
/// (4KiB through 4MiB page sizes) and flags high fragmentation at huge-page
/// orders (9+).
///
/// Args:
///     content (str): Contents of ``sys/kernel/debug/extfrag/extfrag_index``
///         or ``sys/kernel/debug/extfrag/unusable_index``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "zones": [{"node", "zone", "extfragIndex": [...],
///     "unusableIndex": [...]}], "warnings": [...], "rawContent"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_extfrag(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_extfrag_json(content, source_path))
}

// ============================================================================
// Kernel and system events
// ============================================================================

/// Detect ``You are in emergency mode`` events.
///
/// Args:
///     content (str): Raw text from ``messages``, ``localmessages``, or
///         ``journalctl*``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "count", "events": [{"timestamp", "lineNumber",
///     "rawLine", "sourceFile"}]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_emergency_mode(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_emergency_mode_json(content, source_path))
}

/// Detect kernel boot and reboot events.
///
/// Matches ``Linux version X.Y.Z`` boots, ``systemd ... Shutting down`` /
/// ``Starting Reboot`` events, and ``kernel: reboot:`` messages.
///
/// Args:
///     content (str): Raw log text.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"count", "events": [{"timestamp", "lineNumber", "kernelVersion",
///     "type", "rawLine"}]}`` where ``type`` is ``kernel_boot``,
///     ``systemd_shutdown``, or ``reboot_message``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_kernel_reboots(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_kernel_reboots_json(content, source_path))
}

/// Detect Out-of-Memory killer activity.
///
/// Finds actual OOM kills (``Out of memory: Kill process PID (name)``),
/// OOM invocations (``invoked oom-killer:``), post-kill cleanup
/// (``oom_reaper:``), and allocation failures (``Cannot allocate memory``).
///
/// Args:
///     content (str): Raw log text.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"count", "events": [{"timestamp", "lineNumber", "pid",
///     "processName", "score", "totalVM", "type", "rawLine"}]}`` where
///     ``type`` is ``oom_kill``, ``oom_invoked``, ``oom_reaper``, or
///     ``alloc_failure``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_oom_killer(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_oom_killer_json(content, source_path))
}

/// Detect critical XFS filesystem errors that require manual repair.
///
/// Matches ``Please unmount the filesystem and rectify the problem(s)``,
/// metadata/corruption detection, and filesystem shutdown messages.
///
/// Args:
///     content (str): Raw log text.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"count", "events": [{"timestamp", "lineNumber", "device",
///     "message", "rawLine"}]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_xfs_errors(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_xfs_errors_json(content, source_path))
}

// ============================================================================
// Networking
// ============================================================================

/// Parse firewall configuration (firewalld, nftables, iptables, ip6tables, ebtables).
///
/// Classifies the active firewall technology. Resolution priority:
/// firewalld running > nftables with non-empty ruleset > iptables with
/// parsed rules > ip6tables with parsed rules > none.
///
/// Args:
///     content (str): Contents of an SCC ``network.txt`` (aggregated,
///         section-delimited with ``#==[ Command ]===``) or any of the SOS
///         per-command files under ``sos_commands/firewalld/``,
///         ``sos_commands/firewall_tables/``, or sysconfig files such as
///         ``etc/sysconfig/iptables-config`` and ``etc/firewalld/firewalld.conf``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "firewalld": {...}, "iptables": {...}, "ip6tables": {...},
///     "ebtables": {...}, "nftables": {...}, "activeFirewall",
///     "warnings", "rawSections"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_firewall_rules(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_firewall_rules_json(content, source_path))
}

/// Build a unified view of network interfaces from IP / driver / config data.
///
/// Correlates ``ip addr``, ``ip -s -d link``, ``ethtool -i``, ``ifcfg-*``,
/// ``nmcli con show``, ``wicked ifstatus``, netplan YAML, and cloud-init
/// ``ci-info`` tables. Detects Azure Accelerated Networking via known
/// driver names (``mlx4_*``, ``mlx5_core``, ``mana``).
///
/// Args:
///     content (str): One file's content. Typical sources include SCC
///         ``network.txt``, SOS ``sos_commands/networking/*``, and config
///         files under ``etc/sysconfig/network-scripts/`` or ``etc/netplan/``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "interfaces": {<name>: {"name", "state", "mac", "mtu",
///     "ipv4": [...], "ipv6": [...], "driver", "driverInfo", "accelNet",
///     "bootproto", "master", "type"}}, "raw": {...}}``.
///
/// Note:
///     This is a multi-file parser; merge per-file outputs in the caller for
///     a full system view.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_network_interfaces(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_network_interfaces_json(content, source_path))
}

// ============================================================================
// Packages
// ============================================================================

/// Parse installed-package listings and validate Azure-critical versions.
///
/// Supports dpkg (``dpkg_-l``), dnf/yum installed lists, RPM listings
/// (``rpm.txt``, ``installed-rpms``, ``package-data``), zypper history, and
/// dnf/yum logs. For RPM-style sources it validates Azure-critical packages
/// against minimum version rules:
///
/// * ``fence-agents`` >= 4.4
/// * ``python3-azure-mgmt-compute`` >= 17.0
/// * ``python3-azure-identity`` >= 1.0
/// * ``cloud-netconfig-azure`` >= 1.3
/// * ``resource-agents`` >= 4.3
/// * ``python3-azure-core`` < 1.9 or > 1.22 (problematic range)
///
/// Args:
///     content (str): Package listing content.
///
/// Returns:
///     str: JSON-encoded object. RPM-validated:
///     ``{"found", "packages", "warnings"}``. Raw listings:
///     ``{"found", "isDpkg" | "isRpmRaw", "rawContent", "filename",
///     "packageCount"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_distro_packages(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_distro_packages_json(content, source_path))
}

/// Detect cross-distro and major-version package drift.
///
/// Examples:
/// * SUSE packages on a RHEL host
/// * ``.el7`` packages on a RHEL 9 host
///
/// Args:
///     content (str): Package listing content.
///     running_distro_id (str): Host distro ID (e.g. ``rhel``, ``sles``).
///     running_version_id (str): Host distro version (e.g. ``9.4``, ``15.6``).
///     source_path (str): Optional source path.
///
/// Returns:
///     str: JSON object ``{"found", "count", "mismatches": [...],
///     "runningDistroId", "runningVersionId"}``.
#[pyfunction]
#[pyo3(signature = (content, running_distro_id, running_version_id, source_path=""))]
fn parse_package_distro_mismatch(
    content: &str,
    running_distro_id: &str,
    running_version_id: &str,
    source_path: &str,
) -> PyResult<String> {
    Ok(parse_package_distro_mismatch_json(
        content,
        source_path,
        running_distro_id,
        running_version_id,
    ))
}

// ============================================================================
// System services
// ============================================================================

/// Detect SSH daemon start failures and ``/var/empty/sshd`` permission errors.
///
/// Args:
///     content (str): Raw log text (``messages``, ``journalctl*``).
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "count", "events": [{"timestamp", "lineNumber",
///     "rawLine"}]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_ssh_service_issues(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_ssh_service_issues_json(content, source_path))
}

/// Detect the DLM (Distributed Lock Manager) service enabled in systemd.
///
/// DLM enabled outside of Pacemaker control conflicts with cluster-managed
/// lock resources. Severity: ``error``.
///
/// Args:
///     content (str): Contents of systemd unit listings (``systemctl
///         list-unit-files``, ``systemd.txt``).
///
/// Returns:
///     str: JSON-encoded object ``{"found", "enabled", "warnings"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_dlm_service(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_dlm_service_json(content, source_path))
}

/// Detect the Azure Site Recovery ``involflt_start`` service.
///
/// Args:
///     content (str): Contents of systemd unit listings.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "enabled"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_azure_site_recovery(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_azure_site_recovery_json(content, source_path))
}

/// Detect the Guardicore micro-segmentation agent (``gc-agent``).
///
/// Args:
///     content (str): Contents of systemd unit listings.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "running", "details"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_guardicore_agent(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_guardicore_agent_json(content, source_path))
}

/// Detect Illumio security platform installation.
///
/// Args:
///     content (str): Contents of systemd unit listings.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "running", "details"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_illumio(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_illumio_json(content, source_path))
}

/// Detect Trend Micro Deep Security (``ds_agent.service``).
///
/// Args:
///     content (str): Contents of systemd unit listings.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "running", "details"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_trend_micro(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_trend_micro_json(content, source_path))
}

/// Detect CrowdStrike Falcon Sensor (``falcon-sensor`` RPM, ``/opt/CrowdStrike`` process).
///
/// Args:
///     content (str): RPM listing or process table content.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "installed", "running",
///     "version"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_falcon_sensor(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_falcon_sensor_json(content, source_path))
}

/// Inspect CrowdStrike Falcon Sensor configuration for SAP exclusions.
///
/// Returns warnings when SAP workload exclusions are not configured.
///
/// Args:
///     content (str): Contents of CrowdStrike / falcon configuration files.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "exclusions", "warnings"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_falcon_sensor_config(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_falcon_sensor_config_json(content, source_path))
}

/// Detect Microsoft Defender for Endpoint (``mdatp`` RPM, ``wdavdaemon``).
///
/// Args:
///     content (str): RPM listing or process table content.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "installed", "running",
///     "version"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_ms_defender(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_ms_defender_json(content, source_path))
}

/// Inspect Microsoft Defender configuration for SAP exclusions.
///
/// Args:
///     content (str): Contents of mdatp / defender configuration files.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "exclusions", "warnings"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_ms_defender_config(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_ms_defender_config_json(content, source_path))
}

/// Read the Azure Site Recovery ``involflt`` driver version from ``modinfo``.
///
/// Args:
///     content (str): Contents of ``modules.txt`` (modinfo section).
///
/// Returns:
///     str: JSON-encoded object ``{"version", "buildDate", "loaded",
///     "filename"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_involflt_version(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_involflt_version_json(content, source_path))
}

/// Read the Azure Site Recovery ``involflt`` driver version from kernel logs.
///
/// Args:
///     content (str): Contents of ``messages*.txt`` or ``boot.txt``.
///
/// Returns:
///     str: JSON-encoded object ``{"version", "source": "kernel_log"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_involflt_kernel_version(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_involflt_kernel_version_json(content, source_path))
}

// ============================================================================
// Storage
// ============================================================================

/// Parse LVM physical volumes, volume groups, and logical volumes.
///
/// Cross-validates each PV's VG reference against the VG list and flags
/// "Missing VG" and "PV Count Mismatch" warnings.
///
/// Args:
///     content (str): Contents of ``lvm.txt``, ``pvs.txt``, ``vgs.txt``,
///         ``lvs.txt``, or ``pv|vg|lvdisplay`` outputs.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "pvs": [...], "vgs": [...], "lvs": [...],
///     "warnings": [...], "rawOutput"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_lvm_config(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_lvm_config_json(content, source_path))
}

/// Parse ``/proc/mdstat`` RAID arrays.
///
/// Detects degraded state, faulty devices, and rebuild progress; emits
/// "Faulty Device" and "Degraded Array" warnings.
///
/// Args:
///     content (str): Contents of ``mdstat``, ``md-arrays.txt``,
///         ``mdadm.txt``, or ``proc/mdstat``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "arrays": [{"device", "state", "level", "devices",
///     "syncStatus"}], "warnings": [...], "rawOutput"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_raid_config(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_raid_config_json(content, source_path))
}

/// Parse BTRFS filesystem inventory and subvolume list.
///
/// Args:
///     content (str): Contents of ``btrfs.txt``, ``fs-btrfs.txt``,
///         ``btrfs-filesystem-show.txt``, or ``btrfs-subvolume-list.txt``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "filesystems": [{"label", "uuid", "devices",
///     "totalSize"}], "subvolumes": [...], "warnings": [...], "rawOutput"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_btrfs_config(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_btrfs_config_json(content, source_path))
}

/// Build a disk and partition inventory with UUID, filesystem type, and mounts.
///
/// Args:
///     content (str): Contents of ``lsblk``, ``lsblk_-f_-a_-l``,
///         ``blkid_-c_.dev.null``, or InspectIaaSDisk ``results.txt``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "disks", "partitions", "uuidMap", "deviceMap",
///     "mountPoints", "warnings", "rawOutput"}``.
///
/// Note:
///     Multi-file parser; merge results across input files in the caller.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_block_devices(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_block_devices_json(content, source_path))
}

/// Analyse ``/etc/fstab`` entries with mount-option classification.
///
/// Each entry is classified by ``sourceType`` (``uuid``, ``device``,
/// ``label``, ``network``) and flagged for ``hasNofail``,
/// ``isOsPartition``, ``isVirtualFs``, and ``needsNofail``. Missing-nofail
/// warnings include a link to the Azure fstab best-practices doc.
///
/// Args:
///     content (str): Contents of ``/etc/fstab`` or the fstab section of
///         ``fs-diskio.txt``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "entries", "uuidEntries", "deviceEntries",
///     "labelEntries", "warnings"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_fstab_analysis(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_fstab_analysis_json(content, source_path))
}

/// Parse ``df`` filesystem usage output.
///
/// Args:
///     content (str): Contents of ``df``, ``df_-aliT``, ``df_-al_``, or
///         the df section of ``fs-diskio.txt``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "filesystems": [...], "mountToUsage": {...}}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_df_output(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_df_output_json(content, source_path))
}

/// Compare mounted filesystems against fstab to find unmanaged mounts.
///
/// ``extraMounts`` lists mounts present in mtab but absent from fstab
/// (excluding virtual filesystems), indicating hand-mounted or
/// cluster-managed partitions.
///
/// Args:
///     content (str): Contents of ``/etc/mtab``, ``proc/mounts``,
///         ``proc/self/mounts``, ``mount_-l``, or the mount section of
///         ``fs-diskio.txt``.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "entries", "extraMounts", "rawContent"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_mtab_analysis(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_mtab_analysis_json(content, source_path))
}

/// Parse NFS mount entries from ``fstab`` or ``mount``/``mtab`` output and flag
/// suboptimal mount options (soft mounts, small ``rsize``/``wsize``, outdated
/// protocol versions, missing ``nconnect``).
///
/// Args:
///     content (str): Raw text of an ``fstab`` file or ``mount`` output, or an
///         SCC bundle that embeds either.
///     source_path (str): Optional path of the source file used for provenance.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "mounts", "warnings",
///     "source_path"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_nfs_mounts(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_nfs_mounts_json(content, source_path))
}

/// Detect SAP HANA savepoint activity in indexserver/nameserver trace files.
///
/// Args:
///     content (str): Contents of a HANA ``*.trc`` trace file.
///     source_path (str): Optional path of the source file used for provenance.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "count", "snapshot_count",
///     "savepoints", "warnings", "source_path"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_hana_savepoints(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_hana_savepoints_json(content, source_path))
}

/// Detect SAP HANA deadlock cycles in indexserver/nameserver trace files.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_hana_deadlocks(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_hana_deadlocks_json(content, source_path))
}

/// Detect SAP HANA out-of-memory events in indexserver/nameserver trace files.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_hana_oom(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_hana_oom_json(content, source_path))
}

/// Detect SAP HANA delta-merge / optimize-compression failures.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_hana_merge_errors(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_hana_merge_errors_json(content, source_path))
}

// ============================================================================
// OS identity
// ============================================================================

/// Fallback OS identification from supportconfig basic-environment.
///
/// Also detects SAP and EPIC product markers.
///
/// Args:
///     content (str): Contents of ``basic-environment.txt``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "osName", "osVersion",
///     "kernel", "hasSAP", "hasEPIC", ...}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_basic_environment(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_basic_environment_json(content, source_path))
}

/// Primary OS identification via ``/etc/os-release`` or distro release files.
///
/// Detects SLES, RHEL, Ubuntu, Oracle, Alma, and Rocky.
///
/// Args:
///     content (str): Contents of ``os-release``, ``sysinfo.txt``,
///         ``redhat-release``, ``centos-release``, ``SuSE-release``, or
///         ``system-release``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "id", "name", "version",
///     "versionId", "prettyName", ...}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_os_release(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_os_release_json(content, source_path))
}

/// Extract ``/etc/fstab`` entries with mount options.
///
/// Companion to :func:`parse_fstab_analysis` for callers that just need the
/// raw entries without classification.
///
/// Args:
///     content (str): Contents of ``/etc/fstab`` or the fstab section of
///         ``fs-diskio.txt``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "entries": [{"device",
///     "mountPoint", "fsType", "options", "dump", "pass"}]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_fstab(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_fstab_json(content, source_path))
}

// ============================================================================
// InspectIaaSDisk
// ============================================================================

/// Parse InspectIaaSDisk diagnostic output.
///
/// Extracts request info, filesystem status, OS metadata, mount points, and
/// mount failures.
///
/// Args:
///     content (str): Contents of an InspectIaaSDisk ``results.txt``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "requestInfo", "filesystem",
///     "osMetadata", "mountPoints", "mountFailures"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_inspect_disk_results(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_inspect_disk_results_json(content, source_path))
}

// ============================================================================
// Kernel tuning
// ============================================================================

/// Parse sysctl parameters from runtime output or static config files.
///
/// Flags SAP HANA and Azure network tuning settings.
///
/// Args:
///     content (str): Contents of ``env.txt``, ``sysctl.conf``,
///         ``sysctl.d/*.conf``, or ``sysctl_-a``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "params": {...},
///     "warnings": [...]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_kernel_tuning(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_kernel_tuning_json(content, source_path))
}

/// Report HugePages allocation (total, free, size).
///
/// Args:
///     content (str): Contents of ``proc/meminfo``,
///         ``basic-environment.txt``, or ``memory.txt``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "hugePagesTotal", "hugePagesFree",
///     "hugePageSize", ...}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_huge_pages(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_huge_pages_json(content, source_path))
}

// ============================================================================
// Time synchronisation (Azure PTP)
// ============================================================================

/// Detect ``hv_utils`` and PTP clock-source modules; check PHC index assignment.
///
/// Args:
///     content (str): Contents of ``env.txt``, ``boot.txt``, or relevant
///         ``proc/`` files.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "hvUtilsLoaded", "ptpDevices",
///     "phcIndex", ...}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_time_sync(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_time_sync_json(content, source_path))
}

/// Verify chrony / NTP is configured with ``refclock PHC /dev/ptp_hyperv``.
///
/// Args:
///     content (str): Contents of ``chrony.conf``, ``ntp.conf``, or files
///         under ``etc/chrony*`` / ``etc/ntp*``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "azurePtpConfigured",
///     "refclock", "warnings"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_ptp_clock_source(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_ptp_clock_source_json(content, source_path))
}

/// Detect which time-sync service (chrony, ntpd, systemd-timesyncd) is active.
///
/// Args:
///     content (str): Contents of ``ntp.txt``, ``chrony*``,
///         ``timekeeping.txt``, or systemd unit files.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "activeService",
///     "serviceState", "configFiles"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_time_sync_service(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_time_sync_service_json(content, source_path))
}

/// Parse ``timedatectl`` output (NTP enabled / synchronised, source).
///
/// Args:
///     content (str): Contents of ``ntp.txt``, ``timekeeping.txt``, or
///         ``timedatectl``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "ntpEnabled", "ntpSynchronized",
///     "ntpService", "timezone", ...}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_timedatectl(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_timedatectl_json(content, source_path))
}

/// Enumerate PTP devices and check for ``/dev/ptp_hyperv`` symlink.
///
/// Args:
///     content (str): Contents of ``env.txt``, ``boot.txt``, or relevant
///         ``proc/`` / ``dev/`` listings.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "devices": [...],
///     "hasHypervSymlink"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_ptp_device(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_ptp_device_json(content, source_path))
}

/// Parse ``chronyc tracking`` output (stratum, system time offset, leap status).
///
/// Args:
///     content (str): Contents of ``ntp.txt``, ``timekeeping.txt``, or
///         ``chronyc_tracking``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "stratum", "systemTimeOffset",
///     "leapStatus", "referenceId", ...}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_chrony_tracking(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_chrony_tracking_json(content, source_path))
}

/// Check whether ``makestep`` is configured in chrony for initial corrections.
///
/// Args:
///     content (str): Contents of ``chrony.conf`` or files under
///         ``etc/chrony*``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "makestepConfigured",
///     "makestepValue"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_chrony_makestep(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_chrony_makestep_json(content, source_path))
}

// ============================================================================
// RHUI (Red Hat Update Infrastructure)
// ============================================================================

/// Detect Azure RHUI repositories (EUS, non-EUS, E4S, SAP) and dnf plugins.
///
/// Args:
///     content (str): Contents of ``updates.txt`` or files under
///         ``yum.repos.d/`` and ``plugin.conf.d/``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "rhuiType", "repos": [...],
///     "plugins": [...]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_rhui_config(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_rhui_config_json(content, source_path))
}

/// Read the ``releasever`` lock value used for EUS pinning.
///
/// Args:
///     content (str): Contents of ``updates.txt``, ``yum.conf``,
///         ``dnf.conf``, or ``releasever``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "releasever", "source"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_eus_version_lock(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_eus_version_lock_json(content, source_path))
}

/// Check RHUI client install, TLS certificates, and content set entitlements.
///
/// Args:
///     content (str): Contents of ``updates.txt``, files under ``rhui/``,
///         or ``rpm_-qa``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "clientInstalled",
///     "certificateValid", "entitlements", "warnings"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_rhel_rhui_check(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_rhel_rhui_check_json(content, source_path))
}

/// Detect RHUI connectivity errors from package-manager logs.
///
/// Categories: TLS, DNS, 404, repo metadata.
///
/// Args:
///     content (str): Contents of ``updates.txt``, ``dnf.log``,
///         ``yum.log``, or ``messages``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "count", "errors": [{"timestamp",
///     "category", "rawLine"}]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_rhui_errors(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_rhui_errors_json(content, source_path))
}

// ============================================================================
// Security (FIPS / crypto policies)
// ============================================================================

/// Report the active crypto policy on RHEL 8+ (DEFAULT, LEGACY, FUTURE, FIPS).
///
/// Args:
///     content (str): Contents of ``crypto-policies/config`` or ``updates.txt``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "policy", "subPolicies"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_crypto_policies(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_crypto_policies_json(content, source_path))
}

/// Parse ``fips-mode-setup --check`` output.
///
/// Detects FIPS enabled / disabled and inconsistent state.
///
/// Args:
///     content (str): Contents of
///         ``sos_commands/crypto/fips-mode-setup_--check``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "fipsEnabled", "consistent",
///     "rawOutput"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_fips_mode_setup(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_fips_mode_setup_json(content, source_path))
}

/// Parse ``tuned-adm active`` output to report the active tuned profile.
///
/// Args:
///     content (str): Contents of
///         ``sos_commands/tuned/tuned-adm_active`` or similar.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "activeProfile", "warnings",
///     "recommendations"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_tuned_profile(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_tuned_profile_json(content, source_path))
}

/// Parse SELinux mode from ``/etc/selinux/config`` or ``sestatus`` output.
///
/// Args:
///     content (str): Contents of ``etc/selinux/config`` or
///         ``sos_commands/selinux/sestatus``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "configMode", "currentMode",
///     "warnings", "recommendations"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_selinux(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_selinux_json(content, source_path))
}

/// Parse swap space totals from ``/proc/meminfo`` (or ``free`` output).
///
/// Args:
///     content (str): Contents of ``proc/meminfo``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "swapTotalKb", "swapFreeKb",
///     "warnings"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_swap_space(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_swap_space_json(content, source_path))
}

/// Parse the state of the ``fstrim.timer`` systemd unit.
///
/// Args:
///     content (str): Output of ``systemctl is-enabled fstrim.timer`` or a
///         ``systemctl list-unit-files`` listing.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "timerEnabled", "timerState",
///     "warnings"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_fstrim(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_fstrim_json(content, source_path))
}

/// Parse the kernel command line; detect ``fips=1`` and other notable params.
///
/// Args:
///     content (str): Contents of ``proc/cmdline`` or ``boot.txt``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "cmdline", "fips",
///     "params": {...}}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_kernel_cmdline(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_kernel_cmdline_json(content, source_path))
}

// ============================================================================
// Leapp in-place upgrade
// ============================================================================

/// Parse the Leapp pre-upgrade / upgrade report.
///
/// Categorises findings by severity (high, medium, low, info) with
/// remediation hints.
///
/// Args:
///     content (str): Contents of ``leapp-report.txt`` or ``leapp-report.json``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "findings": [{"severity",
///     "title", "summary", "remediation"}], "summary": {...}}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_leapp_report(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_leapp_report_json(content, source_path))
}

/// Scan the Leapp upgrade log for errors, inhibitors, and phase failures.
///
/// Args:
///     content (str): Contents of ``leapp-upgrade.log`` or ``leapp.log``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "errors": [...],
///     "inhibitors": [...], "phaseFailures": [...]}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_leapp_log(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_leapp_log_json(content, source_path))
}

// ============================================================================
// vmcore / kdump
// ============================================================================

/// Parse the kernel dmesg captured at the time of a crash.
///
/// Args:
///     content (str): Contents of ``var/crash/<dir>/vmcore-dmesg.txt``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "crashes": [{"date",
///     "panicReason", "kernelVersion", "callTrace", "comm", "pid",
///     "tainted", ...}]}``. Each crash carries the date parsed from the
///     directory name (e.g. ``127.0.0.1-2026-02-13-03:48:00``).
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_vmcore_dmesg(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_vmcore_dmesg_json(content, source_path))
}

/// Parse ``kdumpctl status`` to check whether kdump is operational.
///
/// Args:
///     content (str): Contents of ``sos_commands/kdump/kdumpctl_status``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "operational", "raw"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_kdump_status(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_kdump_status_json(content, source_path))
}

/// Parse a directory listing of ``/var/crash`` to obtain vmcore file sizes.
///
/// Args:
///     content (str): Contents of ``sos_commands/kdump/ls_-alZR_.var.crash``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "entries": [{"directory",
///     "crashDate", "sizeBytes", "sizeMB", "sizeGB"}], "count",
///     "totalBytes", "totalGB"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_crash_listing(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_crash_listing_json(content, source_path))
}

/// Parse ``/etc/kdump.conf`` (dump path, core_collector, failure_action).
///
/// Args:
///     content (str): Contents of ``etc/kdump.conf``.
///
/// Returns:
///     str: JSON-encoded object ``{"found", "path", "coreCollector",
///     "defaultAction", "raw"}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_kdump_conf(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_kdump_conf_json(content, source_path))
}

/// Build a consolidated vmcore summary from the dmesg / status / listing / conf inputs.
///
/// Use this when you have already concatenated or wish to summarise a single
/// vmcore-related document. For full multi-file analysis, call the four
/// per-file parsers (:func:`parse_vmcore_dmesg`, :func:`parse_kdump_status`,
/// :func:`parse_crash_listing`, :func:`parse_kdump_conf`) and merge the
/// results in the caller.
///
/// Args:
///     content (str): Combined or single-file vmcore-related content.
///
/// Returns:
///     str: JSON-encoded object
///     ``{"found", "crashes": [...], "kdumpStatus": {...},
///     "crashListing": {...}, "kdumpConf": {...}}``.
#[pyfunction]
#[pyo3(signature = (content, source_path=""))]
fn parse_vmcore_summary(content: &str, source_path: &str) -> PyResult<String> {
    Ok(parse_vmcore_summary_json(content, source_path))
}

// ============================================================================
// Module
// ============================================================================

/// Native parsers from the Supportfile (RCA Tool) Rust core.
///
/// This module exposes a flat set of ``parse_*`` functions that turn raw
/// text content (typically a single file from a Linux supportconfig (SCC)
/// or sosreport (SOS) archive) into a JSON document describing what was
/// found.
///
/// Conventions
/// -----------
/// * Every function takes a single ``content: str`` argument: the raw text
///   of one file. The Python wrapper does not read files for you.
/// * Every function returns a ``str`` containing JSON. Use ``json.loads()``
///   to obtain a Python object.
/// * Output objects always include a ``"found"`` boolean (or, for purely
///   list-shaped outputs, an empty list / ``"count": 0``) so callers can
///   skip empty results without exception handling.
/// * Parsers never raise on malformed input; they return an empty result
///   structure instead.
///
/// Quick start
/// -----------
///     >>> import json, supportfile
///     >>> log = "Jan 10 12:23:45 node01 pacemaker-controld[2404]: notice: High CPU load detected: 23.27\n"
///     >>> result = json.loads(supportfile.parse_high_cpu_events(log))
///     >>> result[0]["sourceNode"]
///     'node01'
///
/// Function groups
/// ---------------
/// * Cluster: :func:`parse_high_cpu_events`, :func:`parse_cluster_events`,
///   :func:`parse_cluster_status`, :func:`parse_corosync_config`,
///   :func:`parse_cluster_maintenance_mode`
/// * Automation: :func:`parse_automation_events`
/// * Azure: :func:`parse_azure_vm_properties`,
///   :func:`parse_azure_vm_generation`,
///   :func:`parse_suse_cloud_register`, :func:`parse_waagent_config`,
///   :func:`parse_waagent_log`, :func:`parse_azure_extensions`
/// * Debugfs: :func:`parse_hv_balloon`, :func:`parse_extfrag`
/// * System events: :func:`parse_emergency_mode`,
///   :func:`parse_kernel_reboots`, :func:`parse_oom_killer`,
///   :func:`parse_xfs_errors`
/// * Networking: :func:`parse_firewall_rules`,
///   :func:`parse_network_interfaces`
/// * Packages: :func:`parse_distro_packages`,
///   :func:`parse_package_distro_mismatch`
/// * Services: :func:`parse_ssh_service_issues`, :func:`parse_dlm_service`,
///   :func:`parse_azure_site_recovery`, :func:`parse_guardicore_agent`,
///   :func:`parse_illumio`, :func:`parse_trend_micro`,
///   :func:`parse_falcon_sensor`, :func:`parse_falcon_sensor_config`,
///   :func:`parse_ms_defender`, :func:`parse_ms_defender_config`,
///   :func:`parse_involflt_version`, :func:`parse_involflt_kernel_version`
/// * Storage: :func:`parse_lvm_config`, :func:`parse_raid_config`,
///   :func:`parse_btrfs_config`, :func:`parse_block_devices`,
///   :func:`parse_fstab_analysis`, :func:`parse_df_output`,
///   :func:`parse_mtab_analysis`
/// * OS / filesystem: :func:`parse_basic_environment`,
///   :func:`parse_os_release`, :func:`parse_fstab`,
///   :func:`parse_inspect_disk_results`
/// * Kernel tuning: :func:`parse_kernel_tuning`, :func:`parse_huge_pages`
/// * Time sync (Azure PTP): :func:`parse_time_sync`,
///   :func:`parse_ptp_clock_source`, :func:`parse_time_sync_service`,
///   :func:`parse_timedatectl`, :func:`parse_ptp_device`,
///   :func:`parse_chrony_tracking`, :func:`parse_chrony_makestep`
/// * RHUI: :func:`parse_rhui_config`, :func:`parse_eus_version_lock`,
///   :func:`parse_rhel_rhui_check`, :func:`parse_rhui_errors`
/// * Security: :func:`parse_crypto_policies`,
///   :func:`parse_fips_mode_setup`, :func:`parse_kernel_cmdline`
/// * Leapp: :func:`parse_leapp_report`, :func:`parse_leapp_log`
/// * vmcore / kdump: :func:`parse_vmcore_dmesg`, :func:`parse_kdump_status`,
///   :func:`parse_crash_listing`, :func:`parse_kdump_conf`,
///   :func:`parse_vmcore_summary`
#[pymodule]
fn supportfile(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(parse_high_cpu_events, m)?)?;
    m.add_function(wrap_pyfunction!(parse_cluster_events, m)?)?;
    m.add_function(wrap_pyfunction!(parse_cluster_status, m)?)?;
    m.add_function(wrap_pyfunction!(parse_corosync_config, m)?)?;
    m.add_function(wrap_pyfunction!(parse_cluster_maintenance_mode, m)?)?;
    m.add_function(wrap_pyfunction!(parse_automation_events, m)?)?;
    m.add_function(wrap_pyfunction!(parse_azure_vm_properties, m)?)?;
    m.add_function(wrap_pyfunction!(parse_azure_vm_generation, m)?)?;
    m.add_function(wrap_pyfunction!(parse_suse_cloud_register, m)?)?;
    m.add_function(wrap_pyfunction!(parse_secure_boot, m)?)?;
    m.add_function(wrap_pyfunction!(parse_waagent_config, m)?)?;
    m.add_function(wrap_pyfunction!(parse_waagent_log, m)?)?;
    m.add_function(wrap_pyfunction!(parse_hv_balloon, m)?)?;
    m.add_function(wrap_pyfunction!(parse_extfrag, m)?)?;
    m.add_function(wrap_pyfunction!(parse_emergency_mode, m)?)?;
    m.add_function(wrap_pyfunction!(parse_kernel_reboots, m)?)?;
    m.add_function(wrap_pyfunction!(parse_oom_killer, m)?)?;
    m.add_function(wrap_pyfunction!(parse_xfs_errors, m)?)?;
    m.add_function(wrap_pyfunction!(parse_firewall_rules, m)?)?;
    m.add_function(wrap_pyfunction!(parse_network_interfaces, m)?)?;
    m.add_function(wrap_pyfunction!(parse_distro_packages, m)?)?;
    m.add_function(wrap_pyfunction!(parse_package_distro_mismatch, m)?)?;
    m.add_function(wrap_pyfunction!(parse_ssh_service_issues, m)?)?;
    m.add_function(wrap_pyfunction!(parse_dlm_service, m)?)?;
    m.add_function(wrap_pyfunction!(parse_azure_site_recovery, m)?)?;
    m.add_function(wrap_pyfunction!(parse_guardicore_agent, m)?)?;
    m.add_function(wrap_pyfunction!(parse_illumio, m)?)?;
    m.add_function(wrap_pyfunction!(parse_trend_micro, m)?)?;
    m.add_function(wrap_pyfunction!(parse_falcon_sensor, m)?)?;
    m.add_function(wrap_pyfunction!(parse_falcon_sensor_config, m)?)?;
    m.add_function(wrap_pyfunction!(parse_ms_defender, m)?)?;
    m.add_function(wrap_pyfunction!(parse_ms_defender_config, m)?)?;
    m.add_function(wrap_pyfunction!(parse_involflt_version, m)?)?;
    m.add_function(wrap_pyfunction!(parse_involflt_kernel_version, m)?)?;
    m.add_function(wrap_pyfunction!(parse_azure_extensions, m)?)?;
    m.add_function(wrap_pyfunction!(parse_lvm_config, m)?)?;
    m.add_function(wrap_pyfunction!(parse_raid_config, m)?)?;
    m.add_function(wrap_pyfunction!(parse_btrfs_config, m)?)?;
    m.add_function(wrap_pyfunction!(parse_block_devices, m)?)?;
    m.add_function(wrap_pyfunction!(parse_fstab_analysis, m)?)?;
    m.add_function(wrap_pyfunction!(parse_df_output, m)?)?;
    m.add_function(wrap_pyfunction!(parse_mtab_analysis, m)?)?;
    m.add_function(wrap_pyfunction!(parse_nfs_mounts, m)?)?;
    m.add_function(wrap_pyfunction!(parse_hana_savepoints, m)?)?;
    m.add_function(wrap_pyfunction!(parse_hana_deadlocks, m)?)?;
    m.add_function(wrap_pyfunction!(parse_hana_oom, m)?)?;
    m.add_function(wrap_pyfunction!(parse_hana_merge_errors, m)?)?;
    m.add_function(wrap_pyfunction!(parse_basic_environment, m)?)?;
    m.add_function(wrap_pyfunction!(parse_os_release, m)?)?;
    m.add_function(wrap_pyfunction!(parse_fstab, m)?)?;
    m.add_function(wrap_pyfunction!(parse_inspect_disk_results, m)?)?;
    m.add_function(wrap_pyfunction!(parse_kernel_tuning, m)?)?;
    m.add_function(wrap_pyfunction!(parse_huge_pages, m)?)?;
    m.add_function(wrap_pyfunction!(parse_time_sync, m)?)?;
    m.add_function(wrap_pyfunction!(parse_ptp_clock_source, m)?)?;
    m.add_function(wrap_pyfunction!(parse_time_sync_service, m)?)?;
    m.add_function(wrap_pyfunction!(parse_timedatectl, m)?)?;
    m.add_function(wrap_pyfunction!(parse_ptp_device, m)?)?;
    m.add_function(wrap_pyfunction!(parse_chrony_tracking, m)?)?;
    m.add_function(wrap_pyfunction!(parse_chrony_makestep, m)?)?;
    m.add_function(wrap_pyfunction!(parse_rhui_config, m)?)?;
    m.add_function(wrap_pyfunction!(parse_eus_version_lock, m)?)?;
    m.add_function(wrap_pyfunction!(parse_rhel_rhui_check, m)?)?;
    m.add_function(wrap_pyfunction!(parse_crypto_policies, m)?)?;
    m.add_function(wrap_pyfunction!(parse_fips_mode_setup, m)?)?;
    m.add_function(wrap_pyfunction!(parse_tuned_profile, m)?)?;
    m.add_function(wrap_pyfunction!(parse_selinux, m)?)?;
    m.add_function(wrap_pyfunction!(parse_swap_space, m)?)?;
    m.add_function(wrap_pyfunction!(parse_fstrim, m)?)?;
    m.add_function(wrap_pyfunction!(parse_kernel_cmdline, m)?)?;
    m.add_function(wrap_pyfunction!(parse_rhui_errors, m)?)?;
    m.add_function(wrap_pyfunction!(parse_leapp_report, m)?)?;
    m.add_function(wrap_pyfunction!(parse_leapp_log, m)?)?;
    m.add_function(wrap_pyfunction!(parse_vmcore_dmesg, m)?)?;
    m.add_function(wrap_pyfunction!(parse_kdump_status, m)?)?;
    m.add_function(wrap_pyfunction!(parse_crash_listing, m)?)?;
    m.add_function(wrap_pyfunction!(parse_kdump_conf, m)?)?;
    m.add_function(wrap_pyfunction!(parse_vmcore_summary, m)?)?;
    Ok(())
}
