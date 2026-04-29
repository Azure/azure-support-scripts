use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;

fn extract_timestamp(line: &str) -> Option<String> {
    let iso_re = Regex::new(r"^(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)").unwrap();
    let syslog_re = Regex::new(r"^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)").unwrap();
    iso_re
        .captures(line)
        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
        .or_else(|| syslog_re.captures(line).and_then(|c| c.get(1).map(|m| m.as_str().to_string())))
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ServiceEvent {
    pub timestamp: String,
    pub line_number: usize,
    pub issue_type: String,
    pub message: String,
    pub raw_line: String,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ServiceEventsResult {
    pub found: bool,
    pub count: usize,
    pub events: Vec<ServiceEvent>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ServiceDetectionResult {
    pub found: bool,
    pub service_name: String,
    pub severity: String,
    pub message: String,
    pub documentation_url: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SecuritySoftwareResult {
    pub found: bool,
    pub software_name: String,
    pub message: String,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ConfigCheckResult {
    pub found: bool,
    pub has_exclusions: bool,
    pub message: String,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InvolfltVersionResult {
    pub found: bool,
    pub loaded: bool,
    pub version: Option<String>,
    pub build_date: Option<String>,
    pub filename: Option<String>,
    pub description: Option<String>,
    pub source: String,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InvolfltKernelVersionResult {
    pub found: bool,
    pub version: Option<String>,
    pub source: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureExtensionEvent {
    pub name: String,
    pub label: String,
    pub version: String,
    pub status: String,
    pub code: i64,
    pub message: String,
    pub healthy: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureExtensionsResult {
    pub found: bool,
    pub count: usize,
    pub events: Vec<AzureExtensionEvent>,
    pub source_path: String,
}

fn detect_systemd_service(
    content: &str,
    service_name: &str,
    severity: &str,
    message: &str,
    documentation_url: Option<&str>,
    source_path: &str,
) -> ServiceDetectionResult {
    let re = Regex::new(&format!(r"(?im)\b{}(?:\.service)?\b", regex::escape(service_name))).unwrap();
    let mut source_line: Option<usize> = None;
    let mut found = false;
    for (i, line) in content.lines().enumerate() {
        if re.is_match(line) {
            found = true;
            source_line = Some(i + 1);
            break;
        }
    }

    ServiceDetectionResult {
        found,
        service_name: service_name.to_string(),
        severity: severity.to_string(),
        message: if found { message.to_string() } else { String::new() },
        documentation_url: if found { documentation_url.map(|s| s.to_string()) } else { None },
        source_path: source_path.to_string(),
        source_line,
    }
}

fn detect_security_software(
    content: &str,
    markers: &[&str],
    software_name: &str,
    message: &str,
    source_path: &str,
) -> SecuritySoftwareResult {
    let lowered = content.to_ascii_lowercase();
    let mut source_line: Option<usize> = None;
    let mut found = false;
    'outer: for (i, line) in content.lines().enumerate() {
        let line_lower = line.to_ascii_lowercase();
        for m in markers {
            if line_lower.contains(&m.to_ascii_lowercase()) {
                found = true;
                source_line = Some(i + 1);
                break 'outer;
            }
        }
    }
    if !found {
        // Fallback: detect across the full content even if line iter missed it.
        found = markers.iter().any(|m| lowered.contains(&m.to_ascii_lowercase()));
    }
    SecuritySoftwareResult {
        found,
        software_name: software_name.to_string(),
        message: if found { message.to_string() } else { String::new() },
        source_path: source_path.to_string(),
        source_line,
    }
}

fn check_exclusions(content: &str, keywords: &[&str], software_name: &str, source_path: &str) -> ConfigCheckResult {
    let lowered = content.to_ascii_lowercase();
    let mut source_line: Option<usize> = None;
    for (i, line) in content.lines().enumerate() {
        let line_lower = line.to_ascii_lowercase();
        if keywords.iter().any(|k| line_lower.contains(&k.to_ascii_lowercase())) {
            source_line = Some(i + 1);
            break;
        }
    }
    let has_exclusions = keywords.iter().any(|k| lowered.contains(&k.to_ascii_lowercase()));
    ConfigCheckResult {
        found: has_exclusions,
        has_exclusions,
        message: if has_exclusions {
            format!("{} exclusion or exception settings detected", software_name)
        } else {
            format!("{} exclusions were not detected", software_name)
        },
        source_path: source_path.to_string(),
        source_line,
    }
}

pub fn parse_ssh_service_issues(content: &str, source_path: &str) -> ServiceEventsResult {
    let mut events = Vec::new();
    for (i, line) in content.lines().enumerate() {
        if !(line.contains("OpenSSH") || line.contains("/var/empty/sshd")) {
            continue;
        }
        if Regex::new(r"(?i)Failed to start OpenSSH server daemon").unwrap().is_match(line) {
            events.push(ServiceEvent {
                timestamp: extract_timestamp(line).unwrap_or_else(|| "Date not detected".to_string()),
                line_number: i + 1,
                issue_type: "ssh_start_failed".to_string(),
                message: "Failed to start OpenSSH server daemon".to_string(),
                raw_line: line.trim().to_string(),
                source_path: source_path.to_string(),
            });
        }
        if Regex::new(r"(?i)/var/empty/sshd must be owned by root and not group or world-writable").unwrap().is_match(line) {
            events.push(ServiceEvent {
                timestamp: extract_timestamp(line).unwrap_or_else(|| "Date not detected".to_string()),
                line_number: i + 1,
                issue_type: "ssh_permission_error".to_string(),
                message: "/var/empty/sshd must be owned by root and not group or world-writable".to_string(),
                raw_line: line.trim().to_string(),
                source_path: source_path.to_string(),
            });
        }
    }
    ServiceEventsResult {
        found: !events.is_empty(),
        count: events.len(),
        events,
        source_path: source_path.to_string(),
    }
}

pub fn parse_dlm_service(content: &str, source_path: &str) -> ServiceDetectionResult {
    detect_systemd_service(
        content,
        "dlm",
        "error",
        "DLM service is enabled in systemd and should be managed as a cluster resource.",
        Some("https://access.redhat.com/solutions/878023"),
        source_path,
    )
}

pub fn parse_azure_site_recovery(content: &str, source_path: &str) -> ServiceDetectionResult {
    detect_systemd_service(
        content,
        "involflt_start",
        "info",
        "Azure Site Recovery is enabled on this system.",
        None,
        source_path,
    )
}

pub fn parse_guardicore_agent(content: &str, source_path: &str) -> ServiceDetectionResult {
    detect_systemd_service(
        content,
        "gc-agent",
        "warning",
        "Guardicore agent is enabled on this system.",
        None,
        source_path,
    )
}

pub fn parse_illumio(content: &str, source_path: &str) -> SecuritySoftwareResult {
    detect_security_software(
        content,
        &["illumio"],
        "Illumio",
        "Illumio detected. SAP exclusions should be verified in Illumio policy configuration.",
        source_path,
    )
}

pub fn parse_trend_micro(content: &str, source_path: &str) -> SecuritySoftwareResult {
    detect_security_software(
        content,
        &["ds_agent.service", "trend micro"],
        "Trend Micro Deep Security",
        "Trend Micro Deep Security detected. SAP exclusions should be verified in Deep Security Manager.",
        source_path,
    )
}

pub fn parse_falcon_sensor(content: &str, source_path: &str) -> SecuritySoftwareResult {
    detect_security_software(
        content,
        &["falcon-sensor", "/opt/CrowdStrike"],
        "Falcon Sensor",
        "Falcon Sensor detected. SAP exclusions should be verified manually in CrowdStrike configuration.",
        source_path,
    )
}

pub fn parse_falcon_sensor_config(content: &str, source_path: &str) -> ConfigCheckResult {
    check_exclusions(content, &["exclude", "exception"], "Falcon Sensor", source_path)
}

pub fn parse_ms_defender(content: &str, source_path: &str) -> SecuritySoftwareResult {
    detect_security_software(
        content,
        &["mdatp", "wdavdaemon", "/opt/microsoft/mdatp"],
        "MS Defender",
        "Microsoft Defender detected. SAP exclusions should be verified with mdatp exclusion list.",
        source_path,
    )
}

pub fn parse_ms_defender_config(content: &str, source_path: &str) -> ConfigCheckResult {
    check_exclusions(content, &["exclusion", "exclude"], "Microsoft Defender", source_path)
}

pub fn parse_involflt_version(content: &str, source_path: &str) -> InvolfltVersionResult {
    let mut result = InvolfltVersionResult {
        found: false,
        loaded: Regex::new(r"(?m)^involflt\s+\d+").unwrap().is_match(content),
        version: None,
        build_date: None,
        filename: None,
        description: None,
        source: "modinfo".to_string(),
        source_path: source_path.to_string(),
    };

    if let Some(caps) = Regex::new(r"(?m)^version:\s*(.+)$").unwrap().captures(content) {
        result.version = caps.get(1).map(|m| m.as_str().trim().to_string());
        result.build_date = result
            .version
            .as_ref()
            .and_then(|v| Regex::new(r"([A-Za-z]+\s+\d+\s+\d{4})").unwrap().captures(v))
            .and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
        result.found = true;
    }
    if let Some(caps) = Regex::new(r"(?m)^filename:\s*(.+)$").unwrap().captures(content) {
        result.filename = caps.get(1).map(|m| m.as_str().trim().to_string());
        result.found = true;
    }
    if let Some(caps) = Regex::new(r"(?m)^description:\s*(.+)$").unwrap().captures(content) {
        result.description = caps.get(1).map(|m| m.as_str().trim().to_string());
        result.found = true;
    }
    if result.loaded {
        result.found = true;
    }
    result
}

pub fn parse_involflt_kernel_version(content: &str, source_path: &str) -> InvolfltKernelVersionResult {
    let re = Regex::new(r"(?i)involflt\[involflt_init[^\]]*\]:\s*Version\s*-\s*([\d.]+)").unwrap();
    let mut version = None;
    let mut source_line = None;
    for (i, line) in content.lines().enumerate() {
        if let Some(c) = re.captures(line) {
            version = c.get(1).map(|m| m.as_str().trim().to_string());
            source_line = Some(i + 1);
            break;
        }
    }

    InvolfltKernelVersionResult {
        found: version.is_some(),
        version,
        source: Some("kernel_log".to_string()),
        source_path: source_path.to_string(),
        source_line,
    }
}

pub fn parse_azure_extensions(content: &str, source_path: &str) -> AzureExtensionsResult {
    let Ok(status) = serde_json::from_str::<Value>(content.trim()) else {
        return AzureExtensionsResult {
            found: false,
            count: 0,
            events: Vec::new(),
            source_path: source_path.to_string(),
        };
    };

    let name = status.get("name").and_then(Value::as_str).unwrap_or_default().to_string();
    if name.is_empty() {
        return AzureExtensionsResult {
            found: false,
            count: 0,
            events: Vec::new(),
            source_path: source_path.to_string(),
        };
    }

    let label = match name.as_str() {
        "Microsoft.Azure.AzureDefenderForServers.MDE.Linux" => "Microsoft Defender for Endpoint",
        "Microsoft.Azure.RecoveryServices.VMSnapshotLinux" => "Azure Backup – VM Snapshot",
        "Microsoft.Azure.RecoveryServices.WorkloadBackup.AzureBackupLinuxWorkload" => "Azure Backup – Workload",
        "Microsoft.CPlat.Core.LinuxPatchExtension" => "Azure Update Manager",
        "Microsoft.CPlat.Core.RunCommandLinux" => "Run Command",
        "Microsoft.Azure.RecoveryServices.SiteRecovery.Linux" => "Azure Site Recovery",
        "Microsoft.OSTCExtensions.VMAccessForLinux" => "VM Access (Password Reset)",
        "Microsoft.Azure.Monitor.AzureMonitorLinuxAgent" => "Azure Monitor Agent",
        "Microsoft.Azure.Extensions.CustomScript" => "Custom Script Extension",
        "Microsoft.EnterpriseCloud.Monitoring.OmsAgentForLinux" => "Log Analytics Agent",
        _ => name.as_str(),
    }
    .to_string();

    let version = status.get("version").and_then(Value::as_str).unwrap_or("unknown").to_string();
    let runtime_status = status.get("status").and_then(Value::as_str).unwrap_or("unknown").to_string();
    let code = status.get("code") .and_then(Value::as_i64).unwrap_or(-1);
    let message = status.get("message").and_then(Value::as_str).unwrap_or("").to_string();
    let healthy = runtime_status == "Ready" && code == 0;

    AzureExtensionsResult {
        found: true,
        count: 1,
        events: vec![AzureExtensionEvent {
            name,
            label,
            version,
            status: runtime_status,
            code,
            message,
            healthy,
            source_path: source_path.to_string(),
        }],
        source_path: source_path.to_string(),
    }
}

pub fn parse_ssh_service_issues_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_ssh_service_issues(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_dlm_service_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_dlm_service(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_azure_site_recovery_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_azure_site_recovery(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_guardicore_agent_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_guardicore_agent(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_illumio_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_illumio(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_trend_micro_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_trend_micro(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_falcon_sensor_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_falcon_sensor(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_falcon_sensor_config_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_falcon_sensor_config(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_ms_defender_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_ms_defender(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_ms_defender_config_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_ms_defender_config(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_involflt_version_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_involflt_version(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_involflt_kernel_version_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_involflt_kernel_version(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_azure_extensions_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_azure_extensions(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_ssh_issues() {
        let input = concat!(
            "Jan 10 12:00:00 node1 systemd[1]: Failed to start OpenSSH server daemon.\n",
            "Jan 10 12:00:01 node1 sshd[123]: /var/empty/sshd must be owned by root and not group or world-writable\n"
        );
        let result = parse_ssh_service_issues(input, "");
        assert!(result.found);
        assert_eq!(result.count, 2);
    }

    #[test]
    fn detects_systemd_and_security_software() {
        let dlm = parse_dlm_service("dlm.service enabled", "");
        let falcon = parse_falcon_sensor("falcon-sensor running from /opt/CrowdStrike", "");
        assert!(dlm.found);
        assert!(falcon.found);
    }

    #[test]
    fn parses_involflt_version_data() {
        let input = concat!(
            "involflt              897024  14\n",
            "version:        Oct 23 2024 [ 02:41:25 ]\n",
            "filename:       /lib/modules/involflt.ko\n",
            "description:    Azure Site Recovery filter driver\n"
        );
        let result = parse_involflt_version(input, "");
        assert!(result.found);
        assert!(result.loaded);
        assert!(result.version.is_some());
    }

    #[test]
    fn parses_azure_extension_status() {
        let input = r#"{
          "name": "Microsoft.Azure.Extensions.CustomScript",
          "version": "2.1.10",
          "status": "Ready",
          "code": 0,
          "message": "success"
        }"#;
        let result = parse_azure_extensions(input, "");
        assert!(result.found);
        assert_eq!(result.count, 1);
        assert!(result.events[0].healthy);
    }
}
