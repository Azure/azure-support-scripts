use leptos::prelude::*;

use crate::worker_bridge::ProgressState;

/// Displays a progress bar with file-count, decompressed size, and current file.
#[component]
pub fn ProgressBar(progress: ReadSignal<ProgressState>) -> impl IntoView {
    let pct = move || {
        let raw = progress.get().percent;
        let scaled = if raw <= 1.0 { raw * 100.0 } else { raw };
        scaled.clamp(0.0, 100.0)
    };
    let pct_text = move || format!("{:.0}%", pct());

    let decompressed = move || {
        let bytes = progress.get().decompressed_bytes;
        format_bytes(bytes)
    };

    let file_count = move || progress.get().file_count;
    let current_file = move || {
        let f = progress.get().current_file.clone();
        if f.is_empty() {
            "Waiting for worker output…".to_string()
        } else {
            // show last path component
            f.rsplit('/').next().unwrap_or(&f).to_string()
        }
    };
    let status_message = move || {
        let msg = progress.get().message.trim().to_string();
        if msg.is_empty() {
            format!("Processing {:.0}%…", pct())
        } else {
            msg
        }
    };

    view! {
        <div class="progress-container" role="status" aria-live="polite">
            <div class="progress-meta">
                <span class="progress-label">"Analysis progress"</span>
                <span class="progress-percent">{pct_text}</span>
            </div>

            <progress class="progress-bar" max="100" value=move || pct().to_string()>
                {pct_text}
            </progress>

            <p class="progress-message">{status_message}</p>

            <div class="progress-stats">
                <span class="progress-stats__files">{move || format!("{} files", file_count())}</span>
                <span class="progress-stats__size">{move || format!("{} decompressed", decompressed())}</span>
                <span class="progress-stats__current" title=current_file.clone()>{current_file}</span>
            </div>
        </div>
    }
}

fn format_bytes(b: f64) -> String {
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
