//! SAP HANA trace-file parsers.
//!
//! Currently provides a single detector, [`parse_hana_savepoints`], which
//! scans HANA `indexserver_*.trc` / `nameserver_*.trc` trace files for
//! savepoint activity emitted by the `Savepoint` trace component
//! (`SavepointImpl.cpp`).
//!
//! A savepoint is the periodic flush of changed in-memory pages to the HANA
//! data volume (default cadence `savepoint_interval_s = 300`). Each savepoint
//! has a short blocking / critical phase that can stall writers; a long stall
//! usually points at slow `/hana/data` storage. The detector surfaces every
//! savepoint event plus warnings for:
//!
//! * `hana_savepoint_slow_callback` — a `w Savepoint ... took <N>ms` line
//!   logged by HANA itself (escalated to `error` for very long stalls).
//! * `hana_savepoint_cadence_gap` — an unusually long interval between two
//!   consecutive periodic savepoints in the same file (possible stall / I/O
//!   pressure).
//!
//! Unlike the rest of the RCA tool, these traces are *not* part of a standard
//! sosreport / supportconfig bundle — they have to be collected separately
//! (e.g. a HANA log ZIP). The parser is content-driven and only emits results
//! when savepoint lines are actually present, so feeding it unrelated trace
//! files is harmless.

use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::OnceLock;

// ---------------------------------------------------------------------------
// Tunables
// ---------------------------------------------------------------------------

/// HANA default `persistence/savepoint_interval_s`.
const DEFAULT_SAVEPOINT_INTERVAL_S: f64 = 300.0;
/// Flag a cadence gap when the observed interval exceeds this multiple of the
/// (assumed default) interval.
const CADENCE_GAP_FACTOR: f64 = 3.0;
/// A slow-callback warning at/above this duration is escalated to `error`.
const SLOW_CALLBACK_ERROR_MS: u64 = 60_000;
/// Cap on the number of detailed savepoint records retained per file, to keep
/// JSON output bounded on multi-day traces (count remains accurate).
const MAX_SAVEPOINT_RECORDS: usize = 2_000;

/// Cap on detailed records retained per detector (deadlocks / OOM / merge
/// errors), keeping JSON bounded while the `count` totals stay accurate.
const MAX_DETAIL_RECORDS: usize = 1_000;
/// Number of entries kept in each "top contended objects / statements" list.
const TOP_N: usize = 10;
/// A deadlock count at/above this value is escalated from `warning` to `error`.
const DEADLOCK_ERROR_COUNT: usize = 25;
/// A merge-error count at/above this value is escalated to `error`.
const MERGE_ERROR_ERROR_COUNT: usize = 50;
/// HANA return code for "not enough merge tokens" (delta merge / compression).
const RC_MERGE_TOKEN_EXHAUSTION: &str = "2465";

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HanaWarning {
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
pub struct HanaSavepoint {
    /// HANA trace timestamp, e.g. `2026-06-03 19:54:09.350130`.
    pub timestamp: String,
    /// `Savepoint` (periodic / triggered) or `Snapshot`.
    pub kind: String,
    /// For snapshots, the `kind:` qualifier (e.g. `Replication`), if present.
    pub snapshot_kind: Option<String>,
    pub savepoint_version: Option<u64>,
    pub next_savepoint_version: Option<u64>,
    pub last_snapshot_version: Option<u64>,
    pub restart_redo_log_position: Option<String>,
    pub dropped_version: Option<u64>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HanaSavepointsResult {
    pub found: bool,
    /// Total number of periodic/triggered savepoint events (`Savepoint ...`).
    pub count: usize,
    /// Number of snapshot savepoint events (`Snapshot ...`).
    pub snapshot_count: usize,
    /// Most recent savepoint timestamp seen in this file.
    pub last_savepoint: Option<String>,
    /// Mean interval (seconds) between consecutive periodic savepoints.
    pub avg_interval_s: Option<f64>,
    /// Longest observed interval (seconds) between consecutive savepoints.
    pub max_interval_s: Option<f64>,
    pub savepoints: Vec<HanaSavepoint>,
    pub warnings: Vec<HanaWarning>,
    pub source_path: String,
}

impl Default for HanaSavepointsResult {
    fn default() -> Self {
        Self {
            found: false,
            count: 0,
            snapshot_count: 0,
            last_savepoint: None,
            avg_interval_s: None,
            max_interval_s: None,
            savepoints: Vec::new(),
            warnings: Vec::new(),
            source_path: String::new(),
        }
    }
}

/// A `name -> count` tally entry used for "top contended objects / statements".
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HanaCount {
    pub name: String,
    pub count: usize,
}

/// One transaction participating in a deadlock cycle.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HanaDeadlockParty {
    pub is_victim: bool,
    pub conn_id: Option<String>,
    pub client_host: Option<String>,
    pub client_ip: Option<String>,
    pub app_user: Option<String>,
    pub db_user: Option<String>,
    pub object_name: Option<String>,
    pub lock_type: Option<String>,
    pub stmt_hash: Option<String>,
    pub statement: Option<String>,
}

/// A single `Deadlock detected` event from the `Lock` (`WaitGraph.cc`)
/// component of a HANA indexserver alert trace.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HanaDeadlock {
    pub timestamp: String,
    /// Number of transactions in the reported deadlock cycle.
    pub participant_count: usize,
    /// Distinct lock objects (tables) named in the cycle.
    pub objects: Vec<String>,
    /// The transaction HANA rolled back to break the cycle.
    pub victim: Option<HanaDeadlockParty>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct HanaDeadlocksResult {
    pub found: bool,
    pub count: usize,
    pub last_deadlock: Option<String>,
    /// Tables most frequently involved in a deadlock cycle.
    pub top_objects: Vec<HanaCount>,
    /// Statement hashes most frequently rolled back as the victim.
    pub top_statements: Vec<HanaCount>,
    pub deadlocks: Vec<HanaDeadlock>,
    pub warnings: Vec<HanaWarning>,
    pub source_path: String,
}

/// A single `OUT OF MEMORY occurred` event from the `Memory` component.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HanaOomEvent {
    pub timestamp: String,
    pub memory_type: Option<String>,
    pub host: Option<String>,
    pub executable: Option<String>,
    pub pid: Option<String>,
    pub failed_alloc_bytes: Option<u64>,
    pub failure_type: Option<String>,
    /// Global allocation limit (bytes) from the IPMM short-info block.
    pub global_allocation_limit_bytes: Option<u64>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct HanaOomResult {
    pub found: bool,
    pub count: usize,
    pub last_oom: Option<String>,
    pub events: Vec<HanaOomEvent>,
    pub warnings: Vec<HanaWarning>,
    pub source_path: String,
}

/// A single delta-merge / optimize-compression failure.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HanaMergeError {
    pub timestamp: String,
    /// `delta_merge` or `optimize_compres`.
    pub component: String,
    pub table: Option<String>,
    pub table_id: Option<u64>,
    pub motivation: Option<String>,
    pub rc: Option<String>,
    pub message: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct HanaMergeErrorsResult {
    pub found: bool,
    pub count: usize,
    /// Failures attributed to delta merge (`delta_merge`).
    pub merge_error_count: usize,
    /// Failures attributed to optimize compression (`optimize_compres`).
    pub compression_error_count: usize,
    /// Failures whose return code is `2465` (merge-token exhaustion).
    pub token_exhaustion_count: usize,
    pub last_error: Option<String>,
    /// Tables most frequently failing to merge / compress.
    pub top_tables: Vec<HanaCount>,
    pub errors: Vec<HanaMergeError>,
    pub warnings: Vec<HanaWarning>,
    pub source_path: String,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Matches a standard HANA trace line emitted by the `Savepoint` component:
/// `[<thread>]{<conn>}[<txn>] <date> <time> <sev> Savepoint <src>(<ln>) : <msg>`
fn savepoint_line_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(
            r"^\[\d+\]\{[^}]*\}\[[^\]]*\]\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\s+([iwe])\s+Savepoint\s+\S+\(\d+\)\s*:\s*(.*)$",
        )
        .unwrap()
    })
}

