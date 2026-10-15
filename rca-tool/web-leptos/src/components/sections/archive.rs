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
        </Section>
    }
    .into_any()
}
