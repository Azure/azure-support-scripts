use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ParserWarning {
    pub kind: String,
    pub severity: String,
    pub message: String,
    pub parameter: Option<String>,
    pub expected: Option<String>,
    pub actual: Option<String>,
    pub recommendation: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CorosyncConfigResult {
    pub found: bool,
    pub totem_token: Option<i64>,
    pub totem_retransmits: Option<i64>,
    pub totem_join: Option<i64>,
    pub totem_consensus: Option<i64>,
    pub totem_max_messages: Option<i64>,
    pub totem_transport: Option<String>,
    pub quorum_provider: Option<String>,
    pub quorum_expected_votes: Option<i64>,
    pub quorum_two_node: Option<i64>,
    pub warnings: Vec<ParserWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClusterNodeStatus {
    pub name: String,
    pub status: String,
    pub online: bool,
    pub is_dc: bool,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClusterStatusResult {
    pub found: bool,
    pub cluster_name: Option<String>,
    pub dc_node: Option<String>,
    pub nodes_configured: Option<i64>,
    pub resources_configured: Option<i64>,
    pub last_updated: Option<String>,
    pub quorum_status: Option<String>,
    pub node_statuses: Vec<ClusterNodeStatus>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HighCpuEvent {
    pub timestamp: String,
    pub source_node: String,
    pub resource: String,
    pub cpu_load: f64,
    pub severity: String,
    pub action: String,
    pub raw_line: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ResourceMigrationEvent {
    pub timestamp: Option<String>,
    pub resource: String,
    pub from_node: Option<String>,
    pub to_node: Option<String>,
    pub action: String,
    pub severity: Option<String>,
    pub cpu_load: Option<f64>,
    pub error: Option<String>,
    pub raw_line: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FencingEvent {
    pub timestamp: Option<String>,
    pub target_node: String,
    pub action: String,
    pub status: String,
    pub agent: Option<String>,
    pub raw_line: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClusterEventsResult {
    pub found: bool,
    pub resource_migrations: Vec<ResourceMigrationEvent>,
    pub fencing_events: Vec<FencingEvent>,
    pub total_events: usize,
    pub count: usize,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClusterMaintenanceResult {
    pub found: bool,
    pub maintenance_mode: Option<bool>,
    pub resources_in_maintenance: Vec<String>,
    pub warnings: Vec<ParserWarning>,
    pub source_path: String,
}

#[allow(clippy::too_many_arguments)]
fn make_warning(
    kind: &str,
    severity: &str,
    message: String,
    parameter: Option<&str>,
    expected: Option<String>,
    actual: Option<String>,
    recommendation: Option<&str>,
    source_path: &str,
    source_line: Option<usize>,
) -> ParserWarning {
    ParserWarning {
        kind: kind.to_string(),
        severity: severity.to_string(),
        message,
        parameter: parameter.map(|s| s.to_string()),
        expected,
        actual,
        recommendation: recommendation.map(|s| s.to_string()),
        source_path: source_path.to_string(),
        source_line,
        source_line_end: source_line,
    }
}

fn parse_syslog_prefix(line: &str) -> (Option<String>, Option<String>, String) {
    use std::sync::OnceLock;
    static ISO_RE: OnceLock<Regex> = OnceLock::new();
    static SYSLOG_RE: OnceLock<Regex> = OnceLock::new();
    static SYSLOG_PARTS_RE: OnceLock<Regex> = OnceLock::new();

    let iso_re = ISO_RE.get_or_init(|| {
        Regex::new(r"^(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)").unwrap()
    });
    let syslog_re = SYSLOG_RE.get_or_init(|| {
        Regex::new(r"^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)").unwrap()
    });
    let syslog_parts_re = SYSLOG_PARTS_RE.get_or_init(|| {
        Regex::new(r"^\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?\s+(\S+)\s+.+?:\s*(.+)$").unwrap()
    });

    let timestamp = iso_re
        .captures(line)
        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
        .or_else(|| {
            syslog_re
                .captures(line)
                .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
        });

    if let Some(caps) = syslog_parts_re.captures(line) {
        let node = caps.get(1).map(|m| m.as_str().to_string());
        let message = caps
            .get(2)
            .map(|m| m.as_str().to_string())
            .unwrap_or_else(|| line.trim().to_string());
        (timestamp, node, message)
    } else {
        (timestamp, None, line.trim().to_string())
    }
}

fn is_systemd_resource(resource: &str) -> bool {
    let lower = resource.to_ascii_lowercase();
    lower.ends_with(".service")
        || lower.ends_with(".target")
        || lower.ends_with(".socket")
        || lower.ends_with(".mount")
        || lower.ends_with(".swap")
        || lower.ends_with(".path")
        || lower.ends_with(".timer")
        || lower.ends_with(".device")
        || lower.ends_with(".scope")
        || lower.ends_with(".slice")
        || resource.contains('@')
}

fn is_system_resource(resource: &str) -> bool {
    use std::sync::OnceLock;
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"^(?i)(Getty|Login|Console|Session|User|Seat|agetty|mingetty|mgetty|plymouth|systemd-|dbus|polkit|NetworkManager|ModemManager|firewalld|sshd|crond?|rsyslog|auditd|chronyd?|ntpd?)$")
            .unwrap()
    })
    .is_match(resource)
}

fn is_non_cluster_node(node: &str) -> bool {
    use std::sync::OnceLock;
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"^(?i)(tty\d*[\.\-]?\d*|tty\d*\.{3}|pts/?\d*|console|localhost|127\.0\.0\.1|::1|\d+|port|ports?|socket|sockets?)\.{0,3}$").unwrap()
    })
    .is_match(node)
}

/// Returns true if the line clearly originates from a Pacemaker / Corosync /
/// SBD / pcsd-related process (used to filter out unrelated systemd / app
/// messages that happen to mention "Starting" or "Stopping").
fn is_cluster_log_source(line: &str) -> bool {
    use std::sync::OnceLock;
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(?i)\b(pacemaker(?:-[a-z]+)?|corosync|pcsd|sbd|crmd|lrmd|pengine|attrd|cib|stonith(?:-ng|d)?|fenced|booth|crm_resource|crm_mon|crm_node|crm_attribute)\b").unwrap()
    })
    .is_match(line)
}

// ---------------------------------------------------------------------------
// Corosync config
// ---------------------------------------------------------------------------

pub fn parse_corosync_config(content: &str, source_path: &str) -> CorosyncConfigResult {
    let mut result = CorosyncConfigResult {
        found: false,
        totem_token: None,
        totem_retransmits: None,
        totem_join: None,
        totem_consensus: None,
        totem_max_messages: None,
        totem_transport: None,
        quorum_provider: None,
        quorum_expected_votes: None,
        quorum_two_node: None,
        warnings: Vec::new(),
        source_path: source_path.to_string(),
    };

    // Track which line each value came from so warnings can point at the
    // offending statement in the original file.
    let mut lines_for: std::collections::HashMap<&'static str, usize> =
        std::collections::HashMap::new();

    let mut in_totem = false;
    let mut in_quorum = false;
    let mut totem_depth = 0i32;
    let mut quorum_depth = 0i32;

    for (idx, raw_line) in content.lines().enumerate() {
        let line_no = idx + 1;
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }

        if !in_totem && line.starts_with("totem") {
            in_totem = true;
            result.found = true;
        }
        if !in_quorum && line.starts_with("quorum") {
            in_quorum = true;
            result.found = true;
        }

        if in_totem {
            totem_depth += line.matches('{').count() as i32;
            totem_depth -= line.matches('}').count() as i32;

            if let Some(v) = crate::cached_regex!(r"^token\s*:\s*(\d+)").captures(line) {
                result.totem_token = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.token", line_no);
            }
            if let Some(v) = crate::cached_regex!(r"^token_retransmits_before_loss_const\s*:\s*(\d+)").captures(line) {
                result.totem_retransmits = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.token_retransmits_before_loss_const", line_no);
            }
            if let Some(v) = crate::cached_regex!(r"^join\s*:\s*(\d+)").captures(line) {
                result.totem_join = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.join", line_no);
            }
            if let Some(v) = crate::cached_regex!(r"^consensus\s*:\s*(\d+)").captures(line) {
                result.totem_consensus = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.consensus", line_no);
            }
            if let Some(v) = crate::cached_regex!(r"^max_messages\s*:\s*(\d+)").captures(line) {
                result.totem_max_messages = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.max_messages", line_no);
            }
            if let Some(v) = crate::cached_regex!(r"^transport\s*:\s*(\w+)").captures(line) {
                result.totem_transport = v.get(1).map(|m| m.as_str().to_string());
                lines_for.insert("totem.transport", line_no);
            }

            if totem_depth == 0 && line.contains('}') {
                in_totem = false;
            }
        }

        if in_quorum {
            quorum_depth += line.matches('{').count() as i32;
            quorum_depth -= line.matches('}').count() as i32;

            if let Some(v) = crate::cached_regex!(r"^provider\s*:\s*(\w+)").captures(line) {
                result.quorum_provider = v.get(1).map(|m| m.as_str().to_string());
                lines_for.insert("quorum.provider", line_no);
            }
            if let Some(v) = crate::cached_regex!(r"^expected_votes\s*:\s*(\d+)").captures(line) {
                result.quorum_expected_votes = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("quorum.expected_votes", line_no);
            }
            if let Some(v) = crate::cached_regex!(r"^two_node\s*:\s*(\d+)").captures(line) {
                result.quorum_two_node = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("quorum.two_node", line_no);
            }

            if quorum_depth == 0 && line.contains('}') {
                in_quorum = false;
            }
        }
    }

    let checks: [(&'static str, Option<String>, Option<String>); 9] = [
        ("totem.token", result.totem_token.map(|v| v.to_string()), Some("30000".to_string())),
        ("totem.token_retransmits_before_loss_const", result.totem_retransmits.map(|v| v.to_string()), Some("10".to_string())),
        ("totem.join", result.totem_join.map(|v| v.to_string()), Some("60".to_string())),
        ("totem.consensus", result.totem_consensus.map(|v| v.to_string()), Some("36000".to_string())),
        ("totem.max_messages", result.totem_max_messages.map(|v| v.to_string()), Some("20".to_string())),
        ("totem.transport", result.totem_transport.clone(), Some("udpu".to_string())),
        ("quorum.provider", result.quorum_provider.clone(), Some("corosync_votequorum".to_string())),
        ("quorum.expected_votes", result.quorum_expected_votes.map(|v| v.to_string()), Some("2".to_string())),
        ("quorum.two_node", result.quorum_two_node.map(|v| v.to_string()), Some("1".to_string())),
    ];

    for (parameter, actual, expected) in checks {
        if let (Some(actual_value), Some(expected_value)) = (actual, expected) {
            if actual_value != expected_value {
                let line_no = lines_for.get(parameter).copied();
                result.warnings.push(make_warning(
                    "config_mismatch",
                    "warning",
                    format!("{} is {}, but should be {} for Azure environments", parameter, actual_value, expected_value),
                    Some(parameter),
                    Some(expected_value),
                    Some(actual_value),
                    None,
                    source_path,
                    line_no,
                ));
            }
        }
    }

    result
}

// ---------------------------------------------------------------------------
// Cluster status (cib.xml / crm_mon text)
// ---------------------------------------------------------------------------

pub fn parse_cluster_status(content: &str, source_path: &str) -> ClusterStatusResult {
    let mut result = ClusterStatusResult {
        found: false,
        cluster_name: None,
        dc_node: None,
        nodes_configured: None,
        resources_configured: None,
        last_updated: None,
        quorum_status: None,
        node_statuses: Vec::new(),
        source_path: source_path.to_string(),
    };

    let mut seen = HashSet::new();

    if let Some(caps) = crate::cached_regex!(r#"name=["']cluster-name["']\s+value=["']([^"']+)["']"#).captures(content) {
        result.cluster_name = caps.get(1).map(|m| m.as_str().to_string());
        result.found = true;
    }
    if let Some(caps) = crate::cached_regex!(r#"have-quorum=["']([01])["']"#).captures(content) {
        result.quorum_status = Some(if caps.get(1).map(|m| m.as_str()) == Some("1") {
            "with quorum".to_string()
        } else {
            "without quorum".to_string()
        });
        result.found = true;
    }
    if let Some(caps) = crate::cached_regex!(r#"<current_dc[^>]+(?:name|uname)=["']([^"']+)["'][^>]*with_quorum=["'](true|false)["']"#).captures(content) {
        result.dc_node = caps.get(1).map(|m| m.as_str().to_string());
        result.quorum_status = Some(if caps.get(2).map(|m| m.as_str()) == Some("true") {
            "with quorum".to_string()
        } else {
            "without quorum".to_string()
        });
        result.found = true;
    }

    let cluster_name_re = crate::cached_regex!(r"(?i)^Cluster name:\s+(.+)$");
    let stack_re = crate::cached_regex!(r"(?i)^Stack:\s+(\w+)");
    let dc_re = crate::cached_regex!(r"(?i)^Current DC:\s+([^\s]+)");
    let last_re = crate::cached_regex!(r"(?i)^Last updated:\s+(.+)$");
    let nodes_cfg_re = crate::cached_regex!(r"(?i)(\d+)\s+nodes?\s+configured");
    let res_cfg_re = crate::cached_regex!(r"(?i)(\d+)\s+resource(?:\s+instances?)?\s+configured");
    let online_re = crate::cached_regex!(r"(?i)Online:\s*\[\s*([^\]]+)\s*\]");
    let offline_re = crate::cached_regex!(r"(?i)Offline:\s*\[\s*([^\]]+)\s*\]");
    let node_re = crate::cached_regex!(r"(?i)\*?\s*Node\s+([^\s:]+)[^:]*:\s*(\w+)");

    for (idx, line) in content.lines().enumerate() {
        let line_no = idx + 1;
        let trimmed = line.trim();

        if let Some(caps) = cluster_name_re.captures(trimmed) {
            if result.cluster_name.is_none() {
                result.cluster_name = caps.get(1).map(|m| m.as_str().trim().to_string());
            }
            result.found = true;
        }
        if let Some(caps) = stack_re.captures(trimmed) {
            if result.cluster_name.is_none() {
                result.cluster_name = caps.get(1).map(|m| m.as_str().trim().to_string());
            }
            result.found = true;
        }
        if let Some(caps) = dc_re.captures(trimmed) {
            if result.dc_node.is_none() {
                result.dc_node = caps.get(1).map(|m| m.as_str().trim().to_string());
            }
            result.found = true;
        }
        if let Some(caps) = last_re.captures(trimmed) {
            if result.last_updated.is_none() {
                result.last_updated = caps.get(1).map(|m| m.as_str().trim().to_string());
            }
            result.found = true;
        }
        if let Some(caps) = nodes_cfg_re.captures(trimmed) {
            result.nodes_configured = caps.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
            result.found = true;
        }
        if let Some(caps) = res_cfg_re.captures(trimmed) {
            result.resources_configured = caps.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
            result.found = true;
        }
        if trimmed.to_ascii_lowercase().contains("with quorum") {
            result.quorum_status = Some("with quorum".to_string());
        } else if trimmed.to_ascii_lowercase().contains("without quorum") {
            result.quorum_status = Some("without quorum".to_string());
        }

        if let Some(caps) = online_re.captures(trimmed) {
            if let Some(nodes) = caps.get(1) {
                for node in nodes.as_str().split_whitespace() {
                    if seen.insert(node.to_string()) {
                        let is_dc = result.dc_node.as_deref() == Some(node);
                        result.node_statuses.push(ClusterNodeStatus {
                            name: node.to_string(),
                            status: "online".to_string(),
                            online: true,
                            is_dc,
                            source_path: source_path.to_string(),
                            source_line: Some(line_no),
                            source_line_end: Some(line_no),
                        });
                    }
                }
            }
            result.found = true;
        }

        if let Some(caps) = offline_re.captures(trimmed) {
            if let Some(nodes) = caps.get(1) {
                for node in nodes.as_str().split_whitespace() {
                    if seen.insert(node.to_string()) {
                        result.node_statuses.push(ClusterNodeStatus {
                            name: node.to_string(),
                            status: "offline".to_string(),
                            online: false,
                            is_dc: false,
                            source_path: source_path.to_string(),
                            source_line: Some(line_no),
                            source_line_end: Some(line_no),
                        });
                    }
                }
            }
            result.found = true;
        }

        if let Some(caps) = node_re.captures(trimmed) {
            let node = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
            let status = caps.get(2).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_else(|| "unknown".to_string());
            if seen.insert(node.to_string()) {
                let is_dc = result.dc_node.as_deref() == Some(node);
                result.node_statuses.push(ClusterNodeStatus {
                    name: node.to_string(),
                    online: status == "online",
                    is_dc,
                    status,
                    source_path: source_path.to_string(),
                    source_line: Some(line_no),
                    source_line_end: Some(line_no),
                });
            }
            result.found = true;
        }
    }

    result
}

// ---------------------------------------------------------------------------
// Pacemaker high CPU
// ---------------------------------------------------------------------------

pub fn parse_pacemaker_high_cpu(content: &str, source_path: &str) -> Vec<HighCpuEvent> {
    let regex = Regex::new(
        r"^(?P<timestamp>[A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(?P<node>\S+)\s+pacemaker-controld\[\d+\]:\s+\w+:\s+High CPU load detected:\s*(?P<load>\d+(?:\.\d+)?)",
    )
    .unwrap();

    content
        .lines()
        .enumerate()
        .filter_map(|(idx, line)| {
            let line_no = idx + 1;
            let captures = regex.captures(line)?;
            let cpu_load = captures.get(3).and_then(|m| m.as_str().parse::<f64>().ok()).unwrap_or(0.0);
            let timestamp = captures.name("timestamp").map(|m| m.as_str().to_string()).unwrap_or_default();
            let source_node = captures.name("node").map(|m| m.as_str().to_string()).unwrap_or_default();

            Some(HighCpuEvent {
                timestamp,
                source_node: source_node.clone(),
                resource: "pacemaker-controld".to_string(),
                cpu_load,
                severity: "warning".to_string(),
                action: format!("high CPU load detected on {} ({:.6})", source_node, cpu_load),
                raw_line: line.to_string(),
                source_path: source_path.to_string(),
                source_line: Some(line_no),
                source_line_end: Some(line_no),
            })
        })
        .collect()
}

