use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct IpAddressInfo {
    pub address: String,
    pub scope: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_file: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line_number: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InterfaceInfo {
    pub name: String,
    pub state: Option<String>,
    pub mac: Option<String>,
    pub mtu: Option<i64>,
    pub ipv4: Vec<IpAddressInfo>,
    pub ipv6: Vec<IpAddressInfo>,
    pub driver: Option<String>,
    pub driver_info: Option<String>,
    pub accel_net: bool,
    pub bootproto: Option<String>,
    pub master: Option<String>,
    pub iface_type: Option<String>,
    pub firmware_version: Option<String>,
    pub bus_info: Option<String>,
    pub source_path: String,
    pub source_line: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NetworkInterfacesResult {
    pub found: bool,
    pub interfaces: BTreeMap<String, InterfaceInfo>,
    pub source_path: String,
}

fn classify_driver(driver_name: &str) -> (String, bool) {
    match driver_name.trim() {
        "mlx4_core" | "mlx4_en" => ("Mellanox ConnectX-3 (mlx4)".to_string(), true),
        "mlx5_core" => ("Mellanox ConnectX-4/5/6 (mlx5)".to_string(), true),
        "mana" => ("Microsoft Azure Network Adapter (MANA)".to_string(), true),
        "hv_netvsc" => ("Hyper-V NetVSC (synthetic)".to_string(), false),
        other => (other.to_string(), false),
    }
}

fn ensure_iface<'a>(result: &'a mut NetworkInterfacesResult, name: &str, source_path: &str, source_line: Option<usize>) -> &'a mut InterfaceInfo {
    result.interfaces.entry(name.to_string()).or_insert_with(|| InterfaceInfo {
        name: name.to_string(),
        state: None,
        mac: None,
        mtu: None,
        ipv4: Vec::new(),
        ipv6: Vec::new(),
        driver: None,
        driver_info: None,
        accel_net: false,
        bootproto: None,
        master: None,
        iface_type: None,
        firmware_version: None,
        bus_info: None,
        source_path: source_path.to_string(),
        source_line,
    })
}

fn add_ipv4(iface: &mut InterfaceInfo, address: String, scope: String) {
    if !iface.ipv4.iter().any(|a| a.address == address) {
        iface.ipv4.push(IpAddressInfo { address, scope, source: None, source_file: None, line_number: None });
    }
}

fn add_ipv6(iface: &mut InterfaceInfo, address: String, scope: String) {
    if !iface.ipv6.iter().any(|a| a.address == address) {
        iface.ipv6.push(IpAddressInfo { address, scope, source: None, source_file: None, line_number: None });
    }
}

/// Split SCC supportconfig content into sections delimited by `#==[ ... ]==`
/// markers. Each section is `(heading, body)` where heading is the first
/// `# <heading>` line after the marker and body is everything until the next
/// marker.
fn extract_scc_sections(content: &str) -> Vec<(String, String)> {
    let marker_re = crate::cached_regex!(r"^#==\[.*\]==");
    let mut sections: Vec<(String, String)> = Vec::new();
    let mut current_heading: Option<String> = None;
    let mut current_body: Vec<String> = Vec::new();
    let mut expect_heading = false;
    for line in content.lines() {
        if marker_re.is_match(line) {
            if let Some(h) = current_heading.take() {
                sections.push((h, current_body.join("\n")));
                current_body.clear();
            }
            expect_heading = true;
            continue;
        }
        if expect_heading {
            if let Some(stripped) = line.strip_prefix("# ") {
                current_heading = Some(stripped.trim().to_string());
                expect_heading = false;
                continue;
            } else if line.starts_with('#') {
                current_heading = Some(line.trim_start_matches('#').trim().to_string());
                expect_heading = false;
                continue;
            }
        }
        if current_heading.is_some() {
            current_body.push(line.to_string());
        }
    }
    if let Some(h) = current_heading.take() {
        sections.push((h, current_body.join("\n")));
    }
    sections
}

