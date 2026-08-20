use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Extract an f64 from a JSON value, or `None` if missing / not numeric.
fn json_opt_f64(value: &Value, key: &str) -> Option<f64> {
    value.get(key).and_then(|v| v.as_f64())
}

/// Section – SAP HANA savepoints (from indexserver/nameserver trace files).
#[component]
pub fn HanaSection(data: Value) -> impl IntoView {
    let sp = data.get("hanaSavepoints").cloned().unwrap_or(Value::Null);

    if !json_bool(&sp, "found") {
        return view! {}.into_any();
    }

    let warnings = json_array(&sp, "warnings");
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
        <Section title="SAP HANA Savepoints" class=class>
            {render_savepoint_summary(&sp)}
            {render_savepoint_warnings(&warnings)}
            {render_savepoint_table(&sp)}
        </Section>
    }
    .into_any()
}

fn render_savepoint_summary(sp: &Value) -> AnyView {
    let count = json_u64(sp, "count");
    let snapshot_count = json_u64(sp, "snapshotCount");
    let last = json_str(sp, "lastSavepoint");
    let avg = json_opt_f64(sp, "avgIntervalS");
    let max = json_opt_f64(sp, "maxIntervalS");

    let fmt_secs = |v: Option<f64>| -> String {
        v.map(|s| format!("{s:.0} s")).unwrap_or_else(|| "—".to_string())
    };

    view! {
        <table class="kv-table">
            <tbody>
                <KvRow label="Periodic savepoints" value=count.to_string()/>
                <KvRow label="Snapshot savepoints" value=snapshot_count.to_string()/>
                <KvRow
                    label="Last savepoint"
                    value=if last.is_empty() { "—".to_string() } else { last }
                />
                <KvRow label="Average interval" value=fmt_secs(avg)/>
                <KvRow label="Longest interval" value=fmt_secs(max)/>
            </tbody>
        </table>
    }
    .into_any()
}

fn render_savepoint_warnings(warnings: &[Value]) -> Option<AnyView> {
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

fn render_savepoint_table(sp: &Value) -> Option<AnyView> {
    let savepoints = json_array(sp, "savepoints");
    if savepoints.is_empty() {
        return None;
    }

    // Cap the rendered rows to keep the DOM light on multi-day traces.
    const MAX_ROWS: usize = 200;
    let total = savepoints.len();
    let truncated = total > MAX_ROWS;

    let opt_u64 = |row: &Value, key: &str| -> String {
        row.get(key)
            .and_then(|v| v.as_u64())
            .map(|n| n.to_string())
            .unwrap_or_else(|| "—".to_string())
    };

    let rows = savepoints
        .iter()
        .take(MAX_ROWS)
        .map(|row| {
            let timestamp = json_str(row, "timestamp");
            let kind = {
                let k = json_str(row, "kind");
                let sk = json_str(row, "snapshotKind");
                if sk.is_empty() { k } else { format!("{k} ({sk})") }
            };
            let version = opt_u64(row, "savepointVersion");
            let next = opt_u64(row, "nextSavepointVersion");
            let redo = json_str(row, "restartRedoLogPosition");
            let dropped = opt_u64(row, "droppedVersion");
            view! {
                <tr>
                    <td>{timestamp}</td>
                    <td>{kind}</td>
                    <td>{version}</td>
                    <td>{next}</td>
                    <td><code>{redo}</code></td>
                    <td>{dropped}</td>
                </tr>
            }
        })
        .collect::<Vec<_>>();

    Some(
        view! {
            <details class="content-details">
                <summary>
                    {format!("Savepoint events ({total})")}
                </summary>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>"Timestamp"</th>
                            <th>"Kind"</th>
                            <th>"Version"</th>
                            <th>"Next"</th>
                            <th>"Restart redo log pos"</th>
                            <th>"Dropped"</th>
                        </tr>
                    </thead>
                    <tbody>{rows}</tbody>
                </table>
                {truncated.then(|| view! {
                    <p class="muted">
                        {format!("Showing first {MAX_ROWS} of {total} savepoint events.")}
                    </p>
                })}
            </details>
        }
        .into_any(),
    )
}
