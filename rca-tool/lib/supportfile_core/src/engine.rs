//! In-process analysis engine for supportconfig (SCC) / sosreport (SOS)
//! archives.
//!
//! This module is the reusable core extracted from the `rca_cli` binary: it
//! owns the parser registry, the archive walk (`.tar`, `.tar.gz`, `.tar.xz`,
//! `.zip`, and plaintext logs), inner-member decompression, the parallel
//! parser dispatch, and multi-file result merging. The `rca_cli` binary and
//! any in-process consumer (e.g. an MCP server linking the library directly)
//! call [`process_archive`] / [`analyze_archive`] instead of shelling out.
//!
//! Gated behind the `cli` feature because it depends on the archive and
//! parallelism crates (tar, liblzma, flate2, zip, rayon, crossbeam-channel)
//! that lean library / WASM / PyO3 builds do not need.

use std::collections::{BTreeMap, HashMap};
use std::fs::File;
use std::io::Read;
use std::path::Path;
use std::sync::Arc;

use crossbeam_channel::bounded;
use flate2::read::GzDecoder;
use liblzma::read::XzDecoder;
use liblzma::stream::{MtStreamBuilder, Stream};
use rayon::iter::{ParallelBridge, ParallelIterator};
use regex::Regex;
use serde_json::{Map, Value};
use tar::Archive;

// ---------------------------------------------------------------------------
// Parser registry
// ---------------------------------------------------------------------------

/// Parser entry point used by the registry.
///
/// All parsers receive `(content, source_path)`. Parsers that have not yet
/// been migrated to carry source provenance simply ignore `source_path`; this
/// is achieved with the `compat_shims!` macro below.
pub type ParseFn = fn(&str, &str) -> String;

/// One registry entry: a named parser, the path regex that selects which
/// archive members it runs on, and whether results from multiple matching
/// files should be merged.
pub struct ParserSpec {
    /// Output key under which results are stored.
    pub name: &'static str,
    /// Regex applied to each member's path (with a leading `/`).
    pub pattern: &'static str,
    /// Pointer to one of the `parse_*_json` functions in `supportfile`.
    pub func: ParseFn,
    /// When true, results from successive matching files are merged.
    pub multi_file: bool,
}

/// Generate compatibility shims for parser functions that still take only
/// `content`. Each shim has the same name as the underlying `crate::`
/// function and shadows the `crate::` import within this module.
macro_rules! compat_shims {
    ($($name:ident),* $(,)?) => {
        $(
            fn $name(content: &str, _source_path: &str) -> String {
                crate::$name(content)
            }
        )*
    };
}

compat_shims!();

