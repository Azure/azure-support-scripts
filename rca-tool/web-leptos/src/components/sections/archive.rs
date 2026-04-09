use leptos::prelude::*;
use serde_json::Value;

use super::helpers::*;

/// Section 17 – Archive Contents (always rendered).
#[component]
pub fn ArchiveSection(data: Value) -> impl IntoView {
    let file_count = data.get("fileCount").and_then(|v| v.as_u64()).unwrap_or(0);
    let directories = data
        .get("directories")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let total_parsed = data
        .get("totalParsed")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let file_types = data.get("fileTypes").cloned().unwrap_or(Value::Null);
    let nested_gzip_total_count = data
        .get("nestedGzipTotalCount")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let nested_gzip_count = data
        .get("nestedGzipCount")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let nested_gzip_compressed_bytes = data
        .get("nestedGzipCompressedBytes")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let nested_gzip_decompressed_bytes = data
        .get("nestedGzipDecompressedBytes")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);

    view! {
        <Section title="Archive Contents" class="content-details">
            <KvTable>
                <KvRow label="Files" value=file_count.to_string()/>
                <KvRow label="Directories" value=directories.to_string()/>
                <KvRow label="Parsed" value=total_parsed.to_string()/>
            </KvTable>
            {(nested_gzip_total_count > 0).then(|| {
                let mut summary = format!(
                    "{} .gz file{} found",
                    nested_gzip_total_count,
                    if nested_gzip_total_count == 1 { "" } else { "s" },
                );
                if nested_gzip_count > 0 {
                    summary.push_str(&format!(" ({} decompressed", nested_gzip_count));
                    if nested_gzip_compressed_bytes > 0.0 && nested_gzip_decompressed_bytes > 0.0 {
                        summary.push_str(&format!(
                            ": {:.1} MB → {:.1} MB",
                            nested_gzip_compressed_bytes / 1024.0 / 1024.0,
                            nested_gzip_decompressed_bytes / 1024.0 / 1024.0,
                        ));
                    }
                    summary.push(')');
                }
                view! {
                    <p>
                        <strong>"Nested Compression:"</strong>
                        {format!(" {}", summary)}
                    </p>
                }
            })}
            {(!file_types.is_null()).then(|| {
                let types = file_types
                    .as_object()
                    .map(|m| {
                        m.iter()
                            .map(|(k, v)| {
                                let count = v.as_u64().unwrap_or(0);
                                view! {
                                    <tr>
                                        <td>{k.clone()}</td>
                                        <td>{count.to_string()}</td>
                                    </tr>
                                }
                            })
                            .collect::<Vec<_>>()
                    })
                    .unwrap_or_default();
                view! {
                    <h3>"File Types"</h3>
                    <table class="data-table">
                        <thead>
                            <tr><th scope="col">"Type"</th><th scope="col">"Count"</th></tr>
                        </thead>
                        <tbody>{types}</tbody>
                    </table>
                }
            })}
        </Section>
    }
    .into_any()
}
