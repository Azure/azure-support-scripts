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
        iptables: TableRulesInfo { detected: false, rules: Vec::new(), modules: Vec::new(), config: None },
        ip6tables: TableRulesInfo { detected: false, rules: Vec::new(), modules: Vec::new(), config: None },
        ebtables: EbtablesInfo { detected: false, config: None },
        nftables: NftablesInfo { detected: false, ruleset: None, tables: None },
        active_firewall: "none".to_string(),
        warnings: Vec::new(),
        raw_sections: BTreeMap::new(),
        source_path: source_path.to_string(),
    };

    let trimmed = content.trim();
    if trimmed.is_empty() {
        return result;
    }

    if trimmed.contains("firewalld") || trimmed.contains("firewall-cmd") || trimmed.contains("FirewallBackend") {
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

        if let Some(caps) = crate::cached_regex!(r"(?m)^FirewallBackend\s*=\s*(.+)$").captures(trimmed) {
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
    let nft_table_re = crate::cached_regex!(r"(?m)^\s*table\s+(?:inet|ip|ip6|arp|bridge|netdev)\s+\S+\s*\{");
    let has_nft_table = nft_table_re.is_match(trimmed);
    if has_nft_table {
        result.nftables.detected = true;
        result.nftables.ruleset = Some(trimmed.to_string());
        result.raw_sections.insert("nft -a list ruleset".to_string(), trimmed.to_string());
        result.found = true;
    }

    if trimmed.contains("Chain INPUT") {
        result.iptables.detected = true;
        result.iptables.rules.push(trimmed.to_string());
        result.found = true;
    }
    // Capture missing-module notices regardless of whether rules were found.
    if let Some(caps) = crate::cached_regex!(r"The\s+(\S+)\s+module is not loaded").captures(trimmed) {
        if let Some(module) = caps.get(1).map(|m| m.as_str().to_string()) {
            result.iptables.modules.push(module);
        }
    }

    if trimmed.contains("ip6tables") || trimmed.contains("Chain FORWARD") && trimmed.contains("v6") {
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
    serde_json::to_string(&parse_firewall_rules(content, source_path)).unwrap_or_else(|_| "{}".to_string())
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
        let w = result.warnings.iter().find(|w| w.kind == "firewalld_not_running").expect("warn");
        assert_eq!(w.source_path, PATH);
        assert_eq!(w.source_line, Some(3));
    }

    #[test]
    fn firewall_json_wrapper_includes_source_path() {
        let input = "FirewallD is not running\n";
        let json = parse_firewall_rules_json(input, PATH);
        assert!(json.contains("\"source_path\":\"sos_commands/firewalld/firewall-cmd_--list-all-zones\""));
    }
}