/// The full parser registry: maps file-path regexes to the
/// `supportfile::parse_*_json` functions.
pub fn parsers() -> Vec<ParserSpec> {
    vec![
        // ----- Cluster ----------------------------------------------------
        ParserSpec {
            name: "highCpuEvents",
            pattern: r"/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|localmessages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?(?:\.gz)?$|/ha\.txt$",
            func: crate::parse_pacemaker_high_cpu_json,
            multi_file: true,
        },
        ParserSpec {
            name: "clusterEvents",
            pattern: r"/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?(?:\.gz)?$|/ha\.txt$",
            func: crate::parse_cluster_events_json,
            multi_file: true,
        },
        ParserSpec {
            name: "clusterStatus",
            pattern: r"cib\.xml$|/crm_mon.*\.txt$|/crm_mon.*\.xml$|/ha\.txt$|/pcs_status",
            func: crate::parse_cluster_status_json,
            multi_file: false,
        },
        ParserSpec {
            name: "corosyncConfig",
            pattern: r"/(ha\.txt|corosync\.conf)$",
            func: crate::parse_corosync_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "clusterMaintenanceMode",
            pattern: r"cib\.xml$|/crm_mon.*\.txt$|/ha\.txt$",
            func: crate::parse_cluster_maintenance_mode_json,
            multi_file: false,
        },
        // ----- Automation -------------------------------------------------
        ParserSpec {
            name: "automationEvents",
            pattern: r"/(messages|localmessages|syslog|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$",
            func: crate::parse_automation_events_json,
            multi_file: true,
        },
        // ----- Azure ------------------------------------------------------
        ParserSpec {
            name: "azureVMProperties",
            pattern: r"(?:instance_metadata\.json|public_cloud/metadata\.txt)$",
            func: crate::parse_azure_vm_properties_json,
            multi_file: false,
        },
        ParserSpec {
            name: "suseCloudRegister",
            pattern: r"public_cloud/cloudregister\.txt$",
            func: crate::parse_suse_cloud_register_json,
            multi_file: false,
        },
        ParserSpec {
            name: "waagentConfig",
            pattern: r"/etc/waagent\.conf$",
            func: crate::parse_waagent_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "waagentLog",
            pattern: r"/waagent\.log$",
            func: crate::parse_waagent_log_json,
            multi_file: false,
        },
        ParserSpec {
            name: "azureExtensions",
            pattern: r"var/lib/waagent/[^/]+/config/HandlerStatus$",
            func: crate::parse_azure_extensions_json,
            multi_file: true,
        },
        // ----- Debugfs ----------------------------------------------------
        ParserSpec {
            name: "hvBalloon",
            pattern: r"sys/kernel/debug/hv[-_]balloon$",
            func: crate::parse_hv_balloon_json,
            multi_file: false,
        },
        ParserSpec {
            name: "extfrag",
            pattern: r"sys/kernel/debug/extfrag/(extfrag_index|unusable_index)$",
            func: crate::parse_extfrag_json,
            multi_file: true,
        },
        // ----- System events ---------------------------------------------
        ParserSpec {
            name: "emergencyMode",
            pattern: r"/(messages|localmessages|journalctl[^/]*|console.*\.log)(?:[.-]\d+)?(?:\.txt)?$",
            func: crate::parse_emergency_mode_json,
            multi_file: true,
        },
        ParserSpec {
            name: "kernelReboots",
            pattern: r"/(messages|localmessages|ha-log|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$",
            func: crate::parse_kernel_reboots_json,
            multi_file: true,
        },
        ParserSpec {
            name: "oomKiller",
            pattern: r"/(messages|localmessages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$",
            func: crate::parse_oom_killer_json,
            multi_file: true,
        },
        ParserSpec {
            name: "xfsErrors",
            pattern: r"/(messages|localmessages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$",
            func: crate::parse_xfs_errors_json,
            multi_file: true,
        },
        // ----- Networking -------------------------------------------------
        ParserSpec {
            name: "firewallRules",
            pattern: r"network\.txt$|sos_commands/firewalld/|sos_commands/firewall_tables/|etc/sysconfig/(?:iptables-config|ebtables-config|nftables\.conf|firewalld)$|etc/firewalld/firewalld\.conf$",
            func: crate::parse_firewall_rules_json,
            multi_file: true,
        },
        ParserSpec {
            name: "networkInterfaces",
            pattern: r"network\.txt$|sos_commands/networking/ip_-o_addr$|sos_commands/networking/ip_-s_-d_link$|sos_commands/networking/ethtool_-i_\w+|sos_commands/networkmanager/nmcli_con_show_id_|etc/sysconfig/network-scripts/ifcfg-|etc/sysconfig/network/(?:network/)?ifcfg-|etc/netplan/|var/log/cloud-init-output\.log$|(?:^|/)messages$",
            func: crate::parse_network_interfaces_json,
            multi_file: true,
        },
        ParserSpec {
            name: "packetLoss",
            pattern: r"network\.txt$|sos_commands/networking/ip_-s_-d_link$|sos_commands/networking/ip_-s_link$",
            func: crate::parse_packet_loss_json,
            multi_file: true,
        },
        ParserSpec {
            name: "ringBuffer",
            pattern: r"network\.txt$|sos_commands/networking/ethtool_-g_\w+",
            func: crate::parse_ring_buffer_json,
            multi_file: true,
        },
        ParserSpec {
            name: "networkSysctl",
            pattern: r"/env\.txt$|/sysctl\.conf$|sos_commands/kernel/sysctl_-a$|etc/sysctl\.d/",
            func: crate::parse_network_sysctl_json,
            multi_file: true,
        },
        // ----- Packages ---------------------------------------------------
        ParserSpec {
            name: "distroPackages",
            pattern: r"/(rpm\.txt|installed-rpms|package-data|dpkg_-l|dnf[_-]list[_-]installed|yum[_-]list[_-]installed|var/log/zypp/history|var/log/(?:dnf|yum)\.log)$",
            func: crate::parse_distro_packages_json,
            multi_file: false,
        },
        // ----- Services ---------------------------------------------------
        ParserSpec {
            name: "sshServiceIssues",
            pattern: r"/(messages|localmessages|syslog|journalctl[^/]*|console.*\.log)(?:[.-]\d+)?(?:\.txt)?$",
            func: crate::parse_ssh_service_issues_json,
            multi_file: true,
        },
        ParserSpec {
            name: "dlmService",
            pattern: r"sos_commands/systemd/systemctl_list-unit-files$",
            func: crate::parse_dlm_service_json,
            multi_file: false,
        },
        ParserSpec {
            name: "azureSiteRecovery",
            pattern: r"(?:sos_commands/systemd/systemctl_list-unit-files|systemd-status\.txt)$",
            func: crate::parse_azure_site_recovery_json,
            multi_file: false,
        },
        ParserSpec {
            name: "guardicoreAgent",
            pattern: r"(?:sos_commands/systemd/systemctl_list-unit-files|systemd-status\.txt)$",
            func: crate::parse_guardicore_agent_json,
            multi_file: false,
        },
        ParserSpec {
            name: "illumio",
            pattern: r"sos_commands/systemd/systemctl_list-units_--all$",
            func: crate::parse_illumio_json,
            multi_file: false,
        },
        ParserSpec {
            name: "trendMicro",
            pattern: r"sos_commands/systemd/systemctl_list-units_--all$",
            func: crate::parse_trend_micro_json,
            multi_file: false,
        },
        ParserSpec {
            name: "falconSensor",
            pattern: r"/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$",
            func: crate::parse_falcon_sensor_json,
            multi_file: false,
        },
        ParserSpec {
            name: "falconSensorConfig",
            pattern: r"/(falconctl|CrowdStrike.*config|falcon.*conf)$",
            func: crate::parse_falcon_sensor_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "msDefender",
            pattern: r"/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$",
            func: crate::parse_ms_defender_json,
            multi_file: false,
        },
        ParserSpec {
            name: "msDefenderConfig",
            pattern: r"/(mdatp.*|defender.*config)$",
            func: crate::parse_ms_defender_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "involfltVersion",
            pattern: r"modules\.txt$",
            func: crate::parse_involflt_version_json,
            multi_file: false,
        },
        ParserSpec {
            name: "involfltKernelVersion",
            pattern: r"/(messages|boot)(?:[.-]\d+)?(?:\.txt)?$",
            func: crate::parse_involflt_kernel_version_json,
            multi_file: false,
        },
        // ----- Storage ----------------------------------------------------
        ParserSpec {
            name: "lvmConfig",
            pattern: r"/(lvm\.txt|pvs\.txt|vgs\.txt|lvs\.txt|pvdisplay|vgdisplay|lvdisplay)$|/lvm2/pvs_|/lvm2/vgs_|/lvm2/lvs_",
            func: crate::parse_lvm_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "raidConfig",
            pattern: r"/(mdstat|md-arrays\.txt|mdadm\.txt|proc/mdstat)$",
            func: crate::parse_raid_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "btrfsConfig",
            pattern: r"/(btrfs\.txt|fs-btrfs\.txt|btrfs-filesystem-show\.txt|btrfs-subvolume-list\.txt)$",
            func: crate::parse_btrfs_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "blockDevices",
            pattern: r"/sos_commands/block/(lsblk|lsblk_-f_-a_-l|blkid_-c_\.dev\.null)$|(?:^|/)results\.txt$",
            func: crate::parse_block_devices_json,
            multi_file: true,
        },
        ParserSpec {
            name: "fstabAnalysis",
            pattern: r"/etc/fstab$|/fs-diskio\.txt$",
            func: crate::parse_fstab_analysis_json,
            multi_file: false,
        },
        ParserSpec {
            name: "dfOutput",
            pattern: r"/df$|/df_-aliT|/df_-al_|/fs-diskio\.txt$",
            func: crate::parse_df_output_json,
            multi_file: false,
        },
        ParserSpec {
            name: "mtabAnalysis",
            pattern: r"/etc/mtab$|/proc/mounts$|/proc/self/mounts$|/fs-diskio\.txt$|/mount_-l$|/mount$",
            func: crate::parse_mtab_analysis_json,
            multi_file: false,
        },
        ParserSpec {
            name: "nfsMounts",
            pattern: r"/etc/fstab$|/etc/mtab$|/proc/mounts$|/proc/self/mounts$|/fs-diskio\.txt$|/mount_-l$|/mount$",
            func: crate::parse_nfs_mounts_json,
            multi_file: true,
        },
        // ----- SAP HANA --------------------------------------------------
        ParserSpec {
            name: "hanaSavepoints",
            pattern: r"/(indexserver|nameserver)[^/]*\.trc$",
            func: crate::parse_hana_savepoints_json,
            multi_file: true,
        },
        ParserSpec {
            name: "hanaDeadlocks",
            pattern: r"/(indexserver|nameserver)[^/]*\.trc$",
            func: crate::parse_hana_deadlocks_json,
            multi_file: true,
        },
        ParserSpec {
            name: "hanaOom",
            pattern: r"/(indexserver|nameserver)[^/]*\.trc$",
            func: crate::parse_hana_oom_json,
            multi_file: true,
        },
        ParserSpec {
            name: "hanaMergeErrors",
            pattern: r"/(indexserver|nameserver)[^/]*\.trc$",
            func: crate::parse_hana_merge_errors_json,
            multi_file: true,
        },
        // ----- OS / filesystem -------------------------------------------
        ParserSpec {
            name: "basicEnvironment",
            pattern: r"basic-environment\.txt$",
            func: crate::parse_basic_environment_json,
            multi_file: false,
        },
        ParserSpec {
            name: "osRelease",
            pattern: r"/usr/lib/os-release$|/etc/os-release$|/sysinfo\.txt$|/basic-environment\.txt$|/etc/(redhat|centos|SuSE|system)-release$",
            func: crate::parse_os_release_json,
            multi_file: false,
        },
        ParserSpec {
            name: "fstab",
            pattern: r"/etc/fstab$|/fs-diskio\.txt$",
            func: crate::parse_fstab_json,
            multi_file: false,
        },
        ParserSpec {
            name: "inspectDiskResults",
            pattern: r"(?:^|/)results\.txt$",
            func: crate::parse_inspect_disk_results_json,
            multi_file: false,
        },
        // ----- Kernel tuning ---------------------------------------------
        ParserSpec {
            name: "kernelTuning",
            pattern: r"sos_commands/kernel/sysctl_-a$|/env\.txt$|/etc/sysctl\.conf$|/sysctl\.d/[^/]*\.conf$",
            func: crate::parse_kernel_tuning_json,
            multi_file: false,
        },
        ParserSpec {
            name: "hugePages",
            pattern: r"/proc/meminfo$",
            func: crate::parse_huge_pages_json,
            multi_file: false,
        },
        // ----- Time sync (Azure PTP) -------------------------------------
        ParserSpec {
            name: "timeSync",
            pattern: r"sos_commands/kernel/lsmod$|/modules\.txt$",
            func: crate::parse_time_sync_json,
            multi_file: false,
        },
        ParserSpec {
            name: "ptpClockSource",
            pattern: r"sos_commands/chrony/chronyc_sources$|/etc/chrony\.conf$|/etc/chrony/chrony\.conf$|/ntp\.txt$",
            func: crate::parse_ptp_clock_source_json,
            multi_file: false,
        },
        ParserSpec {
            name: "timeSyncService",
            pattern: r"sos_commands/systemd/systemctl_list-unit-files$|/systemd-status\.txt$|/ntp\.txt$",
            func: crate::parse_time_sync_service_json,
            multi_file: false,
        },
        ParserSpec {
            name: "timedatectl",
            pattern: r"sos_commands/systemd/timedatectl$|/ntp\.txt$",
            func: crate::parse_timedatectl_json,
            multi_file: false,
        },
        ParserSpec {
            name: "ptpDevice",
            pattern: r"sos_commands/block/ls_-lanR_\.dev$|/udev\.txt$",
            func: crate::parse_ptp_device_json,
            multi_file: false,
        },
        ParserSpec {
            name: "chronyTracking",
            pattern: r"sos_commands/chrony/chronyc_tracking$|/ntp\.txt$",
            func: crate::parse_chrony_tracking_json,
            multi_file: false,
        },
        ParserSpec {
            name: "chronyMakestep",
            pattern: r"/etc/chrony\.conf$|/etc/chrony/chrony\.conf$|/ntp\.txt$",
            func: crate::parse_chrony_makestep_json,
            multi_file: false,
        },
        // ----- RHUI ------------------------------------------------------
        ParserSpec {
            name: "rhuiConfig",
            pattern: r"/(rh-cloud.*\.repo|rhui-.*\.repo|yum\.repos\.d\.txt|dnf\.repos\.d\.txt|yum\.repos\.d/.*\.repo)$",
            func: crate::parse_rhui_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "eusVersionLock",
            pattern: r"/(releasever|yum-vars\.txt|dnf-vars\.txt|etc/yum/vars|etc/dnf/vars|dnf/vars/releasever|yum/vars/releasever)$",
            func: crate::parse_eus_version_lock_json,
            multi_file: false,
        },
        ParserSpec {
            name: "rhelRhuiCheck",
            pattern: r"/(installed-rpms|rpm-qa\.txt|rpm_-qa|package-data)$",
            func: crate::parse_rhel_rhui_check_json,
            multi_file: false,
        },
        ParserSpec {
            name: "rhuiErrors",
            pattern: r"/(dnf\.log|yum\.log|rhsm\.log)(\.\d+)?$",
            func: crate::parse_rhui_errors_json,
            multi_file: true,
        },
        // ----- Security --------------------------------------------------
        ParserSpec {
            name: "cryptoPolicies",
            pattern: r"/crypto-policies/(config|state/current)$",
            func: crate::parse_crypto_policies_json,
            multi_file: false,
        },
        ParserSpec {
            name: "fipsModeSetup",
            pattern: r"sos_commands/crypto/fips-mode-setup",
            func: crate::parse_fips_mode_setup_json,
            multi_file: false,
        },
        ParserSpec {
            name: "kernelCmdline",
            pattern: r"/proc/cmdline$|/boot\.txt$",
            func: crate::parse_kernel_cmdline_json,
            multi_file: false,
        },
        // ----- OS tuning (SAP-on-Azure QualityCheck ports) ---------------
        ParserSpec {
            name: "tunedProfile",
            pattern: r"sos_commands/tuned/tuned-adm_active$|/tuned-adm.*\.txt$",
            func: crate::parse_tuned_profile_json,
            multi_file: false,
        },
        ParserSpec {
            name: "selinux",
            pattern: r"/etc/selinux/config$|sos_commands/selinux/sestatus$|/selinux\.txt$",
            func: crate::parse_selinux_json,
            multi_file: false,
        },
        ParserSpec {
            name: "swapSpace",
            pattern: r"/proc/meminfo$",
            func: crate::parse_swap_space_json,
            multi_file: false,
        },
        ParserSpec {
            name: "fstrim",
            pattern: r"sos_commands/systemd/systemctl_list-unit-files$|/systemd-status\.txt$|sos_commands/.*fstrim.*$",
            func: crate::parse_fstrim_json,
            multi_file: false,
        },
        // ----- Leapp -----------------------------------------------------
        ParserSpec {
            name: "leappReport",
            pattern: r"var/log/leapp/leapp-report\.(txt|json)$",
            func: crate::parse_leapp_report_json,
            multi_file: false,
        },
        ParserSpec {
            name: "leappLog",
            pattern: r"var/log/leapp/leapp-(preupgrade|upgrade)\.log$",
            func: crate::parse_leapp_log_json,
            multi_file: false,
        },
        // ----- vmcore / kdump --------------------------------------------
        ParserSpec {
            name: "vmcoreDmesg",
            pattern: r"var/crash/[^/]+/vmcore-dmesg\.txt$",
            func: crate::parse_vmcore_dmesg_json,
            multi_file: true,
        },
        ParserSpec {
            name: "kdumpStatus",
            pattern: r"sos_commands/kdump/kdumpctl_status$",
            func: crate::parse_kdump_status_json,
            multi_file: false,
        },
        ParserSpec {
            name: "crashListing",
            pattern: r"sos_commands/kdump/ls_-alZR_\.var\.crash$",
            func: crate::parse_crash_listing_json,
            multi_file: false,
        },
        ParserSpec {
            name: "kdumpConf",
            pattern: r"etc/kdump\.conf$",
            func: crate::parse_kdump_conf_json,
            multi_file: false,
        },
    ]
}

