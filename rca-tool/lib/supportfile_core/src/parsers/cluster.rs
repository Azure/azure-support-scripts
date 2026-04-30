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
        Regex::new(r"^(?i)(tty\d*|pts/?\d*|console|localhost|127\.0\.0\.1|::1|\d+)$").unwrap()
    })
    .is_match(node)
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

            if let Some(v) = Regex::new(r"^token\s*:\s*(\d+)").unwrap().captures(line) {
                result.totem_token = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.token", line_no);
            }
            if let Some(v) = Regex::new(r"^token_retransmits_before_loss_const\s*:\s*(\d+)").unwrap().captures(line) {
                result.totem_retransmits = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.token_retransmits_before_loss_const", line_no);
            }
            if let Some(v) = Regex::new(r"^join\s*:\s*(\d+)").unwrap().captures(line) {
                result.totem_join = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.join", line_no);
            }
            if let Some(v) = Regex::new(r"^consensus\s*:\s*(\d+)").unwrap().captures(line) {
                result.totem_consensus = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.consensus", line_no);
            }
            if let Some(v) = Regex::new(r"^max_messages\s*:\s*(\d+)").unwrap().captures(line) {
                result.totem_max_messages = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("totem.max_messages", line_no);
            }
            if let Some(v) = Regex::new(r"^transport\s*:\s*(\w+)").unwrap().captures(line) {
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

            if let Some(v) = Regex::new(r"^provider\s*:\s*(\w+)").unwrap().captures(line) {
                result.quorum_provider = v.get(1).map(|m| m.as_str().to_string());
                lines_for.insert("quorum.provider", line_no);
            }
            if let Some(v) = Regex::new(r"^expected_votes\s*:\s*(\d+)").unwrap().captures(line) {
                result.quorum_expected_votes = v.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                lines_for.insert("quorum.expected_votes", line_no);
            }
            if let Some(v) = Regex::new(r"^two_node\s*:\s*(\d+)").unwrap().captures(line) {
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

    if let Some(caps) = Regex::new(r#"name=["']cluster-name["']\s+value=["']([^"']+)["']"#).unwrap().captures(content) {
        result.cluster_name = caps.get(1).map(|m| m.as_str().to_string());
        result.found = true;
    }
    if let Some(caps) = Regex::new(r#"have-quorum=["']([01])["']"#).unwrap().captures(content) {
        result.quorum_status = Some(if caps.get(1).map(|m| m.as_str()) == Some("1") {
            "with quorum".to_string()
        } else {
            "without quorum".to_string()
        });
        result.found = true;
    }
    if let Some(caps) = Regex::new(r#"<current_dc[^>]+(?:name|uname)=["']([^"']+)["'][^>]*with_quorum=["'](true|false)["']"#).unwrap().captures(content) {
        result.dc_node = caps.get(1).map(|m| m.as_str().to_string());
        result.quorum_status = Some(if caps.get(2).map(|m| m.as_str()) == Some("true") {
            "with quorum".to_string()
        } else {
            "without quorum".to_string()
        });
        result.found = true;
    }

    let cluster_name_re = Regex::new(r"(?i)^Cluster name:\s+(.+)$").unwrap();
    let stack_re = Regex::new(r"(?i)^Stack:\s+(\w+)").unwrap();
    let dc_re = Regex::new(r"(?i)^Current DC:\s+([^\s]+)").unwrap();
    let last_re = Regex::new(r"(?i)^Last updated:\s+(.+)$").unwrap();
    let nodes_cfg_re = Regex::new(r"(?i)(\d+)\s+nodes?\s+configured").unwrap();
    let res_cfg_re = Regex::new(r"(?i)(\d+)\s+resource(?:\s+instances?)?\s+configured").unwrap();
    let online_re = Regex::new(r"(?i)Online:\s*\[\s*([^\]]+)\s*\]").unwrap();
    let offline_re = Regex::new(r"(?i)Offline:\s*\[\s*([^\]]+)\s*\]").unwrap();
    let node_re = Regex::new(r"(?i)\*?\s*Node\s+([^\s:]+)[^:]*:\s*(\w+)").unwrap();

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
    let move_re = Regex::new(r"(?i)(?:Moving|Migrating)\s+(?:resource\s+)?(\S+)\s+from\s+(\S+)\s+to\s+(\S+)").unwrap();
    let start_re = Regex::new(r"(?i)(?:Starting|Transition.*Starting)\s+(\S+)\s+on\s+(\S+)").unwrap();
    let stop_re = Regex::new(r"(?i)(?:Stopping|Stopped)\s+(\S+)\s+on\s+(\S+)").unwrap();
    let result_op_re = Regex::new(r"(?i)Result of (start|stop) operation for (\S+) on (\S+):\s*(\w+)").unwrap();
    let op_re = Regex::new(r"(?i)Operation\s+(\S+?)_(?:start|stop|monitor|migrate)_\d+:\s*\w+\s*\(node=(\S+)\)").unwrap();
    let high_cpu_re = Regex::new(r"(?i)High CPU load detected:\s*([0-9]+(?:\.[0-9]+)?)").unwrap();
    let fence_request_re = Regex::new(r"(?i)Requesting\s+fencing\s+\((\w+)\)\s+(?:of\s+|targeting\s+)?(?:node\s+)?(\S+)").unwrap();
    let fence_success_re = Regex::new(r"(?i)(?:Fencing|stonith.*?fence)\s+(\S+).*?(?:success|succeeded)").unwrap();
    let peer_term_re = Regex::new(r"(?i)(?:Peer|peer)\s+(\S+)\s+was\s+(?:terminated|fenced)\s+\((\w+)\)").unwrap();
    let peer_not_term_re = Regex::new(r"(?i)(?:Peer|peer)\s+(\S+)\s+was\s+not\s+terminated\s+\((\w+)\)").unwrap();
    let fence_fail_re = Regex::new(r"(?i)(?:Fencing|stonith.*?fence)\s+(\S+).*?(?:fail|error)").unwrap();
    let fence_will_re = Regex::new(r"(?i)(?:Cluster\s+node|Node|peer)\s+(\S+)\s+will\s+be\s+fenced").unwrap();
    let fence_agent_re = Regex::new(r"(?i)(fence_\w+).*?(?:Called|for)\s+.*?(?:node\s+)?(\S+)").unwrap();
    let monitor_failure_re = Regex::new(r"(?i)Unexpected\s+result\s+\((error|failed|timeout|not running):\s*([^)]+)\).*?(?:for\s+(?:monitor|start|stop|promote|demote)\s+of\s+)?(\S+?)(?::(\d+))?\s+on\s+(\S+)").unwrap();
    let timeout_re = Regex::new(r"(?i)(?:Resource agent did not complete within|operation.* timed out after)\s+(\d+)s").unwrap();
    let transition_fail_re = Regex::new(r"(?i)Transition\s+\d+\s+action\s+\d+\s+\(([^)]+)_(?:monitor|start|stop|promote|demote)_\d+\s+on\s+(\S+)\).*?expected\s+'([^']+)'\s+but\s+got\s+'([^']+)'").unwrap();

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
            if !message_text.contains("systemd")
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
            if !message_text.contains("systemd")
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
            if !message_text.contains("systemd")
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
    let mm_re = Regex::new(r#"name=["']maintenance-mode["']\s+value=["'](true|false)["']"#).unwrap();
    let mut maintenance_line: Option<usize> = None;
    let mut disabled_line: Option<usize> = None;
    let resource_re = Regex::new(r"(?i)(?:Resource|Clone Set|Primary/Secondary Set|Resource Group):\s+([^\s(]+).*?\(.*?maintenance.*?\)").unwrap();
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
