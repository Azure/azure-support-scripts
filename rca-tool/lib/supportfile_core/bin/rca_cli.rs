//! `rca_cli` — pure-Rust example CLI for the `supportfile` library.
//!
//! Mirrors the Python example under `lib/supportfile_py/examples/rca_cli.py`
//! and the JavaScript CLI under `rca-tool/cli/cli.js`. It walks a
//! supportconfig (SCC) or sosreport (SOS) archive (`.tar`, `.tar.gz`,
//! `.tar.xz`), routes each member to one or more `parse_*_json` functions
//! based on a regex registry, decodes the JSON, optionally merges multi-file
//! results, and prints either a human summary or raw JSON.
//!
//! Build & run from the workspace:
//!
//! ```text
//! cd rca-tool/lib/supportfile_core
//! cargo run --example rca_cli -- ../../tests/fixtures/scc_test-azure-vm.tar.xz
//! cargo run --example rca_cli -- ../../tests/fixtures/scc_test-azure-vm.tar.xz --json
//! cargo run --example rca_cli -- --list-parsers
//! ```

use std::collections::BTreeMap;
use std::env;
use std::fs::File;
use std::io::Read;
use std::path::Path;
use std::process::ExitCode;

use flate2::read::GzDecoder;
use liblzma::read::XzDecoder;
use liblzma::stream::{MtStreamBuilder, Stream};
use regex::Regex;
use serde_json::{Map, Value};
use supportfile as sf;
use tar::Archive;

// ---------------------------------------------------------------------------
// Parser registry
// ---------------------------------------------------------------------------

/// Parser entry point used by the registry.
///
/// All parsers receive `(content, source_path)`. Parsers that have not yet
/// been migrated to carry source provenance simply ignore `source_path`; this
/// is achieved with the `compat_shims!` macro below.
type ParseFn = fn(&str, &str) -> String;

struct ParserSpec {
    /// Output key under which results are stored.
    name: &'static str,
    /// Regex applied to each member's path (with a leading `/`).
    pattern: &'static str,
    /// Pointer to one of the `parse_*_json` functions in `supportfile`.
    func: ParseFn,
    /// When true, results from successive matching files are merged.
    multi_file: bool,
}

/// Generate compatibility shims for parser functions that still take only
/// `content`. Each shim has the same name as the underlying `sf::` function
/// and shadows the `sf::` import within this example module.
macro_rules! compat_shims {
    ($($name:ident),* $(,)?) => {
        $(
            fn $name(content: &str, _source_path: &str) -> String {
                sf::$name(content)
            }
        )*
    };
}

compat_shims!(
);