// ---------------------------------------------------------------------------
// Result merging
// ---------------------------------------------------------------------------

/// Best-effort recursive merge of two parser results.
///
/// - Objects merge key-by-key.
/// - Arrays concatenate.
/// - `found` is OR'ed; numeric `count` is summed.
/// - Scalars keep the existing non-empty value, otherwise take the new one.
fn merge(existing: Value, new: Value) -> Value {
    match (existing, new) {
        (Value::Null, v) | (v, Value::Null) => v,
        (Value::Object(mut a), Value::Object(b)) => {
            for (k, v) in b {
                let merged = match a.remove(&k) {
                    Some(prev) => match k.as_str() {
                        "found" => Value::Bool(
                            prev.as_bool().unwrap_or(false) || v.as_bool().unwrap_or(false),
                        ),
                        "count" if prev.is_i64() && v.is_i64() => {
                            Value::from(prev.as_i64().unwrap_or(0) + v.as_i64().unwrap_or(0))
                        }
                        _ => merge(prev, v),
                    },
                    None => v,
                };
                a.insert(k, merged);
            }
            Value::Object(a)
        }
        (Value::Array(mut a), Value::Array(b)) => {
            a.extend(b);
            Value::Array(a)
        }
        (existing, new) => {
            if !is_empty_scalar(&existing) {
                existing
            } else {
                new
            }
        }
    }
}

