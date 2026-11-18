use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FirewallWarning {
    pub kind: String,
    pub severity: String,
    pub message: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FirewalldInfo {
    pub detected: bool,
    pub running: bool,
    pub backend: Option<String>,
    pub zones: Option<String>,
    pub direct_rules: Option<String>,
    pub passthroughs: Option<String>,
    pub chains: Option<String>,
    pub log_denied: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TableRulesInfo {
    pub detected: bool,
    pub rules: Vec<String>,
    pub modules: Vec<String>,
    pub config: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NftablesInfo {
    pub detected: bool,
    pub ruleset: Option<String>,
    pub tables: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EbtablesInfo {
    pub detected: bool,
    pub config: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FirewallRulesResult {
    pub found: bool,
    pub firewalld: FirewalldInfo,
    pub iptables: TableRulesInfo,
    pub ip6tables: TableRulesInfo,
    pub ebtables: EbtablesInfo,
    pub nftables: NftablesInfo,
    pub active_firewall: String,
    pub warnings: Vec<FirewallWarning>,
    pub raw_sections: BTreeMap<String, String>,
    pub source_path: String,
}

/// Find the 1-based line number of the first line whose contents satisfy the
/// predicate. Returns None if no match.
fn find_line<F: Fn(&str) -> bool>(content: &str, predicate: F) -> Option<usize> {
    content
        .lines()
        .enumerate()
        .find(|(_, line)| predicate(line))
        .map(|(i, _)| i + 1)
}

pub fn parse_firewall_rules(content: &str, source_path: &str) -> FirewallRulesResult {
    let mut result = FirewallRulesResult {
        found: false,
        firewalld: FirewalldInfo {
            detected: false,
            running: false,
            backend: None,
            zones: None,
            direct_rules: None,
            passthroughs: None,
            chains: None,
            log_denied: None,
        },
        iptables: TableRulesInfo {
            detected: false,
            rules: Vec::new(),
            modules: Vec::new(),
            config: None,
        },
        ip6tables: TableRulesInfo {
            detected: false,
            rules: Vec::new(),
            modules: Vec::new(),
            config: None,
        },
        ebtables: EbtablesInfo {
            detected: false,
            config: None,
        },
        nftables: NftablesInfo {
            detected: false,
            ruleset: None,
            tables: None,
        },
        active_firewall: "none".to_string(),
        warnings: Vec::new(),
        raw_sections: BTreeMap::new(),
        source_path: source_path.to_string(),
    };

    let trimmed = content.trim();
    if trimmed.is_empty() {
        return result;
    }

    if trimmed.contains("firewalld")
        || trimmed.contains("firewall-cmd")
        || trimmed.contains("FirewallBackend")
    {
        // Avoid false positives where the only mention is in a comment header
        // (e.g. SCC `# rpm -V nftables-...` lines or rpm name strings).
        let has_real_firewalld_signal = crate::cached_regex!(r"(?im)^[^#].*\bfirewalld\b|firewall-cmd|^FirewallBackend\s*=|FirewallD is not running|Active:\s*(active|inactive)").is_match(trimmed);
        if has_real_firewalld_signal {
            result.firewalld.detected = true;
            result.found = true;
        }

        let active_re = crate::cached_regex!(r"(?im)Active:\s+active\s+\(running\)");
        let running_only_re = crate::cached_regex!(r"(?im)^running$");
        if active_re.is_match(trimmed) || running_only_re.is_match(trimmed) {
            result.firewalld.running = true;
        }
        let inactive_re = crate::cached_regex!(r"(?i)Active:\s+inactive|FirewallD is not running");
        if inactive_re.is_match(trimmed) {
            result.firewalld.running = false;
            let inactive_line = find_line(content, |line| inactive_re.is_match(line));
            result.warnings.push(FirewallWarning {
                kind: "firewalld_not_running".to_string(),
                severity: "warning".to_string(),
                message: "firewalld is not running".to_string(),
                source_path: source_path.to_string(),
                source_line: inactive_line,
                source_line_end: inactive_line,
            });
        }

        if let Some(caps) =
            crate::cached_regex!(r"(?m)^FirewallBackend\s*=\s*(.+)$").captures(trimmed)
        {
            result.firewalld.backend = caps.get(1).map(|m| m.as_str().trim().to_string());
        }
        if trimmed.contains("(active)") || trimmed.contains("services:") {
            result.firewalld.zones = Some(trimmed.to_string());
        }
        if trimmed.contains("--get-log-denied") {
            result.firewalld.log_denied = Some(trimmed.to_string());
        }
    }

    // Detect a real nftables ruleset – require an actual `table <fam> NAME {`
    // declaration, not just a stray substring (avoids false positives from
    // comment lines like `# /usr/sbin/nft list tables` or rpm names).
    let nft_table_re =
        crate::cached_regex!(r"(?m)^\s*table\s+(?:inet|ip|ip6|arp|bridge|netdev)\s+\S+\s*\{");
    let has_nft_table = nft_table_re.is_match(trimmed);
    if has_nft_table {
        result.nftables.detected = true;
        result.nftables.ruleset = Some(trimmed.to_string());
        result
            .raw_sections
            .insert("nft -a list ruleset".to_string(), trimmed.to_string());
        result.found = true;
    }

    if trimmed.contains("Chain INPUT") {
        result.iptables.detected = true;
        result.iptables.rules.push(trimmed.to_string());
        result.found = true;
    }
    // Capture missing-module notices regardless of whether rules were found.
    if let Some(caps) =
        crate::cached_regex!(r"The\s+(\S+)\s+module is not loaded").captures(trimmed)
    {
        if let Some(module) = caps.get(1).map(|m| m.as_str().to_string()) {
            result.iptables.modules.push(module);
        }
    }

    if trimmed.contains("ip6tables") || trimmed.contains("Chain FORWARD") && trimmed.contains("v6")
    {
        // Only mark detected if there are actual chains/rules, not just a comment header.
        if trimmed.contains("Chain ") {
            result.ip6tables.detected = true;
            result.ip6tables.rules.push(trimmed.to_string());
            result.found = true;
        }
    }

    if trimmed.contains("ebtables") {
        result.ebtables.detected = true;
        result.ebtables.config = Some(trimmed.to_string());
        result.found = true;
    }

    result.active_firewall = if result.firewalld.running {
        "firewalld".to_string()
    } else if result
        .nftables
        .ruleset
        .as_ref()
        .map(|s| !s.is_empty() && s != "(empty)")
        .unwrap_or(false)
    {
        "nftables".to_string()
    } else if !result.iptables.rules.is_empty() {
        "iptables".to_string()
    } else if !result.ip6tables.rules.is_empty() {
        "ip6tables".to_string()
    } else {
        "none".to_string()
    };

    result
}

pub fn parse_firewall_rules_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_firewall_rules(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

// =====================================================================
// Packet loss parser
//
// Extracts per-interface RX/TX byte/packet/error/dropped counters from
// `ip -stats link` (a.k.a. `ip -s link`) output that SCC supportconfigs
// capture in `network.txt`. Emits warnings when any error/dropped counter
// is non-zero so operators can spot lossy paths quickly.
// =====================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PacketLossWarning {
    pub kind: String,
    pub severity: String,
    pub interface: String,
    pub message: String,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InterfaceCounters {
    pub interface: String,
    pub rx_bytes: u64,
    pub rx_packets: u64,
    pub rx_errors: u64,
    pub rx_dropped: u64,
    pub rx_missed: u64,
    pub rx_mcast: u64,
    pub tx_bytes: u64,
    pub tx_packets: u64,
    pub tx_errors: u64,
    pub tx_dropped: u64,
    pub tx_carrier: u64,
    pub tx_collisions: u64,
    pub rx_drop_pct: f64,
    pub tx_drop_pct: f64,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PacketLossResult {
    pub found: bool,
    pub interfaces: Vec<InterfaceCounters>,
    pub warnings: Vec<PacketLossWarning>,
    pub source_path: String,
}

/// Parse seven non-negative integers separated by whitespace from `line`.
fn parse_counter_row(line: &str) -> Option<[u64; 7]> {
    let mut nums = [0u64; 7];
    let mut idx = 0usize;
    for tok in line.split_whitespace() {
        if let Ok(v) = tok.parse::<u64>() {
            if idx >= 7 {
                return None;
            }
            nums[idx] = v;
            idx += 1;
        } else {
            return None;
        }
    }
    // The `ip -s link` rows expose 6 columns under each header; some
    // newer iproute2 builds add a 7th totals column. Accept 6 or 7.
    if idx == 6 || idx == 7 {
        Some(nums)
    } else {
        None
    }
}

pub fn parse_packet_loss(content: &str, source_path: &str) -> PacketLossResult {
    let mut result = PacketLossResult {
        found: false,
        interfaces: Vec::new(),
        warnings: Vec::new(),
        source_path: source_path.to_string(),
    };

    if content.trim().is_empty() {
        return result;
    }

    // Match interface header lines like `2: eth0: <BROADCAST,...> mtu 1500 ...`
    let header_re = crate::cached_regex!(r"^\s*\d+:\s+([A-Za-z0-9._@-]+?):\s+<");
    let rx_hdr_re = crate::cached_regex!(r"^\s*RX:\s+bytes");
    let tx_hdr_re = crate::cached_regex!(r"^\s*TX:\s+bytes");

    let lines: Vec<&str> = content.lines().collect();
    let mut i = 0usize;
    while i < lines.len() {
        let line = lines[i];
        if let Some(caps) = header_re.captures(line) {
            let iface_name = caps
                .get(1)
                .map(|m| m.as_str().to_string())
                .unwrap_or_default();
            let header_line = i + 1;
            let mut rx: Option<[u64; 7]> = None;
            let mut tx: Option<[u64; 7]> = None;

            // Look ahead a few lines for RX:/TX: header + data row pairs.
            let mut j = i + 1;
            let mut steps = 0usize;
            while j < lines.len() && steps < 12 {
                if header_re.is_match(lines[j]) {
                    break;
                }
                if rx_hdr_re.is_match(lines[j]) && j + 1 < lines.len() {
                    if let Some(nums) = parse_counter_row(lines[j + 1]) {
                        rx = Some(nums);
                        j += 1;
                    }
                } else if tx_hdr_re.is_match(lines[j]) && j + 1 < lines.len() {
                    if let Some(nums) = parse_counter_row(lines[j + 1]) {
                        tx = Some(nums);
                        j += 1;
                    }
                }
                j += 1;
                steps += 1;
            }

            if rx.is_some() || tx.is_some() {
                let rx = rx.unwrap_or([0; 7]);
                let tx = tx.unwrap_or([0; 7]);
                let rx_pct = if rx[1] > 0 {
                    (rx[3] as f64) * 100.0 / (rx[1] as f64)
                } else {
                    0.0
                };
                let tx_pct = if tx[1] > 0 {
                    (tx[3] as f64) * 100.0 / (tx[1] as f64)
                } else {
                    0.0
                };

                let counters = InterfaceCounters {
                    interface: iface_name.clone(),
                    rx_bytes: rx[0],
                    rx_packets: rx[1],
                    rx_errors: rx[2],
                    rx_dropped: rx[3],
                    rx_missed: rx[4],
                    rx_mcast: rx[5],
                    tx_bytes: tx[0],
                    tx_packets: tx[1],
                    tx_errors: tx[2],
                    tx_dropped: tx[3],
                    tx_carrier: tx[4],
                    tx_collisions: tx[5],
                    rx_drop_pct: rx_pct,
                    tx_drop_pct: tx_pct,
                    source_line: Some(header_line),
                };

                // Skip loopback: noisy and rarely actionable.
                if iface_name != "lo" {
                    if counters.rx_errors > 0 {
                        result.warnings.push(PacketLossWarning {
                            kind: "rx_errors".to_string(),
                            severity: "warning".to_string(),
                            interface: iface_name.clone(),
                            message: format!(
                                "{}: {} RX errors detected (ip -s link)",
                                iface_name, counters.rx_errors
                            ),
                            source_path: source_path.to_string(),
                            source_line: Some(header_line),
                        });
                    }
                    if counters.tx_errors > 0 {
                        result.warnings.push(PacketLossWarning {
                            kind: "tx_errors".to_string(),
                            severity: "warning".to_string(),
                            interface: iface_name.clone(),
                            message: format!(
                                "{}: {} TX errors detected (ip -s link)",
                                iface_name, counters.tx_errors
                            ),
                            source_path: source_path.to_string(),
                            source_line: Some(header_line),
                        });
                    }
                    if counters.rx_dropped > 0 {
                        let sev = if rx_pct >= 0.1 { "warning" } else { "info" };
                        result.warnings.push(PacketLossWarning {
                            kind: "rx_dropped".to_string(),
                            severity: sev.to_string(),
                            interface: iface_name.clone(),
                            message: format!(
                                "{}: {} RX packets dropped ({:.4}% of {} received) — possible undersized RX ring buffer, busy NAPI, or qdisc backpressure",
                                iface_name, counters.rx_dropped, rx_pct, counters.rx_packets
                            ),
                            source_path: source_path.to_string(),
                            source_line: Some(header_line),
                        });
                    }
                    if counters.tx_dropped > 0 {
                        let sev = if tx_pct >= 0.1 { "warning" } else { "info" };
                        result.warnings.push(PacketLossWarning {
                            kind: "tx_dropped".to_string(),
                            severity: sev.to_string(),
                            interface: iface_name.clone(),
                            message: format!(
                                "{}: {} TX packets dropped ({:.4}% of {} sent) — possible undersized TX ring buffer or qdisc drops",
                                iface_name, counters.tx_dropped, tx_pct, counters.tx_packets
                            ),
                            source_path: source_path.to_string(),
                            source_line: Some(header_line),
                        });
                    }
                    if counters.rx_missed > 0 {
                        result.warnings.push(PacketLossWarning {
                            kind: "rx_missed".to_string(),
                            severity: "warning".to_string(),
                            interface: iface_name.clone(),
                            message: format!(
                                "{}: {} RX missed frames — NIC overran its FIFO; increase RX ring or interrupt coalescing",
                                iface_name, counters.rx_missed
                            ),
                            source_path: source_path.to_string(),
                            source_line: Some(header_line),
                        });
                    }
                }

                result.interfaces.push(counters);
                result.found = true;
                i = j;
                continue;
            }
        }
        i += 1;
    }

    result
}

pub fn parse_packet_loss_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_packet_loss(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

// =====================================================================
// Ring buffer (ethtool -g) parser
//
// Reads the `ethtool -g <iface>` output blocks present in SCC's
// `network.txt`. Warns when the current TX or RX ring is smaller than
// the hardware pre-set maximum because that ceiling is a common cause
// of TX/RX drops on busy Azure VMs.
// =====================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RingBufferWarning {
    pub kind: String,
    pub severity: String,
    pub interface: String,
    pub message: String,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RingBufferEntry {
    pub interface: String,
    pub rx_max: Option<u64>,
    pub rx_current: Option<u64>,
    pub tx_max: Option<u64>,
    pub tx_current: Option<u64>,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RingBufferResult {
    pub found: bool,
    pub entries: Vec<RingBufferEntry>,
    pub warnings: Vec<RingBufferWarning>,
    pub source_path: String,
}

fn parse_ring_value(line: &str) -> Option<u64> {
    let val = line.split(':').nth(1)?.trim();
    if val.eq_ignore_ascii_case("n/a") {
        return None;
    }
    val.split_whitespace().next()?.parse::<u64>().ok()
}

pub fn parse_ring_buffer(content: &str, source_path: &str) -> RingBufferResult {
    let mut result = RingBufferResult {
        found: false,
        entries: Vec::new(),
        warnings: Vec::new(),
        source_path: source_path.to_string(),
    };

    if content.trim().is_empty() {
        return result;
    }

    let header_re = crate::cached_regex!(r"^Ring parameters for (\S+):");
    let preset_re = crate::cached_regex!(r"(?i)^Pre-set maximums:");
    let current_re = crate::cached_regex!(r"(?i)^Current hardware settings:");
    let rx_re = crate::cached_regex!(r"^RX:\s");
    let tx_re = crate::cached_regex!(r"^TX:\s");

    let lines: Vec<&str> = content.lines().collect();
    let mut i = 0usize;
    while i < lines.len() {
        let line = lines[i].trim_end();
        if let Some(caps) = header_re.captures(line.trim_start()) {
            let iface = caps
                .get(1)
                .map(|m| m.as_str().to_string())
                .unwrap_or_default();
            let header_line = i + 1;
            let mut rx_max: Option<u64> = None;
            let mut tx_max: Option<u64> = None;
            let mut rx_cur: Option<u64> = None;
            let mut tx_cur: Option<u64> = None;
            let mut mode_current = false;

            let mut j = i + 1;
            // Inspect up to 20 lines or until we hit another command block.
            let mut steps = 0usize;
            while j < lines.len() && steps < 20 {
                let l = lines[j].trim_end();
                if l.starts_with("#==[") || header_re.is_match(l.trim_start()) {
                    break;
                }
                if preset_re.is_match(l) {
                    mode_current = false;
                } else if current_re.is_match(l) {
                    mode_current = true;
                } else if rx_re.is_match(l) {
                    let v = parse_ring_value(l);
                    if mode_current {
                        rx_cur = v;
                    } else {
                        rx_max = v;
                    }
                } else if tx_re.is_match(l) {
                    let v = parse_ring_value(l);
                    if mode_current {
                        tx_cur = v;
                    } else {
                        tx_max = v;
                    }
                }
                j += 1;
                steps += 1;
            }

            let entry = RingBufferEntry {
                interface: iface.clone(),
                rx_max,
                rx_current: rx_cur,
                tx_max,
                tx_current: tx_cur,
                source_line: Some(header_line),
            };

            if iface != "lo" {
                if let (Some(cur), Some(max)) = (tx_cur, tx_max) {
                    if cur < max {
                        let pct = (cur as f64) * 100.0 / (max as f64);
                        let sev = if pct < 50.0 { "warning" } else { "info" };
                        result.warnings.push(RingBufferWarning {
                            kind: "tx_ring_below_max".to_string(),
                            severity: sev.to_string(),
                            interface: iface.clone(),
                            message: format!(
                                "{}: TX ring buffer is {} (hardware max {}, {:.1}% of max) — increase with `ethtool -G {} tx {}` to reduce TX drops under load",
                                iface, cur, max, pct, iface, max
                            ),
                            source_path: source_path.to_string(),
                            source_line: Some(header_line),
                        });
                    }
                }
                if let (Some(cur), Some(max)) = (rx_cur, rx_max) {
                    if cur < max {
                        let pct = (cur as f64) * 100.0 / (max as f64);
                        let sev = if pct < 50.0 { "warning" } else { "info" };
                        result.warnings.push(RingBufferWarning {
                            kind: "rx_ring_below_max".to_string(),
                            severity: sev.to_string(),
                            interface: iface.clone(),
                            message: format!(
                                "{}: RX ring buffer is {} (hardware max {}, {:.1}% of max) — increase with `ethtool -G {} rx {}` to reduce RX drops",
                                iface, cur, max, pct, iface, max
                            ),
                            source_path: source_path.to_string(),
                            source_line: Some(header_line),
                        });
                    }
                }
            }

            result.entries.push(entry);
            result.found = true;
            i = j;
            continue;
        }
        i += 1;
    }

    result
}

pub fn parse_ring_buffer_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_ring_buffer(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

// =====================================================================
// Network sysctl tuning parser
//
// Scans sysctl key=value content (env.txt / sysctl-a.txt / sysctl.conf)
// for tuning knobs that affect networking performance. Today it
// specifically flags `net.ipv4.conf.<scope>.rp_filter` values other
// than 0 because strict reverse-path filtering causes the kernel to
// drop packets on Azure VMs with asymmetric routing or multi-NIC
// configurations, which the user reported as a hot point.
// =====================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SysctlWarning {
    pub kind: String,
    pub severity: String,
    pub key: String,
    pub value: String,
    pub message: String,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SysctlEntry {
    pub key: String,
    pub value: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NetworkSysctlResult {
    pub found: bool,
    /// Captured rp_filter values keyed by sysctl name (preserved verbatim).
    pub rp_filter: Vec<SysctlEntry>,
    pub warnings: Vec<SysctlWarning>,
    pub source_path: String,
}

pub fn parse_network_sysctl(content: &str, source_path: &str) -> NetworkSysctlResult {
    let mut result = NetworkSysctlResult {
        found: false,
        rp_filter: Vec::new(),
        warnings: Vec::new(),
        source_path: source_path.to_string(),
    };

    if content.trim().is_empty() {
        return result;
    }

    // Matches both `sysctl -a` style (`net.ipv4.conf.all.rp_filter = 2`)
    // and `/etc/sysctl.conf` entries. Ignores commented-out lines.
    let kv_re =
        crate::cached_regex!(r"^\s*(net\.ipv4\.conf\.[A-Za-z0-9._-]+\.rp_filter)\s*=\s*(\S+)");

    for (idx, raw) in content.lines().enumerate() {
        let line = raw;
        // Skip comments.
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') || trimmed.starts_with(';') {
            continue;
        }
        if let Some(caps) = kv_re.captures(line) {
            let key = caps
                .get(1)
                .map(|m| m.as_str().to_string())
                .unwrap_or_default();
            let value = caps
                .get(2)
                .map(|m| m.as_str().to_string())
                .unwrap_or_default();
            let lineno = Some(idx + 1);
            result.found = true;

            // De-duplicate (sysctl -a + sysctl.conf can both appear).
            let already_seen = result
                .rp_filter
                .iter()
                .any(|e| e.key == key && e.value == value);
            if !already_seen {
                result.rp_filter.push(SysctlEntry {
                    key: key.clone(),
                    value: value.clone(),
                    source_line: lineno,
                });
            }

            // Only emit one warning per key — avoids duplicates when the
            // same setting is captured by both sysctl.conf and `sysctl -a`.
            if already_seen {
                continue;
            }

            // Only `all` and per-interface scopes actually take effect on
            // received packets. `default` only seeds new interfaces, so
            // its value matters less; still surface it as info.
            let is_default_scope = key.contains(".default.");

            let v: i64 = value.parse().unwrap_or(-1);
            if v == 1 {
                let sev = if is_default_scope { "info" } else { "warning" };
                result.warnings.push(SysctlWarning {
                    kind: "rp_filter_strict".to_string(),
                    severity: sev.to_string(),
                    key: key.clone(),
                    value: value.clone(),
                    message: format!(
                        "{} = 1 (strict reverse-path filter) — drops asymmetrically-routed packets, hurting throughput on multi-NIC/accelerated-networking Azure VMs. Consider setting to 0 or 2 (loose).",
                        key
                    ),
                    source_path: source_path.to_string(),
                    source_line: lineno,
                });
            } else if v == 2 {
                let sev = if is_default_scope { "info" } else { "warning" };
                result.warnings.push(SysctlWarning {
                    kind: "rp_filter_loose".to_string(),
                    severity: sev.to_string(),
                    key: key.clone(),
                    value: value.clone(),
                    message: format!(
                        "{} = 2 (loose reverse-path filter) — still performs an extra route lookup per ingress packet and can drop legitimate traffic with multi-NIC or BGP. Set to 0 for maximum performance unless you specifically need anti-spoof filtering.",
                        key
                    ),
                    source_path: source_path.to_string(),
                    source_line: lineno,
                });
            }
        }
    }

    result
}

pub fn parse_network_sysctl_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_network_sysctl(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PATH: &str = "sos_commands/firewalld/firewall-cmd_--list-all-zones";

    #[test]
    fn detects_running_firewalld_and_backend() {
        let input = concat!(
            "# /usr/bin/systemctl status firewalld\n",
            "Active: active (running)\n",
            "# /usr/bin/firewall-cmd --list-all\n",
            "public (active)\n  services: ssh dhcpv6-client\n",
            "FirewallBackend=nftables\n"
        );
        let result = parse_firewall_rules(input, PATH);
        assert!(result.found);
        assert!(result.firewalld.detected);
        assert!(result.firewalld.running);
        assert_eq!(result.active_firewall, "firewalld");
    }

    #[test]
    fn detects_nftables_when_ruleset_present() {
        let input = "table inet filter { chain input { type filter hook input priority 0; policy accept; } }";
        let result = parse_firewall_rules(input, PATH);
        assert!(result.found);
        assert!(result.nftables.detected);
        assert_eq!(result.active_firewall, "nftables");
    }

    #[test]
    fn firewall_warnings_carry_source_provenance() {
        let input = concat!(
            "# /usr/bin/systemctl status firewalld\n",
            "Loaded: loaded\n",
            "Active: inactive (dead)\n",
            "FirewallBackend=nftables\n"
        );
        let result = parse_firewall_rules(input, PATH);
        assert_eq!(result.source_path, PATH);
        assert!(!result.warnings.is_empty());
        let w = result
            .warnings
            .iter()
            .find(|w| w.kind == "firewalld_not_running")
            .expect("warn");
        assert_eq!(w.source_path, PATH);
        assert_eq!(w.source_line, Some(3));
    }

    #[test]
    fn firewall_json_wrapper_includes_source_path() {
        let input = "FirewallD is not running\n";
        let json = parse_firewall_rules_json(input, PATH);
        assert!(json
            .contains("\"source_path\":\"sos_commands/firewalld/firewall-cmd_--list-all-zones\""));
    }

    // ---- packet loss ----

    const NET_PATH: &str = "network.txt";

    #[test]
    fn parses_ip_s_link_counters_and_drops() {
        let input = concat!(
            "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\n",
            "    link/ether 00:0d:3a:b8:55:bc brd ff:ff:ff:ff:ff:ff\n",
            "    RX:       bytes      packets errors dropped  missed   mcast\n",
            "    576576306456948 432918471203      0       0       0       0\n",
            "    TX:       bytes      packets errors dropped carrier collsns\n",
            "     29491879217412  81596197830      0     177       0       0\n",
            "4: eth1: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 1500 qdisc mq master eth0 state UP\n",
            "    link/ether 00:0d:3a:b8:55:bc brd ff:ff:ff:ff:ff:ff\n",
            "    RX:       bytes      packets errors  dropped  missed   mcast\n",
            "    362585752455288 273876533041      0 85686896       0       0\n",
            "    TX:       bytes      packets errors  dropped carrier collsns\n",
            "     25742405933943  68373850463      0        0       0       0\n",
        );
        let r = parse_packet_loss(input, NET_PATH);
        assert!(r.found);
        assert_eq!(r.interfaces.len(), 2);
        let eth0 = r.interfaces.iter().find(|i| i.interface == "eth0").unwrap();
        assert_eq!(eth0.tx_dropped, 177);
        assert_eq!(eth0.rx_dropped, 0);
        let eth1 = r.interfaces.iter().find(|i| i.interface == "eth1").unwrap();
        assert_eq!(eth1.rx_dropped, 85_686_896);
        assert!(r
            .warnings
            .iter()
            .any(|w| w.kind == "rx_dropped" && w.interface == "eth1"));
        assert!(r
            .warnings
            .iter()
            .any(|w| w.kind == "tx_dropped" && w.interface == "eth0"));
    }

    #[test]
    fn packet_loss_ignores_loopback_warnings() {
        let input = concat!(
            "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN\n",
            "    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00\n",
            "    RX:    bytes    packets errors dropped  missed   mcast\n",
            "    100 10 0 5 0 0\n",
            "    TX:    bytes    packets errors dropped carrier collsns\n",
            "    100 10 0 0 0 0\n",
        );
        let r = parse_packet_loss(input, NET_PATH);
        assert_eq!(r.interfaces.len(), 1);
        assert!(r.warnings.is_empty(), "loopback drops should not warn");
    }

    // ---- ring buffer ----

    #[test]
    fn parses_ethtool_g_blocks_and_flags_undersize() {
        let input = concat!(
            "Ring parameters for eth0:\n",
            "Pre-set maximums:\n",
            "RX:             18139\n",
            "RX Mini:        n/a\n",
            "RX Jumbo:       n/a\n",
            "TX:             2560\n",
            "Current hardware settings:\n",
            "RX:             9362\n",
            "RX Mini:        n/a\n",
            "RX Jumbo:       n/a\n",
            "TX:             170\n",
            "\n",
            "Ring parameters for eth1:\n",
            "Pre-set maximums:\n",
            "RX:             8192\n",
            "TX:             8192\n",
            "Current hardware settings:\n",
            "RX:             8192\n",
            "TX:             8192\n",
        );
        let r = parse_ring_buffer(input, NET_PATH);
        assert!(r.found);
        assert_eq!(r.entries.len(), 2);
        let eth0 = r.entries.iter().find(|e| e.interface == "eth0").unwrap();
        assert_eq!(eth0.tx_max, Some(2560));
        assert_eq!(eth0.tx_current, Some(170));
        // eth0 should produce both rx and tx undersize warnings
        assert!(r
            .warnings
            .iter()
            .any(|w| w.kind == "tx_ring_below_max" && w.interface == "eth0"));
        assert!(r
            .warnings
            .iter()
            .any(|w| w.kind == "rx_ring_below_max" && w.interface == "eth0"));
        // eth1 is at max → no warnings
        assert!(!r.warnings.iter().any(|w| w.interface == "eth1"));
    }

    // ---- rp_filter ----

    #[test]
    fn flags_rp_filter_strict_and_loose() {
        let input = concat!(
            "net.ipv4.conf.all.rp_filter = 2\n",
            "net.ipv4.conf.default.rp_filter = 0\n",
            "net.ipv4.conf.eth0.rp_filter = 1\n",
            "net.ipv4.conf.eth1.rp_filter = 0\n",
            "# net.ipv4.conf.lo.rp_filter = 9\n",
        );
        let r = parse_network_sysctl(input, "env.txt");
        assert!(r.found);
        assert_eq!(r.rp_filter.len(), 4, "comment line must be ignored");
        let loose = r
            .warnings
            .iter()
            .find(|w| w.key == "net.ipv4.conf.all.rp_filter")
            .unwrap();
        assert_eq!(loose.kind, "rp_filter_loose");
        assert_eq!(loose.severity, "warning");
        let strict = r
            .warnings
            .iter()
            .find(|w| w.key == "net.ipv4.conf.eth0.rp_filter")
            .unwrap();
        assert_eq!(strict.kind, "rp_filter_strict");
        // zero values must not warn
        assert!(!r
            .warnings
            .iter()
            .any(|w| w.key == "net.ipv4.conf.eth1.rp_filter"));
        assert!(!r
            .warnings
            .iter()
            .any(|w| w.key == "net.ipv4.conf.default.rp_filter"));
    }

    // ---------------------------------------------------------------
    // Negative / false-positive coverage
    //
    // Each parser may be dispatched against any `network.txt` (and
    // sometimes adjacent files) by the worker.  These tests prove that
    // when the input does NOT contain the signals the parser is
    // looking for, the parser returns `found = false` and emits no
    // warnings — so the UI never renders a section with bogus data.
    // ---------------------------------------------------------------

    #[test]
    fn packet_loss_returns_empty_on_unrelated_content() {
        // ethtool / ip route / random text — no `ip -s link` stat block.
        let input = concat!(
            "default via 10.0.0.1 dev eth0\n",
            "10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.4\n",
            "ring parameters discussion in the documentation\n",
            "RX: this is a sentence about RX, not a counter row\n",
        );
        let r = parse_packet_loss(input, NET_PATH);
        assert!(!r.found, "no ip -s link blocks → not found");
        assert!(r.interfaces.is_empty());
        assert!(r.warnings.is_empty());
    }

    #[test]
    fn packet_loss_returns_empty_on_ring_buffer_content() {
        // Confirm that cross-feeding `ethtool -g` output does not
        // trigger the packet-loss parser.
        let input = concat!(
            "Ring parameters for eth0:\n",
            "Pre-set maximums:\n",
            "RX:             2560\n",
            "TX:             2560\n",
            "Current hardware settings:\n",
            "RX:             1024\n",
            "TX:             170\n",
        );
        let r = parse_packet_loss(input, NET_PATH);
        assert!(!r.found);
        assert!(r.interfaces.is_empty());
    }

    #[test]
    fn packet_loss_ignores_zero_drop_interfaces() {
        // Has valid counters but every error/dropped is 0 — `found`
        // is true (we did parse data) but NO warnings must fire.
        let input = concat!(
            "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n",
            "    link/ether 00:0d:3a:b8:55:bc brd ff:ff:ff:ff:ff:ff\n",
            "    RX:       bytes      packets errors dropped  missed   mcast\n",
            "             12345           67      0       0       0       0\n",
            "    TX:       bytes      packets errors dropped carrier collsns\n",
            "             54321           89      0       0       0       0\n",
        );
        let r = parse_packet_loss(input, NET_PATH);
        assert!(r.found);
        assert_eq!(r.interfaces.len(), 1);
        assert!(
            r.warnings.is_empty(),
            "zero error/drop counters must not emit warnings: {:?}",
            r.warnings
        );
    }

    #[test]
    fn ring_buffer_returns_empty_on_unrelated_content() {
        // ip link output + ethtool -i / -k — no `Ring parameters for`.
        let input = concat!(
            "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n",
            "    link/ether 00:0d:3a:b8:55:bc brd ff:ff:ff:ff:ff:ff\n",
            "driver: hv_netvsc\n",
            "version: 5.14.21\n",
            "Features for eth0:\n",
            "rx-checksumming: on\n",
            "tx-checksumming: on\n",
        );
        let r = parse_ring_buffer(input, NET_PATH);
        assert!(!r.found, "no ethtool -g blocks → not found");
        assert!(r.entries.is_empty());
        assert!(r.warnings.is_empty());
    }

    #[test]
    fn ring_buffer_no_warning_when_current_equals_preset() {
        // Ring buffers maxed out — `found` true, but no undersize warning.
        let input = concat!(
            "Ring parameters for eth0:\n",
            "Pre-set maximums:\n",
            "RX:             2048\n",
            "TX:             2048\n",
            "Current hardware settings:\n",
            "RX:             2048\n",
            "TX:             2048\n",
        );
        let r = parse_ring_buffer(input, NET_PATH);
        assert!(r.found);
        assert_eq!(r.entries.len(), 1);
        assert!(
            r.warnings.is_empty(),
            "current == preset must not warn: {:?}",
            r.warnings
        );
    }

    #[test]
    fn network_sysctl_returns_empty_on_unrelated_content() {
        // Contains other sysctl keys, plus an `arp_filter` red-herring,
        // plus a commented rp_filter line — none must match.
        let input = concat!(
            "# /usr/bin/sysctl -a\n",
            "net.ipv4.conf.all.arp_filter = 1\n",
            "net.ipv4.conf.all.accept_source_route = 0\n",
            "net.core.rmem_max = 212992\n",
            "# net.ipv4.conf.all.rp_filter = 2 (commented out)\n",
            "kernel.hostname = host01\n",
        );
        let r = parse_network_sysctl(input, "etc/sysctl.conf");
        assert!(!r.found, "no live rp_filter key → not found");
        assert!(r.rp_filter.is_empty());
        assert!(r.warnings.is_empty());
    }

    #[test]
    fn network_sysctl_no_warning_when_rp_filter_disabled() {
        // rp_filter=0 is neither strict (1) nor loose (2) → no warning.
        let input = concat!(
            "net.ipv4.conf.all.rp_filter = 0\n",
            "net.ipv4.conf.default.rp_filter = 0\n",
            "net.ipv4.conf.eth0.rp_filter = 0\n",
        );
        let r = parse_network_sysctl(input, "etc/sysctl.conf");
        assert!(r.found);
        assert_eq!(r.rp_filter.len(), 3);
        assert!(
            r.warnings.is_empty(),
            "rp_filter=0 must not warn: {:?}",
            r.warnings
        );
    }

    #[test]
    fn parsers_return_empty_on_empty_input() {
        assert!(!parse_packet_loss("", NET_PATH).found);
        assert!(!parse_ring_buffer("", NET_PATH).found);
        assert!(!parse_network_sysctl("", "etc/sysctl.conf").found);
    }

    #[test]
    fn firewall_returns_empty_on_unrelated_content() {
        // Existing firewall parser should also reject random text.
        let r = parse_firewall_rules("this is not a firewall configuration\njust prose\n", PATH);
        assert!(!r.found);
        assert_eq!(r.active_firewall, "none");
        assert!(r.warnings.is_empty());
    }
}