fn parsers() -> Vec<ParserSpec> {
    vec![
        // ----- Cluster ----------------------------------------------------
        ParserSpec {
            name: "highCpuEvents",
            pattern: r"/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|localmessages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?(?:\.gz)?$|/ha\.txt$",
            func: sf::parse_pacemaker_high_cpu_json,
            multi_file: true,
        },
        ParserSpec {
            name: "clusterEvents",
            pattern: r"/(pacemaker\.log|corosync\.log|cluster\.log|ha-log|messages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?(?:\.gz)?$|/ha\.txt$",
            func: sf::parse_cluster_events_json,
            multi_file: true,
        },
        ParserSpec {
            name: "clusterStatus",
            pattern: r"cib\.xml$|/crm_mon.*\.txt$|/crm_mon.*\.xml$|/ha\.txt$|/pcs_status",
            func: sf::parse_cluster_status_json,
            multi_file: false,
        },
        ParserSpec {
            name: "corosyncConfig",
            pattern: r"/(ha\.txt|corosync\.conf)$",
            func: sf::parse_corosync_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "clusterMaintenanceMode",
            pattern: r"cib\.xml$|/crm_mon.*\.txt$|/ha\.txt$",
            func: sf::parse_cluster_maintenance_mode_json,
            multi_file: false,
        },
        // ----- Automation -------------------------------------------------
        ParserSpec {
            name: "automationEvents",
            pattern: r"/(messages|localmessages|syslog|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$",
            func: sf::parse_automation_events_json,
            multi_file: true,
        },
        // ----- Azure ------------------------------------------------------
        ParserSpec {
            name: "azureVMProperties",
            pattern: r"(?:instance_metadata\.json|public_cloud/metadata\.txt)$",
            func: sf::parse_azure_vm_properties_json,
            multi_file: false,
        },
        ParserSpec {
            name: "suseCloudRegister",
            pattern: r"public_cloud/cloudregister\.txt$",
            func: sf::parse_suse_cloud_register_json,
            multi_file: false,
        },
        ParserSpec {
            name: "waagentConfig",
            pattern: r"/etc/waagent\.conf$",
            func: sf::parse_waagent_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "waagentLog",
            pattern: r"/waagent\.log$",
            func: sf::parse_waagent_log_json,
            multi_file: false,
        },
        ParserSpec {
            name: "azureExtensions",
            pattern: r"var/lib/waagent/[^/]+/config/HandlerStatus$",
            func: sf::parse_azure_extensions_json,
            multi_file: true,
        },
        // ----- Debugfs ----------------------------------------------------
        ParserSpec {
            name: "hvBalloon",
            pattern: r"sys/kernel/debug/hv[-_]balloon$",
            func: sf::parse_hv_balloon_json,
            multi_file: false,
        },
        ParserSpec {
            name: "extfrag",
            pattern: r"sys/kernel/debug/extfrag/(extfrag_index|unusable_index)$",
            func: sf::parse_extfrag_json,
            multi_file: true,
        },
        // ----- System events ---------------------------------------------
        ParserSpec {
            name: "emergencyMode",
            pattern: r"/(messages|localmessages|journalctl[^/]*|console.*\.log)(?:[.-]\d+)?(?:\.txt)?$",
            func: sf::parse_emergency_mode_json,
            multi_file: true,
        },
        ParserSpec {
            name: "kernelReboots",
            pattern: r"/(messages|localmessages|ha-log|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$",
            func: sf::parse_kernel_reboots_json,
            multi_file: true,
        },
        ParserSpec {
            name: "oomKiller",
            pattern: r"/(messages|localmessages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$",
            func: sf::parse_oom_killer_json,
            multi_file: true,
        },
        ParserSpec {
            name: "xfsErrors",
            pattern: r"/(messages|localmessages|journalctl[^/]*)(?:[.-]\d+)?(?:\.txt)?$",
            func: sf::parse_xfs_errors_json,
            multi_file: true,
        },
        // ----- Networking -------------------------------------------------
        ParserSpec {
            name: "firewallRules",
            pattern: r"network\.txt$|sos_commands/firewalld/|sos_commands/firewall_tables/|etc/sysconfig/(?:iptables-config|ebtables-config|nftables\.conf|firewalld)$|etc/firewalld/firewalld\.conf$",
            func: sf::parse_firewall_rules_json,
            multi_file: true,
        },
        ParserSpec {
            name: "networkInterfaces",
            pattern: r"network\.txt$|sos_commands/networking/ip_-o_addr$|sos_commands/networking/ip_-s_-d_link$|sos_commands/networking/ethtool_-i_\w+|sos_commands/networkmanager/nmcli_con_show_id_|etc/sysconfig/network-scripts/ifcfg-|etc/sysconfig/network/(?:network/)?ifcfg-|etc/netplan/|var/log/cloud-init-output\.log$|(?:^|/)messages$",
            func: sf::parse_network_interfaces_json,
            multi_file: true,
        },
        // ----- Packages ---------------------------------------------------
        ParserSpec {
            name: "distroPackages",
            pattern: r"/(rpm\.txt|installed-rpms|package-data|dpkg_-l|dnf[_-]list[_-]installed|yum[_-]list[_-]installed|var/log/zypp/history|var/log/(?:dnf|yum)\.log)$",
            func: sf::parse_distro_packages_json,
            multi_file: false,
        },
        // ----- Services ---------------------------------------------------
        ParserSpec {
            name: "sshServiceIssues",
            pattern: r"/(messages|localmessages|syslog|journalctl[^/]*|console.*\.log)(?:[.-]\d+)?(?:\.txt)?$",
            func: sf::parse_ssh_service_issues_json,
            multi_file: true,
        },
        ParserSpec {
            name: "dlmService",
            pattern: r"sos_commands/systemd/systemctl_list-unit-files$",
            func: sf::parse_dlm_service_json,
            multi_file: false,
        },
        ParserSpec {
            name: "azureSiteRecovery",
            pattern: r"(?:sos_commands/systemd/systemctl_list-unit-files|systemd-status\.txt)$",
            func: sf::parse_azure_site_recovery_json,
            multi_file: false,
        },
        ParserSpec {
            name: "guardicoreAgent",
            pattern: r"(?:sos_commands/systemd/systemctl_list-unit-files|systemd-status\.txt)$",
            func: sf::parse_guardicore_agent_json,
            multi_file: false,
        },
        ParserSpec {
            name: "illumio",
            pattern: r"sos_commands/systemd/systemctl_list-units_--all$",
            func: sf::parse_illumio_json,
            multi_file: false,
        },
        ParserSpec {
            name: "trendMicro",
            pattern: r"sos_commands/systemd/systemctl_list-units_--all$",
            func: sf::parse_trend_micro_json,
            multi_file: false,
        },
        ParserSpec {
            name: "falconSensor",
            pattern: r"/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$",
            func: sf::parse_falcon_sensor_json,
            multi_file: false,
        },
        ParserSpec {
            name: "falconSensorConfig",
            pattern: r"/(falconctl|CrowdStrike.*config|falcon.*conf)$",
            func: sf::parse_falcon_sensor_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "msDefender",
            pattern: r"/(rpm\.txt|installed-rpms|package-data|ps\.txt|ps_.*\.txt)$",
            func: sf::parse_ms_defender_json,
            multi_file: false,
        },
        ParserSpec {
            name: "msDefenderConfig",
            pattern: r"/(mdatp.*|defender.*config)$",
            func: sf::parse_ms_defender_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "involfltVersion",
            pattern: r"modules\.txt$",
            func: sf::parse_involflt_version_json,
            multi_file: false,
        },
        ParserSpec {
            name: "involfltKernelVersion",
            pattern: r"/(messages|boot)(?:[.-]\d+)?(?:\.txt)?$",
            func: sf::parse_involflt_kernel_version_json,
            multi_file: false,
        },
        // ----- Storage ----------------------------------------------------
        ParserSpec {
            name: "lvmConfig",
            pattern: r"/(lvm\.txt|pvs\.txt|vgs\.txt|lvs\.txt|pvdisplay|vgdisplay|lvdisplay)$|/lvm2/pvs_|/lvm2/vgs_|/lvm2/lvs_",
            func: sf::parse_lvm_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "raidConfig",
            pattern: r"/(mdstat|md-arrays\.txt|mdadm\.txt|proc/mdstat)$",
            func: sf::parse_raid_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "btrfsConfig",
            pattern: r"/(btrfs\.txt|fs-btrfs\.txt|btrfs-filesystem-show\.txt|btrfs-subvolume-list\.txt)$",
            func: sf::parse_btrfs_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "blockDevices",
            pattern: r"/sos_commands/block/(lsblk|lsblk_-f_-a_-l|blkid_-c_\.dev\.null)$|(?:^|/)results\.txt$",
            func: sf::parse_block_devices_json,
            multi_file: true,
        },
        ParserSpec {
            name: "fstabAnalysis",
            pattern: r"/etc/fstab$|/fs-diskio\.txt$",
            func: sf::parse_fstab_analysis_json,
            multi_file: false,
        },
        ParserSpec {
            name: "dfOutput",
            pattern: r"/df$|/df_-aliT|/df_-al_|/fs-diskio\.txt$",
            func: sf::parse_df_output_json,
            multi_file: false,
        },
        ParserSpec {
            name: "mtabAnalysis",
            pattern: r"/etc/mtab$|/proc/mounts$|/proc/self/mounts$|/fs-diskio\.txt$|/mount_-l$|/mount$",
            func: sf::parse_mtab_analysis_json,
            multi_file: false,
        },
        // ----- OS / filesystem -------------------------------------------
        ParserSpec {
            name: "basicEnvironment",
            pattern: r"basic-environment\.txt$",
            func: sf::parse_basic_environment_json,
            multi_file: false,
        },
        ParserSpec {
            name: "osRelease",
            pattern: r"/usr/lib/os-release$|/etc/os-release$|/sysinfo\.txt$|/basic-environment\.txt$|/etc/(redhat|centos|SuSE|system)-release$",
            func: sf::parse_os_release_json,
            multi_file: false,
        },
        ParserSpec {
            name: "fstab",
            pattern: r"/etc/fstab$|/fs-diskio\.txt$",
            func: sf::parse_fstab_json,
            multi_file: false,
        },
        ParserSpec {
            name: "inspectDiskResults",
            pattern: r"(?:^|/)results\.txt$",
            func: sf::parse_inspect_disk_results_json,
            multi_file: false,
        },
        // ----- Kernel tuning ---------------------------------------------
        ParserSpec {
            name: "kernelTuning",
            pattern: r"sos_commands/kernel/sysctl_-a$|/env\.txt$|/etc/sysctl\.conf$|/sysctl\.d/[^/]*\.conf$",
            func: sf::parse_kernel_tuning_json,
            multi_file: false,
        },
        ParserSpec {
            name: "hugePages",
            pattern: r"/proc/meminfo$",
            func: sf::parse_huge_pages_json,
            multi_file: false,
        },
        // ----- Time sync (Azure PTP) -------------------------------------
        ParserSpec {
            name: "timeSync",
            pattern: r"sos_commands/kernel/lsmod$|/modules\.txt$",
            func: sf::parse_time_sync_json,
            multi_file: false,
        },
        ParserSpec {
            name: "ptpClockSource",
            pattern: r"sos_commands/chrony/chronyc_sources$|/etc/chrony\.conf$|/etc/chrony/chrony\.conf$|/ntp\.txt$",
            func: sf::parse_ptp_clock_source_json,
            multi_file: false,
        },
        ParserSpec {
            name: "timeSyncService",
            pattern: r"sos_commands/systemd/systemctl_list-unit-files$|/systemd-status\.txt$|/ntp\.txt$",
            func: sf::parse_time_sync_service_json,
            multi_file: false,
        },
        ParserSpec {
            name: "timedatectl",
            pattern: r"sos_commands/systemd/timedatectl$|/ntp\.txt$",
            func: sf::parse_timedatectl_json,
            multi_file: false,
        },
        ParserSpec {
            name: "ptpDevice",
            pattern: r"sos_commands/block/ls_-lanR_\.dev$|/udev\.txt$",
            func: sf::parse_ptp_device_json,
            multi_file: false,
        },
        ParserSpec {
            name: "chronyTracking",
            pattern: r"sos_commands/chrony/chronyc_tracking$|/ntp\.txt$",
            func: sf::parse_chrony_tracking_json,
            multi_file: false,
        },
        ParserSpec {
            name: "chronyMakestep",
            pattern: r"/etc/chrony\.conf$|/etc/chrony/chrony\.conf$|/ntp\.txt$",
            func: sf::parse_chrony_makestep_json,
            multi_file: false,
        },
        // ----- RHUI ------------------------------------------------------
        ParserSpec {
            name: "rhuiConfig",
            pattern: r"/(rh-cloud.*\.repo|rhui-.*\.repo|yum\.repos\.d\.txt|dnf\.repos\.d\.txt|yum\.repos\.d/.*\.repo)$",
            func: sf::parse_rhui_config_json,
            multi_file: false,
        },
        ParserSpec {
            name: "eusVersionLock",
            pattern: r"/(releasever|yum-vars\.txt|dnf-vars\.txt|etc/yum/vars|etc/dnf/vars|dnf/vars/releasever|yum/vars/releasever)$",
            func: sf::parse_eus_version_lock_json,
            multi_file: false,
        },
        ParserSpec {
            name: "rhelRhuiCheck",
            pattern: r"/(installed-rpms|rpm-qa\.txt|rpm_-qa|package-data)$",
            func: sf::parse_rhel_rhui_check_json,
            multi_file: false,
        },
        ParserSpec {
            name: "rhuiErrors",
            pattern: r"/(dnf\.log|yum\.log|rhsm\.log)(\.\d+)?$",
            func: sf::parse_rhui_errors_json,
            multi_file: true,
        },
        // ----- Security --------------------------------------------------
        ParserSpec {
            name: "cryptoPolicies",
            pattern: r"/crypto-policies/(config|state/current)$",
            func: sf::parse_crypto_policies_json,
            multi_file: false,
        },
        ParserSpec {
            name: "fipsModeSetup",
            pattern: r"sos_commands/crypto/fips-mode-setup",
            func: sf::parse_fips_mode_setup_json,
            multi_file: false,
        },
        ParserSpec {
            name: "kernelCmdline",
            pattern: r"/proc/cmdline$|/boot\.txt$",
            func: sf::parse_kernel_cmdline_json,
            multi_file: false,
        },
        // ----- Leapp -----------------------------------------------------
        ParserSpec {
            name: "leappReport",
            pattern: r"var/log/leapp/leapp-report\.(txt|json)$",
            func: sf::parse_leapp_report_json,
            multi_file: false,
        },
        ParserSpec {
            name: "leappLog",
            pattern: r"var/log/leapp/leapp-(preupgrade|upgrade)\.log$",
            func: sf::parse_leapp_log_json,
            multi_file: false,
        },
        // ----- vmcore / kdump --------------------------------------------
        ParserSpec {
            name: "vmcoreDmesg",
            pattern: r"var/crash/[^/]+/vmcore-dmesg\.txt$",
            func: sf::parse_vmcore_dmesg_json,
            multi_file: true,
        },
        ParserSpec {
            name: "kdumpStatus",
            pattern: r"sos_commands/kdump/kdumpctl_status$",
            func: sf::parse_kdump_status_json,
            multi_file: false,
        },
        ParserSpec {
            name: "crashListing",
            pattern: r"sos_commands/kdump/ls_-alZR_\.var\.crash$",
            func: sf::parse_crash_listing_json,
            multi_file: false,
        },
        ParserSpec {
            name: "kdumpConf",
            pattern: r"etc/kdump\.conf$",
            func: sf::parse_kdump_conf_json,
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
                        "found" => Value::Bool(prev.as_bool().unwrap_or(false) || v.as_bool().unwrap_or(false)),
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

fn is_empty_scalar(v: &Value) -> bool {
    match v {
        Value::Null => true,
        Value::Bool(b) => !*b,
        Value::Number(n) => n.as_f64().map(|x| x == 0.0).unwrap_or(false),
        Value::String(s) => s.is_empty(),
        Value::Array(a) => a.is_empty(),
        Value::Object(o) => o.is_empty(),
    }
}

fn has_data(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64().map(|x| x != 0.0).unwrap_or(false),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => {
            if o.get("found").and_then(Value::as_bool).unwrap_or(false) {
                return true;
            }
            if let Some(c) = o.get("count").and_then(Value::as_i64) {
                if c > 0 {
                    return true;
                }
            }
            for (k, val) in o {
                if matches!(k.as_str(), "found" | "count" | "warnings" | "errors") {
                    continue;
                }
                if !is_empty_scalar(val) {
                    return true;
                }
            }
            false
        }
    }
}

// ---------------------------------------------------------------------------
// Archive processing
// ---------------------------------------------------------------------------

struct ArchiveResults {
    file_count: usize,
    matched_files: usize,
    parser_results: BTreeMap<String, Value>,
    file_types: BTreeMap<String, usize>,
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
    } else {
        "tar" // best effort
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
        let names: Vec<&str> = matching.iter().map(|cp| specs[cp.spec_index].name).collect();
        eprintln!(
            "[debug] {member_path} ({} chars) -> {}",
            content.len(),
            names.join(", ")
        );
    }

    for cp in matching {
        let spec = &specs[cp.spec_index];
        let raw = (spec.func)(content, member_path);
        let parsed: Value = match serde_json::from_str(&raw) {
            Ok(v) => v,
            Err(e) => {
                if debug {
                    eprintln!(
                        "[debug] parser '{}' produced invalid JSON on {member_path}: {e}",
                        spec.name
                    );
                }
                continue;
            }
        };

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

fn process_archive(
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
            let mut buf = Vec::new();
            if let Err(e) = entry.read_to_end(&mut buf) {
                if debug {
                    eprintln!("[debug] read error {name}: {e}");
                }
                continue;
            }
            let content = String::from_utf8_lossy(&buf).into_owned();
            process_entry(&name, &content, &specs, &active, &mut results, debug);
        }
        return Ok(results);
    }

    let reader = open_tar_reader(path).map_err(|e| format!("opening {}: {e}", path.display()))?;
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
        let mut buf = Vec::new();
        if let Err(e) = entry.read_to_end(&mut buf) {
            if debug {
                eprintln!("[debug] read error {path_in_tar}: {e}");
            }
            continue;
        }
        let content = String::from_utf8_lossy(&buf).into_owned();
        process_entry(&path_in_tar, &content, &specs, &active, &mut results, debug);
    }

    Ok(results)
}