/// True for scalar / container values that carry no information: null, false,
/// zero, empty string, empty array, empty object.
pub fn is_empty_scalar(v: &Value) -> bool {
    match v {
        Value::Null => true,
        Value::Bool(b) => !*b,
        Value::Number(n) => n.as_f64().map(|x| x == 0.0).unwrap_or(false),
        Value::String(s) => s.is_empty(),
        Value::Array(a) => a.is_empty(),
        Value::Object(o) => o.is_empty(),
    }
}

// ---------------------------------------------------------------------------
// Archive processing
// ---------------------------------------------------------------------------

/// Accumulated results for a whole archive: file bookkeeping plus the merged
/// per-parser output keyed by the parser's registry name.
pub struct ArchiveResults {
    pub file_count: usize,
    pub matched_files: usize,
    pub parser_results: BTreeMap<String, Value>,
    pub file_types: BTreeMap<String, usize>,
}

impl Default for ArchiveResults {
    fn default() -> Self {
        Self {
            file_count: 0,
            matched_files: 0,
            parser_results: BTreeMap::new(),
            file_types: BTreeMap::new(),
        }
    }
}

impl ArchiveResults {
    /// Build the combined JSON object used by the CLI `--json` output and by
    /// in-process consumers: top-level `fileCount`, `matchedFiles`,
    /// `fileTypes`, plus one key per parser that produced results.
    pub fn to_json(&self) -> Value {
        let mut combined: Map<String, Value> = Map::new();
        combined.insert("fileCount".to_string(), Value::from(self.file_count));
        combined.insert("matchedFiles".to_string(), Value::from(self.matched_files));
        combined.insert(
            "fileTypes".to_string(),
            serde_json::to_value(&self.file_types).unwrap_or(Value::Null),
        );
        for (k, v) in &self.parser_results {
            combined.insert(k.clone(), v.clone());
        }
        Value::Object(combined)
    }
}

