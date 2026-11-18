use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VmcoreCrash {
    pub date: Option<String>,
    pub panic_reason: Option<String>,
    pub kernel_version: Option<String>,
    pub call_trace: Vec<String>,
    pub hardware: Option<String>,
    pub comm: Option<String>,
    pub pid: Option<i32>,
    pub cpu: Option<i32>,
    pub tainted: Option<String>,
    pub source_path: String,
    pub panic_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct KdumpStatus {
    pub raw: String,
    pub operational: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CrashListingEntry {
    pub directory: String,
    pub crash_date: Option<String>,
    pub size_bytes: i64,
    pub size_mb: i64,
    pub size_gb: String,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CrashListing {
    pub entries: Vec<CrashListingEntry>,
    pub count: usize,
    pub total_bytes: i64,
    pub total_gb: String,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct KdumpConf {
    pub path: String,
    pub core_collector: Option<String>,
    pub default_action: Option<String>,
    pub raw: String,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VmcoreSummary {
    pub found: bool,
    pub crash: Option<VmcoreCrash>,
    pub kdump_status: Option<KdumpStatus>,
    pub crash_listing: Option<CrashListing>,
    pub kdump_conf: Option<KdumpConf>,
    pub source_path: String,
}

pub fn parse_vmcore_dmesg(content: &str, source_path: &str) -> VmcoreCrash {
    let mut crash = VmcoreCrash {
        date: None,
        panic_reason: None,
        kernel_version: None,
        call_trace: Vec::new(),
        hardware: None,
        comm: None,
        pid: None,
        cpu: None,
        tainted: None,
        source_path: source_path.to_string(),
        panic_line: None,
    };

    // The crash date is encoded in the dump directory path, e.g.
    // `var/crash/127.0.0.1-2026-01-20-15:30:00/vmcore-dmesg.txt`. Use the same
    // pattern as the crash-listing parser so the two correlate by date.
    crash.date = crate::cached_regex!(r"(\d{4}-\d{2}-\d{2}[:-]\d{2}[:-]\d{2}[:-]\d{2})")
        .captures(source_path)
        .and_then(|m| m.get(1).map(|x| x.as_str().to_string()));

    let mut in_call_trace = false;
    for (line_idx, line) in content.lines().enumerate() {
        let line_no = line_idx + 1;
        if let Some(c) = crate::cached_regex!(r"Kernel panic - not syncing:\s*(.+)").captures(line)
        {
            crash.panic_reason = Some(c[1].trim().to_string());
            crash.panic_line = Some(line_no);
            in_call_trace = false;
            crash.call_trace.clear();
        }
        if let Some(c) = crate::cached_regex!(r"Hardware name:\s*(.+)").captures(line) {
            crash.hardware = Some(c[1].trim().replace(", BIOS", ""));
        }
        if let Some(c) = crate::cached_regex!(r"CPU:\s*(\d+)\s+PID:\s*(\d+)\s+Comm:\s*(\S+).*(Not tainted|Tainted:\s*\S*)\s+(\S+?)(?:\s+#\d+)?\s*$")
            .captures(line)
        {
            crash.cpu = c[1].parse::<i32>().ok();
            crash.pid = c[2].parse::<i32>().ok();
            crash.comm = Some(c[3].to_string());
            if !c[4].starts_with("Not") {
                crash.tainted = Some(c[4].to_string());
            }
            crash.kernel_version = Some(c[5].to_string());
        }
        if line.contains("Call Trace:") {
            in_call_trace = true;
            continue;
        }
        if in_call_trace {
            let frame = line.trim();
            if frame.is_empty() || frame.starts_with("Kernel Offset") || frame.starts_with("---[") {
                in_call_trace = false;
            } else {
                crash.call_trace.push(frame.to_string());
            }
        }
    }

    crash
}

pub fn parse_kdump_status(content: &str, source_path: &str) -> Option<KdumpStatus> {
    let trimmed = content.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(KdumpStatus {
        raw: trimmed.to_string(),
        operational: trimmed.to_ascii_lowercase().contains("operational")
            && !trimmed.to_ascii_lowercase().contains("not operational"),
        source_path: source_path.to_string(),
    })
}

pub fn parse_crash_listing(content: &str, source_path: &str) -> Option<CrashListing> {
    let mut entries = Vec::new();
    let mut current_dir: Option<String> = None;

    for (line_idx, line) in content.lines().enumerate() {
        let line_no = line_idx + 1;
        if let Some(c) = crate::cached_regex!(r"^(\/var\/crash\/.+):$").captures(line.trim()) {
            current_dir = Some(c[1].to_string());
            continue;
        }
        let Some(dir) = &current_dir else {
            continue;
        };
        if dir == "/var/crash" {
            continue;
        }
        if let Some(c) =
            crate::cached_regex!(r"\s+(\d+)\s+\w+\s+\d+\s+[\d:]+\s+(vmcore)$").captures(line)
        {
            let size_bytes = c[1].parse::<i64>().unwrap_or(0);
            let crash_date =
                crate::cached_regex!(r"(\d{4}-\d{2}-\d{2}[:-]\d{2}[:-]\d{2}[:-]\d{2})")
                    .captures(dir)
                    .and_then(|m| m.get(1).map(|x| x.as_str().to_string()));
            entries.push(CrashListingEntry {
                directory: dir.clone(),
                crash_date,
                size_bytes,
                size_mb: size_bytes / (1024 * 1024),
                size_gb: format!("{:.1}", size_bytes as f64 / (1024.0 * 1024.0 * 1024.0)),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
            });
        }
    }

    if entries.is_empty() {
        return None;
    }
    let total_bytes = entries.iter().map(|e| e.size_bytes).sum::<i64>();
    Some(CrashListing {
        count: entries.len(),
        entries,
        total_bytes,
        total_gb: format!("{:.1}", total_bytes as f64 / (1024.0 * 1024.0 * 1024.0)),
        source_path: source_path.to_string(),
    })
}

pub fn parse_kdump_conf(content: &str, source_path: &str) -> KdumpConf {
    let mut conf = KdumpConf {
        path: "/var/crash".to_string(),
        core_collector: None,
        default_action: None,
        raw: content.trim().to_string(),
        source_path: source_path.to_string(),
    };
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(c) = crate::cached_regex!(r"^path\s+(.+)$").captures(trimmed) {
            conf.path = c[1].trim().to_string();
        }
        if let Some(c) = crate::cached_regex!(r"^core_collector\s+(.+)$").captures(trimmed) {
            conf.core_collector = Some(c[1].trim().to_string());
        }
        if let Some(c) =
            crate::cached_regex!(r"^(?:default|failure_action)\s+(.+)$").captures(trimmed)
        {
            conf.default_action = Some(c[1].trim().to_string());
        }
    }
    conf
}

pub fn parse_vmcore_summary(content: &str, source_path: &str) -> VmcoreSummary {
    VmcoreSummary {
        found: !content.trim().is_empty(),
        crash: if content.contains("Kernel panic - not syncing") || content.contains("Call Trace:")
        {
            Some(parse_vmcore_dmesg(content, source_path))
        } else {
            None
        },
        kdump_status: if content.to_ascii_lowercase().contains("kdump") {
            parse_kdump_status(content, source_path)
        } else {
            None
        },
        crash_listing: if content.contains("/var/crash/") && content.contains("vmcore") {
            parse_crash_listing(content, source_path)
        } else {
            None
        },
        kdump_conf: if content.contains("core_collector")
            || content.contains("failure_action")
            || content.contains("path ")
        {
            Some(parse_kdump_conf(content, source_path))
        } else {
            None
        },
        source_path: source_path.to_string(),
    }
}

pub fn parse_vmcore_dmesg_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_vmcore_dmesg(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_kdump_status_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_kdump_status(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_crash_listing_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_crash_listing(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_kdump_conf_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_kdump_conf(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_vmcore_summary_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_vmcore_summary(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_vmcore_panic_and_trace() {
        let input = concat!(
            "Kernel panic - not syncing: hung_task: blocked tasks\n",
            "CPU: 2 PID: 71 Comm: khungtaskd Kdump: loaded Not tainted 4.18.0-test\n",
            "Call Trace:\n",
            " dump_stack+0x85/0xc2\n",
            " panic+0x101/0x2e3\n"
        );
        let crash = parse_vmcore_dmesg(input, "var/crash/vmcore-dmesg.txt");
        assert_eq!(crash.comm.as_deref(), Some("khungtaskd"));
        assert_eq!(crash.call_trace.len(), 2);
        assert_eq!(crash.source_path, "var/crash/vmcore-dmesg.txt");
        assert_eq!(crash.panic_line, Some(1));
    }

    #[test]
    fn crash_date_is_derived_from_dump_directory_path() {
        let input = "Kernel panic - not syncing: Fatal exception in interrupt\n";
        let dated = parse_vmcore_dmesg(
            input,
            "var/crash/127.0.0.1-2026-01-20-15:30:00/vmcore-dmesg.txt",
        );
        assert_eq!(dated.date.as_deref(), Some("2026-01-20-15:30:00"));

        // No date in the directory path leaves the field empty.
        let undated = parse_vmcore_dmesg(input, "var/crash/nodate-crash/vmcore-dmesg.txt");
        assert_eq!(undated.date, None);
    }

    #[test]
    fn parses_crash_listing_and_kdump_conf() {
        let listing = "/var/crash/host-2026-02-13-03:48:00:\n-rw-------. 1 root root 1351110790 Feb 13 03:48 vmcore\n";
        let parsed = parse_crash_listing(listing, "var/crash/listing.txt").unwrap();
        assert_eq!(parsed.count, 1);
        assert_eq!(parsed.source_path, "var/crash/listing.txt");
        assert_eq!(parsed.entries[0].source_line, Some(2));

        let conf = parse_kdump_conf(
            "path /var/crash\ncore_collector makedumpfile -c\nfailure_action reboot\n",
            "etc/kdump.conf",
        );
        assert_eq!(conf.path, "/var/crash");
        assert_eq!(conf.default_action.as_deref(), Some("reboot"));
        assert_eq!(conf.source_path, "etc/kdump.conf");
    }
}
