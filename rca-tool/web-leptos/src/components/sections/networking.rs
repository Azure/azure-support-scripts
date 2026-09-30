use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section 11 – Networking (interfaces + firewall).
#[component]
pub fn NetworkingSection(data: Value) -> impl IntoView {
    let interfaces = data
        .get("networkInterfaces")
        .cloned()
        .unwrap_or(Value::Null);
    let firewall = data.get("firewallRules").cloned().unwrap_or(Value::Null);
    let packet_loss = data.get("packetLoss").cloned().unwrap_or(Value::Null);
    let ring_buffer = data.get("ringBuffer").cloned().unwrap_or(Value::Null);
    let net_sysctl = data.get("networkSysctl").cloned().unwrap_or(Value::Null);

    let has_intf = json_bool(&interfaces, "found");
    let has_fw = json_bool(&firewall, "found");
    let has_pl = json_bool(&packet_loss, "found");
    let has_rb = json_bool(&ring_buffer, "found");
    let has_sysctl = json_bool(&net_sysctl, "found");

    if !has_intf && !has_fw && !has_pl && !has_rb && !has_sysctl {
        return view! {}.into_any();
    }

    let mut ifaces = interface_values(&interfaces);
    ifaces.retain(|iface| json_str(iface, "name") != "lo");
    ifaces.sort_by(|a, b| {
        let a_name = json_str(a, "name");
        let b_name = json_str(b, "name");
        match (a_name.as_str(), b_name.as_str()) {
            ("eth0", "eth0") => std::cmp::Ordering::Equal,
            ("eth0", _) => std::cmp::Ordering::Less,
            (_, "eth0") => std::cmp::Ordering::Greater,
            _ => a_name.cmp(&b_name),
        }
    });

    let accel_net = ifaces.iter().any(|iface| json_bool(iface, "accelNet"));
    let raw_interfaces = interfaces.get("raw").cloned().unwrap_or(Value::Null);
    let section_class = if has_fw || !ifaces.is_empty() {
        "info-block"
    } else {
        "content-details"
    };

    view! {
        <Section title="Networking" class=section_class open=true>
            {render_interfaces_section(&ifaces, has_intf, accel_net, &raw_interfaces)}
            {render_packet_loss_section(&packet_loss, has_pl)}
            {render_ring_buffer_section(&ring_buffer, has_rb)}
            {render_network_sysctl_section(&net_sysctl, has_sysctl)}
            {render_firewall_section(&firewall, has_fw)}
        </Section>
    }
    .into_any()
}

fn warnings_from(value: &Value) -> Vec<Value> {
    value
        .get("warnings")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
}

fn warning_class(severity: &str) -> &'static str {
    match severity {
        "warning" => "text-warning",
        "danger" | "error" | "critical" => "text-danger",
        _ => "text-muted",
    }
}