fn value_is_empty(v: &Value) -> bool {
    match v {
        Value::Object(o) => !o.get("found").and_then(Value::as_bool).unwrap_or(false),
        Value::Array(a) => a.is_empty(),
        _ => false,
    }
}

/// Combine two `ArchiveResults` (typically one per worker thread) into one.
///
/// - Numeric counters and the `file_types` histogram are summed.
/// - `parser_results` are merged per parser according to its registry entry:
///   `multi_file` parsers go through [`merge`] (deep array concatenation /
///   counter sums); single-file parsers prefer the non-empty value, matching
///   the sequential semantics in [`process_entry`].
fn merge_archive_results(
    multi_file_lookup: &HashMap<&str, bool>,
    mut a: ArchiveResults,
    b: ArchiveResults,
) -> ArchiveResults {
    a.file_count += b.file_count;
    a.matched_files += b.matched_files;
    for (k, v) in b.file_types {
        *a.file_types.entry(k).or_insert(0) += v;
    }
    for (key, val_b) in b.parser_results {
        match a.parser_results.remove(&key) {
            None => {
                a.parser_results.insert(key, val_b);
            }
            Some(val_a) => {
                let is_multi = multi_file_lookup
                    .get(key.as_str())
                    .copied()
                    .unwrap_or(false);
                let merged = if is_multi {
                    merge(val_a, val_b)
                } else if value_is_empty(&val_b) {
                    val_a
                } else {
                    val_b
                };
                a.parser_results.insert(key, merged);
            }
        }
    }
    a
}

fn detect_format(path: &Path) -> &'static str {
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("")
        .to_lowercase();
    if name.ends_with(".tar.xz") || name.ends_with(".txz") {
        "tar.xz"
    } else if name.ends_with(".tar.gz") || name.ends_with(".tgz") {
        "tar.gz"
    } else if name.ends_with(".tar") {
        "tar"
    } else if name.ends_with(".xz") {
        "tar.xz" // bare .xz is assumed to wrap a tar (matches Python tarfile "r:*")
    } else if name.ends_with(".gz") {
        "tar.gz"
    } else if name.ends_with(".zip") {
        "zip"
    } else if name.ends_with(".log") || name.ends_with(".txt") || name.ends_with(".out") {
        "plaintext"
    } else {
        // Sniff magic bytes to distinguish a headerless tar from a console log.
        match File::open(path) {
            Ok(mut f) => {
                let mut buf = [0u8; 6];
                let n = f.read(&mut buf).unwrap_or(0);
                if n >= 6 && buf == [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00] {
                    "tar.xz"
                } else if n >= 2 && buf[0] == 0x1f && buf[1] == 0x8b {
                    "tar.gz"
                } else if n >= 4 && buf[..4] == [0x50, 0x4b, 0x03, 0x04] {
                    "zip"
                } else if n > 0
                    && buf[..n]
                        .iter()
                        .all(|&b| b == 0x09 || b == 0x0a || b == 0x0d || (0x20..=0x7e).contains(&b))
                {
                    "plaintext"
                } else {
                    "tar"
                }
            }
            Err(_) => "tar",
        }
    }
}

