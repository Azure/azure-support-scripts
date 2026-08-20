//! `rca_cli` — pure-Rust CLI for the `supportfile` library.
//!
//! Mirrors the Python example under `lib/supportfile_py/examples/rca_cli.py`
//! and the JavaScript CLI under `rca-tool/cli/cli.js`. It walks a
//! supportconfig (SCC) or sosreport (SOS) archive (`.tar`, `.tar.gz`,
//! `.tar.xz`, `.zip`, or a plaintext log), routes each member to one or more
//! `parse_*_json` functions based on a regex registry, decodes the JSON,
//! optionally merges multi-file results, and prints either a human summary or
//! raw JSON.
//!
//! The archive walk, parser registry, parallel dispatch, and result merging
//! all live in the reusable [`supportfile::engine`] module so that this binary
//! and any in-process consumer (e.g. an MCP server linking the library) share
//! the exact same analysis engine. This binary remains a separately-buildable
//! component (gated behind the `cli` feature) used by CI and by external tools
//! that integrate over its stdin/stdout contract; it is now a thin presentation
//! wrapper that owns only argument parsing and the human-readable summary.
//!
//! Build & run from the workspace:
//!
//! ```text
//! cd rca-tool/lib/supportfile_core
//! cargo run --features cli --bin rca_cli -- ../../tests/fixtures/scc_test-azure-vm.tar.xz
//! cargo run --features cli --bin rca_cli -- ../../tests/fixtures/scc_test-azure-vm.tar.xz --json
//! cargo run --features cli --bin rca_cli -- --list-parsers
//! ```

use std::collections::BTreeMap;
use std::env;
use std::path::Path;
use std::process::ExitCode;

use serde_json::{Map, Value};

use supportfile::engine::{is_empty_scalar, parsers, process_archive, ArchiveResults};

// ---------------------------------------------------------------------------
// Output helpers (CLI presentation only)
// ---------------------------------------------------------------------------

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
                                        .filter_map(|a| a.as_object().and_then(|o| s(o, "address")))
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
                            let healthy =
                                o.get("healthy").and_then(Value::as_bool).unwrap_or(false);
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
                        out.push_str(&format!("    Call trace ({} frames, top 5):\n", ct.len()));
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
        println!(
            "{}",
            serde_json::to_string_pretty(&results.to_json())
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