// ---------------------------------------------------------------------------
// Output formatting
// ---------------------------------------------------------------------------

const SEP: &str = "======================================================================";
const SUB: &str = "----------------------------------------------------------------------";

fn section(title: &str) -> String {
    format!("\n{SUB}\n{title}\n{SUB}\n")
}

fn list_warnings(items: Option<&Value>, indent: &str) -> String {
    let Some(Value::Array(arr)) = items else {
        return String::new();
    };
    let mut out = String::new();
    for w in arr {
        if let Value::Object(o) = w {
            let severity = o
                .get("severity")
                .and_then(Value::as_str)
                .unwrap_or("warn")
                .to_uppercase();
            let msg = o
                .get("message")
                .and_then(Value::as_str)
                .or_else(|| o.get("type").and_then(Value::as_str))
                .map(|s| s.to_string())
                .unwrap_or_else(|| serde_json::to_string(w).unwrap_or_default());
            out.push_str(&format!("{indent}[{severity}] {msg}\n"));
            if let Some(rec) = o.get("recommendation").and_then(Value::as_str) {
                out.push_str(&format!("{indent}        Recommendation: {rec}\n"));
            }
        } else if let Some(s) = w.as_str() {
            out.push_str(&format!("{indent}[WARN] {s}\n"));
        }
    }
    out
}