fn open_tar_reader(path: &Path) -> std::io::Result<Box<dyn Read>> {
    let file = File::open(path)?;
    Ok(match detect_format(path) {
        "tar.xz" => Box::new(open_xz_mt(file)?),
        "tar.gz" => Box::new(GzDecoder::new(file)),
        _ => Box::new(file),
    })
}

/// If the given member bytes start with a gzip or xz magic header, decompress
/// them in-memory and strip the trailing `.gz` / `.xz` from `name` so that
/// parser file-pattern regexes can match the underlying filename. Returns the
/// (possibly rewritten) name and the (possibly decompressed) byte buffer.
///
/// Designed for nested compression inside tar/zip archives — e.g. rotated
/// `messages-YYYYMMDD.gz` log files inside a `.tar.xz` supportconfig.
fn maybe_decompress_inner(name: String, buf: Vec<u8>, debug: bool) -> (String, Vec<u8>) {
    // gzip: 1f 8b
    if buf.len() >= 2 && buf[0] == 0x1f && buf[1] == 0x8b {
        let mut out = Vec::new();
        match GzDecoder::new(buf.as_slice()).read_to_end(&mut out) {
            Ok(_) => {
                let stripped = name.strip_suffix(".gz").unwrap_or(&name).to_string();
                if debug {
                    eprintln!(
                        "[debug] inner gzip member {name} -> {stripped} ({} -> {} bytes)",
                        buf.len(),
                        out.len()
                    );
                }
                return (stripped, out);
            }
            Err(e) => {
                if debug {
                    eprintln!("[debug] inner gzip decompress failed for {name}: {e}");
                }
            }
        }
    }
    // xz: fd 37 7a 58 5a 00
    if buf.len() >= 6 && buf[..6] == [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00] {
        let mut out = Vec::new();
        match XzDecoder::new(buf.as_slice()).read_to_end(&mut out) {
            Ok(_) => {
                let stripped = name.strip_suffix(".xz").unwrap_or(&name).to_string();
                if debug {
                    eprintln!(
                        "[debug] inner xz member {name} -> {stripped} ({} -> {} bytes)",
                        buf.len(),
                        out.len()
                    );
                }
                return (stripped, out);
            }
            Err(e) => {
                if debug {
                    eprintln!("[debug] inner xz decompress failed for {name}: {e}");
                }
            }
        }
    }
    (name, buf)
}

/// Convert a byte buffer to `String` without copying when the bytes are
/// already valid UTF-8. Falls back to a lossy copy otherwise.
fn bytes_to_string(buf: Vec<u8>) -> String {
    match String::from_utf8(buf) {
        Ok(s) => s,
        Err(e) => String::from_utf8_lossy(e.as_bytes()).into_owned(),
    }
}

/// Open an `.xz` stream using liblzma's multi-threaded decoder
/// (`lzma_stream_decoder_mt`). Falls back to the single-threaded decoder if
/// the running liblzma is too old to support MT decoding.
///
/// Note: parallel decoding only happens for `.xz` files compressed into
/// multiple blocks (e.g. produced by `xz -T0` / `xz -T N`). Files compressed
/// with default single-threaded `xz` contain a single block and will decode
/// on one thread no matter how many threads are requested. To benefit from
/// this on a single-block archive, recompress with `xz -T0`.
fn open_xz_mt(file: File) -> std::io::Result<XzDecoder<File>> {
    let threads: u32 = std::thread::available_parallelism()
        .map(|n| n.get() as u32)
        .unwrap_or(1);

    // Note: `MtStreamBuilder` in liblzma 0.4 does not expose a `flags()`
    // setter; the underlying `lzma_mt.flags` defaults to 0, which is correct
    // for ordinary single-stream `.xz` files (the common case for SCC/SOS
    // archives). Streams that are the concatenation of several `.xz` files
    // would require `LZMA_CONCATENATED`, which is not reachable here.
    let stream_result: Result<Stream, _> = MtStreamBuilder::new()
        .threads(threads.max(1))
        .memlimit_stop(u64::MAX)
        .decoder();

    match stream_result {
        Ok(stream) => Ok(XzDecoder::new_stream(file, stream)),
        Err(_) => Ok(XzDecoder::new(file)),
    }
}

struct CompiledParser {
    spec_index: usize,
    re: Regex,
}

/// Check whether *any* active parser's file pattern matches `member_path`.
///
/// Used as a fast pre-filter before reading the content of an archive member,
/// so that large files which no parser cares about are skipped entirely
/// (no `read_to_end`, no inner-decompress, no UTF-8 decode).
fn any_parser_matches(member_path: &str, active: &[CompiledParser]) -> bool {
    let probe = format!("/{member_path}");
    active.iter().any(|cp| cp.re.is_match(&probe))
}

