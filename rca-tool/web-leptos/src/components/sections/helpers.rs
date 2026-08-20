use leptos::prelude::*;

/// Convenience – collapsible `<details>/<summary>` block.
#[component]
pub fn Section(
    #[prop(into)] title: String,
    #[prop(default = "content-details".into(), into)] class: String,
    #[prop(default = false)] open: bool,
    #[prop(optional, into)] badge: Option<String>,
    children: Children,
) -> impl IntoView {
    view! {
        <details class=class open=open>
            <summary>
                {title.clone()}
                {badge.map(|b| view! { <span class="badge">{b}</span> })}
            </summary>
            <div class="section-body">{children()}</div>
        </details>
    }
}

/// Key → value row inside a two-column table.
#[component]
pub fn KvRow(
    #[prop(into)] label: String,
    #[prop(into)] value: String,
    #[prop(optional, into)] class: Option<String>,
) -> impl IntoView {
    view! {
        <tr class=class.unwrap_or_default()>
            <td class="kv-label">{label}</td>
            <td class="kv-value">{value}</td>
        </tr>
    }
}

/// Wraps children in a nice two-column key-value table.
#[component]
pub fn KvTable(children: Children) -> impl IntoView {
    view! {
        <table class="kv-table">
            <tbody>{children()}</tbody>
        </table>
    }
}

/// Badge helper that picks a class based on severity.
pub fn severity_class(danger_count: usize, warning_count: usize) -> &'static str {
    if danger_count > 0 {
        "danger-block"
    } else if warning_count > 0 {
        "warning-block"
    } else {
        "success-block"
    }
}

/// Format bytes → human string.
pub fn format_bytes(b: f64) -> String {
    if b < 1024.0 {
        format!("{b:.0} B")
    } else if b < 1024.0 * 1024.0 {
        format!("{:.1} KB", b / 1024.0)
    } else if b < 1024.0 * 1024.0 * 1024.0 {
        format!("{:.1} MB", b / (1024.0 * 1024.0))
    } else {
        format!("{:.2} GB", b / (1024.0 * 1024.0 * 1024.0))
    }
}

/// Extract a string from a JSON value, returning "" if missing.
pub fn json_str(v: &serde_json::Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string()
}

/// Extract a bool from a JSON value.
pub fn json_bool(v: &serde_json::Value, key: &str) -> bool {
    v.get(key).and_then(|x| x.as_bool()).unwrap_or(false)
}

/// Extract a u64 from a JSON value (numbers only; defaults to 0).
pub fn json_u64(v: &serde_json::Value, key: &str) -> u64 {
    v.get(key).and_then(|x| x.as_u64()).unwrap_or(0)
}

/// Extract an array from a JSON value or return empty vec.
pub fn json_array(v: &serde_json::Value, key: &str) -> Vec<serde_json::Value> {
    v.get(key)
        .and_then(|x| x.as_array())
        .cloned()
        .unwrap_or_default()
}