fn parse_ip_addr_block(content: &str, result: &mut NetworkInterfacesResult, source_path: &str) {
    let iface_re = crate::cached_regex!(r"^\d+:\s+(\S+?):\s+<([^>]*)>\s*(.*)");
    let oneline_re = crate::cached_regex!(r"^\d+:\s+(\S+)\s+(inet6?)\s+(\S+)(?:\s+brd\s+\S+)?\s+scope\s+(\S+)");
    let mac_re = crate::cached_regex!(r"link/ether\s+([0-9a-f:]+)");
    let inet_re = crate::cached_regex!(r"inet\s+(\S+)\s+(?:brd\s+\S+\s+)?scope\s+(\S+)");
    let inet6_re = crate::cached_regex!(r"inet6\s+(\S+)\s+scope\s+(\S+)");
    let state_re = crate::cached_regex!(r"state\s+(\S+)");
    let mtu_re = crate::cached_regex!(r"mtu\s+(\d+)");
    let master_re = crate::cached_regex!(r"master\s+(\S+)");
    let mut current_iface_name: Option<String> = None;
    for (line_idx, line) in content.lines().enumerate() {
        let line_no = line_idx + 1;
        // Try `ip -o addr` single-line format first.
        if let Some(caps) = oneline_re.captures(line) {
            let name = caps
                .get(1)
                .map(|m| m.as_str().split('@').next().unwrap_or(m.as_str()).to_string())
                .unwrap_or_default();
            let family = caps.get(2).map(|m| m.as_str()).unwrap_or("inet");
            let addr = caps.get(3).map(|m| m.as_str().to_string()).unwrap_or_default();
            let scope = caps.get(4).map(|m| m.as_str().to_string()).unwrap_or_else(|| "global".to_string());
            if name != "lo" {
                let iface = ensure_iface(result, &name, source_path, Some(line_no));
                if family == "inet6" {
                    add_ipv6(iface, addr, scope);
                } else {
                    add_ipv4(iface, addr, scope);
                }
                if iface.iface_type.is_none() {
                    iface.iface_type = Some("ethernet".to_string());
                }
                if iface.state.is_none() {
                    iface.state = Some("UP".to_string());
                }
                result.found = true;
            }
            continue;
        }
        if let Some(caps) = iface_re.captures(line) {
            let name = caps
                .get(1)
                .map(|m| m.as_str().split('@').next().unwrap_or(m.as_str()).to_string())
                .unwrap_or_default();
            let flags = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            let rest = caps.get(3).map(|m| m.as_str()).unwrap_or_default();
            let iface = ensure_iface(result, &name, source_path, Some(line_no));
            iface.state = if let Some(state_caps) = state_re.captures(rest) {
                state_caps.get(1).map(|m| m.as_str().to_string())
            } else if flags.contains("UP") {
                Some("UP".to_string())
            } else {
                Some("DOWN".to_string())
            };
            iface.mtu = mtu_re.captures(rest).and_then(|c| c.get(1).and_then(|m| m.as_str().parse::<i64>().ok()));
            iface.iface_type = if flags.contains("LOOPBACK") {
                Some("loopback".to_string())
            } else if flags.contains("SLAVE") {
                Some("linked".to_string())
            } else {
                Some("ethernet".to_string())
            };
            iface.master = master_re.captures(rest).and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
            current_iface_name = Some(name);
            result.found = true;
            continue;
        }
        if let Some(iface_name) = current_iface_name.clone() {
            let iface = ensure_iface(result, &iface_name, source_path, None);
            if let Some(caps) = mac_re.captures(line) {
                iface.mac = caps.get(1).map(|m| m.as_str().to_string());
                continue;
            }
            if let Some(caps) = inet_re.captures(line) {
                add_ipv4(
                    iface,
                    caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                    caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_else(|| "global".to_string()),
                );
                continue;
            }
            if let Some(caps) = inet6_re.captures(line) {
                add_ipv6(
                    iface,
                    caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                    caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_else(|| "link".to_string()),
                );
                continue;
            }
        }
    }
}

fn parse_ethtool_block(content: &str, result: &mut NetworkInterfacesResult, iface_name: &str, source_path: &str) {
    if content.is_empty() {
        return;
    }
    if crate::cached_regex!(r"(?i)Cannot get driver|not supported").is_match(content) {
        return;
    }
    let driver_re = crate::cached_regex!(r"(?m)^driver:\s*(\S+)");
    let firmware_re = crate::cached_regex!(r"(?m)^firmware-version:\s*(.+)$");
    let bus_re = crate::cached_regex!(r"(?m)^bus-info:\s*(\S+)");
    let iface = ensure_iface(result, iface_name, source_path, None);
    if let Some(caps) = driver_re.captures(content) {
        let driver = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
        let (label, accel) = classify_driver(&driver);
        iface.driver = Some(driver);
        iface.driver_info = Some(label);
        iface.accel_net = accel;
    }
    if let Some(caps) = firmware_re.captures(content) {
        iface.firmware_version = caps.get(1).map(|m| m.as_str().trim().to_string());
    }
    if let Some(caps) = bus_re.captures(content) {
        iface.bus_info = caps.get(1).map(|m| m.as_str().trim().to_string());
    }
    result.found = true;
}

