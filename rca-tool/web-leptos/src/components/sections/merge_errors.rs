use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section – SAP HANA delta-merge / optimize-compression failures.
#[component]
pub fn MergeErrorsSection(data: Value) -> impl IntoView {
    let me = data.get("hanaMergeErrors").cloned().unwrap_or(Value::Null);

    if !json_bool(&me, "found") {
        return view! {}.into_any();
    }

    let warnings = json_array(&me, "warnings");
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
        <Section title="SAP HANA Delta-Merge Failures" class=class>
            {render_merge_summary(&me)}
            {render_merge_warnings(&warnings)}
            {render_top_tables(&me)}
            {render_merge_table(&me)}
        </Section>
    }
    .into_any()
}

fn render_merge_summary(me: &Value) -> AnyView {
    let count = json_u64(me, "count");
    let merge = json_u64(me, "mergeErrorCount");
    let compression = json_u64(me, "compressionErrorCount");
    let token = json_u64(me, "tokenExhaustionCount");
    let last = json_str(me, "lastError");

    view! {
        <table class="kv-table">
            <tbody>
                <KvRow label="Total failures" value=count.to_string()/>
                <KvRow label="Delta-merge failures" value=merge.to_string()/>
                <KvRow label="Compression failures" value=compression.to_string()/>
                <KvRow label="Merge-token exhaustion (rc=2465)" value=token.to_string()/>
                <KvRow
                    label="Last failure"
                    value=if last.is_empty() { "—".to_string() } else { last }
                />
            </tbody>
        </table>
    }
    .into_any()
}

fn render_merge_warnings(warnings: &[Value]) -> Option<AnyView> {
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

fn render_top_tables(me: &Value) -> Option<AnyView> {
    let tables = json_array(me, "topTables");
    if tables.is_empty() {
        return None;
    }

    let rows = tables
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
                <summary>"Most frequently failing tables"</summary>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>"Table"</th>
                            <th>"Failures"</th>
                        </tr>
                    </thead>
                    <tbody>{rows}</tbody>
                </table>
            </details>
        }
        .into_any(),
    )
}

fn render_merge_table(me: &Value) -> Option<AnyView> {
    let errors = json_array(me, "errors");
    if errors.is_empty() {
        return None;
    }

    // Cap the rendered rows to keep the DOM light on multi-day traces.
    const MAX_ROWS: usize = 200;
    let total = errors.len();
    let truncated = total > MAX_ROWS;

    let opt_str = |row: &Value, key: &str| -> String {
        let s = json_str(row, key);
        if s.is_empty() { "—".to_string() } else { s }
    };

    let rows = errors
        .iter()
        .take(MAX_ROWS)
        .map(|row| {
            let timestamp = json_str(row, "timestamp");
            let component = opt_str(row, "component");
            let table = opt_str(row, "table");
            let motivation = opt_str(row, "motivation");
            let rc = opt_str(row, "rc");
            view! {
                <tr>
                    <td>{timestamp}</td>
                    <td>{component}</td>
                    <td><code>{table}</code></td>
                    <td>{motivation}</td>
                    <td>{rc}</td>
                </tr>
            }
        })
        .collect::<Vec<_>>();

    Some(
        view! {
            <details class="content-details">
                <summary>
                    {format!("Delta-merge failures ({total})")}
                </summary>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>"Timestamp"</th>
                            <th>"Component"</th>
                            <th>"Table"</th>
                            <th>"Motivation"</th>
                            <th>"rc"</th>
                        </tr>
                    </thead>
                    <tbody>{rows}</tbody>
                </table>
                {truncated.then(|| view! {
                    <p class="muted">
                        {format!("Showing first {MAX_ROWS} of {total} delta-merge failures.")}
                    </p>
                })}
            </details>
        }
        .into_any(),
    )
}
