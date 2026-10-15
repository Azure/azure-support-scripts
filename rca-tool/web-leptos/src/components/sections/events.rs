use std::collections::BTreeMap;

use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section 9 – Events (always rendered, count-based severity).
#[component]
pub fn EventsSection(data: Value) -> impl IntoView {
    let live_migration = data.get("liveMigration").cloned().unwrap_or(Value::Null);
    let kernel_reboots = data.get("kernelReboots").cloned().unwrap_or(Value::Null);
    let oom_killer = data.get("oomKiller").cloned().unwrap_or(Value::Null);
    let xfs_errors = data.get("xfsErrors").cloned().unwrap_or(Value::Null);
    let emergency_mode = data.get("emergencyMode").cloned().unwrap_or(Value::Null);
    let ssh_service = data.get("sshService").cloned().unwrap_or(Value::Null);
    let automation = data.get("automation").cloned().unwrap_or(Value::Null);

    let lm_count = event_count(&live_migration);
    let kr_count = event_count(&kernel_reboots);
    let oom_count = event_count(&oom_killer);
    let xfs_count = event_count(&xfs_errors);
    let em_count = event_count(&emergency_mode);
    let ssh_count = event_count(&ssh_service);
    let automation_count = event_count(&automation);

    let total_danger = oom_count + xfs_count + em_count + ssh_count;
    let total_warning = lm_count + kr_count;
    let total = lm_count + kr_count + oom_count + xfs_count + em_count + ssh_count;

    if total == 0 && automation_count == 0 {
        return view! {}.into_any();
    }

    let class = severity_class(total_danger, total_warning);

    view! {
        <Section title="Events" class=class>
            {render_event_subsection("Live Migration Events", &live_migration, lm_count, "info")}
            {render_event_subsection("Kernel Reboots", &kernel_reboots, kr_count, "warning")}
            {render_event_subsection("OOM Killer Events", &oom_killer, oom_count, "danger")}
            {render_event_subsection("XFS Filesystem Errors", &xfs_errors, xfs_count, "danger")}
            {render_event_subsection("Emergency Mode Events", &emergency_mode, em_count, "danger")}
            {render_event_subsection("SSH Service Issues", &ssh_service, ssh_count, "danger")}
            {render_automation_section(&automation, automation_count)}
        </Section>
    }
    .into_any()
}

fn event_count(value: &Value) -> usize {
    value
        .get("count")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or_else(|| json_array(value, "events").len())
}

fn render_event_subsection(title: &str, data: &Value, count: usize, kind: &str) -> AnyView {
    let class = if count > 0 {
        format!("{kind}-block")
    } else {
        "info-block".to_string()
    };
    let unit = if title == "XFS Filesystem Errors" {
        "error"
    } else if title == "SSH Service Issues" {
        "issue"
    } else {
        "event"
    };
    let summary_title = if count > 0 {
        match title {
            "Live Migration Events" => "Live Migration Events Detected",
            "Kernel Reboots" => "Kernel Reboots Detected",
            _ => title,
        }
    } else {
        title
    };
    let summary_text = format!(
        "{} ({} {}{} found)",
        summary_title,
        count,
        unit,
        if count == 1 { "" } else { "s" }
    );

    view! {
        <details class=class>
            <summary>{summary_text}</summary>
            <div class="section-body">{render_event_body(title, data, count)}</div>
        </details>
    }
    .into_any()
}