fn parse_ifcfg_block(content: &str, result: &mut NetworkInterfacesResult, iface_name: &str, source_path: &str) {
    let bootproto_re = crate::cached_regex!(r#"(?m)^BOOTPROTO\s*=\s*['"]?([^'"\n]+)"#);
    let ipaddr_re = crate::cached_regex!(r#"(?m)^IPADDR\s*=\s*['"]?([^'"\n]+)"#);
    let prefix_re = crate::cached_regex!(r#"(?m)^(?:PREFIX|PREFIXLEN)\s*=\s*['"]?([^'"\n]+)"#);
    let netmask_re = crate::cached_regex!(r#"(?m)^NETMASK\s*=\s*['"]?([^'"\n]+)"#);
    let iface = ensure_iface(result, iface_name, source_path, None);
    if let Some(boot) = bootproto_re
        .captures(content)
        .and_then(|c| c.get(1).map(|m| m.as_str().trim().to_ascii_lowercase()))
    {
        iface.bootproto = Some(boot);
    }
    if let Some(ip) = ipaddr_re.captures(content).and_then(|c| c.get(1).map(|m| m.as_str().trim().to_string())) {
        let prefix = prefix_re.captures(content).and_then(|c| c.get(1).map(|m| m.as_str().trim().to_string()));
        let addr = if let Some(prefix) = prefix {
            format!("{}/{}", ip, prefix)
        } else if netmask_re.captures(content).is_some() {
            ip
        } else {
            ip
        };
        add_ipv4(iface, addr, "global".to_string());
    }
    result.found = true;
}

fn iface_from_filename(source_path: &str) -> Option<(String, &'static str)> {
    // Returns (iface_name, kind) where kind is one of "ethtool" | "ifcfg".
    let name = source_path.rsplit('/').next().unwrap_or(source_path);
    if let Some(rest) = name.strip_prefix("ethtool_-i_") {
        if !rest.is_empty() {
            return Some((rest.to_string(), "ethtool"));
        }
    }
    if let Some(rest) = name.strip_prefix("ifcfg-") {
        if !rest.is_empty() {
            return Some((rest.to_string(), "ifcfg"));
        }
    }
    None
}

/// Convert a dotted IPv4 netmask (e.g. "255.255.254.0") into a CIDR prefix.
/// Returns None if the input is not a valid mask.
fn dotted_mask_to_cidr(mask: &str) -> Option<u8> {
    let octets: Result<Vec<u8>, _> = mask.split('.').map(|o| o.parse::<u8>()).collect();
    let octets = octets.ok()?;
    if octets.len() != 4 {
        return None;
    }
    let bits: u8 = octets.iter().map(|o| o.count_ones() as u8).sum();
    Some(bits)
}

/// Parse cloud-init `ci-info` Net device info tables from log files
/// (`/var/log/messages` or `/var/log/cloud-init-output.log`). If multiple
/// boot cycles are present, only the LAST block is applied.
fn parse_cloud_init_ci_info(content: &str, result: &mut NetworkInterfacesResult, source_path: &str) {
    let net_dev_re = crate::cached_regex!(r"(?i)ci-info:.*Net device info");
    let pipe_re = crate::cached_regex!(r"ci-info:.*\|");
    let route_re = crate::cached_regex!(r"(?i)ci-info:.*Route\s+IPv[46]\s+info");
    let separator_re = crate::cached_regex!(r"ci-info:.*\+[-+]+\+");
    let row_re = crate::cached_regex!(r"ci-info:\s*\|(.+)\|");

    let mut blocks: Vec<Vec<(String, usize)>> = Vec::new();
    let mut in_block = false;
    let mut current: Vec<(String, usize)> = Vec::new();

    for (idx, line) in content.lines().enumerate() {
        let line_no = idx + 1;
        if net_dev_re.is_match(line) {
            in_block = true;
            current.clear();
            continue;
        }
        if in_block {
            if pipe_re.is_match(line) {
                current.push((line.to_string(), line_no));
            } else if route_re.is_match(line) {
                if !current.is_empty() {
                    blocks.push(std::mem::take(&mut current));
                }
                in_block = false;
            } else if separator_re.is_match(line) {
                continue;
            } else {
                if !current.is_empty() {
                    blocks.push(std::mem::take(&mut current));
                }
                in_block = false;
            }
        }
    }
    if in_block && !current.is_empty() {
        blocks.push(current);
    }
    if blocks.is_empty() {
        return;
    }

    let last = blocks.last().unwrap();
    // Find header row containing "Device".
    let header_entry = match last.iter().find(|(t, _)| t.contains("Device")) {
        Some(h) => h,
        None => return,
    };
    let extract = |line: &str| -> Option<Vec<String>> {
        row_re.captures(line).map(|c| {
            c.get(1)
                .map(|m| m.as_str().split('|').map(|s| s.trim().to_string()).collect())
                .unwrap_or_default()
        })
    };
    let header_cols = match extract(&header_entry.0) {
        Some(c) => c,
        None => return,
    };

    let mut col_device: Option<usize> = None;
    let mut col_up: Option<usize> = None;
    let mut col_address: Option<usize> = None;
    let mut col_mask: Option<usize> = None;
    let mut col_scope: Option<usize> = None;
    let mut col_hw: Option<usize> = None;
    for (i, name) in header_cols.iter().enumerate() {
        let lc = name
            .to_ascii_lowercase()
            .chars()
            .filter(|c| !matches!(c, '-' | '_' | ' '))
            .collect::<String>();
        match lc.as_str() {
            "device" => col_device = Some(i),
            "up" => col_up = Some(i),
            "address" => col_address = Some(i),
            "mask" => col_mask = Some(i),
            "scope" => col_scope = Some(i),
            "hwaddress" => col_hw = Some(i),
            _ => {}
        }
    }
    let (Some(d_idx), Some(a_idx)) = (col_device, col_address) else {
        return;
    };

    for (line, line_no) in last {
        if line.contains("Device") {
            continue;
        }
        let cols = match extract(line) {
            Some(c) => c,
            None => continue,
        };
        let device = cols.get(d_idx).cloned().unwrap_or_default();
        if device.is_empty() || device == "." || device == "lo" {
            continue;
        }
        let address = cols.get(a_idx).cloned().unwrap_or_else(|| ".".to_string());
        if address.is_empty() || address == "." {
            continue;
        }
        let mask = col_mask.and_then(|i| cols.get(i).cloned()).unwrap_or_else(|| ".".to_string());
        let scope = col_scope.and_then(|i| cols.get(i).cloned()).unwrap_or_else(|| ".".to_string());
        let hw = col_hw.and_then(|i| cols.get(i).cloned()).unwrap_or_else(|| ".".to_string());

        let iface = ensure_iface(result, &device, source_path, None);
        if hw != "." && !hw.is_empty() && iface.mac.is_none() {
            iface.mac = Some(hw);
        }
        if let Some(up_idx) = col_up {
            if let Some(up) = cols.get(up_idx) {
                if up.eq_ignore_ascii_case("true") {
                    iface.state = Some("UP".to_string());
                }
            }
        }

        let is_ipv6 = address.contains(':') && !address.starts_with("127.");
        if is_ipv6 {
            let scope_val = if scope != "." { scope.clone() } else { "link".to_string() };
            if !iface.ipv6.iter().any(|a| a.address == address) {
                iface.ipv6.push(IpAddressInfo {
                    address: address.clone(),
                    scope: scope_val,
                    source: Some("cloud-init".to_string()),
                    source_file: Some(source_path.to_string()),
                    line_number: Some(*line_no),
                });
            }
        } else {
            let addr = if mask != "." && !mask.is_empty() {
                if let Some(cidr) = dotted_mask_to_cidr(&mask) {
                    format!("{}/{}", address, cidr)
                } else {
                    address.clone()
                }
            } else {
                address.clone()
            };
            let scope_val = if scope != "." { scope.clone() } else { "global".to_string() };
            if !iface.ipv4.iter().any(|a| a.address.starts_with(&address)) {
                iface.ipv4.push(IpAddressInfo {
                    address: addr,
                    scope: scope_val,
                    source: Some("cloud-init".to_string()),
                    source_file: Some(source_path.to_string()),
                    line_number: Some(*line_no),
                });
            }
        }
    }
    result.found = true;
}

pub fn parse_network_interfaces(content: &str, source_path: &str) -> NetworkInterfacesResult {
    let mut result = NetworkInterfacesResult {
        found: false,
        interfaces: BTreeMap::new(),
        source_path: source_path.to_string(),
    };

    if content.trim().is_empty() {
        return result;
    }

    // Per-file dispatch by filename: ethtool_-i_<iface>, ifcfg-<iface>.
    if let Some((iface_name, kind)) = iface_from_filename(source_path) {
        match kind {
            "ethtool" => {
                parse_ethtool_block(content, &mut result, &iface_name, source_path);
                return result;
            }
            "ifcfg" => {
                parse_ifcfg_block(content, &mut result, &iface_name, source_path);
                return result;
            }
            _ => {}
        }
    }

    // SOS `ip -o addr` and `ip addr show` standalone files.
    let basename = source_path.rsplit('/').next().unwrap_or(source_path);
    if basename == "ip_-o_addr" || basename == "ip_addr" || basename == "ip_-s_-d_link" {
        parse_ip_addr_block(content, &mut result, source_path);
        return result;
    }

    // Log files containing cloud-init `ci-info` Net device tables.
    if basename == "messages" || basename == "cloud-init-output.log" {
        if crate::cached_regex!(r"(?i)ci-info:.*Net device info").is_match(content) {
            parse_cloud_init_ci_info(content, &mut result, source_path);
        }
        return result;
    }

    // SCC supportconfig network.txt: dispatch by section heading.
    if content.contains("#==[") {
        for (heading, body) in extract_scc_sections(content) {
            let h = heading.as_str();
            let body_trimmed = body.trim();
            if body_trimmed.is_empty() {
                continue;
            }
            // ip addr (but not 'ip addr show type ...')
            let ip_addr_re = crate::cached_regex!(r"\bip\s+addr\b");
            let ip_addr_show_type_re = crate::cached_regex!(r"ip\s+addr\s+show\s+type");
            if ip_addr_re.is_match(h) && !ip_addr_show_type_re.is_match(h) {
                parse_ip_addr_block(&body, &mut result, source_path);
                continue;
            }
            // ethtool -i <iface>
            if let Some(caps) = crate::cached_regex!(r"ethtool\s+-i\s+(\w+)").captures(h) {
                let iface_name = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
                if !iface_name.is_empty() {
                    parse_ethtool_block(&body, &mut result, &iface_name, source_path);
                }
                continue;
            }
            // ifcfg-<iface>
            if let Some(caps) = crate::cached_regex!(r"ifcfg-(\S+)").captures(h) {
                let iface_name = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
                if !iface_name.is_empty() {
                    parse_ifcfg_block(&body, &mut result, &iface_name, source_path);
                }
                continue;
            }
        }
        // After SCC dispatch, fall through to also try generic line-by-line parsing
        // for any remaining content (e.g., nmcli/wicked/netplan blocks not covered above).
    }

    // Generic line-by-line parsing (handles ip addr standalone files, nmcli, wicked, netplan).
    let iface_re = crate::cached_regex!(r"^\d+:\s+(\S+?):\s+<([^>]*)>\s*(.*)");
    let mac_re = crate::cached_regex!(r"link/ether\s+([0-9a-f:]+)");
    let inet_re = crate::cached_regex!(r"inet\s+(\S+)\s+(?:brd\s+\S+\s+)?scope\s+(\S+)");
    let inet6_re = crate::cached_regex!(r"inet6\s+(\S+)\s+scope\s+(\S+)");
    let driver_re = crate::cached_regex!(r"(?m)^driver:\s*(\S+)");
    let firmware_re = crate::cached_regex!(r"(?m)^firmware-version:\s*(.+)$");
    let bus_re = crate::cached_regex!(r"(?m)^bus-info:\s*(\S+)");
    let device_re = crate::cached_regex!(r#"(?m)^DEVICE\s*=\s*['\"]?([^'\"\n]+)"#);
    let bootproto_re = crate::cached_regex!(r#"(?m)^BOOTPROTO\s*=\s*['\"]?([^'\"\n]+)"#);
    let ipaddr_re = crate::cached_regex!(r#"(?m)^IPADDR\s*=\s*['\"]?([^'\"\n]+)"#);
    let prefix_re = crate::cached_regex!(r#"(?m)^(?:PREFIX|PREFIXLEN)\s*=\s*['\"]?([^'\"\n]+)"#);
    let nmcli_iface_re = crate::cached_regex!(r"(?m)^connection\.interface-name:\s+(\S+)");
    let nmcli_method_re = crate::cached_regex!(r"(?m)^ipv4\.method:\s+(\S+)");
    let wicked_iface_re = crate::cached_regex!(r"^(\S+)\s+(up|down|setup-in-progress|enslaved)");
    let wicked_lease_re = crate::cached_regex!(r"leases:\s+ipv4\s+(\S+)");
    let netplan_iface_re = crate::cached_regex!(r"^\s{4}(\w+):");

    let mut current_iface_name: Option<String> = None;
    for (line_idx, line) in content.lines().enumerate() {
        let line_no = line_idx + 1;
        if let Some(caps) = iface_re.captures(line) {
            let name = caps.get(1).map(|m| m.as_str().split('@').next().unwrap_or(m.as_str()).to_string()).unwrap_or_default();
            let flags = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            let rest = caps.get(3).map(|m| m.as_str()).unwrap_or_default();
            let iface = ensure_iface(&mut result, &name, source_path, Some(line_no));
            iface.state = if let Some(state_caps) = crate::cached_regex!(r"state\s+(\S+)").captures(rest) {
                state_caps.get(1).map(|m| m.as_str().to_string())
            } else if flags.contains("UP") {
                Some("UP".to_string())
            } else {
                Some("DOWN".to_string())
            };
            iface.mtu = crate::cached_regex!(r"mtu\s+(\d+)").captures(rest).and_then(|c| c.get(1).and_then(|m| m.as_str().parse::<i64>().ok()));
            iface.iface_type = if flags.contains("LOOPBACK") {
                Some("loopback".to_string())
            } else if flags.contains("SLAVE") {
                Some("linked".to_string())
            } else {
                Some("ethernet".to_string())
            };
            iface.master = crate::cached_regex!(r"master\s+(\S+)").captures(rest).and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
            current_iface_name = Some(name);
            result.found = true;
            continue;
        }

        if let Some(iface_name) = current_iface_name.clone() {
            let iface = ensure_iface(&mut result, &iface_name, source_path, None);
            if let Some(caps) = mac_re.captures(line) {
                iface.mac = caps.get(1).map(|m| m.as_str().to_string());
                continue;
            }
            if let Some(caps) = inet_re.captures(line) {
                add_ipv4(
                    iface,
                    caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                    caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_else(|| "global".to_string()),
                );
                continue;
            }
            if let Some(caps) = inet6_re.captures(line) {
                add_ipv6(
                    iface,
                    caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default(),
                    caps.get(2).map(|m| m.as_str().to_string()).unwrap_or_else(|| "link".to_string()),
                );
                continue;
            }
            if let Some(caps) = driver_re.captures(line) {
                let driver = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
                let (label, accel) = classify_driver(&driver);
                iface.driver = Some(driver);
                iface.driver_info = Some(label);
                iface.accel_net = accel;
                continue;
            }
            if let Some(caps) = firmware_re.captures(line) {
                iface.firmware_version = caps.get(1).map(|m| m.as_str().trim().to_string());
                continue;
            }
            if let Some(caps) = bus_re.captures(line) {
                iface.bus_info = caps.get(1).map(|m| m.as_str().trim().to_string());
                continue;
            }
        }
    }

    if let Some(caps) = device_re.captures(content) {
        let iface_name = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
        if iface_name != "lo" && iface_name != "template" {
            let iface = ensure_iface(&mut result, iface_name, source_path, None);
            if let Some(boot) = bootproto_re.captures(content).and_then(|c| c.get(1).map(|m| m.as_str().to_ascii_lowercase())) {
                iface.bootproto = Some(boot);
            }
            if let Some(ip) = ipaddr_re.captures(content).and_then(|c| c.get(1).map(|m| m.as_str().to_string())) {
                let prefix = prefix_re.captures(content).and_then(|c| c.get(1).map(|m| m.as_str().to_string()));
                let addr = if let Some(prefix) = prefix { format!("{}/{}", ip, prefix) } else { ip };
                add_ipv4(iface, addr, "global".to_string());
            }
            result.found = true;
        }
    }

    if let Some(caps) = nmcli_iface_re.captures(content) {
        let iface_name = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
        let iface = ensure_iface(&mut result, iface_name, source_path, None);
        if let Some(method) = nmcli_method_re.captures(content).and_then(|c| c.get(1).map(|m| m.as_str().to_ascii_lowercase())) {
            iface.bootproto = Some(match method.as_str() {
                "auto" => "dhcp".to_string(),
                "manual" => "static".to_string(),
                _ => method,
            });
        }
        result.found = true;
    }

    let mut wicked_current: Option<String> = None;
    for line in content.lines() {
        if let Some(caps) = wicked_iface_re.captures(line) {
            let name = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
            if name != "lo" {
                let iface = ensure_iface(&mut result, name, source_path, None);
                iface.state = Some(caps.get(2).map(|m| m.as_str()).unwrap_or_default().to_ascii_uppercase());
                wicked_current = Some(name.to_string());
                result.found = true;
            }
            continue;
        }
        if let Some(name) = wicked_current.clone() {
            if let Some(caps) = wicked_lease_re.captures(line) {
                let lease = caps.get(1).map(|m| m.as_str().to_ascii_lowercase()).unwrap_or_default();
                let iface = ensure_iface(&mut result, &name, source_path, None);
                iface.bootproto = Some(if lease == "dhcp" { "dhcp".to_string() } else { "static".to_string() });
            }
        }
    }

    let mut netplan_iface: Option<String> = None;
    let mut in_ethernets = false;
    for line in content.lines() {
        if line.trim_start().starts_with("ethernets:") {
            in_ethernets = true;
            continue;
        }
        if in_ethernets {
            if let Some(caps) = netplan_iface_re.captures(line) {
                let name = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
                ensure_iface(&mut result, name, source_path, None);
                netplan_iface = Some(name.to_string());
                result.found = true;
                continue;
            }
            if let Some(name) = netplan_iface.clone() {
                let iface = ensure_iface(&mut result, &name, source_path, None);
                if crate::cached_regex!(r"(?i)^\s*dhcp4:\s*(true|yes)").is_match(line) {
                    iface.bootproto = Some("dhcp".to_string());
                } else if crate::cached_regex!(r"(?i)^\s*dhcp4:\s*(false|no)").is_match(line) {
                    iface.bootproto = Some("static".to_string());
                }
            }
            if !line.starts_with(' ') && !line.trim().is_empty() && !line.trim_start().starts_with('#') {
                in_ethernets = false;
                netplan_iface = None;
            }
        }
    }

    result
}

pub fn parse_network_interfaces_json(content: &str, source_path: &str) -> String {
    let mut value = serde_json::to_value(parse_network_interfaces(content, source_path)).unwrap_or(serde_json::Value::Null);
    crate::parsers::fill_source_path(&mut value, source_path);
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_ip_addr_and_driver_info() {
        let input = concat!(
            "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP\n",
            "    link/ether 00:11:22:33:44:55 brd ff:ff:ff:ff:ff:ff\n",
            "    inet 10.0.0.4/24 brd 10.0.0.255 scope global eth0\n",
            "    inet6 fe80::1/64 scope link\n",
            "driver: mana\n",
            "firmware-version: 1.2.3\n",
            "bus-info: VMBUS:01\n"
        );
        let result = parse_network_interfaces(input, "sos_commands/networking/ip_-d_address");
        assert!(result.found);
        assert_eq!(result.source_path, "sos_commands/networking/ip_-d_address");
        let eth0 = result.interfaces.get("eth0").expect("eth0 exists");
        assert_eq!(eth0.state.as_deref(), Some("UP"));
        assert_eq!(eth0.driver.as_deref(), Some("mana"));
        assert!(eth0.accel_net);
        assert_eq!(eth0.ipv4.len(), 1);
        assert_eq!(eth0.source_path, "sos_commands/networking/ip_-d_address");
        assert_eq!(eth0.source_line, Some(1));
    }

    #[test]
    fn parses_bootproto_from_config() {
        let input = concat!(
            "DEVICE=eth1\n",
            "BOOTPROTO=dhcp\n",
            "IPADDR=192.168.1.10\n",
            "PREFIX=24\n"
        );
        let result = parse_network_interfaces(input, "etc/sysconfig/network-scripts/ifcfg-eth1");
        assert!(result.found);
        let eth1 = result.interfaces.get("eth1").expect("eth1 exists");
        assert_eq!(eth1.bootproto.as_deref(), Some("dhcp"));
        assert_eq!(eth1.source_path, "etc/sysconfig/network-scripts/ifcfg-eth1");
    }
}