// ---------------------------------------------------------------------------
// Cluster events (migrations + fencing)
// ---------------------------------------------------------------------------

pub fn parse_cluster_events(content: &str, source_path: &str) -> ClusterEventsResult {
    let move_re = crate::cached_regex!(r"(?i)(?:Moving|Migrating)\s+(?:resource\s+)?(\S+)\s+from\s+(\S+)\s+to\s+(\S+)");
    let start_re = crate::cached_regex!(r"(?i)(?:Starting|Transition.*Starting)\s+(\S+)\s+on\s+(\S+)");
    let stop_re = crate::cached_regex!(r"(?i)(?:Stopping|Stopped)\s+(\S+)\s+on\s+(\S+)");
    let result_op_re = crate::cached_regex!(r"(?i)Result of (start|stop) operation for (\S+) on (\S+):\s*(\w+)");
    let op_re = crate::cached_regex!(r"(?i)Operation\s+(\S+?)_(?:start|stop|monitor|migrate)_\d+:\s*\w+\s*\(node=(\S+)\)");
    let high_cpu_re = crate::cached_regex!(r"(?i)High CPU load detected:\s*([0-9]+(?:\.[0-9]+)?)");
    let fence_request_re = crate::cached_regex!(r"(?i)Requesting\s+fencing\s+\((\w+)\)\s+(?:of\s+|targeting\s+)?(?:node\s+)?(\S+)");
    let fence_success_re = crate::cached_regex!(r"(?i)(?:Fencing|stonith.*?fence)\s+(\S+).*?(?:success|succeeded)");
    let peer_term_re = crate::cached_regex!(r"(?i)(?:Peer|peer)\s+(\S+)\s+was\s+(?:terminated|fenced)\s+\((\w+)\)");
    let peer_not_term_re = crate::cached_regex!(r"(?i)(?:Peer|peer)\s+(\S+)\s+was\s+not\s+terminated\s+\((\w+)\)");
    let fence_fail_re = crate::cached_regex!(r"(?i)(?:Fencing|stonith.*?fence)\s+(\S+).*?(?:fail|error)");
    let fence_will_re = crate::cached_regex!(r"(?i)(?:Cluster\s+node|Node|peer)\s+(\S+)\s+will\s+be\s+fenced");
    let fence_agent_re = crate::cached_regex!(r"(?i)(fence_\w+).*?(?:Called|for)\s+.*?(?:node\s+)?(\S+)");
    let monitor_failure_re = crate::cached_regex!(r"(?i)Unexpected\s+result\s+\((error|failed|timeout|not running):\s*([^)]+)\).*?(?:for\s+(?:monitor|start|stop|promote|demote)\s+of\s+)?(\S+?)(?::(\d+))?\s+on\s+(\S+)");
    let timeout_re = crate::cached_regex!(r"(?i)(?:Resource agent did not complete within|operation.* timed out after)\s+(\d+)s");
    let transition_fail_re = crate::cached_regex!(r"(?i)Transition\s+\d+\s+action\s+\d+\s+\(([^)]+)_(?:monitor|start|stop|promote|demote)_\d+\s+on\s+(\S+)\).*?expected\s+'([^']+)'\s+but\s+got\s+'([^']+)'");

    let mut resource_migrations = Vec::new();
    let mut fencing_events = Vec::new();

    for (idx, line) in content.lines().enumerate() {
        let line_no = idx + 1;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        if !(trimmed.contains("oving")
            || trimmed.contains("igrat")
            || trimmed.contains("tarting")
            || trimmed.contains("topping")
            || trimmed.contains("Operation")
            || trimmed.contains("Result of")
            || trimmed.contains("fence")
            || trimmed.contains("stonith")
            || trimmed.contains("Peer")
            || trimmed.contains("terminated")
            || trimmed.contains("fenced")
            || trimmed.contains("Unexpected")
            || trimmed.contains("Transition")
            || trimmed.contains("High CPU")
            || trimmed.contains("CPU load")
            || trimmed.contains("timed out")
            || trimmed.contains("did not complete"))
        {
            continue;
        }

        let (timestamp, source_node, message_text) = parse_syslog_prefix(trimmed);
        let sp = source_path.to_string();
        let sl = Some(line_no);
        let is_cluster_src = is_cluster_log_source(trimmed);

        if let Some(caps) = high_cpu_re.captures(&message_text) {
            let cpu_load = caps.get(1).and_then(|m| m.as_str().parse::<f64>().ok());
            let load_text = caps.get(1).map(|m| m.as_str()).unwrap_or("unknown");
            resource_migrations.push(ResourceMigrationEvent {
                timestamp,
                resource: "pacemaker-controld".to_string(),
                from_node: source_node.clone(),
                to_node: None,
                action: match source_node.clone() {
                    Some(node) => format!("high CPU load detected on {} ({})", node, load_text),
                    None => format!("high CPU load detected ({})", load_text),
                },
                severity: Some("warning".to_string()),
                cpu_load,
                error: None,
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = move_re.captures(&message_text) {
            resource_migrations.push(ResourceMigrationEvent {
                timestamp,
                resource: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                from_node: caps.get(2).map(|m| m.as_str().to_string()),
                to_node: caps.get(3).map(|m| m.as_str().to_string()),
                action: "migration".to_string(),
                severity: None,
                cpu_load: None,
                error: None,
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = start_re.captures(&message_text) {
            let resource = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
            let node = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            if is_cluster_src
                && !message_text.contains("systemd")
                && !is_systemd_resource(resource)
                && !is_system_resource(resource)
                && !is_non_cluster_node(node)
            {
                resource_migrations.push(ResourceMigrationEvent {
                    timestamp,
                    resource: resource.to_string(),
                    from_node: None,
                    to_node: Some(node.to_string()),
                    action: "start".to_string(),
                    severity: None,
                    cpu_load: None,
                    error: None,
                    raw_line: trimmed.to_string(),
                    source_path: sp.clone(),
                    source_line: sl,
                    source_line_end: sl,
                });
            }
            continue;
        }

        if let Some(caps) = stop_re.captures(&message_text) {
            let resource = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
            let node = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            if is_cluster_src
                && !message_text.contains("systemd")
                && !is_systemd_resource(resource)
                && !is_system_resource(resource)
                && !is_non_cluster_node(node)
            {
                resource_migrations.push(ResourceMigrationEvent {
                    timestamp,
                    resource: resource.to_string(),
                    from_node: Some(node.to_string()),
                    to_node: None,
                    action: "stop".to_string(),
                    severity: None,
                    cpu_load: None,
                    error: None,
                    raw_line: trimmed.to_string(),
                    source_path: sp.clone(),
                    source_line: sl,
                    source_line_end: sl,
                });
            }
            continue;
        }

        if let Some(caps) = result_op_re.captures(&message_text) {
            let action = caps.get(1).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_else(|| "unknown".to_string());
            let resource = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            let node = caps.get(3).map(|m| m.as_str()).unwrap_or_default();
            if is_cluster_src
                && !message_text.contains("systemd")
                && !is_systemd_resource(resource)
                && !is_system_resource(resource)
                && !is_non_cluster_node(node)
            {
                resource_migrations.push(ResourceMigrationEvent {
                    timestamp,
                    resource: resource.to_string(),
                    from_node: if action == "stop" { Some(node.to_string()) } else { None },
                    to_node: if action == "start" { Some(node.to_string()) } else { None },
                    action,
                    severity: None,
                    cpu_load: None,
                    error: None,
                    raw_line: trimmed.to_string(),
                    source_path: sp.clone(),
                    source_line: sl,
                    source_line_end: sl,
                });
            }
            continue;
        }

        if let Some(caps) = op_re.captures(&message_text) {
            let resource = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
            let node = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            let action = if message_text.contains("_start_") {
                "start"
            } else if message_text.contains("_stop_") {
                "stop"
            } else {
                "operation"
            };

            if is_cluster_src
                && !is_systemd_resource(resource)
                && !is_system_resource(resource)
                && !is_non_cluster_node(node)
            {
            resource_migrations.push(ResourceMigrationEvent {
                timestamp,
                resource: resource.to_string(),
                from_node: if action == "stop" { Some(node.to_string()) } else { None },
                to_node: if action == "start" { Some(node.to_string()) } else { None },
                action: action.to_string(),
                severity: None,
                cpu_load: None,
                error: None,
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            }
            continue;
        }

        if let Some(caps) = fence_request_re.captures(trimmed) {
            fencing_events.push(FencingEvent {
                timestamp,
                target_node: caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_default(),
                action: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_else(|| "fence".to_string()),
                status: "requested".to_string(),
                agent: None,
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = fence_success_re.captures(&message_text) {
            fencing_events.push(FencingEvent {
                timestamp,
                target_node: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                action: "fence".to_string(),
                status: "success".to_string(),
                agent: None,
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = peer_term_re.captures(&message_text) {
            fencing_events.push(FencingEvent {
                timestamp,
                target_node: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                action: caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_else(|| "fence".to_string()),
                status: "success".to_string(),
                agent: None,
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = peer_not_term_re.captures(&message_text) {
            fencing_events.push(FencingEvent {
                timestamp,
                target_node: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                action: caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_else(|| "fence".to_string()),
                status: "failed".to_string(),
                agent: None,
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = fence_fail_re.captures(&message_text) {
            fencing_events.push(FencingEvent {
                timestamp,
                target_node: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                action: "fence".to_string(),
                status: "failed".to_string(),
                agent: None,
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = fence_will_re.captures(&message_text) {
            fencing_events.push(FencingEvent {
                timestamp,
                target_node: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                action: "fence".to_string(),
                status: "pending".to_string(),
                agent: None,
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = fence_agent_re.captures(&message_text) {
            fencing_events.push(FencingEvent {
                timestamp,
                target_node: caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_default(),
                action: "fence".to_string(),
                status: "in_progress".to_string(),
                agent: caps.get(1).map(|m| m.as_str().to_string()),
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = monitor_failure_re.captures(&message_text) {
            let resource = match (caps.get(3), caps.get(4)) {
                (Some(base), Some(instance)) => format!("{}:{}", base.as_str(), instance.as_str()),
                (Some(base), None) => base.as_str().to_string(),
                _ => String::new(),
            };
            let node = caps.get(5).map(|m| m.as_str().to_string());
            let err = format!(
                "{}: {}",
                caps.get(1).map(|m| m.as_str()).unwrap_or("error"),
                caps.get(2).map(|m| m.as_str()).unwrap_or("unknown")
            );
            resource_migrations.push(ResourceMigrationEvent {
                timestamp,
                resource,
                from_node: node,
                to_node: None,
                action: "failure".to_string(),
                severity: Some("error".to_string()),
                cpu_load: None,
                error: Some(err),
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = timeout_re.captures(&message_text) {
            resource_migrations.push(ResourceMigrationEvent {
                timestamp,
                resource: "unknown".to_string(),
                from_node: None,
                to_node: None,
                action: "timeout".to_string(),
                severity: Some("warning".to_string()),
                cpu_load: None,
                error: Some(format!("Operation timeout after {}s", caps.get(1).map(|m| m.as_str()).unwrap_or("0"))),
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
            continue;
        }

        if let Some(caps) = transition_fail_re.captures(&message_text) {
            resource_migrations.push(ResourceMigrationEvent {
                timestamp,
                resource: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                from_node: caps.get(2).map(|m| m.as_str().to_string()),
                to_node: None,
                action: "transition_failure".to_string(),
                severity: Some("error".to_string()),
                cpu_load: None,
                error: Some(format!(
                    "Expected '{}' but got '{}'",
                    caps.get(3).map(|m| m.as_str()).unwrap_or("unknown"),
                    caps.get(4).map(|m| m.as_str()).unwrap_or("unknown")
                )),
                raw_line: trimmed.to_string(),
                source_path: sp.clone(),
                source_line: sl,
                source_line_end: sl,
            });
        }
    }

    let total = resource_migrations.len() + fencing_events.len();
    ClusterEventsResult {
        found: total > 0,
        resource_migrations,
        fencing_events,
        total_events: total,
        count: total,
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// Cluster maintenance mode
// ---------------------------------------------------------------------------

pub fn parse_cluster_maintenance_mode(content: &str, source_path: &str) -> ClusterMaintenanceResult {
    let mut result = ClusterMaintenanceResult {
        found: false,
        maintenance_mode: None,
        resources_in_maintenance: Vec::new(),
        warnings: Vec::new(),
        source_path: source_path.to_string(),
    };

    // Locate the line of the cluster-wide maintenance-mode property, if any.
    let mm_re = crate::cached_regex!(r#"name=["']maintenance-mode["']\s+value=["'](true|false)["']"#);
    let mut maintenance_line: Option<usize> = None;
    let mut disabled_line: Option<usize> = None;
    let resource_re = crate::cached_regex!(r"(?i)(?:Resource|Clone Set|Primary/Secondary Set|Resource Group):\s+([^\s(]+).*?\(.*?maintenance.*?\)");
    let mut resource_lines: Vec<(String, usize)> = Vec::new();

    for (idx, line) in content.lines().enumerate() {
        let line_no = idx + 1;
        if maintenance_line.is_none() && mm_re.is_match(line) {
            maintenance_line = Some(line_no);
        }
        if disabled_line.is_none() && line.contains("Resource management is DISABLED") {
            disabled_line = Some(line_no);
        }
        if let Some(caps) = resource_re.captures(line) {
            if let Some(name) = caps.get(1).map(|m| m.as_str().to_string()) {
                resource_lines.push((name, line_no));
            }
        }
    }

    if let Some(caps) = mm_re.captures(content) {
        let enabled = caps.get(1).map(|m| m.as_str().eq_ignore_ascii_case("true")).unwrap_or(false);
        result.found = true;
        result.maintenance_mode = Some(enabled);
        if enabled {
            result.warnings.push(make_warning(
                "cluster_in_maintenance",
                "warning",
                "Cluster is in maintenance mode - resources will not be managed".to_string(),
                None,
                None,
                None,
                Some("Run \"crm configure property maintenance-mode=false\" to exit maintenance mode when ready"),
                source_path,
                maintenance_line,
            ));
        }
    }

    if content.contains("Resource management is DISABLED") {
        result.found = true;
        result.maintenance_mode = Some(true);
        if !result.warnings.iter().any(|w| w.kind == "cluster_in_maintenance") {
            result.warnings.push(make_warning(
                "cluster_in_maintenance",
                "warning",
                "Cluster resource management is DISABLED".to_string(),
                None,
                None,
                None,
                Some("Check if cluster is in maintenance mode or stonith is disabled"),
                source_path,
                disabled_line,
            ));
        }
    }

    let mut first_res_line: Option<usize> = None;
    for (name, line_no) in &resource_lines {
        if !result.resources_in_maintenance.contains(name) {
            result.resources_in_maintenance.push(name.clone());
            if first_res_line.is_none() {
                first_res_line = Some(*line_no);
            }
        }
    }

    if !result.resources_in_maintenance.is_empty() {
        result.found = true;
        result.warnings.push(make_warning(
            "resources_in_maintenance",
            "info",
            format!("{} resource(s) in maintenance mode", result.resources_in_maintenance.len()),
            None,
            None,
            None,
            None,
            source_path,
            first_res_line,
        ));
    }

    result
}

// ===========================================================================
// New text-based parsers (Phase 4 port from cluster.js)
// ===========================================================================

// Helper: extract a section from an SCC aggregated file (like ha.txt).
// Looks for `# <marker>` line; collects subsequent lines until the next
// section marker (`#==` or another `# /…` header).
fn extract_scc_section(content: &str, marker: &str) -> Option<String> {
    let mut lines: Vec<&str> = Vec::new();
    let mut in_section = false;
    for line in content.lines() {
        if !in_section {
            if line.trim_start().starts_with('#') && line.contains(marker) {
                in_section = true;
                continue;
            }
        } else {
            // End on next section header (#==…) or comment-style header for a different file
            if line.starts_with("#==") {
                break;
            }
            if line.trim_start().starts_with("# /") && !line.contains(marker) {
                break;
            }
            lines.push(line);
        }
    }
    if lines.is_empty() {
        None
    } else {
        Some(lines.join("\n"))
    }
}

// ---------------------------------------------------------------------------
// hostsFile  (parses /etc/hosts; embedded inside network.txt for SCC)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HostsEntry {
    pub ip: String,
    pub hostnames: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HostsFileResult {
    pub found: bool,
    pub entries: Vec<HostsEntry>,
    pub all_hostnames: Vec<String>,
    pub source_path: String,
}

pub fn parse_hosts_file(content: &str, source_path: &str) -> HostsFileResult {
    let body = if source_path.ends_with("network.txt") || source_path.contains("/network.txt") {
        match extract_scc_section(content, "/etc/hosts") {
            Some(s) => s,
            None => {
                return HostsFileResult {
                    found: false,
                    entries: Vec::new(),
                    all_hostnames: Vec::new(),
                    source_path: source_path.to_string(),
                };
            }
        }
    } else {
        content.to_string()
    };

    let mut entries: Vec<HostsEntry> = Vec::new();
    let mut hostname_set: HashSet<String> = HashSet::new();

    for line in body.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let parts: Vec<&str> = trimmed.split_whitespace().collect();
        if parts.len() < 2 {
            continue;
        }
        let ip = parts[0].to_string();
        let names: Vec<String> = parts[1..].iter().map(|s| s.to_string()).collect();
        for n in &names {
            hostname_set.insert(n.clone());
        }
        entries.push(HostsEntry { ip, hostnames: names });
    }

    let mut all_hostnames: Vec<String> = hostname_set.into_iter().collect();
    all_hostnames.sort();

    HostsFileResult {
        found: !entries.is_empty(),
        entries,
        all_hostnames,
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// corosyncStatus  (parses corosync-cfgtool -s output)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CorosyncStatusNode {
    pub node_id: String,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CorosyncStatusResult {
    pub found: bool,
    pub valid: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub local_node_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transport: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nodes: Option<Vec<CorosyncStatusNode>>,
    pub source_path: String,
}

pub fn parse_corosync_status(content: &str, source_path: &str) -> CorosyncStatusResult {
    use std::sync::OnceLock;
    static INIT_ERR: OnceLock<Regex> = OnceLock::new();
    static LOCAL_RE: OnceLock<Regex> = OnceLock::new();
    static NODE_RE: OnceLock<Regex> = OnceLock::new();
    let init_err = INIT_ERR.get_or_init(|| {
        Regex::new(r"(?i)Could not initialize corosync configuration").unwrap()
    });
    let local_re = LOCAL_RE.get_or_init(|| {
        Regex::new(r"(?i)Local node ID\s+(\d+).*transport\s+(\w+)").unwrap()
    });
    let node_re = NODE_RE.get_or_init(|| Regex::new(r"(?i)nodeid:\s*(\d+):\s*(\w+)").unwrap());

    let mut local_node_id: Option<String> = None;
    let mut transport: Option<String> = None;
    let mut nodes: Vec<CorosyncStatusNode> = Vec::new();

    for raw in content.lines() {
        let trimmed = raw.trim();
        if init_err.is_match(trimmed) {
            return CorosyncStatusResult {
                found: true,
                valid: false,
                error: Some(trimmed.to_string()),
                local_node_id: None,
                transport: None,
                nodes: None,
                source_path: source_path.to_string(),
            };
        }
        if let Some(caps) = local_re.captures(trimmed) {
            local_node_id = caps.get(1).map(|m| m.as_str().to_string());
            transport = caps.get(2).map(|m| m.as_str().to_string());
        }
        if let Some(caps) = node_re.captures(trimmed) {
            nodes.push(CorosyncStatusNode {
                node_id: caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                status: caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_default(),
            });
        }
    }

    CorosyncStatusResult {
        found: true,
        valid: true,
        error: None,
        local_node_id,
        transport,
        nodes: Some(nodes),
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// clusterDaemonStatus  (parses pcs status "Daemon Status:" section)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct DaemonState {
    pub active: Option<bool>,
    pub enabled: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct DaemonStatusMap {
    pub corosync: DaemonState,
    pub pacemaker: DaemonState,
    pub pcsd: DaemonState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DaemonWarning {
    pub severity: String,
    pub daemon: String,
    pub message: String,
    pub recommendation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClusterDaemonStatusResult {
    pub found: bool,
    pub daemons: DaemonStatusMap,
    pub warnings: Vec<DaemonWarning>,
    pub corosync_enabled: Option<bool>,
    pub pacemaker_enabled: Option<bool>,
    pub corosync_active: Option<bool>,
    pub pacemaker_active: Option<bool>,
    pub source_path: String,
}

pub fn parse_cluster_daemon_status(content: &str, source_path: &str) -> ClusterDaemonStatusResult {
    use std::sync::OnceLock;
    static SECTION_RE: OnceLock<Regex> = OnceLock::new();
    static DAEMON_RE: OnceLock<Regex> = OnceLock::new();
    static SECTION_HEADER_RE: OnceLock<Regex> = OnceLock::new();
    let section_re = SECTION_RE.get_or_init(|| Regex::new(r"(?i)^Daemon Status:?$").unwrap());
    let daemon_re = DAEMON_RE.get_or_init(|| {
        Regex::new(r"(?i)^\s*(corosync|pacemaker|pcsd):\s*(\w+)/(\w+)").unwrap()
    });
    let section_header_re =
        SECTION_HEADER_RE.get_or_init(|| Regex::new(r"^[A-Z][a-z]+ [A-Z]").unwrap());

    let mut daemons = DaemonStatusMap::default();
    let mut warnings: Vec<DaemonWarning> = Vec::new();
    let mut found = false;
    let mut in_section = false;

    for raw in content.lines() {
        let line = raw.trim();
        if section_re.is_match(line) {
            in_section = true;
            continue;
        }
        if in_section
            && (line.is_empty() || section_header_re.is_match(line))
            && !daemon_re.is_match(line)
        {
            in_section = false;
        }
        if in_section {
            if let Some(caps) = daemon_re.captures(line) {
                let daemon = caps.get(1).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_default();
                let active_status = caps.get(2).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_default();
                let enabled_status = caps.get(3).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_default();
                let state = DaemonState {
                    active: Some(active_status == "active"),
                    enabled: Some(enabled_status == "enabled"),
                };
                match daemon.as_str() {
                    "corosync" => daemons.corosync = state,
                    "pacemaker" => daemons.pacemaker = state,
                    "pcsd" => daemons.pcsd = state,
                    _ => {}
                }
                found = true;

                if daemon == "corosync" && enabled_status == "disabled" {
                    warnings.push(DaemonWarning {
                        severity: "error".to_string(),
                        daemon: "corosync".to_string(),
                        message: "Corosync is disabled and will not start automatically after reboot. Cluster resources will not start after system restart.".to_string(),
                        recommendation: "Run \"pcs cluster enable --all\" or \"systemctl enable corosync\" on all nodes to enable automatic cluster startup.".to_string(),
                    });
                }
                if daemon == "pacemaker" && enabled_status == "disabled" {
                    warnings.push(DaemonWarning {
                        severity: "warning".to_string(),
                        daemon: "pacemaker".to_string(),
                        message: "Pacemaker is disabled and will not start automatically after reboot.".to_string(),
                        recommendation: "Run \"pcs cluster enable --all\" or \"systemctl enable pacemaker\" on all nodes.".to_string(),
                    });
                }
                if daemon == "corosync" && active_status != "active" {
                    warnings.push(DaemonWarning {
                        severity: "error".to_string(),
                        daemon: "corosync".to_string(),
                        message: "Corosync is not running. The cluster cannot function without corosync.".to_string(),
                        recommendation: "Run \"pcs cluster start\" or \"systemctl start corosync\" to start the cluster.".to_string(),
                    });
                }
                if daemon == "pacemaker" && active_status != "active" {
                    warnings.push(DaemonWarning {
                        severity: "error".to_string(),
                        daemon: "pacemaker".to_string(),
                        message: "Pacemaker is not running. Cluster resources cannot be managed.".to_string(),
                        recommendation: "Run \"pcs cluster start\" or \"systemctl start pacemaker\" to start the resource manager.".to_string(),
                    });
                }
            }
        }
    }

    if !found {
        return ClusterDaemonStatusResult {
            found: false,
            daemons: DaemonStatusMap::default(),
            warnings: Vec::new(),
            corosync_enabled: None,
            pacemaker_enabled: None,
            corosync_active: None,
            pacemaker_active: None,
            source_path: source_path.to_string(),
        };
    }

    ClusterDaemonStatusResult {
        found: true,
        corosync_enabled: daemons.corosync.enabled,
        pacemaker_enabled: daemons.pacemaker.enabled,
        corosync_active: daemons.corosync.active,
        pacemaker_active: daemons.pacemaker.active,
        daemons,
        warnings,
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// sbdConfig  (parses /etc/sysconfig/sbd or embedded in ha.txt)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SbdWarning {
    #[serde(rename = "type")]
    pub kind: String,
    pub severity: String,
    pub message: String,
    pub recommendation: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SbdRecommendation {
    #[serde(rename = "type")]
    pub kind: String,
    pub severity: String,
    pub message: String,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SbdConfigResult {
    pub found: bool,
    pub sbd_device: Option<String>,
    pub sbd_devices: Vec<String>,
    pub sbd_pacemaker: Option<String>,
    pub sbd_startmode: Option<String>,
    pub sbd_delay_start: Option<String>,
    pub sbd_watchdog_dev: Option<String>,
    pub sbd_watchdog_timeout: Option<i64>,
    pub sbd_timeout_action: Option<String>,
    pub warnings: Vec<SbdWarning>,
    pub recommendations: Vec<SbdRecommendation>,
    pub source_file: Option<String>,
    pub source_path: String,
}

pub fn parse_sbd_config(content: &str, source_path: &str) -> SbdConfigResult {
    let mut result = SbdConfigResult {
        found: false,
        sbd_device: None,
        sbd_devices: Vec::new(),
        sbd_pacemaker: None,
        sbd_startmode: None,
        sbd_delay_start: None,
        sbd_watchdog_dev: None,
        sbd_watchdog_timeout: None,
        sbd_timeout_action: None,
        warnings: Vec::new(),
        recommendations: Vec::new(),
        source_file: None,
        source_path: source_path.to_string(),
    };

    let body = if source_path.contains("ha.txt") {
        match extract_scc_section(content, "/etc/sysconfig/sbd") {
            Some(s) => s,
            None => return result,
        }
    } else {
        content.to_string()
    };

    if body.contains("sbd dump") || body.contains("==[ Command ]") {
        return result;
    }

    use std::sync::OnceLock;
    static DEVICE_RE: OnceLock<Regex> = OnceLock::new();
    static PACEMAKER_RE: OnceLock<Regex> = OnceLock::new();
    static STARTMODE_RE: OnceLock<Regex> = OnceLock::new();
    static DELAY_RE: OnceLock<Regex> = OnceLock::new();
    static WD_DEV_RE: OnceLock<Regex> = OnceLock::new();
    static WD_TO_RE: OnceLock<Regex> = OnceLock::new();
    static TO_ACTION_RE: OnceLock<Regex> = OnceLock::new();
    let device_re = DEVICE_RE.get_or_init(|| Regex::new(r#"^SBD_DEVICE=["']?([^"'\n]+?)["']?$"#).unwrap());
    let pacemaker_re = PACEMAKER_RE.get_or_init(|| Regex::new(r#"^SBD_PACEMAKER=["']?(\w+)["']?"#).unwrap());
    let startmode_re = STARTMODE_RE.get_or_init(|| Regex::new(r#"^SBD_STARTMODE=["']?(\w+)["']?"#).unwrap());
    let delay_re = DELAY_RE.get_or_init(|| Regex::new(r#"^SBD_DELAY_START=["']?([^"'\n]+?)["']?$"#).unwrap());
    let wd_dev_re = WD_DEV_RE.get_or_init(|| Regex::new(r#"^SBD_WATCHDOG_DEV=["']?([^"'\n]+?)["']?$"#).unwrap());
    let wd_to_re = WD_TO_RE.get_or_init(|| Regex::new(r#"^SBD_WATCHDOG_TIMEOUT=["']?(\d+)["']?"#).unwrap());
    let to_action_re = TO_ACTION_RE.get_or_init(|| Regex::new(r#"^SBD_TIMEOUT_ACTION=["']?([^"'\n]+?)["']?$"#).unwrap());

    for raw in body.lines() {
        let trimmed = raw.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(caps) = device_re.captures(trimmed) {
            result.found = true;
            let v = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
            result.sbd_device = Some(v.clone());
            result.sbd_devices = v.split(';').filter(|s| !s.trim().is_empty()).map(|s| s.to_string()).collect();
            result.source_file = Some(source_path.to_string());
        }
        if let Some(caps) = pacemaker_re.captures(trimmed) {
            result.found = true;
            let v = caps.get(1).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_default();
            if v != "yes" {
                result.warnings.push(SbdWarning {
                    kind: "sbd_pacemaker_disabled".to_string(),
                    severity: "warning".to_string(),
                    message: format!("SBD_PACEMAKER is not set to \"yes\" (current: {})", v),
                    recommendation: "Set SBD_PACEMAKER=yes for proper Pacemaker integration".to_string(),
                    documentation_url: None,
                });
            }
            result.sbd_pacemaker = Some(v);
        }
        if let Some(caps) = startmode_re.captures(trimmed) {
            result.found = true;
            let v = caps.get(1).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_default();
            if v != "always" {
                result.warnings.push(SbdWarning {
                    kind: "sbd_startmode_not_always".to_string(),
                    severity: "info".to_string(),
                    message: format!("SBD_STARTMODE is \"{}\" (recommended: \"always\")", v),
                    recommendation: "Consider setting SBD_STARTMODE=always for Azure deployments".to_string(),
                    documentation_url: None,
                });
            }
            result.sbd_startmode = Some(v);
        }
        if let Some(caps) = delay_re.captures(trimmed) {
            result.found = true;
            let v = caps.get(1).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_default();
            if v == "no" || v == "yes" {
                result.warnings.push(SbdWarning {
                    kind: "sbd_delay_start_not_numeric".to_string(),
                    severity: "warning".to_string(),
                    message: format!("SBD_DELAY_START is \"{}\" but should be a numeric value", v),
                    recommendation: "Set SBD_DELAY_START to a specific delay value in seconds (e.g., 216) per Azure best practices".to_string(),
                    documentation_url: Some("https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker".to_string()),
                });
            }
            result.sbd_delay_start = Some(v);
        }
        if let Some(caps) = wd_dev_re.captures(trimmed) {
            result.found = true;
            result.sbd_watchdog_dev = caps.get(1).map(|m| m.as_str().to_string());
        }
        if let Some(caps) = wd_to_re.captures(trimmed) {
            result.found = true;
            result.sbd_watchdog_timeout = caps.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
        }
        if let Some(caps) = to_action_re.captures(trimmed) {
            result.found = true;
            result.sbd_timeout_action = caps.get(1).map(|m| m.as_str().to_string());
        }
    }

    let n = result.sbd_devices.len();
    if n == 2 {
        result.warnings.push(SbdWarning {
            kind: "sbd_two_devices".to_string(),
            severity: "warning".to_string(),
            message: "Only 2 SBD devices configured - this is not recommended".to_string(),
            recommendation: "Use 1 or 3 SBD devices. With 2 devices, Pacemaker cannot automatically fence if one becomes unavailable.".to_string(),
            documentation_url: Some("https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-suse-pacemaker".to_string()),
        });
    } else if n > 0 {
        let detail = if n == 3 {
            "Optimal configuration for high availability".to_string()
        } else if n == 1 {
            "Single device configuration".to_string()
        } else {
            format!("{} devices configured", n)
        };
        result.recommendations.push(SbdRecommendation {
            kind: "sbd_device_count".to_string(),
            severity: "info".to_string(),
            message: format!("{} SBD device(s) configured", n),
            detail,
        });
    }

    result
}

// ---------------------------------------------------------------------------
// azureFenceAuth  (parses fence_azure_arm config from CIB / ha.txt)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureFenceWarning {
    #[serde(rename = "type")]
    pub kind: String,
    pub severity: String,
    pub message: String,
    pub recommendation: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documentation_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureFenceRecommendation {
    #[serde(rename = "type")]
    pub kind: String,
    pub severity: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureFenceAuthResult {
    pub found: bool,
    pub auth_method: Option<String>,
    pub subscription_id: Option<String>,
    pub resource_group: Option<String>,
    pub tenant_id: Option<String>,
    pub has_login: bool,
    pub has_password: bool,
    pub pcmk_monitor_retries: Option<i64>,
    pub pcmk_action_limit: Option<i64>,
    pub power_timeout: Option<i64>,
    pub pcmk_reboot_timeout: Option<i64>,
    pub pcmk_delay_max: Option<i64>,
    pub pcmk_host_map: Option<String>,
    pub warnings: Vec<AzureFenceWarning>,
    pub recommendations: Vec<AzureFenceRecommendation>,
    pub source_file: Option<String>,
    pub source_path: String,
}

fn cap_str(content: &str, pattern: &str) -> Option<String> {
    Regex::new(pattern).ok().and_then(|re| {
        re.captures(content)
            .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
    })
}

fn cap_int(content: &str, pattern: &str) -> Option<i64> {
    cap_str(content, pattern).and_then(|s| s.parse::<i64>().ok())
}

pub fn parse_azure_fence_auth(content: &str, source_path: &str) -> AzureFenceAuthResult {
    let mut result = AzureFenceAuthResult {
        found: false,
        auth_method: None,
        subscription_id: None,
        resource_group: None,
        tenant_id: None,
        has_login: false,
        has_password: false,
        pcmk_monitor_retries: None,
        pcmk_action_limit: None,
        power_timeout: None,
        pcmk_reboot_timeout: None,
        pcmk_delay_max: None,
        pcmk_host_map: None,
        warnings: Vec::new(),
        recommendations: Vec::new(),
        source_file: None,
        source_path: source_path.to_string(),
    };

    if !content.contains("fence_azure_arm") {
        return result;
    }
    result.found = true;
    result.source_file = Some(source_path.to_string());

    // MSI
    let msi_re = crate::cached_regex!(r#"(?i)name=["']msi["']\s+value=["'](true|false)["']"#);
    if let Some(caps) = msi_re.captures(content) {
        if caps.get(1).map(|m| m.as_str().eq_ignore_ascii_case("true")).unwrap_or(false) {
            result.auth_method = Some("msi".to_string());
            result.recommendations.push(AzureFenceRecommendation {
                kind: "using_msi".to_string(),
                severity: "info".to_string(),
                message: "Azure fence agent is using Managed Identity (MSI) - recommended configuration".to_string(),
            });
        }
    }

    let login_re = crate::cached_regex!(r#"(?i)name=["']login["']\s+value=["']([^"']+)["']"#);
    if login_re.is_match(content) {
        result.has_login = true;
        if result.auth_method.is_none() {
            result.auth_method = Some("service_principal".to_string());
        }
    }

    let passwd_re = crate::cached_regex!(r#"(?i)name=["'](?:passwd|password)["']\s+value="#);
    if passwd_re.is_match(content) {
        result.has_password = true;
        if result.auth_method.is_none() {
            result.auth_method = Some("service_principal".to_string());
        }
    }

    if result.auth_method.as_deref() == Some("service_principal") {
        result.warnings.push(AzureFenceWarning {
            kind: "using_service_principal".to_string(),
            severity: "warning".to_string(),
            message: "Azure fence agent is using Service Principal authentication".to_string(),
            recommendation: "Consider migrating to Managed Identity (MSI) for improved security and easier credential management".to_string(),
            documentation_url: Some("https://techcommunity.microsoft.com/t5/running-sap-applications-on-the/sap-on-azure-high-availability-change-from-spn-to-msi-for/ba-p/3609278".to_string()),
        });
    }

    result.subscription_id = cap_str(content, r#"(?i)name=["']subscriptionId["']\s+value=["']([^"']+)["']"#);
    result.resource_group = cap_str(content, r#"(?i)name=["']resourceGroup["']\s+value=["']([^"']+)["']"#);
    result.tenant_id = cap_str(content, r#"(?i)name=["']tenantId["']\s+value=["']([^"']+)["']"#);
    result.pcmk_monitor_retries = cap_int(content, r#"(?i)name=["']pcmk_monitor_retries["']\s+value=["'](\d+)["']"#);
    result.pcmk_action_limit = cap_int(content, r#"(?i)name=["']pcmk_action_limit["']\s+value=["'](\d+)["']"#);
    result.power_timeout = cap_int(content, r#"(?i)name=["']power_timeout["']\s+value=["'](\d+)["']"#);
    result.pcmk_reboot_timeout = cap_int(content, r#"(?i)name=["']pcmk_reboot_timeout["']\s+value=["'](\d+)["']"#);
    result.pcmk_delay_max = cap_int(content, r#"(?i)name=["']pcmk_delay_max["']\s+value=["'](\d+)["']"#);
    result.pcmk_host_map = cap_str(content, r#"(?i)name=["']pcmk_host_map["']\s+value=["']([^"']+)["']"#);

    result
}

// ---------------------------------------------------------------------------
// iscsiConfig  (initiator, targets, sessions, hosts, iscsid.conf)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IscsiPortal {
    pub ip: String,
    pub port: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IscsiTarget {
    pub iqn: String,
    pub portals: Vec<IscsiPortal>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IscsiDiscovery {
    pub ip: String,
    pub port: i64,
    pub method: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IscsiSession {
    pub session_id: i64,
    pub ip: String,
    pub port: i64,
    pub iqn: String,
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub connection_state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_state: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IscsiHost {
    pub host_number: i64,
    pub state: String,
    pub transport: String,
    pub ip: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IscsiSetting {
    // Stored as a list of key/value pairs because the keys (e.g.
    // "node.session.timeo.replacement_timeout") contain underscores that
    // would be mangled by the JS bridge's snake→camel transform. The JS
    // shim re-projects this into the legacy `iscsidConfig` object shape.
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IscsiServiceStatus {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub iscsi_service: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub iscsid_service: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IscsiWarning {
    #[serde(rename = "type")]
    pub kind: String,
    pub severity: String,
    pub message: String,
    pub recommendation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IscsiConfigResult {
    pub found: bool,
    pub initiator_name: Option<String>,
    pub targets: Vec<IscsiTarget>,
    pub discovery_servers: Vec<IscsiDiscovery>,
    pub sessions: Vec<IscsiSession>,
    pub hosts: Vec<IscsiHost>,
    pub node_startup: Option<String>,
    pub iscsid_config: Vec<IscsiSetting>,
    pub service_status: IscsiServiceStatus,
    pub warnings: Vec<IscsiWarning>,
    pub source_file: Option<String>,
    pub source_path: String,
}

pub fn parse_iscsi_config(content: &str, source_path: &str) -> IscsiConfigResult {
    let mut result = IscsiConfigResult {
        found: false,
        initiator_name: None,
        targets: Vec::new(),
        discovery_servers: Vec::new(),
        sessions: Vec::new(),
        hosts: Vec::new(),
        node_startup: None,
        iscsid_config: Vec::new(),
        service_status: IscsiServiceStatus {
            iscsi_service: None,
            iscsid_service: None,
        },
        warnings: Vec::new(),
        source_file: None,
        source_path: source_path.to_string(),
    };

    // InitiatorName
    if let Some(caps) = crate::cached_regex!(r"(?i)InitiatorName=([^\s\n]+)").captures(content) {
        result.found = true;
        result.initiator_name = caps.get(1).map(|m| m.as_str().to_string());
        result.source_file = Some(source_path.to_string());
    }

    // iscsid.conf settings
    let settings = [
        "node.startup",
        "node.session.timeo.replacement_timeout",
        "node.conn[0].timeo.login_timeout",
        "node.conn[0].timeo.logout_timeout",
        "node.session.initial_login_retry_max",
        "node.session.iscsi.FirstBurstLength",
        "node.session.iscsi.MaxBurstLength",
        "discovery.sendtargets.iscsi.MaxRecvDataSegmentLength",
    ];
    for setting in &settings {
        let escaped = regex::escape(setting);
        let pattern = format!(r"(?i){}\s*=\s*([^\n]+)", escaped);
        if let Ok(re) = Regex::new(&pattern) {
            if let Some(caps) = re.captures(content) {
                if let Some(v) = caps.get(1).map(|m| m.as_str().trim().to_string()) {
                    result.found = true;
                    result.iscsid_config.push(IscsiSetting {
                        name: setting.to_string(),
                        value: v,
                    });
                }
            }
        }
    }

    if let Some(s) = result.iscsid_config.iter().find(|s| s.name == "node.startup") {
        result.node_startup = Some(s.value.to_ascii_lowercase());
    }

    // Discovery servers
    let mut seen_disc: HashSet<String> = HashSet::new();
    let disc_re = crate::cached_regex!(r"(\d+\.\d+\.\d+\.\d+):(\d+)\s+via\s+(\w+)");
    for caps in disc_re.captures_iter(content) {
        let ip = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
        let port: i64 = caps.get(2).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
        let key = format!("{}:{}", ip, port);
        if seen_disc.insert(key) {
            result.found = true;
            result.discovery_servers.push(IscsiDiscovery {
                ip,
                port,
                method: caps.get(3).map(|m| m.as_str().to_string()).unwrap_or_default(),
            });
        }
    }

    // Targets
    let mut targets_by_iqn: std::collections::HashMap<String, IscsiTarget> = std::collections::HashMap::new();
    let mut iqn_order: Vec<String> = Vec::new();
    let target_re = crate::cached_regex!(r"(\d+\.\d+\.\d+\.\d+):(\d+),\d+\s+(iqn\.[^\s\n(]+)");
    for caps in target_re.captures_iter(content) {
        let ip = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
        let port: i64 = caps.get(2).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
        let iqn = caps.get(3).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
        let entry = targets_by_iqn.entry(iqn.clone()).or_insert_with(|| {
            iqn_order.push(iqn.clone());
            IscsiTarget {
                iqn: iqn.clone(),
                portals: Vec::new(),
            }
        });
        let portal_key = format!("{}:{}", ip, port);
        if !entry
            .portals
            .iter()
            .any(|p| format!("{}:{}", p.ip, p.port) == portal_key)
        {
            entry.portals.push(IscsiPortal { ip, port });
        }
    }
    for iqn in iqn_order {
        if let Some(t) = targets_by_iqn.remove(&iqn) {
            result.found = true;
            result.targets.push(t);
        }
    }

    // Sessions
    let mut seen_sess: HashSet<String> = HashSet::new();
    let sess_re = Regex::new(
        r"tcp:\s+\[(\d+)\]\s+(\d+\.\d+\.\d+\.\d+):(\d+),\d+\s+(iqn\.[^\s\n(]+)(?:\s+\(([^)]+)\))?",
    )
    .unwrap();
    for caps in sess_re.captures_iter(content) {
        let session_id_str = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
        if !seen_sess.insert(session_id_str.clone()) {
            continue;
        }
        result.found = true;
        result.sessions.push(IscsiSession {
            session_id: session_id_str.parse().unwrap_or(0),
            ip: caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_default(),
            port: caps.get(3).and_then(|m| m.as_str().parse().ok()).unwrap_or(0),
            iqn: caps.get(4).map(|m| m.as_str().trim().to_string()).unwrap_or_default(),
            kind: caps
                .get(5)
                .map(|m| m.as_str().to_string())
                .unwrap_or_else(|| "unknown".to_string()),
            connection_state: None,
            session_state: None,
        });
    }

    // Connection state per session
    let state_re = Regex::new(
        r"Current Portal:\s+(\d+\.\d+\.\d+\.\d+):(\d+)[\s\S]*?iSCSI Connection State:\s*([^\n]+)[\s\S]*?iSCSI Session State:\s*([^\n]+)",
    )
    .unwrap();
    for caps in state_re.captures_iter(content) {
        let ip = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
        let port: i64 = caps.get(2).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
        let conn = caps.get(3).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
        let sess = caps.get(4).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
        if let Some(s) = result
            .sessions
            .iter_mut()
            .find(|s| s.ip == ip && s.port == port)
        {
            s.connection_state = Some(conn);
            s.session_state = Some(sess);
        }
    }

    // Hosts
    let host_re = Regex::new(
        r"Host Number:\s*(\d+)[\s\S]*?State:\s*(\w+)[\s\S]*?Transport:\s*(\w+)[\s\S]*?IPaddress:\s*([^\n]+)",
    )
    .unwrap();
    for caps in host_re.captures_iter(content) {
        result.found = true;
        result.hosts.push(IscsiHost {
            host_number: caps.get(1).and_then(|m| m.as_str().parse().ok()).unwrap_or(0),
            state: caps.get(2).map(|m| m.as_str().trim().to_string()).unwrap_or_default(),
            transport: caps.get(3).map(|m| m.as_str().trim().to_string()).unwrap_or_default(),
            ip: caps.get(4).map(|m| m.as_str().trim().to_string()).unwrap_or_default(),
        });
    }

    // Service status
    if let Some(caps) = crate::cached_regex!(r"iscsi\.service[\s\S]*?Active:\s*([^\n]+)")
        .captures(content)
    {
        result.service_status.iscsi_service = caps.get(1).map(|m| m.as_str().trim().to_string());
    }
    if let Some(caps) = crate::cached_regex!(r"iscsid\.service[\s\S]*?Active:\s*([^\n]+)")
        .captures(content)
    {
        result.service_status.iscsid_service = caps.get(1).map(|m| m.as_str().trim().to_string());
    }

    // Warnings
    if result.sessions.is_empty() && !result.targets.is_empty() {
        result.warnings.push(IscsiWarning {
            kind: "iscsi_no_active_sessions".to_string(),
            severity: "warning".to_string(),
            message: "iSCSI targets configured but no active sessions".to_string(),
            recommendation: "Check iSCSI connectivity and network status".to_string(),
        });
    }
    for s in &result.sessions {
        if let Some(state) = &s.connection_state {
            if state != "LOGGED IN" {
                result.warnings.push(IscsiWarning {
                    kind: "iscsi_session_not_logged_in".to_string(),
                    severity: "error".to_string(),
                    message: format!("iSCSI session to {} is not logged in ({})", s.ip, state),
                    recommendation: "Check iSCSI target availability and network connectivity".to_string(),
                });
            }
        }
    }
    if !result.sessions.is_empty() {
        let mut by_iqn: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        let mut iqn_order: Vec<String> = Vec::new();
        for s in &result.sessions {
            if !by_iqn.contains_key(&s.iqn) {
                iqn_order.push(s.iqn.clone());
            }
            *by_iqn.entry(s.iqn.clone()).or_insert(0) += 1;
        }
        for iqn in iqn_order {
            let count = by_iqn[&iqn];
            if count < 3 {
                result.warnings.push(IscsiWarning {
                    kind: "iscsi_insufficient_paths".to_string(),
                    severity: "info".to_string(),
                    message: format!("iSCSI target {} has only {} path(s)", iqn, count),
                    recommendation: "Azure iSCSI SBD typically requires 3 paths for high availability".to_string(),
                });
            }
        }
    }

    result
}

// ---------------------------------------------------------------------------
// liveMigration  (detects Hyper-V live migration via hv_utils sequence)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LiveMigrationEvent {
    pub timestamp: String,
    pub line_number: usize,
    pub raw_line: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LiveMigrationResult {
    pub found: bool,
    pub count: usize,
    pub events: Vec<LiveMigrationEvent>,
    pub source_path: String,
}

pub fn parse_live_migration(content: &str, source_path: &str) -> LiveMigrationResult {
    let lines: Vec<&str> = content.lines().collect();
    let mut migrations: Vec<LiveMigrationEvent> = Vec::new();

    let mut i = 0usize;
    while i < lines.len() {
        let line = lines[i];
        if !(line.contains("hv_utils") || line.contains("hv_balloon") || line.contains("hv_netvsc")) {
            i += 1;
            continue;
        }
        if line.contains("hv_utils: Heartbeat IC") {
            let heartbeat = i;
            // find hv_balloon within next 100 lines
            let end_b = (i + 100).min(lines.len());
            let mut balloon: Option<usize> = None;
            for j in (i + 1)..end_b {
                if lines[j].contains("hv_balloon") {
                    balloon = Some(j);
                    break;
                }
            }
            if let Some(b) = balloon {
                let end_n = (heartbeat + 100).min(lines.len());
                let mut netvsc: Option<usize> = None;
                for k in (b + 1)..end_n {
                    if lines[k].contains("hv_netvsc") {
                        netvsc = Some(k);
                        break;
                    }
                }
                if let Some(n) = netvsc {
                    let (timestamp, _node, _msg) = parse_syslog_prefix(lines[heartbeat]);
                    migrations.push(LiveMigrationEvent {
                        timestamp: timestamp.unwrap_or_else(|| "Unknown".to_string()),
                        line_number: heartbeat + 1,
                        raw_line: lines[heartbeat].to_string(),
                    });
                    i = n;
                }
            }
        }
        i += 1;
    }

    LiveMigrationResult {
        found: !migrations.is_empty(),
        count: migrations.len(),
        events: migrations,
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// sapInstanceErrors  (scans logs for SAPInstance / Filesystem RA errors)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SapInstanceError {
    #[serde(rename = "type")]
    pub kind: String,
    pub severity: String,
    pub resource_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub service_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mount_point: Option<String>,
    pub timestamp: Option<String>,
    pub line_number: usize,
    pub message: String,
    pub recommendation: String,
    pub raw_line: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct SapInstanceErrorsSummary {
    pub start_profile_error_count: usize,
    pub gray_status_error_count: usize,
    pub filesystem_error_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SapInstanceErrorsResult {
    pub found: bool,
    pub errors: Vec<SapInstanceError>,
    pub start_profile_errors: Vec<SapInstanceError>,
    pub gray_status_errors: Vec<SapInstanceError>,
    pub filesystem_errors: Vec<SapInstanceError>,
    pub error_count: usize,
    pub summary: SapInstanceErrorsSummary,
    pub source_path: String,
}

pub fn parse_sap_instance_errors(content: &str, source_path: &str) -> SapInstanceErrorsResult {
    use std::sync::OnceLock;
    static START_RE: OnceLock<Regex> = OnceLock::new();
    static GRAY_RE: OnceLock<Regex> = OnceLock::new();
    static FS_RE: OnceLock<Regex> = OnceLock::new();
    static TS_RE: OnceLock<Regex> = OnceLock::new();
    let start_re = START_RE.get_or_init(|| {
        Regex::new(r"(?i)SAPInstance\(([^)]+)\)\[\d+\]:\s*ERROR:\s*Expected\s+(\S+)\s+to be the instance START profile").unwrap()
    });
    let gray_re = GRAY_RE.get_or_init(|| {
        Regex::new(r"(?i)SAPInstance\(([^)]+)\)\[\d+\]:\s*ERROR:\s*SAP instance service\s+(\S+)\s+is not running with status GRAY").unwrap()
    });
    let fs_re = FS_RE.get_or_init(|| {
        Regex::new(r"(?i)Filesystem\(([^)]+)\)\[\d+\]:\s*ERROR:\s*Couldn't unmount\s+(\S+)").unwrap()
    });
    let ts_re = TS_RE.get_or_init(|| Regex::new(r"^(\w+\s+\d+\s+\d+:\d+:\d+)").unwrap());

    let mut start_profile_errors: Vec<SapInstanceError> = Vec::new();
    let mut gray_status_errors: Vec<SapInstanceError> = Vec::new();
    let mut filesystem_errors: Vec<SapInstanceError> = Vec::new();
    let mut errors: Vec<SapInstanceError> = Vec::new();

    for (i, raw_line) in content.lines().enumerate() {
        if !(raw_line.contains("SAPInstance") || raw_line.contains("Filesystem(")) {
            continue;
        }
        let timestamp = ts_re
            .captures(raw_line)
            .and_then(|c| c.get(1).map(|m| m.as_str().to_string()));

        if let Some(caps) = start_re.captures(raw_line) {
            let resource_name = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
            let profile_path = caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_default();
            let exists = start_profile_errors.iter().any(|e| {
                e.resource_name == resource_name
                    && e.profile_path.as_deref() == Some(profile_path.as_str())
            });
            if !exists {
                let err = SapInstanceError {
                    kind: "start_profile_not_found".to_string(),
                    severity: "error".to_string(),
                    resource_name,
                    profile_path: Some(profile_path.clone()),
                    service_name: None,
                    mount_point: None,
                    timestamp: timestamp.clone(),
                    line_number: i + 1,
                    message: format!(
                        "SAP profile file \"{}\" not found for resource {}",
                        profile_path,
                        caps.get(1).map(|m| m.as_str()).unwrap_or("")
                    ),
                    recommendation: "Verify that the START_PROFILE path points to an existing SAP profile file. The profile filename should match the virtual hostname configured for the SAP instance. Check /sapmnt/<SID>/profile/ for available profiles.".to_string(),
                    raw_line: raw_line.trim().to_string(),
                };
                start_profile_errors.push(err.clone());
                errors.push(err);
            }
        }
        if let Some(caps) = gray_re.captures(raw_line) {
            let resource_name = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
            let service_name = caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_default();
            let exists = gray_status_errors.iter().any(|e| {
                e.resource_name == resource_name
                    && e.service_name.as_deref() == Some(service_name.as_str())
            });
            if !exists {
                let err = SapInstanceError {
                    kind: "sap_service_gray_status".to_string(),
                    severity: "error".to_string(),
                    resource_name: resource_name.clone(),
                    profile_path: None,
                    service_name: Some(service_name.clone()),
                    mount_point: None,
                    timestamp: timestamp.clone(),
                    line_number: i + 1,
                    message: format!(
                        "SAP service \"{}\" is not running (status GRAY) for resource {}",
                        service_name, resource_name
                    ),
                    recommendation: "GRAY status indicates the SAP service failed to start or crashed. Check SAP instance logs under /usr/sap/<SID>/<INSTANCE>/work/ for startup errors. Verify NFS mounts are available and SAP profile is correct.".to_string(),
                    raw_line: raw_line.trim().to_string(),
                };
                gray_status_errors.push(err.clone());
                errors.push(err);
            }
        }
        if let Some(caps) = fs_re.captures(raw_line) {
            let resource_name = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
            let mount_point = caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_default();
            let exists = filesystem_errors.iter().any(|e| {
                e.resource_name == resource_name
                    && e.mount_point.as_deref() == Some(mount_point.as_str())
            });
            if !exists {
                let err = SapInstanceError {
                    kind: "filesystem_unmount_error".to_string(),
                    severity: "warning".to_string(),
                    resource_name: resource_name.clone(),
                    profile_path: None,
                    service_name: None,
                    mount_point: Some(mount_point.clone()),
                    timestamp,
                    line_number: i + 1,
                    message: format!(
                        "Failed to unmount filesystem \"{}\" for resource {}",
                        mount_point, resource_name
                    ),
                    recommendation: "Check for processes still using the filesystem with \"lsof\" or \"fuser\". This may indicate SAP processes did not stop cleanly before failover.".to_string(),
                    raw_line: raw_line.trim().to_string(),
                };
                filesystem_errors.push(err.clone());
                errors.push(err);
            }
        }
    }

    let found = !errors.is_empty();
    let summary = SapInstanceErrorsSummary {
        start_profile_error_count: start_profile_errors.len(),
        gray_status_error_count: gray_status_errors.len(),
        filesystem_error_count: filesystem_errors.len(),
    };
    SapInstanceErrorsResult {
        found,
        error_count: errors.len(),
        errors,
        start_profile_errors,
        gray_status_errors,
        filesystem_errors,
        summary,
        source_path: source_path.to_string(),
    }
}

// ---------------------------------------------------------------------------
// JSON wrappers
// ---------------------------------------------------------------------------

pub fn parse_pacemaker_high_cpu_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_pacemaker_high_cpu(content, source_path))
        .unwrap_or_else(|_| "[]".to_string())
}

pub fn parse_cluster_events_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_cluster_events(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_cluster_status_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_cluster_status(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_corosync_config_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_corosync_config(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_cluster_maintenance_mode_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_cluster_maintenance_mode(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_hosts_file_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_hosts_file(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_corosync_status_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_corosync_status(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_cluster_daemon_status_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_cluster_daemon_status(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_sbd_config_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_sbd_config(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_azure_fence_auth_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_azure_fence_auth(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_iscsi_config_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_iscsi_config(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_live_migration_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_live_migration(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_sap_instance_errors_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_sap_instance_errors(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

// ============================================================================
// XML attribute helper (regex-based, mirrors JS parseXMLSimple usage pattern)
// ============================================================================

/// Iterate over every opening tag with the given name, returning each tag's
/// attributes as a list of (name, value) pairs. Matches both `<tag attrs>` and
/// `<tag attrs/>`.
fn iter_xml_tags(content: &str, tag: &str) -> Vec<std::collections::HashMap<String, String>> {
    let pattern = format!(r#"<{}\b([^>]*?)/?>"#, regex::escape(tag));
    let re = match Regex::new(&pattern) {
        Ok(r) => r,
        Err(_) => return Vec::new(),
    };
    let attr_re = crate::cached_regex!(r#"([A-Za-z_][A-Za-z0-9_:.\-]*)\s*=\s*"([^"]*)""#);
    let mut out = Vec::new();
    for caps in re.captures_iter(content) {
        let attrs_str = caps.get(1).map(|m| m.as_str()).unwrap_or("");
        let mut map = std::collections::HashMap::new();
        for ac in attr_re.captures_iter(attrs_str) {
            let k = ac.get(1).unwrap().as_str().to_string();
            let v = ac.get(2).unwrap().as_str().to_string();
            map.insert(k, v);
        }
        out.push(map);
    }
    out
}

// ============================================================================
// parse_cluster_nodes — ha.txt / corosync.conf / cib.xml / crm_mon
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NodeIpEntry {
    /// Hostname; the JS shim projects [{host,ip}, ...] back to {host: ip} object.
    pub host: String,
    pub ip: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClusterNodesResult {
    pub nodes: Vec<String>,
    /// Vec form to dodge JS bridge key-mangling; shim converts to {host: ip}.
    pub node_to_ip_map: Vec<NodeIpEntry>,
}

pub fn parse_cluster_nodes(content: &str, _source_path: &str) -> ClusterNodesResult {
    let mut node_set: HashSet<String> = HashSet::new();
    let mut node_to_ip: Vec<NodeIpEntry> = Vec::new();

    // XML CIB extraction (uname/id attributes on <node> tags)
    if content.contains("<node") && (content.contains("<cib") || content.contains("uname=")) {
        let id_only_digits = crate::cached_regex!(r"^\d+$");
        for attrs in iter_xml_tags(content, "node") {
            if let Some(uname) = attrs.get("uname") {
                if !uname.is_empty() {
                    node_set.insert(uname.clone());
                    continue;
                }
            }
            if let Some(id) = attrs.get("id") {
                if !id_only_digits.is_match(id) {
                    node_set.insert(id.clone());
                }
            }
        }
    }

    let nodelist_re = crate::cached_regex!(r"(?i)^nodelist\s*\{");
    let node_block_re = crate::cached_regex!(r"(?i)^node\s*\{");
    let name_re = crate::cached_regex!(r"(?i)^name:\s*([a-zA-Z][a-zA-Z0-9_\-\.]+)");
    let ring0_re = crate::cached_regex!(r"(?i)^ring0_addr:\s*(.+)$");
    let ipv4_re = crate::cached_regex!(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$");
    let host_re = crate::cached_regex!(r"^[a-zA-Z][a-zA-Z0-9_\-\.]+$");
    let plain_node_re = crate::cached_regex!(r"(?i)^node[:\s]+([a-zA-Z][a-zA-Z0-9_\-\.]+)");
    let crm_node_re =
        crate::cached_regex!(r"(?i)(?:\*\s+)?Node\s+([a-zA-Z0-9][a-zA-Z0-9_\-\.]+)(?:\s+\(|:)");
    let name_simple_re = crate::cached_regex!(r"(?i)^\s*name:");
    let name_value_re = crate::cached_regex!(r"(?i)name:\s*([a-zA-Z0-9][a-zA-Z0-9_\-\.]+)");
    let ipv4_inline_re = crate::cached_regex!(r"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}");

    let mut in_nodelist = false;
    let mut in_node = false;
    let mut depth: i32 = 0;
    let mut current_name: Option<String> = None;
    let mut current_ring0: Option<String> = None;

    for line in content.lines() {
        let trimmed = line.trim();
        if nodelist_re.is_match(trimmed) {
            in_nodelist = true;
            depth = 1;
            continue;
        }
        if in_nodelist {
            if node_block_re.is_match(trimmed) {
                in_node = true;
                current_name = None;
                current_ring0 = None;
                depth += 1;
                continue;
            }
            if in_node {
                if let Some(c) = name_re.captures(trimmed) {
                    current_name = Some(c.get(1).unwrap().as_str().to_string());
                }
                if let Some(c) = ring0_re.captures(trimmed) {
                    let addr = c.get(1).unwrap().as_str().trim().to_string();
                    if ipv4_re.is_match(&addr) || host_re.is_match(&addr) {
                        current_ring0 = Some(addr);
                    }
                }
                if trimmed == "}" {
                    in_node = false;
                    depth -= 1;
                    if let (Some(n), Some(r)) = (&current_name, &current_ring0) {
                        if ipv4_re.is_match(r) {
                            node_to_ip.push(NodeIpEntry {
                                host: n.clone(),
                                ip: r.clone(),
                            });
                        }
                    }
                    if let Some(n) = current_name.take() {
                        node_set.insert(n);
                    }
                    current_ring0 = None;
                    continue;
                }
            }
            if trimmed == "}" {
                depth -= 1;
            } else if trimmed.ends_with('{') {
                depth += 1;
            }
            if depth == 0 {
                in_nodelist = false;
            }
            continue;
        }

        if let Some(c) = plain_node_re.captures(trimmed) {
            node_set.insert(c.get(1).unwrap().as_str().to_string());
            continue;
        }
        if let Some(c) = crm_node_re.captures(trimmed) {
            node_set.insert(c.get(1).unwrap().as_str().to_string());
            continue;
        }
        if name_simple_re.is_match(trimmed) {
            if let Some(c) = name_value_re.captures(trimmed) {
                let n = c.get(1).unwrap().as_str();
                if !ipv4_inline_re.is_match(n) {
                    node_set.insert(n.to_string());
                }
            }
        }
    }

    let excluded: HashSet<&str> = [
        "online",
        "offline",
        "standby",
        "maintenance",
        "pending",
        "unclean",
        "node",
        "nodes",
        "cluster",
        "member",
        "members",
        "list",
        "attributes",
        "stonith",
        "fencing",
        "resource",
        "resources",
        "status",
    ]
    .iter()
    .copied()
    .collect();
    let starts_alpha = crate::cached_regex!(r"^[a-zA-Z]");
    let valid_chars = crate::cached_regex!(r"^[a-zA-Z0-9_\-\.]+$");

    let mut nodes: Vec<String> = node_set
        .into_iter()
        .filter(|n| {
            if ipv4_re.is_match(n) {
                return true;
            }
            if !starts_alpha.is_match(n) {
                return false;
            }
            if n.len() < 3 {
                return false;
            }
            if excluded.contains(n.to_lowercase().as_str()) {
                return false;
            }
            valid_chars.is_match(n)
        })
        .collect();
    nodes.sort();

    ClusterNodesResult {
        nodes,
        node_to_ip_map: node_to_ip,
    }
}

// ============================================================================
// parse_fencing_config — cib.xml / crm config / pcs_config
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FencingDevice {
    pub name: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub agent: String,
    pub cloud: Option<String>,
    pub source_file: String,
    pub source_line: usize,
    pub pattern: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FencingConfigResult {
    pub found: bool,
    pub stonith_enabled: Option<bool>,
    pub stonith_source_file: Option<String>,
    pub stonith_source_pattern: Option<String>,
    pub fencing_devices: Vec<FencingDevice>,
    pub count: usize,
}

fn classify_fence_agent(agent_type: &str) -> (String, Option<String>) {
    if agent_type.contains("azure") {
        ("Azure Fencing".to_string(), Some("Azure".to_string()))
    } else if agent_type.contains("aws") {
        ("AWS Fencing".to_string(), Some("AWS".to_string()))
    } else if agent_type.contains("gce") {
        ("GCP Fencing".to_string(), Some("GCP".to_string()))
    } else if let Some(rest) = agent_type.strip_prefix("external/") {
        (format!("External {}", rest.to_uppercase()), None)
    } else if let Some(rest) = agent_type.strip_prefix("fence_") {
        (format!("Fence {}", rest.to_uppercase()), None)
    } else {
        (agent_type.to_string(), None)
    }
}

pub fn parse_fencing_config(content: &str, source_path: &str) -> FencingConfigResult {
    let mut devices: Vec<FencingDevice> = Vec::new();
    let mut stonith_enabled: Option<bool> = None;
    let mut stonith_source_file: Option<String> = None;
    let mut stonith_source_pattern: Option<String> = None;

    // XML branch
    if content.contains("<primitive") || content.contains("<nvpair") {
        // ha.txt extraction of cibadmin -Q section
        let xml_owned;
        let xml_content: &str = if source_path.contains("ha.txt") {
            if let Some(sec) = extract_scc_section(content, "/usr/sbin/cibadmin -Q") {
                xml_owned = sec;
                xml_owned.as_str()
            } else {
                content
            }
        } else {
            content
        };

        for attrs in iter_xml_tags(xml_content, "nvpair") {
            if attrs.get("name").map(|s| s.as_str()) == Some("stonith-enabled") {
                if let Some(v) = attrs.get("value") {
                    if v == "true" {
                        stonith_enabled = Some(true);
                        stonith_source_file = Some(source_path.to_string());
                        stonith_source_pattern =
                            Some(r#"<nvpair name="stonith-enabled" value="true"/>"#.to_string());
                    } else if v == "false" {
                        stonith_enabled = Some(false);
                        stonith_source_file = Some(source_path.to_string());
                        stonith_source_pattern =
                            Some(r#"<nvpair name="stonith-enabled" value="false"/>"#.to_string());
                    }
                }
            }
        }

        for attrs in iter_xml_tags(xml_content, "primitive") {
            let device_name = match attrs.get("id") {
                Some(s) if !s.is_empty() => s.clone(),
                _ => continue,
            };
            let agent_type = attrs.get("type").cloned().unwrap_or_default();
            let agent_class = attrs.get("class").cloned().unwrap_or_default();
            if agent_type.contains("fence_azure_arm") {
                if !devices.iter().any(|d| d.name == device_name) {
                    devices.push(FencingDevice {
                        name: device_name,
                        kind: "fence_azure_arm".to_string(),
                        agent: "Azure Fencing Agent".to_string(),
                        cloud: Some("Azure".to_string()),
                        source_file: source_path.to_string(),
                        source_line: 0,
                        pattern: r#"XML: <primitive ... type="fence_azure_arm">"#.to_string(),
                    });
                }
            } else if agent_class == "stonith" && !agent_type.is_empty() {
                if !devices.iter().any(|d| d.name == device_name) {
                    let (agent, cloud) = classify_fence_agent(&agent_type);
                    devices.push(FencingDevice {
                        name: device_name,
                        kind: agent_type.clone(),
                        agent,
                        cloud,
                        source_file: source_path.to_string(),
                        source_line: 0,
                        pattern: format!(
                            r#"XML: <primitive class="stonith" type="{}">"#,
                            agent_type
                        ),
                    });
                }
            }
        }
    }

    // Line-based scan for crm/pcs formats
    let stonith_true_re = crate::cached_regex!(r"(?i)stonith-enabled[=:\s]*true");
    let stonith_false_re = crate::cached_regex!(r"(?i)stonith-enabled[=:\s]*false");
    let azure_fence_crm_re = crate::cached_regex!(r"^primitive\s+([^\s]+).*?(?:stonith:)?fence_azure_arm");
    let pcs_azure_re =
        crate::cached_regex!(r"^Resource:\s+([^\s]+)\s+\(class=stonith\s+type=fence_azure_arm");
    let crm_fence_re = crate::cached_regex!(r"^primitive\s+([^\s]+).*?stonith:(\S+)");
    let pcs_fence_re =
        crate::cached_regex!(r"^Resource:\s+([^\s]+)\s+\(class=stonith\s+type=([^)\s]+)");

    for (idx, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        let line_num = idx + 1;

        if stonith_true_re.is_match(trimmed) && !trimmed.contains('<') {
            stonith_enabled = Some(true);
            stonith_source_file = Some(source_path.to_string());
            stonith_source_pattern = Some("stonith-enabled: true".to_string());
        }
        if stonith_false_re.is_match(trimmed) && !trimmed.contains('<') {
            stonith_enabled = Some(false);
            stonith_source_file = Some(source_path.to_string());
            stonith_source_pattern = Some("stonith-enabled: false".to_string());
        }

        if !trimmed.contains('<') {
            if let Some(c) = azure_fence_crm_re.captures(trimmed) {
                let name = c.get(1).unwrap().as_str().to_string();
                if !devices.iter().any(|d| d.name == name) {
                    devices.push(FencingDevice {
                        name,
                        kind: "fence_azure_arm".to_string(),
                        agent: "Azure Fencing Agent".to_string(),
                        cloud: Some("Azure".to_string()),
                        source_file: source_path.to_string(),
                        source_line: line_num,
                        pattern: "crm: primitive ... fence_azure_arm".to_string(),
                    });
                }
            }
        }
        if let Some(c) = pcs_azure_re.captures(trimmed) {
            let name = c.get(1).unwrap().as_str().to_string();
            if !devices.iter().any(|d| d.name == name) {
                devices.push(FencingDevice {
                    name,
                    kind: "fence_azure_arm".to_string(),
                    agent: "Azure Fencing Agent".to_string(),
                    cloud: Some("Azure".to_string()),
                    source_file: source_path.to_string(),
                    source_line: line_num,
                    pattern: "pcs: Resource ... (class=stonith type=fence_azure_arm)".to_string(),
                });
            }
        }
        if !trimmed.contains('<') {
            if let Some(c) = crm_fence_re.captures(trimmed) {
                let name = c.get(1).unwrap().as_str().to_string();
                let agent_type = c.get(2).unwrap().as_str().to_string();
                if !devices.iter().any(|d| d.name == name) {
                    let (agent, cloud) = if agent_type.contains("azure") {
                        ("Azure Fencing".to_string(), Some("Azure".to_string()))
                    } else if agent_type.contains("aws") {
                        ("AWS Fencing".to_string(), Some("AWS".to_string()))
                    } else if agent_type.contains("gce") {
                        ("GCP Fencing".to_string(), Some("GCP".to_string()))
                    } else {
                        (agent_type.clone(), None)
                    };
                    devices.push(FencingDevice {
                        name,
                        kind: agent_type.clone(),
                        agent,
                        cloud,
                        source_file: source_path.to_string(),
                        source_line: line_num,
                        pattern: format!("crm: primitive ... stonith:{}", agent_type),
                    });
                }
            }
        }
        if let Some(c) = pcs_fence_re.captures(trimmed) {
            let name = c.get(1).unwrap().as_str().to_string();
            if !devices.iter().any(|d| d.name == name) {
                let agent_type = c.get(2).unwrap().as_str().to_string();
                let (agent, cloud) = if agent_type.contains("azure") {
                    ("Azure Fencing".to_string(), Some("Azure".to_string()))
                } else if agent_type.contains("aws") {
                    ("AWS Fencing".to_string(), Some("AWS".to_string()))
                } else if agent_type.contains("gce") {
                    ("GCP Fencing".to_string(), Some("GCP".to_string()))
                } else {
                    (agent_type.clone(), None)
                };
                devices.push(FencingDevice {
                    name,
                    kind: agent_type.clone(),
                    agent,
                    cloud,
                    source_file: source_path.to_string(),
                    source_line: line_num,
                    pattern: format!("pcs: Resource ... (class=stonith type={})", agent_type),
                });
            }
        }
    }

    if !devices.is_empty() && stonith_enabled.is_none() {
        stonith_enabled = Some(true);
        stonith_source_file = Some(source_path.to_string());
        stonith_source_pattern = Some("Inferred from presence of stonith devices".to_string());
    }

    let count = devices.len();
    FencingConfigResult {
        found: true,
        stonith_enabled,
        stonith_source_file,
        stonith_source_pattern,
        fencing_devices: devices,
        count,
    }
}

// ============================================================================
// parse_azure_scheduled_events
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HealthAzureNode {
    pub node: String,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HealthAzureResource {
    pub found: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureSEWarning {
    pub severity: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub message: String,
    pub recommendation: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stopped_resources: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub online_nodes: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nodes_missing: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureScheduledEventsResult {
    pub found: bool,
    pub health_azure_configured: bool,
    pub health_azure_resource: Option<HealthAzureResource>,
    pub node_health_strategy: Option<String>,
    pub nodes_with_health_azure: Vec<HealthAzureNode>,
    pub nodes_without_health_azure: Vec<String>,
    pub stopped_resources: Vec<String>,
    pub online_nodes: Vec<String>,
    pub warnings: Vec<AzureSEWarning>,
}

pub fn parse_azure_scheduled_events(
    content: &str,
    _source_path: &str,
) -> AzureScheduledEventsResult {
    let mut result = AzureScheduledEventsResult {
        found: false,
        health_azure_configured: false,
        health_azure_resource: None,
        node_health_strategy: None,
        nodes_with_health_azure: Vec::new(),
        nodes_without_health_azure: Vec::new(),
        stopped_resources: Vec::new(),
        online_nodes: Vec::new(),
        warnings: Vec::new(),
    };

    let node_attrs_re = crate::cached_regex!(r"(?i)^Node Attributes:?$");
    let full_resources_re =
        crate::cached_regex!(r"(?i)^(Full List of Resources|Active Resources|Resources):?$");
    let node_list_re = crate::cached_regex!(r"(?i)^Node List:?$");
    let other_section_re =
        crate::cached_regex!(r"(?i)^(Migration Summary|Operations|Fencing History):?$");
    let node_online_re = crate::cached_regex!(r"(?i)^\*?\s*Node\s+(\S+).*:\s*(online|offline)");
    let node_context_re = crate::cached_regex!(r"(?i)^\*?\s*Node:?\s+(\S+)");
    let health_azure_re =
        crate::cached_regex!(r"(?i)^\*?\s*#health-azure\s*:\s*(-?\d+|undefined)");
    let stopped_re = crate::cached_regex!(r"(?i)^\*?\s*(\S+)\s+\([^)]+\):\s+Stopped");
    let health_strat_re = crate::cached_regex!(r"(?i)node-health-strategy\s*[:=]\s*(\S+)");
    let cib_health_attr_re =
        crate::cached_regex!(r#"(?i)name=["']#health-azure["']\s+value=["']([^"']+)["']"#);
    let cib_strat_re =
        crate::cached_regex!(r#"(?i)name=["']node-health-strategy["']\s+value=["']([^"']+)["']"#);
    let health_events_re = crate::cached_regex!(r"(?i)health-azure-events");

    let mut in_node_attrs = false;
    let mut in_resource_list = false;
    let mut in_node_list = false;
    let mut current_node: Option<String> = None;

    for line in content.lines() {
        let trimmed = line.trim();

        if node_attrs_re.is_match(trimmed) {
            in_node_attrs = true;
            in_resource_list = false;
            in_node_list = false;
            continue;
        }
        if full_resources_re.is_match(trimmed) {
            in_resource_list = true;
            in_node_attrs = false;
            in_node_list = false;
            continue;
        }
        if node_list_re.is_match(trimmed) {
            in_node_list = true;
            in_node_attrs = false;
            in_resource_list = false;
            continue;
        }
        if other_section_re.is_match(trimmed) {
            in_node_attrs = false;
            in_resource_list = false;
            in_node_list = false;
        }

        if in_node_list {
            if let Some(c) = node_online_re.captures(trimmed) {
                if c.get(2).unwrap().as_str().to_lowercase() == "online" {
                    result.online_nodes.push(c.get(1).unwrap().as_str().to_string());
                }
            }
        }

        if in_node_attrs {
            if let Some(c) = node_context_re.captures(trimmed) {
                let n = c.get(1).unwrap().as_str().trim_end_matches(':').to_string();
                current_node = Some(n);
                continue;
            }
            if let Some(c) = health_azure_re.captures(trimmed) {
                if let Some(node) = &current_node {
                    result.health_azure_configured = true;
                    result.nodes_with_health_azure.push(HealthAzureNode {
                        node: node.clone(),
                        value: c.get(1).unwrap().as_str().to_string(),
                    });
                }
            }
        }

        if in_resource_list {
            if let Some(c) = stopped_re.captures(trimmed) {
                let rsc = c.get(1).unwrap().as_str();
                if !rsc.to_lowercase().contains("health-azure") {
                    result.stopped_resources.push(rsc.to_string());
                }
            }
            if health_events_re.is_match(trimmed) {
                result.health_azure_resource = Some(HealthAzureResource {
                    found: true,
                    line: Some(trimmed.to_string()),
                    source: None,
                });
            }
        }

        if let Some(c) = health_strat_re.captures(trimmed) {
            result.node_health_strategy = Some(c.get(1).unwrap().as_str().to_string());
        }
    }

    if content.contains("<cib") || content.contains("<nvpair") {
        if cib_health_attr_re.is_match(content) {
            result.health_azure_configured = true;
        }
        if let Some(c) = cib_strat_re.captures(content) {
            result.node_health_strategy = Some(c.get(1).unwrap().as_str().to_string());
        }
        if health_events_re.is_match(content) && result.health_azure_resource.is_none() {
            result.health_azure_resource = Some(HealthAzureResource {
                found: true,
                line: None,
                source: Some("cib.xml".to_string()),
            });
        }
    }

    result.found = !result.online_nodes.is_empty()
        || !result.stopped_resources.is_empty()
        || result.health_azure_configured
        || result.health_azure_resource.is_some();

    if !result.found {
        return AzureScheduledEventsResult {
            found: false,
            ..result
        };
    }

    if !result.stopped_resources.is_empty() && !result.online_nodes.is_empty() {
        if !result.health_azure_configured && result.health_azure_resource.is_none() {
            result.warnings.push(AzureSEWarning {
                severity: "error".to_string(),
                kind: "health_azure_not_configured".to_string(),
                message: format!(
                    "{} cluster resource(s) are stopped while {} node(s) are online. Azure Scheduled Events (health-azure) is NOT configured.",
                    result.stopped_resources.len(),
                    result.online_nodes.len()
                ),
                recommendation: "Configure Azure Scheduled Events by creating the health-azure-events resource and setting #health-azure attribute on all nodes. See: https://learn.microsoft.com/en-us/azure/sap/workloads/high-availability-guide-rhel-pacemaker#configure-pacemaker-for-azure-scheduled-events".to_string(),
                stopped_resources: Some(result.stopped_resources.clone()),
                online_nodes: Some(result.online_nodes.clone()),
                nodes_missing: None,
            });
        }
        if result.node_health_strategy.as_deref() == Some("custom")
            && !result.health_azure_configured
        {
            result.warnings.push(AzureSEWarning {
                severity: "error".to_string(),
                kind: "health_azure_attribute_missing".to_string(),
                message: "node-health-strategy is set to \"custom\" but #health-azure attribute is not configured on nodes. Resources cannot be scheduled.".to_string(),
                recommendation: "Initialize the #health-azure attribute on all nodes: sudo crm_attribute --node <node-name> --name '#health-azure' --update 0".to_string(),
                stopped_resources: None,
                online_nodes: Some(result.online_nodes.clone()),
                nodes_missing: None,
            });
        }
    }

    if !result.nodes_with_health_azure.is_empty()
        && result.online_nodes.len() > result.nodes_with_health_azure.len()
    {
        let nodes_with_attr: HashSet<&String> = result
            .nodes_with_health_azure
            .iter()
            .map(|n| &n.node)
            .collect();
        let missing: Vec<String> = result
            .online_nodes
            .iter()
            .filter(|n| !nodes_with_attr.contains(*n))
            .cloned()
            .collect();
        if !missing.is_empty() {
            result.nodes_without_health_azure = missing.clone();
            result.warnings.push(AzureSEWarning {
                severity: "warning".to_string(),
                kind: "health_azure_partial".to_string(),
                message: format!(
                    "#health-azure attribute is configured on some nodes but missing on: {}",
                    missing.join(", ")
                ),
                recommendation: "Set the #health-azure attribute on all cluster nodes for consistent behavior.".to_string(),
                stopped_resources: None,
                online_nodes: None,
                nodes_missing: Some(missing),
            });
        }
    }

    result
}

// ============================================================================
// parse_sap_instance_config
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SapInstanceWarning {
    pub severity: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub message: String,
    pub recommendation: String,
    pub resource_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instance_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub start_profile: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SapInstance {
    pub resource_name: String,
    pub instance_name: Option<String>,
    pub start_profile: Option<String>,
    #[serde(rename = "isERS")]
    pub is_ers: bool,
    pub automatic_recover: Option<bool>,
    pub warnings: Vec<SapInstanceWarning>,
    pub line_number: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SapInstanceConfigResult {
    pub found: bool,
    pub instances: Vec<SapInstance>,
    pub warnings: Vec<SapInstanceWarning>,
    pub instance_count: usize,
    pub warning_count: usize,
}

pub fn parse_sap_instance_config(content: &str, _source_path: &str) -> SapInstanceConfigResult {
    let mut instances: Vec<SapInstance> = Vec::new();
    let mut warnings: Vec<SapInstanceWarning> = Vec::new();
    let mut found = false;

    let resource_re =
        crate::cached_regex!(r"(?i)Resource:\s+(\S+)\s+\(.*type=SAPInstance\)");
    let xml_resource_re =
        crate::cached_regex!(r#"(?i)<primitive\s+id="([^"]+)"[^>]*type="SAPInstance""#);
    let next_section_re = crate::cached_regex!(r"^Resource:|^Group:");
    let attrs_re = crate::cached_regex!(r"(?i)Attributes:\s+(.*)");
    let instance_name_re = crate::cached_regex!(r"InstanceName=(\S+)");
    let start_profile_re = crate::cached_regex!(r"START_PROFILE=(\S+)");
    let is_ers_re = crate::cached_regex!(r"(?i)IS_ERS=(\S+)");
    let auto_recover_re = crate::cached_regex!(r"(?i)AUTOMATIC_RECOVER=(\S+)");
    let xml_nvpair_re =
        crate::cached_regex!(r#"(?i)<nvpair[^>]*name="([^"]+)"[^>]*value="([^"]+)""#);
    let profile_path_re = crate::cached_regex!(r"/sapmnt/([^/]+)/profile/([^/]+)$");
    let instance_format_re =
        crate::cached_regex!(r"(?i)^([A-Z0-9]{3})_(ASCS|SCS|ERS|D|J)(\d{2})_(.+)$");

    let mut current: Option<SapInstance> = None;
    let mut in_sap = false;

    for (i, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        let line_num = i + 1;

        if let Some(c) = resource_re.captures(trimmed) {
            if let Some(prev) = current.take() {
                instances.push(prev);
            }
            current = Some(SapInstance {
                resource_name: c.get(1).unwrap().as_str().to_string(),
                instance_name: None,
                start_profile: None,
                is_ers: false,
                automatic_recover: None,
                warnings: Vec::new(),
                line_number: line_num,
            });
            in_sap = true;
            found = true;
            continue;
        }
        if let Some(c) = xml_resource_re.captures(trimmed) {
            if let Some(prev) = current.take() {
                instances.push(prev);
            }
            current = Some(SapInstance {
                resource_name: c.get(1).unwrap().as_str().to_string(),
                instance_name: None,
                start_profile: None,
                is_ers: false,
                automatic_recover: None,
                warnings: Vec::new(),
                line_number: line_num,
            });
            in_sap = true;
            found = true;
            continue;
        }

        if in_sap && next_section_re.is_match(trimmed) && !trimmed.contains("SAPInstance") {
            if let Some(prev) = current.take() {
                instances.push(prev);
            }
            in_sap = false;
        }

        if let Some(cur) = current.as_mut() {
            if let Some(am) = attrs_re.captures(trimmed) {
                let s = am.get(1).unwrap().as_str();
                if let Some(c) = instance_name_re.captures(s) {
                    cur.instance_name = Some(c.get(1).unwrap().as_str().to_string());
                }
                if let Some(c) = start_profile_re.captures(s) {
                    cur.start_profile = Some(c.get(1).unwrap().as_str().to_string());
                }
                if let Some(c) = is_ers_re.captures(s) {
                    cur.is_ers = c.get(1).unwrap().as_str().to_lowercase() == "true";
                }
                if let Some(c) = auto_recover_re.captures(s) {
                    cur.automatic_recover =
                        Some(c.get(1).unwrap().as_str().to_lowercase() == "true");
                }
            }
            if let Some(c) = xml_nvpair_re.captures(trimmed) {
                let name = c.get(1).unwrap().as_str();
                let value = c.get(2).unwrap().as_str();
                match name {
                    "InstanceName" => cur.instance_name = Some(value.to_string()),
                    "START_PROFILE" => cur.start_profile = Some(value.to_string()),
                    "IS_ERS" => cur.is_ers = value.to_lowercase() == "true",
                    "AUTOMATIC_RECOVER" => {
                        cur.automatic_recover = Some(value.to_lowercase() == "true")
                    }
                    _ => {}
                }
            }
        }
    }

    if let Some(last) = current.take() {
        instances.push(last);
    }

    // Validate
    for instance in instances.iter_mut() {
        if let Some(sp) = instance.start_profile.clone() {
            if let Some(pm) = profile_path_re.captures(&sp) {
                let profile_filename = pm.get(2).unwrap().as_str();
                if let Some(inst_name) = instance.instance_name.clone() {
                    let instance_parts: Vec<&str> = inst_name.split('_').collect();
                    let profile_parts: Vec<&str> = profile_filename.split('_').collect();
                    if instance_parts.len() >= 3 && profile_parts.len() >= 3 {
                        let instance_hostname = instance_parts[2..].join("_");
                        let profile_hostname = profile_parts[2..].join("_");
                        if instance_hostname != profile_hostname {
                            let w = SapInstanceWarning {
                                severity: "warning".to_string(),
                                kind: "hostname_mismatch".to_string(),
                                message: format!(
                                    "InstanceName hostname \"{}\" does not match START_PROFILE hostname \"{}\"",
                                    instance_hostname, profile_hostname
                                ),
                                recommendation: "Verify that InstanceName and START_PROFILE reference the same virtual hostname for the SAP instance.".to_string(),
                                resource_name: instance.resource_name.clone(),
                                instance_name: Some(inst_name.clone()),
                                start_profile: Some(sp.clone()),
                            };
                            instance.warnings.push(w.clone());
                            warnings.push(w);
                        }
                    }
                }
            }
        } else {
            let w = SapInstanceWarning {
                severity: "error".to_string(),
                kind: "missing_start_profile".to_string(),
                message: "START_PROFILE attribute is missing".to_string(),
                recommendation: "Add START_PROFILE parameter pointing to the SAP instance profile file at /sapmnt/<SID>/profile/<SID>_<INSTANCE>_<virtual_hostname>".to_string(),
                resource_name: instance.resource_name.clone(),
                instance_name: None,
                start_profile: None,
            };
            instance.warnings.push(w.clone());
            warnings.push(w);
        }

        if let Some(inst_name) = instance.instance_name.clone() {
            if !instance_format_re.is_match(&inst_name) {
                let w = SapInstanceWarning {
                    severity: "warning".to_string(),
                    kind: "invalid_instance_format".to_string(),
                    message: format!(
                        "InstanceName \"{}\" does not follow expected format <SID>_<INSTANCE>_<hostname>",
                        inst_name
                    ),
                    recommendation: "InstanceName should be in format <SID>_<InstanceType><InstanceNumber>_<virtual_hostname>, e.g., PJU_SCS01_sapascs".to_string(),
                    resource_name: instance.resource_name.clone(),
                    instance_name: None,
                    start_profile: None,
                };
                instance.warnings.push(w.clone());
                warnings.push(w);
            }
        } else {
            let w = SapInstanceWarning {
                severity: "error".to_string(),
                kind: "missing_instance_name".to_string(),
                message: "InstanceName attribute is missing".to_string(),
                recommendation: "Add InstanceName parameter in format <SID>_<InstanceType><InstanceNumber>_<virtual_hostname>".to_string(),
                resource_name: instance.resource_name.clone(),
                instance_name: None,
                start_profile: None,
            };
            instance.warnings.push(w.clone());
            warnings.push(w);
        }
    }

    if !found {
        return SapInstanceConfigResult {
            found: false,
            instances: Vec::new(),
            warnings: Vec::new(),
            instance_count: 0,
            warning_count: 0,
        };
    }

    let instance_count = instances.len();
    let warning_count = warnings.len();
    SapInstanceConfigResult {
        found: true,
        instances,
        warnings,
        instance_count,
        warning_count,
    }
}

// ============================================================================
// parse_pacemaker_resources — biggest port (~810 LOC of JS)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PacemakerResource {
    pub name: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub provider: String,
    #[serde(rename = "class")]
    pub class_field: String,
    pub format: String,
    pub node: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    pub maintenance: bool,
    pub group_member: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub group_name: Option<String>,
    pub clone_member: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub clone_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location_score: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ResourceGroup {
    pub name: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub members: Vec<String>,
    pub node: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(default)]
    pub maintenance: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FailedAction {
    pub action: String,
    pub node: String,
    pub state: String,
    pub return_code: String,
    pub details: String,
}

/// Polymorphic constraint (location, colocation, order). Unused fields are
/// skipped at serialization to byte-match JS output.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct PacemakerConstraint {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resource: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub node: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub score: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub with_resource: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub first_resource: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub first_action: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub then_resource: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub then_action: Option<String>,
    /// Order constraint "kind" attribute (Mandatory/Optional/Serialize). Renamed
    /// to `kind` in JSON; the parent `kind` field is renamed to `type` so this
    /// does not collide.
    #[serde(rename = "kind", skip_serializing_if = "Option::is_none")]
    pub kind_field: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub symmetrical: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct PacemakerResourcesResult {
    pub found: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub resources: Vec<PacemakerResource>,
    #[serde(default)]
    pub count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub groups: Vec<ResourceGroup>,
    #[serde(default)]
    pub groups_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub constraints: Vec<PacemakerConstraint>,
    #[serde(default)]
    pub constraints_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub failed_actions: Vec<FailedAction>,
    #[serde(default)]
    pub failed_actions_count: usize,
}

pub fn parse_pacemaker_resources(content: &str, source_path: &str) -> PacemakerResourcesResult {
    let mut resources: Vec<PacemakerResource> = Vec::new();
    let mut constraints: Vec<PacemakerConstraint> = Vec::new();
    let mut group_data: Vec<ResourceGroup> = Vec::new();

    let is_ha_txt = source_path.contains("ha.txt");
    let mut relevant_owned: Option<String> = None;

    if is_ha_txt {
        let cib_start = content.find("<cib");
        let cib_end = content.find("</cib>");

        let mut crm_mon_sections: Vec<String> = Vec::new();
        let mut crm_status_section: Option<String> = None;

        // Split on `^#==[ Command ]====`
        let split_re = crate::cached_regex!(r"(?m)^#==\[ Command \]====");
        let parts: Vec<&str> = split_re.split(content).collect();
        let cmd_line_re = crate::cached_regex!(r"(?m)^[=\s]*#\s*([^\n]+)");

        for (i, part) in parts.iter().enumerate() {
            if i == 0 {
                continue;
            }
            let cm = match cmd_line_re.captures(part) {
                Some(c) => c,
                None => continue,
            };
            let cmd_match = cm.get(0).unwrap();
            let command_line = cm.get(1).unwrap().as_str().trim().to_string();
            let after = cmd_match.end();
            let section_content = match part[after..].find('\n') {
                Some(p) => &part[after + p + 1..],
                None => "",
            };

            if command_line.contains("crm_mon")
                && !command_line.contains("rpm")
                && !command_line.contains("egrep")
            {
                crm_mon_sections.push(section_content.to_string());
            } else if crate::cached_regex!(r"^crm\s+status").is_match(&command_line)
                && !command_line.contains("rpm")
            {
                crm_status_section = Some(section_content.to_string());
            }
        }

        let mut sections: Vec<String> = Vec::new();
        if let (Some(s), Some(e)) = (cib_start, cib_end) {
            sections.push(content[s..e + 6].to_string());
        }
        for s in &crm_mon_sections {
            sections.push(s.clone());
        }
        if let Some(s) = crm_status_section {
            sections.push(s);
        }

        if !sections.is_empty() {
            relevant_owned = Some(sections.join("\n\n"));
        } else {
            // crm configure show fallback
            let fallback_re = Regex::new(
                r"(?ms)^#==\[ Command \]====.*?crm configure show.*?(?=^#==\[|\z)",
            )
            .unwrap();
            if let Some(m) = fallback_re.find(content) {
                relevant_owned = Some(m.as_str().to_string());
            } else {
                return PacemakerResourcesResult {
                    found: false,
                    ..Default::default()
                };
            }
        }
    }

    let relevant_content: &str = relevant_owned.as_deref().unwrap_or(content);
    let content_lines: Vec<&str> = relevant_content.lines().collect();

    // ---- XML branch ----
    if relevant_content.contains("<cib") || relevant_content.contains("<primitive") {
        // Groups
        for attrs in iter_xml_tags(relevant_content, "group") {
            if let Some(id) = attrs.get("id") {
                if !id.is_empty() && !attrs.contains_key("crm-debug-origin") {
                    group_data.push(ResourceGroup {
                        name: id.clone(),
                        kind: "group".to_string(),
                        members: Vec::new(),
                        node: None,
                        status: None,
                        maintenance: false,
                    });
                }
            }
        }

        // Primitives
        for attrs in iter_xml_tags(relevant_content, "primitive") {
            let id = attrs.get("id").cloned().unwrap_or_default();
            let kind = attrs.get("type").cloned().unwrap_or_default();
            if id.is_empty() || kind.is_empty() {
                continue;
            }
            resources.push(PacemakerResource {
                name: id,
                kind,
                provider: attrs.get("provider").cloned().unwrap_or_else(|| "unknown".to_string()),
                class_field: attrs.get("class").cloned().unwrap_or_else(|| "ocf".to_string()),
                format: "xml".to_string(),
                node: None,
                status: None,
                maintenance: false,
                group_member: false,
                group_name: None,
                clone_member: false,
                clone_name: None,
                location_score: None,
            });
        }

        // rsc_location
        for attrs in iter_xml_tags(relevant_content, "rsc_location") {
            let id = attrs.get("id").cloned().unwrap_or_default();
            let rsc_name = attrs.get("rsc").cloned().unwrap_or_default();
            if id.is_empty() || rsc_name.is_empty() {
                continue;
            }
            let node = attrs.get("node").cloned();
            let role = attrs.get("role").cloned().unwrap_or_else(|| "Started".to_string());
            let score = attrs.get("score").cloned();
            constraints.push(PacemakerConstraint {
                id: id.clone(),
                kind: "location".to_string(),
                resource: Some(rsc_name.clone()),
                node: node.clone(),
                role: Some(role.clone()),
                score: score.clone(),
                ..Default::default()
            });
            if let Some(n) = node.clone() {
                if let Some(r) = resources.iter_mut().find(|r| r.name == rsc_name) {
                    if r.node.is_none() {
                        r.node = Some(n);
                        r.status = Some(role);
                        r.location_score = score;
                    }
                }
            }
        }

        // rsc_colocation
        for attrs in iter_xml_tags(relevant_content, "rsc_colocation") {
            let id = attrs.get("id").cloned().unwrap_or_default();
            let rsc = attrs.get("rsc").cloned().unwrap_or_default();
            let with_rsc = attrs.get("with-rsc").cloned().unwrap_or_default();
            if id.is_empty() || rsc.is_empty() || with_rsc.is_empty() {
                continue;
            }
            constraints.push(PacemakerConstraint {
                id,
                kind: "colocation".to_string(),
                resource: Some(rsc),
                with_resource: Some(with_rsc),
                score: attrs.get("score").cloned(),
                ..Default::default()
            });
        }

        // rsc_order
        for attrs in iter_xml_tags(relevant_content, "rsc_order") {
            let id = attrs.get("id").cloned().unwrap_or_default();
            let first = attrs.get("first").cloned().unwrap_or_default();
            let then = attrs.get("then").cloned().unwrap_or_default();
            if id.is_empty() || first.is_empty() || then.is_empty() {
                continue;
            }
            constraints.push(PacemakerConstraint {
                id,
                kind: "order".to_string(),
                first_resource: Some(first),
                first_action: Some(
                    attrs.get("first-action").cloned().unwrap_or_else(|| "start".to_string()),
                ),
                then_resource: Some(then),
                then_action: Some(
                    attrs.get("then-action").cloned().unwrap_or_else(|| "start".to_string()),
                ),
                kind_field: Some(
                    attrs.get("kind").cloned().unwrap_or_else(|| "Mandatory".to_string()),
                ),
                symmetrical: attrs.get("symmetrical").cloned(),
                ..Default::default()
            });
        }
    }

    // ---- Text-format scan (crm/crm_mon/pcs) ----
    let mut current_group: Option<String> = None;
    let mut current_clone: Option<String> = None;
    let mut in_pcs_resources = false;
    let mut in_pcs_constraints = false;

    let pcs_section_other_re = Regex::new(
        r"^(Stonith Devices|Location Constraints|Ordering Constraints|Colocation Constraints|Ticket Constraints|Fencing Levels|Node Attributes|Migration Summary|Tickets|PCSD Status|Daemon Status):",
    )
    .unwrap();
    let pcs_resource_re = Regex::new(
        r"^Resource:\s+(\S+)\s+\(class=(\S+)(?:\s+provider=(\S+))?\s+type=([^)]+)\)",
    )
    .unwrap();
    let pcs_group_re = crate::cached_regex!(r"^Group:\s+(\S+)");
    let pcs_clone_re = crate::cached_regex!(r"^Clone:\s+(\S+)");
    let pcs_status_marker_re =
        crate::cached_regex!(r"^\*\s+\S+\s+\([\w:]+\):\s+(Started|Stopped|Master|Slave)");
    let pcs_status_re =
        crate::cached_regex!(r"^\*\s+(\S+)\s+\(([\w:]+)\):\s+(\w+)(?:\s+(\S+))?");
    let pcs_order_re = Regex::new(
        r"^(\w+)\s+(\S+)\s+then\s+(\w+)\s+(\S+)\s+\(kind:(\w+)\)(?:\s+\(id:([^)]+)\))?",
    )
    .unwrap();
    let pcs_coloc_re = crate::cached_regex!(r"^(\S+)\s+with\s+(\S+)\s+\(score:(\S+)\)");
    let clone_set_re = Regex::new(
        r"(?i)^\*?\s*(?:Clone Set|Master/Slave Set|Primary/Secondary Set):\s+(\S+)\s+\[(\S+)\](?:\s+\(([^)]+)\))?",
    )
    .unwrap();
    let resource_group_re =
        crate::cached_regex!(r"(?i)^\*?\s*Resource Group:\s+(\S+):?\s*(?:\(([^)]+)\))?");
    let standalone_re = crate::cached_regex!(r"^\*\s+\S+");
    let exclude_set_re = crate::cached_regex!(r"(?i)Resource Group|Clone Set|Master/Slave Set");
    let crm_primitive_re = crate::cached_regex!(r"^primitive\s+(\S+)\s+(\S+):(\S+):(\S+)");
    let mon_re = Regex::new(
        r"^\*?\s*(\S+)\s+\((\S+)::(\S+):(\S+)\):\s+(\w+)(?:\s+(\S+))?(?:\s+\(([^)]+)\))?",
    )
    .unwrap();
    let stonith_mon_re = Regex::new(
        r"^\*?\s*(\S+)\s+\((\S+):(\S+)/(\S+)\):\s+(\w+)(?:\s+(\S+))?(?:\s+\(([^)]+)\))?",
    )
    .unwrap();
    let status_alt_re = crate::cached_regex!(r"^(\S+)\s+\((\S+):(\S+):(\S+)\):\s+(\w+)\s+(\S+)");

    for line in &content_lines {
        let trimmed = line.trim();

        if trimmed == "Resources:" || trimmed == "Full List of Resources:" {
            in_pcs_resources = true;
            in_pcs_constraints = false;
            continue;
        }
        if pcs_section_other_re.is_match(trimmed) {
            in_pcs_resources = false;
            if trimmed.contains("Constraints:") {
                in_pcs_constraints = true;
            }
            continue;
        }

        // pcs_config Resource:
        if in_pcs_resources {
            if let Some(c) = pcs_resource_re.captures(trimmed) {
                let name = c.get(1).unwrap().as_str().to_string();
                let cls = c.get(2).unwrap().as_str().to_string();
                let provider = c
                    .get(3)
                    .map(|m| m.as_str().to_string())
                    .unwrap_or_else(|| "heartbeat".to_string());
                let kind = c.get(4).unwrap().as_str().to_string();
                resources.push(PacemakerResource {
                    name: name.clone(),
                    kind,
                    provider,
                    class_field: cls,
                    format: "pcs_config".to_string(),
                    node: None,
                    status: None,
                    maintenance: false,
                    group_member: current_group.is_some(),
                    group_name: current_group.clone(),
                    clone_member: current_clone.is_some(),
                    clone_name: current_clone.clone(),
                    location_score: None,
                });
                if let Some(gn) = &current_group {
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == gn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                        }
                    }
                } else if let Some(cn) = &current_clone {
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == cn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                        }
                    }
                }
                continue;
            }
            if let Some(c) = pcs_group_re.captures(trimmed) {
                let group_name = c.get(1).unwrap().as_str().to_string();
                current_group = Some(group_name.clone());
                current_clone = None;
                if !group_data.iter().any(|g| g.name == group_name) {
                    group_data.push(ResourceGroup {
                        name: group_name,
                        kind: "group".to_string(),
                        members: Vec::new(),
                        node: None,
                        status: None,
                        maintenance: false,
                    });
                }
                continue;
            }
            if let Some(c) = pcs_clone_re.captures(trimmed) {
                let clone_name = c.get(1).unwrap().as_str().to_string();
                current_clone = Some(clone_name.clone());
                current_group = None;
                if !group_data.iter().any(|g| g.name == clone_name) {
                    group_data.push(ResourceGroup {
                        name: clone_name,
                        kind: "clone".to_string(),
                        members: Vec::new(),
                        node: None,
                        status: None,
                        maintenance: false,
                    });
                }
                continue;
            }
        }

        // pcs_status format
        if pcs_status_marker_re.is_match(trimmed) {
            if let Some(c) = pcs_status_re.captures(trimmed) {
                let name = c.get(1).unwrap().as_str().to_string();
                let type_string = c.get(2).unwrap().as_str().to_string();
                let status = c.get(3).unwrap().as_str().to_string();
                let node = c.get(4).map(|m| m.as_str().to_string());

                let (cls, provider, kind) = if type_string.contains("::") {
                    let parts: Vec<&str> = type_string.splitn(3, ':').collect();
                    let cls = parts.first().copied().unwrap_or("").to_string();
                    let provider = parts.get(1).copied().unwrap_or("").replace(":", "");
                    let kind = parts.get(2).copied().unwrap_or("").to_string();
                    (cls, provider, kind)
                } else if type_string.contains(':') {
                    let mut sp = type_string.splitn(2, ':');
                    let cls = sp.next().unwrap_or("").to_string();
                    let kind = sp.next().unwrap_or("").to_string();
                    (cls, "heartbeat".to_string(), kind)
                } else {
                    ("ocf".to_string(), "heartbeat".to_string(), type_string.clone())
                };

                if let Some(existing) = resources.iter_mut().find(|r| r.name == name) {
                    existing.node = node.clone();
                    existing.status = Some(status);
                } else {
                    resources.push(PacemakerResource {
                        name,
                        kind,
                        provider,
                        class_field: cls,
                        format: "pcs_status".to_string(),
                        node,
                        status: Some(status),
                        maintenance: false,
                        group_member: current_group.is_some(),
                        group_name: current_group.clone(),
                        clone_member: false,
                        clone_name: None,
                        location_score: None,
                    });
                }
                continue;
            }
        }

        // pcs constraints
        if in_pcs_constraints {
            if let Some(c) = pcs_order_re.captures(trimmed) {
                let first_action = c.get(1).unwrap().as_str().to_string();
                let first_resource = c.get(2).unwrap().as_str().to_string();
                let then_action = c.get(3).unwrap().as_str().to_string();
                let then_resource = c.get(4).unwrap().as_str().to_string();
                let kind = c.get(5).unwrap().as_str().to_string();
                let id = c
                    .get(6)
                    .map(|m| m.as_str().to_string())
                    .unwrap_or_else(|| format!("order-{}-{}", first_resource, then_resource));
                constraints.push(PacemakerConstraint {
                    id,
                    kind: "order".to_string(),
                    first_resource: Some(first_resource),
                    first_action: Some(first_action),
                    then_resource: Some(then_resource),
                    then_action: Some(then_action),
                    kind_field: Some(kind),
                    ..Default::default()
                });
                continue;
            }
            if let Some(c) = pcs_coloc_re.captures(trimmed) {
                let resource = c.get(1).unwrap().as_str().to_string();
                let with_resource = c.get(2).unwrap().as_str().to_string();
                let score = c.get(3).unwrap().as_str().to_string();
                constraints.push(PacemakerConstraint {
                    id: format!("colocation-{}-{}", resource, with_resource),
                    kind: "colocation".to_string(),
                    resource: Some(resource),
                    with_resource: Some(with_resource),
                    score: Some(score),
                    ..Default::default()
                });
                continue;
            }
        }

        // Clone Set / Master/Slave / Primary/Secondary
        if let Some(c) = clone_set_re.captures(trimmed) {
            let clone_name = c.get(1).unwrap().as_str().to_string();
            let attributes = c.get(3).map(|m| m.as_str()).unwrap_or("");
            let is_maintenance = attributes.contains("maintenance");
            current_clone = Some(clone_name.clone());
            if !group_data.iter().any(|g| g.name == clone_name) {
                let kind = if trimmed.to_lowercase().contains("master") {
                    "master-slave"
                } else {
                    "clone"
                };
                group_data.push(ResourceGroup {
                    name: clone_name,
                    kind: kind.to_string(),
                    members: Vec::new(),
                    node: None,
                    status: if is_maintenance {
                        Some("maintenance".to_string())
                    } else {
                        None
                    },
                    maintenance: is_maintenance,
                });
            }
            continue;
        }

        // Resource Group
        if let Some(c) = resource_group_re.captures(trimmed) {
            let group_name = c.get(1).unwrap().as_str().trim_end_matches(':').to_string();
            let attributes = c.get(2).map(|m| m.as_str()).unwrap_or("");
            let is_maintenance = attributes.contains("maintenance");
            current_group = Some(group_name.clone());
            current_clone = None;
            if !group_data.iter().any(|g| g.name == group_name) {
                group_data.push(ResourceGroup {
                    name: group_name,
                    kind: "group".to_string(),
                    members: Vec::new(),
                    node: None,
                    status: if is_maintenance {
                        Some("maintenance".to_string())
                    } else {
                        None
                    },
                    maintenance: is_maintenance,
                });
            }
            continue;
        }

        // Reset on top-level standalone
        if standalone_re.is_match(trimmed) && !exclude_set_re.is_match(trimmed) {
            // Top-level lines have less than 2 leading spaces
            if !line.starts_with("  ") {
                current_group = None;
                current_clone = None;
            }
        }

        // crm primitive
        if let Some(c) = crm_primitive_re.captures(trimmed) {
            let name = c.get(1).unwrap().as_str().to_string();
            let cls = c.get(2).unwrap().as_str().to_string();
            let provider = c.get(3).unwrap().as_str().to_string();
            let kind = c.get(4).unwrap().as_str().to_string();
            resources.push(PacemakerResource {
                name,
                kind,
                provider,
                class_field: cls,
                format: "crm".to_string(),
                node: None,
                status: None,
                maintenance: false,
                group_member: false,
                group_name: None,
                clone_member: false,
                clone_name: None,
                location_score: None,
            });
            continue;
        }

        // crm_mon
        if let Some(c) = mon_re.captures(trimmed) {
            let name = c.get(1).unwrap().as_str().to_string();
            let cls = c.get(2).unwrap().as_str().to_string();
            let provider = c.get(3).unwrap().as_str().to_string();
            let kind = c.get(4).unwrap().as_str().to_string();
            let status = c.get(5).unwrap().as_str().to_string();
            let node = c.get(6).map(|m| m.as_str().to_string());
            let attributes = c.get(7).map(|m| m.as_str()).unwrap_or("");
            let is_maintenance = attributes.contains("maintenance");

            if let Some(existing) = resources.iter_mut().find(|r| r.name == name) {
                existing.node = node.clone();
                existing.status = Some(status);
                existing.maintenance = is_maintenance;
                if let Some(gn) = &current_group {
                    existing.group_member = true;
                    existing.group_name = Some(gn.clone());
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == gn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                            if g.node.is_none() {
                                g.node = node.clone();
                            }
                        }
                    }
                } else if let Some(cn) = &current_clone {
                    existing.clone_member = true;
                    existing.clone_name = Some(cn.clone());
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == cn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                        }
                    }
                }
            } else {
                let r = PacemakerResource {
                    name: name.clone(),
                    kind,
                    provider,
                    class_field: cls,
                    format: "crm_mon".to_string(),
                    node: node.clone(),
                    status: Some(status),
                    maintenance: is_maintenance,
                    group_member: current_group.is_some(),
                    group_name: current_group.clone(),
                    clone_member: current_clone.is_some(),
                    clone_name: current_clone.clone(),
                    location_score: None,
                };
                resources.push(r);
                if let Some(gn) = &current_group {
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == gn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                            if g.node.is_none() {
                                g.node = node.clone();
                            }
                        }
                    }
                } else if let Some(cn) = &current_clone {
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == cn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                        }
                    }
                }
            }
            continue;
        }

        // stonith mon (slash-separated agent)
        if let Some(c) = stonith_mon_re.captures(trimmed) {
            let name = c.get(1).unwrap().as_str().to_string();
            let kind_class = c.get(2).unwrap().as_str().to_string();
            let provider = c.get(3).unwrap().as_str().to_string();
            let agent = c.get(4).unwrap().as_str().to_string();
            let status = c.get(5).unwrap().as_str().to_string();
            let node = c.get(6).map(|m| m.as_str().to_string());
            let attributes = c.get(7).map(|m| m.as_str()).unwrap_or("");
            let is_maintenance = attributes.contains("maintenance");

            if let Some(existing) = resources.iter_mut().find(|r| r.name == name) {
                existing.node = node.clone();
                existing.status = Some(status);
                existing.maintenance = is_maintenance;
                if let Some(gn) = &current_group {
                    existing.group_member = true;
                    existing.group_name = Some(gn.clone());
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == gn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                            if g.node.is_none() {
                                g.node = node.clone();
                            }
                        }
                    }
                } else if let Some(cn) = &current_clone {
                    existing.clone_member = true;
                    existing.clone_name = Some(cn.clone());
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == cn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                        }
                    }
                }
            } else {
                let r = PacemakerResource {
                    name: name.clone(),
                    kind: agent,
                    provider,
                    class_field: kind_class,
                    format: "crm_mon_stonith".to_string(),
                    node: node.clone(),
                    status: Some(status),
                    maintenance: is_maintenance,
                    group_member: current_group.is_some(),
                    group_name: current_group.clone(),
                    clone_member: current_clone.is_some(),
                    clone_name: current_clone.clone(),
                    location_score: None,
                };
                resources.push(r);
                if let Some(gn) = &current_group {
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == gn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                            if g.node.is_none() {
                                g.node = node.clone();
                            }
                        }
                    }
                } else if let Some(cn) = &current_clone {
                    if let Some(g) = group_data.iter_mut().find(|g| &g.name == cn) {
                        if !g.members.iter().any(|m| m == &name) {
                            g.members.push(name.clone());
                        }
                    }
                }
            }
            continue;
        }

        // alt status format
        if let Some(c) = status_alt_re.captures(trimmed) {
            let name = c.get(1).unwrap().as_str().to_string();
            let cls = c.get(2).unwrap().as_str().to_string();
            let provider = c.get(3).unwrap().as_str().to_string();
            let kind = c.get(4).unwrap().as_str().to_string();
            let status = c.get(5).unwrap().as_str().to_string();
            let node = c.get(6).map(|m| m.as_str().to_string());
            if let Some(existing) = resources.iter_mut().find(|r| r.name == name) {
                existing.node = node;
                existing.status = Some(status);
            } else {
                resources.push(PacemakerResource {
                    name,
                    kind,
                    provider,
                    class_field: cls,
                    format: "status".to_string(),
                    node,
                    status: Some(status),
                    maintenance: false,
                    group_member: false,
                    group_name: None,
                    clone_member: false,
                    clone_name: None,
                    location_score: None,
                });
            }
            continue;
        }
    }

    if resources.is_empty() {
        return PacemakerResourcesResult {
            found: false,
            ..Default::default()
        };
    }

    // Failed Resource Actions
    let mut failed_actions: Vec<FailedAction> = Vec::new();
    let mut in_failed = false;
    let next_section_re = crate::cached_regex!(r"^(Node Attributes|Migration Summary|Tickets):");
    let fail_re =
        crate::cached_regex!(r"^\*\s+(\S+)\s+on\s+(\S+)\s+'([^']+)'\s+\((\d+)\):\s+(.+)");

    for line in &content_lines {
        let trimmed = line.trim();
        if trimmed == "Failed Resource Actions:" || trimmed == "Failed Actions:" {
            in_failed = true;
            continue;
        }
        if in_failed {
            if trimmed.is_empty()
                || (trimmed.chars().next().map(|c| c.is_ascii_uppercase()).unwrap_or(false)
                    && next_section_re.is_match(trimmed))
            {
                if next_section_re.is_match(trimmed) {
                    in_failed = false;
                }
                continue;
            }
            if trimmed.starts_with('*') {
                if let Some(c) = fail_re.captures(trimmed) {
                    failed_actions.push(FailedAction {
                        action: c.get(1).unwrap().as_str().to_string(),
                        node: c.get(2).unwrap().as_str().to_string(),
                        state: c.get(3).unwrap().as_str().to_string(),
                        return_code: c.get(4).unwrap().as_str().to_string(),
                        details: c.get(5).unwrap().as_str().to_string(),
                    });
                }
            }
        }
    }

    let count = resources.len();
    let groups_count = group_data.len();
    let constraints_count = constraints.len();
    let failed_actions_count = failed_actions.len();
    PacemakerResourcesResult {
        found: true,
        resources,
        count,
        groups: group_data,
        groups_count,
        constraints,
        constraints_count,
        failed_actions,
        failed_actions_count,
    }
}

// ============================================================================
// JSON wrappers for the 5 XML parsers
// ============================================================================

pub fn parse_cluster_nodes_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_cluster_nodes(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_fencing_config_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_fencing_config(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_azure_scheduled_events_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_azure_scheduled_events(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_sap_instance_config_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_sap_instance_config(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_pacemaker_resources_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_pacemaker_resources(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const HIGH_CPU_PATH: &str = "var/log/pacemaker/pacemaker.log";
    const STATUS_PATH: &str = "sos_commands/pacemaker/crm_mon_-1";
    const COROSYNC_PATH: &str = "etc/corosync/corosync.conf";
    const EVENTS_PATH: &str = "var/log/messages";
    const CIB_PATH: &str = "var/lib/pacemaker/cib/cib.xml";

    #[test]
    fn detects_high_cpu_event() {
        let input = "Jan 10 12:23:45 node01 pacemaker-controld[2404]: notice: High CPU load detected: 23.270000\n";
        let result = parse_pacemaker_high_cpu(input, HIGH_CPU_PATH);

        assert_eq!(result.len(), 1);
        assert_eq!(result[0].source_node, "node01");
        assert!((result[0].cpu_load - 23.27).abs() < 0.0001);
    }

    #[test]
    fn high_cpu_records_carry_source_provenance() {
        let input = concat!(
            "Jan 10 12:23:45 node01 pacemaker-controld[2404]: notice: High CPU load detected: 23.27\n",
            "Jan 10 12:23:46 node01 pacemaker-controld[2404]: notice: High CPU load detected: 25.10\n",
        );
        let result = parse_pacemaker_high_cpu(input, HIGH_CPU_PATH);
        assert_eq!(result.len(), 2);
        assert_eq!(result[0].source_path, HIGH_CPU_PATH);
        assert_eq!(result[0].source_line, Some(1));
        assert_eq!(result[1].source_line, Some(2));
    }

    #[test]
    fn parses_cluster_status_from_text() {
        let input = "Cluster name: hacluster\nCurrent DC: node1\n2 nodes configured\n5 resource instances configured\nOnline: [ node1 ]\nOffline: [ node2 ]\n";
        let result = parse_cluster_status(input, STATUS_PATH);

        assert!(result.found);
        assert_eq!(result.cluster_name.as_deref(), Some("hacluster"));
        assert_eq!(result.dc_node.as_deref(), Some("node1"));
        assert_eq!(result.nodes_configured, Some(2));
        assert_eq!(result.resources_configured, Some(5));
        assert_eq!(result.node_statuses.len(), 2);
    }

    #[test]
    fn cluster_status_records_carry_source_provenance() {
        let input = "Cluster name: hacluster\nCurrent DC: node1\nOnline: [ node1 ]\nOffline: [ node2 ]\n";
        let result = parse_cluster_status(input, STATUS_PATH);
        assert_eq!(result.source_path, STATUS_PATH);
        for n in &result.node_statuses {
            assert_eq!(n.source_path, STATUS_PATH);
            assert!(n.source_line.is_some());
        }
        // node1 came from line 3 (Online), node2 from line 4 (Offline)
        let n1 = result.node_statuses.iter().find(|n| n.name == "node1").unwrap();
        let n2 = result.node_statuses.iter().find(|n| n.name == "node2").unwrap();
        assert_eq!(n1.source_line, Some(3));
        assert_eq!(n2.source_line, Some(4));
    }

    #[test]
    fn parses_corosync_config_and_warnings() {
        let input = "totem {\n  token: 10000\n  token_retransmits_before_loss_const: 5\n  join: 30\n  consensus: 12000\n  max_messages: 17\n  transport: udp\n}\nquorum {\n  provider: corosync_bad\n  expected_votes: 3\n  two_node: 0\n}\n";
        let result = parse_corosync_config(input, COROSYNC_PATH);

        assert!(result.found);
        assert_eq!(result.totem_token, Some(10000));
        assert_eq!(result.quorum_provider.as_deref(), Some("corosync_bad"));
        assert!(!result.warnings.is_empty());
    }

    #[test]
    fn corosync_warnings_carry_source_provenance() {
        let input = "totem {\n  token: 10000\n  token_retransmits_before_loss_const: 5\n  join: 30\n  consensus: 12000\n  max_messages: 17\n  transport: udp\n}\nquorum {\n  provider: corosync_bad\n  expected_votes: 3\n  two_node: 0\n}\n";
        let result = parse_corosync_config(input, COROSYNC_PATH);
        assert_eq!(result.source_path, COROSYNC_PATH);
        for w in &result.warnings {
            assert_eq!(w.source_path, COROSYNC_PATH);
            assert!(w.source_line.is_some(), "warning missing source_line: {:?}", w);
        }
        // The token warning must point at line 2 where `token: 10000` lives.
        let token_warn = result
            .warnings
            .iter()
            .find(|w| w.parameter.as_deref() == Some("totem.token"))
            .expect("token warning");
        assert_eq!(token_warn.source_line, Some(2));
        let provider_warn = result
            .warnings
            .iter()
            .find(|w| w.parameter.as_deref() == Some("quorum.provider"))
            .expect("provider warning");
        assert_eq!(provider_warn.source_line, Some(10));
    }

    #[test]
    fn parses_cluster_events_and_fencing() {
        let input = concat!(
            "Jan 10 12:23:45 node01 pacemaker-controld[2404]: notice: High CPU load detected: 23.270000\n",
            "Jan 10 12:24:00 node01 pacemaker-controld[2404]: notice: Moving resource vip from node01 to node02\n",
            "Jan 10 12:24:30 node01 pacemaker-fenced[1111]: notice: Requesting fencing (reboot) of node node02\n"
        );
        let result = parse_cluster_events(input, EVENTS_PATH);

        assert!(result.found);
        assert_eq!(result.resource_migrations.len(), 2);
        assert_eq!(result.fencing_events.len(), 1);
        assert_eq!(result.total_events, 3);
    }

    #[test]
    fn cluster_events_records_carry_source_provenance() {
        let input = concat!(
            "Jan 10 12:23:45 node01 pacemaker-controld[2404]: notice: High CPU load detected: 23.27\n",
            "Jan 10 12:24:00 node01 pacemaker-controld[2404]: notice: Moving resource vip from node01 to node02\n",
            "Jan 10 12:24:30 node01 pacemaker-fenced[1111]: notice: Requesting fencing (reboot) of node node02\n"
        );
        let result = parse_cluster_events(input, EVENTS_PATH);
        assert_eq!(result.source_path, EVENTS_PATH);
        assert_eq!(result.resource_migrations[0].source_line, Some(1));
        assert_eq!(result.resource_migrations[1].source_line, Some(2));
        assert_eq!(result.fencing_events[0].source_line, Some(3));
        for e in &result.resource_migrations {
            assert_eq!(e.source_path, EVENTS_PATH);
        }
        for e in &result.fencing_events {
            assert_eq!(e.source_path, EVENTS_PATH);
        }
    }

    #[test]
    fn detects_cluster_maintenance_mode() {
        let input = concat!(
            "<nvpair name=\"maintenance-mode\" value=\"true\"/>\n",
            "Resource: vip_dummy (maintenance)\n"
        );
        let result = parse_cluster_maintenance_mode(input, CIB_PATH);

        assert!(result.found);
        assert_eq!(result.maintenance_mode, Some(true));
        assert_eq!(result.resources_in_maintenance, vec!["vip_dummy".to_string()]);
        assert!(!result.warnings.is_empty());
    }

    #[test]
    fn cluster_maintenance_warnings_carry_source_provenance() {
        let input = concat!(
            "<nvpair name=\"maintenance-mode\" value=\"true\"/>\n",
            "Resource: vip_dummy (maintenance)\n"
        );
        let result = parse_cluster_maintenance_mode(input, CIB_PATH);
        assert_eq!(result.source_path, CIB_PATH);
        for w in &result.warnings {
            assert_eq!(w.source_path, CIB_PATH);
            assert!(w.source_line.is_some(), "warning missing source_line: {:?}", w);
        }
        let cluster_warn = result.warnings.iter().find(|w| w.kind == "cluster_in_maintenance").expect("cluster warn");
        assert_eq!(cluster_warn.source_line, Some(1));
        let res_warn = result.warnings.iter().find(|w| w.kind == "resources_in_maintenance").expect("res warn");
        assert_eq!(res_warn.source_line, Some(2));
    }

    #[test]
    fn cluster_json_wrappers_include_source_path() {
        let json = parse_corosync_config_json("totem {\n  token: 10000\n}\n", COROSYNC_PATH);
        assert!(json.contains("\"source_path\":\"etc/corosync/corosync.conf\""));
    }
}