fn s(o: &Map<String, Value>, k: &str) -> Option<String> {
    o.get(k).and_then(|v| match v {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    })
}

fn arr_len(v: Option<&Value>) -> usize {
    v.and_then(|x| x.as_array()).map(|a| a.len()).unwrap_or(0)
}

fn obj<'a>(r: &'a BTreeMap<String, Value>, k: &str) -> Option<&'a Map<String, Value>> {
    r.get(k).and_then(|v| v.as_object())
}

fn count_events(r: &BTreeMap<String, Value>, k: &str) -> i64 {
    match r.get(k) {
        Some(Value::Object(o)) => o
            .get("count")
            .and_then(Value::as_i64)
            .unwrap_or_else(|| arr_len(o.get("events")) as i64),
        Some(Value::Array(a)) => a.len() as i64,
        _ => 0,
    }
}

fn format_text(results: &ArchiveResults) -> String {
    let r = &results.parser_results;
    let mut out = format!("\n{SEP}\n  RCA Analysis Results (rust)\n{SEP}\n\n");
    out.push_str(&format!("Files processed: {}\n", results.file_count));
    out.push_str(&format!(
        "Files matched by parsers: {}\n\n",
        results.matched_files
    ));

    let has = |k: &str| r.get(k).map_or(false, has_data);

    // ----- Azure VM properties / OS -----
    if has("azureVMProperties") || has("osRelease") {
        out.push_str(&section("AZURE VM PROPERTIES"));
        if let Some(vm) = obj(r, "azureVMProperties") {
            for (label, key) in [
                ("VM Size", "vm_size"),
                ("Publisher", "publisher"),
                ("Offer", "offer"),
                ("SKU", "sku"),
                ("License Type", "license_type"),
                ("Billing Model", "billing_model"),
                ("Detection Method", "detection_method"),
                ("OS Disk Type", "os_disk_type"),
            ] {
                if let Some(v) = s(vm, key) {
                    if !v.is_empty() {
                        out.push_str(&format!("  {label}: {v}\n"));
                    }
                }
            }
            if let Some(disks) = vm.get("data_disks").and_then(Value::as_array) {
                if !disks.is_empty() {
                    out.push_str(&format!("  Data Disks: {}\n", disks.len()));
                }
            }
        }
        if let Some(osrel) = obj(r, "osRelease") {
            if has("osRelease") {
                out.push_str("  Operating System:\n");
                if let Some(name) = s(osrel, "pretty_name").or_else(|| s(osrel, "name")) {
                    out.push_str(&format!("    Distribution: {name}\n"));
                }
                if let Some(v) = s(osrel, "version_id") {
                    out.push_str(&format!("    Version: {v}\n"));
                }
            }
        }
        out.push('\n');
    }

    // ----- Cluster -----
    if ["corosyncConfig", "clusterStatus", "clusterMaintenanceMode"]
        .iter()
        .any(|k| has(k))
    {
        out.push_str(&section("CLUSTER"));
        if let Some(cc) = obj(r, "corosyncConfig") {
            if has_data(&Value::Object(cc.clone())) {
                out.push_str("  Corosync:\n");
                for (label, key) in [
                    ("Token", "totem_token"),
                    ("Consensus", "totem_consensus"),
                    ("Transport", "totem_transport"),
                    ("Quorum provider", "quorum_provider"),
                    ("Expected votes", "quorum_expected_votes"),
                    ("Two-node mode", "quorum_two_node"),
                ] {
                    if let Some(v) = s(cc, key) {
                        out.push_str(&format!("    {label}: {v}\n"));
                    }
                }
                out.push_str(&list_warnings(cc.get("warnings"), "    "));
            }
        }
        if let Some(cs) = obj(r, "clusterStatus") {
            if has_data(&Value::Object(cs.clone())) {
                out.push_str("  Status:\n");
                for (label, key) in [
                    ("Cluster name", "cluster_name"),
                    ("DC node", "dc_node"),
                    ("Nodes configured", "nodes_configured"),
                    ("Resources configured", "resources_configured"),
                    ("Quorum status", "quorum_status"),
                ] {
                    if let Some(v) = s(cs, key) {
                        out.push_str(&format!("    {label}: {v}\n"));
                    }
                }
                if let Some(ns) = cs.get("node_statuses").and_then(Value::as_array) {
                    for n in ns {
                        if let Some(o) = n.as_object() {
                            let name = s(o, "name").unwrap_or_default();
                            let state = if o.get("online").and_then(Value::as_bool).unwrap_or(false)
                            {
                                "online"
                            } else {
                                "offline"
                            };
                            out.push_str(&format!("    - {name}: {state}\n"));
                        }
                    }
                }
            }
        }
        if let Some(mm) = obj(r, "clusterMaintenanceMode") {
            if has_data(&Value::Object(mm.clone())) {
                let on = mm
                    .get("maintenance_mode")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                out.push_str(&format!(
                    "  Maintenance Mode: {}\n",
                    if on { "YES" } else { "no" }
                ));
                let res = arr_len(mm.get("resources_in_maintenance"));
                if res > 0 {
                    out.push_str(&format!("    Resources in maintenance: {res}\n"));
                }
            }
        }
        out.push('\n');
    }

    // ----- Storage -----
    let storage_keys = [
        "lvmConfig",
        "raidConfig",
        "btrfsConfig",
        "blockDevices",
        "fstabAnalysis",
        "dfOutput",
        "mtabAnalysis",
    ];
    if storage_keys.iter().any(|k| has(k)) {
        out.push_str(&section("STORAGE"));
        if let Some(bd) = obj(r, "blockDevices") {
            if has_data(&Value::Object(bd.clone())) {
                out.push_str(&format!(
                    "  Block Devices: {} disk(s), {} partition(s)\n",
                    arr_len(bd.get("disks")),
                    arr_len(bd.get("partitions"))
                ));
            }
        }
        if let Some(lvm) = obj(r, "lvmConfig") {
            if has_data(&Value::Object(lvm.clone())) {
                out.push_str(&format!(
                    "  LVM: {} PV(s), {} VG(s), {} LV(s)\n",
                    arr_len(lvm.get("pvs")),
                    arr_len(lvm.get("vgs")),
                    arr_len(lvm.get("lvs"))
                ));
                out.push_str(&list_warnings(lvm.get("warnings"), "    "));
            }
        }
        if let Some(raid) = obj(r, "raidConfig") {
            if has_data(&Value::Object(raid.clone())) {
                let n = arr_len(raid.get("arrays"));
                if n > 0 {
                    out.push_str(&format!("  RAID Arrays: {n}\n"));
                }
                out.push_str(&list_warnings(raid.get("warnings"), "    "));
            }
        }
        if let Some(btrfs) = obj(r, "btrfsConfig") {
            if has_data(&Value::Object(btrfs.clone())) {
                out.push_str(&format!(
                    "  BTRFS: {} fs, {} subvol(s)\n",
                    arr_len(btrfs.get("filesystems")),
                    arr_len(btrfs.get("subvolumes"))
                ));
            }
        }
        if let Some(fa) = obj(r, "fstabAnalysis") {
            if has_data(&Value::Object(fa.clone())) {
                out.push_str(&format!(
                    "  Fstab entries: {}\n",
                    arr_len(fa.get("entries"))
                ));
                out.push_str(&list_warnings(fa.get("warnings"), "    "));
            }
        }
        if let Some(df) = obj(r, "dfOutput") {
            if has_data(&Value::Object(df.clone())) {
                out.push_str(&format!(
                    "  df entries: {}\n",
                    arr_len(df.get("filesystems"))
                ));
            }
        }
        if let Some(mt) = obj(r, "mtabAnalysis") {
            if has_data(&Value::Object(mt.clone())) {
                let extras = arr_len(mt.get("extra_mounts"));
                let mut line = format!("  Mtab entries: {}", arr_len(mt.get("entries")));
                if extras > 0 {
                    line.push_str(&format!(" ({extras} not in fstab)"));
                }
                line.push('\n');
                out.push_str(&line);
            }
        }
        out.push('\n');
    }

    // ----- Networking -----
    if ["networkInterfaces", "firewallRules", "sshServiceIssues"]
        .iter()
        .any(|k| has(k))
    {
        out.push_str(&section("NETWORKING"));
        if let Some(ni) = obj(r, "networkInterfaces") {
            if has_data(&Value::Object(ni.clone())) {
                if let Some(ifaces) = ni.get("interfaces").and_then(Value::as_object) {
                    let real: Vec<(&String, &Value)> =
                        ifaces.iter().filter(|(n, _)| n.as_str() != "lo").collect();
                    let accelnet = real.iter().any(|(_, v)| {
                        v.as_object()
                            .and_then(|o| o.get("accel_net").and_then(Value::as_bool))
                            .unwrap_or(false)
                    });
                    out.push_str(&format!(
                        "  Network Interfaces: {} interface(s){}\n",
                        real.len(),
                        if accelnet {
                            " [Accelerated Networking]"
                        } else {
                            ""
                        }
                    ));
                    for (_, v) in &real {
                        if let Some(i) = v.as_object() {
                            let name = s(i, "name").unwrap_or_default();
                            let state = s(i, "state").unwrap_or_else(|| "-".into());
                            let mac = s(i, "mac").unwrap_or_else(|| "-".into());
                            let driver = s(i, "driver").unwrap_or_else(|| "-".into());
                            let ipv4 = i
                                .get("ipv4")
                                .and_then(Value::as_array)
                                .map(|arr| {
                                    let parts: Vec<String> = arr
                                        .iter()
                                        .filter_map(|a| {
                                            a.as_object()
                                                .and_then(|o| s(o, "address"))
                                        })
                                        .collect();
                                    if parts.is_empty() {
                                        "-".to_string()
                                    } else {
                                        parts.join(", ")
                                    }
                                })
                                .unwrap_or_else(|| "-".to_string());
                            out.push_str(&format!(
                                "    {name}: {state} | {ipv4} | MAC {mac} | driver {driver}\n"
                            ));
                        }
                    }
                }
            }
        }
        if let Some(fw) = obj(r, "firewallRules") {
            if has_data(&Value::Object(fw.clone())) {
                let active = s(fw, "active_firewall").unwrap_or_else(|| "none".into());
                out.push_str(&format!("  Firewall: active = {active}\n"));
                out.push_str(&list_warnings(fw.get("warnings"), "    "));
            }
        }
        if let Some(ssh) = obj(r, "sshServiceIssues") {
            if has_data(&Value::Object(ssh.clone())) {
                let n = ssh.get("count").and_then(Value::as_i64).unwrap_or(0);
                out.push_str(&format!("  SSH issues: {n} event(s)\n"));
            }
        }
        out.push('\n');
    }

    // ----- Events -----
    let event_counts: Vec<(&str, i64)> = vec![
        ("High CPU", count_events(r, "highCpuEvents")),
        ("Cluster", count_events(r, "clusterEvents")),
        ("Kernel reboots", count_events(r, "kernelReboots")),
        ("OOM killer", count_events(r, "oomKiller")),
        ("XFS errors", count_events(r, "xfsErrors")),
        ("Automation", count_events(r, "automationEvents")),
        ("Emergency mode", count_events(r, "emergencyMode")),
    ];
    if event_counts.iter().any(|(_, c)| *c > 0) {
        out.push_str(&section("EVENTS"));
        for (label, count) in event_counts {
            if count > 0 {
                out.push_str(&format!("  {label}: {count} event(s)\n"));
            }
        }
        out.push('\n');
    }

    // ----- Packages / RHUI -----
    let pkg_keys = [
        "distroPackages",
        "rhuiConfig",
        "rhelRhuiCheck",
        "eusVersionLock",
        "rhuiErrors",
        "cryptoPolicies",
        "fipsModeSetup",
        "kernelCmdline",
        "kernelTuning",
        "hugePages",
    ];
    if pkg_keys.iter().any(|k| has(k)) {
        out.push_str(&section("PACKAGES / DISTRIBUTION"));
        if let Some(dp) = obj(r, "distroPackages") {
            if has_data(&Value::Object(dp.clone())) {
                let count = dp
                    .get("package_count")
                    .and_then(Value::as_i64)
                    .unwrap_or_else(|| {
                        dp.get("packages")
                            .and_then(Value::as_object)
                            .map(|o| o.len() as i64)
                            .unwrap_or(0)
                    });
                out.push_str(&format!("  Packages: {count}\n"));
                out.push_str(&list_warnings(dp.get("warnings"), "    "));
            }
        }
        if let Some(rc) = obj(r, "rhuiConfig") {
            if has_data(&Value::Object(rc.clone())) {
                if let Some(repos) = rc.get("repos").and_then(Value::as_array) {
                    let enabled = repos
                        .iter()
                        .filter(|x| {
                            x.as_object()
                                .and_then(|o| o.get("enabled").and_then(Value::as_bool))
                                .unwrap_or(false)
                        })
                        .count();
                    out.push_str(&format!("  RHUI Repositories: {enabled} enabled\n"));
                }
            }
        }
        if let Some(ev) = obj(r, "eusVersionLock") {
            if has_data(&Value::Object(ev.clone())) {
                let v = s(ev, "releasever").unwrap_or_else(|| "not locked".into());
                out.push_str(&format!("  EUS releasever: {v}\n"));
            }
        }
        if let Some(cp) = obj(r, "cryptoPolicies") {
            if has_data(&Value::Object(cp.clone())) {
                let v = s(cp, "policy").unwrap_or_default();
                out.push_str(&format!("  Crypto Policy: {v}\n"));
            }
        }
        if let Some(fp) = obj(r, "fipsModeSetup") {
            if has_data(&Value::Object(fp.clone())) {
                let on = fp
                    .get("fips_enabled")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                out.push_str(&format!(
                    "  FIPS Mode: {}\n",
                    if on { "enabled" } else { "disabled" }
                ));
            }
        }
        if let Some(kc) = obj(r, "kernelCmdline") {
            if has_data(&Value::Object(kc.clone())) {
                if let Some(v) = s(kc, "cmdline") {
                    out.push_str(&format!("  Kernel cmdline: {v}\n"));
                }
            }
        }
        if let Some(re_) = obj(r, "rhuiErrors") {
            if has_data(&Value::Object(re_.clone())) {
                let n = re_.get("count").and_then(Value::as_i64).unwrap_or(0);
                out.push_str(&format!("  RHUI errors: {n}\n"));
            }
        }
        if let Some(kt) = obj(r, "kernelTuning") {
            if has_data(&Value::Object(kt.clone())) {
                out.push_str("  Kernel tuning:\n");
                if let Some(params) = kt.get("parameters").and_then(Value::as_object) {
                    for k in [
                        "vm.swappiness",
                        "vm.nr_hugepages",
                        "net.core.rmem_max",
                        "net.core.wmem_max",
                    ] {
                        if let Some(v) = params.get(k) {
                            out.push_str(&format!("    {k} = {}\n", v));
                        }
                    }
                }
                out.push_str(&list_warnings(kt.get("azure_network_warnings"), "    "));
            }
        }
        if let Some(hp) = obj(r, "hugePages") {
            if has_data(&Value::Object(hp.clone())) {
                let total = hp
                    .get("total")
                    .and_then(Value::as_i64)
                    .or_else(|| hp.get("nr_hugepages").and_then(Value::as_i64))
                    .unwrap_or(0);
                let mut line = format!("  HugePages: total={total}");
                if let Some(free) = hp
                    .get("free")
                    .and_then(Value::as_i64)
                    .or_else(|| hp.get("free_hugepages").and_then(Value::as_i64))
                {
                    line.push_str(&format!(" free={free}"));
                }
                if let Some(size) = hp
                    .get("size_kb")
                    .and_then(Value::as_i64)
                    .or_else(|| hp.get("hugepagesize_kb").and_then(Value::as_i64))
                {
                    line.push_str(&format!(" size={size}KB"));
                }
                line.push('\n');
                out.push_str(&line);
            }
        }
        out.push('\n');
    }

    // ----- Azure agent / extensions -----
    if [
        "waagentConfig",
        "waagentLog",
        "azureExtensions",
        "suseCloudRegister",
    ]
    .iter()
    .any(|k| has(k))
    {
        out.push_str(&section("AZURE AGENT / EXTENSIONS"));
        if let Some(wc) = obj(r, "waagentConfig") {
            if has_data(&Value::Object(wc.clone())) {
                out.push_str("  waagent.conf: parsed\n");
                out.push_str(&list_warnings(wc.get("warnings"), "    "));
            }
        }
        if let Some(wl) = obj(r, "waagentLog") {
            if has_data(&Value::Object(wl.clone())) {
                let v = s(wl, "agent_version").unwrap_or_else(|| "unknown".into());
                out.push_str(&format!("  waagent.log: agent {v}\n"));
                if wl
                    .get("has_errors")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
                {
                    out.push_str("    [WARN] errors detected\n");
                }
            }
        }
        if let Some(ax) = obj(r, "azureExtensions") {
            if has_data(&Value::Object(ax.clone())) {
                if let Some(events) = ax.get("events").and_then(Value::as_array) {
                    out.push_str(&format!("  Extensions: {}\n", events.len()));
                    for ev in events {
                        if let Some(o) = ev.as_object() {
                            let healthy = o
                                .get("healthy")
                                .and_then(Value::as_bool)
                                .unwrap_or(false);
                            let marker = if healthy { "OK " } else { "BAD" };
                            let label = s(o, "label").unwrap_or_default();
                            let version = s(o, "version").unwrap_or_default();
                            let status = s(o, "status").unwrap_or_default();
                            out.push_str(&format!(
                                "    [{marker}] {label} v{version} -> {status}\n"
                            ));
                        }
                    }
                }
            }
        }
        if let Some(sc) = obj(r, "suseCloudRegister") {
            if has_data(&Value::Object(sc.clone())) {
                let bm = s(sc, "billing_model").unwrap_or_else(|| "n/a".into());
                let rs = s(sc, "registration_server").unwrap_or_else(|| "-".into());
                out.push_str(&format!("  SUSE Cloud Register: {bm} via {rs}\n"));
            }
        }
        out.push('\n');
    }

    // ----- Security software -----
    let sec = [
        ("falconSensor", "CrowdStrike Falcon"),
        ("msDefender", "Microsoft Defender"),
        ("trendMicro", "Trend Micro"),
        ("illumio", "Illumio"),
        ("guardicoreAgent", "Guardicore"),
    ];
    if sec.iter().any(|(k, _)| has(k)) {
        out.push_str(&section("SECURITY SOFTWARE"));
        for (key, label) in sec {
            if let Some(v) = obj(r, key) {
                if has_data(&Value::Object(v.clone())) {
                    let msg = s(v, "message").unwrap_or_default();
                    out.push_str(&format!("  {label}: detected"));
                    if !msg.is_empty() {
                        out.push_str(&format!(" ({msg})"));
                    }
                    out.push('\n');
                }
            }
        }
        out.push('\n');
    }

    // ----- vmcore / kdump -----
    let vm_keys = ["vmcoreDmesg", "kdumpStatus", "crashListing", "kdumpConf"];
    if vm_keys.iter().any(|k| has(k)) {
        out.push_str(&section("KERNEL CRASH DUMPS"));
        if let Some(ks) = obj(r, "kdumpStatus") {
            if has_data(&Value::Object(ks.clone())) {
                let on = ks
                    .get("operational")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                out.push_str(&format!(
                    "  Kdump operational: {}\n",
                    if on { "yes" } else { "no" }
                ));
            }
        }
        if let Some(cl) = obj(r, "crashListing") {
            if has_data(&Value::Object(cl.clone())) {
                let count = cl.get("count").and_then(Value::as_i64).unwrap_or(0);
                let total = s(cl, "total_gb").unwrap_or_else(|| "0".into());
                out.push_str(&format!("  Crash entries: {count}, {total} GB total\n"));
                if let Some(entries) = cl.get("entries").and_then(Value::as_array) {
                    for e in entries.iter().take(5) {
                        if let Some(o) = e.as_object() {
                            let date = s(o, "crash_date").unwrap_or_default();
                            let mb = s(o, "size_mb").unwrap_or_default();
                            out.push_str(&format!("    - {date}: {mb} MB\n"));
                        }
                    }
                }
            }
        }
        if let Some(vd) = obj(r, "vmcoreDmesg") {
            if has_data(&Value::Object(vd.clone())) {
                out.push_str("  Latest vmcore-dmesg:\n");
                if let Some(v) = s(vd, "panic_reason") {
                    out.push_str(&format!("    Panic: {v}\n"));
                }
                if let Some(v) = s(vd, "kernel_version") {
                    out.push_str(&format!("    Kernel: {v}\n"));
                }
                if let Some(v) = s(vd, "hardware") {
                    out.push_str(&format!("    Hardware: {v}\n"));
                }
                if let Some(ct) = vd.get("call_trace").and_then(Value::as_array) {
                    if !ct.is_empty() {
                        out.push_str(&format!(
                            "    Call trace ({} frames, top 5):\n",
                            ct.len()
                        ));
                        for frame in ct.iter().take(5) {
                            if let Some(f) = frame.as_str() {
                                out.push_str(&format!("      {f}\n"));
                            }
                        }
                    }
                }
            }
        }
        if let Some(kdc) = obj(r, "kdumpConf") {
            if has_data(&Value::Object(kdc.clone())) {
                out.push_str("  /etc/kdump.conf:\n");
                for k in ["path", "core_collector", "default_action", "failure_action"] {
                    if let Some(v) = s(kdc, k) {
                        out.push_str(&format!("    {k} = {v}\n"));
                    }
                }
            }
        }
        out.push('\n');
    }

    // ----- Debugfs -----
    if has("hvBalloon") || has("extfrag") {
        out.push_str(&section("DEBUGFS"));
        if let Some(hv) = obj(r, "hvBalloon") {
            if has_data(&Value::Object(hv.clone())) {
                let committed = s(hv, "committed_memory_gb").unwrap_or_else(|| "?".into());
                let max = s(hv, "max_dynamic_memory_gb").unwrap_or_else(|| "?".into());
                out.push_str(&format!(
                    "  Hyper-V balloon: committed {committed} GB / max {max} GB\n"
                ));
                out.push_str(&list_warnings(hv.get("warnings"), "    "));
            }
        }
        if let Some(ef) = obj(r, "extfrag") {
            if has_data(&Value::Object(ef.clone())) {
                out.push_str(&format!(
                    "  Memory fragmentation zones: {}\n",
                    arr_len(ef.get("zones"))
                ));
                out.push_str(&list_warnings(ef.get("warnings"), "    "));
            }
        }
        out.push('\n');
    }

    out.push_str(SEP);
    out.push('\n');
    out
}

