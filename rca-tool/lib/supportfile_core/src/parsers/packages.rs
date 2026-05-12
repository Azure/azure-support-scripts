use regex::Regex;
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PackageWarning {
    pub package: String,
    pub expected: String,
    pub actual: String,
    pub severity: String,
    pub message: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FipsPackage {
    pub name: String,
    pub version: String,
    pub source_path: String,
    pub source_line: Option<usize>,
    pub source_line_end: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DistroPackagesResult {
    pub found: bool,
    pub is_dpkg: bool,
    pub is_rpm_raw: bool,
    pub is_zypper_history: bool,
    pub is_dnf_yum_log: bool,
    pub raw_content: Option<String>,
    pub package_count: usize,
    pub packages: BTreeMap<String, String>,
    pub warnings: Vec<PackageWarning>,
    pub fips_packages: Vec<FipsPackage>,
    pub has_dracut_fips: bool,
    pub source_path: String,
}

#[derive(Clone, Copy)]
enum PackageRule {
    Gte(&'static str),
    ProblemRange(&'static str, &'static str),
}

const REQUIRED_PACKAGES: &[(&str, PackageRule)] = &[
    ("fence-agents", PackageRule::Gte("4.4")),
    ("python3-azure-mgmt-compute", PackageRule::Gte("17.0")),
    ("python3-azure-identity", PackageRule::Gte("1.0")),
    ("cloud-netconfig-azure", PackageRule::Gte("1.3")),
    ("resource-agents", PackageRule::Gte("4.3")),
    ("python3-azure-core", PackageRule::ProblemRange("1.9", "1.22")),
];

/// Per-package metadata captured during parsing: version + source line in the
/// original file. Tracked as (name, version, line_no).
type PackageEntry = (String, String, usize);

fn extract_numeric_version(input: &str) -> Option<String> {
    crate::cached_regex!(r"(\d+\.\d+(?:\.\d+)?)")
        .captures(input)
        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
}

fn compare_versions(a: &str, b: &str) -> Ordering {
    let parse_parts = |v: &str| {
        v.split('.')
            .map(|p| p.parse::<i64>().unwrap_or(0))
            .collect::<Vec<_>>()
    };

    let mut left = parse_parts(a);
    let mut right = parse_parts(b);
    let max_len = left.len().max(right.len());
    left.resize(max_len, 0);
    right.resize(max_len, 0);

    for (l, r) in left.into_iter().zip(right.into_iter()) {
        match l.cmp(&r) {
            Ordering::Equal => continue,
            other => return other,
        }
    }
    Ordering::Equal
}

fn split_rpm_name_version(token: &str) -> Option<(String, String)> {
    let trimmed = token.trim();
    if trimmed.is_empty() {
        return None;
    }

    let without_arch = if let Some(idx) = trimmed.rfind('.') {
        let suffix = &trimmed[idx + 1..];
        if suffix.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            &trimmed[..idx]
        } else {
            trimmed
        }
    } else {
        trimmed
    };

    let bytes = without_arch.as_bytes();
    for i in 1..without_arch.len() {
        if bytes[i - 1] == b'-' && bytes[i].is_ascii_digit() {
            let name = without_arch[..i - 1].to_string();
            let version = without_arch[i..].to_string();
            if !name.is_empty() && !version.is_empty() {
                return Some((name, version));
            }
        }
    }
    None
}

fn build_lookup(entries: &[PackageEntry]) -> BTreeMap<String, (String, usize)> {
    let mut map = BTreeMap::new();
    for (name, version, line_no) in entries {
        map.entry(name.clone())
            .or_insert_with(|| (version.clone(), *line_no));
    }
    map
}

fn validate_packages(
    entries: &[PackageEntry],
    source_path: &str,
) -> (BTreeMap<String, String>, Vec<PackageWarning>) {
    let lookup = build_lookup(entries);
    let mut found = BTreeMap::new();
    let mut warnings = Vec::new();

    for (req_name, rule) in REQUIRED_PACKAGES {
        let matched = lookup
            .iter()
            .find(|(name, _)| *name == req_name || name.starts_with(&format!("{}-", req_name)));

        let Some((matched_name, (matched_version_raw, matched_line))) = matched else {
            let expected = match rule {
                PackageRule::Gte(v) => format!(">= {}", v),
                PackageRule::ProblemRange(min, max) => format!("< {} or > {}", min, max),
            };
            warnings.push(PackageWarning {
                package: req_name.to_string(),
                expected,
                actual: "not found".to_string(),
                severity: "error".to_string(),
                message: format!("Required package {} not found in package list", req_name),
                source_path: source_path.to_string(),
                source_line: None,
                source_line_end: None,
            });
            continue;
        };

        let version = extract_numeric_version(matched_version_raw).unwrap_or_else(|| matched_version_raw.clone());
        found.insert(matched_name.clone(), version.clone());
        let line = Some(*matched_line);

        match rule {
            PackageRule::Gte(min) => {
                if compare_versions(&version, min) == Ordering::Less {
                    warnings.push(PackageWarning {
                        package: req_name.to_string(),
                        expected: format!(">= {}", min),
                        actual: version.clone(),
                        severity: "error".to_string(),
                        message: format!(
                            "Package {} version is {}, but should be >= {} for Azure environments",
                            req_name, version, min
                        ),
                        source_path: source_path.to_string(),
                        source_line: line,
                        source_line_end: line,
                    });
                }
            }
            PackageRule::ProblemRange(min, max) => {
                if compare_versions(&version, min) != Ordering::Less
                    && compare_versions(&version, max) != Ordering::Greater
                {
                    warnings.push(PackageWarning {
                        package: req_name.to_string(),
                        expected: format!("< {} or > {}", min, max),
                        actual: version.clone(),
                        severity: "error".to_string(),
                        message: format!(
                            "Package {} version is {}, but should be lower than {} or higher than {} for Azure environments",
                            req_name, version, min, max
                        ),
                        source_path: source_path.to_string(),
                        source_line: line,
                        source_line_end: line,
                    });
                }
            }
        }
    }

    (found, warnings)
}

fn collect_fips_packages(entries: &[PackageEntry], source_path: &str) -> Vec<FipsPackage> {
    let fips_prefixes = ["dracut-fips", "fipscheck", "fips-mode-setup", "crypto-policies"];
    entries
        .iter()
        .filter(|(name, _, _)| {
            fips_prefixes
                .iter()
                .any(|prefix| name == prefix || name.starts_with(&format!("{}-", prefix)))
        })
        .map(|(name, version, line_no)| FipsPackage {
            name: name.clone(),
            version: version.clone(),
            source_path: source_path.to_string(),
            source_line: Some(*line_no),
            source_line_end: Some(*line_no),
        })
        .collect()
}

fn parse_package_entries_from_raw_listing(content: &str) -> Vec<PackageEntry> {
    let mut entries = Vec::new();
    for (i, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        if trimmed.is_empty()
            || trimmed.starts_with("Desired")
            || trimmed.starts_with('|')
            || trimmed.starts_with("+++")
            || trimmed.starts_with("Installed Packages")
            || trimmed.starts_with("Last metadata")
            || trimmed.starts_with("Loaded plugins")
        {
            continue;
        }

        let token = trimmed.split_whitespace().next().unwrap_or(trimmed);
        if let Some((name, version)) = split_rpm_name_version(token) {
            entries.push((name, version, i + 1));
        }
    }
    entries
}

fn parse_zypper_history(content: &str) -> (Vec<PackageEntry>, Vec<String>) {
    let mut entries = Vec::new();
    let mut raw_lines = Vec::new();
    for (i, line) in content.lines().enumerate() {
        if line.starts_with('#') || !line.contains('|') {
            continue;
        }
        let parts = line.split('|').map(|s| s.trim()).collect::<Vec<_>>();
        if parts.len() < 4 || parts[1] != "install" {
            continue;
        }
        let name = parts[2].to_string();
        let version = parts[3].to_string();
        entries.push((name.clone(), version.clone(), i + 1));
        raw_lines.push(format!("{}|{}|{}", name, version, parts[0]));
    }
    (entries, raw_lines)
}

fn parse_dnf_yum_log(content: &str) -> (Vec<PackageEntry>, Vec<String>) {
    let installed_re = crate::cached_regex!(r"(?:^\d{4}-\d{2}-\d{2}|^[A-Z][a-z]{2}\s+\d+).*?Installed:\s*(.+)");
    let mut entries = Vec::new();
    let mut raw_lines = Vec::new();

    for (i, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        if let Some(caps) = installed_re.captures(trimmed) {
            let pkg_str = caps.get(1).map(|m| m.as_str().trim()).unwrap_or_default();
            if let Some((name, version)) = split_rpm_name_version(pkg_str) {
                entries.push((name.clone(), version.clone(), i + 1));
                let date = trimmed.chars().take(19).collect::<String>();
                raw_lines.push(format!("{}|{}|{}", name, version, date));
            }
        }
    }

    (entries, raw_lines)
}

pub fn parse_distro_packages(content: &str, source_path: &str) -> DistroPackagesResult {
    let trimmed = content.trim();
    let empty = DistroPackagesResult {
        found: false,
        is_dpkg: false,
        is_rpm_raw: false,
        is_zypper_history: false,
        is_dnf_yum_log: false,
        raw_content: None,
        package_count: 0,
        packages: BTreeMap::new(),
        warnings: Vec::new(),
        fips_packages: Vec::new(),
        has_dracut_fips: false,
        source_path: source_path.to_string(),
    };
    if trimmed.is_empty() {
        return empty;
    }

    // Special-case file types by filename, mirroring the legacy JS parser.
    let lower_path = source_path.to_lowercase();
    let is_yum_dnf_listing = lower_path.contains("dnf_list_installed")
        || lower_path.contains("dnf-list-installed")
        || lower_path.contains("dnf_list-installed")
        || lower_path.contains("yum_list_installed")
        || lower_path.contains("yum-list-installed")
        || lower_path.contains("yum_list-installed");
    let is_supportconfig_rpm_txt = lower_path.ends_with("/rpm.txt") || lower_path == "rpm.txt";

    if is_yum_dnf_listing {
        let kept: Vec<&str> = trimmed
            .lines()
            .filter(|l| {
                let t = l.trim();
                if t.is_empty() {
                    return true;
                }
                if l.starts_with("Installed Packages")
                    || l.starts_with("Last metadata")
                    || l.starts_with("Loaded plugins")
                {
                    return false;
                }
                if t.starts_with(": manager") || t.starts_with(": plugins") {
                    return false;
                }
                if l.starts_with("Repository") && l.contains("is listed more than once") {
                    return false;
                }
                true
            })
            .collect();
        let filtered = kept.join("\n");
        let entries = parse_package_entries_from_raw_listing(&filtered);
        let pkg_count = trimmed
            .lines()
            .filter(|l| {
                let t = l.trim();
                !t.is_empty()
                    && !l.starts_with("Installed")
                    && !l.starts_with("Last metadata")
                    && !l.starts_with("Loaded plugins")
            })
            .count();
        let fips_packages = collect_fips_packages(&entries, source_path);
        let has_dracut_fips = fips_packages
            .iter()
            .any(|p| p.name == "dracut-fips" || p.name.starts_with("dracut-fips-"));
        let (packages, warnings) = validate_packages(&entries, source_path);
        return DistroPackagesResult {
            found: true,
            is_dpkg: false,
            is_rpm_raw: true,
            is_zypper_history: false,
            is_dnf_yum_log: false,
            raw_content: Some(filtered),
            package_count: pkg_count,
            packages,
            warnings,
            fips_packages,
            has_dracut_fips,
            source_path: source_path.to_string(),
        };
    }

    if is_supportconfig_rpm_txt {
        let queryformat_start = Regex::new(
            r"(?i)^# rpm -qa --queryformat.*NAME.*DISTRIBUTION.*VERSION",
        )
        .unwrap();
        let queryformat_sigpgp = crate::cached_regex!(r"(?i)^# rpm -qa --queryformat.*SIGPGP");
        let mut kept: Vec<&str> = Vec::new();
        let mut in_pkg_list = false;
        for line in trimmed.lines() {
            if queryformat_start.is_match(line) {
                in_pkg_list = true;
                continue;
            }
            if line.starts_with("#==[ Command ]======") || queryformat_sigpgp.is_match(line) {
                in_pkg_list = false;
            }
            if in_pkg_list {
                kept.push(line);
            }
        }
        let filtered = kept.join("\n");
        // Lines look like: "name  DISTRIBUTION  version" — name is first token, version is last.
        let mut entries: Vec<PackageEntry> = Vec::new();
        for (i, line) in filtered.lines().enumerate() {
            let t = line.trim();
            if t.is_empty()
                || t.starts_with("NAME")
                || t.starts_with("DISTRIBUTION")
            {
                continue;
            }
            let toks: Vec<&str> = t.split_whitespace().collect();
            if toks.len() < 2 {
                continue;
            }
            let name = toks[0].to_string();
            let version = toks[toks.len() - 1].to_string();
            entries.push((name, version, i + 1));
        }
        let pkg_count = filtered
            .lines()
            .filter(|l| {
                let t = l.trim();
                !t.is_empty() && !t.starts_with("NAME") && !t.starts_with("DISTRIBUTION")
            })
            .count();
        let fips_packages = collect_fips_packages(&entries, source_path);
        let has_dracut_fips = fips_packages
            .iter()
            .any(|p| p.name == "dracut-fips" || p.name.starts_with("dracut-fips-"));
        let (packages, warnings) = validate_packages(&entries, source_path);
        return DistroPackagesResult {
            found: true,
            is_dpkg: false,
            is_rpm_raw: true,
            is_zypper_history: false,
            is_dnf_yum_log: false,
            raw_content: Some(filtered),
            package_count: pkg_count,
            packages,
            warnings,
            fips_packages,
            has_dracut_fips,
            source_path: source_path.to_string(),
        };
    }

    if trimmed.contains("Desired=Unknown/Install/Remove/Purge/Hold") {
        let package_count = trimmed
            .lines()
            .filter(|l| {
                let t = l.trim();
                !t.is_empty() && !t.starts_with("Desired") && !t.starts_with('|') && !t.starts_with("+++")
            })
            .count();
        return DistroPackagesResult {
            found: true,
            is_dpkg: true,
            is_rpm_raw: false,
            is_zypper_history: false,
            is_dnf_yum_log: false,
            raw_content: Some(trimmed.to_string()),
            package_count,
            packages: BTreeMap::new(),
            warnings: Vec::new(),
            fips_packages: Vec::new(),
            has_dracut_fips: false,
            source_path: source_path.to_string(),
        };
    }

    let (entries, raw_content, is_zypper_history, is_dnf_yum_log, is_rpm_raw) = if trimmed.lines().any(|l| l.contains("|install|")) {
        let (entries, raw_lines) = parse_zypper_history(trimmed);
        (entries, Some(raw_lines.join("\n")), true, false, true)
    } else if trimmed.lines().any(|l| l.contains("Installed:")) {
        let (entries, raw_lines) = parse_dnf_yum_log(trimmed);
        (entries, Some(raw_lines.join("\n")), false, true, true)
    } else {
        let entries = parse_package_entries_from_raw_listing(trimmed);
        let count = trimmed
            .lines()
            .filter(|l| {
                let t = l.trim();
                !t.is_empty()
                    && !t.starts_with("Installed Packages")
                    && !t.starts_with("Last metadata")
                    && !t.starts_with("Loaded plugins")
            })
            .count();
        let raw = if count > 0 { Some(trimmed.to_string()) } else { None };
        (entries, raw, false, false, true)
    };

    if entries.is_empty() && raw_content.is_none() {
        return empty;
    }

    let package_count = entries.len();
    let fips_packages = collect_fips_packages(&entries, source_path);
    let has_dracut_fips = fips_packages
        .iter()
        .any(|p| p.name == "dracut-fips" || p.name.starts_with("dracut-fips-"));
    let (packages, warnings) = validate_packages(&entries, source_path);

    DistroPackagesResult {
        found: true,
        is_dpkg: false,
        is_rpm_raw,
        is_zypper_history,
        is_dnf_yum_log,
        raw_content,
        package_count,
        packages,
        warnings,
        fips_packages,
        has_dracut_fips,
        source_path: source_path.to_string(),
    }
}

pub fn parse_distro_packages_json(content: &str, source_path: &str) -> String {
    serde_json::to_string(&parse_distro_packages(content, source_path)).unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PATH: &str = "sos_commands/rpm/package-data";

    #[test]
    fn validates_rpm_packages_and_fips() {
        let input = concat!(
            "fence-agents-4.12.1-1.noarch\n",
            "python3-azure-mgmt-compute-18.0-1.noarch\n",
            "python3-azure-identity-1.12.0-1.noarch\n",
            "cloud-netconfig-azure-1.5-1.noarch\n",
            "resource-agents-4.3.0-1.noarch\n",
            "python3-azure-core-1.10.0-1.noarch\n",
            "dracut-fips-049-1.noarch\n"
        );

        let result = parse_distro_packages(input, PATH);
        assert!(result.found);
        assert!(result.has_dracut_fips);
        assert!(result.warnings.iter().any(|w| w.package == "python3-azure-core"));
    }

    #[test]
    fn parses_zypper_history() {
        let input = concat!(
            "2024-01-15 10:00:00|install|fence-agents|4.12.1|x86_64|root|repo\n",
            "2024-01-15 10:00:01|install|resource-agents|4.4.0|x86_64|root|repo\n"
        );
        let result = parse_distro_packages(input, PATH);
        assert!(result.found);
        assert!(result.is_zypper_history);
        assert_eq!(result.package_count, 2);
    }

    #[test]
    fn detects_dpkg_raw_listing() {
        let input = concat!(
            "Desired=Unknown/Install/Remove/Purge/Hold\n",
            "ii  openssh-server  1:9.6p1 amd64\n"
        );
        let result = parse_distro_packages(input, PATH);
        assert!(result.found);
        assert!(result.is_dpkg);
    }

    #[test]
    fn package_warnings_carry_source_provenance() {
        // python3-azure-core 1.10.0 falls in the problem range -> warning.
        // fence-agents not present -> "not found" warning with source_line=None.
        // Layout makes line numbers predictable.
        let input = concat!(
            "resource-agents-4.3.0-1.noarch\n",
            "python3-azure-mgmt-compute-18.0-1.noarch\n",
            "python3-azure-identity-1.12.0-1.noarch\n",
            "cloud-netconfig-azure-1.5-1.noarch\n",
            "python3-azure-core-1.10.0-1.noarch\n",
            "dracut-fips-049-1.noarch\n"
        );

        let result = parse_distro_packages(input, PATH);
        assert_eq!(result.source_path, PATH);

        let core_warn = result
            .warnings
            .iter()
            .find(|w| w.package == "python3-azure-core")
            .expect("python3-azure-core warning");
        assert_eq!(core_warn.source_path, PATH);
        assert_eq!(core_warn.source_line, Some(5));

        let missing = result
            .warnings
            .iter()
            .find(|w| w.package == "fence-agents")
            .expect("fence-agents missing warning");
        assert_eq!(missing.actual, "not found");
        assert_eq!(missing.source_line, None);

        let fips = result.fips_packages.iter().find(|p| p.name.starts_with("dracut-fips")).expect("fips entry");
        assert_eq!(fips.source_line, Some(6));
        assert_eq!(fips.source_path, PATH);
    }

    #[test]
    fn packages_json_wrapper_includes_source_path() {
        let input = "fence-agents-4.12.1-1.noarch\n";
        let json = parse_distro_packages_json(input, PATH);
        assert!(json.contains("\"source_path\":\"sos_commands/rpm/package-data\""));
    }
}