/// Bookkeeping-only update for skipped (non-matching) entries: increment
/// `file_count` and the file-type histogram without reading content.
fn record_skipped(member_path: &str, results: &mut ArchiveResults) {
    results.file_count += 1;
    let ext = Path::new(member_path)
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| format!(".{s}"))
        .unwrap_or_else(|| "(none)".to_string());
    *results.file_types.entry(ext).or_insert(0) += 1;
}

/// Apply the matching parsers to a single archive member's text content.
fn process_entry(
    member_path: &str,
    content: &str,
    specs: &[ParserSpec],
    active: &[CompiledParser],
    results: &mut ArchiveResults,
    debug: bool,
) {
    results.file_count += 1;
    let ext = Path::new(member_path)
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| format!(".{s}"))
        .unwrap_or_else(|| "(none)".to_string());
    *results.file_types.entry(ext).or_insert(0) += 1;

    let probe = format!("/{member_path}");
    let matching: Vec<&CompiledParser> =
        active.iter().filter(|cp| cp.re.is_match(&probe)).collect();
    if matching.is_empty() {
        return;
    }

    results.matched_files += 1;
    if debug {
        let names: Vec<&str> = matching
            .iter()
            .map(|cp| specs[cp.spec_index].name)
            .collect();
        eprintln!(
            "[debug] {member_path} ({} chars) -> {}",
            content.len(),
            names.join(", ")
        );
    }

    // Each matching parser is independent and CPU-bound (regex-heavy). When
    // a single file matches several parsers (common for SCC log/config
    // bundles) we run them on the rayon thread pool so they overlap.
    // The outer call site already lives inside a `par_bridge` worker, but
    // rayon nested-parallelism is cooperative and adds no overhead when the
    // pool is saturated -- the inner `into_par_iter` simply yields back.
    use rayon::prelude::*;
    let parsed_outputs: Vec<(usize, Value)> = matching
        .par_iter()
        .filter_map(|cp| {
            let spec = &specs[cp.spec_index];
            let raw = (spec.func)(content, member_path);
            match serde_json::from_str::<Value>(&raw) {
                Ok(v) => Some((cp.spec_index, v)),
                Err(e) => {
                    if debug {
                        eprintln!(
                            "[debug] parser '{}' produced invalid JSON on {member_path}: {e}",
                            spec.name
                        );
                    }
                    None
                }
            }
        })
        .collect();

    for (spec_index, parsed) in parsed_outputs {
        let spec = &specs[spec_index];
        let key = spec.name.to_string();
        if spec.multi_file {
            let prev = results.parser_results.remove(&key).unwrap_or(Value::Null);
            results.parser_results.insert(key, merge(prev, parsed));
        } else {
            let is_empty = match &parsed {
                Value::Object(o) => !o.get("found").and_then(Value::as_bool).unwrap_or(false),
                Value::Array(a) => a.is_empty(),
                _ => false,
            };
            if !results.parser_results.contains_key(&key) || !is_empty {
                results.parser_results.insert(key, parsed);
            }
        }
    }
}

