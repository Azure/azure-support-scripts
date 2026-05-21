use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureVmDataDisk {
    pub lun: Option<i64>,
    pub name: Option<String>,
    pub disk_size_gb: Option<i64>,
    pub storage_account_type: Option<String>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureVmPropertiesResult {
    pub found: bool,
    pub vm_size: Option<String>,
    pub publisher: Option<String>,
    pub offer: Option<String>,
    pub sku: Option<String>,
    pub billing_code: Option<String>,
    pub license_type: Option<String>,
    pub billing_model: Option<String>,
    pub detection_method: Option<String>,
    pub os_disk_type: Option<String>,
    pub data_disks: Vec<AzureVmDataDisk>,
    pub has_ultra_disk: bool,
    pub has_premium_v2: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AzureVmGenerationResult {
    pub found: bool,
    pub vm_size: Option<String>,
    pub vm_generation: Option<u32>,
    pub is_legacy_generation: bool,
    pub recommendation: Option<String>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SuseCloudRegisterResult {
    pub found: bool,
    pub billing_model: Option<String>,
    pub detection_method: Option<String>,
    pub registration_server: Option<String>,
    pub registration_type: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WaagentConfigWarning {
    pub severity: String,
    pub setting: String,
    pub value: String,
    pub message: String,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WaagentConfigSummary {
    pub extensions_enabled: Option<bool>,
    pub provisioning_agent: Option<String>,
    pub resource_disk_format: Option<bool>,
    pub resource_disk_enable_swap: Option<bool>,
    pub resource_disk_swap_size_mb: Option<i64>,
    pub resource_disk_mount_point: Option<String>,
    pub enable_firewall: Option<bool>,
    pub enable_fips: Option<bool>,
    pub root_device_scsi_timeout: Option<i64>,
    pub logs_verbose: Option<bool>,
    pub logs_collect: Option<bool>,
    pub auto_update_enabled: Option<bool>,
    pub auto_update_ga_family: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WaagentConfigResult {
    pub found: bool,
    pub config: HashMap<String, String>,
    pub summary: WaagentConfigSummary,
    pub warnings: Vec<WaagentConfigWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WaagentLogEntry {
    pub timestamp: Option<String>,
    pub line: String,
    pub line_number: usize,
    pub correlation_id: Option<String>,
    pub extension_name: Option<String>,
    pub operation: Option<String>,
    pub message: Option<String>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WaagentVersionEntry {
    pub version: String,
    pub first_seen: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WaagentExtensionStatus {
    pub name: String,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WaagentLogResult {
    pub found: bool,
    pub agent_version: Option<String>,
    pub agent_version_history: Vec<WaagentVersionEntry>,
    pub goal_state_errors: Vec<WaagentLogEntry>,
    pub extension_errors: Vec<WaagentLogEntry>,
    pub resource_disk_errors: Vec<WaagentLogEntry>,
    pub imds_errors: Vec<WaagentLogEntry>,
    pub status_file_warnings: Vec<WaagentLogEntry>,
    pub other_errors: Vec<WaagentLogEntry>,
    pub other_warnings: Vec<WaagentLogEntry>,
    pub extension_status_summary: Option<Vec<WaagentExtensionStatus>>,
    pub total_errors: usize,
    pub total_warnings: usize,
    pub has_errors: bool,
    pub has_warnings: bool,
    pub source_path: String,
}

fn norm_bool(val: Option<&String>) -> Option<bool> {
    let value = val?.trim().to_ascii_lowercase();
    match value.as_str() {
        "y" | "yes" | "true" => Some(true),
        "n" | "no" | "false" => Some(false),
        _ => None,
    }
}

fn detect_billing_model(
    license_type: Option<&str>,
    billing_code: Option<&str>,
) -> (Option<String>, Option<String>) {
    let license_upper = license_type
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_ascii_uppercase());

    if let Some(ref lt) = license_upper {
        if ["RHEL_BYOS", "SLES_BYOS"].contains(&lt.as_str()) {
            return (
                Some("BYOS".to_string()),
                Some(format!(
                    "License Type: {}",
                    license_type.unwrap_or_default()
                )),
            );
        }
        if [
            "RHEL_BASE",
            "RHEL_SAPAPPS",
            "RHEL_BASESAPHA",
            "RHEL_SAPHA",
            "RHEL_EUS",
            "SLES",
            "SLES_SAP",
            "SLES_STANDARD",
            "SLES_HPC",
            "UBUNTU_PRO",
        ]
        .contains(&lt.as_str())
        {
            return (
                Some("PAYG".to_string()),
                Some(format!(
                    "License Type: {}",
                    license_type.unwrap_or_default()
                )),
            );
        }
    }

    if let Some(code) = billing_code {
        if [
            "Linux_IaaS",
            "Linux_IaaS_Canonical",
            "Linux_IaaS_Software_Store",
            "Linux_IaaS_Oracle",
            "Linux_IaaS_OpenLogic",
            "Linux_IaaS_Software_RedHat_Support_on_Store",
            "Linux_IaaS_Software_suse_sles_hpc_byos",
            "Linux_IaaS_Software_suse_sles_sap_byos",
            "Linux_IaaS_Software_SUSE_BYOS",
        ]
        .contains(&code)
        {
            return (
                Some("BYOS".to_string()),
                Some(format!("Billing Code: {}", code)),
            );
        }
        if [
            "Linux_IaaS_SUSE",
            "Linux_IaaS_RedHat_Support",
            "Linux_IaaS_Software_SLES_Basic",
            "Linux_IaaS_Software_SUSE_Support",
            "Linux_IaaS_Software_RedHat_HA",
            "Linux_IaaS_Software_RedHat_SAP_HA",
            "Linux_IaaS_Software_SLES_for_HPC_Priority",
            "Linux_IaaS_Software_SLES_for_SAP",
            "Linux_IaaS_Software_SLES_Standard",
            "Linux_IaaS_Software_RedHat-SAP_BusApp",
        ]
        .contains(&code)
        {
            return (
                Some("PAYG".to_string()),
                Some(format!("Billing Code: {}", code)),
            );
        }
    }

    (None, None)
}

fn extract_vm_generation(vm_size: &str) -> Option<u32> {
    crate::cached_regex!(r"(?i)_v(\d+)$")
        .captures(vm_size.trim())
        .and_then(|c| c.get(1).and_then(|m| m.as_str().parse::<u32>().ok()))
}

pub fn parse_azure_vm_generation(content: &str, source_path: &str) -> AzureVmGenerationResult {
    let vm = parse_azure_vm_properties(content, source_path);
    let vm_size = vm.vm_size.clone();
    let vm_generation = vm_size.as_deref().and_then(extract_vm_generation);
    let is_legacy_generation = vm_generation.is_some_and(|g| g <= 3);

    let recommendation = if is_legacy_generation {
        Some(
            "Legacy VM generation detected (v3 or older). Consider migrating to newer SKUs such as v6 for better price/performance."
                .to_string(),
        )
    } else {
        None
    };

    AzureVmGenerationResult {
        found: vm_size.is_some(),
        vm_size,
        vm_generation,
        is_legacy_generation,
        recommendation,
        source_path: source_path.to_string(),
    }
}

pub fn parse_azure_vm_properties(content: &str, source_path: &str) -> AzureVmPropertiesResult {
    if let Ok(metadata) = serde_json::from_str::<Value>(content) {
        let compute = metadata.get("compute").unwrap_or(&metadata);
        let vm_size = compute
            .get("vmSize")
            .and_then(Value::as_str)
            .map(|s| s.to_string());
        let offer = compute
            .get("offer")
            .and_then(Value::as_str)
            .map(|s| s.to_string());
        let publisher = compute
            .get("publisher")
            .and_then(Value::as_str)
            .map(|s| s.to_string());
        let sku = compute
            .get("sku")
            .and_then(Value::as_str)
            .map(|s| s.to_string());
        let license_type = compute
            .get("licenseType")
            .and_then(Value::as_str)
            .map(|s| s.to_string());
        let billing_code = compute
            .get("billingCode")
            .and_then(Value::as_str)
            .map(|s| s.to_string());

        let os_disk_type = compute
            .get("storageProfile")
            .and_then(|sp| sp.get("osDisk"))
            .and_then(|os| os.get("managedDisk"))
            .and_then(|md| md.get("storageAccountType"))
            .and_then(Value::as_str)
            .map(|s| s.to_string());

        let data_disks = compute
            .get("storageProfile")
            .and_then(|sp| sp.get("dataDisks"))
            .and_then(Value::as_array)
            .map(|arr| {
                arr.iter()
                    .map(|disk| AzureVmDataDisk {
                        lun: disk.get("lun").and_then(Value::as_i64),
                        name: disk
                            .get("name")
                            .and_then(Value::as_str)
                            .map(|s| s.to_string()),
                        disk_size_gb: disk.get("diskSizeGB").and_then(Value::as_i64),
                        storage_account_type: disk
                            .get("managedDisk")
                            .and_then(|md| md.get("storageAccountType"))
                            .and_then(Value::as_str)
                            .map(|s| s.to_string()),
                        source_path: source_path.to_string(),
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        let (billing_model, detection_method) =
            detect_billing_model(license_type.as_deref(), billing_code.as_deref());
        let has_ultra_disk = os_disk_type.as_deref() == Some("UltraSSD_LRS")
            || data_disks
                .iter()
                .any(|d| d.storage_account_type.as_deref() == Some("UltraSSD_LRS"));
        let has_premium_v2 = os_disk_type.as_deref() == Some("PremiumV2_LRS")
            || data_disks
                .iter()
                .any(|d| d.storage_account_type.as_deref() == Some("PremiumV2_LRS"));

        return AzureVmPropertiesResult {
            found: true,
            vm_size,
            publisher,
            offer,
            sku,
            billing_code,
            license_type,
            billing_model,
            detection_method,
            os_disk_type,
            data_disks,
            has_ultra_disk,
            has_premium_v2,
            source_path: source_path.to_string(),
        };
    }

    let mut values = HashMap::new();
    for line in content.lines() {
        if let Some(caps) = crate::cached_regex!(r"^(\w+):\s*(.+)$").captures(line.trim()) {
            values.insert(
                caps.get(1)
                    .map(|m| m.as_str())
                    .unwrap_or_default()
                    .to_string(),
                caps.get(2)
                    .map(|m| m.as_str())
                    .unwrap_or_default()
                    .trim()
                    .to_string(),
            );
        }
    }

    let vm_size = values.get("vmSize").cloned();
    let offer = values.get("offer").cloned();
    let publisher = values.get("publisher").cloned();
    let sku = values.get("sku").cloned();
    let license_type = values.get("licenseType").cloned();
    let billing_code = values.get("billingCode").cloned();
    let (billing_model, detection_method) =
        detect_billing_model(license_type.as_deref(), billing_code.as_deref());

    AzureVmPropertiesResult {
        found: !(vm_size.is_none()
            && offer.is_none()
            && publisher.is_none()
            && sku.is_none()
            && license_type.is_none()
            && billing_code.is_none()),
        vm_size,
        publisher,
        offer,
        sku,
        billing_code,
        license_type,
        billing_model,
        detection_method,
        os_disk_type: None,
        data_disks: Vec::new(),
        has_ultra_disk: false,
        has_premium_v2: false,
        source_path: source_path.to_string(),
    }
}

pub fn parse_suse_cloud_register(content: &str, source_path: &str) -> SuseCloudRegisterResult {
    let truncated = if content.len() > 100 * 1024 {
        &content[..100 * 1024]
    } else {
        content
    };
    let mut registration_server: Option<String> = None;
    let mut server_line: Option<usize> = None;

    for (line_idx, line) in truncated.lines().enumerate().take(1000) {
        let line_no = line_idx + 1;
        let trimmed = line.trim();
        if let Some(caps) =
            crate::cached_regex!(r"SUSEConnect\s+--url\s+(https?://[^\s]+)").captures(trimmed)
        {
            registration_server = caps.get(1).map(|m| m.as_str().trim().to_string());
            server_line = Some(line_no);
            break;
        }
        if let Some(caps) = crate::cached_regex!(r"(?i)url\s*=\s*(.+)").captures(trimmed) {
            registration_server = caps.get(1).map(|m| m.as_str().trim().to_string());
            server_line = Some(line_no);
            break;
        }
        if registration_server.is_none() {
            if let Some(caps) = crate::cached_regex!(r"(?i)server\s*=\s*(.+)").captures(trimmed) {
                registration_server = caps.get(1).map(|m| m.as_str().trim().to_string());
                server_line = Some(line_no);
                break;
            }
        }
    }

    let mut billing_model = None;
    let mut detection_method = None;
    let mut registration_type = None;

    if let Some(server) = registration_server.clone() {
        let server_lower = server.to_ascii_lowercase();
        if server_lower.contains("smt-azure")
            || server_lower.contains("smt.suse.de")
            || server_lower.contains("susecloud.net")
            || server_lower.contains("update.suse.com")
        {
            billing_model = Some("PAYG".to_string());
            registration_type = Some("Microsoft SMT (Subscription Management Tool)".to_string());
            detection_method = Some(format!("Cloud Registration: {}", server));
        } else if server_lower.contains("scc.suse.com")
            || server_lower.contains("customer.suse.com")
        {
            billing_model = Some("BYOS".to_string());
            registration_type = Some("SUSE Customer Center (SCC)".to_string());
            detection_method = Some(format!("Cloud Registration: {}", server));
        } else if server_lower.contains("rmt") || !server_lower.contains("suse") {
            billing_model = Some("BYOS".to_string());
            registration_type = Some("Custom RMT Server".to_string());
            detection_method = Some(format!("Cloud Registration: {}", server));
        }
    }

    SuseCloudRegisterResult {
        found: billing_model.is_some(),
        billing_model,
        detection_method,
        registration_server,
        registration_type,
        source_path: source_path.to_string(),
        source_line: server_line,
    }
}

pub fn parse_waagent_config(content: &str, source_path: &str) -> WaagentConfigResult {
    let mut config = HashMap::new();
    let mut config_lines: HashMap<String, usize> = HashMap::new();
    for (line_idx, line) in content.lines().enumerate() {
        let line_no = line_idx + 1;
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = trimmed.split_once('=') {
            let key = k.trim().to_string();
            config_lines.insert(key.clone(), line_no);
            config.insert(key, v.trim().to_string());
        }
    }

    let summary = WaagentConfigSummary {
        extensions_enabled: norm_bool(config.get("Extensions.Enabled")),
        provisioning_agent: config
            .get("Provisioning.Agent")
            .cloned()
            .or_else(|| config.get("Provisioning.Enabled").cloned()),
        resource_disk_format: norm_bool(config.get("ResourceDisk.Format")),
        resource_disk_enable_swap: norm_bool(config.get("ResourceDisk.EnableSwap")),
        resource_disk_swap_size_mb: config
            .get("ResourceDisk.SwapSizeMB")
            .and_then(|v| v.parse::<i64>().ok()),
        resource_disk_mount_point: config.get("ResourceDisk.MountPoint").cloned(),
        enable_firewall: norm_bool(config.get("OS.EnableFirewall")),
        enable_fips: norm_bool(config.get("OS.EnableFIPS")),
        root_device_scsi_timeout: config
            .get("OS.RootDeviceScsiTimeout")
            .and_then(|v| v.parse::<i64>().ok()),
        logs_verbose: norm_bool(config.get("Logs.Verbose")),
        logs_collect: norm_bool(config.get("Logs.Collect")),
        auto_update_enabled: norm_bool(config.get("AutoUpdate.Enabled")),
        auto_update_ga_family: config.get("AutoUpdate.GAFamily").cloned(),
    };

    let mut warnings = Vec::new();
    if summary.extensions_enabled == Some(false) {
        warnings.push(WaagentConfigWarning {
            severity: "warning".to_string(),
            setting: "Extensions.Enabled".to_string(),
            value: config
                .get("Extensions.Enabled")
                .cloned()
                .unwrap_or_default(),
            message:
                "VM extensions are disabled — extensions (monitoring, backups, CSE) will not run."
                    .to_string(),
            source_path: source_path.to_string(),
            source_line: config_lines.get("Extensions.Enabled").copied(),
        });
    }
    if summary.resource_disk_enable_swap == Some(true) {
        warnings.push(WaagentConfigWarning {
            severity: "info".to_string(),
            setting: "ResourceDisk.EnableSwap".to_string(),
            value: format!("{} ({} MB)", config.get("ResourceDisk.EnableSwap").cloned().unwrap_or_default(), summary.resource_disk_swap_size_mb.unwrap_or(0)),
            message: "Swap is enabled on the resource (temporary) disk. Data on this disk is not persistent across VM maintenance events.".to_string(),
            source_path: source_path.to_string(),
            source_line: config_lines.get("ResourceDisk.EnableSwap").copied(),
        });
    }
    if summary.enable_firewall == Some(false) {
        warnings.push(WaagentConfigWarning {
            severity: "warning".to_string(),
            setting: "OS.EnableFirewall".to_string(),
            value: config.get("OS.EnableFirewall").cloned().unwrap_or_default(),
            message: "The Azure agent OS-level firewall (wire-server access control) is disabled."
                .to_string(),
            source_path: source_path.to_string(),
            source_line: config_lines.get("OS.EnableFirewall").copied(),
        });
    }
    if summary.enable_fips == Some(true) {
        warnings.push(WaagentConfigWarning {
            severity: "info".to_string(),
            setting: "OS.EnableFIPS".to_string(),
            value: config.get("OS.EnableFIPS").cloned().unwrap_or_default(),
            message: "FIPS mode is enabled for the Azure agent.".to_string(),
            source_path: source_path.to_string(),
            source_line: config_lines.get("OS.EnableFIPS").copied(),
        });
    }
    if summary.auto_update_enabled == Some(false) {
        warnings.push(WaagentConfigWarning {
            severity: "info".to_string(),
            setting: "AutoUpdate.Enabled".to_string(),
            value: config
                .get("AutoUpdate.Enabled")
                .cloned()
                .unwrap_or_default(),
            message: "Auto-update of the Azure Linux Agent is disabled.".to_string(),
            source_path: source_path.to_string(),
            source_line: config_lines.get("AutoUpdate.Enabled").copied(),
        });
    }

    WaagentConfigResult {
        found: !config.is_empty(),
        config,
        summary,
        warnings,
        source_path: source_path.to_string(),
    }
}

pub fn parse_waagent_log(content: &str, source_path: &str) -> WaagentLogResult {
    let lines: Vec<&str> = content.lines().collect();
    let ts_regex = crate::cached_regex!(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.\d+Z\s+");
    let heartbeat_regex = crate::cached_regex!(r"WALinuxAgent-(\S+)\s+is running");
    let corr_regex = crate::cached_regex!(r"correlation ID: ([0-9a-f-]+)");
    let name_regex = crate::cached_regex!(r"name=([^,\s]+)");
    let op_regex = crate::cached_regex!(r"op=([^,\s]+)");
    let msg_regex = crate::cached_regex!(r"message=(.+)");
    let ext_regex = crate::cached_regex!(r"extension\s+(\S+)");
    let tuple_regex = crate::cached_regex!(r#"\(\\?\"([^\"\\]+)\\?\",\s*\\?\"([^\"\\]+)\\?\"\)"#);

    let mut version_history = Vec::new();
    let mut current_version: Option<String> = None;
    let mut goal_state_errors = Vec::new();
    let mut extension_errors = Vec::new();
    let mut resource_disk_errors = Vec::new();
    let mut imds_errors = Vec::new();
    let mut status_file_warnings = Vec::new();
    let mut other_errors = Vec::new();
    let mut other_warnings = Vec::new();

    for (i, line) in lines.iter().enumerate() {
        if line.is_empty() {
            continue;
        }
        let timestamp = ts_regex
            .captures(line)
            .and_then(|c| c.get(1).map(|m| m.as_str().replace('T', " ")));

        if let Some(caps) = heartbeat_regex.captures(line) {
            let version = caps
                .get(1)
                .map(|m| m.as_str().to_string())
                .unwrap_or_default();
            if current_version.as_deref() != Some(version.as_str()) {
                current_version = Some(version.clone());
                version_history.push(WaagentVersionEntry {
                    version,
                    first_seen: timestamp.clone(),
                });
            }
            continue;
        }

        let mut entry = WaagentLogEntry {
            timestamp: timestamp.clone(),
            line: line.chars().take(500).collect(),
            line_number: i + 1,
            correlation_id: None,
            extension_name: None,
            operation: None,
            message: None,
            source_path: source_path.to_string(),
        };

        if line.contains(" ERROR ") {
            if line.contains("Error fetching the goal state") {
                entry.correlation_id = corr_regex
                    .captures(line)
                    .and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
                goal_state_errors.push(entry);
            } else if line.contains("op=Enable") || line.contains("op=Install") {
                entry.extension_name = name_regex
                    .captures(line)
                    .and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
                entry.operation = op_regex
                    .captures(line)
                    .and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
                entry.message = msg_regex
                    .captures(line)
                    .and_then(|c| c.get(1).map(|m| m.as_str().chars().take(300).collect()));
                extension_errors.push(entry);
            } else if line.contains("ResourceDisk") || line.contains("resource disk") {
                entry.message = Some(line.chars().take(300).collect());
                resource_disk_errors.push(entry);
            } else {
                other_errors.push(entry);
            }
        } else if line.contains(" WARNING ") {
            if line.contains("IMDS_CONNECTION_ERROR") {
                imds_errors.push(entry);
            } else if line.contains("no status file was reported")
                || line.contains("incorrect format")
            {
                entry.extension_name = ext_regex.captures(line).and_then(|c| {
                    c.get(1)
                        .map(|m| m.as_str().trim_end_matches(':').to_string())
                });
                status_file_warnings.push(entry);
            } else if line.contains("ResourceDisk") || line.contains("resource disk") {
                entry.message = Some(line.chars().take(300).collect());
                resource_disk_errors.push(entry);
            } else {
                other_warnings.push(entry);
            }
        }
    }

    let mut extension_status_summary = None;
    for line in lines.iter().rev() {
        if line.contains("Extension status:") {
            if let Some(caps) = crate::cached_regex!(r"Extension status:\s*\[(.+)\]").captures(line)
            {
                let raw = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
                let entries = tuple_regex
                    .captures_iter(raw)
                    .filter_map(|m| {
                        Some(WaagentExtensionStatus {
                            name: m.get(1)?.as_str().to_string(),
                            status: m.get(2)?.as_str().to_string(),
                        })
                    })
                    .collect::<Vec<_>>();
                if !entries.is_empty() {
                    extension_status_summary = Some(entries);
                }
            }
            break;
        }
    }

    let total_errors = goal_state_errors.len()
        + extension_errors.len()
        + resource_disk_errors.len()
        + other_errors.len();
    let total_warnings = imds_errors.len() + status_file_warnings.len() + other_warnings.len();

    WaagentLogResult {
        found: true,
        agent_version: current_version,
        agent_version_history: version_history,
        goal_state_errors,
        extension_errors,
        resource_disk_errors,
        imds_errors,
        status_file_warnings,
        other_errors,
        other_warnings,
        extension_status_summary,
        total_errors,
        total_warnings,
        has_errors: total_errors > 0,
        has_warnings: total_warnings > 0,
        source_path: source_path.to_string(),
    }
}

pub fn parse_azure_vm_properties_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_azure_vm_properties(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_azure_vm_generation_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_azure_vm_generation(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_suse_cloud_register_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_suse_cloud_register(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_waagent_config_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_waagent_config(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

pub fn parse_waagent_log_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_waagent_log(content, source_path))
        .unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_vm_properties_from_json() {
        let input = r#"{
          "compute": {
            "vmSize": "Standard_D4s_v5",
            "publisher": "RedHat",
            "offer": "RHEL",
            "sku": "9-lvm",
            "licenseType": "RHEL_BYOS",
            "storageProfile": {
              "osDisk": { "managedDisk": { "storageAccountType": "Premium_LRS" } },
              "dataDisks": [
                { "lun": 0, "name": "data0", "diskSizeGB": 128, "managedDisk": { "storageAccountType": "UltraSSD_LRS" } }
              ]
            }
          }
        }"#;

        let result = parse_azure_vm_properties(input, "");
        assert!(result.found);
        assert_eq!(result.billing_model.as_deref(), Some("BYOS"));
        assert!(result.has_ultra_disk);
    }

    #[test]
    fn detects_legacy_vm_generation() {
        let input = r#"{
                    "compute": {
                        "vmSize": "Standard_D8s_v2"
                    }
                }"#;

        let result = parse_azure_vm_generation(input, "");
        assert!(result.found);
        assert_eq!(result.vm_generation, Some(2));
        assert!(result.is_legacy_generation);
        assert!(result.recommendation.is_some());
    }

    #[test]
    fn detects_modern_vm_generation() {
        let input = r#"{
                    "compute": {
                        "vmSize": "Standard_D4s_v6"
                    }
                }"#;

        let result = parse_azure_vm_generation(input, "");
        assert!(result.found);
        assert_eq!(result.vm_generation, Some(6));
        assert!(!result.is_legacy_generation);
        assert!(result.recommendation.is_none());
    }

    #[test]
    fn parses_suse_registration() {
        let input = "Registration: /usr/sbin/SUSEConnect --url https://scc.suse.com";
        let result = parse_suse_cloud_register(input, "");
        assert!(result.found);
        assert_eq!(result.billing_model.as_deref(), Some("BYOS"));
    }

    #[test]
    fn parses_waagent_config_and_warnings() {
        let input = concat!(
            "Extensions.Enabled=n\n",
            "ResourceDisk.EnableSwap=y\n",
            "ResourceDisk.SwapSizeMB=2048\n",
            "OS.EnableFirewall=n\n",
            "AutoUpdate.Enabled=n\n"
        );
        let result = parse_waagent_config(input, "");
        assert!(result.found);
        assert_eq!(result.summary.extensions_enabled, Some(false));
        assert!(result.warnings.len() >= 3);
    }

    #[test]
    fn parses_waagent_log_categories() {
        let input = concat!(
            "2026-02-19T06:05:04.123456Z INFO ExtHandler WALinuxAgent-2.9.1 is running\n",
            "2026-02-19T06:06:04.123456Z ERROR ExtHandler Error fetching the goal state [incarnation 4] from wireserver, correlation ID: abcd-1234\n",
            "2026-02-19T06:06:05.123456Z ERROR ExtHandler name=CustomScript, op=Enable, message=Enable failed\n",
            "2026-02-19T06:06:06.123456Z WARNING ExtHandler IMDS_CONNECTION_ERROR failed to connect\n",
            "2026-02-19T06:06:07.123456Z INFO ExtHandler Extension status: [(\"CustomScript\", \"error\")]\n"
        );
        let result = parse_waagent_log(input, "");
        assert!(result.found);
        assert_eq!(result.agent_version.as_deref(), Some("2.9.1"));
        assert_eq!(result.goal_state_errors.len(), 1);
        assert_eq!(result.extension_errors.len(), 1);
        assert_eq!(result.imds_errors.len(), 1);
    }
}
