use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

// ---------------------------------------------------------------------------
// Provenance
// ---------------------------------------------------------------------------
//
// Every leaf record produced by the storage parsers carries flat
// `source_path` / `source_line` / `source_line_end` fields so consumers can
// trace each detection back to the original file inside a support archive
// (sosreport / supportconfig). When a parser is invoked without a known
// source path the caller may pass an empty string; line numbers are 1-based
// and refer to the supplied `content`.

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StorageWarning {
    #[serde(rename = "type")]
    pub r#type: String,
    pub message: String,
    pub details: Option<String>,
    pub severity: Option<String>,
    pub recommendation: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LvmPv {
    pub device: String,
    pub vg: String,
    pub attr: String,
    pub size: String,
    pub free: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LvmVg {
    pub name: String,
    pub pv_count: String,
    pub lv_count: String,
    pub attr: String,
    pub size: String,
    pub free: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LvmLv {
    pub name: String,
    pub vg: String,
    pub attr: String,
    pub size: String,
    pub pool: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LvmConfigResult {
    pub found: bool,
    pub pvs: Vec<LvmPv>,
    pub vgs: Vec<LvmVg>,
    pub lvs: Vec<LvmLv>,
    pub warnings: Vec<StorageWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RaidDevice {
    pub device: String,
    pub state: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RaidSyncStatus {
    pub operation: String,
    pub percentage: String,
    pub finish: Option<String>,
    pub speed: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RaidArray {
    pub device: String,
    pub state: String,
    pub level: String,
    pub devices: Vec<RaidDevice>,
    pub sync_status: Option<RaidSyncStatus>,
    pub size: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RaidConfigResult {
    pub found: bool,
    pub arrays: Vec<RaidArray>,
    pub warnings: Vec<StorageWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BtrfsFilesystem {
    pub label: Option<String>,
    pub uuid: Option<String>,
    pub devices: Vec<String>,
    pub total_size: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BtrfsSubvolume {
    pub id: String,
    pub path: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BtrfsConfigResult {
    pub found: bool,
    pub filesystems: Vec<BtrfsFilesystem>,
    pub subvolumes: Vec<BtrfsSubvolume>,
    pub warnings: Vec<StorageWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BlockDeviceInfo {
    pub name: String,
    pub device: String,
    pub r#type: String,
    pub mountpoint: Option<String>,
    pub fstype: Option<String>,
    pub uuid: Option<String>,
    pub size: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BlockDevicesResult {
    pub found: bool,
    pub disks: Vec<BlockDeviceInfo>,
    pub partitions: Vec<BlockDeviceInfo>,
    pub uuid_map: BTreeMap<String, String>,
    /// device path → device info, used by the storage-correlation pass
    /// to look up fstype/uuid when fstab references a device path.
    pub device_map: BTreeMap<String, BlockDeviceInfo>,
    pub mount_points: BTreeMap<String, String>,
    pub warnings: Vec<StorageWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FstabEntry {
    pub source: String,
    pub mountpoint: String,
    pub fstype: String,
    pub options: String,
    pub dump: String,
    pub pass: String,
    pub source_type: String,
    /// When `source_type == "uuid"`, the bare UUID (without the
    /// `UUID=` prefix) so the storage-correlation step can look it up
    /// against `blockDevices.uuidMap` directly.
    pub uuid: Option<String>,
    /// When `source_type == "device"`, the device path (same as
    /// `source`) so the correlation step can look it up directly
    /// against `blockDevices.deviceMap`.
    pub device: Option<String>,
    pub has_nofail: bool,
    pub is_os_partition: bool,
    pub is_virtual_fs: bool,
    pub needs_nofail: bool,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FstabAnalysisResult {
    pub found: bool,
    pub entries: Vec<FstabEntry>,
    pub warnings: Vec<StorageWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DfEntry {
    pub filesystem: String,
    pub fstype: Option<String>,
    pub size: String,
    pub used: String,
    pub available: String,
    pub use_percent: i32,
    pub mountpoint: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DfOutputResult {
    pub found: bool,
    pub filesystems: Vec<DfEntry>,
    pub mount_to_usage: BTreeMap<String, DfEntry>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MtabEntry {
    pub source: String,
    pub mountpoint: String,
    pub fstype: String,
    pub options: String,
    pub is_virtual_fs: bool,
    pub source_type: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MtabAnalysisResult {
    pub found: bool,
    pub entries: Vec<MtabEntry>,
    pub extra_mounts: Vec<MtabEntry>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NvmeListResult {
    pub found: bool,
    pub has_nvme: bool,
    pub drive_count: usize,
    pub content: Option<String>,
    pub filename: Option<String>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NfsMount {
    pub source: String,
    pub mountpoint: String,
    pub fstype: String,
    pub options: String,
    /// Negotiated/configured protocol version (e.g. "3", "4.1") when present.
    pub vers: Option<String>,
    /// Read/write block sizes in bytes when present in the option list.
    pub rsize: Option<i64>,
    pub wsize: Option<i64>,
    /// Mount timeout in deciseconds (NFS `timeo` option) when present.
    pub timeo: Option<i64>,
    /// Number of TCP connections (`nconnect`) when present.
    pub nconnect: Option<i64>,
    pub has_hard: bool,
    pub has_soft: bool,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NfsMountsResult {
    pub found: bool,
    pub mounts: Vec<NfsMount>,
    pub warnings: Vec<StorageWarning>,
    pub source_path: String,
}

// ---------------------------------------------------------------------------
// LVM
// ---------------------------------------------------------------------------

fn is_lvm_noise(line: &str) -> bool {
    let t = line.trim();
    t.starts_with("#==")
        || t.starts_with("WARNING:")
        || t.starts_with("Reloading")
        || t.starts_with("Loading config")
        || t.starts_with("devices/")
}

fn validate_lvm(result: &mut LvmConfigResult, source_path: &str) {
    let vg_names = result
        .vgs
        .iter()
        .map(|vg| vg.name.clone())
        .collect::<BTreeSet<_>>();
    for pv in &result.pvs {
        if !pv.vg.is_empty() && pv.vg != "-" && pv.vg != "--" && !vg_names.contains(&pv.vg) {
            result.warnings.push(StorageWarning {
                r#type: "Missing VG".to_string(),
                message: format!(
                    "Physical Volume {} references Volume Group '{}' which is not present",
                    pv.device, pv.vg
                ),
                details: Some("This may indicate a missing or corrupted Volume Group".to_string()),
                severity: None,
                recommendation: None,
                source_path: source_path.to_string(),
                source_line: pv.source_line,
                source_line_end: pv.source_line_end,
            });
        }
    }
    for vg in &result.vgs {
        let actual = result.pvs.iter().filter(|pv| pv.vg == vg.name).count();
        let expected = vg.pv_count.parse::<usize>().unwrap_or(actual);
        if actual != expected {
            result.warnings.push(StorageWarning {
                r#type: "PV Count Mismatch".to_string(),
                message: format!(
                    "Volume Group '{}' expects {} PVs but only {} were found",
                    vg.name, expected, actual
                ),
                details: Some(format!("Missing PVs: {}", expected.saturating_sub(actual))),
                severity: None,
                recommendation: None,
                source_path: source_path.to_string(),
                source_line: vg.source_line,
                source_line_end: vg.source_line_end,
            });
        }
    }
}

pub fn parse_lvm_config(content: &str, source_path: &str) -> LvmConfigResult {
    let mut result = LvmConfigResult {
        found: false,
        pvs: Vec::new(),
        vgs: Vec::new(),
        lvs: Vec::new(),
        warnings: Vec::new(),
        source_path: source_path.to_string(),
    };
    // Accept both the compact `lvs` form (4 columns and end-of-line) and
    // the verbose `lvs -v` / `lvs -a -o lv_tags,devices ...` form which
    // appends extra columns after the size — so don't anchor at $.
    let lv_re =
        crate::cached_regex!(r"^(\S+)\s+(\S+)\s+([-a-zA-Z]{6,})\s+(<?\d+[\.\d]*[KMGTPmkgtp]?)\b");

    for (idx, raw_line) in content.lines().enumerate() {
        if is_lvm_noise(raw_line) {
            continue;
        }
        let line_no = idx + 1;
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        if trimmed.starts_with("/dev/") {
            let parts = trimmed.split_whitespace().collect::<Vec<_>>();
            if parts.len() >= 3 && parts[2] == "lvm2" {
                result.pvs.push(LvmPv {
                    device: parts[0].to_string(),
                    vg: parts[1].to_string(),
                    attr: parts.get(3).copied().unwrap_or("-").to_string(),
                    size: parts.get(4).copied().unwrap_or("-").to_string(),
                    free: parts.get(5).copied().unwrap_or("-").to_string(),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
                continue;
            }
        }

        let parts = trimmed.split_whitespace().collect::<Vec<_>>();
        if parts.len() >= 7 && !parts[0].starts_with('/') {
            if parts[1].chars().all(|c| c.is_ascii_digit()) {
                result.vgs.push(LvmVg {
                    name: parts[0].to_string(),
                    pv_count: parts[1].to_string(),
                    lv_count: parts[2].to_string(),
                    attr: parts[4].to_string(),
                    size: parts[5].to_string(),
                    free: parts[6].to_string(),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
                continue;
            }
            if parts.len() >= 8 && parts[3].chars().all(|c| c.is_ascii_digit()) {
                result.vgs.push(LvmVg {
                    name: parts[0].to_string(),
                    attr: parts[1].to_string(),
                    pv_count: parts[3].to_string(),
                    lv_count: parts[4].to_string(),
                    size: parts[6].to_string(),
                    free: parts[7].to_string(),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
                continue;
            }
        }

        if let Some(caps) = lv_re.captures(trimmed) {
            result.lvs.push(LvmLv {
                name: caps[1].to_string(),
                vg: caps[2].to_string(),
                attr: caps[3].to_string(),
                size: caps[4].to_string(),
                pool: "-".to_string(),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
        }
    }

    if !result.pvs.is_empty() || !result.vgs.is_empty() || !result.lvs.is_empty() {
        result.found = true;
    }
    if !result.pvs.is_empty() && !result.vgs.is_empty() {
        validate_lvm(&mut result, source_path);
    }
    result
}

// ---------------------------------------------------------------------------
// RAID
// ---------------------------------------------------------------------------

pub fn parse_raid_config(content: &str, source_path: &str) -> RaidConfigResult {
    let mut result = RaidConfigResult {
        found: false,
        arrays: Vec::new(),
        warnings: Vec::new(),
        source_path: source_path.to_string(),
    };

    let header_re = crate::cached_regex!(r"^(md\d+)\s*:\s*(\w+)\s+(\w+)\s+(.+)$");
    let dev_re = crate::cached_regex!(r"(\w+)\[\d+\](?:\((\w+)\))?");
    let blocks_re = crate::cached_regex!(r"(\d+)\s+blocks");
    let pct_re = crate::cached_regex!(r"([\d.]+)%");
    let finish_re = crate::cached_regex!(r"finish=([^\s]+)");
    let speed_re = crate::cached_regex!(r"speed=([^\s]+)");

    let mut current: Option<RaidArray> = None;
    for (idx, line) in content.lines().enumerate() {
        let line_no = idx + 1;
        if let Some(caps) = header_re.captures(line) {
            if let Some(arr) = current.take() {
                result.arrays.push(arr);
            }
            let devices_str = caps[4].to_string();
            let mut devices = Vec::new();
            for dev_caps in dev_re.captures_iter(&devices_str) {
                let raw_state = dev_caps.get(2).map(|m| m.as_str()).unwrap_or("active");
                let state = if raw_state == "S" { "spare" } else { raw_state }.to_string();
                devices.push(RaidDevice {
                    device: format!("/dev/{}", &dev_caps[1]),
                    state,
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
            if devices_str.contains("(F)") {
                result.warnings.push(StorageWarning {
                    r#type: "Faulty Device".to_string(),
                    message: format!("RAID array /dev/{} has faulty devices", &caps[1]),
                    details: Some("Check device status with mdadm".to_string()),
                    severity: None,
                    recommendation: None,
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
            current = Some(RaidArray {
                device: format!("/dev/{}", &caps[1]),
                state: caps[2].to_string(),
                level: caps[3].to_string(),
                devices,
                sync_status: None,
                size: None,
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
            continue;
        }

        if let Some(arr) = &mut current {
            // extend array's line range as we consume continuation lines
            arr.source_line_end = Some(line_no);
            if line.contains("blocks") {
                if let Some(caps) = blocks_re.captures(line) {
                    let blocks = caps[1].parse::<f64>().unwrap_or(0.0);
                    arr.size = Some(format!("{:.2} MB", blocks / 1024.0));
                }
                if line.contains("[_") {
                    arr.state = "degraded".to_string();
                    result.warnings.push(StorageWarning {
                        r#type: "Degraded Array".to_string(),
                        message: format!("RAID array {} is degraded", arr.device),
                        details: Some("One or more devices are missing or failed".to_string()),
                        severity: None,
                        recommendation: None,
                        source_path: source_path.to_string(),
                        source_line: Some(line_no),
                        source_line_end: Some(line_no),
                    });
                }
            }
            if (line.contains("recovery")
                || line.contains("resync")
                || line.contains("reshape")
                || line.contains("check"))
                && line.contains('%')
            {
                let op = if line.contains("recovery") {
                    "recovery"
                } else if line.contains("resync") {
                    "resync"
                } else if line.contains("reshape") {
                    "reshape"
                } else {
                    "check"
                };
                let pct = pct_re
                    .captures(line)
                    .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
                    .unwrap_or_else(|| "0".to_string());
                arr.sync_status = Some(RaidSyncStatus {
                    operation: op.to_string(),
                    percentage: pct,
                    finish: finish_re
                        .captures(line)
                        .and_then(|c| c.get(1).map(|m| m.as_str().to_string())),
                    speed: speed_re
                        .captures(line)
                        .and_then(|c| c.get(1).map(|m| m.as_str().to_string())),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
        }
    }
    if let Some(arr) = current.take() {
        result.arrays.push(arr);
    }
    result.found = !result.arrays.is_empty();
    result
}

// ---------------------------------------------------------------------------
// BTRFS
// ---------------------------------------------------------------------------

pub fn parse_btrfs_config(content: &str, source_path: &str) -> BtrfsConfigResult {
    let mut result = BtrfsConfigResult {
        found: false,
        filesystems: Vec::new(),
        subvolumes: Vec::new(),
        warnings: Vec::new(),
        source_path: source_path.to_string(),
    };

    let label_re = crate::cached_regex!(r"Label:\s*(?:'([^']*)'|none)\s+uuid:\s*(\S+)");
    let dev_re = crate::cached_regex!(r"devid\s+\d+\s+size\s+(\S+)\s+used\s+\S+\s+path\s+(\S+)");
    let sub_re = crate::cached_regex!(r"ID\s+(\d+)\s+.*\s+path\s+(.+)$");

    let mut current_fs: Option<BtrfsFilesystem> = None;
    for (idx, line) in content.lines().enumerate() {
        let line_no = idx + 1;
        let trimmed = line.trim();
        if let Some(caps) = label_re.captures(trimmed) {
            if let Some(fs) = current_fs.take() {
                result.filesystems.push(fs);
            }
            current_fs = Some(BtrfsFilesystem {
                label: caps
                    .get(1)
                    .map(|m| m.as_str().to_string())
                    .filter(|s| !s.is_empty()),
                uuid: Some(caps[2].to_string()),
                devices: Vec::new(),
                total_size: None,
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
            continue;
        }
        if let Some(fs) = &mut current_fs {
            if let Some(caps) = dev_re.captures(trimmed) {
                fs.total_size = Some(caps[1].to_string());
                fs.devices.push(caps[2].to_string());
                fs.source_line_end = Some(line_no);
            }
        }
        if let Some(caps) = sub_re.captures(trimmed) {
            result.subvolumes.push(BtrfsSubvolume {
                id: caps[1].to_string(),
                path: caps[2].trim().to_string(),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
        }
    }
    if let Some(fs) = current_fs.take() {
        result.filesystems.push(fs);
    }
    result.found = !result.filesystems.is_empty() || !result.subvolumes.is_empty();
    result
}

// ---------------------------------------------------------------------------
// Block devices
// ---------------------------------------------------------------------------

pub fn parse_block_devices(content: &str, source_path: &str) -> BlockDevicesResult {
    let mut uuid_map = BTreeMap::new();
    let mut mount_points = BTreeMap::new();
    let mut device_map = BTreeMap::<String, BlockDeviceInfo>::new();

    let blkid_re = crate::cached_regex!(r"^(\/dev\/\S+):\s*(.*)$");
    let type_re = crate::cached_regex!(r#"TYPE=\"([^\"]+)\""#);
    let uuid_re = crate::cached_regex!(r#"UUID=\"([^\"]+)\""#);
    let blkid_alt_re = crate::cached_regex!(r"^(\/dev\/\S+):\s+(\S+)\s+\[uuid=([^\]]*)\]");

    for (idx, raw_line) in content.lines().enumerate() {
        let line_no = idx + 1;
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with("NAME") {
            continue;
        }

        if let Some(caps) = blkid_re.captures(trimmed) {
            let device = caps[1].to_string();
            let attrs = caps[2].to_string();
            let name = device.trim_start_matches("/dev/").to_string();
            let entry = device_map.entry(device.clone()).or_insert(BlockDeviceInfo {
                name,
                device: device.clone(),
                r#type: "part".to_string(),
                mountpoint: None,
                fstype: None,
                uuid: None,
                size: None,
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
            entry.source_line_end = Some(line_no);
            if let Some(c) = type_re.captures(&attrs) {
                entry.fstype = Some(c[1].to_string());
            }
            if let Some(c) = uuid_re.captures(&attrs) {
                let uuid = c[1].to_string();
                entry.uuid = Some(uuid.clone());
                uuid_map.insert(uuid.clone(), device.clone());
                uuid_map.insert(uuid.to_lowercase(), device.clone());
                uuid_map.insert(uuid.to_uppercase(), device.clone());
            }
            continue;
        }

        if let Some(caps) = blkid_alt_re.captures(trimmed) {
            let device = caps[1].to_string();
            let name = device.trim_start_matches("/dev/").to_string();
            let entry = device_map.entry(device.clone()).or_insert(BlockDeviceInfo {
                name,
                device: device.clone(),
                r#type: if device.matches('/').count() > 2 {
                    "lvm".to_string()
                } else {
                    "part".to_string()
                },
                mountpoint: None,
                fstype: None,
                uuid: None,
                size: None,
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
            entry.source_line_end = Some(line_no);
            if &caps[2] != "unknown" {
                entry.fstype = Some(caps[2].to_string());
            }
            if !caps[3].is_empty() {
                let uuid = caps[3].to_string();
                entry.uuid = Some(uuid.clone());
                uuid_map.insert(uuid.clone(), device.clone());
            }
            continue;
        }

        let clean = trimmed
            .replace(&['├', '└', '│', '`'][..], "")
            .replace('─', "");
        let parts = clean.split_whitespace().collect::<Vec<_>>();
        if parts.len() >= 6 && !parts[0].starts_with('#') && !parts[0].starts_with("Filesystem") {
            let name = parts[0].to_string();
            if !name.starts_with("/dev/") && name.chars().all(|c| c.is_ascii_alphanumeric()) {
                let kind = parts[5].to_string();
                if ["disk", "part", "lvm", "rom", "loop", "crypt"]
                    .iter()
                    .any(|k| kind.starts_with(k))
                {
                    let device = format!("/dev/{}", name);
                    let mountpoint = parts
                        .get(6)
                        .map(|s| s.to_string())
                        .filter(|s| s.starts_with('/'));
                    let entry = BlockDeviceInfo {
                        name: name.clone(),
                        device: device.clone(),
                        r#type: kind.clone(),
                        mountpoint: mountpoint.clone(),
                        fstype: None,
                        uuid: None,
                        size: parts.get(3).map(|s| s.to_string()),
                        source_path: source_path.to_string(),
                        source_line: Some(line_no),
                        source_line_end: Some(line_no),
                    };
                    if let Some(mp) = mountpoint {
                        mount_points.insert(mp, device.clone());
                    }
                    device_map.entry(device.clone()).or_insert(entry);
                }
            }
        }
    }

    let mut disks = Vec::new();
    let mut partitions = Vec::new();
    for info in device_map.values() {
        if info.r#type == "disk" {
            disks.push(info.clone());
        } else {
            partitions.push(info.clone());
        }
        if let Some(mp) = &info.mountpoint {
            mount_points.insert(mp.clone(), info.device.clone());
        }
    }

    BlockDevicesResult {
        found: !disks.is_empty() || !partitions.is_empty() || !uuid_map.is_empty(),
        disks,
        partitions,
        uuid_map,
        device_map,
        mount_points,
        warnings: Vec::new(),
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// fstab
// ---------------------------------------------------------------------------

/// SCC's `fs-diskio.txt` bundles multiple files into one stream, with the
/// `/etc/fstab` content introduced by a `# /etc/fstab` header line and
/// terminated by the next `#==` section marker. Blank lines and commented
/// fstab entries (e.g. `#/dev/system/swap`) are legitimate fstab content
/// and must NOT terminate the section. Returns `None` if no header is found
/// (i.e. the input already looks like a raw fstab).
fn extract_fstab_from_scc(content: &str) -> Option<String> {
    let header_re = crate::cached_regex!(r"^#\s*/etc/fstab\s*$");
    if !content.lines().any(|l| header_re.is_match(l)) {
        return None;
    }
    let mut lines: Vec<&str> = Vec::new();
    let mut in_section = false;
    for line in content.lines() {
        if !in_section {
            if header_re.is_match(line) {
                in_section = true;
            }
            continue;
        }
        if line.starts_with("#==") {
            break;
        }
        lines.push(line);
    }
    while lines.first().map_or(false, |l| l.trim().is_empty()) {
        lines.remove(0);
    }
    while lines.last().map_or(false, |l| l.trim().is_empty()) {
        lines.pop();
    }
    if lines.is_empty() {
        None
    } else {
        Some(lines.join("\n"))
    }
}

pub fn parse_fstab_analysis(content: &str, source_path: &str) -> FstabAnalysisResult {
    // If we were given the SCC multipart file (fs-diskio.txt) instead of a
    // raw fstab, extract just the `# /etc/fstab` section. Without this, we
    // happily parse lsblk/df/blkid rows as fstab entries.
    let extracted = extract_fstab_from_scc(content);
    let effective_content: &str = extracted.as_deref().unwrap_or(content);

    let mut entries = Vec::new();
    let mut warnings = Vec::new();
    let os_mounts = [
        "/",
        "/boot",
        "/boot/efi",
        "/usr",
        "/var",
        "/tmp",
        "/home",
        "/opt",
    ];
    let virtual_fs = [
        "tmpfs",
        "devtmpfs",
        "sysfs",
        "proc",
        "cgroup",
        "cgroup2",
        "securityfs",
        "devpts",
        "hugetlbfs",
        "mqueue",
        "debugfs",
        "tracefs",
        "fusectl",
        "configfs",
        "pstore",
        "efivarfs",
        "bpf",
        "binfmt_misc",
        "autofs",
        "sunrpc",
    ];

    for (idx, raw_line) in effective_content.lines().enumerate() {
        let line_no = idx + 1;
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let parts = trimmed.split_whitespace().collect::<Vec<_>>();
        if parts.len() < 4 {
            continue;
        }
        let source = parts[0].to_string();
        let mountpoint = parts[1].to_string();
        let fstype = parts[2].to_string();
        let options = parts[3].to_string();
        let source_type = if source.starts_with("UUID=") {
            "uuid"
        } else if source.starts_with("LABEL=") {
            "label"
        } else if source.starts_with("/dev/") {
            "device"
        } else if source.starts_with("//") || source.contains(':') {
            "network"
        } else {
            "unknown"
        }
        .to_string();
        let has_nofail = options.contains("nofail");
        let is_os_partition = os_mounts.contains(&mountpoint.as_str());
        let is_virtual = virtual_fs.contains(&fstype.as_str()) || fstype == "none";
        let needs_nofail = !is_os_partition && !is_virtual && !has_nofail;
        if needs_nofail {
            warnings.push(StorageWarning {
                r#type: "missing_nofail".to_string(),
                message: format!(
                    "Mount point '{}' is missing the 'nofail' option",
                    mountpoint
                ),
                details: None,
                severity: Some("warning".to_string()),
                recommendation: Some(
                    "Add nofail option to prevent boot failures if this mount becomes unavailable"
                        .to_string(),
                ),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
        }
        entries.push(FstabEntry {
            uuid: if source_type == "uuid" {
                Some(source.trim_start_matches("UUID=").to_string())
            } else {
                None
            },
            device: if source_type == "device" {
                Some(source.clone())
            } else {
                None
            },
            source,
            mountpoint,
            fstype,
            options,
            dump: parts.get(4).copied().unwrap_or("0").to_string(),
            pass: parts.get(5).copied().unwrap_or("0").to_string(),
            source_type,
            has_nofail,
            is_os_partition,
            is_virtual_fs: is_virtual,
            needs_nofail,
            source_path: source_path.to_string(),
            source_line: Some(line_no),
            source_line_end: Some(line_no),
        });
    }

    FstabAnalysisResult {
        found: !entries.is_empty(),
        entries,
        warnings,
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// df
// ---------------------------------------------------------------------------

pub fn parse_df_output(content: &str, source_path: &str) -> DfOutputResult {
    let mut filesystems = Vec::new();
    let mut mount_to_usage = BTreeMap::new();
    let typed_fs = Regex::new(
        r"^(xfs|ext[234]|vfat|btrfs|nfs[34]?|cifs|tmpfs|devtmpfs|sysfs|proc|overlay|zfs|swap)$",
    )
    .unwrap();

    for (idx, raw_line) in content.lines().enumerate() {
        let line_no = idx + 1;
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with("Filesystem") || trimmed.starts_with('#') {
            continue;
        }
        let parts = trimmed.split_whitespace().collect::<Vec<_>>();
        if parts.len() < 6 {
            continue;
        }
        let entry = if parts.len() >= 7 && typed_fs.is_match(parts[1]) {
            DfEntry {
                filesystem: parts[0].to_string(),
                fstype: Some(parts[1].to_string()),
                size: parts[2].to_string(),
                used: parts[3].to_string(),
                available: parts[4].to_string(),
                use_percent: parts[5].trim_end_matches('%').parse().unwrap_or(0),
                mountpoint: parts[6].to_string(),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            }
        } else {
            DfEntry {
                filesystem: parts[0].to_string(),
                fstype: None,
                size: parts[1].to_string(),
                used: parts[2].to_string(),
                available: parts[3].to_string(),
                use_percent: parts[4].trim_end_matches('%').parse().unwrap_or(0),
                mountpoint: parts[5].to_string(),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            }
        };
        mount_to_usage.insert(entry.mountpoint.clone(), entry.clone());
        filesystems.push(entry);
    }

    DfOutputResult {
        found: !filesystems.is_empty(),
        filesystems,
        mount_to_usage,
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// mtab / mount
// ---------------------------------------------------------------------------

pub fn parse_mtab_analysis(content: &str, source_path: &str) -> MtabAnalysisResult {
    let mut entries = Vec::new();
    let virtual_fs = [
        "tmpfs",
        "devtmpfs",
        "sysfs",
        "proc",
        "cgroup",
        "cgroup2",
        "securityfs",
        "devpts",
        "hugetlbfs",
        "mqueue",
        "debugfs",
        "tracefs",
        "fusectl",
        "configfs",
        "pstore",
        "efivarfs",
        "bpf",
        "binfmt_misc",
        "autofs",
        "sunrpc",
        "rpc_pipefs",
        "nfsd",
        "overlay",
        "nsfs",
        "squashfs",
        "rootfs",
        "ramfs",
    ];
    let mount_re = crate::cached_regex!(r"^(\S+)\s+on\s+(\S+)\s+type\s+(\S+)\s+\(([^)]*)\)");

    for (idx, raw_line) in content.lines().enumerate() {
        let line_no = idx + 1;
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let normalized = if let Some(caps) = mount_re.captures(trimmed) {
            format!("{} {} {} {}", &caps[1], &caps[2], &caps[3], &caps[4])
        } else {
            trimmed.to_string()
        };
        let parts = normalized.split_whitespace().collect::<Vec<_>>();
        if parts.len() < 3 {
            continue;
        }
        let source = parts[0].to_string();
        let mountpoint = parts[1].to_string();
        let fstype = parts[2].to_string();
        let options = parts.get(3).copied().unwrap_or("defaults").to_string();
        let source_type = if source.starts_with("UUID=") {
            "uuid"
        } else if source.starts_with("LABEL=") {
            "label"
        } else if source.starts_with("/dev/") {
            "device"
        } else if source.starts_with("//") || source.contains(':') {
            "network"
        } else {
            "unknown"
        }
        .to_string();
        entries.push(MtabEntry {
            source,
            mountpoint,
            fstype: fstype.clone(),
            options,
            is_virtual_fs: virtual_fs.contains(&fstype.as_str()) || fstype == "none",
            source_type,
            source_path: source_path.to_string(),
            source_line: Some(line_no),
            source_line_end: Some(line_no),
        });
    }
    let extra_mounts = entries
        .iter()
        .filter(|e| !e.is_virtual_fs)
        .cloned()
        .collect::<Vec<_>>();
    MtabAnalysisResult {
        found: !entries.is_empty(),
        entries,
        extra_mounts,
        source_path: source_path.to_string(),
    }
}

pub fn parse_nvme_list(content: &str, source_path: &str) -> NvmeListResult {
    let non_empty_count = content.lines().filter(|l| !l.trim().is_empty()).count();
    let has_nvme = non_empty_count > 2;

    NvmeListResult {
        found: has_nvme,
        has_nvme,
        drive_count: non_empty_count.saturating_sub(2),
        content: if has_nvme {
            Some(content.to_string())
        } else {
            None
        },
        filename: if source_path.is_empty() {
            None
        } else {
            Some(source_path.to_string())
        },
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// NFS mount analysis
// ---------------------------------------------------------------------------
//
// SAP-on-Azure workloads frequently place HANA data/log/shared and
// /sapmnt/transport directories on NFS (Azure NetApp Files or Azure Files).
// Misconfigured NFS mount options are a common, hard-to-spot root cause of
// data-integrity issues and poor throughput. This detector identifies NFS
// mounts in fstab or mount/mtab output and flags option problems against
// Microsoft's published SAP-on-NFS guidance. Generic boot-resilience checks
// (e.g. `nofail`) are handled by `parse_fstab_analysis`; this parser focuses
// only on NFS-specific option quality.

fn nfs_option_value(options: &str, key: &str) -> Option<String> {
    options.split(',').find_map(|opt| {
        let opt = opt.trim();
        let (k, v) = opt.split_once('=')?;
        if k.trim().eq_ignore_ascii_case(key) {
            Some(v.trim().to_string())
        } else {
            None
        }
    })
}

fn nfs_has_flag(options: &str, flag: &str) -> bool {
    options
        .split(',')
        .any(|opt| opt.trim().eq_ignore_ascii_case(flag))
}

/// Parse NFS mounts from either fstab (`src mnt nfs opts ...`) or mount /
/// mtab output (`src on mnt type nfs (opts)`), then emit SAP-relevant
/// option-quality warnings.
pub fn parse_nfs_mounts(content: &str, source_path: &str) -> NfsMountsResult {
    // Reuse the SCC fstab section if we were handed an aggregated file.
    let extracted = extract_fstab_from_scc(content);
    let effective: &str = extracted.as_deref().unwrap_or(content);

    let mount_re = crate::cached_regex!(r"^(\S+)\s+on\s+(\S+)\s+type\s+(\S+)\s+\(([^)]*)\)");

    let mut mounts: Vec<NfsMount> = Vec::new();
    let mut warnings: Vec<StorageWarning> = Vec::new();

    for (idx, raw_line) in effective.lines().enumerate() {
        let line_no = idx + 1;
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        // Normalise the two supported formats into: source mountpoint fstype options
        let (source, mountpoint, fstype, options) = if let Some(caps) = mount_re.captures(trimmed) {
            (
                caps[1].to_string(),
                caps[2].to_string(),
                caps[3].to_string(),
                caps[4].to_string(),
            )
        } else {
            let parts = trimmed.split_whitespace().collect::<Vec<_>>();
            if parts.len() < 4 {
                continue;
            }
            (
                parts[0].to_string(),
                parts[1].to_string(),
                parts[2].to_string(),
                parts[3].to_string(),
            )
        };

        // Recognise NFS by filesystem type. `host:/export` sources are only
        // treated as NFS when the fstype confirms it, to avoid misclassifying
        // other network filesystems.
        let fstype_l = fstype.to_ascii_lowercase();
        let is_nfs = fstype_l == "nfs" || fstype_l == "nfs4" || fstype_l == "nfs3";
        if !is_nfs {
            continue;
        }

        let vers = nfs_option_value(&options, "vers")
            .or_else(|| nfs_option_value(&options, "nfsvers"));
        let rsize = nfs_option_value(&options, "rsize").and_then(|v| v.parse::<i64>().ok());
        let wsize = nfs_option_value(&options, "wsize").and_then(|v| v.parse::<i64>().ok());
        let timeo = nfs_option_value(&options, "timeo").and_then(|v| v.parse::<i64>().ok());
        let nconnect = nfs_option_value(&options, "nconnect").and_then(|v| v.parse::<i64>().ok());
        let has_soft = nfs_has_flag(&options, "soft");
        let has_hard = nfs_has_flag(&options, "hard");

        // 1) soft mounts risk silent data corruption for SAP workloads.
        if has_soft {
            warnings.push(StorageWarning {
                r#type: "nfs_soft_mount".to_string(),
                message: format!(
                    "NFS mount '{}' uses the 'soft' option",
                    mountpoint
                ),
                details: Some(
                    "Soft NFS mounts can silently drop I/O on timeout, risking data corruption for SAP/HANA volumes".to_string(),
                ),
                severity: Some("error".to_string()),
                recommendation: Some(
                    "Use the 'hard' option for SAP NFS volumes so I/O retries instead of failing".to_string(),
                ),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
        }

        // 2) rsize/wsize below 262144 (256 KiB) reduce NFS throughput.
        let small_rsize = rsize.map(|v| v < 262144).unwrap_or(false);
        let small_wsize = wsize.map(|v| v < 262144).unwrap_or(false);
        if small_rsize || small_wsize {
            warnings.push(StorageWarning {
                r#type: "nfs_small_rsize_wsize".to_string(),
                message: format!(
                    "NFS mount '{}' uses small read/write sizes (rsize={}, wsize={})",
                    mountpoint,
                    rsize.map(|v| v.to_string()).unwrap_or_else(|| "default".to_string()),
                    wsize.map(|v| v.to_string()).unwrap_or_else(|| "default".to_string()),
                ),
                details: None,
                severity: Some("warning".to_string()),
                recommendation: Some(
                    "Set rsize=262144 and wsize=262144 for SAP NFS volumes on Azure NetApp Files".to_string(),
                ),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
        }

        // 3) Outdated protocol versions (NFSv2 / NFSv4.0) are not recommended.
        if let Some(v) = &vers {
            if v == "2" || v == "4.0" {
                warnings.push(StorageWarning {
                    r#type: "nfs_outdated_version".to_string(),
                    message: format!(
                        "NFS mount '{}' uses protocol version {}",
                        mountpoint, v
                    ),
                    details: None,
                    severity: Some("warning".to_string()),
                    recommendation: Some(
                        "Use NFSv3 or NFSv4.1 for SAP workloads on Azure".to_string(),
                    ),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
        }

        // 4) Missing nconnect leaves throughput on the table for ANF.
        if nconnect.is_none() {
            warnings.push(StorageWarning {
                r#type: "nfs_no_nconnect".to_string(),
                message: format!(
                    "NFS mount '{}' does not set the 'nconnect' option",
                    mountpoint
                ),
                details: None,
                severity: Some("info".to_string()),
                recommendation: Some(
                    "Consider nconnect (e.g. nconnect=8) to improve NFS throughput on Azure NetApp Files".to_string(),
                ),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
        }

        mounts.push(NfsMount {
            source,
            mountpoint,
            fstype,
            options,
            vers,
            rsize,
            wsize,
            timeo,
            nconnect,
            has_hard,
            has_soft,
            source_path: source_path.to_string(),
            source_line: Some(line_no),
            source_line_end: Some(line_no),
        });
    }

    NfsMountsResult {
        found: !mounts.is_empty(),
        mounts,
        warnings,
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// JSON wrappers
// ---------------------------------------------------------------------------

pub fn parse_lvm_config_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_lvm_config(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_raid_config_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_raid_config(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_btrfs_config_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_btrfs_config(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_block_devices_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_block_devices(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_fstab_analysis_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_fstab_analysis(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_df_output_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_df_output(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_mtab_analysis_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_mtab_analysis(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_nvme_list_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_nvme_list(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_nfs_mounts_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_nfs_mounts(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const FSTAB_PATH: &str = "etc/fstab";
    const MTAB_PATH: &str = "etc/mtab";
    const DF_PATH: &str = "sos_commands/filesys/df_-al";
    const LVM_PATH: &str = "sos_commands/lvm2/vgs_-v";
    const RAID_PATH: &str = "proc/mdstat";
    const BTRFS_PATH: &str = "sos_commands/btrfs/btrfs_filesystem_show";
    const BLK_PATH: &str = "sos_commands/block/blkid";

    // ---- LVM ----------------------------------------------------------------

    #[test]
    fn parses_lvm_and_warns_on_mismatch() {
        let input = concat!(
            "/dev/sda2 vg00 lvm2 a-- 100g 0\n",
            "vg00 2 1 0 wz--n- 100g 0\n",
            "root vg00 -wi-ao---- 50g\n"
        );
        let result = parse_lvm_config(input, LVM_PATH);
        assert!(result.found);
        assert_eq!(result.pvs.len(), 1);
        assert_eq!(result.vgs.len(), 1);
        assert!(!result.warnings.is_empty());
    }

    #[test]
    fn lvm_records_carry_source_provenance() {
        let input = concat!(
            "/dev/sda2 vg_missing lvm2 a-- 100g 0\n",
            "vg00 2 1 0 wz--n- 100g 0\n",
            "root vg00 -wi-ao---- 50g\n"
        );
        let result = parse_lvm_config(input, LVM_PATH);
        assert_eq!(result.source_path, LVM_PATH);
        for pv in &result.pvs {
            assert_eq!(pv.source_path, LVM_PATH);
            assert!(pv.source_line.is_some());
        }
        for vg in &result.vgs {
            assert_eq!(vg.source_path, LVM_PATH);
            assert!(vg.source_line.is_some());
        }
        for lv in &result.lvs {
            assert_eq!(lv.source_path, LVM_PATH);
            assert!(lv.source_line.is_some());
        }
        for w in &result.warnings {
            assert_eq!(w.source_path, LVM_PATH);
            assert!(w.source_line.is_some(), "warning {:?} missing line", w);
        }
        assert_eq!(result.pvs[0].source_line, Some(1));
        assert_eq!(result.vgs[0].source_line, Some(2));
        assert_eq!(result.lvs[0].source_line, Some(3));
    }

    // ---- RAID ---------------------------------------------------------------

    #[test]
    fn parses_raid_and_degraded_state() {
        let input = concat!(
            "md0 : active raid1 sda1[0] sdb1[1](F)\n",
            "      104320 blocks [_U]\n"
        );
        let result = parse_raid_config(input, RAID_PATH);
        assert!(result.found);
        assert_eq!(result.arrays[0].state, "degraded");
    }

    #[test]
    fn raid_records_carry_source_provenance() {
        let input = concat!(
            "md0 : active raid1 sda1[0] sdb1[1](F)\n",
            "      104320 blocks [_U]\n",
            "      [>....................]  recovery =  3.1% (3000/104320) finish=10.0min speed=5000K/sec\n"
        );
        let result = parse_raid_config(input, RAID_PATH);
        assert_eq!(result.source_path, RAID_PATH);
        let arr = &result.arrays[0];
        assert_eq!(arr.source_path, RAID_PATH);
        assert_eq!(arr.source_line, Some(1));
        assert!(arr.source_line_end.unwrap() >= 1);
        for d in &arr.devices {
            assert_eq!(d.source_path, RAID_PATH);
            assert!(d.source_line.is_some());
        }
        let sync = arr.sync_status.as_ref().expect("sync_status");
        assert_eq!(sync.source_path, RAID_PATH);
        assert_eq!(sync.source_line, Some(3));
        for w in &result.warnings {
            assert_eq!(w.source_path, RAID_PATH);
            assert!(w.source_line.is_some(), "warning {:?} missing line", w);
        }
    }

    // ---- BTRFS --------------------------------------------------------------

    #[test]
    fn btrfs_records_carry_source_provenance() {
        let input = concat!(
            "Label: 'data'  uuid: abcd-1234\n",
            "    devid 1 size 10G used 1G path /dev/sda1\n",
            "ID 256 gen 7 top level 5 path subvol_data\n"
        );
        let result = parse_btrfs_config(input, BTRFS_PATH);
        assert!(result.found);
        assert_eq!(result.source_path, BTRFS_PATH);
        for fs in &result.filesystems {
            assert_eq!(fs.source_path, BTRFS_PATH);
            assert!(fs.source_line.is_some());
        }
        for sv in &result.subvolumes {
            assert_eq!(sv.source_path, BTRFS_PATH);
            assert!(sv.source_line.is_some());
        }
        assert_eq!(result.filesystems[0].source_line, Some(1));
        assert_eq!(result.subvolumes[0].source_line, Some(3));
    }

    // ---- Block devices ------------------------------------------------------

    #[test]
    fn parses_block_and_fstab_data() {
        let blk = parse_block_devices("/dev/sda1: UUID=\"1234-ABCD\" TYPE=\"xfs\"\n", BLK_PATH);
        let fstab = parse_fstab_analysis("UUID=1234-ABCD /data xfs defaults 0 0\n", FSTAB_PATH);
        assert!(blk.found);
        assert!(fstab.found);
        assert!(fstab.entries[0].needs_nofail);
    }

    #[test]
    fn block_records_carry_source_provenance() {
        let input = "/dev/sda1: UUID=\"1234-ABCD\" TYPE=\"xfs\"\n";
        let blk = parse_block_devices(input, BLK_PATH);
        assert_eq!(blk.source_path, BLK_PATH);
        for d in blk.disks.iter().chain(blk.partitions.iter()) {
            assert_eq!(d.source_path, BLK_PATH);
            assert!(d.source_line.is_some());
        }
        assert!(!blk.partitions.is_empty() || !blk.disks.is_empty());
    }

    // ---- NVMe list ---------------------------------------------------------

    #[test]
    fn parses_nvme_list_header_only() {
        let input = "Node             SN                   Model\n-----------------------------------------------\n";
        let result = parse_nvme_list(input, "sos_commands/nvme/nvme_list");
        assert!(!result.found);
        assert!(!result.has_nvme);
        assert_eq!(result.drive_count, 0);
    }

    #[test]
    fn parses_nvme_list_with_devices() {
        let input = concat!(
            "Node             SN                   Model\n",
            "-----------------------------------------------\n",
            "/dev/nvme0n1     deadbeef123         NVMeDisk\n",
            "/dev/nvme1n1     cafe1234abcd         NVMeDisk\n"
        );
        let result = parse_nvme_list(input, "sos_commands/nvme/nvme_list");
        assert!(result.found);
        assert!(result.has_nvme);
        assert_eq!(result.drive_count, 2);
    }

    // ---- fstab --------------------------------------------------------------

    #[test]
    fn fstab_records_carry_source_provenance() {
        let input = concat!(
            "# header\n",
            "UUID=root-uuid / xfs defaults 0 0\n",
            "UUID=data-uuid /data xfs defaults 0 0\n",
        );
        let result = parse_fstab_analysis(input, FSTAB_PATH);
        assert!(result.found);
        assert_eq!(result.source_path, FSTAB_PATH);
        assert_eq!(result.entries.len(), 2);
        assert_eq!(result.entries[0].source_line, Some(2));
        assert_eq!(result.entries[1].source_line, Some(3));
        for e in &result.entries {
            assert_eq!(e.source_path, FSTAB_PATH);
        }
        // The /data entry is missing nofail; the warning must point at line 3.
        let warn = result
            .warnings
            .iter()
            .find(|w| w.r#type == "missing_nofail")
            .expect("missing_nofail warning");
        assert_eq!(warn.source_path, FSTAB_PATH);
        assert_eq!(warn.source_line, Some(3));
    }

    // ---- df ----------------------------------------------------------------

    #[test]
    fn df_records_carry_source_provenance() {
        let input = concat!(
            "Filesystem 1K-blocks Used Available Use% Mounted on\n",
            "/dev/sda1 1000 100 900 10% /\n",
            "/dev/sdb1 xfs 2000 200 1800 10% /data\n",
        );
        let result = parse_df_output(input, DF_PATH);
        assert!(result.found);
        assert_eq!(result.source_path, DF_PATH);
        assert_eq!(result.filesystems.len(), 2);
        assert_eq!(result.filesystems[0].source_line, Some(2));
        assert_eq!(result.filesystems[1].source_line, Some(3));
        for e in &result.filesystems {
            assert_eq!(e.source_path, DF_PATH);
        }
    }

    // ---- mtab --------------------------------------------------------------

    #[test]
    fn mtab_records_carry_source_provenance() {
        let input = concat!(
            "/dev/sda1 / xfs defaults 0 0\n",
            "tmpfs /run tmpfs rw,nosuid 0 0\n",
        );
        let result = parse_mtab_analysis(input, MTAB_PATH);
        assert!(result.found);
        assert_eq!(result.source_path, MTAB_PATH);
        assert_eq!(result.entries[0].source_line, Some(1));
        assert_eq!(result.entries[1].source_line, Some(2));
        for e in &result.entries {
            assert_eq!(e.source_path, MTAB_PATH);
        }
        for e in &result.extra_mounts {
            assert_eq!(e.source_path, MTAB_PATH);
            assert!(e.source_line.is_some());
        }
    }

    // ---- JSON wrappers preserve the new fields -----------------------------

    #[test]
    fn json_wrappers_include_source_path_and_line() {
        let json = parse_fstab_analysis_json("UUID=data-uuid /data xfs defaults 0 0\n", FSTAB_PATH);
        assert!(json.contains("\"source_path\":\"etc/fstab\""));
        assert!(json.contains("\"source_line\":1"));
    }

    // ---- NFS mounts --------------------------------------------------------

    #[test]
    fn nfs_flags_soft_small_size_and_missing_nconnect_from_fstab() {
        let input = concat!(
            "# /etc/fstab managed by admin\n",
            "UUID=root-uuid / xfs defaults 0 0\n",
            "10.0.0.4:/hana/data /hana/data nfs vers=4.1,soft,rsize=65536,wsize=65536,timeo=600 0 0\n",
        );
        let result = parse_nfs_mounts(input, FSTAB_PATH);
        assert!(result.found);
        assert_eq!(result.mounts.len(), 1);
        let mount = &result.mounts[0];
        assert_eq!(mount.mountpoint, "/hana/data");
        assert_eq!(mount.fstype, "nfs");
        assert_eq!(mount.vers.as_deref(), Some("4.1"));
        assert_eq!(mount.rsize, Some(65536));
        assert_eq!(mount.wsize, Some(65536));
        assert_eq!(mount.timeo, Some(600));
        assert!(mount.has_soft);
        assert!(!mount.has_hard);
        assert_eq!(mount.source_line, Some(3));

        let types: Vec<&str> = result.warnings.iter().map(|w| w.r#type.as_str()).collect();
        assert!(types.contains(&"nfs_soft_mount"));
        assert!(types.contains(&"nfs_small_rsize_wsize"));
        assert!(types.contains(&"nfs_no_nconnect"));
        for w in &result.warnings {
            assert_eq!(w.source_path, FSTAB_PATH);
            assert_eq!(w.source_line, Some(3));
        }
    }

    #[test]
    fn nfs_parses_mount_output_and_keeps_good_mounts_clean() {
        let input = concat!(
            "/dev/sda1 on / type xfs (rw,relatime)\n",
            "10.0.0.4:/sapmnt on /sapmnt type nfs4 (rw,hard,rsize=262144,wsize=262144,nconnect=8,vers=4.1)\n",
        );
        let result = parse_nfs_mounts(input, MTAB_PATH);
        assert!(result.found);
        assert_eq!(result.mounts.len(), 1);
        let mount = &result.mounts[0];
        assert_eq!(mount.mountpoint, "/sapmnt");
        assert_eq!(mount.fstype, "nfs4");
        assert!(mount.has_hard);
        assert_eq!(mount.nconnect, Some(8));
        assert!(result.warnings.is_empty());
    }

    #[test]
    fn nfs_flags_outdated_version() {
        let input =
            "10.0.0.4:/export /export nfs vers=2,hard,rsize=262144,wsize=262144,nconnect=4 0 0\n";
        let result = parse_nfs_mounts(input, FSTAB_PATH);
        assert!(result.found);
        let types: Vec<&str> = result.warnings.iter().map(|w| w.r#type.as_str()).collect();
        assert!(types.contains(&"nfs_outdated_version"));
        assert!(!types.contains(&"nfs_no_nconnect"));
    }
}