fn render_packet_loss_section(packet_loss: &Value, has_pl: bool) -> AnyView {
    if !has_pl {
        return view! {}.into_any();
    }
    let interfaces = packet_loss
        .get("interfaces")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    // Hide loopback for clarity.
    let interfaces: Vec<Value> = interfaces
        .into_iter()
        .filter(|i| json_str(i, "interface") != "lo")
        .collect();
    let warnings = warnings_from(packet_loss);
    let has_warn = !warnings.is_empty();
    let block_class = if has_warn { "warning-block" } else { "info-block" };
    let summary = if has_warn {
        format!("{} issue{}", warnings.len(), if warnings.len() == 1 { "" } else { "s" })
    } else {
        "no losses detected".to_string()
    };

    view! {
        <details class=block_class open=has_warn>
            <summary>
                "Packet loss (ip -s link) "
                <span class="text-muted">{format!("({summary})")}</span>
            </summary>
            <div class="section-body">
                {(!interfaces.is_empty()).then(|| view! {
                    <table class="kv-table">
                        <thead>
                            <tr>
                                <th class="kv-label">"Interface"</th>
                                <th class="kv-label">"RX packets"</th>
                                <th class="kv-label">"RX errors"</th>
                                <th class="kv-label">"RX dropped"</th>
                                <th class="kv-label">"RX missed"</th>
                                <th class="kv-label">"TX packets"</th>
                                <th class="kv-label">"TX errors"</th>
                                <th class="kv-label">"TX dropped"</th>
                            </tr>
                        </thead>
                        <tbody>
                            {interfaces.iter().cloned().map(|i| {
                                let name = json_str(&i, "interface");
                                let rx_pkts = json_u64(&i, "rxPackets");
                                let rx_err = json_u64(&i, "rxErrors");
                                let rx_drop = json_u64(&i, "rxDropped");
                                let rx_miss = json_u64(&i, "rxMissed");
                                let tx_pkts = json_u64(&i, "txPackets");
                                let tx_err = json_u64(&i, "txErrors");
                                let tx_drop = json_u64(&i, "txDropped");
                                let rx_err_cls = if rx_err > 0 { "text-danger" } else { "kv-value" };
                                let rx_drop_cls = if rx_drop > 0 { "text-warning" } else { "kv-value" };
                                let rx_miss_cls = if rx_miss > 0 { "text-warning" } else { "kv-value" };
                                let tx_err_cls = if tx_err > 0 { "text-danger" } else { "kv-value" };
                                let tx_drop_cls = if tx_drop > 0 { "text-warning" } else { "kv-value" };
                                view! {
                                    <tr>
                                        <td class="kv-value"><strong>{name}</strong></td>
                                        <td class="kv-value">{rx_pkts.to_string()}</td>
                                        <td class=rx_err_cls>{rx_err.to_string()}</td>
                                        <td class=rx_drop_cls>{rx_drop.to_string()}</td>
                                        <td class=rx_miss_cls>{rx_miss.to_string()}</td>
                                        <td class="kv-value">{tx_pkts.to_string()}</td>
                                        <td class=tx_err_cls>{tx_err.to_string()}</td>
                                        <td class=tx_drop_cls>{tx_drop.to_string()}</td>
                                    </tr>
                                }
                            }).collect::<Vec<_>>()}
                        </tbody>
                    </table>
                })}
                {has_warn.then(|| view! {
                    <ul>
                        {warnings.iter().cloned().map(|w| {
                            let sev = json_str(&w, "severity");
                            let cls = warning_class(&sev);
                            let msg = json_str(&w, "message");
                            view! { <li class=cls>{msg}</li> }
                        }).collect::<Vec<_>>()}
                    </ul>
                })}
            </div>
        </details>
    }.into_any()
}

fn render_ring_buffer_section(ring_buffer: &Value, has_rb: bool) -> AnyView {
    if !has_rb {
        return view! {}.into_any();
    }
    let entries = ring_buffer
        .get("entries")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let entries: Vec<Value> = entries
        .into_iter()
        .filter(|i| json_str(i, "interface") != "lo")
        .collect();
    let warnings = warnings_from(ring_buffer);
    let has_warn = !warnings.is_empty();
    let block_class = if has_warn { "warning-block" } else { "info-block" };
    let summary = if has_warn {
        format!("{} undersized ring{}", warnings.len(), if warnings.len() == 1 { "" } else { "s" })
    } else {
        "ring buffers at hardware max".to_string()
    };

    let fmt_opt = |v: &Value, k: &str| -> String {
        match v.get(k) {
            Some(Value::Number(n)) => n.to_string(),
            _ => "-".to_string(),
        }
    };

    view! {
        <details class=block_class open=has_warn>
            <summary>
                "Ring buffers (ethtool -g) "
                <span class="text-muted">{format!("({summary})")}</span>
            </summary>
            <div class="section-body">
                {(!entries.is_empty()).then(|| view! {
                    <table class="kv-table">
                        <thead>
                            <tr>
                                <th class="kv-label">"Interface"</th>
                                <th class="kv-label">"RX current"</th>
                                <th class="kv-label">"RX max"</th>
                                <th class="kv-label">"TX current"</th>
                                <th class="kv-label">"TX max"</th>
                            </tr>
                        </thead>
                        <tbody>
                            {entries.iter().cloned().map(|i| {
                                let name = json_str(&i, "interface");
                                let rx_cur = fmt_opt(&i, "rxCurrent");
                                let rx_max = fmt_opt(&i, "rxMax");
                                let tx_cur = fmt_opt(&i, "txCurrent");
                                let tx_max = fmt_opt(&i, "txMax");
                                let rx_cls = if rx_cur != rx_max && rx_max != "-" { "text-warning" } else { "kv-value" };
                                let tx_cls = if tx_cur != tx_max && tx_max != "-" { "text-warning" } else { "kv-value" };
                                view! {
                                    <tr>
                                        <td class="kv-value"><strong>{name}</strong></td>
                                        <td class=rx_cls>{rx_cur}</td>
                                        <td class="kv-value">{rx_max}</td>
                                        <td class=tx_cls>{tx_cur}</td>
                                        <td class="kv-value">{tx_max}</td>
                                    </tr>
                                }
                            }).collect::<Vec<_>>()}
                        </tbody>
                    </table>
                })}
                {has_warn.then(|| view! {
                    <ul>
                        {warnings.iter().cloned().map(|w| {
                            let sev = json_str(&w, "severity");
                            let cls = warning_class(&sev);
                            let msg = json_str(&w, "message");
                            view! { <li class=cls>{msg}</li> }
                        }).collect::<Vec<_>>()}
                    </ul>
                })}
            </div>
        </details>
    }.into_any()
}