fn render_event_body(title: &str, data: &Value, count: usize) -> AnyView {
    let mut events = json_array(data, "events");
    events.sort_by(|a, b| {
        let ts_cmp = json_str(b, "timestamp").cmp(&json_str(a, "timestamp"));
        if ts_cmp == std::cmp::Ordering::Equal {
            b.get("lineNumber")
                .and_then(|v| v.as_u64())
                .cmp(&a.get("lineNumber").and_then(|v| v.as_u64()))
        } else {
            ts_cmp
        }
    });

    if count == 0 || events.is_empty() {
        let empty_message = match title {
            "Live Migration Events" => "No live migration events were detected in the analyzed files.",
            "Kernel Reboots" => "No kernel reboot events were detected in the analyzed files.",
            "OOM Killer Events" => "No OOM (Out of Memory) killer events were detected in the analyzed files.",
            "XFS Filesystem Errors" => "No XFS filesystem errors were detected in the analyzed files.",
            "Emergency Mode Events" => "No emergency mode events were detected in the analyzed files.",
            "SSH Service Issues" => "No SSH service issues were detected in the analyzed files.",
            _ => "No events found.",
        };
        return view! { <p class="text-muted"><em>{empty_message}</em></p> }.into_any();
    }

    match title {
        "Live Migration Events" => view! {
            <>
                <p><strong>"Detected Hyper-V Live Migration events:"</strong></p>
                <ul class="event-list">
                    {events
                        .into_iter()
                        .map(|event| {
                            let timestamp = non_empty(json_str(&event, "timestamp"), "Unknown".to_string());
                            let source = format_source(&event);
                            let line_number = event
                                .get("lineNumber")
                                .and_then(|v| v.as_u64())
                                .map(|v| v.to_string())
                                .unwrap_or_default();
                            view! {
                                <li class="event-item">
                                    <strong class="text-info">{timestamp}</strong>
                                    {(!line_number.is_empty()).then(|| view! {
                                        <span class="text-muted">{format!(" | Line: {}", line_number)}</span>
                                    })}
                                    {(!source.is_empty()).then(|| view! {
                                        <div class="event-details">{format!("Source: {}", source)}</div>
                                    })}
                                </li>
                            }
                        })
                        .collect::<Vec<_>>()}
                </ul>
                <p class="text-muted"><em>"Detection pattern: hv_utils: Heartbeat IC → hv_balloon → hv_netvsc within 100 lines"</em></p>
            </>
        }
        .into_any(),

        "Kernel Reboots" => view! {
            <>
                <p><strong>"Detected system reboots:"</strong></p>
                <ul class="event-list">
                    {events
                        .into_iter()
                        .map(|event| {
                            let timestamp = non_empty(json_str(&event, "timestamp"), "Unknown".to_string());
                            let kernel_version = json_str(&event, "kernelVersion");
                            let event_type = json_str(&event, "type").replace('_', " ");
                            let source = format_source(&event);
                            view! {
                                <li class="event-item">
                                    <strong class="text-warning-dark">{timestamp}</strong>
                                    {(!kernel_version.is_empty()).then(|| view! {
                                        <span class="badge badge-warning">{format!("Kernel {}", kernel_version.clone())}</span>
                                    })}
                                    {(!event_type.is_empty()).then(|| view! {
                                        <div class="event-details">{format!("Type: {}", event_type)}</div>
                                    })}
                                    {(!source.is_empty()).then(|| view! {
                                        <div class="event-details">{format!("Source: {}", source)}</div>
                                    })}
                                </li>
                            }
                        })
                        .collect::<Vec<_>>()}
                </ul>
            </>
        }
        .into_any(),

        "OOM Killer Events" => view! {
            <>
                <p><strong>"Detected OOM killer events:"</strong></p>
                <ul class="event-list">
                    {events
                        .into_iter()
                        .map(|event| {
                            let timestamp = non_empty(json_str(&event, "timestamp"), "Unknown".to_string());
                            let process_name = json_str(&event, "processName");
                            let pid = json_str(&event, "pid");
                            let raw_line = json_str(&event, "rawLine");
                            let source = format_source(&event);
                            view! {
                                <li class="event-item">
                                    <strong class="text-danger">{timestamp}</strong>
                                    {(!process_name.is_empty()).then(|| view! {
                                        <div>
                                            <strong>{process_name.clone()}</strong>
                                            {(!pid.is_empty()).then(|| view! {
                                                <span class="text-muted">{format!(" (PID {})", pid.clone())}</span>
                                            })}
                                        </div>
                                    })}
                                    {(!raw_line.is_empty()).then(|| view! {
                                        <div class="event-raw-line">{raw_line.clone()}</div>
                                    })}
                                    {(!source.is_empty()).then(|| view! {
                                        <div class="event-details">{format!("Source: {}", source)}</div>
                                    })}
                                </li>
                            }
                        })
                        .collect::<Vec<_>>()}
                </ul>
            </>
        }
        .into_any(),

        "XFS Filesystem Errors" => view! {
            <>
                <p><strong>"Detected XFS filesystem errors requiring attention:"</strong></p>
                <ul class="event-list">
                    {events
                        .into_iter()
                        .map(|event| {
                            let timestamp = non_empty(json_str(&event, "timestamp"), "Unknown".to_string());
                            let device = json_str(&event, "device");
                            let message = json_str(&event, "message");
                            let raw_line = json_str(&event, "rawLine");
                            let source = format_source(&event);
                            view! {
                                <li class="event-item">
                                    <strong class="text-danger">{timestamp}</strong>
                                    {(!device.is_empty()).then(|| view! {
                                        <div><strong>{format!("Device: {}", device.clone())}</strong></div>
                                    })}
                                    {(!message.is_empty()).then(|| view! {
                                        <div>{message.clone()}</div>
                                    })}
                                    {(!raw_line.is_empty()).then(|| view! {
                                        <div class="event-raw-line">{raw_line.clone()}</div>
                                    })}
                                    {(!source.is_empty()).then(|| view! {
                                        <div class="event-details">{format!("Source: {}", source)}</div>
                                    })}
                                </li>
                            }
                        })
                        .collect::<Vec<_>>()}
                </ul>
            </>
        }
        .into_any(),

        _ => view! {
            <ul class="event-list">
                {events
                    .into_iter()
                    .map(|event| {
                        let message = first_non_empty(&[
                            json_str(&event, "message"),
                            json_str(&event, "rawLine"),
                            event.as_str().unwrap_or_default().to_string(),
                        ]);
                        let source = format_source(&event);
                        view! {
                            <li class="event-item">
                                <div>{message}</div>
                                {(!source.is_empty()).then(|| view! {
                                    <div class="event-details">{format!("Source: {}", source)}</div>
                                })}
                            </li>
                        }
                    })
                    .collect::<Vec<_>>()}
            </ul>
        }
        .into_any(),
    }
}