/// Matches any standard HANA trace-line header, capturing
/// `(timestamp, severity, component, message)`:
/// `[<thread>]{<conn>}[<txn>] <date> <time> <sev> <component> <src>(<ln>) : <msg>`
fn trace_header_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(
            r"^\[\d+\]\{[^}]*\}\[[^\]]*\]\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\s+([iwedf])\s+(\S+)\s+\S+\(\d+\)\s*:\s*(.*)$",
        )
        .unwrap()
    })
}

/// True when `line` begins a new HANA trace record (`[<thread>]{...`), used to
/// bound multi-line blocks (deadlock cycles, OOM dumps).
fn is_trace_header(line: &str) -> bool {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^\[\d+\]\{").unwrap())
        .is_match(line)
}

/// Take the top-`TOP_N` `(name, count)` entries from a tally, ordered by count
/// descending then name ascending for deterministic output.
fn top_counts(map: &HashMap<String, usize>) -> Vec<HanaCount> {
    let mut entries: Vec<HanaCount> = map
        .iter()
        .map(|(name, count)| HanaCount {
            name: name.clone(),
            count: *count,
        })
        .collect();
    entries.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| a.name.cmp(&b.name)));
    entries.truncate(TOP_N);
    entries
}

fn capture_u64(re: &Regex, text: &str) -> Option<u64> {
    re.captures(text)
        .and_then(|c| c.get(1))
        .and_then(|m| m.as_str().parse::<u64>().ok())
}

fn capture_str(re: &Regex, text: &str) -> Option<String> {
    re.captures(text)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().to_string())
}

