use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct UnixWarning {
    #[serde(rename = "type")]
    pub r#type: String,
    pub severity: String,
    pub message: String,
    pub recommendation: Option<String>,
    pub documentation_url: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BasicEnvironmentResult {
    pub found: bool,
    pub pretty_name: Option<String>,
    pub name: Option<String>,
    pub distribution: Option<String>,
    pub sap_product_detected: bool,
    pub epic_product_detected: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OsReleaseResult {
    pub found: bool,
    pub name: Option<String>,
    pub version: Option<String>,
    pub version_id: Option<String>,
    pub pretty_name: Option<String>,
    pub major_version: Option<String>,
    pub minor_version: Option<String>,
    pub warnings: Vec<UnixWarning>,
    pub has_warnings: bool,
    pub is_eol: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RawFileResult {
    pub found: bool,
    pub content: Option<String>,
    pub source: Option<String>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InspectFilesystemStatus {
    pub device: String,
    pub r#type: String,
    pub uuid: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InspectMountResult {
    pub device: String,
    pub mount_point: String,
    pub status: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InspectDiskResultsResult {
    pub found: bool,
    pub is_inspect_disk: bool,
    pub request_info: BTreeMap<String, String>,
    pub filesystem_status: Vec<InspectFilesystemStatus>,
    pub inspection_metadata: BTreeMap<String, String>,
    pub mount_points: BTreeMap<String, String>,
    pub mount_results: Vec<InspectMountResult>,
    pub warnings: Vec<UnixWarning>,
    pub has_warnings: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TuningDifference {
    pub parameter: String,
    pub expected: String,
    pub actual: String,
    pub documentation_url: Option<String>,
    pub matches: Option<bool>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct KernelTuningResult {
    pub found: bool,
    pub parameters: BTreeMap<String, String>,
    pub warnings: Vec<TuningDifference>,
    pub has_warnings: bool,
    pub azure_network_warnings: Vec<TuningDifference>,
    pub has_azure_network_warnings: bool,
    pub azure_network_tuned: bool,
    pub optional_network_info: Vec<TuningDifference>,
    pub has_optional_network_info: bool,
    pub fips_enabled: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HugePagesResult {
    pub found: bool,
    pub static_huge_pages: BTreeMap<String, i64>,
    pub transparent_huge_pages: BTreeMap<String, i64>,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TimeSyncResult {
    pub found: bool,
    pub has_hv_utils: bool,
    pub has_ptp_clock: bool,
    pub ptp_index: Option<String>,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PtpClockSourceResult {
    pub found: bool,
    pub has_refclock: bool,
    pub uses_hyperv_symlink: bool,
    pub refclock_device: Option<String>,
    pub warnings: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TimeSyncServiceResult {
    pub found: bool,
    pub service_name: Option<String>,
    pub active: bool,
    pub warnings: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TimedatectlResult {
    pub found: bool,
    pub ntp_enabled: bool,
    pub ntp_synchronized: bool,
    pub ntp_service: Option<String>,
    pub local_time: Option<String>,
    pub timezone: Option<String>,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub has_warnings: bool,
    pub has_errors: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PtpDeviceResult {
    pub found: bool,
    pub ptp_devices: Vec<String>,
    pub has_ptp_hyperv_symlink: bool,
    pub ptp_hyperv_target: Option<String>,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ChronyTrackingResult {
    pub found: bool,
    pub reference_id: Option<String>,
    pub reference_name: Option<String>,
    pub stratum: Option<i32>,
    pub system_time: Option<String>,
    pub system_time_seconds: Option<f64>,
    pub last_offset: Option<String>,
    pub last_offset_seconds: Option<f64>,
    pub rms_offset: Option<String>,
    pub update_interval: Option<String>,
    pub leap_status: Option<String>,
    pub is_ptp_source: bool,
    pub is_phc_source: bool,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub has_warnings: bool,
    pub has_errors: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ChronyMakestepResult {
    pub found: bool,
    pub has_makestep: bool,
    pub makestep_threshold: Option<f64>,
    pub makestep_limit: Option<i32>,
    pub has_refclock: bool,
    pub refclock_device: Option<String>,
    pub refclock_poll_interval: Option<i32>,
    pub uses_hyperv_symlink: bool,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub has_warnings: bool,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RepoEntry {
    pub name: String,
    pub enabled: bool,
    pub is_microsoft: bool,
    pub is_eus: bool,
    pub baseurl: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RhuiConfigResult {
    pub found: bool,
    pub repos: Vec<RepoEntry>,
    pub has_eus_repos: bool,
    pub has_microsoft_repo: bool,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EusVersionLockResult {
    pub found: bool,
    pub has_releasever_file: bool,
    pub releasever: Option<String>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RhelRhuiCheckResult {
    pub found: bool,
    pub rhui_packages: Vec<String>,
    pub has_rhui_package: bool,
    pub rhui_type: Option<String>,
    pub is_eus: bool,
    pub is_sap: bool,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CryptoPoliciesResult {
    pub found: bool,
    pub policy: Option<String>,
    pub is_default: bool,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FipsModeSetupResult {
    pub found: bool,
    pub fips_enabled: bool,
    pub inconsistent_state: bool,
    pub raw_output: String,
    pub warnings: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct KernelCmdlineResult {
    pub found: bool,
    pub fips_enabled: bool,
    pub crashkernel: Option<String>,
    pub root_device: Option<String>,
    pub raw_cmdline: String,
    pub warnings: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ErrorItem {
    pub r#type: String,
    pub line: usize,
    pub message: String,
    pub sample: String,
    pub repo: Option<String>,
    pub eus_version: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RhuiErrorsResult {
    pub found: bool,
    pub has_cert_expiration: bool,
    pub has_http403: bool,
    pub has_http400: bool,
    pub has_connection_error: bool,
    pub errors: Vec<ErrorItem>,
    pub affected_repos: Vec<String>,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LeappIssue {
    pub risk_factor: Option<String>,
    pub is_error: bool,
    pub title: String,
    pub summary: String,
    pub remediation: Option<String>,
    pub key: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LeappReportResult {
    pub found: bool,
    pub has_errors: bool,
    pub has_high_risk: bool,
    pub has_medium_risk: bool,
    pub upgrade_blocked: bool,
    pub total_issues: usize,
    pub error_count: usize,
    pub high_risk_count: usize,
    pub medium_risk_count: usize,
    pub low_risk_count: usize,
    pub info_count: usize,
    pub issues: Vec<LeappIssue>,
    pub third_party_packages: Vec<String>,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LeappLogResult {
    pub found: bool,
    pub has_errors: bool,
    pub has_curl_errors: bool,
    pub has_dns_errors: bool,
    pub has_rhui_errors: bool,
    pub error_count: usize,
    pub warning_count: usize,
    pub critical_count: usize,
    pub errors: Vec<ErrorItem>,
    pub warnings: Vec<UnixWarning>,
    pub recommendations: Vec<UnixWarning>,
    pub source_path: String,
}

fn normalize_space(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join("\t")
}

fn check_eol_distribution(name: Option<&str>, major_version: Option<&str>, pretty_name: Option<&str>) -> Vec<UnixWarning> {
    let mut warnings = Vec::new();
    let name_lower = name.unwrap_or("").to_ascii_lowercase();
    let pretty_lower = pretty_name.unwrap_or("").to_ascii_lowercase();
    let major = major_version.and_then(|v| v.parse::<i32>().ok()).unwrap_or(0);
    if (name_lower.contains("red hat")
        || name_lower.contains("rhel")
        || name_lower.contains("centos")
        || name_lower.contains("oracle linux")
        || pretty_lower.contains("red hat")
        || pretty_lower.contains("centos")
        || pretty_lower.contains("oracle linux"))
        && major == 7
    {
        warnings.push(UnixWarning {
            r#type: "eol_distribution".to_string(),
            severity: "warning".to_string(),
            message: "RHEL 7 / CentOS 7 is out of general support. Some RCA Tool detectors may be inaccurate for this distribution.".to_string(),
            recommendation: Some("Consider upgrading to a supported distribution for better analysis accuracy.".to_string()),
            documentation_url: Some("https://access.redhat.com/support/policy/updates/errata".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if (name_lower.contains("suse") || name_lower.contains("sles") || pretty_lower.contains("suse") || pretty_lower.contains("sles"))
        && major == 12
    {
        warnings.push(UnixWarning {
            r#type: "eol_distribution".to_string(),
            severity: "warning".to_string(),
            message: "SUSE Linux Enterprise 12 is out of general support. Some RCA Tool detectors may be inaccurate for this distribution.".to_string(),
            recommendation: Some("Consider upgrading to SLES 15+ for better analysis accuracy.".to_string()),
            documentation_url: Some("https://www.suse.com/lifecycle/".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    warnings
}

pub fn parse_basic_environment(content: &str, source_path: &str) -> BasicEnvironmentResult {
    let mut pretty_name = None;
    let mut name = None;
    let mut product = None;
    let mut skip_section = false;

    for raw in content.lines() {
        let trimmed = raw.trim();
        if trimmed.starts_with('#') {
            skip_section = trimmed.to_ascii_lowercase().contains(".rpmsave");
            continue;
        }
        if skip_section || trimmed.is_empty() {
            continue;
        }
        if let Some(c) = crate::cached_regex!(r#"^PRETTY_NAME=(?:\"|')?([^\"']+)(?:\"|')?$"#).captures(trimmed) {
            pretty_name = Some(c[1].trim().to_string());
            break;
        }
        if let Some(c) = crate::cached_regex!(r#"^NAME=(?:\"|')?([^\"']+)(?:\"|')?$"#).captures(trimmed) {
            name = Some(c[1].trim().to_string());
        }
        if let Some(c) = crate::cached_regex!(r"^Product:\s*(.+)$").captures(trimmed) {
            product = Some(c[1].trim().to_string());
        }
    }
    let distribution = pretty_name.clone().or(product.clone()).or(name.clone());
    let mut sap = false;
    let mut epic = false;
    for field in [pretty_name.as_ref(), product.as_ref(), name.as_ref()].into_iter().flatten() {
        if crate::cached_regex!(r"(?i)\bSAP\b|for\s+SAP|SAP\s+Applications").is_match(field) {
            sap = true;
        }
        if crate::cached_regex!(r"(?i)\bEPIC\b|Enterprise\s+Portal\s+Integration|for\s+EPIC").is_match(field) {
            epic = true;
        }
    }
    BasicEnvironmentResult {
        found: distribution.is_some(),
        pretty_name,
        name,
        distribution,
        sap_product_detected: sap,
        epic_product_detected: epic,
            source_path: source_path.to_string(),
}
}

pub fn parse_os_release(content: &str, source_path: &str) -> OsReleaseResult {
    let mut name = None;
    let mut version = None;
    let mut version_id = None;
    let mut pretty_name = None;

    let first_line = content.lines().next().unwrap_or("").trim();
    if !content.contains('=') && !first_line.is_empty() {
        if let Some(c) = crate::cached_regex!(r"^(.+?)\s+release\s+([\d.]+)")
            .captures(first_line)
        {
            name = Some(c[1].trim().to_string());
            version_id = Some(c[2].to_string());
            pretty_name = Some(first_line.to_string());
        } else if let Some(c) = crate::cached_regex!(r"^(SUSE.+?)\s+(\d+)")
            .captures(first_line)
        {
            name = Some(c[1].trim().to_string());
            version_id = Some(c[2].to_string());
            pretty_name = Some(first_line.to_string());
        }
    } else {
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            if let Some(c) = crate::cached_regex!(r#"^NAME=[\"']?([^\"']+)[\"']?$"#).captures(trimmed) {
                name = Some(c[1].to_string());
            }
            if let Some(c) = crate::cached_regex!(r#"^VERSION=[\"']?([^\"']+)[\"']?$"#).captures(trimmed) {
                version = Some(c[1].to_string());
            }
            if let Some(c) = crate::cached_regex!(r#"^VERSION_ID=[\"']?([^\"']+)[\"']?$"#).captures(trimmed) {
                version_id = Some(c[1].to_string());
            }
            if let Some(c) = crate::cached_regex!(r#"^PRETTY_NAME=[\"']?([^\"']+)[\"']?$"#).captures(trimmed) {
                pretty_name = Some(c[1].to_string());
            }
            if pretty_name.is_none() {
                if let Some(c) = crate::cached_regex!(r"^Distribution:\s*(.+)$").captures(trimmed) {
                    pretty_name = Some(c[1].trim().to_string());
                }
            }
        }
    }

    let (major_version, minor_version) = if let Some(v) = &version_id {
        let mut parts = v.split('.');
        (parts.next().map(|s| s.to_string()), parts.next().map(|s| s.to_string()))
    } else if let Some(pn) = &pretty_name {
        let mv = crate::cached_regex!(r"\b(1[0-9]|[789])\b")
            .captures(pn)
            .and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
        (mv, None)
    } else {
        (None, None)
    };
    let warnings = check_eol_distribution(name.as_deref(), major_version.as_deref(), pretty_name.as_deref());
    OsReleaseResult {
        found: name.is_some() || pretty_name.is_some(),
        name,
        version,
        version_id,
        pretty_name,
        major_version,
        minor_version,
        has_warnings: !warnings.is_empty(),
        is_eol: !warnings.is_empty(),
        warnings,
            source_path: source_path.to_string(),
}
}

pub fn parse_fstab(content: &str, source_path: &str) -> RawFileResult {
    // SCC's `fs-diskio.txt` is a multipart file with sections delimited by
    // lines starting with `#==[` (e.g. `#==[ Configuration File ]===#`).
    // The fstab section is introduced by a `# /etc/fstab` header line.
    // Blank lines and commented-out fstab entries (e.g. `#/dev/system/swap`)
    // are legitimate fstab content and must NOT terminate the section.
    let header_re = crate::cached_regex!(r"^#\s*/etc/fstab\s*$");
    let has_header = content.lines().any(|l| header_re.is_match(l));
    let extracted = if has_header {
        let mut lines: Vec<&str> = Vec::new();
        let mut in_section = false;
        for line in content.lines() {
            if !in_section {
                if header_re.is_match(line) {
                    in_section = true;
                }
                continue;
            }
            if line.starts_with("#==") {
                break;
            }
            lines.push(line);
        }
        // Strip leading/trailing blank lines, keep interior blanks.
        while lines.first().map_or(false, |l| l.trim().is_empty()) {
            lines.remove(0);
        }
        while lines.last().map_or(false, |l| l.trim().is_empty()) {
            lines.pop();
        }
        if lines.is_empty() { None } else { Some(lines.join("\n")) }
    } else if content.trim().is_empty() {
        None
    } else {
        Some(content.trim().to_string())
    };
    RawFileResult {
        found: extracted.is_some(),
        content: extracted,
        source: Some("fstab".to_string()),
            source_path: source_path.to_string(),
}
}

pub fn parse_inspect_disk_results(content: &str, source_path: &str) -> InspectDiskResultsResult {
    let mut result = InspectDiskResultsResult {
        found: false,
        is_inspect_disk: false,
        request_info: BTreeMap::new(),
        filesystem_status: Vec::new(),
        inspection_metadata: BTreeMap::new(),
        mount_points: BTreeMap::new(),
        mount_results: Vec::new(),
        warnings: Vec::new(),
        has_warnings: false,
            source_path: source_path.to_string(),
};

    let mut section: Option<&str> = None;
    let mut has_request = false;
    let mut has_meta = false;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed == "========== Request Info ==========" {
            section = Some("request");
            has_request = true;
            continue;
        }
        if trimmed == "========== End Request Info ==========" {
            section = None;
            continue;
        }
        if trimmed == "Filesystem Status:" {
            section = Some("fs");
            continue;
        }
        if trimmed.starts_with("Inspection Status:") || trimmed.starts_with("Inspection Metadata for") {
            section = Some("meta");
            has_meta = true;
            continue;
        }
        if trimmed == "Mount Points:" {
            section = Some("mount_points");
            continue;
        }

        if let Some(c) = crate::cached_regex!(r"^Mounting\s+(\/dev\/\S+)\s+on\s+(\S+)\s+(SUCCEEDED|FAILED)\.")
            .captures(trimmed)
        {
            result.mount_results.push(InspectMountResult {
                device: c[1].to_string(),
                mount_point: c[2].to_string(),
                status: c[3].to_string(),
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
            if &c[3] == "FAILED" {
                result.warnings.push(UnixWarning {
                    r#type: "inspect_disk_mount_failure".to_string(),
                    severity: "error".to_string(),
                    message: format!("Mount failed: {} on {}", &c[1], &c[2]),
                    recommendation: Some("Check if the device exists and the filesystem is intact.".to_string()),
                    documentation_url: None,
                                    source_path: String::new(),
                    source_line: None,
                    source_line_end: None,
});
            }
        }

        match section {
            Some("request") => {
                if let Some(c) = crate::cached_regex!(r"^(.+?):\s+(.+)$").captures(trimmed) {
                    result.request_info.insert(c[1].trim().to_string(), c[2].trim().to_string());
                }
            }
            Some("fs") => {
                if let Some(c) = crate::cached_regex!(r"^(\/dev\/\S+):\s+(\S+)\s+\[uuid=([^\]]*)\]")
                    .captures(trimmed)
                {
                    result.filesystem_status.push(InspectFilesystemStatus {
                        device: c[1].to_string(),
                        r#type: c[2].to_string(),
                        uuid: if c[3].is_empty() { None } else { Some(c[3].to_string()) },
                                            source_path: String::new(),
                        source_line: None,
                        source_line_end: None,
});
                }
            }
            Some("meta") => {
                if let Some(c) = crate::cached_regex!(r"^(Type|Distribution|Product Name):\s+(.+)$")
                    .captures(trimmed)
                {
                    result.inspection_metadata.insert(c[1].to_string(), c[2].trim().to_string());
                }
            }
            Some("mount_points") => {
                if let Some(c) = crate::cached_regex!(r"^(\/\S*)\s*:\s+(\/dev\/\S+)$").captures(trimmed) {
                    result.mount_points.insert(c[1].to_string(), c[2].to_string());
                }
            }
            _ => {}
        }
    }

    result.found = has_request || has_meta;
    result.is_inspect_disk = result.found;
    result.has_warnings = !result.warnings.is_empty();
    result
}

pub fn parse_kernel_tuning(content: &str, source_path: &str) -> KernelTuningResult {
    let mut parameters = BTreeMap::new();
    for line in content.lines() {
        if let Some(c) = crate::cached_regex!(r"^([^\s=]+)\s*=\s*(.+)$").captures(line.trim()) {
            parameters.insert(c[1].to_string(), c[2].trim().to_string());
        }
    }

    let expected_values = [
        ("vm.dirty_bytes", "629145600"),
        ("vm.dirty_background_bytes", "314572800"),
        ("vm.swappiness", "10"),
    ];
    let mut warnings = Vec::new();
    for (k, v) in expected_values {
        if let Some(actual) = parameters.get(k) {
            if actual != v {
                warnings.push(TuningDifference {
                    parameter: k.to_string(),
                    expected: v.to_string(),
                    actual: actual.clone(),
                    documentation_url: Some("https://learn.microsoft.com/en-us/azure/sap/workloads/sap-hana-high-availability".to_string()),
                    matches: None,
                                    source_path: String::new(),
                    source_line: None,
                    source_line_end: None,
});
            }
        }
    }

    let azure_network_params = [
        ("net.ipv4.tcp_mem", "4096\t87380\t67108864"),
        ("net.ipv4.udp_mem", "4096\t87380\t33554432"),
        ("net.ipv4.tcp_rmem", "4096\t87380\t67108864"),
        ("net.ipv4.tcp_wmem", "4096\t65536\t67108864"),
        ("net.core.rmem_default", "33554432"),
        ("net.core.wmem_default", "33554432"),
        ("net.ipv4.udp_wmem_min", "16384"),
        ("net.ipv4.udp_rmem_min", "16384"),
        ("net.core.wmem_max", "134217728"),
        ("net.core.rmem_max", "134217728"),
        ("net.core.busy_poll", "50"),
        ("net.core.busy_read", "50"),
        ("net.ipv4.tcp_congestion_control", "bbr"),
    ];
    let mut azure_network_warnings = Vec::new();
    for (k, v) in azure_network_params {
        if let Some(actual) = parameters.get(k) {
            if normalize_space(actual) != normalize_space(v) {
                azure_network_warnings.push(TuningDifference {
                    parameter: k.to_string(),
                    expected: v.to_string(),
                    actual: actual.clone(),
                    documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-optimize-network-bandwidth#linux-virtual-machines".to_string()),
                    matches: None,
                                    source_path: String::new(),
                    source_line: None,
                    source_line_end: None,
});
            }
        }
    }

    let optional_network_params = [
        ("net.ipv4.tcp_timestamps", "1"),
        ("net.ipv4.tcp_tw_reuse", "1"),
        ("net.ipv4.ip_local_port_range", "1024\t65535"),
        ("net.core.netdev_budget", "1000"),
        ("net.core.optmem_max", "65535"),
        ("net.ipv4.tcp_frto", "0"),
        ("net.core.somaxconn", "32768"),
        ("net.core.netdev_max_backlog", "32768"),
        ("net.core.dev_weight", "64"),
        ("net.core.default_qdisc", "fq"),
    ];
    let mut optional_network_info = Vec::new();
    for (k, v) in optional_network_params {
        if let Some(actual) = parameters.get(k) {
            optional_network_info.push(TuningDifference {
                parameter: k.to_string(),
                expected: v.to_string(),
                actual: actual.clone(),
                documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-optimize-network-bandwidth#linux-virtual-machines".to_string()),
                matches: Some(normalize_space(actual) == normalize_space(v)),
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
    }

    let azure_expected_keys = [
        "net.ipv4.tcp_mem", "net.ipv4.udp_mem", "net.ipv4.tcp_rmem", "net.ipv4.tcp_wmem",
        "net.core.rmem_default", "net.core.wmem_default", "net.ipv4.udp_wmem_min",
        "net.ipv4.udp_rmem_min", "net.core.wmem_max", "net.core.rmem_max", "net.core.busy_poll",
        "net.core.busy_read", "net.ipv4.tcp_congestion_control",
    ];
    let azure_network_tuned = azure_network_warnings.is_empty() && azure_expected_keys.iter().all(|k| parameters.contains_key(*k));
    let fips_enabled = parameters.get("crypto.fips_enabled").map(|v| v == "1").unwrap_or(false);

    KernelTuningResult {
        found: !parameters.is_empty(),
        parameters,
        has_warnings: !warnings.is_empty(),
        warnings,
        has_azure_network_warnings: !azure_network_warnings.is_empty(),
        azure_network_warnings,
        azure_network_tuned,
        has_optional_network_info: !optional_network_info.is_empty(),
        optional_network_info,
        fips_enabled,
            source_path: source_path.to_string(),
}
}

pub fn parse_huge_pages(content: &str, source_path: &str) -> HugePagesResult {
    let mut static_hp = BTreeMap::new();
    let mut thp = BTreeMap::new();
    let mut warnings = Vec::new();
    let mut recommendations = Vec::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(c) = crate::cached_regex!(r"^HugePages_(\w+):\s+(\d+)")
            .captures(trimmed)
        {
            static_hp.insert(c[1].to_ascii_lowercase(), c[2].parse::<i64>().unwrap_or(0));
        }
        if let Some(c) = crate::cached_regex!(r"^Hugepagesize:\s+(\d+)\s+kB")
            .captures(trimmed)
        {
            static_hp.insert("pagesize_kb".to_string(), c[1].parse::<i64>().unwrap_or(0));
        }
        if let Some(c) = crate::cached_regex!(r"^Hugetlb:\s+(\d+)\s+kB")
            .captures(trimmed)
        {
            static_hp.insert("hugetlb_kb".to_string(), c[1].parse::<i64>().unwrap_or(0));
        }
        if let Some(c) = crate::cached_regex!(r"^AnonHugePages:\s+(\d+)\s+kB")
            .captures(trimmed)
        {
            thp.insert("anon_kb".to_string(), c[1].parse::<i64>().unwrap_or(0));
        }
        if let Some(c) = crate::cached_regex!(r"^ShmemHugePages:\s+(\d+)\s+kB")
            .captures(trimmed)
        {
            thp.insert("shmem_kb".to_string(), c[1].parse::<i64>().unwrap_or(0));
        }
    }

    if let (Some(total), Some(free)) = (static_hp.get("total"), static_hp.get("free")) {
        if *total > 0 {
            let used_percent = ((*total - *free) as f64 / *total as f64) * 100.0;
            if used_percent < 10.0 {
                warnings.push(UnixWarning {
                    r#type: "unused_hugepages".to_string(),
                    severity: "warning".to_string(),
                    message: format!("Static huge pages are configured but mostly unused ({:.1}% used)", used_percent),
                    recommendation: Some("Consider reducing huge page allocation to free memory.".to_string()),
                    documentation_url: None,
                                    source_path: String::new(),
                    source_line: None,
                    source_line_end: None,
});
            }
        }
    }
    if let Some(anon_kb) = thp.get("anon_kb") {
        if *anon_kb > 0 {
            recommendations.push(UnixWarning {
                r#type: "thp_usage".to_string(),
                severity: "info".to_string(),
                message: format!("Transparent Huge Pages are in use ({} MB)", anon_kb / 1024),
                recommendation: Some("For SAP HANA, THP should usually be disabled.".to_string()),
                documentation_url: Some("https://learn.microsoft.com/en-us/azure/sap/large-instances/archived-hli-docs/hana-monitor-troubleshoot#operating-system-os".to_string()),
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
    }

    HugePagesResult {
        found: !static_hp.is_empty() || !thp.is_empty(),
        static_huge_pages: static_hp,
        transparent_huge_pages: thp,
        warnings,
        recommendations,
            source_path: source_path.to_string(),
}
}

pub fn parse_time_sync(content: &str, source_path: &str) -> TimeSyncResult {
    let has_hv_utils = crate::cached_regex!(r"(?i)hv_utils|hyperv").is_match(content);
    let ptp_index = crate::cached_regex!(r"(?i)ptp(\d+)")
        .captures(content)
        .and_then(|c| c.get(1).map(|m| format!("ptp{}", m.as_str())));
    let has_ptp_clock = ptp_index.is_some() || content.contains("ptp_hyperv");
    let mut warnings = Vec::new();
    let mut recommendations = Vec::new();
    if has_hv_utils && !has_ptp_clock {
        warnings.push(UnixWarning {
            r#type: "ptp_missing".to_string(),
            severity: "warning".to_string(),
            message: "Hyper-V utilities are present but no PTP clock source was detected.".to_string(),
            recommendation: Some("Check hv_utils and Azure time sync configuration.".to_string()),
            documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if has_ptp_clock {
        recommendations.push(UnixWarning {
            r#type: "ptp_present".to_string(),
            severity: "info".to_string(),
            message: "PTP clock source detected.".to_string(),
            recommendation: None,
            documentation_url: None,
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    TimeSyncResult {
        found: has_hv_utils || has_ptp_clock,
        has_hv_utils,
        has_ptp_clock,
        ptp_index,
        warnings,
        recommendations,
            source_path: source_path.to_string(),
}
}

pub fn parse_ptp_clock_source(content: &str, source_path: &str) -> PtpClockSourceResult {
    let refclock = crate::cached_regex!(r"(?im)^refclock\s+PHC\s+(\/dev\/[^\s]+)")
        .captures(content)
        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
    let uses_hyperv_symlink = refclock.as_deref().map(|d| d.contains("ptp_hyperv")).unwrap_or(false);
    let mut warnings = Vec::new();
    if refclock.is_none() {
        warnings.push(UnixWarning {
            r#type: "no_ptp_refclock".to_string(),
            severity: "warning".to_string(),
            message: "No PTP refclock found in chrony or NTP configuration.".to_string(),
            recommendation: Some("Configure refclock PHC /dev/ptp_hyperv.".to_string()),
            documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#chrony".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    PtpClockSourceResult {
        found: refclock.is_some(),
        has_refclock: refclock.is_some(),
        uses_hyperv_symlink,
        refclock_device: refclock,
        warnings,
            source_path: source_path.to_string(),
}
}

pub fn parse_time_sync_service(content: &str, source_path: &str) -> TimeSyncServiceResult {
    let lowered = content.to_ascii_lowercase();
    let (service_name, active) = if lowered.contains("chronyd") || lowered.contains("chrony") {
        (Some("chrony".to_string()), lowered.contains("active") || lowered.contains("running"))
    } else if lowered.contains("ntpd") || lowered.contains("ntp") {
        (Some("ntpd".to_string()), lowered.contains("active") || lowered.contains("running"))
    } else if lowered.contains("systemd-timesyncd") {
        (Some("systemd-timesyncd".to_string()), lowered.contains("active") || lowered.contains("running"))
    } else {
        (None, false)
    };
    let mut warnings = Vec::new();
    if let Some(name) = &service_name {
        if !active {
            warnings.push(UnixWarning {
                r#type: "time_service_inactive".to_string(),
                severity: "warning".to_string(),
                message: format!("{} is configured but not active.", name),
                recommendation: Some("Start and enable the configured time sync service.".to_string()),
                documentation_url: None,
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
    }
    TimeSyncServiceResult {
        found: service_name.is_some(),
        service_name,
        active,
        warnings,
            source_path: source_path.to_string(),
}
}

pub fn parse_timedatectl(content: &str, source_path: &str) -> TimedatectlResult {
    let mut result = TimedatectlResult {
        found: false,
        ntp_enabled: false,
        ntp_synchronized: false,
        ntp_service: None,
        local_time: None,
        timezone: None,
        warnings: Vec::new(),
        recommendations: Vec::new(),
        has_warnings: false,
        has_errors: false,
            source_path: source_path.to_string(),
};

    for line in content.lines() {
        let trimmed = line.trim();
        let Some(idx) = trimmed.find(':') else { continue; };
        let key = trimmed[..idx].trim().to_ascii_lowercase();
        let value = trimmed[idx + 1..].trim().to_ascii_lowercase();
        match key.as_str() {
            "ntp enabled" => {
                result.ntp_enabled = value == "yes";
                result.found = true;
            }
            "ntp synchronized" | "system clock synchronized" => {
                result.ntp_synchronized = value == "yes";
                result.found = true;
            }
            "ntp service" => {
                result.ntp_service = Some(value.clone());
                result.ntp_enabled = value == "active" || value == "running";
                result.found = true;
            }
            "local time" => {
                result.local_time = Some(trimmed[idx + 1..].trim().to_string());
                result.found = true;
            }
            "time zone" => result.timezone = Some(trimmed[idx + 1..].trim().to_string()),
            _ => {}
        }
    }
    if result.found && !result.ntp_synchronized {
        result.warnings.push(UnixWarning {
            r#type: "not_synchronized".to_string(),
            severity: "error".to_string(),
            message: "System clock is not synchronized with NTP.".to_string(),
            recommendation: Some("Check time service status and network connectivity to time sources.".to_string()),
            documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if result.found && !result.ntp_enabled {
        result.warnings.push(UnixWarning {
            r#type: "ntp_disabled".to_string(),
            severity: "error".to_string(),
            message: "NTP service is not enabled.".to_string(),
            recommendation: Some("Enable NTP with timedatectl set-ntp true".to_string()),
            documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    result.has_warnings = !result.warnings.is_empty();
    result.has_errors = result.warnings.iter().any(|w| w.severity == "error");
    result
}

pub fn parse_ptp_device(content: &str, source_path: &str) -> PtpDeviceResult {
    let mut devices = Vec::new();
    let mut has_symlink = false;
    let mut target = None;
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(c) = crate::cached_regex!(r"\b(ptp\d+)\b").captures(trimmed) {
            let dev = c[1].to_string();
            if !devices.contains(&dev) {
                devices.push(dev);
            }
        }
        if let Some(c) = crate::cached_regex!(r"ptp_hyperv\s+->\s+(\S+)")
            .captures(trimmed)
        {
            has_symlink = true;
            target = Some(c[1].to_string());
        }
        if trimmed.contains("DEVLINKS=") && trimmed.contains("ptp_hyperv") {
            has_symlink = true;
        }
        if trimmed.starts_with("E: DEVNAME=/dev/ptp") && target.is_none() {
            target = Some(trimmed.trim_start_matches("E: DEVNAME=/dev/").to_string());
        }
    }
    let mut warnings = Vec::new();
    let mut recommendations = Vec::new();
    if !devices.is_empty() && !has_symlink {
        warnings.push(UnixWarning {
            r#type: "ptp_hyperv_symlink_missing".to_string(),
            severity: "warning".to_string(),
            message: "/dev/ptp_hyperv symlink is not present.".to_string(),
            recommendation: Some("Create a udev rule to create the /dev/ptp_hyperv symlink.".to_string()),
            documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#check-for-ptp-clock-source".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if devices.is_empty() {
        recommendations.push(UnixWarning {
            r#type: "no_ptp_devices".to_string(),
            severity: "info".to_string(),
            message: "No PTP devices found.".to_string(),
            recommendation: Some("Ensure the kernel supports PTP and hv_utils is loaded.".to_string()),
            documentation_url: None,
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    PtpDeviceResult {
        found: !devices.is_empty() || has_symlink,
        ptp_devices: devices,
        has_ptp_hyperv_symlink: has_symlink,
        ptp_hyperv_target: target,
        warnings,
        recommendations,
            source_path: source_path.to_string(),
}
}

pub fn parse_chrony_tracking(content: &str, source_path: &str) -> ChronyTrackingResult {
    let mut result = ChronyTrackingResult {
        found: false,
        reference_id: None,
        reference_name: None,
        stratum: None,
        system_time: None,
        system_time_seconds: None,
        last_offset: None,
        last_offset_seconds: None,
        rms_offset: None,
        update_interval: None,
        leap_status: None,
        is_ptp_source: false,
        is_phc_source: false,
        warnings: Vec::new(),
        recommendations: Vec::new(),
        has_warnings: false,
        has_errors: false,
            source_path: source_path.to_string(),
};
    for line in content.lines() {
        let trimmed = line.trim();
        let Some(idx) = trimmed.find(':') else { continue; };
        let key = trimmed[..idx].trim().to_ascii_lowercase();
        let value = trimmed[idx + 1..].trim().to_string();
        match key.as_str() {
            "reference id" => {
                result.reference_id = Some(value.clone());
                result.found = true;
                if let Some(c) = crate::cached_regex!(r"\(PHC(\d+)\)").captures(&value) {
                    result.reference_name = Some(format!("PHC{}", &c[1]));
                    result.is_phc_source = true;
                    result.is_ptp_source = true;
                }
            }
            "stratum" => result.stratum = value.parse::<i32>().ok(),
            "system time" => {
                result.system_time = Some(value.clone());
                if let Some(c) = crate::cached_regex!(r"([\d.]+)\s+seconds?\s+(slow|fast)")
                    .captures(&value)
                {
                    let mut v = c[1].parse::<f64>().unwrap_or(0.0);
                    if &c[2].to_ascii_lowercase() == "slow" {
                        v = -v;
                    }
                    result.system_time_seconds = Some(v);
                }
            }
            "last offset" => {
                result.last_offset = Some(value.clone());
                if let Some(c) = crate::cached_regex!(r"([+-]?[\d.]+)\s+seconds?")
                    .captures(&value)
                {
                    result.last_offset_seconds = c[1].parse::<f64>().ok();
                }
            }
            "rms offset" => result.rms_offset = Some(value),
            "update interval" => result.update_interval = Some(value),
            "leap status" => result.leap_status = Some(value),
            _ => {}
        }
    }
    if let Some(off) = result.last_offset_seconds {
        let abs = off.abs();
        if abs > 0.1 {
            result.warnings.push(UnixWarning {
                r#type: "high_time_offset".to_string(),
                severity: if abs > 1.0 { "error".to_string() } else { "warning".to_string() },
                message: format!("Time offset is {:.3} seconds.", abs),
                recommendation: Some("Check chrony and consider running chronyc makestep.".to_string()),
                documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync".to_string()),
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
    }
    if result.is_ptp_source {
        result.recommendations.push(UnixWarning {
            r#type: "using_ptp".to_string(),
            severity: "info".to_string(),
            message: "Time is synchronized from a PTP source.".to_string(),
            recommendation: None,
            documentation_url: None,
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if let Some(leap) = &result.leap_status {
        if leap.to_ascii_lowercase() != "normal" {
            result.warnings.push(UnixWarning {
                r#type: "leap_status_abnormal".to_string(),
                severity: "warning".to_string(),
                message: format!("Chrony leap status is '{}' instead of 'Normal'.", leap),
                recommendation: Some("Check chrony and time source status.".to_string()),
                documentation_url: None,
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
    }
    result.has_warnings = !result.warnings.is_empty();
    result.has_errors = result.warnings.iter().any(|w| w.severity == "error");
    result
}

pub fn parse_chrony_makestep(content: &str, source_path: &str) -> ChronyMakestepResult {
    let makestep = crate::cached_regex!(r"(?im)^makestep\s+([\d.]+)\s+(\d+)")
        .captures(content);
    let refclock = crate::cached_regex!(r"(?im)^refclock\s+PHC\s+(\/dev\/[^\s]+)(?:\s+poll\s+(\d+))?")
        .captures(content);
    let mut result = ChronyMakestepResult {
        found: makestep.is_some() || refclock.is_some(),
        has_makestep: makestep.is_some(),
        makestep_threshold: makestep.as_ref().and_then(|c| c.get(1).and_then(|m| m.as_str().parse::<f64>().ok())),
        makestep_limit: makestep.as_ref().and_then(|c| c.get(2).and_then(|m| m.as_str().parse::<i32>().ok())),
        has_refclock: refclock.is_some(),
        refclock_device: refclock.as_ref().and_then(|c| c.get(1).map(|m| m.as_str().to_string())),
        refclock_poll_interval: refclock.as_ref().and_then(|c| c.get(2).and_then(|m| m.as_str().parse::<i32>().ok())),
        uses_hyperv_symlink: refclock.as_ref().and_then(|c| c.get(1)).map(|m| m.as_str().contains("ptp_hyperv")).unwrap_or(false),
        warnings: Vec::new(),
        recommendations: Vec::new(),
        has_warnings: false,
            source_path: source_path.to_string(),
};
    if !result.has_makestep {
        result.recommendations.push(UnixWarning {
            r#type: "no_makestep".to_string(),
            severity: "info".to_string(),
            message: "makestep directive not configured.".to_string(),
            recommendation: Some("Consider adding makestep 1.0 3".to_string()),
            documentation_url: None,
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if result.has_refclock && !result.uses_hyperv_symlink {
        result.warnings.push(UnixWarning {
            r#type: "hardcoded_ptp_device".to_string(),
            severity: "warning".to_string(),
            message: "Chrony is using a hardcoded PTP device instead of /dev/ptp_hyperv.".to_string(),
            recommendation: Some("Use refclock PHC /dev/ptp_hyperv".to_string()),
            documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#chrony".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if !result.has_refclock {
        result.warnings.push(UnixWarning {
            r#type: "no_ptp_refclock".to_string(),
            severity: "warning".to_string(),
            message: "Chrony is not configured with a PTP refclock.".to_string(),
            recommendation: Some("Add refclock PHC /dev/ptp_hyperv poll 3 dpoll -2 offset 0".to_string()),
            documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#chrony".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    result.has_warnings = !result.warnings.is_empty();
    result
}

pub fn parse_rhui_config(content: &str, source_path: &str) -> RhuiConfigResult {
    let mut repos = Vec::new();
    let mut current: Option<RepoEntry> = None;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(c) = crate::cached_regex!(r"^\[([^\]]+)\]$").captures(trimmed) {
            if let Some(repo) = current.take() {
                repos.push(repo);
            }
            let name = c[1].to_string();
            current = Some(RepoEntry {
                enabled: true,
                is_microsoft: crate::cached_regex!(r"(?i)^(rhui-)?microsoft").is_match(&name),
                is_eus: crate::cached_regex!(r"(?i)-(eus|e4s)-").is_match(&name),
                name,
                baseurl: None,
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
            continue;
        }
        if let Some(repo) = &mut current {
            if let Some(c) = crate::cached_regex!(r"^enabled\s*=\s*(\d+)").captures(trimmed) {
                repo.enabled = &c[1] == "1";
            }
            if let Some(c) = crate::cached_regex!(r"^baseurl\s*=\s*(.+)$").captures(trimmed) {
                repo.baseurl = Some(c[1].trim().to_string());
            }
        }
    }
    if let Some(repo) = current.take() {
        repos.push(repo);
    }
    let has_eus_repos = repos.iter().any(|r| r.is_eus && r.enabled);
    let has_microsoft_repo = repos.iter().any(|r| r.is_microsoft && r.enabled);
    let mut warnings = Vec::new();
    if repos.iter().any(|r| r.is_microsoft) && !has_microsoft_repo {
        warnings.push(UnixWarning {
            r#type: "rhui_repo_disabled".to_string(),
            severity: "warning".to_string(),
            message: "Microsoft RHUI repository is installed but not enabled.".to_string(),
            recommendation: Some("Enable the repository with yum-config-manager --enable <repo-name>".to_string()),
            documentation_url: Some("https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    RhuiConfigResult {
        found: !repos.is_empty(),
        repos,
        has_eus_repos,
        has_microsoft_repo,
        warnings,
        recommendations: Vec::new(),
            source_path: source_path.to_string(),
}
}

pub fn parse_eus_version_lock(content: &str, source_path: &str) -> EusVersionLockResult {
    let trimmed = content.trim();
    let releasever = crate::cached_regex!(r"^(\d+(?:\.\d+)?)")
        .captures(trimmed)
        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
    EusVersionLockResult {
        found: releasever.is_some(),
        has_releasever_file: releasever.is_some(),
        releasever,
            source_path: source_path.to_string(),
}
}

pub fn parse_rhel_rhui_check(content: &str, source_path: &str) -> RhelRhuiCheckResult {
    let mut pkgs = Vec::new();
    let mut is_eus = false;
    let mut is_sap = false;
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(c) = crate::cached_regex!(r"^(rhui-[a-zA-Z0-9\-.]+)")
            .captures(trimmed)
        {
            let pkg = c[1].to_string();
            if crate::cached_regex!(r"(?i)-eus-|-e4s-").is_match(&pkg) {
                is_eus = true;
            }
            if crate::cached_regex!(r"(?i)-sap-").is_match(&pkg) {
                is_sap = true;
            }
            pkgs.push(pkg);
        }
    }
    let rhui_type = if is_sap && is_eus {
        Some("SAP-EUS".to_string())
    } else if is_sap {
        Some("SAP".to_string())
    } else if is_eus {
        Some("EUS".to_string())
    } else if !pkgs.is_empty() {
        Some("Standard".to_string())
    } else {
        None
    };
    let mut warnings = Vec::new();
    if pkgs.is_empty() {
        warnings.push(UnixWarning {
            r#type: "rhui_package_missing".to_string(),
            severity: "warning".to_string(),
            message: "No RHUI package found. RHEL VMs on Azure require RHUI packages for updates.".to_string(),
            recommendation: Some("Install the appropriate RHUI package for your subscription type.".to_string()),
            documentation_url: Some("https://learn.microsoft.com/troubleshoot/azure/virtual-machines/troubleshoot-linux-rhui-certificate-issues#cause-3-rhui-package-is-missing".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    RhelRhuiCheckResult {
        found: !pkgs.is_empty(),
        rhui_packages: pkgs.clone(),
        has_rhui_package: !pkgs.is_empty(),
        rhui_type,
        is_eus,
        is_sap,
        warnings,
        recommendations: Vec::new(),
            source_path: source_path.to_string(),
}
}

pub fn parse_crypto_policies(content: &str, source_path: &str) -> CryptoPoliciesResult {
    let policy = content.lines().next().map(|l| l.trim().to_string()).filter(|s| !s.is_empty());
    let is_default = policy.as_deref().map(|p| p == "DEFAULT" || p == "DEFAULT:SHA1").unwrap_or(true);
    let mut warnings = Vec::new();
    if let Some(pol) = &policy {
        if !is_default {
            warnings.push(UnixWarning {
                r#type: "crypto_policy_non_default".to_string(),
                severity: "warning".to_string(),
                message: format!("Crypto policy is set to '{}' instead of 'DEFAULT'.", pol),
                recommendation: Some("Set crypto policy to DEFAULT using update-crypto-policies --set DEFAULT".to_string()),
                documentation_url: Some("https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues#cause-5-verification-error-in-rhel-version-8-or-9-ca-certificate-key-too-weak".to_string()),
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
    }
    CryptoPoliciesResult {
        found: policy.is_some(),
        policy,
        is_default,
        warnings,
        recommendations: Vec::new(),
            source_path: source_path.to_string(),
}
}

pub fn parse_fips_mode_setup(content: &str, source_path: &str) -> FipsModeSetupResult {
    let trimmed = content.trim();
    let found = !trimmed.is_empty();
    let fips_enabled = crate::cached_regex!(r"(?i)FIPS mode is enabled").is_match(trimmed);
    let inconsistent_state = crate::cached_regex!(r"(?i)inconsistent.*state").is_match(trimmed);
    let mut warnings = Vec::new();
    if inconsistent_state {
        warnings.push(UnixWarning {
            r#type: "fips_inconsistent_state".to_string(),
            severity: "warning".to_string(),
            message: "FIPS mode is in an inconsistent state.".to_string(),
            recommendation: Some("Run fips-mode-setup --enable or --disable and reboot.".to_string()),
            documentation_url: Some("https://learn.microsoft.com/en-us/azure/virtual-machines/linux/fips-overview".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    FipsModeSetupResult {
        found,
        fips_enabled,
        inconsistent_state,
        raw_output: trimmed.chars().take(500).collect(),
        warnings,
            source_path: source_path.to_string(),
}
}

pub fn parse_kernel_cmdline(content: &str, source_path: &str) -> KernelCmdlineResult {
    let cmdline = content.trim().lines().next().unwrap_or("").to_string();
    let mut result = KernelCmdlineResult {
        found: !cmdline.is_empty(),
        fips_enabled: false,
        crashkernel: None,
        root_device: None,
        raw_cmdline: cmdline.clone(),
        warnings: Vec::new(),
            source_path: source_path.to_string(),
};
    for p in cmdline.split_whitespace() {
        if p == "fips=1" {
            result.fips_enabled = true;
        }
        if let Some(v) = p.strip_prefix("crashkernel=") {
            result.crashkernel = Some(v.to_string());
        }
        if let Some(v) = p.strip_prefix("root=") {
            result.root_device = Some(v.to_string());
        }
    }
    result
}

pub fn parse_rhui_errors(content: &str, source_path: &str) -> RhuiErrorsResult {
    let mut result = RhuiErrorsResult {
        found: false,
        has_cert_expiration: false,
        has_http403: false,
        has_http400: false,
        has_connection_error: false,
        errors: Vec::new(),
        affected_repos: Vec::new(),
        warnings: Vec::new(),
        recommendations: Vec::new(),
            source_path: source_path.to_string(),
};

    for (idx, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        if crate::cached_regex!(r"(?i)SSL certificate problem.*expired|certificate has expired|CERTIFICATE_VERIFY_FAILED|certificate verify failed|unable to get local issuer certificate")
            .is_match(trimmed)
        {
            result.found = true;
            result.has_cert_expiration = true;
            result.errors.push(ErrorItem {
                r#type: "certificate_expired".to_string(),
                line: idx + 1,
                message: "RHUI client certificate has expired or cannot be verified".to_string(),
                sample: trimmed.chars().take(200).collect(),
                repo: None,
                eus_version: None,
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
        if crate::cached_regex!(r"Status code: 403 .*microsoft\.com")
            .is_match(trimmed)
        {
            result.found = true;
            result.has_http403 = true;
            result.errors.push(ErrorItem {
                r#type: "http_403".to_string(),
                line: idx + 1,
                message: "HTTP 403 from RHUI servers".to_string(),
                sample: trimmed.chars().take(200).collect(),
                repo: None,
                eus_version: None,
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
        if let Some(c) = crate::cached_regex!(r"Status code: 400 .*?/eus/rhel\d+/rhui/(\d+\.\d+)/")
            .captures(trimmed)
        {
            result.found = true;
            result.has_http400 = true;
            result.errors.push(ErrorItem {
                r#type: "http_400".to_string(),
                line: idx + 1,
                message: format!("HTTP 400 Bad Request - EUS version {} may be unavailable", &c[1]),
                sample: trimmed.chars().take(200).collect(),
                repo: None,
                eus_version: Some(c[1].to_string()),
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
        if crate::cached_regex!(r"(?i)Curl error \(28\)|Curl error \(7\)|Could not resolve host|Connection timed out|Connection refused|Curl error \(6\)")
            .is_match(trimmed)
            && crate::cached_regex!(r"(?i)rhui|microsoft").is_match(trimmed)
        {
            result.found = true;
            result.has_connection_error = true;
            result.errors.push(ErrorItem {
                r#type: "connection_error".to_string(),
                line: idx + 1,
                message: "Network connectivity issue to RHUI servers".to_string(),
                sample: trimmed.chars().take(200).collect(),
                repo: None,
                eus_version: None,
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
        if let Some(c) = crate::cached_regex!(r#"Failed to download metadata for repo[:\s]+['\"]?([^'\":\s]+)"#)
            .captures(trimmed)
        {
            let repo = c[1].to_string();
            if !result.affected_repos.contains(&repo) {
                result.affected_repos.push(repo);
            }
            result.found = true;
        }
    }
    if result.has_cert_expiration || result.has_http403 {
        result.warnings.push(UnixWarning {
            r#type: "rhui_cert_expired".to_string(),
            severity: "warning".to_string(),
            message: "RHUI client certificate appears to be expired or invalid".to_string(),
            recommendation: Some("Reinstall the RHUI package to renew certificates.".to_string()),
            documentation_url: Some("https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if result.has_http400 {
        result.warnings.push(UnixWarning {
            r#type: "eus_version_unavailable".to_string(),
            severity: "warning".to_string(),
            message: "HTTP 400 errors from RHUI indicate an unavailable EUS version or config issue.".to_string(),
            recommendation: Some("Update the releasever lock or switch to a supported RHUI repo set.".to_string()),
            documentation_url: Some("https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui#rhel-eus-and-version-locking-rhel-vms".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if result.has_connection_error {
        result.warnings.push(UnixWarning {
            r#type: "rhui_connectivity".to_string(),
            severity: "warning".to_string(),
            message: "Network connectivity issues to RHUI servers detected".to_string(),
            recommendation: Some("Check NSG rules, DNS, and outbound connectivity to rhui-*.microsoft.com on port 443.".to_string()),
            documentation_url: Some("https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui#troubleshoot-connection-problems-to-azure-rhui".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    result
}

pub fn parse_leapp_report(content: &str, source_path: &str) -> LeappReportResult {
    let mut result = LeappReportResult {
        found: false,
        has_errors: false,
        has_high_risk: false,
        has_medium_risk: false,
        upgrade_blocked: false,
        total_issues: 0,
        error_count: 0,
        high_risk_count: 0,
        medium_risk_count: 0,
        low_risk_count: 0,
        info_count: 0,
        issues: Vec::new(),
        third_party_packages: Vec::new(),
        warnings: Vec::new(),
        recommendations: Vec::new(),
            source_path: source_path.to_string(),
};

    let entries = crate::cached_regex!(r"(?m)^-{30,}$")
        .split(content)
        .filter(|e| !e.trim().is_empty())
        .collect::<Vec<_>>();

    for entry in entries {
        let mut risk_factor = None;
        let mut is_error = false;
        let mut title = None;
        let mut summary = String::new();
        let mut remediation = None;
        let mut key = None;
        let mut current = None::<&str>;
        for line in entry.lines() {
            if let Some(c) = crate::cached_regex!(r"^Risk Factor:\s*(\w+)(?:\s*\(error\))?")
                .captures(line)
            {
                risk_factor = Some(c[1].to_ascii_lowercase());
                is_error = line.to_ascii_lowercase().contains("(error)");
                current = None;
                continue;
            }
            if let Some(c) = crate::cached_regex!(r"^Title:\s*(.+)$").captures(line) {
                title = Some(c[1].trim().to_string());
                current = None;
                continue;
            }
            if let Some(c) = crate::cached_regex!(r"^Summary:\s*(.*)$").captures(line) {
                summary = c[1].to_string();
                current = Some("summary");
                continue;
            }
            if let Some(c) = crate::cached_regex!(r"^Remediation:\s*(.*)$").captures(line) {
                remediation = Some(c[1].to_string());
                current = Some("remediation");
                continue;
            }
            if let Some(c) = crate::cached_regex!(r"^Key:\s*(\w+)").captures(line) {
                key = Some(c[1].to_string());
                current = None;
                continue;
            }
            if line.trim().starts_with("Related links:") {
                current = None;
                continue;
            }
            if let Some(field) = current {
                if !line.trim().is_empty() {
                    if field == "summary" {
                        summary.push(' ');
                        summary.push_str(line.trim());
                    } else if field == "remediation" {
                        remediation = Some(format!("{} {}", remediation.unwrap_or_default(), line.trim()).trim().to_string());
                    }
                }
            }
        }
        let Some(title) = title else { continue; };
        result.found = true;
        result.total_issues += 1;
        let issue = LeappIssue {
            risk_factor: risk_factor.clone(),
            is_error,
            title: title.clone(),
            summary: summary.trim().to_string(),
            remediation,
            key,
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
};
        if is_error {
            result.error_count += 1;
            result.has_errors = true;
            result.upgrade_blocked = true;
        } else if risk_factor.as_deref() == Some("high") {
            result.high_risk_count += 1;
            result.has_high_risk = true;
        } else if risk_factor.as_deref() == Some("medium") {
            result.medium_risk_count += 1;
            result.has_medium_risk = true;
        } else if risk_factor.as_deref() == Some("low") {
            result.low_risk_count += 1;
        } else if risk_factor.as_deref() == Some("info") {
            result.info_count += 1;
        }
        if title.contains("not signed by the distribution vendor") {
            for pkg in crate::cached_regex!(r"-\s*(\S+)")
                .captures_iter(&summary)
                .filter_map(|c| c.get(1).map(|m| m.as_str().to_string()))
            {
                result.third_party_packages.push(pkg);
            }
        }
        result.issues.push(issue);
    }

    if result.upgrade_blocked {
        result.warnings.push(UnixWarning {
            r#type: "leapp_upgrade_blocked".to_string(),
            severity: "error".to_string(),
            message: format!("Leapp detected {} error(s) that will block the upgrade", result.error_count),
            recommendation: Some("Resolve all reported errors before attempting the upgrade.".to_string()),
            documentation_url: Some("https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/upgrading_from_rhel_8_to_rhel_9/index".to_string()),
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if result.has_high_risk && !result.upgrade_blocked {
        result.warnings.push(UnixWarning {
            r#type: "leapp_high_risk".to_string(),
            severity: "warning".to_string(),
            message: format!("Leapp detected {} high-risk warning(s)", result.high_risk_count),
            recommendation: Some("Review all high-risk items before the upgrade.".to_string()),
            documentation_url: None,
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if !result.third_party_packages.is_empty() {
        result.warnings.push(UnixWarning {
            r#type: "leapp_third_party".to_string(),
            severity: "warning".to_string(),
            message: format!("{} third-party packages detected that may need manual handling", result.third_party_packages.len()),
            recommendation: Some("Consider removing third-party packages before the upgrade and reinstalling afterward.".to_string()),
            documentation_url: None,
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    result
}

pub fn parse_leapp_log(content: &str, source_path: &str) -> LeappLogResult {
    let mut result = LeappLogResult {
        found: false,
        has_errors: false,
        has_curl_errors: false,
        has_dns_errors: false,
        has_rhui_errors: false,
        error_count: 0,
        warning_count: 0,
        critical_count: 0,
        errors: Vec::new(),
        warnings: Vec::new(),
        recommendations: Vec::new(),
            source_path: source_path.to_string(),
};
    for (idx, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        let lower = trimmed.to_ascii_lowercase();
        if lower.contains(" curl error (") {
            result.found = true;
            result.has_errors = true;
            result.has_curl_errors = true;
            result.error_count += 1;
            if lower.contains("resolve host") {
                result.has_dns_errors = true;
            }
            if lower.contains("rhui") || lower.contains("microsoft") {
                result.has_rhui_errors = true;
            }
            result.errors.push(ErrorItem {
                r#type: "curl_error".to_string(),
                line: idx + 1,
                message: "Curl error detected in Leapp log".to_string(),
                sample: trimmed.chars().take(400).collect(),
                repo: None,
                eus_version: None,
                            source_path: String::new(),
                source_line: None,
                source_line_end: None,
});
        }
        if crate::cached_regex!(r"^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}[.\d]*\s+ERROR\s+")
            .is_match(trimmed)
        {
            result.found = true;
            result.has_errors = true;
            result.error_count += 1;
        }
        if crate::cached_regex!(r"^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}[.\d]*\s+CRITICAL\s+")
            .is_match(trimmed)
        {
            result.found = true;
            result.critical_count += 1;
        }
        if lower.contains("warning") {
            result.warning_count += 1;
        }
    }
    if result.has_dns_errors {
        result.warnings.push(UnixWarning {
            r#type: "leapp_dns_error".to_string(),
            severity: "warning".to_string(),
            message: "DNS resolution issues were detected during the Leapp workflow.".to_string(),
            recommendation: Some("Verify RHUI and general outbound DNS resolution before re-running Leapp.".to_string()),
            documentation_url: None,
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    if result.has_rhui_errors {
        result.warnings.push(UnixWarning {
            r#type: "leapp_rhui_error".to_string(),
            severity: "warning".to_string(),
            message: "RHUI-related errors were detected in the Leapp log.".to_string(),
            recommendation: Some("Check RHUI configuration, certificates, and connectivity.".to_string()),
            documentation_url: None,
                    source_path: String::new(),
            source_line: None,
            source_line_end: None,
});
    }
    result
}

macro_rules! json_wrap {
    ($name:ident, $func:ident) => {
        pub fn $name(content: &str, source_path: &str) -> String {
            let result = $func(content, source_path);
            let mut value = match serde_json::to_value(&result) {
                Ok(v) => v,
                Err(_) => return "{}".to_string(),
            };
            crate::parsers::fill_source_path(&mut value, source_path);
            serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
        }
    };
}

json_wrap!(parse_basic_environment_json, parse_basic_environment);
json_wrap!(parse_os_release_json, parse_os_release);
json_wrap!(parse_fstab_json, parse_fstab);
json_wrap!(parse_inspect_disk_results_json, parse_inspect_disk_results);
json_wrap!(parse_kernel_tuning_json, parse_kernel_tuning);
json_wrap!(parse_huge_pages_json, parse_huge_pages);
json_wrap!(parse_time_sync_json, parse_time_sync);
json_wrap!(parse_ptp_clock_source_json, parse_ptp_clock_source);
json_wrap!(parse_time_sync_service_json, parse_time_sync_service);
json_wrap!(parse_timedatectl_json, parse_timedatectl);
json_wrap!(parse_ptp_device_json, parse_ptp_device);
json_wrap!(parse_chrony_tracking_json, parse_chrony_tracking);
json_wrap!(parse_chrony_makestep_json, parse_chrony_makestep);
json_wrap!(parse_rhui_config_json, parse_rhui_config);
json_wrap!(parse_eus_version_lock_json, parse_eus_version_lock);
json_wrap!(parse_rhel_rhui_check_json, parse_rhel_rhui_check);
json_wrap!(parse_crypto_policies_json, parse_crypto_policies);
json_wrap!(parse_fips_mode_setup_json, parse_fips_mode_setup);
json_wrap!(parse_kernel_cmdline_json, parse_kernel_cmdline);
json_wrap!(parse_rhui_errors_json, parse_rhui_errors);
json_wrap!(parse_leapp_report_json, parse_leapp_report);
json_wrap!(parse_leapp_log_json, parse_leapp_log);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_os_release_and_eol_warning() {
        let input = "NAME=\"CentOS Linux\"\nVERSION_ID=\"7.9\"\nPRETTY_NAME=\"CentOS Linux 7\"\n";
        let result = parse_os_release(input, "");
        assert!(result.found);
        assert!(result.is_eol);
    }

    #[test]
    fn parses_kernel_tuning_and_fips() {
        let input = concat!(
            "vm.swappiness = 60\n",
            "net.ipv4.tcp_congestion_control = cubic\n",
            "crypto.fips_enabled = 1\n"
        );
        let result = parse_kernel_tuning(input, "");
        assert!(result.found);
        assert!(result.fips_enabled);
        assert!(!result.warnings.is_empty());
    }

    #[test]
    fn parses_timedatectl_and_chrony() {
        let timed = parse_timedatectl("System clock synchronized: yes\nNTP service: active\nTime zone: UTC\n", "");
        let chrony = parse_chrony_tracking("Reference ID    : 50484330 (PHC0)\nLast offset     : +0.000000718 seconds\nLeap status     : Normal\n", "");
        assert!(timed.found);
        assert!(timed.ntp_enabled);
        assert!(chrony.is_ptp_source);
    }

    #[test]
    fn parses_rhui_and_leapp() {
        let rhui = parse_rhel_rhui_check("rhui-microsoft-azure-rhel8-1.0-1\n", "");
        let leapp = parse_leapp_report("Risk Factor: high\nTitle: Test issue\nSummary: Something important\n----------------------------------------\n", "");
        assert!(rhui.found);
        assert!(leapp.found);
        assert_eq!(leapp.total_issues, 1);
    }

    #[test]
    fn os_release_carries_source_path() {
        let input = "NAME=\"Red Hat Enterprise Linux\"\nVERSION_ID=\"7.9\"\n";
        let result = parse_os_release(input, "etc/os-release");
        assert_eq!(result.source_path, "etc/os-release");
        // EOL warning gets the source_path stamped via the json wrapper.
        let json = parse_os_release_json(input, "etc/os-release");
        assert!(json.contains("\"source_path\":\"etc/os-release\""));
        // The warning object inside is also stamped (from the wrapper post-pass).
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        let warnings = v["warnings"].as_array().expect("warnings array");
        assert!(!warnings.is_empty());
        assert_eq!(warnings[0]["source_path"], "etc/os-release");
    }

    #[test]
    fn rhui_config_carries_source_path() {
        let input = "[rhui-microsoft-azure-rhel8]\nname=Microsoft Azure RHUI\nenabled=1\n";
        let json = parse_rhui_config_json(input, "etc/yum.repos.d/rh-cloud.repo");
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["source_path"], "etc/yum.repos.d/rh-cloud.repo");
        let repos = v["repos"].as_array().expect("repos array");
        if !repos.is_empty() {
            assert_eq!(repos[0]["source_path"], "etc/yum.repos.d/rh-cloud.repo");
        }
    }
}