fn render_network_sysctl_section(net_sysctl: &Value, has_sysctl: bool) -> AnyView {
    if !has_sysctl {
        return view! {}.into_any();
    }
    let entries = net_sysctl
        .get("rpFilter")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let warnings = warnings_from(net_sysctl);
    let has_warn = !warnings.is_empty();
    let block_class = if has_warn { "warning-block" } else { "info-block" };
    let summary = if has_warn {
        format!("rp_filter active on {} scope{}", warnings.len(), if warnings.len() == 1 { "" } else { "s" })
    } else {
        "rp_filter disabled".to_string()
    };

    view! {
        <details class=block_class open=has_warn>
            <summary>
                "Network sysctl tuning "
                <span class="text-muted">{format!("({summary})")}</span>
            </summary>
            <div class="section-body">
                {(!entries.is_empty()).then(|| view! {
                    <table class="kv-table">
                        <thead>
                            <tr>
                                <th class="kv-label">"Sysctl key"</th>
                                <th class="kv-label">"Value"</th>
                            </tr>
                        </thead>
                        <tbody>
                            {entries.iter().cloned().map(|e| {
                                let key = json_str(&e, "key");
                                let val = json_str(&e, "value");
                                let cls = if val == "0" { "kv-value" } else { "text-warning" };
                                view! {
                                    <tr>
                                        <td class="kv-value"><code>{key}</code></td>
                                        <td class=cls><strong>{val}</strong></td>
                                    </tr>
                                }
                            }).collect::<Vec<_>>()}
                        </tbody>
                    </table>
                })}
                {has_warn.then(|| view! {
                    <ul>
                        {warnings.iter().cloned().map(|w| {
                            let sev = json_str(&w, "severity");
                            let cls = warning_class(&sev);
                            let msg = json_str(&w, "message");
                            view! { <li class=cls>{msg}</li> }
                        }).collect::<Vec<_>>()}
                    </ul>
                })}
            </div>
        </details>
    }.into_any()
}

