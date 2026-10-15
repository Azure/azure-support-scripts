use leptos::prelude::*;
use supportfile::parse_pacemaker_high_cpu;
use serde_json::Value;

use super::helpers::*;

/// Section 4 – Cluster Configuration.
#[component]
pub fn ClusterSection(data: Value) -> impl IntoView {
    let corosync = data.get("corosyncConfig").cloned().unwrap_or(Value::Null);
    let cluster_status = data.get("clusterStatus").cloned().unwrap_or(Value::Null);
    let pacemaker = data
        .get("pacemakerResources")
        .cloned()
        .unwrap_or(Value::Null);
    let fencing = data.get("fencingConfig").cloned().unwrap_or(Value::Null);
    let sbd = data.get("sbdConfig").cloned().unwrap_or(Value::Null);
    let nodes = data.get("clusterNodes").cloned().unwrap_or(Value::Null);
    let events = data.get("clusterEvents").cloned().unwrap_or(Value::Null);
    let maintenance = data
        .get("clusterMaintenanceMode")
        .cloned()
        .unwrap_or(Value::Null);
    let daemon = data
        .get("clusterDaemonStatus")
        .cloned()
        .unwrap_or(Value::Null);
    let azure_fence = data.get("azureFenceAuth").cloned().unwrap_or(Value::Null);
    let cluster_services = data.get("clusterServices").cloned().unwrap_or(Value::Null);
    let hosts_file = data.get("hostsFile").cloned().unwrap_or(Value::Null);
    let nodes_in_hosts = data
        .get("nodesInHosts")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let nodes_missing_from_hosts = data
        .get("nodesMissingFromHosts")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let has_corosync_content = json_bool(&corosync, "found")
        || !json_array(&corosync, "warnings").is_empty()
        || corosync.get("token").is_some()
        || corosync.get("totemToken").is_some()
        || corosync.get("transport").is_some()
        || corosync.get("totemTransport").is_some();
    let has_pacemaker_content = json_bool(&pacemaker, "found")
        || !json_array(&pacemaker, "resources").is_empty()
        || !json_array(&pacemaker, "groups").is_empty()
        || !json_array(&pacemaker, "failedActions").is_empty()
        || !json_array(&pacemaker, "constraints").is_empty();
    let has_node_content = json_bool(&nodes, "found")
        || !json_array(&nodes, "nodes").is_empty()
        || !json_array(&nodes, "clusterNodes").is_empty()
        || !nodes_in_hosts.is_empty()
        || !nodes_missing_from_hosts.is_empty();
    let has_event_content = !json_array(&events, "resourceMigrations").is_empty()
        || !json_array(&events, "fencingEvents").is_empty();

    let has_content = has_corosync_content
        || json_bool(&cluster_status, "found")
        || has_pacemaker_content
        || json_bool(&fencing, "found")
        || json_bool(&sbd, "found")
        || has_node_content
        || has_event_content
        || json_bool(&maintenance, "found")
        || json_bool(&daemon, "found")
        || json_bool(&azure_fence, "found")
        || cluster_services.get("dlmService").is_some();

    if !has_content {
        return view! {}.into_any();
    }

    let corosync_warning_count = json_array(&corosync, "warnings").len();
    let daemon_warning_count = json_array(&daemon, "warnings").len();
    let failed_actions_count = pacemaker
        .get("failedActionsCount")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as usize;
    let maintenance_enabled = maintenance
        .get("maintenanceMode")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let stonith_enabled = fencing.get("stonithEnabled").and_then(|v| v.as_bool());
    let cluster_event_count = json_array(&events, "resourceMigrations").len()
        + json_array(&events, "fencingEvents").len();

    let class = if maintenance_enabled
        || stonith_enabled == Some(false)
        || failed_actions_count > 0
        || daemon_warning_count > 0
    {
        "danger-block"
    } else if corosync_warning_count > 0 || cluster_event_count > 0 {
        "warning-block"
    } else {
        "success-block"
    };

    view! {
        <Section title="Cluster Configuration" class=class open=true>
            {render_cluster_health(&cluster_status)}
            {render_corosync_warnings(&corosync)}
            {render_cluster_nodes(&nodes, &hosts_file, &nodes_in_hosts, &nodes_missing_from_hosts)}
            {render_pacemaker_resources(&pacemaker, &cluster_status)}
            {render_fencing_section(&fencing)}
            {render_maintenance_section(&maintenance)}
            {render_sbd_section(&sbd)}
            {render_cluster_events(&events)}
            {render_daemon_status(&daemon)}
            {render_cluster_services(&cluster_services)}
            {render_azure_fence_auth(&azure_fence)}
        </Section>
    }
    .into_any()
}