fn render_automation_section(automation: &Value, count: usize) -> AnyView {
    let events = json_array(automation, "events");
    let mut events_by_tool: BTreeMap<String, Vec<Value>> = BTreeMap::new();
    for event in events {
        let tool_type = non_empty(json_str(&event, "toolType"), "other".to_string());
        events_by_tool.entry(tool_type).or_default().push(event);
    }

    view! {
        <details class="info-block">
            <summary>{format!("Automation Tools Usage ({} event{} found)", count, if count == 1 { "" } else { "s" })}</summary>
            <div class="section-body">
                {if count == 0 || events_by_tool.is_empty() {
                    view! {
                        <>
                            <p class="text-muted"><em>"No automation tool usage was detected in the analyzed files."</em></p>
                            <p class="text-muted"><em>"Detection patterns: \"ansible-command:\", \"ansible-setup:\", \"puppet-agent:\", \"puppet apply\", \"puppet-run:\", \"chef-client[PID]:\", \"chef-solo[PID]:\", \"chef-apply[PID]:\" (Future: SaltStack)"</em></p>
                        </>
                    }
                    .into_any()
                } else {
                    view! {
                        <>
                            <p><strong>"Detected automation tool executions:"</strong></p>
                            {events_by_tool
                                .into_iter()
                                .map(|(tool_type, mut tool_events)| {
                                    tool_events.sort_by(|a, b| {
                                        a.get("lineNumber")
                                            .and_then(|v| v.as_u64())
                                            .cmp(&b.get("lineNumber").and_then(|v| v.as_u64()))
                                    });
                                    let tool_name = format_tool_name(&tool_type);
                                    let execution_count = tool_events.len();
                                    view! {
                                        <details class="content-details" open=true>
                                            <summary>{format!("{} ({} execution{})", tool_name, execution_count, if execution_count == 1 { "" } else { "s" })}</summary>
                                            <ul class="event-list">
                                                {tool_events
                                                    .into_iter()
                                                    .map(|event| {
                                                        let timestamp = non_empty(json_str(&event, "timestamp"), "Unknown".to_string());
                                                        let pattern_type = json_str(&event, "patternType");
                                                        let command = json_str(&event, "command");
                                                        let source = format_source(&event);
                                                        let pattern_label = if pattern_type.is_empty() {
                                                            String::new()
                                                        } else {
                                                            format!("{}-{}:", tool_type, pattern_type)
                                                        };
                                                        view! {
                                                            <li class="event-item">
                                                                <strong class="text-info">{timestamp}</strong>
                                                                {(!pattern_label.is_empty()).then(|| view! {
                                                                    <div><code>{pattern_label.clone()}</code></div>
                                                                })}
                                                                {(!command.is_empty()).then(|| view! {
                                                                    <div><code>{command.clone()}</code></div>
                                                                })}
                                                                {(!source.is_empty()).then(|| view! {
                                                                    <div class="event-details">{format!("Source: {}", source)}</div>
                                                                })}
                                                            </li>
                                                        }
                                                    })
                                                    .collect::<Vec<_>>()}
                                            </ul>
                                        </details>
                                    }
                                })
                                .collect::<Vec<_>>()}
                            <p class="text-muted"><em>"Detection patterns: \"ansible-command:\", \"ansible-setup:\", \"puppet-agent:\", \"puppet apply\", \"puppet-run:\", \"chef-client[PID]:\", \"chef-solo[PID]:\", \"chef-apply[PID]:\""</em></p>
                        </>
                    }
                    .into_any()
                }}
            </div>
        </details>
    }
    .into_any()
}

fn format_tool_name(tool_type: &str) -> String {
    let mut chars = tool_type.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => "Other".to_string(),
    }
}

fn format_source(event: &Value) -> String {
    let source_file = json_str(event, "sourceFile");
    let line_number = event
        .get("lineNumber")
        .or_else(|| event.get("sourceLine"))
        .and_then(|v| v.as_u64())
        .map(|v| v.to_string())
        .unwrap_or_default();
    if source_file.is_empty() {
        String::new()
    } else if line_number.is_empty() {
        source_file
    } else {
        format!("{}:{}", source_file, line_number)
    }
}

fn first_non_empty(values: &[String]) -> String {
    values
        .iter()
        .find(|value| !value.trim().is_empty())
        .cloned()
        .unwrap_or_else(|| "No details available".to_string())
}

fn non_empty(value: String, fallback: String) -> String {
    if value.trim().is_empty() {
        fallback
    } else {
        value
    }
}