fn render_interfaces_section(
    ifaces: &[Value],
    has_intf: bool,
    accel_net: bool,
    raw_sections: &Value,
) -> AnyView {
    let iface_count = ifaces.len();
    let summary = if iface_count == 0 {
        "No interfaces detected".to_string()
    } else if accel_net {
        format!(
            "{} interface{} | Accelerated Networking",
            iface_count,
            if iface_count == 1 { "" } else { "s" }
        )
    } else {
        format!(
            "{} interface{}",
            iface_count,
            if iface_count == 1 { "" } else { "s" }
        )
    };
    let block_class = if has_intf {
        "info-block"
    } else {
        "content-details"
    };

    let cloud_init_entries = collect_cloud_init_sources(ifaces);

    view! {
        <details class=block_class open=has_intf>
            <summary>
                "Network Interfaces "
                <span class="text-muted">{format!("({summary})")}</span>
            </summary>
            <div class="section-body">
                {if ifaces.is_empty() {
                    view! {
                        <p class="text-muted">
                            <em>"No network interface configuration was detected in the analyzed files."</em>
                        </p>
                    }
                    .into_any()
                } else {
                    view! {
                        <>
                            <table class="kv-table">
                                <thead>
                                    <tr>
                                        <th class="kv-label">"Interface"</th>
                                        <th class="kv-label">"State"</th>
                                        <th class="kv-label">"IPv4"</th>
                                        <th class="kv-label">"IPv6"</th>
                                        <th class="kv-label">"MAC"</th>
                                        <th class="kv-label">"MTU"</th>
                                        <th class="kv-label">"DHCP / Static"</th>
                                        <th class="kv-label">"Driver"</th>
                                        <th class="kv-label">"Accel Net"</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {ifaces
                                        .iter()
                                        .cloned()
                                        .map(|iface| {
                                            let name = json_str(&iface, "name");
                                            let master = json_str(&iface, "master");
                                            let state = json_str(&iface, "state");
                                            let state_class = if state == "UP" {
                                                "text-success"
                                            } else if state == "DOWN" {
                                                "text-danger"
                                            } else {
                                                "text-muted"
                                            };
                                            let ipv4 = format_ip_entries(iface.get("ipv4").unwrap_or(&Value::Null), false);
                                            let ipv6 = format_ip_entries(iface.get("ipv6").unwrap_or(&Value::Null), true);
                                            let mac = json_str(&iface, "mac");
                                            let mtu = display_value(&iface, "mtu");
                                            let bootproto = display_bootproto(&iface);
                                            let driver = json_str(&iface, "driver");
                                            let accel = display_accel_net(&iface, ifaces);
                                            let display_name = if master.is_empty() {
                                                name.clone()
                                            } else {
                                                format!("{name} (linked to {master})")
                                            };

                                            view! {
                                                <tr>
                                                    <td class="kv-value"><strong>{display_name}</strong></td>
                                                    <td class=state_class>{if state.is_empty() { "-".to_string() } else { state }}</td>
                                                    <td class="kv-value">{ipv4}</td>
                                                    <td class="kv-value">{ipv6}</td>
                                                    <td class="kv-value"><code>{if mac.is_empty() { "-".to_string() } else { mac }}</code></td>
                                                    <td class="kv-value">{mtu}</td>
                                                    <td class="kv-value">{bootproto}</td>
                                                    <td class="kv-value">{if driver.is_empty() { "-".to_string() } else { driver }}</td>
                                                    <td class="kv-value">{accel}</td>
                                                </tr>
                                            }
                                        })
                                        .collect::<Vec<_>>()}
                                </tbody>
                            </table>

                            {(!cloud_init_entries.is_empty()).then(|| view! {
                                <div class="warning-block">
                                    <p class="text-warning">
                                        <strong>"cloud-init:"</strong>
                                        " Some IP addresses were captured from cloud-init ci-info boot messages and reflect the last reported configuration during boot. They may not represent the current runtime state."
                                    </p>
                                    <ul>
                                        {cloud_init_entries
                                            .into_iter()
                                            .map(|entry| view! { <li><code>{entry}</code></li> })
                                            .collect::<Vec<_>>()}
                                    </ul>
                                </div>
                            })}

                            {render_raw_network_sections(raw_sections)}
                        </>
                    }
                    .into_any()
                }}
            </div>
        </details>
    }
    .into_any()
}

fn render_firewall_section(firewall: &Value, has_fw: bool) -> AnyView {
    let active = json_str(firewall, "activeFirewall");
    let active_label = if active.is_empty() || active == "none" {
        "No Active Firewall".to_string()
    } else {
        format!("Active: {active}")
    };
    let block_class = if !has_fw {
        "info-block"
    } else if active.is_empty() || active == "none" {
        "warning-block"
    } else {
        "info-block"
    };

    let warnings = string_array_from_key(firewall, "warnings");
    let firewalld = firewall.get("firewalld").cloned().unwrap_or(Value::Null);
    let nftables = firewall.get("nftables").cloned().unwrap_or(Value::Null);
    let iptables = firewall.get("iptables").cloned().unwrap_or(Value::Null);
    let ip6tables = firewall.get("ip6tables").cloned().unwrap_or(Value::Null);
    let ebtables = firewall.get("ebtables").cloned().unwrap_or(Value::Null);
    let raw_sections = firewall.get("rawSections").cloned().unwrap_or(Value::Null);

    view! {
        <details class=block_class>
            <summary>
                "Firewall Rules "
                <span class="text-muted">{format!("({active_label})")}</span>
            </summary>
            <div class="section-body">
                {if !has_fw {
                    view! {
                        <>
                            <p class="text-muted">
                                <em>"No firewall configuration was detected in the analyzed files."</em>
                            </p>
                            <p class="text-muted">
                                <em>"Checked for: firewalld, iptables, ip6tables, ebtables, nftables"</em>
                            </p>
                        </>
                    }
                    .into_any()
                } else {
                    view! {
                        <>
                            {(!warnings.is_empty()).then(|| view! {
                                <div class="warning-block">
                                    <ul>
                                        {warnings
                                            .into_iter()
                                            .map(|warning| view! { <li class="text-warning">{warning}</li> })
                                            .collect::<Vec<_>>()}
                                    </ul>
                                </div>
                            })}
                            {render_firewalld_details(&firewalld, &raw_sections)}
                            {render_nftables_details(&nftables, &raw_sections)}
                            {render_iptables_details("iptables", &iptables, "iptables-config")}
                            {render_iptables_details("ip6tables", &ip6tables, "")}
                            {render_ebtables_details(&ebtables)}
                            {render_remaining_raw_sections(&raw_sections)}
                        </>
                    }
                    .into_any()
                }}
            </div>
        </details>
    }
    .into_any()
}