fn render_cluster_health(cluster_status: &Value) -> Option<AnyView> {
    if !json_bool(cluster_status, "found") {
        return None;
    }

    let cluster_name = json_text(cluster_status, "clusterName");
    let dc_node = json_text(cluster_status, "dcNode");
    let quorum_status = json_text(cluster_status, "quorumStatus");
    let nodes_configured = json_text(cluster_status, "nodesConfigured");
    let resources_configured = json_text(cluster_status, "resourcesConfigured");
    let last_updated = json_text(cluster_status, "lastUpdated");
    let online = json_text(cluster_status, "online");
    let node_statuses = json_array(cluster_status, "nodeStatuses");

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Cluster Health:"</p>
                <KvTable>
                    {(!cluster_name.is_empty()).then(|| view! {
                        <KvRow label="Cluster Stack" value=cluster_name.clone()/>
                    })}
                    {(!dc_node.is_empty()).then(|| view! {
                        <KvRow label="DC Node" value=if quorum_status.is_empty() {
                            dc_node.clone()
                        } else {
                            format!("{} ({})", dc_node.clone(), quorum_status.clone())
                        }/>
                    })}
                    {(!nodes_configured.is_empty()).then(|| view! {
                        <KvRow label="Nodes" value=format!("{} configured", nodes_configured.clone())/>
                    })}
                    {(!resources_configured.is_empty()).then(|| view! {
                        <KvRow label="Resources" value=format!("{} configured", resources_configured.clone())/>
                    })}
                    {(!online.is_empty()).then(|| view! {
                        <KvRow label="Online" value=online.clone()/>
                    })}
                    {(!last_updated.is_empty()).then(|| view! {
                        <KvRow label="Last Updated" value=last_updated.clone()/>
                    })}
                </KvTable>

                {(!node_statuses.is_empty()).then(|| view! {
                    <>
                        <p><strong>"Node Status:"</strong></p>
                        <ul class="disk-list">
                            {node_statuses
                                .into_iter()
                                .map(|node| {
                                    let name = json_text(&node, "name");
                                    let status = json_text(&node, "status");
                                    let is_dc = node.get("isDC").and_then(|v| v.as_bool()).unwrap_or(false);
                                    let resources_running = node
                                        .get("resourcesRunning")
                                        .and_then(|v| v.as_u64())
                                        .unwrap_or(0);
                                    let status_class = match status.as_str() {
                                        "online" => "text-success",
                                        "standby" => "text-warning",
                                        "maintenance" => "text-info",
                                        _ => "text-danger",
                                    };
                                    view! {
                                        <li>
                                            <strong>{name.clone()}</strong>
                                            ": "
                                            <span class=status_class>{status.clone()}</span>
                                            {is_dc.then(|| view! { <span class="text-info">" (DC)"</span> })}
                                            {(resources_running > 0).then(|| view! {
                                                <span class="text-muted">{format!(" ({} resources)", resources_running)}</span>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_corosync_warnings(corosync: &Value) -> Option<AnyView> {
    let warnings = json_array(corosync, "warnings");
    let token = corosync
        .get("token")
        .and_then(value_as_text)
        .or_else(|| corosync.get("totemToken").and_then(value_as_text))
        .unwrap_or_default();
    let transport = corosync
        .get("transport")
        .and_then(value_as_text)
        .or_else(|| corosync.get("totemTransport").and_then(value_as_text))
        .unwrap_or_default();
    let provider = corosync
        .get("provider")
        .and_then(value_as_text)
        .or_else(|| corosync.get("quorumProvider").and_then(value_as_text))
        .unwrap_or_default();
    let expected_votes = corosync
        .get("expectedVotes")
        .and_then(value_as_text)
        .or_else(|| corosync.get("quorumExpectedVotes").and_then(value_as_text))
        .unwrap_or_default();
    let two_node = corosync
        .get("twoNode")
        .and_then(value_as_text)
        .or_else(|| corosync.get("quorumTwoNode").and_then(value_as_text))
        .unwrap_or_default();
    let source_file = json_text(corosync, "sourceFile");

    if !json_bool(corosync, "found")
        && warnings.is_empty()
        && token.is_empty()
        && transport.is_empty()
        && provider.is_empty()
        && expected_votes.is_empty()
        && two_node.is_empty()
    {
        return None;
    }

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Corosync Configuration:"</p>
                <KvTable>
                    {(!token.is_empty()).then(|| view! {
                        <KvRow label="Totem token" value=token.clone()/>
                    })}
                    {(!transport.is_empty()).then(|| view! {
                        <KvRow label="Transport" value=transport.clone()/>
                    })}
                    {(!provider.is_empty()).then(|| view! {
                        <KvRow label="Quorum provider" value=provider.clone()/>
                    })}
                    {(!expected_votes.is_empty()).then(|| view! {
                        <KvRow label="Expected votes" value=expected_votes.clone()/>
                    })}
                    {(!two_node.is_empty()).then(|| view! {
                        <KvRow label="two_node" value=two_node.clone()/>
                    })}
                </KvTable>
                {(!source_file.is_empty()).then(|| view! {
                    <p class="text-muted"><em>{format!("Source: {}", source_file.clone())}</em></p>
                })}

                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>"Corosync Checks:"</strong></p>
                        {warnings
                            .into_iter()
                            .map(|warning| {
                                let message = json_text(&warning, "message");
                                let expected = json_text(&warning, "expected");
                                let actual = json_text(&warning, "actual");
                                let documentation_url = json_text(&warning, "documentationUrl");
                                view! {
                                    <div class="subsection">
                                        <p class="text-danger"><strong>{format!("[!] {}", message)}</strong></p>
                                        {(!expected.is_empty() || !actual.is_empty()).then(|| view! {
                                            <p>
                                                {(!expected.is_empty()).then(|| view! {
                                                    <span>
                                                        <strong>"Expected:"</strong>
                                                        " "
                                                        <code>{expected.clone()}</code>
                                                    </span>
                                                })}
                                                {(!expected.is_empty() && !actual.is_empty()).then(|| view! { <span>" • "</span> })}
                                                {(!actual.is_empty()).then(|| view! {
                                                    <span>
                                                        <strong>"Found:"</strong>
                                                        " "
                                                        <code>{actual.clone()}</code>
                                                    </span>
                                                })}
                                            </p>
                                        })}
                                        {(!documentation_url.is_empty()).then(|| view! {
                                            <p>
                                                <a
                                                    href=documentation_url
                                                    target="_blank"
                                                    rel="noopener noreferrer"
                                                    class="text-info"
                                                >
                                                    "View Documentation"
                                                </a>
                                            </p>
                                        })}
                                    </div>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </div>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_cluster_nodes(
    nodes: &Value,
    hosts_file: &Value,
    nodes_in_hosts: &[Value],
    nodes_missing_from_hosts: &[Value],
) -> Option<AnyView> {
    let mut node_entries = json_array(nodes, "nodes");
    if node_entries.is_empty() {
        node_entries = json_array(nodes, "clusterNodes");
    }

    let mut node_names = node_entries
        .iter()
        .filter_map(value_name)
        .collect::<Vec<_>>();

    let in_hosts = nodes_in_hosts
         .iter()
         .filter_map(value_name)
         .collect::<Vec<_>>();
    let missing = nodes_missing_from_hosts
         .iter()
         .filter_map(value_name)
         .collect::<Vec<_>>();
    if node_names.is_empty() {
        node_names = in_hosts.clone();
    }
    if node_names.is_empty() {
        node_names = missing.clone();
    }
    if node_names.is_empty() {
        node_names = hosts_file
            .get("allHostnames")
            .and_then(|v| v.as_array())
            .map(|entries| entries.iter().filter_map(value_name).collect::<Vec<_>>())
            .unwrap_or_default();
    }
    if node_names.is_empty() {
        return None;
    }

    let total_hostnames = hosts_file
        .get("allHostnames")
        .and_then(|v| v.as_array())
        .map(|a| a.len())
        .unwrap_or(0);
    let ip_map = nodes
        .get("nodeToIpMap")
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default();
    let has_hosts = json_bool(hosts_file, "found");

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Cluster nodes in ha.txt and hosts file"</p>
                <ul class="disk-list">
                    {node_names
                        .into_iter()
                        .map(|node| {
                            let node_in_hosts = in_hosts.iter().any(|entry| entry == &node);
                            let ip = ip_map.get(&node).and_then(value_as_text).unwrap_or_default();
                            view! {
                                <li>
                                    <code>{node.clone()}</code>
                                    {has_hosts.then(|| view! {
                                        <span class=if node_in_hosts {
                                            "badge badge-success"
                                        } else {
                                            "badge badge-danger"
                                        }>
                                            {if node_in_hosts { "in hosts" } else { "not in hosts" }}
                                        </span>
                                    })}
                                    {(!ip.is_empty()).then(|| view! {
                                        <span class="text-muted">{format!(" — IP: {ip}")}</span>
                                    })}
                                </li>
                            }
                        })
                        .collect::<Vec<_>>()}
                </ul>

                {has_hosts.then(|| view! {
                    <div class="vm-note info">
                        <p><strong>"Hosts File Validation:"</strong></p>
                        <p class="text-success">{format!("[OK] {} node(s) found in /etc/hosts", in_hosts.len())}</p>
                        {(!missing.is_empty()).then(|| view! {
                            <>
                                <p class="text-danger">{format!("[ERROR] {} node(s) missing from /etc/hosts", missing.len())}</p>
                                <ul class="disk-list">
                                    {missing
                                        .into_iter()
                                        .map(|name| view! { <li><code>{name}</code></li> })
                                        .collect::<Vec<_>>()}
                                </ul>
                            </>
                        })}
                        {(total_hostnames > 0).then(|| view! {
                            <p class="text-muted">{format!("Total hostnames in /etc/hosts: {}", total_hostnames)}</p>
                        })}
                    </div>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_pacemaker_resources(pacemaker: &Value, cluster_status: &Value) -> Option<AnyView> {
    let resources = json_array(pacemaker, "resources");
    let groups = json_array(pacemaker, "groups");
    let failed_actions = json_array(pacemaker, "failedActions");
    let constraints = json_array(pacemaker, "constraints");
    if !json_bool(pacemaker, "found")
        && resources.is_empty()
        && groups.is_empty()
        && failed_actions.is_empty()
        && constraints.is_empty()
    {
        return None;
    }
    let count = pacemaker
        .get("count")
        .and_then(|v| v.as_u64())
        .unwrap_or(resources.len() as u64) as usize;
    let groups_count = pacemaker
        .get("groupsCount")
        .and_then(|v| v.as_u64())
        .unwrap_or(groups.len() as u64) as usize;
    let total_count = count + groups_count;
    let configured_count = cluster_status
        .get("resourcesConfigured")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as usize;

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Cluster Resources:"</p>
                <p class="text-muted">
                    {format!(
                        "{} active resource{} detected",
                        total_count,
                        if total_count == 1 { "" } else { "s" },
                    )}
                    {(groups_count > 0).then(|| format!(
                        " ({} group{}, {} primitive{})",
                        groups_count,
                        if groups_count == 1 { "" } else { "s" },
                        count,
                        if count == 1 { "" } else { "s" },
                    ))}
                </p>
                <p class="text-muted"><em>"Source: ha.txt / cluster status output"</em></p>
                {(configured_count > total_count && total_count > 0).then(|| view! {
                    <p class="text-warning-dark">
                        {format!(
                            "Note: {} total configured ({} may be stopped, disabled, or failed)",
                            configured_count,
                            configured_count - total_count,
                        )}
                    </p>
                })}

                {(!groups.is_empty()).then(|| view! {
                    <ul class="disk-list">
                        {groups
                            .iter()
                            .map(|group| {
                                let name = json_text(group, "name");
                                let kind = match json_text(group, "type").as_str() {
                                    "clone" => "Clone Set",
                                    "master-slave" => "Primary/Secondary Set",
                                    _ => "Resource Group",
                                };
                                let node = json_text(group, "node");
                                let maintenance = group
                                    .get("maintenance")
                                    .and_then(|v| v.as_bool())
                                    .unwrap_or(false);
                                let members = group
                                    .get("members")
                                    .and_then(|v| v.as_array())
                                    .cloned()
                                    .unwrap_or_default();
                                view! {
                                    <li>
                                        <strong>{format!("{}: ", kind)}</strong>
                                        <code class="text-info">{name.clone()}</code>
                                        {maintenance.then(|| view! {
                                            <span class="badge badge-warning">"In maintenance"</span>
                                        })}
                                        {(!node.is_empty()).then(|| view! {
                                            <div class="text-success">{format!("Active on: {}", node.clone())}</div>
                                        })}
                                        {(!members.is_empty()).then(|| view! {
                                            <ul class="disk-list">
                                                {members
                                                    .iter()
                                                    .filter_map(value_name)
                                                    .map(|member_name| {
                                                        let member = resources
                                                            .iter()
                                                            .find(|resource| json_text(resource, "name") == member_name)
                                                            .cloned()
                                                            .unwrap_or(Value::Null);
                                                        let status = json_text(&member, "status")
                                                            .replace("Master", "Primary")
                                                            .replace("Slave", "Secondary");
                                                        let node = json_text(&member, "node");
                                                        view! {
                                                            <li>
                                                                <code>{member_name.clone()}</code>
                                                                {(!resource_spec(&member).is_empty()).then(|| view! {
                                                                    <span class="text-muted">{format!(" ({})", resource_spec(&member))}</span>
                                                                })}
                                                                {(!status.is_empty()).then(|| view! {
                                                                    <span class="text-muted">{format!(" — {}", status)}</span>
                                                                })}
                                                                {(!node.is_empty()).then(|| view! {
                                                                    <span class="text-success">{format!(" on {}", node.clone())}</span>
                                                                })}
                                                            </li>
                                                        }
                                                    })
                                                    .collect::<Vec<_>>()}
                                            </ul>
                                        })}
                                    </li>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </ul>
                })}

                {(!resources.is_empty()).then(|| view! {
                    <ul class="disk-list">
                        {resources
                            .iter()
                            .filter(|resource| {
                                !resource.get("groupMember").and_then(|v| v.as_bool()).unwrap_or(false)
                                    && !resource.get("cloneMember").and_then(|v| v.as_bool()).unwrap_or(false)
                            })
                            .map(|resource| {
                                let name = json_text(resource, "name");
                                let node = json_text(resource, "node");
                                let status = json_text(resource, "status")
                                    .replace("Master", "Primary")
                                    .replace("Slave", "Secondary");
                                let maintenance = resource
                                    .get("maintenance")
                                    .and_then(|v| v.as_bool())
                                    .unwrap_or(false);
                                view! {
                                    <li>
                                        <code class="text-info">{name.clone()}</code>
                                        {(!resource_spec(resource).is_empty()).then(|| view! {
                                            <span class="text-muted">{format!(" ({})", resource_spec(resource))}</span>
                                        })}
                                        {maintenance.then(|| view! {
                                            <span class="badge badge-warning">"In maintenance"</span>
                                        })}
                                        {(!node.is_empty()).then(|| view! {
                                            <div class="text-success">
                                                {format!("Active on: {}{}", node.clone(), if status.is_empty() {
                                                    String::new()
                                                } else {
                                                    format!(" ({})", status.clone())
                                                })}
                                            </div>
                                        })}
                                        {(node.is_empty() && !status.is_empty()).then(|| view! {
                                            <div class="text-muted">{format!("Status: {}", status.clone())}</div>
                                        })}
                                    </li>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </ul>
                })}

                {(!failed_actions.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>{format!("Failed Resource Actions ({})", failed_actions.len())}</strong></p>
                        <ul class="disk-list">
                            {failed_actions
                                .into_iter()
                                .map(|action| {
                                    let action_name = json_text(&action, "action");
                                    let node = json_text(&action, "node");
                                    let state = json_text(&action, "state");
                                    let return_code = json_text(&action, "returnCode");
                                    let details = json_text(&action, "details");
                                    view! {
                                        <li>
                                            <code class="text-danger">{action_name}</code>
                                            {(!node.is_empty()).then(|| view! {
                                                <span>{format!(" on {}", node.clone())}</span>
                                            })}
                                            {(!state.is_empty() || !return_code.is_empty()).then(|| view! {
                                                <div class="text-warning-dark">
                                                    {format!(
                                                        "State: {}{}",
                                                        if state.is_empty() { "unknown".to_string() } else { state.clone() },
                                                        if return_code.is_empty() {
                                                            String::new()
                                                        } else {
                                                            format!(" | Return Code: {}", return_code.clone())
                                                        },
                                                    )}
                                                </div>
                                            })}
                                            {(!details.is_empty()).then(|| view! {
                                                <div class="text-muted">{details}</div>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {(!constraints.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Resource Constraints ({})", constraints.len())}</summary>
                        <ul class="disk-list">
                            {constraints
                                .into_iter()
                                .map(|constraint| {
                                    let kind = json_text(&constraint, "type");
                                    let resource = json_text(&constraint, "resource");
                                    let with_resource = json_text(&constraint, "withResource");
                                    let node = json_text(&constraint, "node");
                                    let score = json_text(&constraint, "score");
                                    let first_resource = json_text(&constraint, "firstResource");
                                    let then_resource = json_text(&constraint, "thenResource");
                                    let first_action = json_text(&constraint, "firstAction");
                                    let then_action = json_text(&constraint, "thenAction");
                                    let id = json_text(&constraint, "id");
                                    let description = if kind == "location" {
                                        format!("{} → {}{}", resource, if node.is_empty() { "rule-based".to_string() } else { node }, if score.is_empty() { String::new() } else { format!(" (score: {})", score) })
                                    } else if kind == "colocation" {
                                        format!("{} ↔ {}{}", resource, with_resource, if score.is_empty() { String::new() } else { format!(" (score: {})", score) })
                                    } else if kind == "order" {
                                        format!("{} ({}) → {} ({})", first_resource, first_action, then_resource, then_action)
                                    } else {
                                        format!("{} constraint", kind)
                                    };
                                    view! {
                                        <li>
                                            {description}
                                            {(!id.is_empty()).then(|| view! {
                                                <span class="text-muted">{format!(" — ID: {}", id)}</span>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </details>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_fencing_section(fencing: &Value) -> Option<AnyView> {
    if !json_bool(fencing, "found") {
        return None;
    }

    let stonith_enabled = fencing.get("stonithEnabled").and_then(|v| v.as_bool());
    let stonith_status = match stonith_enabled {
        Some(true) => "Enabled".to_string(),
        Some(false) => "Disabled".to_string(),
        None => "Unknown".to_string(),
    };
    let stonith_class = if stonith_enabled == Some(true) {
        "text-success"
    } else {
        "text-danger"
    };
    let source_file = json_text(fencing, "stonithSourceFile");
    let source_pattern = json_text(fencing, "stonithSourcePattern");
    let devices = json_array(fencing, "fencingDevices");

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Fencing Configuration:"</p>
                <p>
                    <strong>"STONITH Status:"</strong>
                    " "
                    <span class=stonith_class>{stonith_status}</span>
                </p>
                {(!source_file.is_empty()).then(|| view! {
                    <p class="text-muted">
                        <em>{format!("Source: {}", source_file.clone())}</em>
                    </p>
                })}
                {(!source_pattern.is_empty()).then(|| view! {
                    <p><code>{source_pattern.clone()}</code></p>
                })}

                {if devices.is_empty() {
                    view! { <p class="text-danger"><em>"No fencing devices detected"</em></p> }
                        .into_any()
                } else {
                    view! {
                        <>
                            <p class="text-muted">
                                {format!(
                                    "{} fencing device{} configured",
                                    devices.len(),
                                    if devices.len() == 1 { "" } else { "s" },
                                )}
                            </p>
                            <ul class="disk-list">
                                {devices
                                    .into_iter()
                                    .map(|device| {
                                        let name = json_text(&device, "name");
                                        let agent = json_text(&device, "agent");
                                        let cloud = json_text(&device, "cloud");
                                        let device_type = json_text(&device, "type");
                                        let source_file = json_text(&device, "sourceFile");
                                        let source_line = json_text(&device, "sourceLine");
                                        let pattern = json_text(&device, "pattern");
                                        view! {
                                            <li>
                                                <code class="text-info">{name}</code>
                                                {(!agent.is_empty()).then(|| view! {
                                                    <span class="text-muted">{format!(" — {}", agent.clone())}</span>
                                                })}
                                                {(!cloud.is_empty()).then(|| view! {
                                                    <span class="badge badge-info">{cloud.clone()}</span>
                                                })}
                                                {(!device_type.is_empty()).then(|| view! {
                                                    <div class="text-muted">{format!("Type: {}", device_type.clone())}</div>
                                                })}
                                                {(!source_file.is_empty()).then(|| view! {
                                                    <div class="text-muted">
                                                        {format!(
                                                            "Source: {}{}",
                                                            source_file.clone(),
                                                            if source_line.is_empty() {
                                                                String::new()
                                                            } else {
                                                                format!(" (line {})", source_line.clone())
                                                            },
                                                        )}
                                                    </div>
                                                })}
                                                {(!pattern.is_empty()).then(|| view! {
                                                    <div><code>{pattern.clone()}</code></div>
                                                })}
                                            </li>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </ul>
                        </>
                    }
                    .into_any()
                }}
            </div>
        }
        .into_any(),
    )
}

fn render_maintenance_section(maintenance: &Value) -> Option<AnyView> {
    if !json_bool(maintenance, "found") {
        return None;
    }

    let maintenance_mode = maintenance
        .get("maintenanceMode")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let resources_in_maintenance = json_array(maintenance, "resourcesInMaintenance")
        .iter()
        .filter_map(value_name)
        .collect::<Vec<_>>();

    if !maintenance_mode && resources_in_maintenance.is_empty() {
        return None;
    }

    Some(
        view! {
            <div class="warning-block">
                <p><strong>"Maintenance Mode:"</strong></p>
                {maintenance_mode.then(|| view! {
                    <>
                        <p class="text-warning"><strong>"[!] Cluster is in MAINTENANCE MODE"</strong></p>
                        <p>
                            "Resources are not being managed. Run "
                            <code>"crm configure property maintenance-mode=false"</code>
                            " to exit."
                        </p>
                    </>
                })}
                {(!resources_in_maintenance.is_empty()).then(|| view! {
                    <>
                        <p><strong>"Resources in maintenance:"</strong></p>
                        <ul class="disk-list">
                            {resources_in_maintenance
                                .into_iter()
                                .map(|resource| view! { <li><code>{resource}</code></li> })
                                .collect::<Vec<_>>()}
                        </ul>
                    </>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_sbd_section(sbd: &Value) -> Option<AnyView> {
    if !json_bool(sbd, "found") {
        return None;
    }

    let devices = json_array(sbd, "sbdDevices")
        .iter()
        .filter_map(value_name)
        .collect::<Vec<_>>();
    let sbd_device = json_text(sbd, "sbdDevice");
    let sbd_pacemaker = json_text(sbd, "sbdPacemaker");
    let sbd_startmode = json_text(sbd, "sbdStartmode");
    let sbd_delay_start = json_text(sbd, "sbdDelayStart");
    let sbd_watchdog_dev = json_text(sbd, "sbdWatchdogDev");
    let sbd_watchdog_timeout = json_text(sbd, "sbdWatchdogTimeout");
    let sbd_timeout_action = json_text(sbd, "sbdTimeoutAction");
    let warnings = json_array(sbd, "warnings");
    let recommendations = json_array(sbd, "recommendations");

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"SBD Configuration:"</p>
                <KvTable>
                    {(!sbd_device.is_empty()).then(|| view! {
                        <KvRow label="SBD Device" value=sbd_device.clone()/>
                    })}
                    {(!devices.is_empty()).then(|| view! {
                        <KvRow label="SBD Devices" value=devices.join("; ")/>
                    })}
                    {(!sbd_pacemaker.is_empty()).then(|| view! {
                        <KvRow label="SBD_PACEMAKER" value=sbd_pacemaker.clone()/>
                    })}
                    {(!sbd_startmode.is_empty()).then(|| view! {
                        <KvRow label="SBD_STARTMODE" value=sbd_startmode.clone()/>
                    })}
                    {(!sbd_delay_start.is_empty()).then(|| view! {
                        <KvRow label="SBD_DELAY_START" value=sbd_delay_start.clone()/>
                    })}
                    {(!sbd_watchdog_dev.is_empty()).then(|| view! {
                        <KvRow label="Watchdog Device" value=sbd_watchdog_dev.clone()/>
                    })}
                    {(!sbd_watchdog_timeout.is_empty()).then(|| view! {
                        <KvRow label="Watchdog Timeout" value=sbd_watchdog_timeout.clone()/>
                    })}
                    {(!sbd_timeout_action.is_empty()).then(|| view! {
                        <KvRow label="Timeout Action" value=sbd_timeout_action.clone()/>
                    })}
                </KvTable>

                {(!warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p><strong>{format!("Warnings ({})", warnings.len())}</strong></p>
                        <ul class="disk-list">
                            {warnings
                                .into_iter()
                                .map(|warning| {
                                    let message = json_text(&warning, "message");
                                    let recommendation = json_text(&warning, "recommendation");
                                    view! {
                                        <li>
                                            {message}
                                            {(!recommendation.is_empty()).then(|| view! {
                                                <div class="text-muted">{recommendation}</div>
                                            })}
                                        </li>
                                    }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </div>
                })}

                {(!recommendations.is_empty()).then(|| view! {
                    <details class="content-details">
                        <summary>{format!("Recommendations ({})", recommendations.len())}</summary>
                        <ul class="disk-list">
                            {recommendations
                                .into_iter()
                                .map(|item| {
                                    let message = json_text(&item, "message");
                                    view! { <li>{message}</li> }
                                })
                                .collect::<Vec<_>>()}
                        </ul>
                    </details>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_cluster_events(events: &Value) -> Option<AnyView> {
    let mut resource_migrations = json_array(events, "resourceMigrations");
    let mut fencing_events = json_array(events, "fencingEvents");

    if resource_migrations.is_empty() && fencing_events.is_empty() {
        return None;
    }

    resource_migrations.sort_by(|a, b| json_text(b, "timestamp").cmp(&json_text(a, "timestamp")));
    fencing_events.sort_by(|a, b| json_text(b, "timestamp").cmp(&json_text(a, "timestamp")));

    let total_migrations = events
        .get("totalResourceMigrations")
        .and_then(|v| v.as_u64())
        .unwrap_or(resource_migrations.len() as u64) as usize;
    let total_fencing = events
        .get("totalFencingEvents")
        .and_then(|v| v.as_u64())
        .unwrap_or(fencing_events.len() as u64) as usize;
    let total_events = total_migrations + total_fencing;

    let rust_high_cpu_input = resource_migrations
        .iter()
        .filter_map(|migration| migration.get("logLine").and_then(|v| v.as_str()))
        .collect::<Vec<_>>()
        .join("\n");
    let rust_high_cpu_events = parse_pacemaker_high_cpu(&rust_high_cpu_input, "");

    Some(
        view! {
            <details class="warning-block" open=true>
                <summary>{format!("Cluster Events Detected ({} event{} found)", total_events, if total_events == 1 { "" } else { "s" })}</summary>
                <div class="section-body">
                    {(!resource_migrations.is_empty()).then(|| view! {
                        <>
                            <p><strong>{format!("Resource Events ({})", total_migrations)}</strong></p>
                            <ul class="disk-list">
                                {resource_migrations
                                    .into_iter()
                                    .map(|migration| {
                                        let timestamp = json_text(&migration, "timestamp");
                                        let resource = json_text(&migration, "resource");
                                        let action = json_text(&migration, "action");
                                        let from_node = json_text(&migration, "fromNode");
                                        let to_node = json_text(&migration, "toNode");
                                        let source_file = first_non_empty_text(&migration, &["sourcePath", "sourceFile"]);
                                        let source_line = json_text(&migration, "sourceLine");
                                        let log_line = first_non_empty_text(&migration, &["rawLine", "logLine"]);
                                        let description = if action == "migration" && !from_node.is_empty() && !to_node.is_empty() {
                                            format!("migrated from {} to {}", from_node, to_node)
                                        } else if action == "start" && !to_node.is_empty() {
                                            format!("started on {}", to_node)
                                        } else if action == "stop" && !from_node.is_empty() {
                                            format!("stopped on {}", from_node)
                                        } else {
                                            action.clone()
                                        };
                                        view! {
                                            <li class="event-item">
                                                {(!timestamp.is_empty()).then(|| view! {
                                                    <div class="event-timestamp text-info">{timestamp.clone()}</div>
                                                })}
                                                <div>
                                                    <code class="text-info">{resource}</code>
                                                    {(!description.is_empty()).then(|| view! {
                                                        <span>{format!(" {}", description.clone())}</span>
                                                    })}
                                                </div>
                                                {(!source_file.is_empty()).then(|| view! {
                                                    <div class="event-details">
                                                        {format!(
                                                            "Source: {}{}",
                                                            source_file.clone(),
                                                            if source_line.is_empty() {
                                                                String::new()
                                                            } else {
                                                                format!(":{}", source_line.clone())
                                                            },
                                                        )}
                                                    </div>
                                                })}
                                                {(!log_line.is_empty()).then(|| view! {
                                                    <div class="event-raw-line">{log_line.clone()}</div>
                                                })}
                                            </li>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </ul>
                        </>
                    })}

                    {(!rust_high_cpu_events.is_empty()).then(|| view! {
                        <div class="subsection">
                            <p><strong>{format!("Rust parser preview: Pacemaker high CPU events ({})", rust_high_cpu_events.len())}</strong></p>
                            <p class="text-muted">
                                "This list is produced by the shared Supportfile library used for the WASM UI and the Python prototype."
                            </p>
                            <ul class="disk-list">
                                {rust_high_cpu_events
                                    .clone()
                                    .into_iter()
                                    .map(|event| {
                                        view! {
                                            <li class="event-item">
                                                <div class="event-timestamp text-warning">{event.timestamp}</div>
                                                <div>
                                                    <strong class="text-warning">{event.source_node}</strong>
                                                    {format!(" - {:.6}% CPU via {}", event.cpu_load, event.resource)}
                                                </div>
                                                <div class="event-raw-line">{event.raw_line}</div>
                                            </li>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </ul>
                        </div>
                    })}

                    {(!fencing_events.is_empty()).then(|| view! {
                        <div class="subsection-danger">
                            <p><strong>{format!("Fencing/STONITH Events ({})", total_fencing)}</strong></p>
                            <ul class="disk-list">
                                {fencing_events
                                    .into_iter()
                                    .map(|event| {
                                        let timestamp = json_text(&event, "timestamp");
                                        let status = json_text(&event, "status");
                                        let target_node = json_text(&event, "targetNode");
                                        let action = json_text(&event, "action");
                                        let agent = json_text(&event, "agent");
                                        let source_file = first_non_empty_text(&event, &["sourcePath", "sourceFile"]);
                                        let source_line = json_text(&event, "sourceLine");
                                        let log_line = first_non_empty_text(&event, &["rawLine", "logLine"]);
                                        let status_class = match status.as_str() {
                                            "success" => "text-success",
                                            "failed" => "text-danger",
                                            "requested" | "pending" => "text-warning",
                                            "in_progress" => "text-info",
                                            _ => "text-muted",
                                        };
                                        view! {
                                            <li class="event-item">
                                                {(!timestamp.is_empty()).then(|| view! {
                                                    <div class="event-timestamp text-danger">{timestamp.clone()}</div>
                                                })}
                                                <div>
                                                    <span class=status_class><strong>{status.to_uppercase()}</strong></span>
                                                    " - Fencing of node "
                                                    <strong class="text-danger">{target_node}</strong>
                                                    {(!action.is_empty() && action != "fence").then(|| view! {
                                                        <span class="text-muted">{format!(" ({})", action.clone())}</span>
                                                    })}
                                                </div>
                                                {(!agent.is_empty()).then(|| view! {
                                                    <div class="event-details">{format!("Agent: {}", agent.clone())}</div>
                                                })}
                                                {(!source_file.is_empty()).then(|| view! {
                                                    <div class="event-details">
                                                        {format!(
                                                            "Source: {}{}",
                                                            source_file.clone(),
                                                            if source_line.is_empty() {
                                                                String::new()
                                                            } else {
                                                                format!(":{}", source_line.clone())
                                                            },
                                                        )}
                                                    </div>
                                                })}
                                                {(!log_line.is_empty()).then(|| view! {
                                                    <div class="event-raw-line">{log_line.clone()}</div>
                                                })}
                                            </li>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </ul>
                        </div>
                    })}
                </div>
            </details>
        }
        .into_any(),
    )
}

fn render_cluster_services(cluster_services: &Value) -> Option<AnyView> {
    let dlm = cluster_services.get("dlmService").cloned().unwrap_or(Value::Null);
    if !json_bool(&dlm, "detected") {
        return None;
    }

    let message = json_text(&dlm, "message");
    let detection_file = json_text(&dlm, "detectionFile");
    let doc = json_text(&dlm, "documentationUrl");

    Some(
        view! {
            <div class="danger-block">
                <p class="subsection-title">"Cluster Services"</p>
                <p><strong>"DLM Service"</strong> " — " {if message.is_empty() { "Enabled".to_string() } else { message }}</p>
                {(!detection_file.is_empty()).then(|| view! {
                    <p class="text-muted">{format!("Detected in {}", detection_file)}</p>
                })}
                {(!doc.is_empty()).then(|| view! {
                    <p>
                        <a href=doc.clone() target="_blank" rel="noopener noreferrer" class="text-info">{doc.clone()}</a>
                    </p>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_daemon_status(daemon: &Value) -> Option<AnyView> {
    if !json_bool(daemon, "found") {
        return None;
    }

    let warnings = json_array(daemon, "warnings");

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Daemon Status:"</p>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>"Service"</th>
                            <th>"Running"</th>
                            <th>"Boot Enabled"</th>
                        </tr>
                    </thead>
                    <tbody>
                        {[
                            "corosync",
                            "pacemaker",
                            "pcsd",
                        ]
                            .into_iter()
                            .filter_map(|service| {
                                let status = daemon.get("daemons").and_then(|v| v.get(service))?;
                                let active = status.get("active").and_then(|v| v.as_bool());
                                let enabled = status.get("enabled").and_then(|v| v.as_bool());
                                Some(view! {
                                    <tr>
                                        <td><code>{service}</code></td>
                                        <td class=if active == Some(true) { "text-success" } else { "text-danger" }>
                                            {match active {
                                                Some(true) => "active",
                                                Some(false) => "inactive",
                                                None => "unknown",
                                            }}
                                        </td>
                                        <td class=if enabled == Some(true) { "text-success" } else { "text-danger" }>
                                            {match enabled {
                                                Some(true) => "enabled",
                                                Some(false) => "disabled",
                                                None => "unknown",
                                            }}
                                        </td>
                                    </tr>
                                })
                            })
                            .collect::<Vec<_>>()}
                    </tbody>
                </table>

                {(!warnings.is_empty()).then(|| view! {
                    <div class="vm-notes">
                        {warnings
                            .into_iter()
                            .map(|warning| {
                                let severity = json_text(&warning, "severity");
                                let message = json_text(&warning, "message");
                                let recommendation = json_text(&warning, "recommendation");
                                let class = if severity == "error" {
                                    "vm-note warning"
                                } else {
                                    "vm-note info"
                                };
                                view! {
                                    <div class=class>
                                        <p><strong>{message}</strong></p>
                                        {(!recommendation.is_empty()).then(|| view! {
                                            <p>{recommendation}</p>
                                        })}
                                    </div>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </div>
                })}
            </div>
        }
        .into_any(),
    )
}

fn render_azure_fence_auth(auth: &Value) -> Option<AnyView> {
    if !json_bool(auth, "found") {
        return None;
    }

    let auth_method = json_text(auth, "authMethod");
    let auth_display = match auth_method.as_str() {
        "msi" => "Managed Identity (MSI)",
        "service_principal" => "Service Principal",
        _ => "Unknown",
    }
    .to_string();
    let auth_class = if auth_method == "msi" {
        "text-success"
    } else {
        "text-warning"
    };
    let subscription_id = json_text(auth, "subscriptionId");
    let resource_group = json_text(auth, "resourceGroup");
    let tenant_id = json_text(auth, "tenantId");
    let pcmk_monitor_retries = json_text(auth, "pcmkMonitorRetries");
    let pcmk_action_limit = json_text(auth, "pcmkActionLimit");
    let power_timeout = json_text(auth, "powerTimeout");
    let pcmk_reboot_timeout = json_text(auth, "pcmkRebootTimeout");
    let pcmk_delay_max = json_text(auth, "pcmkDelayMax");
    let pcmk_host_map = json_text(auth, "pcmkHostMap");
    let warnings = json_array(auth, "warnings");
    let recommendations = json_array(auth, "recommendations");

    Some(
        view! {
            <div class="subsection">
                <p class="subsection-title">"Azure Fence Agent Authentication:"</p>
                <p>
                    <strong>"Auth Method:"</strong>
                    " "
                    <span class=auth_class>{auth_display}</span>
                </p>
                <KvTable>
                    {(!subscription_id.is_empty()).then(|| view! {
                        <KvRow label="Subscription ID" value=subscription_id.clone()/>
                    })}
                    {(!resource_group.is_empty()).then(|| view! {
                        <KvRow label="Resource Group" value=resource_group.clone()/>
                    })}
                    {(!tenant_id.is_empty()).then(|| view! {
                        <KvRow label="Tenant ID" value=tenant_id.clone()/>
                    })}
                    {(!pcmk_monitor_retries.is_empty()).then(|| view! {
                        <KvRow label="pcmk_monitor_retries" value=pcmk_monitor_retries.clone()/>
                    })}
                    {(!pcmk_action_limit.is_empty()).then(|| view! {
                        <KvRow label="pcmk_action_limit" value=pcmk_action_limit.clone()/>
                    })}
                    {(!power_timeout.is_empty()).then(|| view! {
                        <KvRow label="power_timeout" value=power_timeout.clone()/>
                    })}
                    {(!pcmk_reboot_timeout.is_empty()).then(|| view! {
                        <KvRow label="pcmk_reboot_timeout" value=pcmk_reboot_timeout.clone()/>
                    })}
                    {(!pcmk_delay_max.is_empty()).then(|| view! {
                        <KvRow label="pcmk_delay_max" value=pcmk_delay_max.clone()/>
                    })}
                    {(!pcmk_host_map.is_empty()).then(|| view! {
                        <KvRow label="pcmk_host_map" value=pcmk_host_map.clone()/>
                    })}
                </KvTable>

                {(!warnings.is_empty() || !recommendations.is_empty()).then(|| view! {
                    <div class="vm-notes">
                        {warnings
                            .into_iter()
                            .chain(recommendations.into_iter())
                            .map(|item| {
                                let severity = json_text(&item, "severity");
                                let message = json_text(&item, "message");
                                let recommendation = json_text(&item, "recommendation");
                                let documentation_url = json_text(&item, "documentationUrl");
                                let class = if severity == "warning" {
                                    "vm-note warning"
                                } else {
                                    "vm-note info"
                                };
                                view! {
                                    <div class=class>
                                        <p><strong>{message}</strong></p>
                                        {(!recommendation.is_empty()).then(|| view! {
                                            <p>{recommendation}</p>
                                        })}
                                        {(!documentation_url.is_empty()).then(|| view! {
                                            <p>
                                                <a
                                                    href=documentation_url
                                                    target="_blank"
                                                    rel="noopener noreferrer"
                                                    class="text-info"
                                                >
                                                    "View Documentation"
                                                </a>
                                            </p>
                                        })}
                                    </div>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </div>
                })}
            </div>
        }
        .into_any(),
    )
}

fn resource_spec(resource: &Value) -> String {
    let class = json_text(resource, "class");
    let provider = json_text(resource, "provider");
    let resource_type = json_text(resource, "type");

    if resource_type.is_empty() {
        String::new()
    } else if class.is_empty() && provider.is_empty() {
        resource_type
    } else if provider.is_empty() {
        format!("{}:{}", class, resource_type)
    } else {
        format!("{}::{}:{}", class, provider, resource_type)
    }
}

fn json_text(value: &Value, key: &str) -> String {
    value.get(key).and_then(value_as_text).unwrap_or_default()
}

fn first_non_empty_text(value: &Value, keys: &[&str]) -> String {
    for key in keys {
        let text = json_text(value, key);
        if !text.is_empty() {
            return text;
        }
    }
    String::new()
}

fn value_as_text(value: &Value) -> Option<String> {
    value
        .as_str()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .or_else(|| value.as_i64().map(|v| v.to_string()))
        .or_else(|| value.as_u64().map(|v| v.to_string()))
        .or_else(|| {
            value
                .as_bool()
                .map(|v| if v { "true" } else { "false" }.to_string())
        })
        .or_else(|| {
            value.as_f64().map(|v| {
                if v.fract() == 0.0 {
                    format!("{v:.0}")
                } else {
                    v.to_string()
                }
            })
        })
}

/// Section 6 – Applications (SAP / EPIC).
#[component]
pub fn ApplicationsSection(data: Value) -> impl IntoView {
    let directories = json_array(&data, "directories");
    let files = json_array(&data, "files");
    let pacemaker = data
        .get("pacemakerResources")
        .cloned()
        .unwrap_or(Value::Null);
    let resources = json_array(&pacemaker, "resources");
    let distro_packages = data.get("distroPackages").cloned().unwrap_or(Value::Null);
    let basic_environment = data.get("basicEnvironment").cloned().unwrap_or(Value::Null);

    let dir_list = directories
        .iter()
        .filter_map(value_name)
        .map(|name| name.to_ascii_lowercase())
        .collect::<Vec<_>>();
    let file_list = files
        .iter()
        .filter_map(value_name)
        .map(|name| name.to_ascii_lowercase())
        .collect::<Vec<_>>();

    let sap_paths = ["usr/sap", "sapmnt", "hana/shared", "hana/data", "hana/log"];
    let found_sap_indicator = sap_paths.iter().any(|path| {
        dir_list.iter().any(|entry| entry.contains(path))
            || file_list.iter().any(|entry| entry.contains(path))
    });

    let hana_resources = resources
        .iter()
        .filter_map(|resource| {
            let name = json_str(resource, "name");
            let resource_type = json_str(resource, "type");
            let provider = json_str(resource, "provider");
            let haystack = format!(
                "{} {} {}",
                name.to_ascii_lowercase(),
                resource_type.to_ascii_lowercase(),
                provider.to_ascii_lowercase(),
            );

            if haystack.contains("hana") || haystack.contains("hdb") || haystack.contains("saphana")
            {
                Some(name)
            } else {
                None
            }
        })
        .collect::<Vec<_>>();

    let sap_pacemaker_resources = resources
        .iter()
        .filter_map(|resource| {
            let name = json_str(resource, "name");
            let resource_type = json_str(resource, "type");
            let provider = json_str(resource, "provider");
            let haystack = format!(
                "{} {} {}",
                name.to_ascii_lowercase(),
                resource_type.to_ascii_lowercase(),
                provider.to_ascii_lowercase(),
            );

            if haystack.contains("sap") || resource_type.contains("SAPInstance") {
                Some(name)
            } else {
                None
            }
        })
        .collect::<Vec<_>>();

    let sap_packages = collect_packages(&distro_packages, &["sap", "hana", "hdb", "saptune"]);
    let service_files_found = file_list.iter().any(|entry| {
        entry.ends_with(".service")
            || entry.contains("/etc/systemd/")
            || entry.contains("systemctl")
            || entry.contains("sapstart")
            || entry.contains("sapstartsrv")
            || entry.contains("saposcol")
    });

    let basic_env_sap = json_bool(&basic_environment, "sapProductDetected")
        || json_str(&basic_environment, "product")
            .to_ascii_lowercase()
            .contains("sap")
        || json_str(&basic_environment, "prettyName")
            .to_ascii_lowercase()
            .contains("sap")
        || json_str(&basic_environment, "name")
            .to_ascii_lowercase()
            .contains("sap");

    let sap_detected = found_sap_indicator
        || !hana_resources.is_empty()
        || !sap_pacemaker_resources.is_empty()
        || !sap_packages.is_empty()
        || service_files_found
        || basic_env_sap;

    let basic_env_epic = basic_environment
        .get("epicProductDetected")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let epic_packages = collect_packages(
        &distro_packages,
        &[
            "sap-instance-",
            "sapstartsrv",
            "sap-saptune",
            "sap-host-agent",
            "lvm2-clvm",
        ],
    );
    let epic_pacemaker_resources = resources
        .iter()
        .filter_map(|resource| {
            let name = json_str(resource, "name");
            let resource_type = json_str(resource, "type");
            let haystack = format!(
                "{} {}",
                name.to_ascii_lowercase(),
                resource_type.to_ascii_lowercase(),
            );

            if haystack.contains("epic") || haystack.contains("sap") {
                Some(name)
            } else {
                None
            }
        })
        .collect::<Vec<_>>();
    let epic_detected =
        basic_env_epic || !epic_packages.is_empty() || !epic_pacemaker_resources.is_empty();

    if !sap_detected && !epic_detected {
        return view! {}.into_any();
    }

    let mut sap_sources = Vec::new();
    if found_sap_indicator {
        sap_sources.push("SAP directory structure (/usr/sap, /hana/*, /sapmnt)".to_string());
    }
    if !hana_resources.is_empty() {
        sap_sources.push(format!("HANA resources ({})", hana_resources.join(", ")));
    }
    if !sap_pacemaker_resources.is_empty() {
        sap_sources.push(format!(
            "SAP pacemaker resources ({})",
            sap_pacemaker_resources.join(", "),
        ));
    }
    if !sap_packages.is_empty() {
        sap_sources.push(format!("SAP packages ({})", sap_packages.join(", ")));
    }
    if service_files_found {
        sap_sources.push("SAP service files".to_string());
    }
    if basic_env_sap {
        sap_sources.push("SAP product identification in OS metadata".to_string());
    }

    let mut epic_sources = Vec::new();
    if basic_env_epic {
        epic_sources.push("EPIC product identification in OS metadata".to_string());
    }
    if !epic_pacemaker_resources.is_empty() {
        epic_sources.push(format!(
            "EPIC pacemaker resources ({})",
            epic_pacemaker_resources.join(", "),
        ));
    }
    if !epic_packages.is_empty() {
        epic_sources.push(format!("EPIC packages ({})", epic_packages.join(", ")));
    }

    view! {
        <Section title="[OK] Applications" class="success-block" open=true>
            {sap_detected.then(|| view! {
                <div class="subsection">
                    <p class="text-success"><strong>"SAP Applications Detected"</strong></p>
                    <p>"The analysis detected SAP-related components:"</p>
                    <ul>
                        {sap_sources
                            .into_iter()
                            .map(|source| view! { <li>{format!("[OK] {source}")}</li> })
                            .collect::<Vec<_>>()}
                    </ul>
                </div>
            })}

            {epic_detected.then(|| view! {
                <div class="subsection">
                    <p class="text-success"><strong>"SAP EPIC Applications Detected"</strong></p>
                    <p>"The analysis detected SAP EPIC-related components:"</p>
                    <ul>
                        {epic_sources
                            .into_iter()
                            .map(|source| view! { <li>{format!("[OK] {source}")}</li> })
                            .collect::<Vec<_>>()}
                    </ul>
                </div>
            })}
        </Section>
    }
    .into_any()
}

/// Section 7 – SAP Instance Configuration.
#[component]
pub fn SapInstanceSection(data: Value) -> impl IntoView {
    let sap_config = data
        .get("sapInstanceConfig")
        .cloned()
        .unwrap_or(Value::Null);
    let sap_errors = data
        .get("sapInstanceErrors")
        .cloned()
        .unwrap_or(Value::Null);

    let config_warnings = json_array(&sap_config, "warnings");
    let runtime_errors = json_array(&sap_errors, "errors");

    let has_issues = (json_bool(&sap_config, "found") && !config_warnings.is_empty())
        || (json_bool(&sap_errors, "found") && !runtime_errors.is_empty());
    if !has_issues {
        return view! {}.into_any();
    }

    let total_issues = config_warnings.len() + runtime_errors.len();
    let has_errors = runtime_errors
        .iter()
        .any(|entry| json_str(entry, "severity").eq_ignore_ascii_case("error"));
    let block_class = if has_errors {
        "danger-block"
    } else {
        "warning-block"
    };

    let instances = json_array(&sap_config, "instances");
    let start_profile_errors = runtime_errors
        .iter()
        .filter(|entry| json_str(entry, "type") == "start_profile_not_found")
        .cloned()
        .collect::<Vec<_>>();
    let gray_status_errors = runtime_errors
        .iter()
        .filter(|entry| json_str(entry, "type") == "sap_service_gray_status")
        .cloned()
        .collect::<Vec<_>>();
    let filesystem_errors = runtime_errors
        .iter()
        .filter(|entry| json_str(entry, "type") == "filesystem_unmount_error")
        .cloned()
        .collect::<Vec<_>>();

    view! {
        <details class=block_class open=true>
            <summary>
                {format!(
                    "SAP Instance Configuration ({} issue{} found)",
                    total_issues,
                    if total_issues == 1 { "" } else { "s" },
                )}
            </summary>

            <div class="section-body">
                {(!instances.is_empty()).then(|| view! {
                    <div class="subsection">
                        <p><strong>"SAPInstance Resources:"</strong></p>
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>"Resource"</th>
                                    <th>"InstanceName"</th>
                                    <th>"START_PROFILE"</th>
                                </tr>
                            </thead>
                            <tbody>
                                {instances
                                    .into_iter()
                                    .map(|instance| {
                                        let resource_name = json_str(&instance, "resourceName");
                                        let instance_name = json_str(&instance, "instanceName");
                                        let start_profile = json_str(&instance, "startProfile");
                                        view! {
                                            <tr>
                                                <td><code>{resource_name}</code></td>
                                                <td><code>{if instance_name.is_empty() {
                                                    "N/A".to_string()
                                                } else {
                                                    instance_name
                                                }}</code></td>
                                                <td><code>{if start_profile.is_empty() {
                                                    "N/A".to_string()
                                                } else {
                                                    start_profile
                                                }}</code></td>
                                            </tr>
                                        }
                                    })
                                    .collect::<Vec<_>>()}
                            </tbody>
                        </table>
                    </div>
                })}

                {(!config_warnings.is_empty()).then(|| view! {
                    <div class="warning-block">
                        <p class="text-warning"><strong>"Configuration Issues:"</strong></p>
                        {config_warnings
                            .into_iter()
                            .map(|warning| {
                                let severity = json_str(&warning, "severity");
                                let message = json_str(&warning, "message");
                                let resource = json_str(&warning, "resource");
                                let recommendation = json_str(&warning, "recommendation");
                                let documentation_url = json_str(&warning, "documentationUrl");
                                let text_class = if severity == "error" {
                                    "text-danger"
                                } else {
                                    "text-warning"
                                };
                                view! {
                                    <div class="subsection">
                                        <p class=text_class><strong>{message}</strong></p>
                                        {(!resource.is_empty()).then(|| view! {
                                            <p>
                                                <strong>"Resource:"</strong>
                                                " "
                                                <code>{resource}</code>
                                            </p>
                                        })}
                                        {(!recommendation.is_empty()).then(|| view! {
                                            <p>
                                                <strong>"Recommendation:"</strong>
                                                " "
                                                {recommendation}
                                            </p>
                                        })}
                                        {(!documentation_url.is_empty()).then(|| view! {
                                            <p>
                                                <a
                                                    href=documentation_url
                                                    target="_blank"
                                                    rel="noopener noreferrer"
                                                    class="text-info"
                                                >
                                                    "View Documentation"
                                                </a>
                                            </p>
                                        })}
                                    </div>
                                }
                            })
                            .collect::<Vec<_>>()}
                    </div>
                })}

                {render_sap_issue_group(
                    "START_PROFILE Errors",
                    "The SAP instance cannot find the expected START profile.",
                    start_profile_errors,
                    "danger-block",
                )}
                {render_sap_issue_group(
                    "SAP Services in GRAY Status",
                    "SAP instance services are not running properly.",
                    gray_status_errors,
                    "danger-block",
                )}
                {render_sap_issue_group(
                    "Filesystem Errors",
                    "Filesystem operations failed during cluster resource management.",
                    filesystem_errors,
                    "warning-block",
                )}
            </div>
        </details>
    }
    .into_any()
}

fn value_name(value: &Value) -> Option<String> {
    value.as_str().map(|name| name.to_string()).or_else(|| {
        value
            .get("name")
            .and_then(|name| name.as_str())
            .map(|name| name.to_string())
    })
}

fn collect_packages(packages_value: &Value, patterns: &[&str]) -> Vec<String> {
    packages_value
        .get("packages")
        .and_then(|packages| packages.as_object())
        .map(|packages| {
            packages
                .iter()
                .filter_map(|(name, version)| {
                    let lower_name = name.to_ascii_lowercase();
                    if patterns.iter().any(|pattern| lower_name.contains(pattern)) {
                        let version = version.as_str().unwrap_or("");
                        if version.is_empty() {
                            Some(name.clone())
                        } else {
                            Some(format!("{name}-{version}"))
                        }
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn render_sap_issue_group(
    title: &'static str,
    intro: &'static str,
    items: Vec<Value>,
    class: &'static str,
) -> Option<AnyView> {
    if items.is_empty() {
        return None;
    }

    let len = items.len();
    let recommendation = items.iter().find_map(|item| {
        let recommendation = json_str(item, "recommendation");
        if recommendation.is_empty() {
            None
        } else {
            Some(recommendation)
        }
    });

    Some(
        view! {
            <div class=class>
                <p><strong>{format!("{title} ({len})")}</strong></p>
                <p>{intro}</p>

                {items
                    .into_iter()
                    .map(|item| {
                        let resource_name = json_str(&item, "resourceName");
                        let service_name = json_str(&item, "serviceName");
                        let mount_point = json_str(&item, "mountPoint");
                        let profile_path = json_str(&item, "profilePath");
                        let message = json_str(&item, "message");
                        let timestamp = json_str(&item, "timestamp");
                        let source_file = json_str(&item, "sourceFile");
                        let raw_line = json_str(&item, "rawLine");
                        let line_number = item
                            .get("lineNumber")
                            .and_then(|value| value.as_u64())
                            .map(|value| value.to_string())
                            .unwrap_or_default();

                        view! {
                            <div class="subsection">
                                {(!resource_name.is_empty()).then(|| view! {
                                    <p>
                                        <strong>"Resource:"</strong>
                                        " "
                                        <code>{resource_name}</code>
                                    </p>
                                })}
                                {(!service_name.is_empty()).then(|| view! {
                                    <p>
                                        <strong>"Service:"</strong>
                                        " "
                                        <code>{service_name}</code>
                                    </p>
                                })}
                                {(!mount_point.is_empty()).then(|| view! {
                                    <p>
                                        <strong>"Mount Point:"</strong>
                                        " "
                                        <code>{mount_point}</code>
                                    </p>
                                })}
                                {(!profile_path.is_empty()).then(|| view! {
                                    <p>
                                        <strong>"Profile Path:"</strong>
                                        " "
                                        <code>{profile_path}</code>
                                    </p>
                                })}
                                {(!message.is_empty()).then(|| view! {
                                    <p>
                                        <strong>"Error:"</strong>
                                        " "
                                        {message}
                                    </p>
                                })}
                                {(!timestamp.is_empty()).then(|| view! {
                                    <p class="text-muted">{format!("Timestamp: {timestamp}")}</p>
                                })}
                                {(!source_file.is_empty() || !line_number.is_empty()).then(|| view! {
                                    <p class="text-muted">
                                        <strong>"Source:"</strong>
                                        " "
                                        <code>{if line_number.is_empty() {
                                            source_file.clone()
                                        } else {
                                            format!("{} (line {})", source_file, line_number)
                                        }}</code>
                                    </p>
                                })}
                                {(!raw_line.is_empty()).then(|| view! {
                                    <details class="content-details">
                                        <summary>"Show raw log line"</summary>
                                        <pre>{raw_line}</pre>
                                    </details>
                                })}
                            </div>
                        }
                    })
                    .collect::<Vec<_>>()}

                {recommendation.map(|text| {
                    view! {
                        <p>
                            <strong>"Recommendation:"</strong>
                            " "
                            {text}
                        </p>
                    }
                })}
            </div>
        }
        .into_any(),
    )
}
