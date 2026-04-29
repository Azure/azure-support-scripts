use regex::Regex;
use serde::{Deserialize, Serialize};

fn extract_timestamp(line: &str) -> Option<String> {
    let iso_re = Regex::new(r"^(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)").unwrap();
    let syslog_re = Regex::new(r"^(\w{3})\s+(\d{1,2})\s+(\d{2}:\d{2}:\d{2}(?:\.\d+)?)").unwrap();
    if let Some(c) = iso_re.captures(line) {
        return c.get(1).map(|m| m.as_str().to_string());
    }
    // Normalise classic syslog timestamp so single-digit day numbers are zero
    // padded ("Dec  2 ..." -> "Dec 02 ..."), matching the legacy JS parser
    // behaviour required for cross-file deduplication.
    syslog_re.captures(line).map(|c| {
        let month = c.get(1).map(|m| m.as_str()).unwrap_or("");
        let day = c.get(2).map(|m| m.as_str()).unwrap_or("");
        let time = c.get(3).map(|m| m.as_str()).unwrap_or("");
        format!("{} {:0>2} {}", month, day, time)
    })
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SimpleEvent {
    pub timestamp: String,
    pub line_number: usize,
    pub raw_line: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EmergencyModeResult {
    pub found: bool,
    pub count: usize,
    pub events: Vec<SimpleEvent>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct KernelRebootEvent {
    pub timestamp: String,
    pub line_number: usize,
    pub kernel_version: Option<String>,
    pub event_type: String,
    pub raw_line: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct KernelRebootsResult {
    pub count: usize,
    pub events: Vec<KernelRebootEvent>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OomEvent {
    pub timestamp: String,
    pub line_number: usize,
    pub pid: Option<String>,
    pub process_name: Option<String>,
    pub score: Option<String>,
    pub total_vm: Option<String>,
    pub invoked_by: Option<String>,
    pub order: Option<String>,
    pub event_type: String,
    pub raw_line: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OomKillerResult {
    pub count: usize,
    pub events: Vec<OomEvent>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct XfsErrorEvent {
    pub timestamp: String,
    pub line_number: usize,
    pub device: String,
    pub message: String,
    pub raw_line: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct XfsErrorsResult {
    pub count: usize,
    pub events: Vec<XfsErrorEvent>,
    pub source_path: String,
}

pub fn parse_emergency_mode(content: &str, source_path: &str) -> EmergencyModeResult {
    let mut events = Vec::new();
    for (i, line) in content.lines().enumerate() {
        if !line.contains("emergency mode") {
            continue;
        }
        if Regex::new(r"(?i)You are in emergency mode").unwrap().is_match(line) {
            let line_no = i + 1;
            events.push(SimpleEvent {
                timestamp: extract_timestamp(line).unwrap_or_else(|| "Date not detected".to_string()),
                line_number: line_no,
                raw_line: line.trim().to_string(),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
        }
    }
    EmergencyModeResult {
        found: !events.is_empty(),
        count: events.len(),
        events,
        source_path: source_path.to_string(),
    }
}

pub fn parse_kernel_reboots(content: &str, source_path: &str) -> KernelRebootsResult {
    let kernel_re = Regex::new(r"(?i)(?:kernel:\s*)?(?:\[\s*[\d\.]+\]\s*(?:\[\s*T\d+\]\s*)?)?Linux version\s+([\d\.\-\w]+)").unwrap();
    let shutdown_re = Regex::new(r"(?i)systemd.*Shutting down|systemd.*Starting Reboot|systemd.*Stopped target.*Shutdown").unwrap();
    let reboot_re = Regex::new(r"(?i)kernel:\s*reboot:").unwrap();

    let mut events = Vec::new();
    for (i, line) in content.lines().enumerate() {
        if !(line.contains("Linux version") || line.contains("hutting down") || line.contains("tarting Reboot") || line.contains("topped target") || line.contains("reboot:")) {
            continue;
        }
        let line_no = i + 1;

        if let Some(caps) = kernel_re.captures(line) {
            events.push(KernelRebootEvent {
                timestamp: extract_timestamp(line).unwrap_or_else(|| "Unknown".to_string()),
                line_number: line_no,
                kernel_version: caps.get(1).map(|m| m.as_str().to_string()),
                event_type: "kernel_boot".to_string(),
                raw_line: line.trim().to_string(),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
            continue;
        }

        if shutdown_re.is_match(line) {
            let duplicate = events
                .iter()
                .any(|e| e.event_type == "systemd_shutdown" && e.line_number.abs_diff(line_no) < 5);
            if !duplicate {
                events.push(KernelRebootEvent {
                    timestamp: extract_timestamp(line).unwrap_or_else(|| "Unknown".to_string()),
                    line_number: line_no,
                    kernel_version: None,
                    event_type: "systemd_shutdown".to_string(),
                    raw_line: line.trim().to_string(),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
            continue;
        }

        if reboot_re.is_match(line) {
            events.push(KernelRebootEvent {
                timestamp: extract_timestamp(line).unwrap_or_else(|| "Unknown".to_string()),
                line_number: line_no,
                kernel_version: None,
                event_type: "reboot_message".to_string(),
                raw_line: line.trim().to_string(),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
        }
    }
    KernelRebootsResult { count: events.len(), events, source_path: source_path.to_string() }
}

pub fn parse_oom_killer(content: &str, source_path: &str) -> OomKillerResult {
    let kill_re = Regex::new(r"(?i)Out of memory:.*Kill(?:ed)? process\s+(\d+)\s+\(([^)]+)\)").unwrap();
    let score_re = Regex::new(r"(?i)score\s+(\d+)").unwrap();
    let vm_re = Regex::new(r"(?i)total-vm:(\d+)kB").unwrap();
    let invoked_re = Regex::new(r"(?i)\]\s+([^\s]+)\s+invoked oom-killer:").unwrap();
    let order_re = Regex::new(r"(?i)order=(\d+)").unwrap();
    let pid_re = Regex::new(r"(?i)reaped process\s+(\d+)").unwrap();
    let process_re = Regex::new(r"\]\s+([^\s:]+):").unwrap();

    let mut events: Vec<OomEvent> = Vec::new();
    for (i, line) in content.lines().enumerate() {
        if !(line.contains("ut of memory") || line.contains("oom-killer") || line.contains("oom_reaper") || line.contains("annot allocate memory")) {
            continue;
        }
        let line_no = i + 1;

        if let Some(caps) = kill_re.captures(line) {
            events.push(OomEvent {
                timestamp: extract_timestamp(line).unwrap_or_else(|| "Unknown".to_string()),
                line_number: line_no,
                pid: caps.get(1).map(|m| m.as_str().to_string()),
                process_name: caps.get(2).map(|m| m.as_str().to_string()),
                score: score_re.captures(line).and_then(|c| c.get(1).map(|m| m.as_str().to_string())),
                total_vm: vm_re.captures(line).and_then(|c| c.get(1).map(|m| format!("{}kB", m.as_str()))),
                invoked_by: None,
                order: None,
                event_type: "oom_kill".to_string(),
                raw_line: line.trim().to_string(),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            });
            continue;
        }

        if Regex::new(r"(?i)invoked oom-killer:").unwrap().is_match(line) {
            let duplicate = events
                .iter()
                .any(|e| e.event_type == "oom_invoked" && e.line_number.abs_diff(line_no) < 3);
            if !duplicate {
                events.push(OomEvent {
                    timestamp: extract_timestamp(line).unwrap_or_else(|| "Unknown".to_string()),
                    line_number: line_no,
                    pid: None,
                    process_name: None,
                    score: None,
                    total_vm: None,
                    invoked_by: invoked_re.captures(line).and_then(|c| c.get(1).map(|m| m.as_str().to_string())),
                    order: order_re.captures(line).and_then(|c| c.get(1).map(|m| m.as_str().to_string())),
                    event_type: "oom_invoked".to_string(),
                    raw_line: line.trim().to_string(),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
            continue;
        }

        if Regex::new(r"(?i)oom_reaper:").unwrap().is_match(line) {
            let duplicate = events
                .iter()
                .any(|e| e.event_type == "oom_reaper" && e.line_number.abs_diff(line_no) < 3);
            if !duplicate {
                events.push(OomEvent {
                    timestamp: extract_timestamp(line).unwrap_or_else(|| "Unknown".to_string()),
                    line_number: line_no,
                    pid: pid_re.captures(line).and_then(|c| c.get(1).map(|m| m.as_str().to_string())),
                    process_name: None,
                    score: None,
                    total_vm: None,
                    invoked_by: None,
                    order: None,
                    event_type: "oom_reaper".to_string(),
                    raw_line: line.trim().to_string(),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
            continue;
        }

        if Regex::new(r"(?i)Cannot allocate memory").unwrap().is_match(line) {
            let duplicate = events
                .iter()
                .any(|e| e.event_type == "alloc_failure" && e.line_number.abs_diff(line_no) < 3);
            if !duplicate {
                events.push(OomEvent {
                    timestamp: extract_timestamp(line).unwrap_or_else(|| "Unknown".to_string()),
                    line_number: line_no,
                    pid: None,
                    process_name: process_re.captures(line).and_then(|c| c.get(1).map(|m| m.as_str().to_string())),
                    score: None,
                    total_vm: None,
                    invoked_by: None,
                    order: None,
                    event_type: "alloc_failure".to_string(),
                    raw_line: line.trim().to_string(),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
        }
    }
    OomKillerResult { count: events.len(), events, source_path: source_path.to_string() }
}

pub fn parse_xfs_errors(content: &str, source_path: &str) -> XfsErrorsResult {
    let xfs_pattern = Regex::new(r"(?i)XFS\s+\(([^)]+)\):\s*(.+)").unwrap();
    let critical_re = Regex::new(r"(?i)please unmount.*rectify|metadata.*corruption|corruption.*detected|corruption warning|internal error|shutting down filesystem|filesystem has been shut down|duplicate UUID.*can't mount|unrecovered unlinked inode").unwrap();

    let mut events = Vec::new();
    for (i, line) in content.lines().enumerate() {
        if !line.contains("XFS") {
            continue;
        }
        let trimmed = line.trim();
        if let Some(caps) = xfs_pattern.captures(trimmed) {
            let device = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
            let message = caps.get(2).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
            if critical_re.is_match(&message) {
                let line_no = i + 1;
                events.push(XfsErrorEvent {
                    timestamp: extract_timestamp(trimmed).unwrap_or_else(|| "Unknown".to_string()),
                    line_number: line_no,
                    device,
                    message,
                    raw_line: trimmed.to_string(),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
        }
    }
    XfsErrorsResult { count: events.len(), events, source_path: source_path.to_string() }
}

pub fn parse_emergency_mode_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_emergency_mode(content, source_path)).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_kernel_reboots_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_kernel_reboots(content, source_path)).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_oom_killer_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_oom_killer(content, source_path)).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_xfs_errors_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_xfs_errors(content, source_path)).unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PATH: &str = "var/log/messages";

    #[test]
    fn detects_emergency_mode() {
        let input = "Jan 10 12:00:00 node1 systemd[1]: You are in emergency mode.";
        let result = parse_emergency_mode(input, PATH);
        assert!(result.found);
        assert_eq!(result.count, 1);
    }

    #[test]
    fn detects_kernel_reboot_events() {
        let input = concat!(
            "Jan 10 12:00:00 node1 kernel: Linux version 5.14.0-42\n",
            "Jan 10 12:10:00 node1 systemd[1]: Shutting down.\n",
            "Jan 10 12:10:01 node1 kernel: reboot: Restarting system\n"
        );
        let result = parse_kernel_reboots(input, PATH);
        assert_eq!(result.count, 3);
    }

    #[test]
    fn detects_oom_activity() {
        let input = concat!(
            "Jan 10 12:00:00 node1 kernel: myproc invoked oom-killer: gfp_mask=0x0 order=2\n",
            "Jan 10 12:00:01 node1 kernel: Out of memory: Kill process 1234 (java) score 987 or sacrifice child total-vm:2048kB\n",
            "Jan 10 12:00:02 node1 kernel: oom_reaper: reaped process 1234 (java)\n"
        );
        let result = parse_oom_killer(input, PATH);
        assert_eq!(result.count, 3);
        assert_eq!(result.events[1].process_name.as_deref(), Some("java"));
    }

    #[test]
    fn detects_xfs_errors() {
        let input = "Jan 10 12:00:00 node1 kernel: XFS (sdd1): Please unmount the filesystem and rectify the problem(s)";
        let result = parse_xfs_errors(input, PATH);
        assert_eq!(result.count, 1);
        assert_eq!(result.events[0].device, "sdd1");
    }

    #[test]
    fn events_carry_source_provenance() {
        let input = concat!(
            "Jan 10 12:00:00 node1 systemd[1]: You are in emergency mode.\n",
            "Jan 10 12:00:01 node1 kernel: Out of memory: Kill process 1234 (java) score 987 total-vm:2048kB\n",
            "Jan 10 12:00:02 node1 kernel: XFS (sdd1): Please unmount the filesystem and rectify the problem(s)\n",
            "Jan 10 12:00:03 node1 kernel: Linux version 5.14.0-42\n"
        );
        let em = parse_emergency_mode(input, PATH);
        assert_eq!(em.source_path, PATH);
        assert_eq!(em.events[0].source_path, PATH);
        assert_eq!(em.events[0].source_line, Some(1));

        let oom = parse_oom_killer(input, PATH);
        assert_eq!(oom.events[0].source_line, Some(2));
        assert_eq!(oom.events[0].source_path, PATH);

        let xfs = parse_xfs_errors(input, PATH);
        assert_eq!(xfs.events[0].source_line, Some(3));
        assert_eq!(xfs.events[0].source_path, PATH);

        let kr = parse_kernel_reboots(input, PATH);
        assert_eq!(kr.events[0].source_line, Some(4));
        assert_eq!(kr.events[0].source_path, PATH);
    }

    #[test]
    fn events_json_wrappers_include_source_path() {
        let input = "Jan 10 12:00:00 node1 systemd[1]: You are in emergency mode.";
        let json = parse_emergency_mode_json(input, PATH);
        assert!(json.contains("\"source_path\":\"var/log/messages\""));
    }
}