fn render_firewalld_details(firewalld: &Value, raw_sections: &Value) -> Option<AnyView> {
    if !json_bool(firewalld, "detected") {
        return None;
    }

    let running = json_bool(firewalld, "running");
    let backend = json_str(firewalld, "backend");
    let log_denied = json_str(firewalld, "logDenied");
    let zones = json_str(firewalld, "zones");
    let direct_rules = json_str(firewalld, "directRules");
    let chains = json_str(firewalld, "chains");
    let passthroughs = json_str(firewalld, "passthroughs");
    let config = firewalld.get("config").cloned().unwrap_or(Value::Null);
    let config_entries = [
        "DefaultZone",
        "LogDenied",
        "AllowZoneDrifting",
        "FlushAllOnReload",
        "Lockdown",
    ]
    .into_iter()
    .filter_map(|key| {
        config
            .get(key)
            .map(|value| format!("{}={}", key, value_to_inline_string(value)))
    })
    .collect::<Vec<_>>();

    Some(
        view! {
            <details class="content-details" open=running>
                <summary>
                    "firewalld "
                    <span class=if running { "text-success" } else { "text-warning" }>
                        {format!("({})", if running { "running" } else { "not running" })}
                    </span>
                </summary>
                <div class="section-body">
                    <KvTable>
                        {(!backend.is_empty()).then(|| view! { <KvRow label="Backend" value=backend.clone()/> })}
                        {(!log_denied.is_empty()).then(|| view! { <KvRow label="LogDenied" value=log_denied.clone()/> })}
                        {(!config_entries.is_empty()).then(|| view! {
                            <KvRow label="Config" value=config_entries.join(", ")/>
                        })}
                    </KvTable>
                    {render_pre_block("Zones (runtime)", zones)}
                    {render_pre_block("Direct Rules", direct_rules)}
                    {render_pre_block("Direct Chains", chains)}
                    {render_pre_block("Passthroughs", passthroughs)}
                    {render_pre_block(
                        "Raw firewalld.conf",
                        raw_sections
                            .get("firewalld.conf")
                            .and_then(|value| value.as_str())
                            .unwrap_or("")
                            .to_string(),
                    )}
                </div>
            </details>
        }
        .into_any(),
    )
}

fn render_nftables_details(nftables: &Value, raw_sections: &Value) -> Option<AnyView> {
    if !json_bool(nftables, "detected") {
        return None;
    }

    let tables = json_str(nftables, "tables");
    let ruleset = json_str(nftables, "ruleset");
    let has_rules = !ruleset.is_empty() && ruleset != "(empty)";

    Some(
        view! {
            <details class="content-details" open=has_rules>
                <summary>
                    "nftables "
                    <span class=if has_rules { "text-info" } else { "text-muted" }>
                        {format!("({})", if has_rules { "rules present" } else { "no rules" })}
                    </span>
                </summary>
                <div class="section-body">
                    {(!tables.is_empty()).then(|| view! { <p><strong>"Tables:"</strong> " " <code>{tables.clone()}</code></p> })}
                    {render_pre_block("Ruleset", ruleset)}
                    {render_pre_block(
                        "Raw /etc/sysconfig/nftables.conf",
                        raw_sections
                            .get("nftables-sysconfig")
                            .and_then(|value| value.as_str())
                            .unwrap_or("")
                            .to_string(),
                    )}
                </div>
            </details>
        }
        .into_any(),
    )
}

