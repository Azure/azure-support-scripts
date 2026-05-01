use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AutomationEvent {
    pub timestamp: String,
    pub line_number: usize,
    pub tool_type: String,
    pub pattern_type: String,
    pub command: Option<String>,
    pub raw_line: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AutomationResult {
    pub found: bool,
    pub count: usize,
    pub events: Vec<AutomationEvent>,
    pub source_path: String,
}

fn extract_timestamp(line: &str) -> Option<String> {
    static ISO_RE: OnceLock<Regex> = OnceLock::new();
    static SYSLOG_RE: OnceLock<Regex> = OnceLock::new();
    let iso_re = ISO_RE.get_or_init(|| {
        Regex::new(r"^(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)").unwrap()
    });
    let syslog_re = SYSLOG_RE.get_or_init(|| {
        Regex::new(r"^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)").unwrap()
    });
    iso_re
        .captures(line)
        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
        .or_else(|| syslog_re.captures(line).and_then(|c| c.get(1).map(|m| m.as_str().to_string())))
}

fn strip_ansi_codes(input: &str) -> String {
    static ANSI_RE: OnceLock<Regex> = OnceLock::new();
    let re = ANSI_RE.get_or_init(|| Regex::new(r"\x1B\[[0-9;]*[A-Za-z]").unwrap());
    re.replace_all(input, "").into_owned()
}

pub fn parse_automation_events(content: &str, source_path: &str) -> AutomationResult {
    static ANSIBLE_CMD_RE: OnceLock<Regex> = OnceLock::new();
    static ANSIBLE_SETUP_RE: OnceLock<Regex> = OnceLock::new();
    static PUPPET_AGENT_RE: OnceLock<Regex> = OnceLock::new();
    static PUPPET_APPLY_RE: OnceLock<Regex> = OnceLock::new();
    static PUPPET_RUN_RE: OnceLock<Regex> = OnceLock::new();
    static CHEF_CLIENT_RE: OnceLock<Regex> = OnceLock::new();
    static CHEF_SOLO_RE: OnceLock<Regex> = OnceLock::new();
    static CHEF_APPLY_RE: OnceLock<Regex> = OnceLock::new();

    let ansible_cmd_re =
        ANSIBLE_CMD_RE.get_or_init(|| Regex::new(r"ansible-command:\s*(.+)").unwrap());
    let ansible_setup_re =
        ANSIBLE_SETUP_RE.get_or_init(|| Regex::new(r"ansible-setup:\s*(.+)").unwrap());
    let puppet_agent_re =
        PUPPET_AGENT_RE.get_or_init(|| Regex::new(r"puppet-agent:\s*(.+)").unwrap());
    let puppet_apply_re =
        PUPPET_APPLY_RE.get_or_init(|| Regex::new(r"(puppet apply.+)").unwrap());
    let puppet_run_re =
        PUPPET_RUN_RE.get_or_init(|| Regex::new(r"puppet-run:\s*(.+)").unwrap());
    let chef_client_re =
        CHEF_CLIENT_RE.get_or_init(|| Regex::new(r"chef-client\[\d+\]:\s*(.+)").unwrap());
    let chef_solo_re =
        CHEF_SOLO_RE.get_or_init(|| Regex::new(r"chef-solo\[\d+\]:\s*(.+)").unwrap());
    let chef_apply_re =
        CHEF_APPLY_RE.get_or_init(|| Regex::new(r"chef-apply\[\d+\]:\s*(.+)").unwrap());

    let lines: Vec<&str> = content.lines().collect();
    let mut events = Vec::new();

    for (i, line) in lines.iter().enumerate() {
        if !(line.contains("ansible-") || line.contains("puppet") || line.contains("chef-")) {
            continue;
        }

        let mut tool_type: Option<&str> = None;
        let mut pattern_type: Option<&str> = None;
        let mut command: Option<String> = None;
        let mut end_line = i + 1;

        if let Some(caps) = ansible_cmd_re.captures(line) {
            tool_type = Some("ansible");
            pattern_type = Some("command");
            command = caps.get(1).map(|m| m.as_str().trim().to_string());
        } else if let Some(caps) = ansible_setup_re.captures(line) {
            tool_type = Some("ansible");
            pattern_type = Some("setup");
            command = caps.get(1).map(|m| m.as_str().trim().to_string());
        } else if let Some(caps) = puppet_agent_re.captures(line) {
            tool_type = Some("puppet");
            pattern_type = Some("agent");
            command = caps.get(1).map(|m| m.as_str().trim().to_string());
        } else if let Some(caps) = puppet_run_re.captures(line) {
            tool_type = Some("puppet");
            pattern_type = Some("run");
            command = caps.get(1).map(|m| m.as_str().trim().to_string());
        } else if let Some(caps) = puppet_apply_re.captures(line) {
            tool_type = Some("puppet");
            pattern_type = Some("apply");
            command = caps.get(1).map(|m| m.as_str().trim().to_string());
        } else if let Some(caps) = chef_client_re.captures(line) {
            let message = strip_ansi_codes(caps.get(1).map(|m| m.as_str()).unwrap_or_default().trim());
            if [
                "Starting Chef",
                "Chef Infra Client finished",
                "Chef Run complete",
                "Chef Client finished",
                "Synchronizing Cookbooks",
                "Installing Cookbook Gems",
                "Compiling Cookbooks",
                "Converging",
                "FATAL:",
                "ERROR:",
            ]
            .iter()
            .any(|kw| message.contains(kw))
            {
                tool_type = Some("chef");
                pattern_type = Some("client");
                let mut context = vec![message];
                for j in 1..=5 {
                    if let Some(next_line) = lines.get(i + j) {
                        if let Some(next_caps) = chef_client_re.captures(next_line) {
                            context.push(strip_ansi_codes(next_caps.get(1).map(|m| m.as_str()).unwrap_or_default().trim()));
                            end_line = i + j + 1;
                        } else {
                            break;
                        }
                    }
                }
                command = Some(context.join(" | "));
            }
        } else if let Some(caps) = chef_solo_re.captures(line) {
            let message = strip_ansi_codes(caps.get(1).map(|m| m.as_str()).unwrap_or_default().trim());
            if ["Starting Chef", "Chef Solo finished", "Chef Run complete", "Synchronizing Cookbooks", "Compiling Cookbooks", "Converging", "FATAL:", "ERROR:"]
                .iter()
                .any(|kw| message.contains(kw))
            {
                tool_type = Some("chef");
                pattern_type = Some("solo");
                command = Some(message);
            }
        } else if let Some(caps) = chef_apply_re.captures(line) {
            let message = strip_ansi_codes(caps.get(1).map(|m| m.as_str()).unwrap_or_default().trim());
            if ["Starting Chef", "Chef Apply finished", "Chef Run complete", "Compiling Cookbooks", "Converging", "FATAL:", "ERROR:"]
                .iter()
                .any(|kw| message.contains(kw))
            {
                tool_type = Some("chef");
                pattern_type = Some("apply");
                command = Some(message);
            }
        }

        if let (Some(tool_type), Some(pattern_type)) = (tool_type, pattern_type) {
            events.push(AutomationEvent {
                timestamp: extract_timestamp(line).unwrap_or_else(|| "Date not detected".to_string()),
                line_number: i + 1,
                tool_type: tool_type.to_string(),
                pattern_type: pattern_type.to_string(),
                command,
                raw_line: line.trim().to_string(),
                source_path: source_path.to_string(),
                source_line: Some(i + 1),
                source_line_end: Some(end_line),
            });
        }
    }

    AutomationResult {
        found: !events.is_empty(),
        count: events.len(),
        events,
        source_path: source_path.to_string(),
    }
}

pub fn parse_automation_events_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_automation_events(content, source_path))
        .unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PATH: &str = "var/log/messages";

    #[test]
    fn detects_ansible_and_puppet_events() {
        let content = concat!(
            "Jan 10 12:00:00 node1 root: ansible-command: /usr/bin/ansible-playbook site.yml\n",
            "Jan 10 12:05:00 node1 root: puppet-agent: Applying configuration version 99\n"
        );

        let result = parse_automation_events(content, PATH);
        assert!(result.found);
        assert_eq!(result.count, 2);
        assert_eq!(result.events[0].tool_type, "ansible");
        assert_eq!(result.events[1].tool_type, "puppet");
    }

    #[test]
    fn captures_chef_context() {
        let content = concat!(
            "Jan 10 12:00:00 node1 chef-client[123]: Starting Chef Infra Client\n",
            "Jan 10 12:00:01 node1 chef-client[123]: Compiling Cookbooks...\n",
            "Jan 10 12:00:02 node1 chef-client[123]: Chef Run complete\n"
        );

        let result = parse_automation_events(content, PATH);
        assert!(result.found);
        assert_eq!(result.events[0].tool_type, "chef");
        assert!(result.events[0].command.as_deref().unwrap_or("").contains("Chef Run complete"));
    }

    #[test]
    fn automation_records_carry_source_provenance() {
        let content = concat!(
            "Jan 10 12:00:00 node1 root: ansible-command: /usr/bin/ansible-playbook site.yml\n",
            "Jan 10 12:05:00 node1 root: puppet-agent: Applying configuration version 99\n",
            "Jan 10 12:06:00 node1 chef-client[123]: Starting Chef Infra Client\n",
            "Jan 10 12:06:01 node1 chef-client[123]: Compiling Cookbooks...\n",
        );
        let result = parse_automation_events(content, PATH);
        assert!(result.found);
        assert_eq!(result.source_path, PATH);
        assert_eq!(result.events[0].source_path, PATH);
        assert_eq!(result.events[0].source_line, Some(1));
        assert_eq!(result.events[1].source_line, Some(2));
        // Chef event spans context lines 3-4
        assert_eq!(result.events[2].source_line, Some(3));
        assert_eq!(result.events[2].source_line_end, Some(4));
        for e in &result.events {
            assert_eq!(e.source_path, PATH);
            assert!(e.source_line.is_some());
        }
    }

    #[test]
    fn automation_json_wrapper_includes_source_path() {
        let json = parse_automation_events_json(
            "Jan 10 12:00:00 node1 root: ansible-command: ls\n",
            PATH,
        );
        assert!(json.contains("\"source_path\":\"var/log/messages\""));
        assert!(json.contains("\"source_line\":1"));
    }
}
