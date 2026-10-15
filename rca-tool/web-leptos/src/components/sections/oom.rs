use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Format an optional byte count into a human-readable string, or `—`.
fn opt_bytes(row: &Value, key: &str) -> String {
    row.get(key)
        .and_then(|v| v.as_f64())
        .map(format_bytes)
        .unwrap_or_else(|| "—".to_string())
}

/// Section – SAP HANA out-of-memory events (from indexserver/nameserver traces).
#[component]
pub fn OomSection(data: Value) -> impl IntoView {
    let oom = data.get("hanaOom").cloned().unwrap_or(Value::Null);

    if !json_bool(&oom, "found") {
        return view! {}.into_any();
    }

    let warnings = json_array(&oom, "warnings");
    // OOM warnings are always errors, but keep the same severity-aware styling.
    let error_count = warnings
        .iter()
        .filter(|w| json_str(w, "severity") == "error")
        .count();
    let warning_count = warnings.len() - error_count;
    let class = if error_count > 0 {
        "danger-block"
    } else if warning_count > 0 {
        "warning-block"
    } else {
        "content-details"
    };

    view! {
        <Section title="SAP HANA Out-of-Memory" class=class>
            {render_oom_summary(&oom)}
            {render_oom_warnings(&warnings)}
            {render_oom_table(&oom)}
        </Section>
    }
    .into_any()
}

fn render_oom_summary(oom: &Value) -> AnyView {
    let count = json_u64(oom, "count");
    let last = json_str(oom, "lastOom");

    view! {
        <table class="kv-table">
            <tbody>
                <KvRow label="Out-of-memory events" value=count.to_string()/>
                <KvRow
                    label="Last OOM"
                    value=if last.is_empty() { "—".to_string() } else { last }
                />
            </tbody>
        </table>
    }
    .into_any()
}

fn render_oom_warnings(warnings: &[Value]) -> Option<AnyView> {
    if warnings.is_empty() {
        return None;
    }

    Some(
        warnings
            .iter()
            .map(|warning| {
                let severity = json_str(warning, "severity");
                let message = json_str(warning, "message");
                let details = json_str(warning, "details");
                let recommendation = json_str(warning, "recommendation");
                let class = if severity == "error" {
                    "danger-block"
                } else if severity == "warning" {
                    "warning-block"
                } else {
                    "info-block"
                };
                let heading = if severity == "error" {
                    "Error"
                } else if severity == "warning" {
                    "Warning"
                } else {
                    "Info"
                };
                view! {
                    <div class=class>
                        <p>
                            <strong>{format!("{heading}:")}</strong>
                            " "
                            {message}
                        </p>
                        {(!details.is_empty())
                            .then(|| view! { <p><code>{details}</code></p> })}
                        {(!recommendation.is_empty())
                            .then(|| view! { <p>{recommendation}</p> })}
                    </div>
                }
            })
            .collect::<Vec<_>>()
            .into_any(),
    )
}

fn render_oom_table(oom: &Value) -> Option<AnyView> {
    let events = json_array(oom, "events");
    if events.is_empty() {
        return None;
    }

    // Cap the rendered rows to keep the DOM light on multi-day traces.
    const MAX_ROWS: usize = 200;
    let total = events.len();
    let truncated = total > MAX_ROWS;

    let opt_str = |row: &Value, key: &str| -> String {
        let s = json_str(row, key);
        if s.is_empty() { "—".to_string() } else { s }
    };

    let rows = events
        .iter()
        .take(MAX_ROWS)
        .map(|row| {
            let timestamp = json_str(row, "timestamp");
            let mem_type = opt_str(row, "memoryType");
            let host = opt_str(row, "host");
            let executable = opt_str(row, "executable");
            let failed = opt_bytes(row, "failedAllocBytes");
            let gal = opt_bytes(row, "globalAllocationLimitBytes");
            view! {
                <tr>
                    <td>{timestamp}</td>
                    <td>{mem_type}</td>
                    <td>{host}</td>
                    <td>{executable}</td>
                    <td>{failed}</td>
                    <td>{gal}</td>
                </tr>
            }
        })
        .collect::<Vec<_>>();

    Some(
        view! {
            <details class="content-details">
                <summary>
                    {format!("Out-of-memory events ({total})")}
                </summary>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>"Timestamp"</th>
                            <th>"Memory type"</th>
                            <th>"Host"</th>
                            <th>"Executable"</th>
                            <th>"Failed allocation"</th>
                            <th>"Global allocation limit"</th>
                        </tr>
                    </thead>
                    <tbody>{rows}</tbody>
                </table>
                {truncated.then(|| view! {
                    <p class="muted">
                        {format!("Showing first {MAX_ROWS} of {total} out-of-memory events.")}
                    </p>
                })}
            </details>
        }
        .into_any(),
    )
}