fn render_iptables_details(
    label: &'static str,
    value: &Value,
    raw_key: &'static str,
) -> Option<AnyView> {
    if !json_bool(value, "detected") {
        return None;
    }

    let rules = json_array(value, "rules");
    let modules = json_array(value, "modules");
    let has_rules = !rules.is_empty();
    let summary = if has_rules {
        format!("{} table(s) with rules", rules.len())
    } else if !modules.is_empty() {
        "modules not loaded".to_string()
    } else {
        "no rules".to_string()
    };

    Some(
        view! {
            <details class="content-details" open=has_rules>
                <summary>
                    {label}
                    " "
                    <span class=if has_rules { "text-info" } else { "text-muted" }>
                        {format!("({summary})")}
                    </span>
                </summary>
                <div class="section-body">
                    {rules
                        .into_iter()
                        .map(|rule| {
                            let heading = json_str(&rule, "heading");
                            let raw = json_str(&rule, "raw");
                            view! {
                                <div class="subsection">
                                    <p><strong>{if heading.is_empty() { label.to_string() } else { heading }}</strong></p>
                                    <pre class="json-dump">{raw}</pre>
                                </div>
                            }
                        })
                        .collect::<Vec<_>>()}
                    {modules
                        .into_iter()
                        .map(|module| {
                            let module_name = json_str(&module, "module");
                            let note = json_str(&module, "note");
                            view! { <p class="text-muted">{format!("{}: {}", module_name, note)}</p> }
                        })
                        .collect::<Vec<_>>()}
                    {(!raw_key.is_empty())
                        .then(|| render_pre_block(&format!("Raw /etc/sysconfig/{raw_key}"), json_str(value, "config")))}
                </div>
            </details>
        }
        .into_any(),
    )
}

fn render_ebtables_details(ebtables: &Value) -> Option<AnyView> {
    if !json_bool(ebtables, "detected") {
        return None;
    }

    Some(
        view! {
            <details class="content-details">
                <summary>
                    "ebtables "
                    <span class="text-muted">"(config present)"</span>
                </summary>
                <div class="section-body">
                    {render_pre_block("Config", json_str(ebtables, "config"))}
                </div>
            </details>
        }
        .into_any(),
    )
}