/// Parse a HANA trace timestamp (`YYYY-MM-DD HH:MM:SS.ffffff`) into seconds
/// since the Unix epoch (UTC, naive — adequate for interval arithmetic).
fn timestamp_to_secs(ts: &str) -> Option<f64> {
    // ts: "2026-06-03 19:54:09.350130"
    let (date, rest) = ts.split_once(' ')?;
    let mut dparts = date.split('-');
    let year: i64 = dparts.next()?.parse().ok()?;
    let month: i64 = dparts.next()?.parse().ok()?;
    let day: i64 = dparts.next()?.parse().ok()?;
    let (hms, frac) = match rest.split_once('.') {
        Some((a, b)) => (a, b),
        None => (rest, "0"),
    };
    let mut tparts = hms.split(':');
    let hh: i64 = tparts.next()?.parse().ok()?;
    let mm: i64 = tparts.next()?.parse().ok()?;
    let ss: i64 = tparts.next()?.parse().ok()?;
    // Days from civil (Howard Hinnant's algorithm), valid for the Gregorian
    // calendar — good enough for interval differences between two timestamps.
    let y = if month <= 2 { year - 1 } else { year };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    let frac_secs: f64 = format!("0.{frac}").parse().unwrap_or(0.0);
    Some(days as f64 * 86400.0 + hh as f64 * 3600.0 + mm as f64 * 60.0 + ss as f64 + frac_secs)
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

pub fn parse_hana_savepoints(content: &str, source_path: &str) -> HanaSavepointsResult {
    static EVENT_RE: OnceLock<Regex> = OnceLock::new();
    static VERSION_RE: OnceLock<Regex> = OnceLock::new();
    static NEXT_RE: OnceLock<Regex> = OnceLock::new();
    static LAST_SNAP_RE: OnceLock<Regex> = OnceLock::new();
    static REDO_RE: OnceLock<Regex> = OnceLock::new();
    static DROPPED_RE: OnceLock<Regex> = OnceLock::new();
    static KIND_RE: OnceLock<Regex> = OnceLock::new();
    static TOOK_RE: OnceLock<Regex> = OnceLock::new();

    // `Savepoint current savepoint version: N` / `Snapshot current savepoint version: N`
    let event_re = EVENT_RE
        .get_or_init(|| Regex::new(r"^(Savepoint|Snapshot)\s+current savepoint version:").unwrap());
    let version_re =
        VERSION_RE.get_or_init(|| Regex::new(r"current savepoint version:\s*(\d+)").unwrap());
    let next_re =
        NEXT_RE.get_or_init(|| Regex::new(r"next savepoint version:\s*(\d+)").unwrap());
    let last_snap_re =
        LAST_SNAP_RE.get_or_init(|| Regex::new(r"last snapshot SP version:\s*(\d+)").unwrap());
    let redo_re = REDO_RE
        .get_or_init(|| Regex::new(r"restart redo log position:\s*(0x[0-9a-fA-F]+)").unwrap());
    let dropped_re = DROPPED_RE.get_or_init(|| Regex::new(r"dropped:\s*(\d+)").unwrap());
    let kind_re = KIND_RE.get_or_init(|| Regex::new(r"kind:\s*(\w+)").unwrap());
    let took_re = TOOK_RE.get_or_init(|| Regex::new(r"took\s+(\d+)\s*ms").unwrap());

    let line_re = savepoint_line_re();

    let mut result = HanaSavepointsResult {
        source_path: source_path.to_string(),
        ..Default::default()
    };

    // (timestamp_secs, is_periodic_savepoint) for cadence analysis.
    let mut periodic_times: Vec<(f64, usize)> = Vec::new();

    for (i, line) in content.lines().enumerate() {
        if !line.contains("Savepoint") {
            continue;
        }
        let caps = match line_re.captures(line) {
            Some(c) => c,
            None => continue,
        };
        let line_no = i + 1;
        let timestamp = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
        let severity = caps.get(2).map(|m| m.as_str()).unwrap_or("i");
        let message = caps.get(3).map(|m| m.as_str()).unwrap_or("");

        if event_re.is_match(message) {
            let kind = if message.starts_with("Snapshot") {
                "Snapshot"
            } else {
                "Savepoint"
            };
            let snapshot_kind = if kind == "Snapshot" {
                capture_str(kind_re, message)
            } else {
                None
            };
            let sp = HanaSavepoint {
                timestamp: timestamp.clone(),
                kind: kind.to_string(),
                snapshot_kind,
                savepoint_version: capture_u64(version_re, message),
                next_savepoint_version: capture_u64(next_re, message),
                last_snapshot_version: capture_u64(last_snap_re, message),
                restart_redo_log_position: capture_str(redo_re, message),
                dropped_version: capture_u64(dropped_re, message),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            };

            if kind == "Snapshot" {
                result.snapshot_count += 1;
            } else {
                result.count += 1;
                if let Some(secs) = timestamp_to_secs(&timestamp) {
                    periodic_times.push((secs, line_no));
                }
            }
            result.last_savepoint = Some(timestamp);
            if result.savepoints.len() < MAX_SAVEPOINT_RECORDS {
                result.savepoints.push(sp);
            }
            continue;
        }

        // Slow-callback warning: HANA logs these at `w` (warning) level.
        if severity == "w" {
            if let Some(ms) = capture_u64(took_re, message) {
                let secs = ms as f64 / 1000.0;
                let severity_label = if ms >= SLOW_CALLBACK_ERROR_MS {
                    "error"
                } else {
                    "warning"
                };
                result.warnings.push(HanaWarning {
                    r#type: "hana_savepoint_slow_callback".to_string(),
                    message: format!("HANA savepoint callback stalled for {secs:.1}s"),
                    details: Some(message.to_string()),
                    severity: Some(severity_label.to_string()),
                    recommendation: Some(
                        "A long savepoint callback indicates slow /hana/data storage or lock \
                         contention; review data-volume I/O latency and throughput."
                            .to_string(),
                    ),
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
        }
    }

    // Cadence analysis over periodic savepoints in chronological order.
    if periodic_times.len() >= 2 {
        let mut times: Vec<(f64, usize)> = periodic_times.clone();
        times.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        let mut total = 0.0;
        let mut intervals = 0u64;
        let mut max_interval = 0.0_f64;
        let gap_threshold = DEFAULT_SAVEPOINT_INTERVAL_S * CADENCE_GAP_FACTOR;
        for win in times.windows(2) {
            let delta = win[1].0 - win[0].0;
            if delta < 0.0 {
                continue;
            }
            total += delta;
            intervals += 1;
            if delta > max_interval {
                max_interval = delta;
            }
            if delta > gap_threshold {
                result.warnings.push(HanaWarning {
                    r#type: "hana_savepoint_cadence_gap".to_string(),
                    message: format!(
                        "Gap of {:.0}s between consecutive savepoints (expected ~{:.0}s)",
                        delta, DEFAULT_SAVEPOINT_INTERVAL_S
                    ),
                    details: Some(format!(
                        "No periodic savepoint completed between trace lines {} and {}",
                        win[0].1, win[1].1
                    )),
                    severity: Some("info".to_string()),
                    recommendation: Some(
                        "Long gaps between savepoints extend crash-recovery time and can signal \
                         that savepoints are blocked on I/O; correlate with /hana/data latency."
                            .to_string(),
                    ),
                    source_path: source_path.to_string(),
                    source_line: Some(win[1].1),
                    source_line_end: Some(win[1].1),
                });
            }
        }
        if intervals > 0 {
            result.avg_interval_s = Some(total / intervals as f64);
            result.max_interval_s = Some(max_interval);
        }
    }

    result.found = result.count > 0 || result.snapshot_count > 0 || !result.warnings.is_empty();
    result
}

pub fn parse_hana_savepoints_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_hana_savepoints(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    super::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "null".to_string())
}

// ===========================================================================
// Deadlock detector
// ===========================================================================

/// Extract a `KEY=VALUE` field (value terminated by `,` or `]`) from a HANA
/// deadlock participant line. `APPUSER = X` (with spaces) is handled too.
fn participant_field(line: &str, key: &str) -> Option<String> {
    // Build a tiny regex per (cached) key. The set of keys is fixed and small.
    let pos = line.find(key)?;
    let after = &line[pos + key.len()..];
    let after = after.trim_start();
    let after = after.strip_prefix('=')?.trim_start();
    let end = after.find(|c| c == ',' || c == ']').unwrap_or(after.len());
    let val = after[..end].trim();
    if val.is_empty() {
        None
    } else {
        Some(val.to_string())
    }
}

/// Extract the trailing `STMT=...` statement text from a participant line.
fn participant_statement(line: &str) -> Option<String> {
    let pos = line.find("STMT=")?;
    let mut stmt = line[pos + "STMT=".len()..].trim().to_string();
    // Drop a single trailing `]` that closes the participant bracket.
    if stmt.ends_with(']') {
        stmt.pop();
    }
    let stmt = stmt.trim();
    if stmt.is_empty() {
        return None;
    }
    // Keep storage bounded; statements can be very long.
    const MAX_STMT: usize = 500;
    if stmt.len() > MAX_STMT {
        let mut truncated: String = stmt.chars().take(MAX_STMT).collect();
        truncated.push('…');
        Some(truncated)
    } else {
        Some(stmt.to_string())
    }
}

fn parse_deadlock_party(line: &str) -> HanaDeadlockParty {
    HanaDeadlockParty {
        is_victim: line.contains("(victim)"),
        conn_id: participant_field(line, "CONNID"),
        client_host: participant_field(line, "CLIENT_HOST"),
        client_ip: participant_field(line, "CLIENT_IP"),
        app_user: participant_field(line, "APPUSER"),
        db_user: participant_field(line, "DBUSER"),
        object_name: participant_field(line, "OBJECT_NAME"),
        lock_type: participant_field(line, "LOCK_TYPE"),
        stmt_hash: participant_field(line, "STMT_HASH"),
        statement: participant_statement(line),
    }
}

pub fn parse_hana_deadlocks(content: &str, source_path: &str) -> HanaDeadlocksResult {
    let lines: Vec<&str> = content.lines().collect();
    let header_re = trace_header_re();

    let mut result = HanaDeadlocksResult {
        source_path: source_path.to_string(),
        ..Default::default()
    };
    let mut object_counts: HashMap<String, usize> = HashMap::new();
    let mut stmt_counts: HashMap<String, usize> = HashMap::new();

    let mut i = 0usize;
    while i < lines.len() {
        let line = lines[i];
        let caps = match header_re.captures(line) {
            Some(c) => c,
            None => {
                i += 1;
                continue;
            }
        };
        let component = caps.get(3).map(|m| m.as_str()).unwrap_or("");
        if component != "Lock" || !line.contains("WaitGraph") {
            i += 1;
            continue;
        }
        let timestamp = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
        let start_line = i + 1;

        // Gather the continuation block (until the next trace header / EOF).
        let mut j = i + 1;
        let mut block: Vec<&str> = Vec::new();
        while j < lines.len() && !is_trace_header(lines[j]) {
            block.push(lines[j]);
            j += 1;
        }
        let end_line = j; // 1-based index of last block line (= j when j>start)

        if block.iter().any(|l| l.contains("Deadlock detected")) {
            let parties: Vec<HanaDeadlockParty> = block
                .iter()
                .filter(|l| l.contains("CONNID="))
                .map(|l| parse_deadlock_party(l))
                .collect();

            // Distinct objects in the cycle.
            let mut objects: Vec<String> = Vec::new();
            for p in &parties {
                if let Some(obj) = &p.object_name {
                    if !objects.contains(obj) {
                        objects.push(obj.clone());
                    }
                }
            }
            for obj in &objects {
                *object_counts.entry(obj.clone()).or_insert(0) += 1;
            }

            let victim = parties.iter().find(|p| p.is_victim).cloned();
            if let Some(v) = &victim {
                if let Some(h) = &v.stmt_hash {
                    *stmt_counts.entry(h.clone()).or_insert(0) += 1;
                }
            }

            result.count += 1;
            result.last_deadlock = Some(timestamp.clone());
            if result.deadlocks.len() < MAX_DETAIL_RECORDS {
                result.deadlocks.push(HanaDeadlock {
                    timestamp,
                    participant_count: parties.len(),
                    objects,
                    victim,
                    source_path: source_path.to_string(),
                    source_line: Some(start_line),
                    source_line_end: Some(end_line.max(start_line)),
                });
            }
        }
        i = j;
    }

    if result.count > 0 {
        result.top_objects = top_counts(&object_counts);
        result.top_statements = top_counts(&stmt_counts);
        let severity = if result.count >= DEADLOCK_ERROR_COUNT {
            "error"
        } else {
            "warning"
        };
        let top_obj = result
            .top_objects
            .first()
            .map(|c| format!("{} ({} deadlocks)", c.name, c.count))
            .unwrap_or_else(|| "unknown".to_string());
        result.warnings.push(HanaWarning {
            r#type: "hana_deadlocks_detected".to_string(),
            message: format!(
                "{} deadlock(s) detected; HANA rolled back a victim transaction each time",
                result.count
            ),
            details: Some(format!("Most contended object: {top_obj}")),
            severity: Some(severity.to_string()),
            recommendation: Some(
                "Recurring deadlocks usually mean concurrent transactions update the same rows \
                 in different orders. Review the contended table/statement and the application's \
                 update ordering, batch size, and commit frequency."
                    .to_string(),
            ),
            source_path: source_path.to_string(),
            source_line: result.deadlocks.first().and_then(|d| d.source_line),
            source_line_end: result.deadlocks.last().and_then(|d| d.source_line_end),
        });
    }

    result.found = result.count > 0;
    result
}

pub fn parse_hana_deadlocks_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_hana_deadlocks(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    super::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "null".to_string())
}

// ===========================================================================
// Out-of-memory detector
// ===========================================================================

pub fn parse_hana_oom(content: &str, source_path: &str) -> HanaOomResult {
    static MEMTYPE_RE: OnceLock<Regex> = OnceLock::new();
    static HOST_RE: OnceLock<Regex> = OnceLock::new();
    static EXEC_RE: OnceLock<Regex> = OnceLock::new();
    static PID_RE: OnceLock<Regex> = OnceLock::new();
    static FAILED_RE: OnceLock<Regex> = OnceLock::new();
    static FAILTYPE_RE: OnceLock<Regex> = OnceLock::new();
    static GAL_RE: OnceLock<Regex> = OnceLock::new();

    let memtype_re = MEMTYPE_RE.get_or_init(|| Regex::new(r"(?m)^MemoryType:\s*(\S+)").unwrap());
    let host_re = HOST_RE.get_or_init(|| Regex::new(r"(?m)^Host:\s*(\S+)").unwrap());
    let exec_re = EXEC_RE.get_or_init(|| Regex::new(r"(?m)^Executable:\s*(\S+)").unwrap());
    let pid_re = PID_RE.get_or_init(|| Regex::new(r"(?m)^PID:\s*(\d+)").unwrap());
    let failed_re =
        FAILED_RE.get_or_init(|| Regex::new(r"Failed to allocate \S+ \((\d+)b\)").unwrap());
    let failtype_re =
        FAILTYPE_RE.get_or_init(|| Regex::new(r"Allocation failure type:\s*(\S+)").unwrap());
    let gal_re = GAL_RE
        .get_or_init(|| Regex::new(r"GLOBAL_ALLOCATION_LIMIT \(GAL\)\s*=\s*[^(]*\((\d+)b\)").unwrap());

    let lines: Vec<&str> = content.lines().collect();
    let header_re = trace_header_re();

    let mut result = HanaOomResult {
        source_path: source_path.to_string(),
        ..Default::default()
    };

    let mut i = 0usize;
    while i < lines.len() {
        let line = lines[i];
        let caps = match header_re.captures(line) {
            Some(c) => c,
            None => {
                i += 1;
                continue;
            }
        };
        let component = caps.get(3).map(|m| m.as_str()).unwrap_or("");
        let message = caps.get(4).map(|m| m.as_str()).unwrap_or("");
        if component != "Memory" || !message.starts_with("OUT OF MEMORY occurred") {
            i += 1;
            continue;
        }
        let timestamp = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
        let start_line = i + 1;

        let mut j = i + 1;
        while j < lines.len() && !is_trace_header(lines[j]) {
            j += 1;
        }
        let block = lines[i..j].join("\n");

        result.count += 1;
        result.last_oom = Some(timestamp.clone());
        if result.events.len() < MAX_DETAIL_RECORDS {
            result.events.push(HanaOomEvent {
                timestamp,
                memory_type: capture_str(memtype_re, &block),
                host: capture_str(host_re, &block),
                executable: capture_str(exec_re, &block),
                pid: capture_str(pid_re, &block),
                failed_alloc_bytes: capture_u64(failed_re, &block),
                failure_type: capture_str(failtype_re, &block),
                global_allocation_limit_bytes: capture_u64(gal_re, &block),
                source_path: source_path.to_string(),
                source_line: Some(start_line),
                source_line_end: Some(j.max(start_line)),
            });
        }
        i = j;
    }

    if result.count > 0 {
        let first = result.events.first();
        let details = first.map(|e| {
            let ft = e.failure_type.as_deref().unwrap_or("unknown");
            let host = e.host.as_deref().unwrap_or("?");
            format!("First OOM on {host}: allocation failure type {ft}")
        });
        result.warnings.push(HanaWarning {
            r#type: "hana_out_of_memory".to_string(),
            message: format!(
                "{} HANA out-of-memory event(s) — an allocation hit the global allocation limit",
                result.count
            ),
            details,
            severity: Some("error".to_string()),
            recommendation: Some(
                "OOM means HANA could not allocate within its global allocation limit. Check the \
                 largest memory consumers (column-store tables, statement memory, heap \
                 allocators), reduce statement_memory_limit offenders, and verify the host has \
                 enough physical RAM for the configured limit."
                    .to_string(),
            ),
            source_path: source_path.to_string(),
            source_line: first.and_then(|e| e.source_line),
            source_line_end: result.events.last().and_then(|e| e.source_line_end),
        });
    }

    result.found = result.count > 0;
    result
}

pub fn parse_hana_oom_json(content: &str, source_path: &str) -> String {
    let mut value =
        serde_json::to_value(parse_hana_oom(content, source_path)).unwrap_or(serde_json::Value::Null);
    super::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "null".to_string())
}

// ===========================================================================
// Delta-merge / optimize-compression failure detector
// ===========================================================================

pub fn parse_hana_merge_errors(content: &str, source_path: &str) -> HanaMergeErrorsResult {
    static TABLE_RE: OnceLock<Regex> = OnceLock::new();
    static MOTIV_RE: OnceLock<Regex> = OnceLock::new();
    static RC_RE: OnceLock<Regex> = OnceLock::new();

    let table_re = TABLE_RE.get_or_init(|| Regex::new(r"table = (\S+) \(t (\d+)\)").unwrap());
    let motiv_re = MOTIV_RE.get_or_init(|| Regex::new(r"merge motivation = (\w+)").unwrap());
    let rc_re = RC_RE.get_or_init(|| Regex::new(r"\brc = (\d+)").unwrap());

    let header_re = trace_header_re();

    let mut result = HanaMergeErrorsResult {
        source_path: source_path.to_string(),
        ..Default::default()
    };
    let mut table_counts: HashMap<String, usize> = HashMap::new();

    for (i, line) in content.lines().enumerate() {
        if !line.contains("delta_merge") && !line.contains("optimize_compres") {
            continue;
        }
        let caps = match header_re.captures(line) {
            Some(c) => c,
            None => continue,
        };
        let severity = caps.get(2).map(|m| m.as_str()).unwrap_or("");
        let component = caps.get(3).map(|m| m.as_str()).unwrap_or("");
        let message = caps.get(4).map(|m| m.as_str()).unwrap_or("");
        if severity != "e" || (component != "delta_merge" && component != "optimize_compres") {
            continue;
        }

        let (table, table_id) = match table_re.captures(message) {
            Some(c) => (
                c.get(1).map(|m| m.as_str().to_string()),
                c.get(2).and_then(|m| m.as_str().parse::<u64>().ok()),
            ),
            None => (None, None),
        };
        let rc = capture_str(rc_re, message);

        if component == "delta_merge" {
            result.merge_error_count += 1;
        } else {
            result.compression_error_count += 1;
        }
        if rc.as_deref() == Some(RC_MERGE_TOKEN_EXHAUSTION) {
            result.token_exhaustion_count += 1;
        }
        if let Some(t) = &table {
            *table_counts.entry(t.clone()).or_insert(0) += 1;
        }

        result.count += 1;
        result.last_error = Some(
            caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
        );
        if result.errors.len() < MAX_DETAIL_RECORDS {
            result.errors.push(HanaMergeError {
                timestamp: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                component: component.to_string(),
                table,
                table_id,
                motivation: capture_str(motiv_re, message),
                rc,
                message: message.to_string(),
                source_path: source_path.to_string(),
                source_line: Some(i + 1),
                source_line_end: Some(i + 1),
            });
        }
    }

    if result.count > 0 {
        result.top_tables = top_counts(&table_counts);
        let severity = if result.count >= MERGE_ERROR_ERROR_COUNT {
            "error"
        } else {
            "warning"
        };
        let (message, recommendation) = if result.token_exhaustion_count > 0 {
            (
                format!(
                    "{} delta-merge / compression failure(s); {} due to merge-token exhaustion (rc=2465)",
                    result.count, result.token_exhaustion_count
                ),
                "Merge-token exhaustion (rc=2465) means too many merges were requested at once, \
                 often a symptom of memory pressure or a merge backlog. Check for concurrent OOM \
                 events, the mergedog configuration, and whether large tables need manual / \
                 smart merge tuning.",
            )
        } else {
            (
                format!(
                    "{} delta-merge / optimize-compression failure(s) in HANA",
                    result.count
                ),
                "Failed merges leave tables with an oversized delta storage, hurting query \
                 performance and memory. Review the affected tables and the indexserver alert \
                 trace for the underlying cause.",
            )
        };
        let top_table = result
            .top_tables
            .first()
            .map(|c| format!("{} ({} failures)", c.name, c.count));
        result.warnings.push(HanaWarning {
            r#type: "hana_merge_failures".to_string(),
            message,
            details: top_table.map(|t| format!("Most affected table: {t}")),
            severity: Some(severity.to_string()),
            recommendation: Some(recommendation.to_string()),
            source_path: source_path.to_string(),
            source_line: result.errors.first().and_then(|e| e.source_line),
            source_line_end: result.errors.last().and_then(|e| e.source_line_end),
        });
    }

    result.found = result.count > 0;
    result
}

pub fn parse_hana_merge_errors_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_hana_merge_errors(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    super::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "null".to_string())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    const PATH: &str = "T31 HANA Logs/indexserver_vmltmdbuspd01.39003.023.trc";

    fn sp_line(ts: &str, msg: &str) -> String {
        format!("[1527771]{{-1}}[-1/-1] {ts} i Savepoint        SavepointImpl.cpp(03481) : {msg}")
    }

    #[test]
    fn detects_periodic_savepoint() {
        let input = sp_line(
            "2026-06-03 19:54:09.350130",
            "Savepoint current savepoint version: 609685, restart redo log position: 0x33cb84d9ca6, next savepoint version: 609686, last snapshot SP version: 609683",
        );
        let r = parse_hana_savepoints(&input, PATH);
        assert!(r.found);
        assert_eq!(r.count, 1);
        assert_eq!(r.snapshot_count, 0);
        assert_eq!(r.savepoints.len(), 1);
        let sp = &r.savepoints[0];
        assert_eq!(sp.kind, "Savepoint");
        assert_eq!(sp.savepoint_version, Some(609685));
        assert_eq!(sp.next_savepoint_version, Some(609686));
        assert_eq!(sp.last_snapshot_version, Some(609683));
        assert_eq!(
            sp.restart_redo_log_position.as_deref(),
            Some("0x33cb84d9ca6")
        );
        assert_eq!(sp.source_line, Some(1));
    }

    #[test]
    fn detects_snapshot_with_kind_and_dropped() {
        let input = sp_line(
            "2026-06-03 20:04:04.157061",
            "Snapshot current savepoint version: 609687, restart redo log position: 0x33cb9c4b4fb, next savepoint version: 609688, last snapshot SP version: 609687, kind: Replication",
        );
        let r = parse_hana_savepoints(&input, PATH);
        assert_eq!(r.snapshot_count, 1);
        assert_eq!(r.count, 0);
        let sp = &r.savepoints[0];
        assert_eq!(sp.kind, "Snapshot");
        assert_eq!(sp.snapshot_kind.as_deref(), Some("Replication"));
    }

    #[test]
    fn detects_dropped_version() {
        let input = sp_line(
            "2026-06-03 20:04:05.051147",
            "Savepoint current savepoint version: 609688, restart redo log position: 0x33cb9c54daa, next savepoint version: 609689, last snapshot SP version: 609687, dropped: 609683",
        );
        let r = parse_hana_savepoints(&input, PATH);
        assert_eq!(r.savepoints[0].dropped_version, Some(609683));
    }

    #[test]
    fn flags_slow_callback_warning() {
        let input = format!(
            "[1312462]{{-1}}[-1/-1] 2026-06-04 21:44:46.620914 w Savepoint        SavepointImpl.cpp(05733) : Callback PersistenceSessionSavepointCallback::spBeginRestart() took 12384ms."
        );
        let r = parse_hana_savepoints(&input, PATH);
        assert!(r.found);
        assert_eq!(r.warnings.len(), 1);
        let w = &r.warnings[0];
        assert_eq!(w.r#type, "hana_savepoint_slow_callback");
        assert_eq!(w.severity.as_deref(), Some("warning"));
        assert!(w.message.contains("12.4s"));
    }

    #[test]
    fn escalates_very_slow_callback_to_error() {
        let input = "[1312462]{-1}[-1/-1] 2026-06-04 21:44:46.620914 w Savepoint        SavepointImpl.cpp(05733) : Callback X() took 75000ms.";
        let r = parse_hana_savepoints(input, PATH);
        assert_eq!(r.warnings[0].severity.as_deref(), Some("error"));
    }

    #[test]
    fn flags_cadence_gap() {
        let mut input = String::new();
        input.push_str(&sp_line(
            "2026-06-03 19:54:00.000000",
            "Savepoint current savepoint version: 1, next savepoint version: 2, last snapshot SP version: 0",
        ));
        input.push('\n');
        // ~20 min later — well over the 3x300s gap threshold.
        input.push_str(&sp_line(
            "2026-06-03 20:14:00.000000",
            "Savepoint current savepoint version: 2, next savepoint version: 3, last snapshot SP version: 0",
        ));
        let r = parse_hana_savepoints(&input, PATH);
        assert_eq!(r.count, 2);
        assert!(r
            .warnings
            .iter()
            .any(|w| w.r#type == "hana_savepoint_cadence_gap"));
        assert!(r.max_interval_s.unwrap() > 1000.0);
    }

    #[test]
    fn ignores_non_savepoint_content() {
        let input = "[123]{-1}[-1/-1] 2026-06-03 19:54:09.350130 i Logger SomeOther.cpp(01) : nothing here\nplain text line";
        let r = parse_hana_savepoints(input, PATH);
        assert!(!r.found);
        assert_eq!(r.count, 0);
        assert!(r.savepoints.is_empty());
    }

    #[test]
    fn json_wrapper_fills_source_path() {
        let input = sp_line(
            "2026-06-03 19:54:09.350130",
            "Savepoint current savepoint version: 1, next savepoint version: 2, last snapshot SP version: 0",
        );
        let json = parse_hana_savepoints_json(&input, PATH);
        assert!(json.contains("\"found\":true"));
        assert!(json.contains(PATH));
    }

    // ----- Deadlocks -----------------------------------------------------

    const ALERT_PATH: &str = "T31 HANA Logs/indexserver_alert_vmltmdbuspd01.trc";

    fn deadlock_block(ts: &str, victim_obj: &str, stmt_hash: &str) -> String {
        format!(
            "[1528819]{{303164}}[1551/16004765485] {ts} e Lock             WaitGraph.cc(00250) : \n  Deadlock detected\n   - Deadlock cycle\n    [(victim) CONNID=303164, SESSIONID=303164, CLIENT_HOST=VMLTMAPUSPD07, CLIENT_IP=10.105.10.76, CLIENT_PID=1467392, APPUSER = ZWLATMTMS, DBUSER=SAPHANADB, ID=1551, UPDATE_TRANSACTION_ID=16004765485, TYPE=USER, STATE=ACTIVE, ISOLATION_LEVEL=RC, LOCK_TYPE=RECORD_LOCK, ACQ_LOCK_MODE=NON_KEY_EXCLUSIVE, REQ_LOCK_MODE=NON_KEY_EXCLUSIVE, OBJECT_ID=29593135, OBJECT_NAME={victim_obj}, RECORD_ID=[KEY=E20DF99BBBE981FC, HASH=1C95F99BBBC99C20], WAITING_PART_ID=0, WAITING_PHYSICAL_PART_ID=0, IS_HESITANT_LOCK=false, APPLICATION_SOURCE=SAPLSZA0:47846, STMT_HASH={stmt_hash}, STMT=UPDATE \"ADR2\" SET \"COUNTRY\" = ? WHERE \"CLIENT\" = ?]\n    [CONNID=302171, SESSIONID=302171, CLIENT_HOST=VMLTMAPUSPD03, CLIENT_IP=10.105.10.53, APPUSER = ZWLATMTMS, DBUSER=SAPHANADB, ID=586, LOCK_TYPE=RECORD_LOCK, OBJECT_ID=29593135, OBJECT_NAME={victim_obj}, STMT_HASH={stmt_hash}, STMT=UPDATE \"ADR2\" SET \"COUNTRY\" = ? WHERE \"CLIENT\" = ?]"
        )
    }

    #[test]
    fn detects_deadlock_with_victim_and_objects() {
        let input = deadlock_block(
            "2026-06-01 13:41:24.116632",
            "SAPHANADB:ADR2",
            "259829e7fca4f2c336f63a2447378053",
        );
        let r = parse_hana_deadlocks(&input, ALERT_PATH);
        assert!(r.found);
        assert_eq!(r.count, 1);
        let d = &r.deadlocks[0];
        assert_eq!(d.participant_count, 2);
        assert_eq!(d.objects, vec!["SAPHANADB:ADR2".to_string()]);
        let v = d.victim.as_ref().unwrap();
        assert!(v.is_victim);
        assert_eq!(v.conn_id.as_deref(), Some("303164"));
        assert_eq!(v.client_host.as_deref(), Some("VMLTMAPUSPD07"));
        assert_eq!(v.app_user.as_deref(), Some("ZWLATMTMS"));
        assert_eq!(v.object_name.as_deref(), Some("SAPHANADB:ADR2"));
        assert_eq!(v.lock_type.as_deref(), Some("RECORD_LOCK"));
        assert_eq!(v.stmt_hash.as_deref(), Some("259829e7fca4f2c336f63a2447378053"));
        assert!(v.statement.as_deref().unwrap().starts_with("UPDATE"));
        assert_eq!(r.top_objects[0].name, "SAPHANADB:ADR2");
        assert_eq!(r.top_objects[0].count, 1);
        assert_eq!(r.warnings[0].r#type, "hana_deadlocks_detected");
        assert_eq!(r.warnings[0].severity.as_deref(), Some("warning"));
    }

    #[test]
    fn escalates_many_deadlocks_to_error() {
        let mut input = String::new();
        for _ in 0..DEADLOCK_ERROR_COUNT {
            input.push_str(&deadlock_block(
                "2026-06-01 13:41:24.116632",
                "SAPHANADB:ADR2",
                "259829e7fca4f2c336f63a2447378053",
            ));
            input.push('\n');
        }
        let r = parse_hana_deadlocks(&input, ALERT_PATH);
        assert_eq!(r.count, DEADLOCK_ERROR_COUNT);
        assert_eq!(r.warnings[0].severity.as_deref(), Some("error"));
    }

    #[test]
    fn ignores_non_deadlock_lock_lines() {
        let input = "[123]{1}[1/1] 2026-06-01 13:41:24.116632 e Lock WaitGraph.cc(00250) : \n  Some other lock note";
        let r = parse_hana_deadlocks(input, ALERT_PATH);
        assert!(!r.found);
        assert_eq!(r.count, 0);
    }

    // ----- Out of memory -------------------------------------------------

    #[test]
    fn detects_oom_event() {
        let input = "[1335394]{-1}[-1/-1] 2026-06-04 17:32:51.297072 e Memory           mmReportMemoryProblems.cpp(02088) : OUT OF MEMORY occurred.\nMemoryType: NearDRAM\nHost: vmltmdbuspd01\nExecutable: hdbindexserver\nPID: 1312305\nFailed to allocate 64mb (67108864b).\nAllocation failure type: GLOBAL_ALLOCATION_LIMIT\nGLOBAL_ALLOCATION_LIMIT (GAL) = 3.62tb (3983937077248b), SHARED_MEMORY = 50.62gb (54358601728b)\n[1335395]{-1}[-1/-1] 2026-06-04 17:32:52.000000 i Logger Other.cpp(01) : next record";
        let r = parse_hana_oom(input, ALERT_PATH);
        assert!(r.found);
        assert_eq!(r.count, 1);
        let e = &r.events[0];
        assert_eq!(e.memory_type.as_deref(), Some("NearDRAM"));
        assert_eq!(e.host.as_deref(), Some("vmltmdbuspd01"));
        assert_eq!(e.executable.as_deref(), Some("hdbindexserver"));
        assert_eq!(e.pid.as_deref(), Some("1312305"));
        assert_eq!(e.failed_alloc_bytes, Some(67108864));
        assert_eq!(e.failure_type.as_deref(), Some("GLOBAL_ALLOCATION_LIMIT"));
        assert_eq!(e.global_allocation_limit_bytes, Some(3983937077248));
        assert_eq!(r.warnings[0].r#type, "hana_out_of_memory");
        assert_eq!(r.warnings[0].severity.as_deref(), Some("error"));
    }

    #[test]
    fn ignores_non_oom_memory_lines() {
        let input = "[1]{-1}[-1/-1] 2026-06-04 17:32:51.297072 i Memory mm.cpp(01) : routine memory note";
        let r = parse_hana_oom(input, ALERT_PATH);
        assert!(!r.found);
    }

    // ----- Merge / compression errors ------------------------------------

    #[test]
    fn detects_merge_token_exhaustion() {
        let input = "[2564393]{-1}[-1/9223372036854775806] 2026-06-04 22:06:50.349323 e delta_merge      CsTableMerge.cpp(02527) : Error in local merge: not enough merge tokens for delta merge or optimize compression : table = T31::SAPHANADB:/1DH/ML000000006 (t 551461), merge motivation = AutoMerge, rc = 2465";
        let r = parse_hana_merge_errors(input, ALERT_PATH);
        assert!(r.found);
        assert_eq!(r.count, 1);
        assert_eq!(r.merge_error_count, 1);
        assert_eq!(r.compression_error_count, 0);
        assert_eq!(r.token_exhaustion_count, 1);
        let e = &r.errors[0];
        assert_eq!(e.component, "delta_merge");
        assert_eq!(e.table.as_deref(), Some("T31::SAPHANADB:/1DH/ML000000006"));
        assert_eq!(e.table_id, Some(551461));
        assert_eq!(e.motivation.as_deref(), Some("AutoMerge"));
        assert_eq!(e.rc.as_deref(), Some("2465"));
        assert_eq!(r.top_tables[0].name, "T31::SAPHANADB:/1DH/ML000000006");
        assert_eq!(r.warnings[0].r#type, "hana_merge_failures");
        assert!(r.warnings[0].message.contains("2465"));
    }

    #[test]
    fn detects_optimize_compression_failure() {
        let input = "[2495755]{-1}[-1/-1] 2026-06-04 22:20:41.621698 e optimize_compres RedoMerge.cpp(02512) : Last concurrent optimize compression failed: table = T31::SAPHANADB:/1DH/ML00000000A (t 562676), container id = 0xfe5225497c, last savepoint pos = 3562287544226";
        let r = parse_hana_merge_errors(input, ALERT_PATH);
        assert_eq!(r.compression_error_count, 1);
        assert_eq!(r.merge_error_count, 0);
        assert_eq!(r.token_exhaustion_count, 0);
        assert_eq!(r.errors[0].component, "optimize_compres");
        assert_eq!(r.errors[0].table_id, Some(562676));
    }

    #[test]
    fn merge_json_wrapper_fills_source_path() {
        let input = "[1]{-1}[-1/1] 2026-06-04 22:06:50.349323 e delta_merge CsTableMerge.cpp(02527) : Error in local merge: not enough merge tokens : table = T31::SAPHANADB:FOO (t 1), merge motivation = AutoMerge, rc = 2465";
        let json = parse_hana_merge_errors_json(input, ALERT_PATH);
        assert!(json.contains("\"found\":true"));
        assert!(json.contains(ALERT_PATH));
    }
}