// ---------------------------------------------------------------------------
// CLI plumbing
// ---------------------------------------------------------------------------

struct CliArgs {
    file: Option<String>,
    json: bool,
    debug: bool,
    list: bool,
    parser: Option<String>,
}

fn parse_args() -> Result<CliArgs, String> {
    let mut args = env::args().skip(1);
    let mut out = CliArgs {
        file: None,
        json: false,
        debug: false,
        list: false,
        parser: None,
    };
    while let Some(a) = args.next() {
        match a.as_str() {
            "-h" | "--help" => {
                print_usage();
                std::process::exit(0);
            }
            "-j" | "--json" => out.json = true,
            "-d" | "--debug" => out.debug = true,
            "-l" | "--list-parsers" => out.list = true,
            "-p" | "--parser" => {
                out.parser = Some(
                    args.next()
                        .ok_or_else(|| "--parser requires a value".to_string())?,
                );
            }
            other if other.starts_with('-') => {
                return Err(format!("unknown option: {other}"));
            }
            other => {
                if out.file.is_some() {
                    return Err(format!("unexpected positional arg: {other}"));
                }
                out.file = Some(other.to_string());
            }
        }
    }
    Ok(out)
}

fn print_usage() {
    println!(
        "rca_cli - example CLI for the supportfile Rust library\n\n\
         Usage:\n  \
           rca_cli <archive> [--json] [--parser NAME] [--debug]\n  \
           rca_cli --list-parsers\n\n\
         Options:\n  \
           -j, --json          Print raw merged JSON instead of summary text\n  \
           -d, --debug         Log per-file parser dispatch to stderr\n  \
           -p, --parser NAME   Run only the parser with this name\n  \
           -l, --list-parsers  List parser names + file regexes and exit\n  \
           -h, --help          Show this help"
    );
}

fn run() -> Result<(), String> {
    let args = parse_args()?;

    if args.list {
        println!("Available parsers:");
        for p in parsers() {
            println!("  {:<24} -> {}", p.name, p.pattern);
        }
        return Ok(());
    }

    let file = args
        .file
        .ok_or_else(|| "missing archive path (use --help for usage)".to_string())?;
    eprintln!("Analyzing: {file}");
    let results = process_archive(Path::new(&file), args.parser.as_deref(), args.debug)?;

    if args.json {
        let summary: BTreeMap<&str, Value> = BTreeMap::from([
            ("fileCount", Value::from(results.file_count)),
            ("matchedFiles", Value::from(results.matched_files)),
            (
                "fileTypes",
                serde_json::to_value(&results.file_types).unwrap_or(Value::Null),
            ),
        ]);
        let mut combined: Map<String, Value> = Map::new();
        for (k, v) in &summary {
            combined.insert((*k).to_string(), v.clone());
        }
        for (k, v) in &results.parser_results {
            combined.insert(k.clone(), v.clone());
        }
        println!(
            "{}",
            serde_json::to_string_pretty(&Value::Object(combined))
                .map_err(|e| format!("json encode: {e}"))?
        );
    } else {
        print!("{}", format_text(&results));
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}
