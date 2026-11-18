use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section – SAP HANA deadlocks (from indexserver/nameserver trace files).
#[component]
pub fn DeadlocksSection(data: Value) -> impl IntoView {
    let dl = data.get("hanaDeadlocks").cloned().unwrap_or(Value::Null);

    if !json_bool(&dl, "found") {
        return view! {}.into_any();
    }

    let warnings = json_array(&dl, "warnings");
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
        <Section title="SAP HANA Deadlocks" class=class>
            {render_deadlock_summary(&dl)}
            {render_deadlock_warnings(&warnings)}
            {render_top_counts(&dl, "topObjects", "Most contended objects", "Object")}
            {render_top_counts(&dl, "topStatements", "Most rolled-back statements", "Statement hash")}
            {render_deadlock_table(&dl)}
        </Section>
    }
    .into_any()
}

fn render_deadlock_summary(dl: &Value) -> AnyView {
    let count = json_u64(dl, "count");
    let last = json_str(dl, "lastDeadlock");

    view! {
        <table class="kv-table">
            <tbody>
                <KvRow label="Deadlocks detected" value=count.to_string()/>
                <KvRow
                    label="Last deadlock"
                    value=if last.is_empty() { "—".to_string() } else { last }
                />
            </tbody>
        </table>
    }
    .into_any()
}

fn render_deadlock_warnings(warnings: &[Value]) -> Option<AnyView> {
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

/// Render a `name -> count` top-N list (top objects / top statements).
fn render_top_counts(dl: &Value, key: &str, title: &str, label: &str) -> Option<AnyView> {
    let counts = json_array(dl, key);
    if counts.is_empty() {
        return None;
    }
    let title = title.to_string();
    let label = label.to_string();

    let rows = counts
        .iter()
        .map(|row| {
            let name = json_str(row, "name");
            let count = json_u64(row, "count");
            view! {
                <tr>
                    <td><code>{name}</code></td>
                    <td>{count.to_string()}</td>
                </tr>
            }
        })
        .collect::<Vec<_>>();

    Some(
        view! {
            <details class="content-details">
                <summary>{title}</summary>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>{label}</th>
                            <th>"Deadlocks"</th>
                        </tr>
                    </thead>
                    <tbody>{rows}</tbody>
                </table>
            </details>
        }
        .into_any(),
    )
}

fn render_deadlock_table(dl: &Value) -> Option<AnyView> {
    let deadlocks = json_array(dl, "deadlocks");
    if deadlocks.is_empty() {
        return None;
    }

    // Cap the rendered rows to keep the DOM light on multi-day traces.
    const MAX_ROWS: usize = 200;
    let total = deadlocks.len();
    let truncated = total > MAX_ROWS;

    let rows = deadlocks
        .iter()
        .take(MAX_ROWS)
        .map(|row| {
            let timestamp = json_str(row, "timestamp");
            let participants = json_u64(row, "participantCount");
            let objects = json_array(row, "objects")
                .iter()
                .map(|o| o.as_str().unwrap_or("").to_string())
                .collect::<Vec<_>>()
                .join(", ");
            let victim = row.get("victim").cloned().unwrap_or(Value::Null);
            let victim_host = json_str(&victim, "clientHost");
            let victim_user = json_str(&victim, "dbUser");
            let victim_label = match (victim_host.is_empty(), victim_user.is_empty()) {
                (true, true) => "—".to_string(),
                (false, true) => victim_host,
                (true, false) => victim_user,
                (false, false) => format!("{victim_user} @ {victim_host}"),
            };
            view! {
                <tr>
                    <td>{timestamp}</td>
                    <td>{participants.to_string()}</td>
                    <td><code>{objects}</code></td>
                    <td>{victim_label}</td>
                </tr>
            }
        })
        .collect::<Vec<_>>();

    Some(
        view! {
            <details class="content-details">
                <summary>
                    {format!("Deadlock events ({total})")}
                </summary>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>"Timestamp"</th>
                            <th>"Parties"</th>
                            <th>"Objects"</th>
                            <th>"Victim"</th>
                        </tr>
                    </thead>
                    <tbody>{rows}</tbody>
                </table>
                {truncated.then(|| view! {
                    <p class="muted">
                        {format!("Showing first {MAX_ROWS} of {total} deadlock events.")}
                    </p>
                })}
            </details>
        }
        .into_any(),
    )
}