/// Walk an archive (or plaintext log) at `path`, dispatch each member to the
/// matching parsers, and return the merged [`ArchiveResults`].
///
/// `parser_filter`, when `Some(name)`, restricts the run to the single parser
/// with that registry name. `debug` enables per-file dispatch logging to
/// stderr.
pub fn process_archive(
    path: &Path,
    parser_filter: Option<&str>,
    debug: bool,
) -> Result<ArchiveResults, String> {
    let specs = parsers();
    let active: Vec<CompiledParser> = specs
        .iter()
        .enumerate()
        .filter(|(_, s)| parser_filter.map_or(true, |n| n == s.name))
        .map(|(i, s)| {
            Regex::new(s.pattern)
                .map(|re| CompiledParser { spec_index: i, re })
                .map_err(|e| format!("invalid regex for {}: {e}", s.name))
        })
        .collect::<Result<_, _>>()?;

    if let Some(name) = parser_filter {
        if active.is_empty() {
            return Err(format!(
                "Unknown parser '{name}'. Use --list-parsers to see names."
            ));
        }
    }

    let mut results = ArchiveResults {
        file_count: 0,
        matched_files: 0,
        parser_results: BTreeMap::new(),
        file_types: BTreeMap::new(),
    };

    if detect_format(path) == "zip" {
        let file = File::open(path).map_err(|e| format!("opening {}: {e}", path.display()))?;
        let mut zip = zip::ZipArchive::new(file).map_err(|e| format!("zip open: {e}"))?;
        for i in 0..zip.len() {
            let mut entry = match zip.by_index(i) {
                Ok(e) => e,
                Err(e) => {
                    if debug {
                        eprintln!("[debug] zip entry {i} error: {e}");
                    }
                    continue;
                }
            };
            if !entry.is_file() {
                continue;
            }
            let name = entry.name().to_string();
            // Pre-filter: skip the read entirely if no parser cares about
            // either the original name or the inner-decompressed name.
            let candidate = name
                .strip_suffix(".gz")
                .or_else(|| name.strip_suffix(".xz"))
                .unwrap_or(&name);
            if !any_parser_matches(&name, &active) && !any_parser_matches(candidate, &active) {
                record_skipped(&name, &mut results);
                continue;
            }
            let mut buf = Vec::new();
            if let Err(e) = entry.read_to_end(&mut buf) {
                if debug {
                    eprintln!("[debug] read error {name}: {e}");
                }
                continue;
            }
            let (logical_name, raw) = maybe_decompress_inner(name, buf, debug);
            let content = bytes_to_string(raw);
            process_entry(
                &logical_name,
                &content,
                &specs,
                &active,
                &mut results,
                debug,
            );
        }
        return Ok(results);
    }

    if detect_format(path) == "plaintext" {
        // Mirror the Leptos web UI's `analyze_plaintext` path: read the file
        // as a single console log and route it through the parser registry
        // using a synthetic `messages` basename so the event parsers' file
        // patterns match.
        let mut file = File::open(path).map_err(|e| format!("opening {}: {e}", path.display()))?;
        let mut buf = Vec::new();
        file.read_to_end(&mut buf)
            .map_err(|e| format!("reading {}: {e}", path.display()))?;
        let original_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("input.log")
            .to_string();
        let (_logical_name, raw) = maybe_decompress_inner(original_name.clone(), buf, debug);
        let content = bytes_to_string(raw);
        // Use a synthetic path that ends in `/messages` (with the original
        // name preserved as a parent directory) so file-pattern regexes
        // like `/(messages|localmessages|...)` match while the original
        // filename remains visible in the file inventory.
        let synthetic = format!("{original_name}/messages");
        process_entry(&synthetic, &content, &specs, &active, &mut results, debug);
        return Ok(results);
    }

    // ---- Tar branch (parallel) -------------------------------------------
    //
    // The reader thread walks the tar sequentially (libtar can't be split),
    // pre-filters by path, increments bookkeeping for skipped entries, and
    // pushes (logical_name, raw_bytes) for matching entries through a bounded
    // crossbeam channel. Inner-archive decompression and UTF-8 decoding plus
    // the regex-heavy parser dispatch happen in parallel on the rayon thread
    // pool via `par_bridge` + `fold` + `reduce`.
    let active = Arc::new(active);
    let specs = Arc::new(specs);
    let multi_file_lookup: HashMap<&str, bool> =
        specs.iter().map(|s| (s.name, s.multi_file)).collect();

    let workers = rayon::current_num_threads().max(1);
    let (tx, rx) = bounded::<(String, Vec<u8>)>(workers * 4);

    let path_for_reader = path.to_path_buf();
    let active_for_reader = Arc::clone(&active);
    let reader_handle = std::thread::spawn(move || -> Result<ArchiveResults, String> {
        let mut local = ArchiveResults::default();
        let reader = open_tar_reader(&path_for_reader)
            .map_err(|e| format!("opening {}: {e}", path_for_reader.display()))?;
        let mut archive = Archive::new(reader);
        for entry in archive
            .entries()
            .map_err(|e| format!("reading entries: {e}"))?
        {
            let mut entry = match entry {
                Ok(e) => e,
                Err(e) => {
                    if debug {
                        eprintln!("[debug] entry error: {e}");
                    }
                    continue;
                }
            };
            if !entry.header().entry_type().is_file() {
                continue;
            }
            let path_in_tar = match entry.path() {
                Ok(p) => p.to_string_lossy().into_owned(),
                Err(_) => continue,
            };
            let candidate = path_in_tar
                .strip_suffix(".gz")
                .or_else(|| path_in_tar.strip_suffix(".xz"))
                .unwrap_or(&path_in_tar);
            if !any_parser_matches(&path_in_tar, &active_for_reader)
                && !any_parser_matches(candidate, &active_for_reader)
            {
                record_skipped(&path_in_tar, &mut local);
                continue;
            }
            let mut buf = Vec::new();
            if let Err(e) = entry.read_to_end(&mut buf) {
                if debug {
                    eprintln!("[debug] read error {path_in_tar}: {e}");
                }
                continue;
            }
            if tx.send((path_in_tar, buf)).is_err() {
                break;
            }
        }
        // Dropping `tx` here closes the channel so the workers' iterator
        // terminates and `reduce` can return.
        drop(tx);
        Ok(local)
    });

    let active_for_workers = Arc::clone(&active);
    let specs_for_workers = Arc::clone(&specs);
    let worker_results: ArchiveResults = rx
        .into_iter()
        .par_bridge()
        .fold(ArchiveResults::default, |mut acc, (name, buf)| {
            let (logical_name, raw) = maybe_decompress_inner(name, buf, debug);
            let content = bytes_to_string(raw);
            process_entry(
                &logical_name,
                &content,
                &specs_for_workers,
                &active_for_workers,
                &mut acc,
                debug,
            );
            acc
        })
        .reduce(ArchiveResults::default, |a, b| {
            merge_archive_results(&multi_file_lookup, a, b)
        });

    let reader_results = reader_handle
        .join()
        .map_err(|_| "reader thread panicked".to_string())??;
    let merged = merge_archive_results(&multi_file_lookup, reader_results, worker_results);

    Ok(merged)
}

/// Analyze an archive (or plaintext log) and return the combined JSON value
/// (`{fileCount, matchedFiles, fileTypes, ...parsers}`).
///
/// Convenience wrapper over [`process_archive`] + [`ArchiveResults::to_json`]
/// for in-process consumers that want the same shape as the CLI `--json`
/// output.
pub fn analyze_archive(
    path: &Path,
    parser_filter: Option<&str>,
    debug: bool,
) -> Result<Value, String> {
    Ok(process_archive(path, parser_filter, debug)?.to_json())
}