fn render_remaining_raw_sections(raw_sections: &Value) -> Option<AnyView> {
    let sections = raw_sections
        .as_object()
        .map(|items| {
            items
                .iter()
                .filter(|(key, _)| {
                    ![
                        "firewalld.conf",
                        "iptables-config",
                        "ebtables-config",
                        "nftables-sysconfig",
                    ]
                    .contains(&key.as_str())
                })
                .map(|(key, value)| (key.clone(), value.as_str().unwrap_or("").to_string()))
                .filter(|(_, value)| !value.trim().is_empty())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    if sections.is_empty() {
        return None;
    }

    Some(
        view! {
            <details class="content-details">
                <summary>{format!("All Raw Sections ({})", sections.len())}</summary>
                <div class="section-body">
                    {sections
                        .into_iter()
                        .map(|(key, value)| view! {
                            <details class="content-details">
                                <summary>{key}</summary>
                                <pre class="json-dump">{value}</pre>
                            </details>
                        })
                        .collect::<Vec<_>>()}
                </div>
            </details>
        }
        .into_any(),
    )
}

fn render_pre_block(title: &str, content: String) -> Option<AnyView> {
    if content.trim().is_empty() {
        return None;
    }

    Some(
        view! {
            <details class="content-details">
                <summary>{title.to_string()}</summary>
                <pre class="json-dump">{content}</pre>
            </details>
        }
        .into_any(),
    )
}

fn interface_values(interfaces: &Value) -> Vec<Value> {
    interfaces
        .get("interfaces")
        .and_then(|value| value.as_object())
        .map(|items| items.values().cloned().collect::<Vec<_>>())
        .unwrap_or_default()
}

fn format_ip_entries(value: &Value, skip_link_local: bool) -> String {
    let entries = value
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    let address = json_str(item, "address");
                    if address.is_empty() || (skip_link_local && address.starts_with("fe80:")) {
                        return None;
                    }
                    let prefix = item
                        .get("prefix")
                        .map(value_to_inline_string)
                        .unwrap_or_default();
                    Some(if prefix.is_empty() {
                        address
                    } else {
                        format!("{address}/{prefix}")
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    if entries.is_empty() {
        "-".to_string()
    } else {
        entries.join(", ")
    }
}

fn display_value(value: &Value, key: &str) -> String {
    value
        .get(key)
        .map(value_to_inline_string)
        .filter(|item| !item.is_empty())
        .unwrap_or_else(|| "-".to_string())
}

fn display_bootproto(iface: &Value) -> String {
    match json_str(iface, "bootproto").to_ascii_lowercase().as_str() {
        "dhcp" | "dhcp4" => "DHCP".to_string(),
        "static" | "none" => "Static".to_string(),
        "" => "-".to_string(),
        other => other.to_string(),
    }
}

fn display_accel_net(iface: &Value, all_ifaces: &[Value]) -> String {
    let driver = json_str(iface, "driver");
    if json_bool(iface, "accelNet") {
        if driver == "mana" {
            "MANA".to_string()
        } else {
            "Yes".to_string()
        }
    } else if driver == "hv_netvsc" {
        let name = json_str(iface, "name");
        if let Some(linked) = all_ifaces.iter().find(|candidate| {
            json_bool(candidate, "accelNet") && json_str(candidate, "master") == name
        }) {
            format!("Yes (via {})", json_str(linked, "name"))
        } else {
            "No".to_string()
        }
    } else {
        "-".to_string()
    }
}

fn collect_cloud_init_sources(ifaces: &[Value]) -> Vec<String> {
    let mut entries = Vec::new();

    for iface in ifaces {
        let iface_name = json_str(iface, "name");
        for key in ["ipv4", "ipv6"] {
            if let Some(items) = iface.get(key).and_then(|value| value.as_array()) {
                for item in items {
                    if json_str(item, "source") == "cloud-init" {
                        let address = json_str(item, "address");
                        let source_file = json_str(item, "sourceFile");
                        let line = item
                            .get("lineNumber")
                            .map(value_to_inline_string)
                            .unwrap_or_default();
                        if !address.is_empty() {
                            if source_file.is_empty() {
                                entries.push(format!("{} {}", iface_name, address));
                            } else if line.is_empty() {
                                entries
                                    .push(format!("{} {} ← {}", iface_name, address, source_file));
                            } else {
                                entries.push(format!(
                                    "{} {} ← {}:{}",
                                    iface_name, address, source_file, line
                                ));
                            }
                        }
                    }
                }
            }
        }
    }

    entries
}

fn render_raw_network_sections(raw: &Value) -> Option<AnyView> {
    let sections = raw
        .as_object()
        .map(|items| {
            items
                .iter()
                .map(|(key, value)| (key.clone(), value.as_str().unwrap_or("").to_string()))
                .filter(|(_, value)| !value.trim().is_empty())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    if sections.is_empty() {
        return None;
    }

    Some(
        view! {
            <details class="content-details">
                <summary>{format!("Raw Network Configuration ({})", sections.len())}</summary>
                <div class="section-body">
                    {sections
                        .into_iter()
                        .map(|(key, value)| view! {
                            <details class="content-details">
                                <summary>{key}</summary>
                                <pre class="json-dump">{value}</pre>
                            </details>
                        })
                        .collect::<Vec<_>>()}
                </div>
            </details>
        }
        .into_any(),
    )
}

fn string_array_from_key(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(|items| items.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(|entry| entry.to_string()))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn value_to_inline_string(value: &Value) -> String {
    if let Some(text) = value.as_str() {
        text.to_string()
    } else if let Some(number) = value.as_i64() {
        number.to_string()
    } else if let Some(number) = value.as_u64() {
        number.to_string()
    } else if let Some(number) = value.as_f64() {
        if number.fract() == 0.0 {
            (number as i64).to_string()
        } else {
            format!("{number:.2}")
        }
    } else if let Some(boolean) = value.as_bool() {
        if boolean {
            "true".to_string()
        } else {
            "false".to_string()
        }
    } else {
        "".to_string()
    }
}
