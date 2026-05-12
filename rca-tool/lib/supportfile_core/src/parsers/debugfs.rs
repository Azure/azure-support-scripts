use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HvBalloonResult {
    pub found: bool,
    pub host_version: Option<String>,
    pub capabilities: Option<String>,
    pub state: Option<i64>,
    pub state_text: Option<String>,
    pub page_size: i64,
    pub pages_added: i64,
    pub pages_onlined: i64,
    pub pages_ballooned: i64,
    pub total_pages_committed: i64,
    pub max_dynamic_page_count: i64,
    pub committed_memory_gb: f64,
    pub max_dynamic_memory_gb: f64,
    pub ballooned_memory_mb: f64,
    pub warnings: Vec<String>,
    pub raw_content: String,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ExtfragZone {
    pub node: i64,
    pub zone: String,
    pub extfrag_index: Vec<f64>,
    pub unusable_index: Vec<f64>,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ExtfragResult {
    pub found: bool,
    pub zones: Vec<ExtfragZone>,
    pub warnings: Vec<String>,
    pub raw_content: String,
    pub source_path: String,
}

pub fn parse_hv_balloon(content: &str, source_path: &str) -> HvBalloonResult {
    let mut result = HvBalloonResult {
        found: false,
        host_version: None,
        capabilities: None,
        state: None,
        state_text: None,
        page_size: 4096,
        pages_added: 0,
        pages_onlined: 0,
        pages_ballooned: 0,
        total_pages_committed: 0,
        max_dynamic_page_count: 0,
        committed_memory_gb: 0.0,
        max_dynamic_memory_gb: 0.0,
        ballooned_memory_mb: 0.0,
        warnings: Vec::new(),
        raw_content: String::new(),
        source_path: source_path.to_string(),
    };

    if content.trim().is_empty() {
        return result;
    }

    result.raw_content = content.trim().to_string();
    let pair_re = crate::cached_regex!(r"^(\S+(?:\s+\S+)*?)\s*:\s*(.+)$");

    for line in content.lines() {
        if let Some(caps) = pair_re.captures(line) {
            let key = caps
                .get(1)
                .map(|m| m.as_str().trim().to_ascii_lowercase().replace([' ', '-'], "_"))
                .unwrap_or_default();
            let value = caps.get(2).map(|m| m.as_str().trim()).unwrap_or_default();

            match key.as_str() {
                "host_version" => {
                    result.host_version = Some(value.to_string());
                    result.found = true;
                }
                "capabilities" => result.capabilities = Some(value.to_string()),
                "state" => {
                    if let Some(state_caps) = crate::cached_regex!(r"^(\d+)").captures(value) {
                        result.state = state_caps.get(1).and_then(|m| m.as_str().parse::<i64>().ok());
                    }
                    result.state_text = crate::cached_regex!(r"\(([^)]+)\)")
                        .captures(value)
                        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
                        .or_else(|| match result.state {
                            Some(0) => Some("Not configured".to_string()),
                            Some(1) => Some("Initialized".to_string()),
                            Some(2) => Some("Ready".to_string()),
                            Some(3) => Some("Operating".to_string()),
                            Some(4) => Some("Degraded".to_string()),
                            _ => Some("Unknown".to_string()),
                        });
                }
                "page_size" => result.page_size = value.parse::<i64>().unwrap_or(4096),
                "pages_added" => result.pages_added = value.parse::<i64>().unwrap_or(0),
                "pages_onlined" => result.pages_onlined = value.parse::<i64>().unwrap_or(0),
                "pages_ballooned" => result.pages_ballooned = value.parse::<i64>().unwrap_or(0),
                "total_pages_committed" => result.total_pages_committed = value.parse::<i64>().unwrap_or(0),
                "max_dynamic_page_count" => result.max_dynamic_page_count = value.parse::<i64>().unwrap_or(0),
                _ => {}
            }
        }
    }

    if !result.found {
        return result;
    }

    let bytes_per_gb = 1024_f64 * 1024_f64 * 1024_f64;
    let bytes_per_mb = 1024_f64 * 1024_f64;
    result.committed_memory_gb = ((result.total_pages_committed as f64 * result.page_size as f64) / bytes_per_gb * 100.0).round() / 100.0;
    result.max_dynamic_memory_gb = ((result.max_dynamic_page_count as f64 * result.page_size as f64) / bytes_per_gb * 100.0).round() / 100.0;
    result.ballooned_memory_mb = ((result.pages_ballooned as f64 * result.page_size as f64) / bytes_per_mb * 100.0).round() / 100.0;

    if result.pages_ballooned > 0 {
        result.warnings.push(format!(
            "Ballooning active: host is reclaiming {} MB from the guest. This can cause memory pressure and allocation failures.",
            result.ballooned_memory_mb
        ));
    }

    if result.max_dynamic_page_count > 0 && result.total_pages_committed > 0 {
        let usage_ratio = result.total_pages_committed as f64 / result.max_dynamic_page_count as f64;
        if usage_ratio > 0.9 {
            result.warnings.push(format!(
                "Memory near capacity: {} GB committed of {} GB maximum ({}%).",
                result.committed_memory_gb,
                result.max_dynamic_memory_gb,
                (usage_ratio * 100.0).round() as i64
            ));
        }
    }

    result
}

pub fn parse_extfrag(content: &str, source_path: &str) -> ExtfragResult {
    let mut result = ExtfragResult {
        found: false,
        zones: Vec::new(),
        warnings: Vec::new(),
        raw_content: content.trim().to_string(),
        source_path: source_path.to_string(),
    };

    if content.trim().is_empty() {
        return result;
    }

    let line_re = crate::cached_regex!(r"^Node\s+(\d+),\s+zone\s+(\S+)\s+(.+)$");
    let mut current_field = if content.contains("unusable_index") {
        "unusable"
    } else {
        "extfrag"
    };

    for (line_idx, line) in content.lines().enumerate() {
        let line_no = line_idx + 1;
        let trimmed = line.trim();
        if trimmed.starts_with("===") {
            let lower = trimmed.to_ascii_lowercase();
            if lower.contains("extfrag_index") {
                current_field = "extfrag";
            } else if lower.contains("unusable_index") {
                current_field = "unusable";
            }
            continue;
        }

        if let Some(caps) = line_re.captures(trimmed) {
            let node = caps.get(1).and_then(|m| m.as_str().parse::<i64>().ok()).unwrap_or(0);
            let zone_name = caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_default();
            let values = caps
                .get(3)
                .map(|m| {
                    m.as_str()
                        .split_whitespace()
                        .filter_map(|v| v.parse::<f64>().ok())
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();

            let idx = result
                .zones
                .iter()
                .position(|z| z.node == node && z.zone == zone_name)
                .unwrap_or_else(|| {
                    result.zones.push(ExtfragZone {
                        node,
                        zone: zone_name.clone(),
                        extfrag_index: Vec::new(),
                        unusable_index: Vec::new(),
                        source_path: source_path.to_string(),
                        source_line: Some(line_no),
                    });
                    result.zones.len() - 1
                });

            if current_field == "extfrag" {
                result.zones[idx].extfrag_index = values;
            } else {
                result.zones[idx].unusable_index = values;
            }
            result.found = true;
        }
    }

    let order_labels = ["4K", "8K", "16K", "32K", "64K", "128K", "256K", "512K", "1M", "2M", "4M"];
    for zone in &result.zones {
        for ord in 9..zone.unusable_index.len() {
            let val = zone.unusable_index[ord];
            if val > 0.5 {
                let severity = if val > 0.8 { "Severe" } else { "Moderate" };
                let label = order_labels.get(ord).copied().unwrap_or("high order");
                result.warnings.push(format!(
                    "{} fragmentation on Node {} zone {} at {} (order {}): unusable index {:.3}. Huge page allocations may fail.",
                    severity, zone.node, zone.zone, label, ord, val
                ));
            }
        }
        for ord in 9..zone.extfrag_index.len() {
            let val = zone.extfrag_index[ord];
            if val > 0.7 && val <= 1.0 {
                let label = order_labels.get(ord).copied().unwrap_or("high order");
                result.warnings.push(format!(
                    "High external fragmentation on Node {} zone {} at {} (order {}): extfrag index {:.3}. Memory compaction may help.",
                    zone.node, zone.zone, label, ord, val
                ));
            }
        }
    }

    result
}

pub fn parse_hv_balloon_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_hv_balloon(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_extfrag_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_extfrag(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_hv_balloon_and_warnings() {
        let input = concat!(
            "host version : 6.3\n",
            "state : 3 (Operating)\n",
            "page_size : 4096\n",
            "pages_ballooned : 1024\n",
            "total_pages_committed : 950000\n",
            "max_dynamic_page_count : 1000000\n"
        );
        let result = parse_hv_balloon(input, "sys/kernel/debug/hv-balloon");
        assert!(result.found);
        assert_eq!(result.state, Some(3));
        assert_eq!(result.source_path, "sys/kernel/debug/hv-balloon");
        assert!(result.warnings.len() >= 2);
    }

    #[test]
    fn parses_extfrag_and_unusable_sections() {
        let input = concat!(
            "=== extfrag_index ===\n",
            "Node 0, zone Normal 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.91 0.85\n",
            "=== unusable_index ===\n",
            "Node 0, zone Normal 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.92 0.81\n"
        );
        let result = parse_extfrag(input, "sys/kernel/debug/extfrag/extfrag_index");
        assert!(result.found);
        assert_eq!(result.zones.len(), 1);
        assert_eq!(result.zones[0].source_path, "sys/kernel/debug/extfrag/extfrag_index");
        assert_eq!(result.zones[0].source_line, Some(2));
        assert!(!result.warnings.is_empty());
    }
}
